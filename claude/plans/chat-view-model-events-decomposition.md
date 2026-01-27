# ChatViewModel+Events.swift Decomposition Plan

## Status: PLANNING

## Overview

**Target file**: `packages/ios-app/Sources/ViewModels/Chat/ChatViewModel+Events.swift` (1,015 lines)

**Goal**: Decompose the monolithic event handling extension into focused handler classes that own specific event domains, following the existing pattern established by `State/` objects.

---

## Current State Analysis

### Existing Architecture

The codebase already has a partial extraction:
- `ChatEventHandler.swift` (493 lines) - **Data extraction only** (transforms events → result types)
- `ChatEventContext.swift` (29 lines) - Protocol for ChatViewModel abstraction
- Various `State/` objects - Domain-specific state management (BrowserState, PlanModeState, etc.)

**Problem**: `ChatViewModel+Events.swift` still has ~1,000 lines because it performs all UI updates and state mutations after receiving results from `ChatEventHandler`.

### Current Handler Distribution (1,015 lines)

| Handler | Lines | Complexity | Description |
|---------|-------|------------|-------------|
| `handleToolStart` | ~130 | HIGH | RenderAppUI chip creation, AskUserQuestion, OpenBrowser detection |
| `handleToolEnd` | ~45 | MEDIUM | Tool result processing, browser screenshot extraction |
| `handleTurnStart` | ~45 | MEDIUM | Turn state reset, tracking initialization |
| `handleTurnEnd` | ~165 | HIGH | Token tracking, metadata assignment, context updates |
| `handleAgentTurn` | ~65 | MEDIUM | Turn content caching for persistence |
| `handleComplete` | ~55 | MEDIUM | Final state cleanup, dashboard updates |
| `handleTextDelta` | ~25 | LOW | Already delegating to StreamingManager |
| `handleThinkingDelta` | ~25 | LOW | Thinking message management |
| `handleCompaction` | ~30 | LOW | Compaction notification pill |
| `handleContextCleared` | ~30 | LOW | Context cleared notification pill |
| `handleMessageDeleted` | ~10 | LOW | Deletion notification |
| `handleSkillRemoved` | ~20 | LOW | Skill removal notification |
| `handlePlanModeEntered` | ~10 | LOW | Plan mode state update |
| `handlePlanModeExited` | ~10 | LOW | Plan mode state update |
| `handleAgentError` | ~30 | LOW | Error notification, state cleanup |
| `handleUIRenderStart` | ~45 | MEDIUM | Canvas state initialization |
| `handleUIRenderChunk` | ~70 | MEDIUM | Chip creation from chunks, race handling |
| `handleUIRenderComplete` | ~40 | MEDIUM | UI parsing and completion |
| `handleUIRenderError` | ~20 | LOW | Error state update |
| `handleUIRenderRetry` | ~25 | LOW | Retry state update |
| `handleTodosUpdated` | ~10 | LOW | Todo state delegation |
| Private helpers | ~110 | MEDIUM | `extractTitleFromAccumulated`, `getToolCallIdForCanvas`, etc. |

### Proposed Extraction Groups

Based on cohesion and coupling analysis:

| Group | Handlers | Lines | Justification |
|-------|----------|-------|---------------|
| **ToolEventCoordinator** | `handleToolStart`, `handleToolEnd`, AskUserQuestion/OpenBrowser helpers | ~200 | Tool lifecycle is tightly coupled |
| **TurnLifecycleCoordinator** | `handleTurnStart`, `handleTurnEnd`, `handleAgentTurn`, `handleComplete` | ~330 | Turn state management is interconnected |
| **UICanvasCoordinator** | All `handleUIRender*` methods + helpers | ~210 | Canvas rendering is self-contained |
| **ContextEventCoordinator** | `handleCompaction`, `handleContextCleared`, `handleMessageDeleted`, `handleSkillRemoved` | ~90 | Context-change events share similar patterns |
| **ChatViewModel+Events** | `handleTextDelta`, `handleThinkingDelta`, `handlePlanMode*`, `handleAgentError`, `handleTodosUpdated` | ~120 | Simple delegations/notifications stay in extension |

---

## Proposed Structure

```
ViewModels/
├── Chat/
│   ├── ChatViewModel.swift              # Main view model
│   ├── ChatViewModel+Events.swift       # Thin routing layer (~120 lines)
│   ├── ChatViewModel+Connection.swift   # Existing
│   ├── ChatViewModel+Messaging.swift    # Existing
│   ├── ChatViewModel+Pagination.swift   # Existing
│   ├── ChatViewModel+Subagent.swift     # Existing
│   └── ChatViewModel+Transcription.swift # Existing
│
├── Handlers/
│   ├── ChatEventHandler.swift           # Existing - data extraction
│   ├── ChatEventContext.swift           # Existing - protocol
│   ├── ToolEventCoordinator.swift       # NEW - tool lifecycle
│   ├── TurnLifecycleCoordinator.swift   # NEW - turn management
│   └── UICanvasCoordinator.swift        # NEW - canvas rendering
│
├── State/
│   ├── BrowserState.swift               # Existing
│   ├── AskUserQuestionState.swift       # Existing
│   ├── PlanModeState.swift              # Existing
│   ├── TodoState.swift                  # Existing
│   ├── ThinkingState.swift              # Existing
│   ├── UICanvasState.swift              # Existing
│   ├── RenderAppUIChipTracker.swift     # Existing
│   ├── ContextTrackingState.swift       # Existing
│   ├── SubagentState.swift              # Existing
│   └── InputBarState.swift              # Existing
│
└── Managers/
    ├── StreamingManager.swift           # Existing (assumed)
    ├── UIUpdateQueue.swift              # Existing
    ├── AnimationCoordinator.swift       # Existing
    └── MessageWindowManager.swift       # Existing
```

---

## Implementation Phases

### Phase 1: Extract ToolEventCoordinator (Highest Impact)

**File**: `ViewModels/Handlers/ToolEventCoordinator.swift`

**Extract**:
- `handleToolStart` (main logic after ChatEventHandler.handleToolStart)
- `handleAskUserQuestionToolStart` (private helper)
- `handleOpenBrowserToolStart` (private helper)
- `handleToolEnd` (main logic after ChatEventHandler.handleToolEnd)
- `extractAndDisplayBrowserScreenshot` (private helper)

**Dependencies needed**:
- `messages: [ChatMessage]` (read/write)
- `currentToolMessages: [UUID: ChatMessage]` (read/write)
- `currentTurnToolCalls: [ToolCallRecord]` (read/write)
- `askUserQuestionState: AskUserQuestionState`
- `browserState: BrowserState`
- `renderAppUIChipTracker: RenderAppUIChipTracker`
- `animationCoordinator: AnimationCoordinator`
- `uiUpdateQueue: UIUpdateQueue`
- `messageWindowManager: MessageWindowManager`
- `uiCanvasState: UICanvasState`
- `logger: TronLogger`

**Interface**:
```swift
@MainActor
final class ToolEventCoordinator {
    // Dependencies injected via init or context protocol

    func handleToolStart(
        _ event: ToolStartEvent,
        result: ToolStartResult,
        context: ToolEventContext
    )

    func handleToolEnd(
        _ event: ToolEndEvent,
        result: ToolEndResult,
        context: ToolEventContext
    )
}

@MainActor
protocol ToolEventContext: AnyObject {
    var messages: [ChatMessage] { get set }
    var currentToolMessages: [UUID: ChatMessage] { get set }
    var currentTurnToolCalls: [ToolCallRecord] { get set }
    var askUserQuestionState: AskUserQuestionState { get }
    var browserState: BrowserState { get }
    var renderAppUIChipTracker: RenderAppUIChipTracker { get }
    var animationCoordinator: AnimationCoordinator { get }
    var uiUpdateQueue: UIUpdateQueue { get }
    var messageWindowManager: MessageWindowManager { get }
    var uiCanvasState: UICanvasState { get }

    func flushPendingTextUpdates()
    func finalizeStreamingMessage()
    func openAskUserQuestionSheet(for data: AskUserQuestionToolData)
}
```

**Estimated lines**: ~200

**Verification**:
```bash
cd packages/ios-app && xcodebuild -scheme TronMobile -destination 'platform=iOS Simulator,name=iPhone 16' build
```

---

### Phase 2: Extract TurnLifecycleCoordinator

**File**: `ViewModels/Handlers/TurnLifecycleCoordinator.swift`

**Extract**:
- `handleTurnStart` (turn state initialization)
- `handleTurnEnd` (token tracking, metadata assignment)
- `handleAgentTurn` (turn content caching)
- `handleComplete` (final state cleanup)

**Dependencies needed**:
- `messages: [ChatMessage]` (read/write)
- `contextState: ContextTrackingState`
- `thinkingState: ThinkingState`
- `streamingManager: StreamingManager`
- `uiUpdateQueue: UIUpdateQueue`
- `animationCoordinator: AnimationCoordinator`
- `eventStoreManager: EventStoreManager?`
- `currentModel: String`
- `sessionId: String`
- Various turn tracking properties

**Interface**:
```swift
@MainActor
final class TurnLifecycleCoordinator {
    func handleTurnStart(
        _ event: TurnStartEvent,
        result: TurnStartResult,
        context: TurnLifecycleContext
    )

    func handleTurnEnd(
        _ event: TurnEndEvent,
        result: TurnEndResult,
        context: TurnLifecycleContext
    )

    func handleAgentTurn(
        _ event: AgentTurnEvent,
        context: TurnLifecycleContext
    )

    func handleComplete(
        context: TurnLifecycleContext
    )
}
```

**Estimated lines**: ~330

---

### Phase 3: Extract UICanvasCoordinator

**File**: `ViewModels/Handlers/UICanvasCoordinator.swift`

**Extract**:
- `handleUIRenderStart`
- `handleUIRenderChunk`
- `handleUIRenderComplete`
- `handleUIRenderError`
- `handleUIRenderRetry`
- `extractTitleFromAccumulated` (private helper)
- `getToolCallIdForCanvas` (private helper)

**Dependencies needed**:
- `messages: [ChatMessage]` (read/write)
- `renderAppUIChipTracker: RenderAppUIChipTracker`
- `uiCanvasState: UICanvasState`
- `animationCoordinator: AnimationCoordinator`
- `messageWindowManager: MessageWindowManager`
- `logger: TronLogger`

**Interface**:
```swift
@MainActor
final class UICanvasCoordinator {
    func handleUIRenderStart(_ event: UIRenderStartEvent, context: UICanvasContext)
    func handleUIRenderChunk(_ event: UIRenderChunkEvent, context: UICanvasContext)
    func handleUIRenderComplete(_ event: UIRenderCompleteEvent, context: UICanvasContext)
    func handleUIRenderError(_ event: UIRenderErrorEvent, context: UICanvasContext)
    func handleUIRenderRetry(_ event: UIRenderRetryEvent, context: UICanvasContext)
}
```

**Estimated lines**: ~210

---

### Phase 4: Refactor ChatViewModel+Events.swift as Thin Routing Layer

After phases 1-3, `ChatViewModel+Events.swift` becomes a thin routing layer:

```swift
extension ChatViewModel {
    func handleTextDelta(_ delta: String) {
        // ~10 lines - delegates to StreamingManager
    }

    func handleThinkingDelta(_ delta: String) {
        // ~15 lines - delegates to ThinkingState
    }

    func handleToolStart(_ event: ToolStartEvent) {
        let result = eventHandler.handleToolStart(event, context: self)
        toolEventCoordinator.handleToolStart(event, result: result, context: self)
    }

    func handleToolEnd(_ event: ToolEndEvent) {
        let result = eventHandler.handleToolEnd(event)
        toolEventCoordinator.handleToolEnd(event, result: result, context: self)
    }

    // ... similar delegations for turn lifecycle and UI canvas ...

    func handleCompaction(_ event: CompactionEvent) {
        // ~20 lines - stays here (simple)
    }

    // ... other simple handlers stay ...
}
```

**Estimated final lines**: ~120

---

## Testing Strategy

### Unit Tests for Each Coordinator

1. **ToolEventCoordinatorTests.swift**
   - Test RenderAppUI chip creation from tool_start
   - Test RenderAppUI chip update when chunk arrives first
   - Test AskUserQuestion detection and handling
   - Test OpenBrowser URL parsing
   - Test browser screenshot extraction

2. **TurnLifecycleCoordinatorTests.swift**
   - Test turn state reset on turnStart
   - Test token metadata assignment on turnEnd
   - Test context state updates from normalizedUsage
   - Test catching-up notification removal

3. **UICanvasCoordinatorTests.swift**
   - Test chip creation from first chunk (race condition)
   - Test canvas state creation for existing chip
   - Test title extraction from accumulated JSON
   - Test error and retry state updates

### Mock Contexts

Create mock implementations of context protocols for isolated testing:

```swift
final class MockToolEventContext: ToolEventContext {
    var messages: [ChatMessage] = []
    var currentToolMessages: [UUID: ChatMessage] = [:]
    var flushPendingTextUpdatesCalled = false
    // ... etc
}
```

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Circular dependencies | LOW | Context protocols break cycles |
| Race conditions | MEDIUM | UICanvasCoordinator handles chip/chunk race explicitly |
| State inconsistency | MEDIUM | Coordinators operate on context, not internal state |
| Build failures | LOW | Incremental extraction, build after each phase |

---

## Success Criteria

- [ ] Phase 1: ToolEventCoordinator extracted, build passes
- [ ] Phase 2: TurnLifecycleCoordinator extracted, build passes
- [ ] Phase 3: UICanvasCoordinator extracted, build passes
- [ ] Phase 4: ChatViewModel+Events.swift reduced to ~120 lines
- [ ] All existing functionality preserved
- [ ] Unit tests added for each coordinator
- [ ] No increase in build time

---

## Final Structure Summary

| File | Lines (Before) | Lines (After) |
|------|----------------|---------------|
| `ChatViewModel+Events.swift` | 1,015 | ~120 |
| `ToolEventCoordinator.swift` | 0 | ~200 |
| `TurnLifecycleCoordinator.swift` | 0 | ~330 |
| `UICanvasCoordinator.swift` | 0 | ~210 |
| **Total** | 1,015 | ~860 |

The slight increase in total lines is offset by:
- Clear separation of concerns
- Independent testability
- Easier maintenance and feature addition
- Better code discoverability

---

## Verification Commands

```bash
# After each phase
cd packages/ios-app && xcodebuild -scheme TronMobile -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests
cd packages/ios-app && xcodebuild test -scheme TronMobile -destination 'platform=iOS Simulator,name=iPhone 16'

# Check line counts
wc -l Sources/ViewModels/Chat/ChatViewModel+Events.swift
wc -l Sources/ViewModels/Handlers/*.swift
```
