# Plan: Chat Mode Keyboard Shortcuts & Image Upload

## Goal
Enable Claude Code keyboard shortcut capabilities in chat mode via a toolbar, plus add image upload support for messages.

## Key Keyboard Shortcuts to Support

From Claude Code CLI, these are the capabilities that need chat mode equivalents:

| Shortcut | Capability | Priority |
|----------|------------|----------|
| `Shift+Tab` / `Alt+M` | Toggle permission modes (Auto-Accept, Plan, Normal) | High |
| `Ctrl+O` | Toggle verbose output | Medium |
| `Option+P` / `Alt+P` | Switch model | High |
| `Esc+Esc` | Rewind conversation | Medium |
| `Ctrl+V` / `Alt+V` | Paste image from clipboard | High (ties to image upload) |
| `!` prefix | Bash mode (run command directly) | Medium |
| `#` prefix | Memory shortcut (add to CLAUDE.md) | Low |
| `/` prefix | Slash commands | Medium |

## Implementation Plan

### Phase 1: Chat Toolbar Component (iOS-Aware)

**Files to create/modify:**
- Create: `frontend/src/components/chat/ChatToolbar.tsx`
- Modify: `frontend/src/components/chat/InputBar.tsx`

**Layout (toolbar above textarea, keyboard dismiss on right):**
```
┌──────────────────────────────────────────────────────────────┐
│ [Mode ▾] [Model ▾] [⚙ Verbose] [↩ Rewind] [📎]    [⌨ Done] │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│   Message textarea...                                        │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│ [Send]                                                       │
└──────────────────────────────────────────────────────────────┘
```

**iOS Keyboard Handling:**
- Use existing `useKeyboard()` hook pattern from `TerminalView.tsx`
- Our toolbar appears above textarea as the primary interaction point
- **Note**: The iOS Safari accessory bar (with arrows and Done) is system-controlled and cannot be hidden in web contexts. Our custom toolbar provides a better UX and the system bar becomes secondary/ignorable.
- **Keyboard Dismiss Button**: Right-most button, calls `document.activeElement?.blur()` to dismiss keyboard
- Follow existing `visualViewport` handling for proper positioning
- Match toolbar styling from TerminalView (scrollable-x, padding adjustments)

**Toolbar Buttons (left to right):**
1. **Mode Toggle** (dropdown): Normal → Auto-Accept → Plan Mode
   - Compact display: "Normal" / "Auto" / "Plan"
   - Tooltip: `Shift+Tab to cycle`

2. **Model Switcher** (dropdown): Select model
   - Compact display: Model name or icon
   - Tooltip: `Alt+P`

3. **Verbose Toggle** (icon button): Toggle verbose output
   - Visual indicator when active (filled vs outline icon)
   - Tooltip: `Ctrl+O - Toggle verbose`

4. **Rewind** (icon button): Open rewind history modal
   - Tooltip: `Esc+Esc - Rewind conversation`

5. **Attachment/Image** (icon button): Open file picker
   - Tooltip: `Ctrl+V to paste image`

6. **Keyboard Dismiss** (icon button, iOS only): Dismiss keyboard
   - Shows only when `keyboardVisible()` is true
   - Shows keyboard icon with down arrow or "Done"
   - Calls `blur()` on active element

### Phase 2: Image Upload Capability

**Files to create/modify:**
- Create: `frontend/src/components/chat/ImagePreview.tsx`
- Modify: `frontend/src/components/chat/InputBar.tsx`
- Modify: `frontend/src/stores/messages.ts`
- Modify: `crates/clauset-types/src/chat.rs`
- Modify: `crates/clauset-types/src/ws.rs`

**Frontend Implementation:**

1. **Hidden file input** triggered by attachment button:
   ```tsx
   <input
     type="file"
     accept="image/*"
     ref={fileInputRef}
     style={{ display: 'none' }}
     onChange={handleFileSelect}
   />
   ```

2. **Clipboard paste handling** (Ctrl+V / Cmd+V):
   ```tsx
   const handlePaste = async (e: ClipboardEvent) => {
     const items = e.clipboardData?.items;
     for (const item of items || []) {
       if (item.type.startsWith('image/')) {
         e.preventDefault();
         const file = item.getAsFile();
         if (file) await processImage(file);
       }
     }
   };
   ```

3. **Image processing** (resize if > 2048px, validate < 10MB):
   ```tsx
   async function processImage(file: File) {
     if (file.size > 10 * 1024 * 1024) {
       // Show error: too large
       return;
     }
     const resized = await resizeIfNeeded(file, 2048);
     const base64 = await toBase64(resized);
     addPendingImage({ name: file.name, base64, mimeType: file.type });
   }
   ```

4. **ImagePreview component** showing thumbnails above textarea:
   ```
   ┌─────────────────────────────────────────────────────┐
   │ [🖼 img1.png ✕] [🖼 img2.jpg ✕]                    │  ← ImagePreview
   ├─────────────────────────────────────────────────────┤
   │ Message textarea...                                 │
   └─────────────────────────────────────────────────────┘
   ```

**Data Structure Changes:**

```typescript
// frontend/src/stores/messages.ts
interface ImageAttachment {
  id: string;
  name: string;
  base64: string;      // Data URL for display and sending
  mimeType: string;
}

// Add to InputBar local state
const [pendingImages, setPendingImages] = createSignal<ImageAttachment[]>([]);
```

```rust
// crates/clauset-types/src/chat.rs
#[derive(Serialize, Deserialize, Clone)]
pub struct ImageAttachment {
    pub id: String,
    pub name: String,
    pub base64: String,
    pub mime_type: String,
}

// Add to ChatMessage
pub struct ChatMessage {
    // ... existing fields
    #[serde(default)]
    pub images: Vec<ImageAttachment>,
}
```

**WebSocket Protocol Update:**
```rust
// crates/clauset-types/src/ws.rs - Update Input message
pub enum WsClientMessage {
    Input {
        content: String,
        #[serde(default)]
        images: Vec<ImageAttachment>,
    },
    // ... other variants
}
```

### Phase 3: Keyboard Event Handling

**In InputBar.tsx - add to handleKeyDown:**
```typescript
function handleKeyDown(e: KeyboardEvent) {
  // Existing: Enter to submit
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    handleSubmit(e);
    return;
  }

  // Shift+Tab or Alt+M: Toggle mode
  if ((e.shiftKey && e.key === 'Tab') || (e.altKey && e.key === 'm')) {
    e.preventDefault();
    cyclePermissionMode();
    return;
  }

  // Alt+P: Open model switcher
  if (e.altKey && e.key === 'p') {
    e.preventDefault();
    setModelDropdownOpen(true);
    return;
  }

  // Ctrl+O: Toggle verbose
  if (e.ctrlKey && e.key === 'o') {
    e.preventDefault();
    toggleVerbose();
    return;
  }

  // Double Escape: Open rewind modal
  // (Track last escape time, if < 500ms apart, open rewind)
}
```

**Add onPaste handler to textarea:**
```typescript
<textarea
  onPaste={handlePaste}
  // ... other props
/>
```

### Phase 4: Backend Commands for Mode/Model Control

**WebSocket Commands to Add:**
```rust
// In crates/clauset-types/src/ws.rs
pub enum WsClientMessage {
    // ... existing
    SetMode { mode: PermissionMode },
    SetModel { model: String },
    ToggleVerbose,
    Rewind { to_message_id: String },
}

#[derive(Serialize, Deserialize, Clone, Copy)]
pub enum PermissionMode {
    Normal,
    AutoAccept,
    Plan,
}
```

**Session State Tracking:**
```rust
// In session handler, track current settings
pub struct SessionState {
    pub mode: PermissionMode,
    pub model: String,
    pub verbose: bool,
}
```

**CLI Integration:**
- Mode switching: Send appropriate keyboard sequence or command to Claude CLI
- Model switching: Use `/model` command or similar
- Verbose: Toggle via `/verbose` or equivalent
- Rewind: May require session restart or specific CLI command

### Phase 5: Rewind History Modal

**Create: `frontend/src/components/chat/RewindModal.tsx`**

Simple modal showing conversation checkpoints:
```
┌─────────────────────────────────────────┐
│ Rewind Conversation                  ✕  │
├─────────────────────────────────────────┤
│ Select a point to rewind to:            │
│                                         │
│ ○ "Add dark mode toggle" (2 min ago)    │
│ ○ "Fix the button style" (5 min ago)    │
│ ● "Initial commit" (10 min ago)         │
│                                         │
│              [Cancel] [Rewind]          │
└─────────────────────────────────────────┘
```

- Shows user messages as checkpoints
- Selecting and confirming sends `Rewind { to_message_id }` via WebSocket
- Backend handles truncating conversation history

---

## Files Summary

**Create:**
- `frontend/src/components/chat/ChatToolbar.tsx` - Toolbar with mode/model/verbose/rewind/image buttons
- `frontend/src/components/chat/ImagePreview.tsx` - Pending image thumbnails with remove button
- `frontend/src/components/chat/RewindModal.tsx` - Conversation history rewind picker

**Modify:**
- `frontend/src/components/chat/InputBar.tsx` - Integrate toolbar, image handling, keyboard shortcuts
- `frontend/src/components/chat/MessageBubble.tsx` - Display images in sent messages
- `frontend/src/stores/messages.ts` - Add image attachment types
- `crates/clauset-types/src/chat.rs` - Add ImageAttachment struct
- `crates/clauset-types/src/ws.rs` - Add image field to Input, new command variants
- `crates/clauset-core/src/chat_processor.rs` - Handle new commands
- `crates/clauset-server/src/ws/handler.rs` - Route new WebSocket messages

---

## Implementation Order

1. **ChatToolbar.tsx** - Create toolbar UI with placeholder buttons (no functionality yet)
2. **InputBar.tsx** - Integrate toolbar, add iOS keyboard dismiss button
3. **Image handling** - Add file input, paste handler, ImagePreview, pending state
4. **MessageBubble.tsx** - Display images in messages
5. **Backend types** - Update Rust structs for images and commands
6. **WebSocket integration** - Wire up mode/model/verbose/rewind commands
7. **RewindModal.tsx** - Create rewind UI last

---

## Verification Checklist

- [ ] Toolbar visible above textarea
- [ ] iOS: Keyboard dismiss button appears when keyboard is up
- [ ] iOS: Tapping dismiss button closes keyboard
- [ ] Desktop: Keyboard shortcuts work (Shift+Tab, Alt+P, Ctrl+O, Ctrl+V)
- [ ] Tooltips show keyboard shortcuts on hover
- [ ] Mode toggle cycles: Normal → Auto-Accept → Plan → Normal
- [ ] Model dropdown shows available models
- [ ] Verbose toggle has visual feedback (icon changes)
- [ ] Clicking attachment opens file picker
- [ ] Pasting image from clipboard adds to pending
- [ ] Image preview shows with remove button
- [ ] Images included in sent message
- [ ] Images display in MessageBubble
- [ ] Rewind button opens modal
- [ ] Rewind modal shows conversation checkpoints
- [ ] Large images (> 2048px) are resized
- [ ] Images > 10MB show error
