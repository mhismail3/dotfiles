# iOS App Performance & Efficiency Improvements

## Executive Summary

The Tron iOS app has a well-architected foundation with good memory management (weak self captures throughout, proper cancellation). However, there are significant opportunities to reduce battery drain and improve responsiveness, particularly around **caching**, **polling optimization**, and **frame streaming**.

---

## Stack-Ranked Improvements

### TIER 1: CRITICAL (High Impact, Zero Regression Risk)

#### 1. Add Client-Side Model List Cache
**Impact**: High | **Risk**: None | **Battery Savings**: Moderate

**Problem**: `listModels()` is called fresh on every view that needs model data:
- `ModelSwitcher.swift` - on appear + background refresh
- `ChatView.swift` - `prefetchModels()`
- `NewSessionFlow.swift` - model picker population

**Files to modify**:
- `packages/ios-app/Sources/Services/RPCClient.swift`

**Solution**: Add 5-minute TTL cache for model list:
```swift
private var modelCache: [Model]?
private var modelCacheTime: Date?
private let modelCacheTTL: TimeInterval = 300 // 5 minutes

func listModels(forceRefresh: Bool = false) async throws -> [Model] {
    if !forceRefresh, let cached = modelCache,
       let time = modelCacheTime, Date().timeIntervalSince(time) < modelCacheTTL {
        return cached
    }
    let models = try await _listModels()
    modelCache = models
    modelCacheTime = Date()
    return models
}
```

---

#### 2. Stop Dashboard Polling Completely When Backgrounded
**Impact**: High | **Risk**: None | **Battery Savings**: High

**Problem**: Dashboard polling continues at 5-second intervals even when app is backgrounded:
```swift
if self?.isInBackground == true {
    try? await Task.sleep(for: .seconds(5))  // Still wakes CPU every 5s!
    continue
}
```

**File to modify**:
- `packages/ios-app/Sources/Services/EventStoreManager+Dashboard.swift`

**Solution**: Use a continuation-based approach that truly suspends:
```swift
while !Task.isCancelled {
    if self?.isInBackground == true {
        await withCheckedContinuation { continuation in
            self?.backgroundResumeContinuation = continuation
        }
        // Resumed when foregrounded
    }
    await self?.pollAllSessionStates()
    // ... rest of loop
}
```

Or simpler: cancel polling task on background, restart on foreground.

---

#### 3. Add Browser Frame Skipping/Throttling
**Impact**: High | **Risk**: None | **Battery Savings**: Very High

**Problem**: Browser streaming requests every frame at ~10 FPS:
```swift
let params = BrowserStartStreamParams(
    everyNthFrame: 1  // Gets EVERY frame
)
```

**File to modify**:
- `packages/ios-app/Sources/ViewModels/ChatViewModel.swift` - `handleBrowserFrame()`

**Solution**:
1. Increase `everyNthFrame` to 2-3 (reduces to 3-5 FPS, still smooth)
2. Add frame dropping during UI lag (skip frame if previous still decoding)
3. Make quality adaptive based on frame decode time

---

#### 4. SkillStore Already Has Refresh Logic (Low Priority)
**Impact**: Low | **Risk**: None | **Status**: Already partially addressed

**Finding**: `SkillStore` already has a 30-second refresh interval with `needsRefresh()` and `refreshIfNeeded()` logic (lines 149-168). However, `loadSkills()` still makes a network call to the server's cache on every call.

**Potential optimization**: Add client-side TTL cache similar to model cache, so repeated calls within 30s don't even hit the server cache endpoint. Currently the server does the caching, but the client still makes the RPC call.

---

### TIER 2: HIGH PRIORITY (Moderate Impact, Low Risk)

#### 5. Batch Agent State Polling Requests
**Impact**: Medium | **Risk**: Low | **Battery Savings**: Moderate

**Problem**: Each processing session triggers separate `getAgentStateForSession()` calls every 2 seconds.

**File to modify**:
- `packages/ios-app/Sources/Services/EventStoreManager+Dashboard.swift`

**Solution**: Add batch endpoint or coalesce requests:
```swift
// Instead of 5 separate calls for 5 sessions:
let states = try await rpcClient.getAgentStatesForSessions(sessionIds)
```

---

#### 6. Implement SubagentState Memory Limits
**Impact**: Medium | **Risk**: Low | **Prevents**: Memory exhaustion

**Problem**: `SubagentState` stores all forwarded events indefinitely:
```swift
subagentEvents: [String: [SubagentEventItem]]  // Unbounded growth!
```

**File to modify**:
- `packages/ios-app/Sources/ViewModels/State/SubagentState.swift`

**Solution**: Add max event count per subagent (e.g., 500 events), evict oldest.

---

#### 7. Eliminate Double Event Deserialization on Session Entry
**Impact**: Medium | **Risk**: Low | **CPU Savings**: Moderate

**Problem**: Session initialization path:
1. `connectAndResume()` calls `checkAndResumeAgentState()`
2. Then `syncAndLoadMessages()` calls `getReconstructedState()`
3. Both deserialize the same event data

**Files to investigate**:
- `packages/ios-app/Sources/ViewModels/ChatViewModel+Connection.swift`
- `packages/ios-app/Sources/ViewModels/ChatViewModel+Pagination.swift`

**Solution**: Unify into single state reconstruction call.

---

### TIER 3: MEDIUM PRIORITY (Optimization Opportunities)

#### 8. Incremental Message Loading (Not Full Reload)
**Impact**: Medium | **Risk**: Medium | **UX Improvement**: Faster session switching

**Problem**: When new events sync, entire message list is rebuilt:
```swift
if newEvents > 0 {
    messages = getReconstructedState()  // Full rebuild!
}
```

**Solution**: Apply delta updates instead of full reconstruction.

---

#### 9. Add Request Deduplication
**Impact**: Low-Medium | **Risk**: Low

**Problem**: Concurrent calls for same data (e.g., two views loading models simultaneously).

**Solution**: Track in-flight requests, return same promise for duplicate requests.

---

#### 10. Turn Content Cache TTL Tuning
**Impact**: Low | **Risk**: Low

**Current**: 2-minute TTL, max 10 sessions cached.

**Consideration**: For long sessions, 2 minutes may cause re-fetches. Consider extending to 5 minutes.

---

### TIER 4: DEFERRED (Larger Refactors)

#### 11. Break Up Large View Files
- `SessionTreeView.swift` (2,000 lines)
- `UnifiedEventTransformer.swift` (2,112 lines)

These affect maintainability more than runtime performance. Defer unless profiling shows layout issues.

#### 12. Add UnifiedEventTransformer Memoization
Cache transformation results keyed by event set hash.

#### 13. WebSocket Background Disconnect
Currently stays connected in background (intentional for real-time events). Consider explicit disconnect if battery critical mode.

---

## Background Process Assessment (No Action Needed)

The exploration found these are **already well-managed**:

| Process | Status | Notes |
|---------|--------|-------|
| WebSocket Heartbeat | Good | Pauses in background |
| Audio Availability Monitor | Good | Only polls when foreground |
| Voice Recording Timers | Excellent | Only during recording, properly invalidated |
| StreamingManager Batching | Excellent | Self-cancelling, 10MB backpressure limit |
| UIUpdateQueue | Good | 16ms batching prevents excessive redraws |
| Combine Subscriptions | Excellent | All weak self, stored in cancellables |

---

## Verification Plan

1. **Model Cache**: Add unit test verifying cache hit on second call within TTL
2. **Dashboard Polling**: Instrument with logging, verify no polls when backgrounded
3. **Browser Frames**: Add frame skip counter, verify reduced bandwidth in profiler
4. **Memory Limits**: Load test with 100+ subagent events, verify cap enforced
5. **Overall**: Profile with Instruments (Energy Log) before/after changes

---

## Files to Modify (Summary)

| Priority | File | Change |
|----------|------|--------|
| P1 | `Sources/Services/RPCClient.swift` | Add model cache (lines 631-642) |
| P1 | `Sources/Services/EventStoreManager+Dashboard.swift` | Stop polling in background (lines 67-70) |
| P1 | `Sources/Services/RPCClient.swift` | Frame skipping (line 1040: `everyNthFrame: 1` → `everyNthFrame: 2-3`) |
| P2 | `Sources/ViewModels/State/SubagentState.swift` | Memory limits on `subagentEvents` dict (line 58) |
| P2 | `Sources/ViewModels/ChatViewModel+Connection.swift` | Dedupe state loading |

---

## AI Code Review (Codex Changes)

After reviewing the codebase, **no obvious AI-generated slop was found**:
- Comments are legitimate and helpful (PERFORMANCE, NOTE markers explain actual optimizations)
- Defensive checks are appropriate (race condition guards in RPCClient.connect())
- Code style is consistent throughout
- No unnecessary try/catch blocks or type escapes

The performance comments found (e.g., "PERFORMANCE OPTIMIZATION: Load cached messages first") reflect genuine optimizations that were intentionally added.

---

## Key Code Locations Verified

1. **Dashboard polling continues in background** - `EventStoreManager+Dashboard.swift:67-70`:
   ```swift
   if self?.isInBackground == true {
       try? await Task.sleep(for: .seconds(5))  // Wakes CPU every 5s!
       continue
   }
   ```

2. **No model caching** - `RPCClient.swift:631-642`:
   ```swift
   func listModels() async throws -> [ModelInfo] {
       // Direct server call every time, no cache
       return try await ws.send(method: "model.list", params: EmptyParams())
   }
   ```

3. **Browser frames at full rate** - `RPCClient.swift:1040`:
   ```swift
   everyNthFrame: 1  // Gets EVERY frame
   ```

4. **Unbounded subagent events** - `SubagentState.swift:58`:
   ```swift
   private(set) var subagentEvents: [String: [SubagentEventItem]] = [:]
   // No limit on event count per subagent
   ```
