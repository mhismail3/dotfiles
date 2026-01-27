# Input Bar Interactive Glass

## Problem Statement

The text input field uses `.glassEffect()` but lacks the `.interactive()` modifier that other glass elements have, so it doesn't respond to touch with the native iOS 26 liquid glass visual feedback.

---

## Solution

Add `.interactive()` to the text field's glass effect modifier.

---

## Implementation

### File: `Sources/Views/InputBar/InputBar.swift`

**Add `.interactive()` to text field glass effect** (line 384):

```swift
// Before
.glassEffect(.regular.tint(Color.tronPhthaloGreen.opacity(0.35)), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

// After
.glassEffect(.regular.tint(Color.tronPhthaloGreen.opacity(0.35)).interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `Sources/Views/InputBar/InputBar.swift` | Add `.interactive()` to text field glass effect |

---

## Verification

### Manual Tests

1. **Input Bar Touch**: Touch/press on the text field → glass effect should respond with visual feedback (depress/highlight)

### Regression Tests

- Sending messages still works
- Text input and editing still works normally
- Keyboard behavior unchanged
