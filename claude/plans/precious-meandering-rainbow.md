# Plan: SessionPreviewSheet Scroll-to-Bottom

## Goal
When tapping a recent session in the new session sheet, scroll to the bottom so users see the most recent messages first and can scroll up to see older ones.

## File to Modify
`packages/ios-app/Sources/Views/Session/SessionPreviewSheet.swift`

## Implementation

### Primary Approach: Add `.defaultScrollAnchor(.bottom)`

Add the `defaultScrollAnchor(.bottom)` modifier to the ScrollView in `historyContent`:

```swift
private var historyContent: some View {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
            sessionInfoHeader
            ForEach(displayMessages) { message in
                MessageBubble(message: message)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    .defaultScrollAnchor(.bottom)  // <-- Add this line
}
```

**Why this works:**
- `defaultScrollAnchor(.bottom)` positions scroll at bottom on initial render with no visible animation
- Content only loads once (no streaming) so no complex state management needed
- When `isLoading` becomes false and `historyContent` appears, messages are already populated
- SwiftUI applies the anchor during initial layout

### Fallback (if primary doesn't work with async loading)

If the conditional view switching (`isLoading` toggle) causes issues with `defaultScrollAnchor`, use `ScrollViewReader`:

```swift
private var historyContent: some View {
    ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                sessionInfoHeader
                ForEach(displayMessages) { message in
                    MessageBubble(message: message)
                }
                Color.clear.frame(height: 1).id("bottom")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .defaultScrollAnchor(.bottom)
        .onAppear {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}
```

## Testing
1. Open New Session sheet, tap a recent session with 10+ messages
2. Verify sheet opens showing most recent messages (bottom)
3. Verify no visible scroll animation on open
4. Scroll up - older messages should be visible
5. Test with various session sizes (1, 5, 50+ messages)

## Build Verification
```bash
cd packages/ios-app && xcodebuild -scheme TronMobile -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```
