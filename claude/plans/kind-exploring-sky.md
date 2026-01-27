# iOS App Architecture Analysis & Anti-Pattern Remediation Plan

## Current Rating: 62/100

### Breakdown by Category

| Category | Score | Notes |
|----------|-------|-------|
| **Architecture** | 75/100 | Event plugin system is clean; coordinator pattern good |
| **Code Organization** | 70/100 | Extension-based separation works; some large files |
| **Error Handling** | 40/100 | 115 `try?` instances; silent failures throughout |
| **State Management** | 55/100 | Fragmented (@Published vs @Observable); multiple sources of truth |
| **Testability/DI** | 45/100 | No DI container; tight coupling via EnvironmentObject |
| **Separation of Concerns** | 55/100 | ChatViewModel god object; 12 extensions masking complexity |
| **Code Duplication** | 75/100 | Well-managed; extension pattern prevents most duplication |

---

## Critical Anti-Patterns to Address

### 1. **ChatViewModel God Object** (Priority: HIGH)
**Location:** `Sources/ViewModels/Chat/ChatViewModel.swift` + 12 extension files
**Lines:** 767 + 703 + 312 + 308 + ... = ~3,500 lines total

**Problem:** ChatViewModel handles 12+ distinct responsibilities:
- Message streaming & pagination
- WebSocket event routing (150+ line switch statement)
- Browser state & screenshots
- AskUserQuestion interaction
- Tool event coordination
- Turn lifecycle management
- Thinking content management
- UI canvas rendering
- Subagent tracking
- Context window management
- Audio recording
- Transcription

**Evidence:**
- 8 internal managers (AnimationCoordinator, StreamingManager, MessageWindowManager, etc.)
- 8 extracted state objects (BrowserState, PlanModeState, etc.)
- 9 @Published properties
- `ToolEventContext` protocol exposes 15+ properties/methods

**Impact:** Difficult to test, reason about, or modify without risking regressions.

---

### 2. **Silent Error Handling** (Priority: HIGH)
**Location:** Throughout codebase
**Count:** 115 instances of `try?`

**Problem:** Errors are silently swallowed, making debugging impossible.

**Examples:**
```swift
// EventStoreManager.swift - errors lost
try? await database.deleteEvent(event)

// ToolResultParser.swift - silent JSON parse failures
guard let json = try? JSONDecoder().decode(...) else { return nil }

// ChatViewModel+Events.swift - event handling failures hidden
if let data = try? JSONEncoder().encode(message) { ... }
```

**Impact:** Production issues become impossible to diagnose; silent data corruption.

---

### 3. **Fragmented State Management** (Priority: MEDIUM)
**Location:** ViewModels/, State objects
**Pattern:** Mixing @Published + ObservableObject (22 classes) with @Observable (12 classes)

**Problem:** No single source of truth for state:
- Messages in: `ChatViewModel.messages`, `MessageWindowManager`, `currentToolMessages`, `StreamingManager`
- Tool state in: `ToolEventCoordinator`, `currentTurnToolCalls`, individual tool messages
- Multiple patterns: @Published vs @Observable vs @State

**Evidence:**
```swift
// ChatViewModel has
@Published var messages: [ChatMessage]
var currentToolMessages: [UUID: ChatMessage]  // Duplicate tracking
var currentTurnToolCalls: [ToolCallRecord]     // Another tracking

// Plus MessageWindowManager has
var paginationState: MessagePaginationState   // More message state
```

**Impact:** State synchronization bugs; difficult to reason about data flow.

---

### 4. **Missing Dependency Injection** (Priority: MEDIUM)
**Location:** Views creating state objects inline

**Problem:** State objects instantiated directly in Views, not injected:
```swift
// ChatView.swift
@StateObject var viewModel: ChatViewModel  // Created via .init()
@StateObject var scrollCoordinator: ScrollStateCoordinator
@StateObject var inputHistory = InputHistoryStore()
// ... 4 more @StateObjects
```

**Impact:**
- Unit testing requires full View instantiation
- Coordinators require full ChatViewModel context to test
- No mock injection points

---

### 5. **Large Files with Multiple Concerns** (Priority: MEDIUM)
**Files exceeding 700 lines:**

| File | Lines | Issue |
|------|-------|-------|
| `Events.swift` | 955 | 29 event types in one file |
| `ContextAnalyticsViews.swift` | 954 | 12 view components |
| `Message.swift` | 863 | Model + enum + helpers |
| `ContextSectionViews.swift` | 770 | 9+ @ViewBuilder properties |
| `ChatViewModel.swift` | 767 | God object (see #1) |
| `ChatView.swift` | 760 | 8 @ViewBuilder properties |
| `NewSessionFlow.swift` | 707 | Multi-step wizard |
| `ChatViewModel+Events.swift` | 703 | Event dispatch |

---

### 6. **String-Based Tool Matching** (Priority: LOW)
**Location:** Event handlers, tool coordination

**Problem:** Tool names matched via strings, not type-safe enums:
```swift
if result.isAskUserQuestion { ... }
if event.toolName.lowercased() == "renderappui" { ... }
if toolName == "Read" || toolName == "Edit" || toolName == "Write" { ... }
```

**Impact:** Typos cause silent failures; no compiler assistance.

---

### 7. **Result-to-Event Bridge Overhead** (Priority: LOW)
**Location:** `ChatViewModel+Events.swift` lines 376-677

**Problem:** Event plugin Results converted back to legacy Event structs:
```swift
// Plugin produces Result, then converted back to Event
case ToolStartPlugin.eventType:
    if let r = transform() as? ToolStartPlugin.Result {
        let event = ToolStartEvent(...)  // Reconstruction
        handleToolStart(event: event)
    }
```

**Status:** Intentional migration pattern, but represents ~300 lines of bridge code.

---

## Implementation Plan: Error Handling & Robust Logging

**Goal:** Replace silent error handling AND strengthen logging infrastructure throughout the codebase.

---

## Part A: Logging Infrastructure Improvements

### A1. Add Missing Log Category

**File:** `Sources/Services/Infrastructure/TronLogger.swift`

Add `.database` category for repository-layer operations:
```swift
enum LogCategory: String, CaseIterable {
    case websocket, rpc, session, chat, ui, network, events, notification, general
    case database  // NEW - for repository operations
}
```

Update buffer sizes:
```swift
case .database: return 500  // Moderate retention for DB operations
```

### A2. Add Logging to Silent Database Operations

**File:** `Sources/Database/Repositories/EventRepository.swift`

Add logging to batch operations (currently 0 logs in ~60 lines):

```swift
func insertBatch(_ events: [SessionEvent]) throws {
    guard !events.isEmpty else { return }
    logger.debug("Starting batch insert of \(events.count) events", category: .database)
    try transport.execute("BEGIN TRANSACTION")
    do {
        for event in events {
            try insert(event)
        }
        try transport.execute("COMMIT")
        logger.info("Batch insert committed: \(events.count) events", category: .database)
    } catch {
        try transport.execute("ROLLBACK")
        logger.error("Batch insert rolled back: \(error.localizedDescription)", category: .database)
        throw error
    }
}

func insertIgnoringDuplicates(_ events: [SessionEvent]) throws -> Int {
    logger.debug("Starting insertIgnoringDuplicates for \(events.count) events", category: .database)
    // ... existing logic ...
    logger.info("Inserted \(insertedCount) of \(events.count) events (duplicates ignored)", category: .database)
    return insertedCount
}
```

Also add logs to:
- `delete()` - log event ID being deleted
- `deleteBySession()` - log session ID and count

### A3. Log State Transitions

**File:** `Sources/Services/Events/EventStoreManager.swift`

Add logging to critical state changes:

```swift
var processingSessionIds: Set<String> = [] {
    didSet {
        if processingSessionIds != oldValue {
            let added = processingSessionIds.subtracting(oldValue)
            let removed = oldValue.subtracting(processingSessionIds)
            if !added.isEmpty { logger.debug("Processing started for sessions: \(added)", category: .session) }
            if !removed.isEmpty { logger.debug("Processing completed for sessions: \(removed)", category: .session) }
        }
        UserDefaults.standard.set(Array(processingSessionIds), forKey: "tron.processingSessionIds")
    }
}

@Published private(set) var activeSessionId: String? {
    didSet {
        logger.info("Active session changed: \(oldValue ?? "nil") → \(activeSessionId ?? "nil")", category: .session)
    }
}
```

### A4. Add Context to Error Logs

**Files:** All repository files

Change from:
```swift
logger.warning("Failed to parse event row in getBySession: \(error.localizedDescription)", category: .session)
```

To:
```swift
logger.warning("Failed to parse event row: sessionId=\(sessionId), rowIndex=\(index), error=\(error)", category: .database)
```

### A5. Make Error Context Required

**File:** `Sources/Services/Infrastructure/ErrorHandler.swift`

Change `withErrorHandling` signature:
```swift
// Before - context is optional
func withErrorHandling<T>(context: String? = nil, operation: () async throws -> T) async -> T?

// After - context is required
func withErrorHandling<T>(context: String, operation: () async throws -> T) async -> T?
```

This forces callers to provide meaningful context.

### A6. Add Truncation Markers

**File:** `Sources/Services/Infrastructure/TronLogger.swift`

Update RPC logging to indicate truncation:
```swift
let paramsStr: String
if let p = params {
    let full = String(describing: p)
    if full.count > 500 {
        paramsStr = String(full.prefix(500)) + " [TRUNCATED:\(full.count) chars]"
    } else {
        paramsStr = full
    }
} else {
    paramsStr = "nil"
}
```

### A7. Standardize Log Levels

Document and enforce:
| Level | Use For |
|-------|---------|
| `.verbose` | UI interactions, fine-grained debugging |
| `.debug` | Operation details, token counts, state details |
| `.info` | Operation start/complete, state changes, user actions |
| `.warning` | Recoverable errors, validation failures, optional features unavailable |
| `.error` | Failures that affect functionality |

Audit and fix inconsistent usages in:
- `ChatViewModel+Connection.swift` - some `.info` should be `.debug`
- `ChatViewModel+Messaging.swift` - standardize success logs

### A8. Log Async Task Completions

**File:** `Sources/ViewModels/Chat/ChatViewModel+Browser.swift`

```swift
func closeBrowserSession() {
    logger.info("Closing browser session", category: .session)
    Task {
        do {
            await stopBrowserStream()
            await MainActor.run { /* state clearing */ }
            logger.debug("Browser session closed successfully", category: .session)
        } catch {
            logger.error("Failed to close browser session: \(error)", category: .session)
        }
    }
}
```

---

## Part B: Error Handling Foundation

### B1. Create Error Infrastructure

Create `Sources/Core/Errors/AppError.swift`:
```swift
enum AppError: Error, LocalizedError {
    // Database
    case databaseRead(underlying: Error)
    case databaseWrite(underlying: Error)
    case databaseDelete(underlying: Error)

    // Network/RPC
    case rpcEncode(underlying: Error)
    case rpcDecode(underlying: Error)
    case websocketDisconnected

    // Event Processing
    case eventParseFailed(type: String, underlying: Error)
    case eventTransformFailed(type: String)

    // Tool Processing
    case toolResultParseFailed(toolName: String, underlying: Error)
    case toolOutputInvalid(toolName: String, reason: String)

    // State
    case messageNotFound(id: UUID)
    case sessionNotFound(id: String)

    var errorDescription: String? { ... }
}
```

### Step 2: Replace try? Patterns by Category

**Database Operations (~20 instances):**
- `EventStoreManager.swift` - event CRUD
- `EventStoreManager+Operations.swift` - batch operations
- `SessionRepository.swift` - session persistence
- `EventRepository.swift` - event queries

**Pattern:**
```swift
// Before
try? await database.deleteEvent(event)

// After
do {
    try await database.deleteEvent(event)
} catch {
    logger.error("Failed to delete event \(event.id): \(error)", category: .database)
}
```

**JSON Encoding/Decoding (~35 instances):**
- `RPCClient.swift` - RPC encoding
- `ToolResultParser.swift` - tool output parsing
- `ChatViewModel+Events.swift` - event payloads
- `UnifiedEventTransformer.swift` - event transformation

**Pattern:**
```swift
// Before
guard let json = try? JSONDecoder().decode(Foo.self, from: data) else { return nil }

// After
do {
    return try JSONDecoder().decode(Foo.self, from: data)
} catch {
    logger.warning("Failed to decode Foo: \(error)", category: .parsing)
    return nil  // Or throw AppError.rpcDecode(underlying: error)
}
```

**Event Handling (~25 instances):**
- `ChatViewModel+Events.swift` - event dispatch
- `ToolEventCoordinator.swift` - tool events
- Event plugins - parsing

**Tool Processing (~15 instances):**
- `ToolResultParser.swift` - output parsing
- `ToolResultRouter.swift` - tool dispatch
- Individual tool viewers

**File I/O (~10 instances):**
- Screenshot extraction
- Attachment handling
- Cache operations

**Other (~10 instances):**
- URL parsing
- Date formatting
- String encoding

### Step 3: Add Logging for All Error Paths

Ensure every catch block logs with:
- Error category (`.database`, `.network`, `.parsing`, `.events`, `.tools`)
- Context (what operation, what ID/name)
- Underlying error description

### Step 4: Audit and Verify

1. Search for remaining `try?` instances
2. Verify each is intentional (truly optional) or needs conversion
3. Run full test suite

---

## Files to Modify

**New files:**
- `Sources/Core/Errors/AppError.swift`

**Logging infrastructure:**
- `Sources/Services/Infrastructure/TronLogger.swift` (add .database category, truncation markers)
- `Sources/Services/Infrastructure/ErrorHandler.swift` (make context required)

**Database layer (add batch operation logs, context to errors):**
- `Sources/Database/Repositories/EventRepository.swift`
- `Sources/Database/Repositories/SessionRepository.swift`
- `Sources/Database/Repositories/SyncRepository.swift`

**Event management (state transition logs):**
- `Sources/Services/Events/EventStoreManager.swift`
- `Sources/Services/Events/EventStoreManager+Operations.swift`

**Error handling (replace try? with proper handling):**
- `Sources/Services/Network/RPCClient.swift`
- `Sources/Services/Tools/ToolResultParser.swift`
- `Sources/ViewModels/Chat/ChatViewModel+Events.swift`
- `Sources/ViewModels/Chat/ChatViewModel+Messaging.swift`
- `Sources/ViewModels/Chat/ChatViewModel+Browser.swift`
- `Sources/Models/Events/UnifiedEventTransformer.swift`
- `Sources/Views/Tools/ToolResultRouter.swift`

---

## Verification

### Build & Tests
```bash
bun run build && bun run test
```

### Static Checks
1. Search for `try?` - should be <20 intentional instances
2. Search for `context: nil` in ErrorHandler calls - should be 0
3. Verify `.database` category is used in all repository files

### Runtime Verification in Simulator
1. **Start session** - verify connection logs include session context
2. **Send messages** - verify streaming logs show progress
3. **Use tools** - verify tool start/end logs with tool names
4. **Check batch operations** - sync a session, verify "Batch insert committed: X events" appears
5. **State transitions** - switch sessions, verify "Active session changed" logs
6. **Error paths** - disconnect network, verify error logs include context
7. **Open LogViewer** - verify `.database` category appears in filter dropdown

### Deliberate Failure Tests
1. Corrupt a cached event JSON, resume session → verify parse error logs include eventId
2. Send invalid tool output → verify ToolResultParser logs the error with tool name
3. Call ErrorHandler.withErrorHandling without context → should fail to compile

---

## Future Phases (after error handling)

### Phase 2: ChatViewModel Decomposition
- Extract MessageStreamingViewModel
- Extract ToolCoordinationViewModel
- Extract BrowserViewModel

### Phase 3: State Unification
- Migrate to @Observable pattern
- Single source of truth for messages

### Phase 4: Dependency Injection
- Create DependencyContainer
- Protocol-based service injection

### Phase 5: File Modularization
- Split Events.swift
- Split large view files
