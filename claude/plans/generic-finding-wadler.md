# Fix Forked Session Message Ordering Bug

## Problem Summary

When forking a session in the iOS app:
1. Initial display shows messages correctly (historical + new)
2. Sending prompts works correctly
3. After navigating to dashboard and returning, messages appear misordered: forked messages interleaved incorrectly with original messages

## Root Cause Analysis

**Event Storage Architecture:**
- Events are stored with `session_id` identifying which session they belong to
- Forked sessions have their OWN `session_id`, different from the parent session
- A fork event's `parentId` points to an event in the PARENT session

**iOS Sync Flow (current - broken):**
1. `fullSyncSession(sessionId)` → `rpcClient.getAllEvents(sessionId)`
2. Server calls `orchestrator.getSessionEvents(sessionId)` → returns only events WHERE session_id = forkedSessionId
3. **Parent session events are NOT included** (they have parent sessionId)
4. iOS stores only forked session events locally
5. When reconstructing via `eventDB.getAncestors(headEventId)`, the chain breaks at fork boundary because parent events don't exist locally

**Why Initial Display Works:**
- `resumeSession` RPC returns messages via `orchestrator.getSessionMessages(sessionId)`
- This uses `getMessagesAtHead()` → `getMessagesAt(eventId)` → `backend.getAncestors(eventId)`
- `getAncestors` correctly walks the parentId chain **across session boundaries**
- So initial display gets correct messages from server

**Why Return Display Fails:**
- After navigating away, iOS reloads from local EventDatabase
- `eventDB.getAncestors(headEventId)` walks parentId chain
- Chain breaks when it reaches a parent event that wasn't stored locally
- Only forked session events are returned, in wrong order

## Solution

**Fix Location:** iOS `EventStoreManager+Sync.swift`

**Approach:** When syncing a forked session, also fetch and store ancestor events using the existing `tree.getAncestors` RPC endpoint.

### Implementation Steps

#### 1. Add `getAncestors` RPC method to iOS `RPCClient.swift`

```swift
// Add to RPCClient.swift
func getAncestors(eventId: String) async throws -> [RawEvent] {
    guard let ws = webSocket else {
        throw RPCClientError.connectionNotEstablished
    }

    struct Params: Codable { let eventId: String }
    struct Result: Codable { let events: [RawEvent] }

    let result: Result = try await ws.send(method: "tree.getAncestors", params: Params(eventId: eventId))
    return result.events
}
```

Also add to `RPCClientProtocol.swift`.

#### 2. Modify `fullSyncSession` in `EventStoreManager+Sync.swift`

After fetching session events, check if session is forked and fetch ancestors:

```swift
func fullSyncSession(_ sessionId: String) async throws {
    logger.info("[FULL-SYNC] Starting full sync for session \(sessionId)", category: .session)

    // Clear existing events
    try eventDB.deleteEventsBySession(sessionId)

    // Fetch all events for this session
    let events = try await rpcClient.getAllEvents(sessionId: sessionId)
    var sessionEvents = events.map { rawEventToSessionEvent($0) }

    // Check if first event has a parentId pointing to another session (fork indicator)
    // If so, fetch and store ancestor events
    if let firstEvent = sessionEvents.first,
       let parentId = firstEvent.parentId,
       !sessionEvents.contains(where: { $0.id == parentId }) {
        logger.info("[FULL-SYNC] Session appears forked, fetching ancestor events from \(parentId)", category: .session)

        let ancestorEvents = try await rpcClient.getAncestors(eventId: parentId)
        let ancestorSessionEvents = ancestorEvents.map { rawEventToSessionEvent($0) }

        // Insert ancestor events (they may belong to parent session)
        let insertedCount = try eventDB.insertEventsIgnoringDuplicates(ancestorSessionEvents)
        logger.info("[FULL-SYNC] Inserted \(insertedCount) ancestor events", category: .session)
    }

    try eventDB.insertEvents(sessionEvents)
    // ... rest of existing logic
}
```

#### 3. Update `syncSessionEvents` for incremental sync

Similar logic for incremental sync - if first synced event references a missing parent, fetch ancestors:

```swift
func syncSessionEvents(sessionId: String) async throws {
    // ... existing sync logic ...

    if !result.events.isEmpty {
        var events = result.events.map { rawEventToSessionEvent($0) }

        // Check if any event references a parent not in local DB
        for event in events {
            if let parentId = event.parentId,
               !(try eventDB.eventExists(parentId)) {
                // Fetch and store ancestors
                logger.info("[SYNC] Event references missing parent \(parentId), fetching ancestors", category: .session)
                let ancestorEvents = try await rpcClient.getAncestors(eventId: parentId)
                let ancestorSessionEvents = ancestorEvents.map { rawEventToSessionEvent($0) }
                let insertedCount = try eventDB.insertEventsIgnoringDuplicates(ancestorSessionEvents)
                logger.info("[SYNC] Inserted \(insertedCount) ancestor events", category: .session)
                break // Only need to fetch ancestors once
            }
        }

        // ... rest of existing logic ...
    }
}
```

### Files to Modify

| File | Change |
|------|--------|
| `packages/ios-app/Sources/Services/RPCClient.swift` | Add `getAncestors(eventId:)` method |
| `packages/ios-app/Sources/Protocols/RPCClientProtocol.swift` | Add protocol method |
| `packages/ios-app/Sources/Services/EventStoreManager+Sync.swift` | Fetch ancestors for forked sessions |

### Test Cases to Add

#### 1. Unit Test: Forked Session Event Sync

```swift
func testForkedSessionSyncIncludesAncestors() async throws {
    // Setup: Create parent session with events
    // Fork the session
    // Sync the forked session
    // Verify: Parent events are stored locally
    // Verify: getAncestors returns complete chain
}
```

#### 2. Unit Test: Incremental Sync with Missing Ancestors

```swift
func testIncrementalSyncFetchesMissingAncestors() async throws {
    // Setup: Forked session with local events
    // Clear ancestor events to simulate missing parents
    // Trigger incremental sync
    // Verify: Ancestors are refetched and stored
}
```

#### 3. Integration Test: Message Reconstruction After Navigation

```swift
func testMessageOrderAfterNavigatingAwayAndBack() async throws {
    // Setup: Fork session, add messages
    // Navigate away (clear in-memory state)
    // Navigate back, reload from local DB
    // Verify: Messages in correct chronological order
}
```

## Verification

1. **Build & Test**
   ```bash
   cd packages/ios-app && xcodebuild test -scheme Tron -destination 'platform=iOS Simulator,name=iPhone 15'
   ```

2. **Manual Test**
   - Fork a session with history
   - Send a few messages in forked session
   - Navigate to dashboard
   - Return to forked session
   - Verify messages are in correct order

3. **Run existing tests**
   ```bash
   bun run build && bun run test
   ```

## Alternative Considered

**Server-side fix**: Modify `events.getHistory` to include ancestors for forked sessions.
- Rejected because: Would change API behavior for all clients, could cause duplicate events in responses, more invasive change.

The iOS-side fix is more targeted and only affects the sync flow for forked sessions.
