# RenderAppUI Chip Implementation Plan

## Goal
Create an interactive chip in the chat view for RenderAppUI tool calls, modeled after the SpawnSubagent chip. The chip shows rendering state (amber/spinner while rendering, green when complete), allows tapping to show the canvas sheet, and persists correctly on session reconstruction.

## Files to Modify

### 1. `packages/ios-app/Sources/Models/Message.swift`
**Add new types and MessageContent case:**

```swift
// New status enum
enum RenderAppUIStatus: String, Equatable {
    case rendering
    case retrying
    case complete
    case error
}

// New chip data struct (similar to SubagentToolData)
struct RenderAppUIChipData: Equatable {
    let toolCallId: String
    let canvasId: String
    let title: String?
    var status: RenderAppUIStatus
    var retryAttempt: Int?
    var errorMessage: String?

    var displayTitle: String {
        title ?? "App"
    }
}

// Add to MessageContent enum:
case renderAppUI(RenderAppUIChipData)

// Add to textContent switch:
case .renderAppUI(let data):
    switch data.status {
    case .rendering: return "Rendering \(data.displayTitle)..."
    case .retrying: return "Retrying \(data.displayTitle)..."
    case .complete: return "\(data.displayTitle) rendered"
    case .error: return "Render failed"
    }
```

### 2. `packages/ios-app/Sources/Views/RenderAppUIChip.swift` (new file)
**Create chip view following SubagentChip pattern:**

- **Rendering state:** Amber tint, spinner, "Rendering app..."
- **Retrying state:** Amber/warning tint, spinner, "Retrying... (attempt N)"
- **Complete state:** Green tint (`.tronSuccess`), checkmark, "App Rendered"
- **Error state:** Red tint (`.tronError`), X icon, "Render Failed"
- Chevron indicator for tappability
- Glass effect (iOS 26+) with fallback for older iOS

### 3. `packages/ios-app/Sources/Views/MessageBubble/MessageBubble.swift`
**Add chip rendering and tap handling:**

```swift
// Add callback property:
var onRenderAppUITap: ((RenderAppUIChipData) -> Void)?

// Add case in contentView switch for tool routing:
case "renderappui":
    if let chipData = createRenderAppUIChipData(from: tool) {
        // Render chip
    }

// Add case for persisted .renderAppUI content:
case .renderAppUI(let data):
    if #available(iOS 26.0, *) {
        RenderAppUIChip(data: data) { onRenderAppUITap?(data) }
    } else {
        RenderAppUIChipFallback(data: data) { onRenderAppUITap?(data) }
    }

// Add helper function to parse tool data:
private func createRenderAppUIChipData(from tool: ToolUseData) -> RenderAppUIChipData?
```

### 4. `packages/ios-app/Sources/ViewModels/ChatViewModel+Events.swift`
**Update UI render event handlers to manage chip messages:**

Add tracking dictionary:
```swift
// In ChatViewModel:
private var renderAppUIChipMessageIds: [String: UUID] = [:]  // canvasId → messageId
```

Modify `handleUIRenderStart`:
1. Create `RenderAppUIChipData` with `.rendering` status
2. Find existing RenderAppUI tool message by `toolCallId` and convert to `.renderAppUI` content
3. Store message ID in tracking dictionary
4. Continue with existing `uiCanvasState.startRender()` call

Modify `handleUIRenderComplete`:
1. Find chip message by canvasId
2. Update chip status to `.complete`

Modify `handleUIRenderError`:
1. Find chip message by canvasId
2. Update chip status to `.error` with message

Modify `handleUIRenderRetry`:
1. Find chip message by canvasId
2. Update chip status to `.retrying` with attempt number

### 5. `packages/ios-app/Sources/Views/ChatView.swift`
**Wire up chip tap to show sheet:**

Add tap handler to MessageBubble:
```swift
onRenderAppUITap: { data in
    viewModel.uiCanvasState.activeCanvasId = data.canvasId
    viewModel.uiCanvasState.showSheet = true
}
```

### 6. `packages/ios-app/Sources/ViewModels/State/UICanvasState.swift`
**Add helper to get chip data from canvas state:**

```swift
func getChipData(for canvasId: String, toolCallId: String) -> RenderAppUIChipData? {
    guard let canvas = canvases[canvasId] else { return nil }

    let status: RenderAppUIStatus = switch canvas.status {
        case .rendering: .rendering
        case .retrying: .retrying
        case .complete: .complete
        case .error: .error
    }

    return RenderAppUIChipData(
        toolCallId: toolCallId,
        canvasId: canvasId,
        title: canvas.title,
        status: status,
        retryAttempt: canvas.retryAttempt,
        errorMessage: canvas.errorMessage
    )
}
```

## Reconstruction Strategy

On session resume, the chip reconstructs through **two paths** (same as SubagentChip):

1. **If message content is `.renderAppUI(...)`** → Render directly from persisted content
2. **If message content is `.toolUse(...)` with toolName "RenderAppUI"** → `createRenderAppUIChipData(from:)` parses the tool result to determine status

The `createRenderAppUIChipData` function should:
- Parse arguments to extract `canvasId` and `title`
- Determine status from tool.status (running/success/error)
- Return chip data for rendering

## Verification Steps

1. **Live rendering test:**
   - Send message that triggers RenderAppUI tool
   - Verify chip appears with amber color and "Rendering app..." text
   - Verify sheet auto-opens
   - Dismiss sheet, tap chip → sheet reopens
   - On completion → chip turns green "App Rendered"
   - Tap completed chip → see rendered app

2. **Error/retry test:**
   - Trigger RenderAppUI with invalid UI
   - Verify chip shows retry state
   - On final error → chip shows red error state

3. **Persistence test:**
   - Complete a render, close app
   - Reopen → chip shows green "App Rendered"
   - Tap chip → canvas content displays

4. **Session resume test:**
   - Resume an existing session with rendered app
   - Verify chip reconstructs correctly with green state
   - Tap chip → see the rendered app

5. **Fork test:**
   - Fork session at a point after render
   - Verify chip preserved with correct state
