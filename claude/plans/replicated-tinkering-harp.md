# Fix: RenderAppUI "Canvas Not Found" During Active Session

## Problem
When tapping a RenderAppUI chip during an active streaming session, the error "Canvas not found" appears. However, if the user navigates away and returns, tapping the same chip works correctly.

## Analysis: Other Interactive Chips

Verified that other interactive chips don't have this issue:

| Chip | Pattern | Issue? |
|------|---------|--------|
| **RenderAppUI** | Loads external state (canvas content) | **YES** |
| **Subagent** | Self-heals: adds chip data to state if missing | No |
| **TodoWrite** | State populated by events, no lookup | No |
| **NotifyApp** | Chip data passed directly | No |
| **AskUserQuestion** | Chip data passed directly | No |

RenderAppUI is unique because chip data only contains metadata (canvasId, title, status), while actual UI content is stored separately in `UICanvasState.canvases`.

## Root Cause
Race condition between `tool_start` and `ui_render_chunk` events causes canvas state to not be created.

**Event handling paths for RenderAppUI:**

| Event | Creates Chip? | Calls `startRender()`? |
|-------|--------------|------------------------|
| `ui_render_start` | Yes | ✅ Yes |
| `ui_render_chunk` (first) | Yes | ✅ Yes (only if no chip exists) |
| `tool_start` | Yes | ❌ **No** |

**Bug scenario:**
1. `tool_start` arrives first → creates chip, sets `renderAppUIChipMessageIds[canvasId]`
2. Does NOT call `startRender()` → **canvas not in `UICanvasState.canvases`**
3. `ui_render_chunk` arrives → checks `renderAppUIChipMessageIds[canvasId]` → not nil
4. **Skips** the block that would call `startRender()`
5. Calls `updateRender()` → logs warning, returns (canvas doesn't exist)
6. User taps chip → `loadFromServer()` → `canvases[canvasId]` is nil → server fetch → not persisted yet → "Canvas not found"

## Fix

**File:** `packages/ios-app/Sources/ViewModels/ChatViewModel+Events.swift`

**Change:** In `handleUIRenderChunk()`, ensure canvas state exists before calling `updateRender()`, regardless of whether the chip already exists.

```swift
func handleUIRenderChunk(_ event: UIRenderChunkEvent) {
    // ... existing chip creation logic (lines 810-843) ...

    // NEW: Ensure canvas exists even if chip was created by tool_start
    // This handles the race condition where tool_start arrives before ui_render_chunk
    if !uiCanvasState.hasCanvas(event.canvasId) {
        let title = extractTitleFromAccumulated(event.accumulated)
        let toolCallId = getToolCallIdForCanvas(event.canvasId) ?? "pending_\(event.canvasId)"
        uiCanvasState.startRender(
            canvasId: event.canvasId,
            title: title,
            toolCallId: toolCallId
        )
        logger.info("Created canvas state for existing chip: \(event.canvasId)", category: .events)
    }

    // Update the canvas with the new chunk
    uiCanvasState.updateRender(...)
}
```

**File:** `packages/ios-app/Sources/ViewModels/State/UICanvasState.swift`

**Add helper method:**
```swift
/// Check if a canvas exists in memory
func hasCanvas(_ canvasId: String) -> Bool {
    canvases[canvasId] != nil
}
```

**File:** `packages/ios-app/Sources/ViewModels/ChatViewModel+Events.swift`

**Add helper method:**
```swift
/// Get the toolCallId for an existing RenderAppUI chip
private func getToolCallIdForCanvas(_ canvasId: String) -> String? {
    guard let messageId = renderAppUIChipMessageIds[canvasId],
          let message = messages.first(where: { $0.id == messageId }),
          case .renderAppUI(let data) = message.content else {
        return nil
    }
    return data.toolCallId
}
```

## Files to Modify
1. `packages/ios-app/Sources/ViewModels/ChatViewModel+Events.swift` - Add canvas existence check in `handleUIRenderChunk()`
2. `packages/ios-app/Sources/ViewModels/State/UICanvasState.swift` - Add `hasCanvas()` helper

## Verification
1. Run `bun run build && bun run test` to ensure no regressions
2. Test in iOS app:
   - Ask agent to use RenderAppUI tool
   - While streaming, tap the chip immediately when it appears
   - Should open canvas sheet without "Canvas not found" error
   - Verify chip remains tappable after completion
   - Verify leaving/returning to session still works
