# Fix iOS Swipe-to-Archive Animation Glitch

## Problem

When swiping left on a session card and tapping "Archive", the card glitches - other cards jump up momentarily then restore - instead of smoothly animating out.

## Root Cause

In `EventStoreManager+Operations.swift:64`, `deleteSession()` calls `loadSessions()` which replaces the entire `@Published sessions` array:

```swift
func deleteSession(_ sessionId: String) async throws {
    try eventDB.deleteSession(sessionId)
    try eventDB.deleteEventsBySession(sessionId)
    // ...
    loadSessions()  // <-- PROBLEM: Replaces entire array (line 64)
}
```

When a `@Published` array is **replaced** (not mutated), SwiftUI treats it as a complete data structure change and re-renders all items, causing the visual "jump" glitch.

## Solution

Use **optimistic local removal** - remove the session from the local array first (triggering smooth SwiftUI animation), then persist to database. If persistence fails, restore the session.

## Current Architecture (Post-Refactor)

The recent refactor (commit `78bccdd`) split the monolithic EventStoreManager into focused components:

| File | Purpose |
|------|---------|
| `EventStoreManager.swift` | Core state: `@Published sessions`, helper setters |
| `EventStoreManager+Operations.swift` | CRUD operations: `deleteSession()`, `archiveAllSessions()` |
| `EventStoreManager+Dashboard.swift` | Dashboard info extraction, processing state |
| `EventStoreManager+Sync.swift` | Server sync (delegates to `SessionSynchronizer`) |
| `EventStoreManagerProtocol.swift` | Split into 3 protocols: `SessionStoreProtocol`, `SessionSyncProtocol`, `DashboardPollingProtocol` |

## Files to Modify

| File | Changes |
|------|---------|
| `packages/ios-app/Sources/Services/EventStoreManager.swift` | Add `removeSessionLocally()` and `insertSessionLocally()` helpers (after line 204) |
| `packages/ios-app/Sources/Services/EventStoreManager+Operations.swift` | Update `deleteSession()` (lines 46-66) and `archiveAllSessions()` (lines 68-97) to use optimistic updates |
| `packages/ios-app/Sources/Protocols/EventStoreManagerProtocol.swift` | Add protocol declarations to `SessionStoreProtocol` (after line 32) |

## Implementation

### 1. Add helper methods to `EventStoreManager.swift` (after line 204, after `setActiveSessionId`)

```swift
/// Remove a session from the local array by ID (for optimistic UI updates)
/// Returns the removed session and its index for potential rollback
func removeSessionLocally(_ sessionId: String) -> (session: CachedSession, index: Int)? {
    guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
        return nil
    }
    let session = sessions[index]
    sessions.remove(at: index)
    return (session, index)
}

/// Insert a session back into the local array at a specific index (for rollback)
func insertSessionLocally(_ session: CachedSession, at index: Int) {
    let clampedIndex = min(index, sessions.count)
    sessions.insert(session, at: clampedIndex)
}
```

### 2. Update `deleteSession()` in `EventStoreManager+Operations.swift` (replace lines 46-66)

```swift
/// Delete a session (local + server)
/// Uses optimistic UI update: removes from local array first, then persists
func deleteSession(_ sessionId: String) async throws {
    // 1. Optimistically remove from local array (triggers smooth List animation)
    let removed = removeSessionLocally(sessionId)

    // 2. If this was the active session, update immediately
    let wasActiveSession = activeSessionId == sessionId
    if wasActiveSession {
        setActiveSession(sessions.first?.id)
    }

    // 3. Attempt database deletion
    do {
        try eventDB.deleteSession(sessionId)
        try eventDB.deleteEventsBySession(sessionId)
    } catch {
        // Rollback: restore the session to local array
        if let (session, index) = removed {
            insertSessionLocally(session, at: index)
            if wasActiveSession {
                setActiveSession(sessionId)
            }
        }
        logger.error("Failed to delete session from database: \(error.localizedDescription)", category: .session)
        throw error
    }

    // 4. Try to delete from server (optional, don't rollback on failure)
    do {
        _ = try await rpcClient.deleteSession(sessionId)
    } catch {
        logger.warning("Server delete failed (continuing): \(error.localizedDescription)", category: .session)
    }

    // 5. DON'T call loadSessions() - the local array is already correct
    logger.info("Deleted session: \(sessionId)", category: .session)
}
```

### 3. Update `archiveAllSessions()` in `EventStoreManager+Operations.swift` (replace lines 68-97)

```swift
/// Archive all sessions (delete locally, optionally notify server)
func archiveAllSessions() async {
    let sessionsToArchive = sessions

    guard !sessionsToArchive.isEmpty else {
        logger.info("No sessions to archive", category: .session)
        return
    }

    logger.info("Archiving \(sessionsToArchive.count) sessions...", category: .session)

    // Clear local array first (optimistic, all at once for smooth animation)
    clearSessions()
    setActiveSession(nil)

    // Then persist deletions
    for session in sessionsToArchive {
        do {
            try eventDB.deleteSession(session.id)
            try eventDB.deleteEventsBySession(session.id)

            do {
                _ = try await rpcClient.deleteSession(session.id)
            } catch {
                logger.warning("Server delete failed for \(session.id) (continuing): \(error.localizedDescription)", category: .session)
            }
        } catch {
            logger.error("Failed to archive session \(session.id): \(error.localizedDescription)", category: .session)
        }
    }

    // DON'T call loadSessions() - array is already cleared
    logger.info("Archived \(sessionsToArchive.count) sessions", category: .session)
}
```

### 4. Add protocol declarations to `SessionStoreProtocol` in `EventStoreManagerProtocol.swift` (after line 32)

```swift
func removeSessionLocally(_ sessionId: String) -> (session: CachedSession, index: Int)?
func insertSessionLocally(_ session: CachedSession, at index: Int)
```

## Why This Works

1. **Smooth animation**: Mutating the array (removing one item via `sessions.remove(at:)`) triggers SwiftUI's diff-based List updates - the List knows exactly which cell to animate out

2. **No glitch**: Other cards don't jump because only the specific item is removed, not the entire data source replaced

3. **Error resilience**: If database deletion fails, the session is restored to its original position

4. **Maintains consistency**: On success, array matches database; on failure, both are unchanged

5. **Thread safety**: `EventStoreManager` is `@MainActor`, so all operations are serialized on the main thread

## Verification

1. Build the project:
   ```bash
   bun run build && bun run test
   ```

2. Build iOS app in Xcode (`packages/ios-app/TronMobile.xcodeproj`)

3. Test swipe-to-archive on a session:
   - Session card should smoothly animate out
   - Other cards should smoothly shift up (no jumping/glitching)
   - Verify session is actually deleted (doesn't reappear on app restart)

4. Test "Archive All Sessions" from settings menu

5. Test error handling: temporarily make `eventDB.deleteSession` fail to verify rollback works
