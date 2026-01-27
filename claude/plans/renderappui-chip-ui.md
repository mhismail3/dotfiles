# RenderAppUI Chip-Based UI Implementation

## Goal

Display RenderAppUI tool calls as chips in the chat view (like SpawnSubagent), with:
- Amber chip with spinner during rendering: "Rendering app..."
- Green chip when complete: "App Rendered"
- Auto-show canvas sheet when tool called
- Tap chip to reopen sheet anytime
- **MUST persist on session reconstruction** (resume/fork)

---

## Current Architecture

```
RenderAppUI Tool Called
       ↓
agent-event-handler.ts emits ui_render_start/complete/error
       ↓
iOS: UICanvasState (ephemeral) manages sheet
       ↓
Tool message shows as generic ".toolUse" in chat
       ↓
On session resume: Canvas data LOST (not persisted)
```

## Target Architecture

```
RenderAppUI Tool Called
       ↓
agent-event-handler.ts emits events (unchanged)
       ↓
iOS: Convert ".toolUse" message to ".uiCanvas(UICanvasToolData)"
       ↓
UICanvasChip renders in chat with status colors
       ↓
Tap chip → opens UICanvasSheet
       ↓
On session resume: Parse tool arguments → reconstruct UICanvasToolData
```

---

## Implementation Plan

### Step 1: Create UICanvasToolData Model

**File:** `packages/ios-app/Sources/Models/UICanvas.swift`

Add data model for chip display (similar to `SubagentToolData`):

```swift
/// Data for UI canvas chip display in chat
struct UICanvasToolData: Equatable, Identifiable {
    let id: String           // toolCallId
    let canvasId: String
    let title: String?
    var status: UICanvasChipStatus
    var ui: UICanvasComponent?
    var state: [String: AnyCodable]

    enum UICanvasChipStatus: Equatable {
        case rendering
        case retrying(attempt: Int)
        case complete
        case error(String)
    }
}
```

### Step 2: Create UICanvasChip View

**File:** `packages/ios-app/Sources/Views/UICanvasChip.swift` (NEW)

Model after `SubagentChip.swift`:

```swift
struct UICanvasChip: View {
    let data: UICanvasToolData
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                statusIcon
                Text(statusText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(statusColor.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch data.status {
        case .rendering, .retrying:
            ProgressView().scaleEffect(0.7).tint(statusColor)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    private var statusText: String {
        switch data.status {
        case .rendering: return "Rendering app..."
        case .retrying(let attempt): return "Fixing issues (\(attempt)/3)..."
        case .complete: return data.title ?? "App Rendered"
        case .error: return "Render Failed"
        }
    }

    private var statusColor: Color {
        switch data.status {
        case .rendering, .retrying: return .tronWarning  // Amber
        case .complete: return .tronSuccess              // Green
        case .error: return .tronError                   // Red
        }
    }
}
```

### Step 3: Add MessageContent Case

**File:** `packages/ios-app/Sources/Models/ChatMessage.swift`

Add new case to `MessageContent` enum:

```swift
enum MessageContent: Equatable, Identifiable {
    // ... existing cases
    case toolUse(ToolCallInfo)
    case subagent(SubagentToolData)
    case uiCanvas(UICanvasToolData)  // ← NEW
    // ...
}
```

### Step 4: Create UICanvasState Extension for Chip Data

**File:** `packages/ios-app/Sources/ViewModels/State/UICanvasState.swift`

Add method to get chip data and handle chip tap:

```swift
extension UICanvasState {
    /// Get chip data for a canvas
    func getChipData(canvasId: String, toolCallId: String) -> UICanvasToolData? {
        guard let canvas = canvases[canvasId] else { return nil }

        let chipStatus: UICanvasToolData.UICanvasChipStatus
        switch canvas.status {
        case .rendering: chipStatus = .rendering
        case .retrying(let attempt, _): chipStatus = .retrying(attempt: attempt)
        case .complete: chipStatus = .complete
        case .error(let msg): chipStatus = .error(msg)
        }

        return UICanvasToolData(
            id: toolCallId,
            canvasId: canvasId,
            title: canvas.title,
            status: chipStatus,
            ui: canvas.parsedRoot,
            state: canvas.state
        )
    }

    /// Show canvas for a chip tap
    func showCanvas(canvasId: String) {
        activeCanvasId = canvasId
        showSheet = true
    }
}
```

### Step 5: Update Message Conversion (Key Step)

**File:** `packages/ios-app/Sources/ViewModels/ChatViewModel+Events.swift`

Add method to convert tool messages to canvas chips (like `updateToolMessageToSubagentChip`):

```swift
/// Convert a RenderAppUI tool message to a canvas chip
func updateToolMessageToCanvasChip(toolCallId: String, canvasId: String) {
    uiUpdateQueue.enqueue(toolCallId: toolCallId) { [weak self] in
        guard let self else { return }

        // Find the message with this tool call
        guard let index = messages.firstIndex(where: { msg in
            msg.content.contains { content in
                if case .toolUse(let info) = content, info.id == toolCallId {
                    return true
                }
                return false
            }
        }) else {
            logger.warning("Could not find message for tool call: \(toolCallId)", category: .events)
            return
        }

        // Get chip data from canvas state
        guard let chipData = uiCanvasState.getChipData(canvasId: canvasId, toolCallId: toolCallId) else {
            logger.warning("Could not get chip data for canvas: \(canvasId)", category: .events)
            return
        }

        // Replace .toolUse with .uiCanvas
        var updatedContent = messages[index].content
        if let contentIndex = updatedContent.firstIndex(where: { content in
            if case .toolUse(let info) = content, info.id == toolCallId {
                return true
            }
            return false
        }) {
            updatedContent[contentIndex] = .uiCanvas(chipData)
            messages[index].content = updatedContent
            logger.info("Converted tool message to canvas chip: \(canvasId)", category: .events)
        }
    }
}

/// Update existing canvas chip status
func updateCanvasChipStatus(toolCallId: String, canvasId: String) {
    guard let chipData = uiCanvasState.getChipData(canvasId: canvasId, toolCallId: toolCallId) else {
        return
    }

    // Find and update the chip
    for i in messages.indices {
        for j in messages[i].content.indices {
            if case .uiCanvas(var data) = messages[i].content[j], data.canvasId == canvasId {
                data.status = chipData.status
                data.ui = chipData.ui
                messages[i].content[j] = .uiCanvas(data)
                return
            }
        }
    }
}
```

### Step 6: Wire Up Event Handlers

**File:** `packages/ios-app/Sources/ViewModels/ChatViewModel+Events.swift`

Update existing handlers to convert to chips:

```swift
func handleUIRenderStart(_ event: UIRenderStartEvent) {
    // Existing: update canvas state
    uiCanvasState.startRender(canvasId: event.canvasId, title: event.title, toolCallId: event.toolCallId)

    // NEW: Convert tool message to chip
    updateToolMessageToCanvasChip(toolCallId: event.toolCallId, canvasId: event.canvasId)
}

func handleUIRenderComplete(_ event: UIRenderCompleteEvent) {
    // Existing: complete canvas
    if let ui = UICanvasComponent.decode(from: event.ui) {
        uiCanvasState.completeRender(canvasId: event.canvasId, ui: ui, state: event.state)
    }

    // NEW: Update chip status
    updateCanvasChipStatus(toolCallId: event.toolCallId, canvasId: event.canvasId)
}

func handleUIRenderRetry(_ event: UIRenderRetryEvent) {
    // Existing: set retry status
    uiCanvasState.setRetrying(canvasId: event.canvasId, attempt: event.attempt, errors: event.errors)

    // NEW: Update chip status (find by canvasId since toolCallId changes on retry)
    updateCanvasChipInAllMessages(canvasId: event.canvasId)
}

func handleUIRenderError(_ event: UIRenderErrorEvent) {
    // Existing: set error
    uiCanvasState.errorRender(canvasId: event.canvasId, error: event.error)

    // NEW: Update chip status
    updateCanvasChipStatus(toolCallId: event.toolCallId, canvasId: event.canvasId)
}
```

### Step 7: Render Chip in MessageBubble

**File:** `packages/ios-app/Sources/Views/MessageBubble/MessageBubble.swift`

Add rendering case:

```swift
case .uiCanvas(let data):
    UICanvasChip(data: data) {
        viewModel.uiCanvasState.showCanvas(canvasId: data.canvasId)
    }
```

### Step 8: Session Reconstruction (CRITICAL)

**File:** `packages/ios-app/Sources/Views/MessageBubble/MessageBubble.swift`

Add parsing for session resume (like `createSubagentToolData`):

```swift
/// Create UICanvasToolData from persisted tool result
private func createCanvasToolData(from toolInfo: ToolCallInfo) -> UICanvasToolData? {
    // Parse canvasId from tool arguments
    guard let argsData = toolInfo.arguments?.data(using: .utf8),
          let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any],
          let canvasId = args["canvasId"] as? String else {
        return nil
    }

    let title = args["title"] as? String

    // Determine status from tool result
    let status: UICanvasToolData.UICanvasChipStatus
    if toolInfo.isError {
        status = .error(toolInfo.result ?? "Unknown error")
    } else if toolInfo.result != nil {
        status = .complete
    } else {
        status = .rendering
    }

    // Parse UI from arguments if complete
    var ui: UICanvasComponent? = nil
    if status == .complete, let uiDict = args["ui"] as? [String: Any] {
        ui = UICanvasComponent.decode(from: uiDict)
    }

    // Parse state from arguments
    var state: [String: AnyCodable] = [:]
    if let stateDict = args["state"] as? [String: Any] {
        state = stateDict.mapValues { AnyCodable($0) }
    }

    return UICanvasToolData(
        id: toolInfo.id,
        canvasId: canvasId,
        title: title,
        status: status,
        ui: ui,
        state: state
    )
}
```

Update `renderToolUse` to check for RenderAppUI:

```swift
@ViewBuilder
private func renderToolUse(_ toolInfo: ToolCallInfo) -> some View {
    // Check for SpawnSubsession (existing)
    if toolInfo.name == "SpawnSubsession",
       let subagentData = createSubagentToolData(from: toolInfo) {
        SubagentChip(data: subagentData) { ... }
    }
    // Check for RenderAppUI (NEW)
    else if toolInfo.name == "RenderAppUI",
            let canvasData = createCanvasToolData(from: toolInfo) {
        UICanvasChip(data: canvasData) {
            viewModel.uiCanvasState.showCanvas(canvasId: canvasData.canvasId)
        }
    }
    // Default tool rendering
    else {
        // ... existing default rendering
    }
}
```

### Step 9: Restore Canvas State on Reconstruction

When reconstructing from persisted data, also restore UICanvasState:

```swift
// In createCanvasToolData or a separate restore method
private func restoreCanvasState(from data: UICanvasToolData) {
    // Restore canvas to UICanvasState so sheet can be shown
    if data.status == .complete, let ui = data.ui {
        viewModel.uiCanvasState.restoreCanvas(
            canvasId: data.canvasId,
            title: data.title,
            toolCallId: data.id,
            ui: ui,
            state: data.state
        )
    }
}
```

Add restore method to UICanvasState:

```swift
/// Restore a canvas from persisted data (session reconstruction)
func restoreCanvas(canvasId: String, title: String?, toolCallId: String, ui: UICanvasComponent, state: [String: AnyCodable]) {
    let canvas = UICanvasData(
        canvasId: canvasId,
        title: title,
        toolCallId: toolCallId,
        status: .complete,
        parsedRoot: ui,
        state: state
    )
    canvases[canvasId] = canvas
    logger.info("Canvas restored from session: \(canvasId)", category: .ui)
}
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `packages/ios-app/Sources/Models/UICanvas.swift` | Add `UICanvasToolData` struct |
| `packages/ios-app/Sources/Views/UICanvasChip.swift` | NEW - Chip view component |
| `packages/ios-app/Sources/Models/ChatMessage.swift` | Add `.uiCanvas` case to `MessageContent` |
| `packages/ios-app/Sources/ViewModels/State/UICanvasState.swift` | Add `getChipData`, `showCanvas`, `restoreCanvas` |
| `packages/ios-app/Sources/ViewModels/ChatViewModel+Events.swift` | Add chip conversion methods, update handlers |
| `packages/ios-app/Sources/Views/MessageBubble/MessageBubble.swift` | Add chip rendering, session reconstruction |

---

## Flow Diagrams

### Live Session Flow
```
RenderAppUI tool called
       ↓
ui_render_start event
       ↓
UICanvasState.startRender() + updateToolMessageToCanvasChip()
       ↓
Chat shows: [Amber chip: "Rendering app..." with spinner]
       ↓
Sheet auto-opens (existing behavior)
       ↓
ui_render_complete event
       ↓
UICanvasState.completeRender() + updateCanvasChipStatus()
       ↓
Chat shows: [Green chip: "App Rendered"]
       ↓
Tap chip → showCanvas() → Sheet opens
```

### Session Reconstruction Flow
```
Resume/Fork session
       ↓
Load persisted messages with .toolUse(RenderAppUI)
       ↓
MessageBubble.renderToolUse() detects "RenderAppUI"
       ↓
createCanvasToolData() parses tool arguments
       ↓
Renders UICanvasChip with reconstructed data
       ↓
restoreCanvasState() populates UICanvasState
       ↓
Tap chip → showCanvas() → Sheet shows persisted UI
```

---

## Verification

1. **New session**: Ask agent to render UI
   - Chip appears amber with spinner
   - Sheet auto-opens
   - Chip turns green on complete
   - Tap chip reopens sheet

2. **Session resume**:
   - Resume session with RenderAppUI in history
   - Chip displays correctly (green if completed)
   - Tap chip opens sheet with persisted UI

3. **Session fork**:
   - Fork session at point after RenderAppUI
   - Same behavior as resume

4. **Retry flow**:
   - Trigger validation failure
   - Chip shows "Fixing issues (1/3)..."
   - Updates to green on success

5. **Error handling**:
   - Trigger max retries
   - Chip shows red "Render Failed"
   - Sheet shows error view

---

## Risk Assessment

- **Medium complexity**: Follows established SubagentChip pattern closely
- **Session reconstruction is critical**: Must parse tool arguments correctly
- **State synchronization**: UICanvasState and chip data must stay in sync
