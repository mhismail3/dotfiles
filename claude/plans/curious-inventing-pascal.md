# Thinking Display Feature - Implementation Plan

## Objective
Add a caption-style thinking indicator (max 3 lines) that streams in real-time during agent processing. Tapping it opens a sheet showing full thinking content and history. Only visible for models that support thinking.

**Critical Requirements (User Specified):**
1. **Database Persistence** - Thinking blocks persisted to DB like all other events
2. **Lazy Loading** - Show first few lines on resume; load full content on-demand in sheet
3. **Memory Efficiency** - Single buffer for sheet content; clear and replace when switching blocks

---

## Architecture Overview

### Current State
- `agent.thinking_delta` is a **streaming-only** event (NOT persisted)
- `stream.thinking_delta` **IS** a persisted event type (defined but may not be used)
- Events stored in SQLite: `EventDatabase.insertEvent()` with `session_id`, `type`, `payload`
- Events loaded via `EventDatabase.getEventsBySession(sessionId)`
- No turn correlation for thinking - just accumulates in one string
- At turn end, consolidated into `message.assistant` (but thinking content may be lost)

### Key Insight
To persist thinking properly, we consolidate thinking per turn into a `stream.thinking_complete` event (similar to how text deltas become `message.assistant`). This:
- Keeps event count manageable (1 event per turn, not 100s of deltas)
- Enables efficient lazy loading (preview in listing, full on demand)
- Fits existing event architecture patterns

---

## Data Flow

```
Live Streaming:
  Server → agent.thinking_delta → StreamingManager → ThinkingState.currentText

Turn End:
  ThinkingState.endTurn() → Insert stream.thinking_complete event to DB

Session Resume:
  Load events → Filter stream.thinking_complete → ThinkingState.history (previews only)

Sheet Open:
  User taps block → Load full content from DB into single buffer
  User taps different block → Clear buffer, load new content
```

---

## Implementation

### Phase 1: Event & Persistence

#### 1.1 ThinkingCompleteEvent (NEW)
**File**: `Sources/Models/Payloads/ThinkingCompletePayload.swift`

```swift
struct ThinkingCompletePayload: Codable {
    let turnNumber: Int
    let content: String           // Full thinking text
    let preview: String           // First 3 lines for captions
    let characterCount: Int       // For display
    let model: String?
    let timestamp: Date
}
```

#### 1.2 Register Event Type
**File**: `Sources/Models/EventTypeRegistry.swift`

Add `stream.thinking_complete` to `PersistedEventType` enum.

#### 1.3 Database Query Method (NEW)
**File**: `Sources/Database/EventDatabase.swift`

```swift
/// Load thinking events with preview-only mode for efficiency
func getThinkingEvents(sessionId: String, previewOnly: Bool = true) throws -> [ThinkingCompletePayload]
```

---

### Phase 2: State Management

#### 2.1 ThinkingBlock Model (NEW)
**File**: `Sources/Models/ThinkingBlock.swift`

```swift
struct ThinkingBlock: Identifiable {
    let id: UUID                  // Event ID in DB
    let turnNumber: Int
    let preview: String           // First 3 lines (always loaded)
    let characterCount: Int
    let model: String?
    let timestamp: Date

    // Full content NOT stored here - loaded on demand into shared buffer
}
```

#### 2.2 ThinkingState (NEW)
**File**: `Sources/ViewModels/State/ThinkingState.swift`

```swift
@Observable
@MainActor
final class ThinkingState {
    // === Live Streaming ===
    private(set) var currentText: String = ""
    private(set) var isStreaming: Bool = false
    private var currentTurnNumber: Int = 0
    private var currentModel: String?

    // === History (lightweight) ===
    private(set) var blocks: [ThinkingBlock] = []   // Preview data only

    // === Sheet State ===
    var showSheet: Bool = false
    private(set) var selectedBlockId: UUID?
    private(set) var loadedFullContent: String = "" // Single buffer, reused
    private(set) var isLoadingContent: Bool = false

    // === Dependencies ===
    private weak var eventDatabase: EventDatabase?

    // === Methods ===
    func handleThinkingDelta(_ delta: String)
    func startTurn(_ turnNumber: Int, model: String?)
    func endTurn() async                            // Persists to DB
    func loadHistory(sessionId: String) async       // On session resume
    func loadFullContent(blockId: UUID) async       // Lazy load for sheet
    func clearCurrentStreaming()
    func clearAll()

    // === Computed ===
    var captionText: String { /* first 3 lines of currentText */ }
    var shouldShowCaption: Bool { !currentText.isEmpty && isStreaming }
}
```

**Memory Model:**
- `blocks` array holds only preview strings (~500 chars each max)
- `loadedFullContent` is the single full-text buffer
- When user taps different block: clear buffer, load new content
- Total memory: O(n * preview_size) + O(1 * full_content_size)

---

### Phase 3: UI Components

#### 3.1 ThinkingCaption (NEW)
**File**: `Sources/Views/ThinkingCaption.swift`

```swift
struct ThinkingCaption: View {
    @Bindable var thinkingState: ThinkingState

    var body: some View {
        Button { thinkingState.showSheet = true } label: {
            HStack(spacing: 8) {
                RotatingIcon(icon: .thinking)
                Text(thinkingState.captionText)
                    .lineLimit(3)
                    .font(TronTypography.caption)
                    .italic()
                    .foregroundStyle(.tronPurple)
                Image(systemName: "chevron.up.circle")
                    .foregroundStyle(.tronPurple)
            }
            .padding(12)
            .glassBackground()
        }
    }
}
```

#### 3.2 ThinkingDetailSheet (NEW)
**File**: `Sources/Views/ThinkingDetailSheet.swift`

```swift
struct ThinkingDetailSheet: View {
    @Bindable var thinkingState: ThinkingState

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Current streaming (if active)
                    if thinkingState.isStreaming {
                        CurrentThinkingSection(text: thinkingState.currentText)
                    }

                    // History blocks
                    ForEach(thinkingState.blocks) { block in
                        ThinkingBlockCard(
                            block: block,
                            isSelected: block.id == thinkingState.selectedBlockId,
                            loadedContent: thinkingState.loadedFullContent,
                            isLoading: thinkingState.isLoadingContent
                        ) {
                            Task { await thinkingState.loadFullContent(blockId: block.id) }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Thinking")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium, .large])
        }
    }
}
```

#### 3.3 ThinkingBlockCard (Helper)
```swift
struct ThinkingBlockCard: View {
    let block: ThinkingBlock
    let isSelected: Bool
    let loadedContent: String
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Turn N • Model • Timestamp
            HStack {
                Text("Turn \(block.turnNumber)")
                if let model = block.model { Text("•"); Text(model) }
                Spacer()
                Text(block.timestamp.formatted(.relative))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Content: preview or full (if selected)
            if isSelected {
                if isLoading {
                    ProgressView()
                } else {
                    Text(loadedContent)
                        .font(TronTypography.messageBody)
                        .textSelection(.enabled)
                }
            } else {
                Text(block.preview)
                    .font(TronTypography.messageBody)
                    .lineLimit(3)
            }

            // Expand indicator
            if !isSelected {
                Text("\(block.characterCount) characters • Tap to expand")
                    .font(.caption2)
                    .foregroundStyle(.tronPurple)
            }
        }
        .padding()
        .glassBackground()
        .onTapGesture(perform: onTap)
    }
}
```

---

### Phase 4: Integration

#### 4.1 ChatViewModel Changes
**File**: `Sources/ViewModels/ChatViewModel.swift`

```swift
// Add:
let thinkingState: ThinkingState

init(...) {
    self.thinkingState = ThinkingState(eventDatabase: eventDatabase)
}

// In loadSession():
await thinkingState.loadHistory(sessionId: session.id)
```

#### 4.2 Event Handler Updates
**File**: `Sources/ViewModels/ChatViewModel+Events.swift`

| Event | Handler |
|-------|---------|
| `agent.thinking_delta` | `thinkingState.handleThinkingDelta(delta)` |
| `agent.turn_start` | `thinkingState.startTurn(turnNumber, model: currentModel)` |
| `agent.turn_end` | `await thinkingState.endTurn()` ← persists to DB |
| `agent.complete` | `thinkingState.clearCurrentStreaming()` |
| `agent.error` | `thinkingState.clearCurrentStreaming()` |

#### 4.3 ChatView Changes
**File**: `Sources/Views/ChatView.swift`

Replace ThinkingBanner with:
```swift
if viewModel.thinkingState.shouldShowCaption && currentModelInfo?.supportsThinking == true {
    ThinkingCaption(thinkingState: viewModel.thinkingState)
}
```

Add sheet:
```swift
.sheet(isPresented: $viewModel.thinkingState.showSheet) {
    ThinkingDetailSheet(thinkingState: viewModel.thinkingState)
}
```

---

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Session resume | Load previews from `stream.thinking_complete` events |
| Empty thinking turn | Skip persisting, no block added |
| Sheet open during streaming | Show current streaming section + history |
| Memory pressure | Only 1 full content in memory at a time |
| Rapid block switching | Cancel pending load, clear buffer, load new |
| Model doesn't support thinking | Caption not shown (capability check) |

---

## Files Summary

### New Files (5)
1. `Sources/Models/ThinkingBlock.swift` - Lightweight block model
2. `Sources/Models/Payloads/ThinkingCompletePayload.swift` - DB payload
3. `Sources/ViewModels/State/ThinkingState.swift` - State manager
4. `Sources/Views/ThinkingCaption.swift` - Compact caption
5. `Sources/Views/ThinkingDetailSheet.swift` - Full sheet with lazy loading

### Modified Files (4)
1. `Sources/Database/EventDatabase.swift` - Add `getThinkingEvents()`
2. `Sources/Models/EventTypeRegistry.swift` - Add `stream.thinking_complete`
3. `Sources/ViewModels/ChatViewModel.swift` - Add thinkingState
4. `Sources/ViewModels/ChatViewModel+Events.swift` - Route events
5. `Sources/Views/ChatView.swift` - Replace banner, add sheet

---

## Implementation Order

1. Add `stream.thinking_complete` to EventTypeRegistry
2. Create `ThinkingCompletePayload` and `ThinkingBlock` models
3. Add `getThinkingEvents()` to EventDatabase
4. Create `ThinkingState` with streaming + persistence + lazy loading
5. Create `ThinkingCaption` component
6. Create `ThinkingDetailSheet` with `ThinkingBlockCard`
7. Integrate into ChatViewModel (init, event handlers)
8. Integrate into ChatView (replace banner, add sheet)
9. Build and test

---

## Verification

### Automated
```bash
bun run build && bun run test
```

### Manual Testing
- [ ] Send message with Claude 4.5 → thinking caption appears (max 3 lines)
- [ ] Tap caption → sheet opens with current streaming
- [ ] Turn ends → thinking persisted to DB
- [ ] Force quit app, reopen → session shows thinking history
- [ ] Tap history block → full content lazy loads (single buffer)
- [ ] Tap different block → buffer cleared, new content loads
- [ ] Switch to non-thinking model → caption disappears
- [ ] Empty thinking turn → no block persisted

---

## Memory Model

```
ThinkingState memory usage:
├── blocks: [ThinkingBlock]           ~500 chars × N turns (previews)
├── currentText: String               ~up to 1MB (streaming, cleared after turn)
└── loadedFullContent: String         ~up to 1MB (single block, cleared on switch)

Peak memory: ~2MB (streaming + one expanded block)
Steady state: ~N × 500 chars (just previews)
```
