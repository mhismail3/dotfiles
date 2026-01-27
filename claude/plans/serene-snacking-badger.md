# iOS App Comprehensive Refactoring Plan

## Goal
Refactor the Tron iOS app for maintainability and extensibility with **ZERO regressions** or UI/UX changes. Follow incremental, test-driven development.

## Current State
- **82 Swift files** (~35K LOC), **8 test files** (~3.5K LOC, ~10% coverage)
- MVVM + Services architecture with event-sourcing persistence
- SwiftUI/Combine reactive patterns, iOS 18.0+

## Key Problem Areas
| Component | LOC | Issue |
|-----------|-----|-------|
| ChatViewModel | 3K+ (6 files) | 51+ @Published props, god object |
| ContextAuditView | 2,555 | Monolithic view |
| ToolResultViewers | 1,860 | Many tool viewers in one file |
| MessageBubble | 1,607 | 20+ content type handlers |
| InputBar | 1,534 | Complex multi-purpose component |
| TronMobileApp | 1,611 | 4+ views inline |
| RPCClient | 1,080 | 20+ callback props, no protocol |
| EventStoreManager | 1,139 | Fragmented across 5 extensions |

---

## Phase 0: Testability Infrastructure (Foundation)

### 0.1 Create Service Protocols
Enable mocking for TDD by defining protocols for all services.

**New Files:**
- `Sources/Protocols/RPCClientProtocol.swift`
- `Sources/Protocols/EventDatabaseProtocol.swift`
- `Sources/Protocols/EventStoreManagerProtocol.swift`

**Modify:**
- `Sources/Services/RPCClient.swift` - conform to protocol
- `Sources/Services/EventStoreManager.swift` - conform to protocol
- `Sources/Database/EventDatabase.swift` - conform to protocol

### 0.2 Create Mock Implementations
**New Files:**
- `Tests/Mocks/MockRPCClient.swift`
- `Tests/Mocks/MockEventDatabase.swift`
- `Tests/Mocks/MockEventStoreManager.swift`

**Verification:** All existing tests pass, app runs unchanged.

---

## Phase 1: ChatViewModel State Extraction

Extract related state groups into dedicated `@Observable` classes while ChatViewModel remains the SwiftUI source of truth.

### 1.1 Extract Browser State
**Tests First:** `Tests/ViewModels/BrowserStateTests.swift`
```
- testBrowserFrameUpdate()
- testUserDismissedBrowserThisTurn()
- testBrowserStatusTracking()
```

**New File:** `Sources/ViewModels/State/BrowserState.swift`
- Move: `browserFrame`, `showBrowserWindow`, `browserStatus`, `userDismissedBrowserThisTurn`, `safariURL`

### 1.2 Extract AskUserQuestion State
**Tests First:** `Tests/ViewModels/AskUserQuestionStateTests.swift`

**New File:** `Sources/ViewModels/State/AskUserQuestionState.swift`
- Move: `showAskUserQuestionSheet`, `currentAskUserQuestionData`, `askUserQuestionAnswers`, `askUserQuestionCalledInTurn`

### 1.3 Extract Plan Mode State
**Tests First:** `Tests/ViewModels/PlanModeStateTests.swift`

**New File:** `Sources/ViewModels/State/PlanModeState.swift`
- Move: `isPlanModeActive`, `planModeSkillName`

### 1.4 Extract Context Tracking State
**Tests First:** `Tests/ViewModels/ContextStateTests.swift`

**New File:** `Sources/ViewModels/State/ContextTrackingState.swift`
- Move: `totalTokenUsage`, `currentContextWindow`, `accumulatedInputTokens`, `accumulatedOutputTokens`, etc.

**Migration Pattern:** Use computed property proxies in ChatViewModel during transition:
```swift
let browserState = BrowserState()
var browserFrame: UIImage? {
    get { browserState.browserFrame }
    set { browserState.browserFrame = newValue }
}
```

**Verification:** All features work identically, new tests pass.

---

## Phase 2: Event Handler Extraction

### 2.1 Create Event Handler Class
**Tests First:** `Tests/ViewModels/ChatEventHandlerTests.swift`
```
- testTextDeltaHandling()
- testToolStartCreatesMessage()
- testToolEndUpdatesMessage()
- testTurnStartResetsState()
- testTurnEndUpdatesMetadata()
```

**New Files:**
- `Sources/ViewModels/Handlers/ChatEventHandler.swift`
- `Sources/ViewModels/Handlers/ChatEventContext.swift` (protocol)

**Modify:** `Sources/ViewModels/ChatViewModel+Events.swift`
- Delegate to `ChatEventHandler` instead of inline handling

**Verification:** Send message, receive response, tool calls work correctly.

---

## Phase 3: View Component Extraction

### 3.1 MessageBubble Decomposition
**New Directory:** `Sources/Views/MessageBubble/`
- `MessageBubble.swift` (main container, ~100 LOC)
- `TextContentView.swift`
- `StreamingContentView.swift`
- `ToolResultRouter.swift`
- `NotificationViews.swift` (model change, interrupted, etc.)
- `MessageMetadataBadge.swift`

### 3.2 InputBar Decomposition
**New Directory:** `Sources/Views/InputBar/`
- `InputBar.swift` (container, ~200 LOC)
- `InputTextField.swift`
- `StatusPillBar.swift` (context, model, reasoning pills)
- `AttachmentBar.swift`
- `ActionButtons.swift` (send, mic, attachment)

### 3.3 ToolResultViewers Decomposition
**New Directory:** `Sources/Views/ToolViewers/`
- `ToolResultRouter.swift`
- `FileToolViewer.swift` (Read, Write, Edit)
- `BashToolViewer.swift`
- `SearchToolViewer.swift` (Grep, Glob)
- `BrowserToolViewer.swift`
- `GenericToolViewer.swift`

### 3.4 TronMobileApp Decomposition
**Extract from** `Sources/App/TronMobileApp.swift`:
- `Sources/Views/ContentView.swift`
- `Sources/Views/WelcomePage.swift`
- `Sources/Views/SessionDetailView.swift`
- `Sources/Views/EmptySessionView.swift`

Reduce TronMobileApp to ~70 LOC (just @main and app lifecycle).

### 3.5 ContextAuditView Decomposition
**New Directory:** `Sources/Views/ContextAudit/`
- `ContextAuditView.swift` (container)
- `ContextSnapshotView.swift`
- `MessageListSection.swift`
- `TokenAnalyticsView.swift`

**Verification:** Visual comparison - all views render identically.

---

## Phase 4: Service Layer Tests

### 4.1 RPCClient Tests
**New File:** `Tests/Services/RPCClientTests.swift`
- Test connection state transitions
- Test session resume
- Test prompt sending
- Test event parsing

### 4.2 EventStoreManager Tests
**New File:** `Tests/Services/EventStoreManagerTests.swift`
- Test session loading
- Test event syncing
- Test processing state tracking
- Test caching behavior

**Verification:** Test coverage > 50% for services.

---

## Phase 5: Design System Consolidation

### 5.1 Expand Theme
**Modify:** `Sources/Theme/TronColors.swift`
- Add semantic colors (userMessageBackground, toolMessageBackground, etc.)

**New Files:**
- `Sources/Theme/TronTypography.swift`
- `Sources/Theme/TronSpacing.swift`
- `Sources/Theme/TronAnimations.swift` (timing constants)

### 5.2 Extract Magic Numbers
Replace inline values throughout codebase:
- Animation durations → `TronAnimations.fast`, `.medium`, `.slow`
- Spacing → `TronSpacing.sm`, `.md`, `.lg`
- Text update interval (100ms), message cap (150), etc. → named constants

**Verification:** App behavior unchanged, code more readable.

---

## Phase 6: Error Handling Standardization

### 6.1 Create Error Types
**New File:** `Sources/Utilities/TronError.swift`
```swift
enum TronError: LocalizedError {
    case network(NetworkError)
    case database(DatabaseError)
    case session(SessionError)
}
```

### 6.2 Create Error Handler
**New File:** `Sources/Services/ErrorHandler.swift`
- Centralized error display
- Consistent severity handling
- Retry logic for transient errors

**Modify:** Replace scattered `showErrorAlert()` calls with `ErrorHandler.handle()`.

---

## Critical Files to Modify

| File | Phase | Changes |
|------|-------|---------|
| `Sources/ViewModels/ChatViewModel.swift` | 1, 2 | Extract state, delegate events |
| `Sources/ViewModels/ChatViewModel+Events.swift` | 2 | Delegate to ChatEventHandler |
| `Sources/Services/RPCClient.swift` | 0 | Add protocol conformance |
| `Sources/Services/EventStoreManager.swift` | 0 | Add protocol conformance |
| `Sources/Views/MessageBubble.swift` | 3 | Split into directory |
| `Sources/Views/InputBar.swift` | 3 | Split into directory |
| `Sources/Views/ToolResultViewers.swift` | 3 | Split into directory |
| `Sources/App/TronMobileApp.swift` | 3 | Extract inline views |
| `Sources/Views/ContextAuditView.swift` | 3 | Split into directory |

---

## Verification Strategy

### After Each Phase
1. **Automated:** Run full test suite (`xcodebuild test -scheme TronMobile`)
2. **Manual Checklist:**
   - [ ] App launches without crash
   - [ ] Can create new session
   - [ ] Can send message and receive response
   - [ ] Tool calls display and complete correctly
   - [ ] Browser features work
   - [ ] Context/token tracking accurate
   - [ ] Settings persist
   - [ ] Background/foreground transitions work

### Regression Prevention
- Git tag at each phase completion
- Each phase independently deployable
- No new features - only reorganization

---

## Execution Order

```
Phase 0 (Protocols/Mocks)
    ↓
Phase 1 (State Extraction) → Phase 2 (Event Handlers)
    ↓                              ↓
Phase 3 (View Components) ←────────┘
    ↓
Phase 4 (Service Tests)
    ↓
Phase 5 (Design System)
    ↓
Phase 6 (Error Handling)
```

**Recommended start:** Phase 0 (protocols) enables TDD for all subsequent phases.
