# TodoWrite Chip Rendering

## Summary

Add a compact chip rendering for the TodoWrite tool (similar to SubagentChip, AskUserQuestionToolViewer). The chip displays "Tasks Updated" with optional counts "(X new, Y done)" and is tappable to open the TodoDetailSheet.

---

## Implementation

### 1. Create TodoWriteChip Component

**File:** `packages/ios-app/Sources/Views/TodoWriteChip.swift` (new)

Create a chip component following the pattern of SubagentChip:
- Slate colored (`.tronSlate`) to match the popup text style
- Shows "Tasks Updated" text
- Optional count badges: "(3 new)" if pending+inProgress > 0, "(2 done)" if completed > 0
- Checklist icon
- Chevron to indicate tappable
- iOS 26 glass effect + fallback for older iOS

**Chip text logic:**
- Base: "Tasks Updated"
- If `newCount > 0`: append "(X new)"
- If `doneCount > 0`: append "(Y done)"
- Both: "(X new, Y done)"

### 2. Add TodoWriteChipData Struct

**File:** `packages/ios-app/Sources/Models/Message.swift`

Add data struct for the chip:
```swift
struct TodoWriteChipData: Equatable {
    let toolCallId: String
    let newCount: Int      // pending + in_progress
    let doneCount: Int     // completed
    let totalCount: Int
}
```

### 3. Update MessageBubble to Route TodoWrite

**File:** `packages/ios-app/Sources/Views/MessageBubble/MessageBubble.swift`

Add to the `toolUse` switch case (around line 85):
```swift
case "todowrite":
    if let chipData = createTodoWriteChipData(from: tool) {
        if #available(iOS 26.0, *) {
            TodoWriteChip(data: chipData) {
                onTodoWriteTap?()
            }
        } else {
            TodoWriteChipFallback(data: chipData) {
                onTodoWriteTap?()
            }
        }
    } else {
        ToolResultRouter(tool: tool)
    }
```

Add helper to parse the tool result:
```swift
private func createTodoWriteChipData(from tool: ToolUseData) -> TodoWriteChipData? {
    // Parse "X completed, Y in progress, Z pending" from result
    // Extract counts using regex
}
```

Add callback property:
```swift
var onTodoWriteTap: (() -> Void)?
```

### 4. Wire Up Tap Handler in ChatView

**File:** `packages/ios-app/Sources/Views/ChatView.swift`

Pass the tap handler through MessageBubble:
```swift
onTodoWriteTap: {
    viewModel.showTodoSheet = true
}
```

### 5. Parse Tool Result for Counts

Parse the last line of the TodoWrite result:
```
"1 completed, 0 in progress, 2 pending"
```

Extract using regex pattern: `(\d+) completed, (\d+) in progress, (\d+) pending`

Calculate:
- `newCount = inProgress + pending`
- `doneCount = completed`

---

## Files to Modify

| File | Change |
|------|--------|
| `Sources/Views/TodoWriteChip.swift` | **NEW** - Chip component with iOS 26 and fallback |
| `Sources/Models/Message.swift` | Add `TodoWriteChipData` struct |
| `Sources/Views/MessageBubble/MessageBubble.swift` | Route "todowrite" to chip, add tap callback |
| `Sources/Views/ChatView.swift` | Wire up `onTodoWriteTap` to show TodoDetailSheet |
| `TronMobile.xcodeproj/project.pbxproj` | Add new file reference |

---

## Chip Design

**Appearance:**
- Capsule shape with glass effect (iOS 26) or `.tronSlate.opacity(0.15)` fill (fallback)
- Stroke border: `.tronSlate.opacity(0.4)`
- Icon: `checklist` in slate color
- Text: Slate colored monospace font
- Chevron: Right-pointing, slate, 0.6 opacity

**Text examples:**
- No counts: "Tasks Updated"
- New only: "Tasks Updated (3 new)"
- Done only: "Tasks Updated (2 done)"
- Both: "Tasks Updated (3 new, 2 done)"

---

## Verification

1. Build iOS app: `cd packages/ios-app && xcodebuild build -scheme TronMobile -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
2. Test in simulator:
   - Start a session and trigger TodoWrite tool call
   - Verify chip appears instead of full tool card
   - Verify chip text shows correct counts
   - Tap chip → TodoDetailSheet opens
3. Test fallback on older iOS (if possible)
