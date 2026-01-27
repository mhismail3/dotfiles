# NotifyApp Chip Rendering & Sheet Content

## Overview

Update NotifyApp tool to render as a compact chip (like TodoWrite, Subagent, RenderAppUI) with "Notified User" text. Tapping opens a detail sheet showing notification title, body, and additional sheet-specific content. Extend the tool params to support rich content for the sheet separate from the push notification payload.

---

## Changes Summary

### New Files (2)
| File | Purpose |
|------|---------|
| `packages/ios-app/Sources/Views/NotifyAppChip.swift` | Chip component with glass effect |
| `packages/ios-app/Sources/Views/NotifyAppDetailSheet.swift` | Detail sheet for notification content |

### Modified Files (5)
| File | Changes |
|------|---------|
| `packages/core/src/tools/notify-app.ts` | Add `sheetContent` param for rich detail content |
| `packages/ios-app/Sources/Models/Message.swift` | Add `NotifyAppChipData` struct |
| `packages/ios-app/Sources/Views/MessageBubble/MessageBubble.swift` | Route `notifyapp` to chip, add sheet state |
| `packages/ios-app/Sources/Views/MessageBubble/MessageBubbleContainer.swift` | Add sheet presentation for NotifyApp |
| `packages/ios-app/Sources/ViewModels/ChatViewModel+Events.swift` | Handle NotifyApp tool events (if needed) |

---

## Phase 1: Extend Tool Parameters

**File: `packages/core/src/tools/notify-app.ts`**

Add new optional `sheetContent` parameter:

```typescript
interface NotifyAppParams {
  // Push notification content (existing)
  title: string;           // max 50 chars - notification title
  body: string;            // max 200 chars - notification body

  // Sheet-specific content (new)
  sheetContent?: string;   // Markdown-formatted rich content for detail sheet

  // Existing optional params
  data?: Record<string, string>;
  priority?: 'high' | 'normal';
  sound?: string;
  badge?: number;
}
```

Update schema to include `sheetContent` as optional string.

The `sheetContent` field is stored with the tool call arguments and rendered in the detail sheet. It does NOT go to APNS - only to the iOS app via the event stream.

---

## Phase 2: iOS Data Model

**File: `packages/ios-app/Sources/Models/Message.swift`**

Add data struct for chip:

```swift
// MARK: - NotifyApp Chip Data

struct NotifyAppChipData: Equatable {
    let toolCallId: String
    let title: String
    let body: String
    let sheetContent: String?      // Markdown content for sheet
    var status: NotifyAppStatus
    var successCount: Int?
    var failureCount: Int?
    var errorMessage: String?
}

enum NotifyAppStatus: String, Equatable, Codable {
    case sending
    case sent
    case failed
}
```

---

## Phase 3: Chip Component

**File: `packages/ios-app/Sources/Views/NotifyAppChip.swift`**

Follow TodoWriteChip pattern:

```swift
struct NotifyAppChip: View {
    let data: NotifyAppChipData
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                statusIcon
                Text("Notified User")
                    .font(TronTypography.mono(size: 13, weight: .medium))
                    .foregroundStyle(statusColor)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tronTextMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background { chipBackground }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(statusColor.opacity(0.4), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch data.status {
        case .sending:
            ProgressView()
                .scaleEffect(0.7)
                .tint(.tronAmber)
        case .sent:
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 12))
                .foregroundStyle(.tronSuccess)
        case .failed:
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 12))
                .foregroundStyle(.tronError)
        }
    }

    private var statusColor: Color {
        switch data.status {
        case .sending: .tronAmber
        case .sent: .tronSuccess
        case .failed: .tronError
        }
    }

    @ViewBuilder
    private var chipBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.tint(Color.tronSlate.opacity(0.35)), in: .capsule)
        } else {
            Capsule()
                .fill(Color.tronSlate.opacity(0.15))
        }
    }
}
```

---

## Phase 4: Detail Sheet

**File: `packages/ios-app/Sources/Views/NotifyAppDetailSheet.swift`**

Style like TodoDetailSheet:

```swift
struct NotifyAppDetailSheet: View {
    let data: NotifyAppChipData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Notification header (title)
                    Text(data.title)
                        .font(TronTypography.mono(size: 18, weight: .semibold))
                        .foregroundStyle(.tronEmerald)

                    // Notification body
                    Text(data.body)
                        .font(TronTypography.mono(size: 14, weight: .regular))
                        .foregroundStyle(.tronTextPrimary)

                    // Sheet content (markdown)
                    if let sheetContent = data.sheetContent, !sheetContent.isEmpty {
                        Divider()
                            .background(Color.tronBorder)

                        MarkdownText(sheetContent)
                            .font(TronTypography.mono(size: 13, weight: .regular))
                            .foregroundStyle(.tronTextSecondary)
                    }

                    // Delivery status
                    if data.status == .sent || data.status == .failed {
                        Divider()
                            .background(Color.tronBorder)

                        deliveryStatusView
                    }
                }
                .padding()
            }
            .background(Color.tronBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(.tronEmerald)
                        Text("Notification")
                            .font(TronTypography.mono(size: 16, weight: .medium))
                            .foregroundStyle(.tronEmerald)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(TronTypography.mono(size: 14, weight: .medium))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .tint(.tronEmerald)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var deliveryStatusView: some View {
        HStack(spacing: 8) {
            if data.status == .sent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tronSuccess)
                Text("Delivered to \(data.successCount ?? 0) device(s)")
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tronError)
                Text(data.errorMessage ?? "Failed to deliver")
            }
        }
        .font(TronTypography.mono(size: 12, weight: .regular))
        .foregroundStyle(.tronTextMuted)
    }
}
```

---

## Phase 5: Wire Chip into MessageBubble

**File: `packages/ios-app/Sources/Views/MessageBubble/MessageBubble.swift`**

Add case in tool routing switch:

```swift
case "notifyapp":
    if let chipData = createNotifyAppChipData(from: tool) {
        NotifyAppChip(data: chipData) {
            onNotifyAppTap?(chipData)
        }
    }
```

Add helper to extract data:

```swift
private func createNotifyAppChipData(from tool: ToolUseData) -> NotifyAppChipData? {
    guard let argsData = tool.arguments?.data(using: .utf8),
          let args = try? JSONDecoder().decode(NotifyAppArgs.self, from: argsData) else {
        return nil
    }

    let status: NotifyAppStatus = switch tool.status {
    case .running: .sending
    case .success: .sent
    case .error: .failed
    }

    // Parse result for success/failure counts
    var successCount: Int?
    var failureCount: Int?
    var errorMessage: String?

    if let result = tool.result {
        // Extract from result JSON or text
        // Result format: "Notification sent to X device(s)" or error
    }

    return NotifyAppChipData(
        toolCallId: tool.toolCallId,
        title: args.title,
        body: args.body,
        sheetContent: args.sheetContent,
        status: status,
        successCount: successCount,
        failureCount: failureCount,
        errorMessage: errorMessage
    )
}

// Args struct for decoding
private struct NotifyAppArgs: Decodable {
    let title: String
    let body: String
    let sheetContent: String?
}
```

Add callback and sheet state to MessageBubbleContainer.

---

## Phase 6: Sheet Presentation

**File: `packages/ios-app/Sources/Views/MessageBubble/MessageBubbleContainer.swift`**

Add state and sheet modifier:

```swift
// Add state
@State private var notifyAppSheetData: NotifyAppChipData?

// Add to MessageBubble call
MessageBubble(
    // ... existing params
    onNotifyAppTap: { data in
        notifyAppSheetData = data
    }
)
.sheet(item: $notifyAppSheetData) { data in
    NotifyAppDetailSheet(data: data)
}
```

Make `NotifyAppChipData` conform to `Identifiable`:

```swift
extension NotifyAppChipData: Identifiable {
    var id: String { toolCallId }
}
```

---

## Data Flow

```
1. Agent calls NotifyApp tool with:
   - title: "Build Complete"
   - body: "All tests passed"
   - sheetContent: "## Details\n- 47 tests passed\n- Coverage: 85%"

2. Tool executes:
   - Sends APNS push with title + body only
   - Returns result with success/failure counts

3. iOS receives tool events:
   - tool.call with full arguments (including sheetContent)
   - tool.result with delivery status

4. MessageBubble renders NotifyAppChip:
   - Shows "Notified User" with bell icon
   - Status color: amber (sending) → green (sent) / red (failed)

5. User taps chip:
   - Sheet opens with title as header
   - Body displayed below
   - sheetContent rendered as markdown
   - Delivery status at bottom
```

---

## Verification

1. **Tool params**: Call NotifyApp with sheetContent, verify it's in tool.call event
2. **Chip rendering**: Verify chip appears instead of text result
3. **Status updates**: Watch chip transition from amber spinner to green checkmark
4. **Sheet content**: Tap chip, verify title/body/sheetContent display correctly
5. **Markdown rendering**: Include headers, lists, code in sheetContent
6. **Error state**: Force failure, verify red styling and error message

---

## Files to Read Before Implementation

- `packages/ios-app/Sources/Views/TodoWriteChip.swift` - Chip pattern reference
- `packages/ios-app/Sources/Views/TodoDetailSheet.swift` - Sheet pattern reference
- `packages/ios-app/Sources/Views/MessageBubble/MessageBubble.swift` - Tool routing
- `packages/core/src/tools/notify-app.ts` - Current tool implementation
