# ChatView Comprehensive Refactor Plan

## Goals
1. **Robust pill morph animations** - Sequential chained morphing (context → model → reasoning)
2. **Elegant tool call handling** - Queue-based, ordered, staggered appearance
3. **Cascade session load** - Messages animate in from bottom with 20ms stagger
4. **Virtual scrolling** - Lazy load older, unload off-screen, ~150 max in memory
5. **In-progress session joining** - Seamless catch-up with streaming
6. **Modular architecture** - Break ViewModel into focused sub-managers

---

## New Architecture

### Component Structure
```
Sources/ViewModels/
  ChatViewModel.swift              # Coordinator - owns sub-managers
  Managers/
    AnimationCoordinator.swift     # Pill morphs, message cascade, tool stagger
    StreamingManager.swift         # Text deltas, batching, backpressure
    MessageWindowManager.swift     # Virtual scrolling, load/unload
    UIUpdateQueue.swift            # Ordered updates, tool call sequencing
```

### Responsibility Matrix

| Component | Responsibilities |
|-----------|-----------------|
| **ChatViewModel** | Owns sub-managers, exposes unified @Published state, coordinates |
| **AnimationCoordinator** | Pill morph state machine, cascade timing, tool stagger queue |
| **StreamingManager** | Text delta batching (100ms), thinking, backpressure (10MB limit) |
| **MessageWindowManager** | Window tracking (150 max), load/unload decisions, placeholders |
| **UIUpdateQueue** | FIFO queue, tool ordering guarantees, batch coalescing |

---

## Part 1: AnimationCoordinator

### Pill Morph Sequence (Chained)
```
0ms       Context pill morphs UP from right side of input bar / mic button
+200ms    Model pill morphs UP from context pill anchor
+170ms    Reasoning pill morphs UP from model pill anchor (if supported)
```

### Key Design
```swift
@MainActor @Observable
class AnimationCoordinator {
    enum PillMorphPhase: Int {
        case dormant = 0
        case contextPillVisible = 1
        case modelPillVisible = 2
        case reasoningPillVisible = 3
    }

    // Computed visibility from phase
    var showContextPill: Bool { currentPhase.rawValue >= 1 }
    var showModelPill: Bool { currentPhase.rawValue >= 2 }
    var showReasoningPill: Bool { currentPhase.rawValue >= 3 && supportsReasoning }

    // Anchor points for matchedGeometryEffect
    // contextPill anchors to: micButton (or inputBar right edge)
    // modelPill anchors to: contextPill
    // reasoningPill anchors to: modelPill
}
```

### Message Cascade
- 20ms stagger per message (capped at 50 messages = 1 second max)
- Messages beyond cap appear instantly
- Spring animation: response 0.3, damping 0.85

### Tool Call Stagger
- Queue incoming tool starts
- 80ms between each tool appearance (capped at 200ms)
- Tool ends processed in order (later tools wait for earlier ones)

---

## Part 2: UIUpdateQueue

### Purpose
Ensure tool calls appear in order and batch UI updates for 60fps.

### Design
```swift
class UIUpdateQueue {
    // Tool call ordering
    private var toolCallOrder: [String] = []        // Order by start time
    private var completedTools: Set<String> = []
    private var pendingToolResults: [String: Update] = []

    func enqueueToolStart(toolCallId:) { ... }
    func enqueueToolEnd(toolCallId:) {
        // Only process if all earlier tools completed
        // Otherwise queue for later
    }
}
```

### Batch Interval
- 16ms (~60fps) coalescing for rapid updates
- Priority ordering: turnBoundary > toolStart > toolEnd > messageAppend > textDelta

---

## Part 3: MessageWindowManager

### Virtual Scrolling Config
```swift
static let initialLoadCount = 50
static let loadMoreCount = 30
static let maxWindowSize = 150      // Messages in memory
static let unloadThreshold = 100    // Trigger prune
static let preloadBuffer = 20       // Load ahead of scroll
```

### Window Management
- Track `windowStart` and `windowEnd` indices into full message ID list
- Load messages into `loadedMessages: [UUID: ChatMessage]` dictionary
- Prune from top when user at bottom, prune from bottom when user at top
- Placeholder views for unloaded regions (estimated height)

### Public Interface
```swift
var windowedMessages: [ChatMessage]  // Currently loaded, for ForEach
var hasMoreOlder: Bool               // Show load more button
func loadInitial(from:) async
func loadOlder(from:) async
func appendMessage(_:)               // New streaming/user message
func updateMessage(_:)               // Tool result, finalize
```

---

## Part 4: Streaming & In-Progress Sessions

### StreamingManager
- Batch text deltas every 100ms (existing behavior)
- 10MB backpressure limit (existing)
- Clean separation from ViewModel

### In-Progress Session Join Flow
1. Show latest messages immediately (no animation delay)
2. Process catch-up content (text, running tools)
3. Set up streaming state for ongoing responses
4. Load older messages in background
5. Apply cascade animation only to most recent 10 messages

---

## Part 5: InputBar Pill Animation Changes

### Current (Fade In)
Pills fade in with delays - not morphing from anchors.

### New (Chained Morph)
```swift
// In InputBar view body
HStack {
    // ... input field ...

    // Mic button (always present anchor)
    micButton
        .matchedGeometryEffect(id: "micAnchor", in: pillNamespace)

    // Context pill - morphs from mic button
    if animationCoordinator.showContextPill {
        ContextPill()
            .matchedGeometryEffect(id: "contextPill", in: pillNamespace)
            .transition(.asymmetric(
                insertion: .scale(scale: 0, anchor: .trailing).combined(with: .opacity),
                removal: .opacity
            ))
    }

    // Model pill - morphs from context pill
    if animationCoordinator.showModelPill {
        ModelPill()
            .matchedGeometryEffect(id: "modelPill", in: pillNamespace)
            .transition(.scale(scale: 0, anchor: .trailing).combined(with: .opacity))
    }

    // Reasoning pill - morphs from model pill
    if animationCoordinator.showReasoningPill {
        ReasoningPill()
            .matchedGeometryEffect(id: "reasoningPill", in: pillNamespace)
            .transition(.scale(scale: 0, anchor: .trailing).combined(with: .opacity))
    }
}
```

---

## Implementation Phases

### Phase 1: Foundation (Non-Breaking)
- [ ] Create `Sources/ViewModels/Managers/` directory
- [ ] Create empty manager files with protocols
- [ ] Add manager properties to ChatViewModel (private, unused initially)
- **Checkpoint**: Build succeeds, no behavior change

### Phase 2: AnimationCoordinator
- [ ] Implement pill morph state machine
- [ ] Extract timing constants from InputBar.swift
- [ ] Update InputBar to use AnimationCoordinator
- [ ] Implement chained anchor morphing with matchedGeometryEffect
- **Checkpoint**: Pills morph sequentially from anchors

### Phase 3: UIUpdateQueue
- [ ] Implement queue structure with priority
- [ ] Implement tool ordering guarantees
- [ ] Route `handleToolStart`/`handleToolEnd` through queue
- [ ] Add stagger timing via AnimationCoordinator
- **Checkpoint**: Multiple rapid tool calls appear in order, staggered

### Phase 4: MessageWindowManager
- [ ] Implement window tracking core
- [ ] Migrate pagination from ChatViewModel+Pagination.swift
- [ ] Implement unload logic for off-screen messages
- [ ] Add placeholder views for unloaded regions
- [ ] Update ChatView ScrollView to use windowed messages
- **Checkpoint**: Memory stays bounded with 1000+ message sessions

### Phase 5: Message Cascade Animation
- [ ] Implement cascade scheduling in AnimationCoordinator
- [ ] Apply cascade on initial session load
- [ ] Apply cascade on existing session open
- **Checkpoint**: Messages cascade in from bottom

### Phase 6: StreamingManager & Final Integration
- [ ] Extract streaming logic from ChatViewModel
- [ ] Implement in-progress session catch-up flow
- [ ] Wire up all managers in ChatViewModel
- [ ] Full regression testing
- **Checkpoint**: All features working, no regressions

---

## Files to Modify

| File | Changes |
|------|---------|
| `Sources/ViewModels/ChatViewModel.swift` | Add manager properties, delegate to managers |
| `Sources/ViewModels/ChatViewModel+Events.swift` | Route tool events through UIUpdateQueue |
| `Sources/ViewModels/ChatViewModel+Pagination.swift` | Migrate to MessageWindowManager |
| `Sources/Views/ChatView.swift` | Add namespaces, use windowed messages, cascade animation |
| `Sources/Views/InputBar.swift` | Use AnimationCoordinator, chained pill morphs |
| `Sources/Theme/TronColors.swift` | Add animation timing constants |

## New Files to Create

| File | Purpose |
|------|---------|
| `Sources/ViewModels/Managers/AnimationCoordinator.swift` | Pill/tool/cascade animations |
| `Sources/ViewModels/Managers/UIUpdateQueue.swift` | Ordered update processing |
| `Sources/ViewModels/Managers/MessageWindowManager.swift` | Virtual scrolling |
| `Sources/ViewModels/Managers/StreamingManager.swift` | Text delta batching |

---

## Verification Plan

### Unit Tests
- AnimationCoordinator phase transitions
- UIUpdateQueue tool ordering (multiple rapid starts/ends)
- MessageWindowManager window bounds after load/unload

### Manual Testing
1. **Pill morph**: Open new chat, verify pills chain-morph up sequentially
2. **Tool stagger**: Trigger multi-tool response, verify staggered appearance
3. **Cascade load**: Open existing session with 100+ messages, verify cascade
4. **Virtual scroll**: Open session with 500+ messages, verify memory stays bounded
5. **In-progress join**: Start long response, close/reopen, verify seamless continuation
6. **Scroll to bottom**: Always land at bottom gracefully when opening session

### Performance
- Profile memory with 1000 message session (should stay <50MB for messages)
- Profile scroll performance (should maintain 60fps)
- Profile cascade animation (no frame drops)
