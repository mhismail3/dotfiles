# Queued Messages Feature for Tron iOS App

## Overview
Enable users to continue typing and queue messages while the agent is processing, with automatic injection when the agent completes.

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| When to inject | On `complete` event | `turn_end` fires mid-agentic-loop; `complete` means agent is truly waiting for user |
| Batch format | Single combined message | More efficient, cleaner context, agent sees all steering at once |
| Abort behavior | Queue persists | User may have aborted to add more steering |
| Attachments/Skills | Supported | Stored with each queued message, combined on injection |
| Server changes | None | Entirely client-side; uses standard `sendPrompt` RPC |

---

## Files to Modify

### 1. New Model: `packages/ios-app/Sources/Models/QueuedMessage.swift`
```swift
struct QueuedMessage: Identifiable, Equatable {
    let id: UUID
    let text: String
    let attachments: [Attachment]
    let skills: [Skill]
    let timestamp: Date
}
```

### 2. ChatViewModel State: `packages/ios-app/Sources/ViewModels/ChatViewModel.swift`
Add:
- `@Published var queuedMessages: [QueuedMessage] = []`
- `var hasQueuedMessages: Bool` computed property
- `var currentReasoningLevel: String?` (for injection)

### 3. New Extension: `packages/ios-app/Sources/ViewModels/ChatViewModel+Queue.swift`
- `queueMessage(_:attachments:skills:)` - add to queue
- `removeQueuedMessage(_:)` - remove from queue
- `clearQueuedMessages()` - clear all
- `injectQueuedMessages(reasoningLevel:)` - format and send combined prompt
- `formatQueuedMessagesForAgent(_:)` - format with `[QUEUED MESSAGE X of Y]` headers

### 4. Modify Send Logic: `packages/ios-app/Sources/ViewModels/ChatViewModel+Messaging.swift`
At start of `sendMessage()`:
```swift
if isProcessing {
    queueMessage(text, attachments: attachments, skills: skills ?? [])
    inputText = ""
    attachments = []
    selectedImages = []
    return  // Don't send immediately
}
```

### 5. Modify Complete Handler: `packages/ios-app/Sources/ViewModels/ChatViewModel+Events.swift`
At end of `handleComplete()`:
```swift
if hasQueuedMessages {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms settle
        injectQueuedMessages(reasoningLevel: currentReasoningLevel)
    }
}
```

### 6. Input Bar: `packages/ios-app/Sources/Views/InputBar/InputBar.swift`
**Remove TextField disabled state:**
```swift
// BEFORE: .disabled(isProcessing || readOnly)
// AFTER:  .disabled(readOnly)
```

**Remove keyboard dismiss on processing** (delete the entire `onChange(of: isProcessing)` block that dismisses keyboard)

**Add new props:**
- `queuedMessageCount: Int`
- `onQueueTap: (() -> Void)?`

**Add queue chip above input row:**
```swift
if queuedMessageCount > 0 {
    QueuedMessagesChip(count: queuedMessageCount, onTap: onQueueTap)
}
```

### 7. Action Button: `packages/ios-app/Sources/Views/InputBar/ActionButtons.swift`
Update `GlassActionButton` to handle three states:
- `isProcessing && !canSend` → Stop button (red stop.fill)
- `isProcessing && canSend` → Queue-send button (text.badge.plus icon)
- `!isProcessing && canSend` → Normal send (arrow.up)
- `!isProcessing && !canSend` → Disabled send

### 8. New UI: `packages/ios-app/Sources/Views/InputBar/QueuedMessagesChip.swift`
Capsule chip showing "N Queued" with text.badge.plus icon, tappable.

### 9. New UI: `packages/ios-app/Sources/Views/InputBar/QueuedMessagesSheet.swift`
Sheet for viewing/removing queued messages (optional, lower priority).

### 10. Message Badge: `packages/ios-app/Sources/Models/Message.swift`
Add optional field to ChatMessage:
```swift
var queuedInfo: (index: Int, total: Int)?
```

### 11. Message Display: `packages/ios-app/Sources/Views/MessageBubble/QueuedMessageBadge.swift`
Small badge showing "Queued" or "Queued 1/3" under user messages that were queued.

### 12. ChatView Integration: `packages/ios-app/Sources/Views/ChatView.swift`
- Pass `queuedMessageCount` to InputBar
- Add sheet state for QueuedMessagesSheet
- Track reasoning level changes and sync to ChatViewModel

---

## Implementation Order

1. **Core State** - QueuedMessage model, ChatViewModel state
2. **Queue Logic** - ChatViewModel+Queue extension, modify sendMessage()
3. **Injection** - Modify handleComplete() to inject queue
4. **Input Bar** - Remove disabled state, keep keyboard open
5. **Button Logic** - Three-state action button
6. **Queue Chip** - Visual indicator above input
7. **Message Badge** - "Queued" indicator on injected messages
8. **Queue Sheet** - Management UI (optional polish)

---

## Message Format for Agent

Single queued message:
```
<user's text as-is>
```

Multiple queued messages:
```
[QUEUED MESSAGE 1 of 3]
First message text here

[QUEUED MESSAGE 2 of 3]
Second message text here

[QUEUED MESSAGE 3 of 3]
Third message text here
```

---

## Edge Cases

| Case | Handling |
|------|----------|
| User aborts with queue | Queue persists; user can send with next prompt or clear |
| Disconnect with queue | Queue persists in memory; lost on app kill (v2: persist to UserDefaults) |
| Queue during AskUserQuestion | Allowed; AskUserQuestion pending, queue injects after complete |
| Rapid-fire queueing | Each message appended to array; UI shows count |
| Empty input during processing | Nothing queued (requires text or attachments) |

---

## Verification

1. **Basic flow**: Send message, type during processing, send again (queues), verify chip appears, verify injection on complete
2. **Multi-queue**: Queue 3+ messages, verify all appear in chat with badges, verify combined format
3. **Abort**: Queue messages, abort, verify queue persists, send new prompt with queue
4. **Attachments/Skills**: Queue message with attachment, verify attachment included in injection
5. **Model switch**: Change model while queue exists, verify injection uses correct model
