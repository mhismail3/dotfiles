# Port-Based Session Filtering for Tron iOS App

## Overview
Add ability to switch between beta (8082) and prod (8080) servers, with sessions filtered by their source environment.

## Implementation

### 1. Data Model - Add `serverOrigin` to CachedSession
**File:** `packages/ios-app/Sources/Database/EventTypes.swift`

Add new field after `isFork`:
```swift
/// Server origin (host:port) this session was synced from
var serverOrigin: String?
```

### 2. Database Migration
**File:** `packages/ios-app/Sources/Database/EventDatabase.swift`

Add migration in `createTables()` (after existing migrations ~line 144):
```swift
// Migration: Add server_origin for environment filtering
do {
    try execute("ALTER TABLE sessions ADD COLUMN server_origin TEXT")
} catch {
    // Column already exists
}

// Index for filtering
try execute("CREATE INDEX IF NOT EXISTS idx_sessions_origin ON sessions(server_origin)")
```

Update `insertSession()` to include `server_origin` in INSERT statement.

Update `parseSessionRow()` to read the new column.

Add filtered query method:
```swift
func getSessionsByOrigin(_ origin: String?) throws -> [CachedSession]
```
- If origin is nil, return all sessions
- If origin is set, return sessions WHERE `server_origin = ? OR server_origin IS NULL` (include legacy sessions)

### 3. Track Origin During Sync
**File:** `packages/ios-app/Sources/Services/EventStoreManager+Sync.swift`

Modify `serverSessionToCached()` to accept origin parameter:
```swift
func serverSessionToCached(_ info: SessionInfo, serverOrigin: String) -> CachedSession
```

Update `fullSync()` to pass current origin:
```swift
let serverOrigin = "\(getCurrentHost()):\(getCurrentPort())"
let cachedSession = serverSessionToCached(serverSession, serverOrigin: serverOrigin)
```

### 4. Filter Sessions in EventStoreManager
**File:** `packages/ios-app/Sources/Services/EventStoreManager.swift`

Add property to track current filter:
```swift
@Published var filterByOrigin: Bool = true
```

Add computed property for current origin (get from AppState or RPCClient).

Modify `loadSessions()` to filter:
```swift
func loadSessions() {
    let origin = filterByOrigin ? currentServerOrigin : nil
    sessions = try eventDB.getSessionsByOrigin(origin)
}
```

### 5. UI - Environment Quick Switch
**File:** `packages/ios-app/Sources/Views/SettingsView.swift`

Add segmented picker above existing Server section:
```swift
Section {
    Picker("Environment", selection: $selectedEnvironment) {
        Text("Beta").tag("8082")
        Text("Prod").tag("8080")
    }
    .pickerStyle(.segmented)
    .onChange(of: selectedEnvironment) { _, port in
        serverPort = port
    }
} header: {
    Text("Environment")
}
```

Derive `selectedEnvironment` from current `serverPort` (or "custom" if neither).

### 6. Reconnect on Port Change
Ensure changing port triggers:
1. Disconnect from old server
2. Connect to new server
3. Reload sessions with new filter

This may already work via `AppState.serverURL` being observed by `RPCClient`.

## Files to Modify
1. `Sources/Database/EventTypes.swift` - Add `serverOrigin` field
2. `Sources/Database/EventDatabase.swift` - Migration + filtered query
3. `Sources/Services/EventStoreManager+Sync.swift` - Track origin during sync
4. `Sources/Services/EventStoreManager.swift` - Filter logic
5. `Sources/Views/SettingsView.swift` - Environment picker UI

## Edge Cases
- **Legacy sessions** (no `serverOrigin`): Show in all environments via `OR server_origin IS NULL`
- **Custom ports**: Work naturally - origin is just "host:port" string
- **Host changes**: Origin includes host, so `localhost:8080` vs `192.168.1.5:8080` are separate

## Verification
1. Build and run the app
2. Connect to beta (8082) and create/sync a session
3. Switch to prod (8080) - verify beta session disappears from list
4. Switch back to beta - verify session reappears
5. Test with legacy sessions (existing sessions without origin should appear in both)
