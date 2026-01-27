# Plan: Add "Archive All Sessions" Button to iOS Settings

## Summary
Add an "Archive all sessions" button at the bottom of the Settings sheet that shows a native iOS 26 confirmation dialog, then archives (deletes locally) all sessions from the dashboard.

## Files to Modify

### 1. `packages/ios-app/Sources/Views/SettingsView.swift`

**Add environment object** (after line 13):
```swift
@EnvironmentObject var eventStoreManager: EventStoreManager
```

**Add state** (after line 20):
```swift
@State private var showArchiveAllConfirmation = false
@State private var isArchivingAll = false
```

**Add new "Data" section** before the Footer section (insert after line 134, before "// Footer"):
```swift
// Data Section
Section {
    Button(role: .destructive) {
        showArchiveAllConfirmation = true
    } label: {
        HStack {
            Label("Archive All Sessions", systemImage: "archivebox")
                .font(TronTypography.subheadline)
                .foregroundStyle(.red)
            Spacer()
            if isArchivingAll {
                ProgressView()
                    .tint(.red)
            }
        }
    }
    .disabled(eventStoreManager.sessions.isEmpty || isArchivingAll)
} header: {
    Text("Data")
        .font(TronTypography.caption)
} footer: {
    Text("Removes all sessions from your device. Session data on the server will remain.")
        .font(TronTypography.caption2)
}
.listSectionSpacing(24)
```

**Add confirmation alert** (after the existing `.alert()` on line 192):
```swift
.alert("Archive All Sessions?", isPresented: $showArchiveAllConfirmation) {
    Button("Cancel", role: .cancel) {}
    Button("Archive All", role: .destructive) {
        archiveAllSessions()
    }
} message: {
    Text("This will remove \(eventStoreManager.sessions.count) session\(eventStoreManager.sessions.count == 1 ? "" : "s") from your device. Session data on the server will remain.")
}
```

**Add action method** (after `resetToDefaults()` around line 214):
```swift
private func archiveAllSessions() {
    isArchivingAll = true
    Task {
        await eventStoreManager.archiveAllSessions()
        isArchivingAll = false
    }
}
```

### 2. `packages/ios-app/Sources/Services/EventStoreManager+Operations.swift`

**Add new method** (after `deleteSession()` around line 66):
```swift
/// Archive all sessions (delete locally, optionally notify server)
func archiveAllSessions() async {
    let sessionsToArchive = sessions

    guard !sessionsToArchive.isEmpty else {
        logger.info("No sessions to archive", category: .session)
        return
    }

    logger.info("Archiving \(sessionsToArchive.count) sessions...", category: .session)

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

    setActiveSession(nil)
    loadSessions()
    logger.info("Archived \(sessionsToArchive.count) sessions", category: .session)
}
```

## Edge Cases Handled
- **No sessions**: Button disabled when `sessions.isEmpty`
- **Double-tap prevention**: Button disabled while `isArchivingAll` is true
- **Active session**: Cleared via `setActiveSession(nil)` after archive
- **Individual failures**: Loop continues even if one session fails
- **Server failures**: Logged as warning, local delete still proceeds

## Verification
1. Build the project: `bun run build`
2. Run tests: `bun run test`
3. Open iOS app in simulator
4. Create a few test sessions
5. Open Settings sheet
6. Verify "Archive All Sessions" button appears in new "Data" section
7. Tap button → confirmation alert appears with session count
8. Cancel → nothing happens
9. Confirm → all sessions removed, dashboard is empty
10. Verify button is disabled when no sessions exist
