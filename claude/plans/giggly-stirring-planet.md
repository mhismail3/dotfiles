# Compaction Detail Sheet - Tap to See Before → After

## Goal

When user taps the compaction notification pill in the chat, show a sheet with the Before → After summary of the context.

---

## Current State

**CompactionNotificationView** (`NotificationViews.swift:183-251`):
- Renders cyan pill with "Context compacted" text
- Shows tokens saved and compression percentage
- **Not interactive** - no tap handler

**Data available**:
- `tokensBefore: Int`
- `tokensAfter: Int`
- `reason: String` ("manual", "pre_turn_guardrail", "threshold_exceeded")

---

## Implementation Plan

### 1. Add Tap Callback to MessageBubble

**File**: `packages/ios-app/Sources/Views/MessageBubble/MessageBubble.swift`

Add a new callback parameter alongside existing ones:

```swift
struct MessageBubble: View {
    let message: ChatMessage
    var onSkillTap: ((String) -> Void)? = nil
    var onAskUserQuestionTap: ((AskUserQuestionData) -> Void)? = nil
    var onCompactionTap: ((Int, Int, String) -> Void)? = nil  // NEW
    // ...
}
```

### 2. Make CompactionNotificationView Tappable

**File**: `packages/ios-app/Sources/Views/MessageBubble/NotificationViews.swift`

Add tap handler to the view:

```swift
struct CompactionNotificationView: View {
    let tokensBefore: Int
    let tokensAfter: Int
    let reason: String
    var onTap: (() -> Void)? = nil  // NEW

    var body: some View {
        HStack(spacing: 6) {
            // ... existing content
        }
        .contentShape(Rectangle())  // Make entire area tappable
        .onTapGesture {
            onTap?()
        }
    }
}
```

### 3. Wire Up in MessageBubble

**File**: `MessageBubble.swift` (around line 107-108)

```swift
case .compaction(let tokensBefore, let tokensAfter, let reason):
    CompactionNotificationView(
        tokensBefore: tokensBefore,
        tokensAfter: tokensAfter,
        reason: reason,
        onTap: {
            onCompactionTap?(tokensBefore, tokensAfter, reason)
        }
    )
```

### 4. Create CompactionDetailSheet

**File**: `packages/ios-app/Sources/Views/CompactionDetailSheet.swift` (NEW)

```swift
import SwiftUI

struct CompactionDetailSheet: View {
    let tokensBefore: Int
    let tokensAfter: Int
    let reason: String
    @Environment(\.dismiss) private var dismiss

    private var tokensSaved: Int { tokensBefore - tokensAfter }
    private var compressionPercent: Int {
        guard tokensBefore > 0 else { return 0 }
        return Int((Double(tokensSaved) / Double(tokensBefore)) * 100)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Before → After visualization
                HStack(spacing: 20) {
                    TokenBox(label: "Before", tokens: tokensBefore, color: .orange)
                    Image(systemName: "arrow.right")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    TokenBox(label: "After", tokens: tokensAfter, color: .cyan)
                }
                .padding(.top, 20)

                // Stats
                VStack(spacing: 12) {
                    StatRow(label: "Tokens saved", value: formatTokens(tokensSaved))
                    StatRow(label: "Compression", value: "\(compressionPercent)%")
                    StatRow(label: "Reason", value: reasonDisplay)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                Spacer()
            }
            .padding()
            .navigationTitle("Context Compacted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var reasonDisplay: String {
        switch reason {
        case "pre_turn_guardrail": return "Auto (context limit)"
        case "threshold_exceeded": return "Auto (threshold)"
        case "manual": return "Manual"
        default: return reason
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1000 {
            return String(format: "%.1fk", Double(tokens) / 1000)
        }
        return "\(tokens)"
    }
}

// Helper views
struct TokenBox: View {
    let label: String
    let tokens: Int
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatTokens(tokens))
                .font(.system(.title, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: 100)
        .padding()
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1000 {
            return String(format: "%.1fk", Double(tokens) / 1000)
        }
        return "\(tokens)"
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
```

### 5. Add State and Sheet to ChatView

**File**: `packages/ios-app/Sources/Views/ChatView.swift`

Add state variables:
```swift
@State private var showCompactionDetail = false
@State private var compactionDetailData: (tokensBefore: Int, tokensAfter: Int, reason: String)?
```

Add callback to MessageBubble in ForEach:
```swift
MessageBubble(
    message: message,
    onSkillTap: { skill in ... },
    onAskUserQuestionTap: { data in ... },
    onCompactionTap: { tokensBefore, tokensAfter, reason in
        compactionDetailData = (tokensBefore, tokensAfter, reason)
        showCompactionDetail = true
    }
)
```

Add sheet modifier:
```swift
.sheet(isPresented: $showCompactionDetail) {
    if let data = compactionDetailData {
        CompactionDetailSheet(
            tokensBefore: data.tokensBefore,
            tokensAfter: data.tokensAfter,
            reason: data.reason
        )
        .presentationDetents([.medium])
    }
}
```

---

## Files to Modify

| File | Change |
|------|--------|
| `NotificationViews.swift` | Add `onTap` callback to `CompactionNotificationView` |
| `MessageBubble.swift` | Add `onCompactionTap` parameter, wire up callback |
| `ChatView.swift` | Add state, callback handler, and sheet presentation |
| **NEW** `CompactionDetailSheet.swift` | Create the detail sheet view |

---

## Verification

1. Build and run on iOS simulator
2. Trigger a compaction (manual or auto)
3. Tap the cyan "Context compacted" pill
4. Sheet should appear with Before → After visualization
5. Dismiss with "Done" button or swipe down
