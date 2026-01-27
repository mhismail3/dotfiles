# EventStoreManager Refactoring Plan

## Goal
Break up the 1,412 LOC EventStoreManager into modular, testable components with zero regressions.

---

## Current State

### File Structure (1,412 LOC total)
```
EventStoreManager.swift                329 LOC  (main class, @Observable state, init)
├── EventStoreManager+Sync.swift       331 LOC  (server sync operations)
├── EventStoreManager+Operations.swift 333 LOC  (session CRUD, fork, lifecycle)
├── EventStoreManager+Dashboard.swift  276 LOC  (polling, processing state, pre-warm)
└── EventStoreManager+Cache.swift      143 LOC  (turn content caching with TTL)
```

### Responsibilities (8+ distinct concerns)
1. **Session State** - `sessions` array, `processingSessionIds` set
2. **Database Access** - Wrapper around EventDatabase operations
3. **Server Sync** - fullSync, syncSessionEvents, fetchServerEvents
4. **Dashboard Polling** - Background polling with adaptive intervals
5. **Processing State** - Track which sessions have active agents
6. **Connection Pre-warming** - WebSocket warm-up for fast session entry
7. **Background State** - Pause/resume when app enters background
8. **Turn Content Caching** - TTL-based cache for enriching events

---

## Problems

### 1. Too Many Responsibilities
EventStoreManager violates single responsibility principle with 8+ distinct concerns. This makes it:
- Hard to test individual behaviors in isolation
- Difficult to reason about state changes
- Prone to bugs when modifying one area affecting another

### 2. Duplicated Content Extraction
`extractTextFromContent()` and `extractDashboardInfoFromEvents()` duplicate patterns already solved in UnifiedEventTransformer:

```swift
// In +Dashboard.swift (lines 244-275)
func extractTextFromContent(_ content: Any?) -> String {
    // 30 lines of content block parsing
}

// In +Dashboard.swift (lines 184-241)
func extractDashboardInfoFromEvents(sessionId: String) {
    // 57 lines parsing event payloads for text/tool blocks
}
```

### 3. Complex Polling Logic
Dashboard polling has multiple interleaved concerns:
- Adaptive intervals (2s processing, 10s idle)
- Background suspension with continuation
- Connection pre-warming
- Session state checking

### 4. State Sprawl
Multiple state properties with unclear ownership:
```swift
@Observable class EventStoreManager {
    var sessions: [DashboardSession] = []
    var processingSessionIds: Set<String> = []
    var turnContentCache: [String: (messages: [[String: Any]], timestamp: Date)] = [:]
    private var isPollingActive = false
    private var isInBackground = false
    private var pollingTask: Task<Void, Never>?
}
```

### 5. Tight Protocol Coupling
`EventStoreManagerProtocol` has 20+ methods, making it hard to mock for testing.

---

## Target Architecture

```
Services/
├── EventStoreManager.swift              (~200 LOC - thin coordinator)
├── EventStoreManager+Operations.swift   (~250 LOC - session CRUD, mostly unchanged)
│
├── Polling/                             # NEW - extracted from +Dashboard
│   ├── DashboardPoller.swift            (~120 LOC) - polling loop + background state
│   └── SessionStateChecker.swift        (~80 LOC) - check individual session states
│
├── Sync/                                # NEW - extracted from +Sync
│   └── SessionSynchronizer.swift        (~200 LOC) - all server sync operations
│
├── Cache/                               # NEW - extracted from +Cache
│   └── TurnContentCache.swift           (~100 LOC) - TTL cache with enrichment
│
└── Utilities/                           # Reuse existing
    └── ContentExtractor.swift           (~50 LOC) - text extraction (or reuse transformer)
```

**Estimated: 1,412 → ~1,000 LOC in EventStoreManager** (30% reduction + better organization)

---

## Implementation Phases

### Phase 1: Add Characterization Tests
**Goal**: Ensure coverage before changes.

1. Review existing test coverage for EventStoreManager
2. Add tests for critical paths:
   - `syncSessionEvents` - server sync flow
   - `setSessionProcessing` - processing state updates
   - `cacheTurnContent` / `getCachedTurnContent` - cache TTL behavior
   - `extractDashboardInfoFromEvents` - content extraction
3. Run tests - establish baseline

**Deliverables**:
- [ ] Test coverage for sync operations
- [ ] Test coverage for cache TTL behavior
- [ ] Baseline passing

---

### Phase 2: Extract TurnContentCache
**Goal**: Isolate caching logic with clear TTL semantics.

**Current** (in +Cache.swift):
```swift
var turnContentCache: [String: (messages: [[String: Any]], timestamp: Date)] = [:]
let cacheExpiry: TimeInterval = 60
let maxCachedSessions = 10

func cacheTurnContent(sessionId: String, turnNumber: Int, messages: [[String: Any]])
func getCachedTurnContent(sessionId: String) -> [[String: Any]]?
func clearCachedTurnContent(sessionId: String)
func cleanExpiredCacheEntries()
func enrichEventsWithCachedContent(events: [SessionEvent], sessionId: String) throws -> [SessionEvent]
func checkForToolBlocks(in payload: [String: AnyCodable]) -> Bool
```

**Extract to**:
```swift
/// TTL-based cache for turn content used to enrich server events
final class TurnContentCache {
    private var cache: [String: CacheEntry] = []
    private let expiry: TimeInterval
    private let maxEntries: Int

    struct CacheEntry {
        let messages: [[String: Any]]
        let timestamp: Date
    }

    func store(sessionId: String, messages: [[String: Any]])
    func get(sessionId: String) -> [[String: Any]]?
    func clear(sessionId: String)
    func cleanExpired()
    func enrichEvents(_ events: [SessionEvent], sessionId: String) -> [SessionEvent]
}
```

**Files to modify**:
- Create `Services/Cache/TurnContentCache.swift`
- Update `EventStoreManager.swift` to own a `TurnContentCache` instance
- Remove caching code from `+Cache.swift` extension (delete file)

**Deliverables**:
- [ ] `TurnContentCache.swift` created (~100 LOC)
- [ ] Cache logic isolated with clear API
- [ ] `+Cache.swift` deleted
- [ ] Tests pass

---

### Phase 3: Extract DashboardPoller
**Goal**: Isolate polling loop and background state management.

**Current** (in +Dashboard.swift lines 36-116):
```swift
private static var backgroundResumeContinuation: CheckedContinuation<Void, Never>?

func setBackgroundState(_ inBackground: Bool)
func startDashboardPolling()
func stopDashboardPolling()
func preWarmConnection() async
```

**Extract to**:
```swift
/// Manages dashboard polling lifecycle with background suspension
final class DashboardPoller {
    private var pollingTask: Task<Void, Never>?
    private var isActive = false
    private var isInBackground = false
    private var backgroundContinuation: CheckedContinuation<Void, Never>?

    /// Delegate for polling actions
    weak var delegate: DashboardPollerDelegate?

    func start()
    func stop()
    func setBackgroundState(_ inBackground: Bool)
}

protocol DashboardPollerDelegate: AnyObject {
    func pollerShouldPreWarm() async
    func pollerShouldPollSessions() async
    func pollerHasProcessingSessions() -> Bool
}
```

**Files to modify**:
- Create `Services/Polling/DashboardPoller.swift`
- Update `EventStoreManager.swift` to own `DashboardPoller` and implement delegate
- Simplify `+Dashboard.swift` to just session state methods

**Deliverables**:
- [ ] `DashboardPoller.swift` created (~120 LOC)
- [ ] Polling loop isolated from session state logic
- [ ] Background suspension cleanly encapsulated
- [ ] Tests pass

---

### Phase 4: Extract SessionStateChecker
**Goal**: Isolate session processing state checking logic.

**Current** (in +Dashboard.swift lines 118-159):
```swift
func pollAllSessionStates() async
func checkSessionProcessingState(sessionId: String) async
```

**Extract to**:
```swift
/// Checks session processing states from server
final class SessionStateChecker {
    private let rpcClient: RPCClientProtocol

    init(rpcClient: RPCClientProtocol)

    /// Check if a session's agent is currently running
    func checkProcessingState(sessionId: String) async throws -> Bool

    /// Batch check multiple sessions
    func checkProcessingStates(sessionIds: [String]) async -> [String: Bool]
}
```

**Files to modify**:
- Create `Services/Polling/SessionStateChecker.swift`
- Update `EventStoreManager+Dashboard.swift` to use SessionStateChecker
- EventStoreManager owns SessionStateChecker instance

**Deliverables**:
- [ ] `SessionStateChecker.swift` created (~80 LOC)
- [ ] State checking isolated from polling loop
- [ ] Tests pass

---

### Phase 5: Extract SessionSynchronizer
**Goal**: Consolidate all server sync operations.

**Current** (in +Sync.swift):
```swift
func fullSync() async throws
func syncSessionEvents(sessionId: String) async throws
func fullSyncSession(sessionId: String) async throws
func fetchServerEvents(sessionId: String) async throws -> [SessionEvent]
func mergeServerEvents(_ events: [SessionEvent], sessionId: String) throws -> Int
```

**Extract to**:
```swift
/// Handles synchronization of session events with the server
final class SessionSynchronizer {
    private let rpcClient: RPCClientProtocol
    private let eventDB: EventDatabase
    private let cache: TurnContentCache

    init(rpcClient: RPCClientProtocol, eventDB: EventDatabase, cache: TurnContentCache)

    /// Sync all sessions from server
    func syncAll() async throws -> SyncResult

    /// Sync events for a specific session
    func syncSession(_ sessionId: String) async throws -> SyncResult

    /// Full sync including session list refresh
    func fullSyncSession(_ sessionId: String) async throws

    struct SyncResult {
        let newEventCount: Int
        let sessionId: String?
    }
}
```

**Files to modify**:
- Create `Services/Sync/SessionSynchronizer.swift`
- Update `EventStoreManager.swift` to own SessionSynchronizer
- Simplify `+Sync.swift` to delegate to SessionSynchronizer

**Deliverables**:
- [ ] `SessionSynchronizer.swift` created (~200 LOC)
- [ ] Sync logic isolated from state management
- [ ] Cache integration clean (enrichment happens in sync)
- [ ] Tests pass

---

### Phase 6: Extract ContentExtractor Utility
**Goal**: Eliminate duplicated content extraction patterns.

**Current** (in +Dashboard.swift lines 184-275):
```swift
func extractDashboardInfoFromEvents(sessionId: String)
func extractTextFromContent(_ content: Any?) -> String
```

These duplicate patterns in UnifiedEventTransformer.

**Options**:
1. **Reuse UnifiedEventTransformer** - If it already has these methods, just call them
2. **Create shared utility** - If transformer is too heavy, extract to lightweight utility

**Check first**: Does UnifiedEventTransformer have text extraction we can reuse?

**If extraction needed**:
```swift
/// Extracts text and metadata from event content blocks
enum ContentExtractor {
    static func extractText(from content: Any?) -> String
    static func extractToolCount(from content: Any?) -> Int
    static func extractDashboardInfo(from events: [SessionEvent]) -> DashboardInfo

    struct DashboardInfo {
        let lastUserPrompt: String?
        let lastAssistantResponse: String?
        let lastToolCount: Int?
    }
}
```

**Files to modify**:
- Create `Services/Utilities/ContentExtractor.swift` OR reuse existing
- Update `+Dashboard.swift` to use extracted utility
- Remove duplicated extraction code

**Deliverables**:
- [ ] Content extraction consolidated
- [ ] No duplicated parsing logic
- [ ] Tests pass

---

### Phase 7: Simplify EventStoreManager Core
**Goal**: Reduce main class to thin coordinator.

After phases 2-6, EventStoreManager should be:
- **State holder**: `sessions`, `processingSessionIds`
- **Coordinator**: Owns extracted components, delegates to them
- **Protocol conformance**: Implement simplified protocol

**Remaining in EventStoreManager.swift**:
```swift
@Observable
@MainActor
final class EventStoreManager: EventStoreManagerProtocol {
    // State
    private(set) var sessions: [DashboardSession] = []
    private(set) var processingSessionIds: Set<String> = []

    // Components
    private let synchronizer: SessionSynchronizer
    private let poller: DashboardPoller
    private let stateChecker: SessionStateChecker
    private let cache: TurnContentCache

    // Dependencies
    let eventDB: EventDatabase
    let rpcClient: RPCClientProtocol

    // Thin delegation methods...
}
```

**Deliverables**:
- [ ] EventStoreManager.swift reduced to ~200 LOC
- [ ] Clear component ownership
- [ ] Tests pass

---

### Phase 8: Simplify Protocol
**Goal**: Break up monolithic protocol into focused protocols.

**Current**: `EventStoreManagerProtocol` with 20+ methods

**Target**:
```swift
protocol SessionStoreProtocol {
    var sessions: [DashboardSession] { get }
    func getSession(_ sessionId: String) -> DashboardSession?
    func createSession(...) async throws -> DashboardSession
    func deleteSession(_ sessionId: String) async throws
    func forkSession(...) async throws -> DashboardSession
}

protocol SessionSyncProtocol {
    func syncSessionEvents(sessionId: String) async throws
    func fullSync() async throws
}

protocol DashboardPollingProtocol {
    func startDashboardPolling()
    func stopDashboardPolling()
    func setBackgroundState(_ inBackground: Bool)
}

// EventStoreManager conforms to all three
```

**Files to modify**:
- Update `EventStoreManagerProtocol.swift` with focused protocols
- Update conformances

**Deliverables**:
- [ ] Protocol split into 3 focused protocols
- [ ] Easier to mock for testing
- [ ] Tests pass

---

### Phase 9: Cleanup & Documentation
**Goal**: Final polish.

1. Add documentation comments to new components
2. Remove any dead code from original extensions
3. Verify no backward compatibility issues
4. Run full test suite
5. Manual smoke test on device

**Deliverables**:
- [ ] Documentation complete
- [ ] All tests pass
- [ ] Manual verification

---

## Files to Create

| File | LOC | Purpose |
|------|-----|---------|
| `Services/Cache/TurnContentCache.swift` | ~100 | TTL-based turn content caching |
| `Services/Polling/DashboardPoller.swift` | ~120 | Polling loop + background state |
| `Services/Polling/SessionStateChecker.swift` | ~80 | Check session processing states |
| `Services/Sync/SessionSynchronizer.swift` | ~200 | Server sync operations |
| `Services/Utilities/ContentExtractor.swift` | ~50 | Text extraction (if needed) |

**Total new: ~550 LOC**

## Files to Modify

| File | Before | After | Change |
|------|--------|-------|--------|
| `EventStoreManager.swift` | 329 | ~200 | -129 LOC |
| `EventStoreManager+Sync.swift` | 331 | ~100 | -231 LOC (delegates to Synchronizer) |
| `EventStoreManager+Dashboard.swift` | 276 | ~100 | -176 LOC (delegates to Poller/Checker) |
| `EventStoreManager+Cache.swift` | 143 | 0 | DELETE (moved to TurnContentCache) |
| `EventStoreManager+Operations.swift` | 333 | ~300 | -33 LOC (minor cleanup) |

**Net change**: 1,412 → ~1,250 LOC (12% reduction) + significantly better organization

---

## Verification

### After Each Phase
```bash
xcodebuild -scheme TronMobile -configuration Debug build
xcodebuild test -scheme TronMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TronMobileTests
```

### Critical Tests
- Session sync (new events merged correctly)
- Cache TTL (expired entries cleaned)
- Polling (starts/stops correctly, background suspension)
- Processing state (updates propagate to UI)

### Manual Testing
1. Open dashboard - verify sessions load
2. Enter session with active agent - verify processing indicator
3. Background app - verify polling suspends
4. Foreground app - verify polling resumes
5. Fork session - verify new session created
6. Delete session - verify removed from list

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Breaking session sync | Characterization tests before changes |
| Cache behavior changes | Test TTL edge cases explicitly |
| Polling timing changes | Keep same intervals, just restructure |
| Protocol changes break callers | Update all conformances in same PR |

---

## Dependencies

- **TurnContentCache**: No dependencies on other new components
- **SessionStateChecker**: Depends on RPCClient only
- **DashboardPoller**: Depends on SessionStateChecker (via delegate)
- **SessionSynchronizer**: Depends on TurnContentCache, EventDatabase, RPCClient

**Recommended order**: Cache → StateChecker → Poller → Synchronizer → Core cleanup
