# Plan: Detect Deleted Workspace - Read-Only Mode

## Overview
When a session's workspace path no longer exists (e.g., the folder was deleted), we need to:
1. Detect this when opening the session
2. Allow viewing session history in **read-only mode**
3. Show a pill notification at the end of chat indicating workspace was deleted
4. Disable the input bar and most controls (except context manager button)
5. Context manager can be opened but all actions are disabled
6. User can still archive session later if desired
7. Filter deleted workspaces from the "recent sessions" list in new session sheet

## Implementation Status

### Already Completed (Phase 1)
- ✅ `Tests/WorkspaceValidationTests.swift` - Unit tests created
- ✅ `Tests/Mocks/MockRPCClient.swift` - Mock RPC client created
- ✅ `Sources/Services/EventStoreManager+Operations.swift` - Added `validateWorkspacePath()` method
- ✅ `Sources/Views/Session/NewSessionFlow.swift` - Added filtering for deleted workspaces in recent sessions
- ✅ All 243 tests passing

### Phase 2: Revised Implementation (Read-Only Mode)

### 2.1 Modify ContentView - Allow Session Selection with Workspace Flag
**File:** `packages/ios-app/Sources/Views/ContentView.swift`

**Changes needed:** Remove the alert-based blocking and instead pass `workspaceDeleted` flag to ChatView.

Current state variables to keep:
```swift
@State private var isValidatingWorkspace = false
```

Remove these state variables (no longer needed):
- `showDeletedWorkspaceAlert`
- `deletedWorkspaceSessionId`
- `deletedWorkspaceSessionName`

Add new state variable to track workspace validity per session:
```swift
@State private var workspaceDeletedForSession: [String: Bool] = [:]
```

Update `onChange(of: selectedSessionId)`:
```swift
.onChange(of: selectedSessionId) { oldValue, newValue in
    guard let id = newValue else { return }

    // Find the session to validate
    guard let session = eventStoreManager.sessions.first(where: { $0.id == id }) else {
        eventStoreManager.setActiveSession(id)
        return
    }

    // Always allow selection, but validate workspace path
    eventStoreManager.setActiveSession(id)

    Task {
        isValidatingWorkspace = true
        let pathExists = await eventStoreManager.validateWorkspacePath(session.workingDirectory)
        isValidatingWorkspace = false
        workspaceDeletedForSession[id] = !pathExists
    }
}
```

Update ChatView instantiation to pass workspace deleted flag (~line 90-94):
```swift
ChatView(
    rpcClient: appState.rpcClient,
    sessionId: sessionId,
    skillStore: appState.skillStore,
    workspaceDeleted: workspaceDeletedForSession[sessionId] ?? false
)
```

Remove the "Workspace Deleted" alert modifier (lines ~165-185).

### 2.2 Modify ChatView - Accept Workspace Deleted Flag
**File:** `packages/ios-app/Sources/Views/ChatView.swift`

Add new parameter:
```swift
let workspaceDeleted: Bool
```

Pass to InputBar (~line 127-149):
```swift
InputBar(
    // ... existing params ...
    readOnly: workspaceDeleted
)
```

Add workspace deleted notification to messages when `workspaceDeleted` is true. This should appear as the last item in the message list.

### 2.3 Modify InputBar - Add Read-Only Mode
**File:** `packages/ios-app/Sources/Views/InputBar/InputBar.swift`

Add new parameter:
```swift
var readOnly: Bool = false
```

Apply `.disabled(isProcessing || readOnly)` to all interactive elements EXCEPT:
- The context manager button (keep enabled)

Show visual indication of read-only mode (e.g., muted colors or "Read-only" label).

### 2.4 Add Workspace Deleted Notification View
**File:** `packages/ios-app/Sources/Views/MessageBubble/NotificationViews.swift`

Add new view following existing patterns:
```swift
/// Notification shown when workspace folder was deleted
struct WorkspaceDeletedNotificationView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tronWarning)
            Text("Workspace folder deleted")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.tronWarning.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.tronWarning.opacity(0.1))
        .clipShape(Capsule())
    }
}
```

### 2.5 Modify ContextAuditView - Add Read-Only Mode
**File:** `packages/ios-app/Sources/Views/ContextAudit/ContextAuditView.swift`

Add new parameter:
```swift
var readOnly: Bool = false
```

When `readOnly` is true:
- Disable "Clear" button in toolbar (top-left)
- Disable "Compact" button in toolbar (top-right)
- Disable context menu actions (delete, etc.) on items
- Can still scroll and view all context items

Apply `.disabled(readOnly)` to:
- Clear button
- Compact button
- Delete handlers on context items

### 2.6 Keep NewSessionFlow Filtering (Already Done)
**File:** `packages/ios-app/Sources/Views/Session/NewSessionFlow.swift`

The filtering of deleted workspaces from recent sessions is already implemented and should remain unchanged.

---

## Files Summary

| File | Status | Purpose |
|------|--------|---------|
| `Tests/WorkspaceValidationTests.swift` | ✅ Done | Unit tests for workspace validation |
| `Tests/Mocks/MockRPCClient.swift` | ✅ Done | Mock for testing |
| `Sources/Services/EventStoreManager+Operations.swift` | ✅ Done | `validateWorkspacePath()` method |
| `Sources/Views/Session/NewSessionFlow.swift` | ✅ Done | Filter deleted workspaces from recent sessions |
| `Sources/Views/ContentView.swift` | **Modify** | Pass `workspaceDeleted` flag to ChatView instead of blocking |
| `Sources/Views/ChatView.swift` | **Modify** | Accept flag, show notification, pass to InputBar |
| `Sources/Views/InputBar/InputBar.swift` | **Modify** | Add `readOnly` parameter |
| `Sources/Views/MessageBubble/NotificationViews.swift` | **Modify** | Add `WorkspaceDeletedNotificationView` |
| `Sources/Views/ContextAudit/ContextAuditView.swift` | **Modify** | Add `readOnly` parameter to disable actions |

---

## Verification

### Run Tests
```bash
cd packages/ios-app
xcodebuild test -scheme TronMobile -destination 'platform=iOS Simulator,name=iPhone 17'
```

### Manual Test Cases

1. **Valid workspace session** - Opens normally, input bar is active
2. **Deleted workspace session (sidebar)** - Opens in read-only mode:
   - Shows pill notification "Workspace folder deleted"
   - Input bar is disabled
   - Context manager button still works
   - Context manager sheet opens but Clear/Compact/Delete disabled
3. **Recent sessions filtering** - Deleted workspace sessions don't appear in new session sheet
4. **Archive later** - User can still archive session via swipe-to-delete in sidebar
5. **Network error handling** - App doesn't crash if server is unavailable
