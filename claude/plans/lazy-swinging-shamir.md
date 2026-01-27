# Deep Linking for Push Notifications in Tron iOS App

## Overview

Implement deep linking so tapping a push notification navigates to the specific session and scrolls to the notify_app tool call that triggered it.

## Current State

- **Notification payload** already includes `sessionId` (line 1741 in `event-store-orchestrator.ts`)
- **AppDelegate** extracts `sessionId` from tap and posts `.navigateToSession` notification
- **TronMobileApp** subscribes to `.navigateToSession` but has **TODO at line 95** - not wired
- **ContentView** uses `@State private var selectedSessionId: String?` for navigation
- **ScrollStateCoordinator** (new!) manages scroll state with modes: `.following`, `.reviewing`, `.loading`
- **ChatView** uses both `scrollCoordinator` and `scrollProxy` for scrolling
- Messages loaded in `.task` with `initialLoadComplete = true` at completion (line 500)
- URL scheme `tron-mobile://` already registered (for OAuth)

## Architecture

```
Push Tap (AppDelegate) ──┐
                         ├──► DeepLinkRouter ──► NavigationIntent
URL Scheme (onOpenURL) ──┘           │
                                     ▼
                              TronMobileApp
                                     │
                    ┌────────────────┴────────────────┐
                    ▼                                 ▼
        selectedSessionId                     scrollTarget
             (State)                     (Environment/Binding)
                    │                                 │
                    ▼                                 ▼
              ContentView ────────────────────► ChatView
                                                     │
                                    ┌────────────────┴────────────────┐
                                    ▼                                 ▼
                          ScrollStateCoordinator          scrollProxy.scrollTo()
                            (mode management)              (actual scroll)
```

## Implementation Plan

### Phase 1: Server-Side Enhancement (Add toolCallId to notifications)

**File: `packages/core/src/tools/notify-app.ts`**
- The tool already has access to its own tool call context
- No changes needed here - toolCallId is available at execution time

**File: `packages/server/src/orchestrator/agent-factory.ts`** (lines 192-199)
- Modify `onNotify` callback signature to include `toolCallId: string`
- Pass toolCallId from tool execution context

**File: `packages/server/src/event-store-orchestrator.ts`** (lines 1701-1772)
- Update `sendNotification` to accept `toolCallId`
- Add `toolCallId` to APNS payload data alongside `sessionId`

### Phase 2: ScrollStateCoordinator Enhancement

**File: `packages/ios-app/Sources/ViewModels/Managers/ScrollStateCoordinator.swift`**

Add deep link scroll support:
```swift
/// Mode for deep link navigation (prevents auto-scroll interference)
// Add to Mode enum:
case deepLinking  // Navigating to specific item from deep link

/// Scroll to a deep link target (tool call or event)
/// Sets mode to prevent interference, then scrolls
func scrollToDeepLinkTarget(messageId: UUID, using proxy: ScrollViewProxy?) {
    // Set mode to prevent auto-scroll from interfering
    mode = .reviewing  // User initiated, not following
    hasUnreadContent = false
    graceUntil = Date().addingTimeInterval(gracePeriod)

    // Scroll with animation
    withAnimation(.tronStandard) {
        proxy?.scrollTo(messageId, anchor: .center)
    }
}
```

### Phase 3: iOS Deep Link Router (New File)

**New File: `packages/ios-app/Sources/Navigation/DeepLinkRouter.swift`**

```swift
import Foundation

/// Represents a scroll target within a session
enum ScrollTarget: Equatable {
    case toolCall(id: String)  // Scroll to specific tool call
    case event(id: String)     // Scroll to specific event
    case bottom                // Scroll to bottom (default)
}

/// Represents a navigation destination from deep links
enum NavigationIntent: Equatable {
    case session(id: String, scrollTo: ScrollTarget?)
    case settings
    case voiceNotes
}

/// Central router for handling deep links from notifications and URLs
@MainActor
class DeepLinkRouter: ObservableObject {
    @Published var pendingIntent: NavigationIntent?

    /// Handle notification payload (from AppDelegate)
    func handle(notificationPayload: [AnyHashable: Any]) {
        guard let sessionId = notificationPayload["sessionId"] as? String else { return }

        let scrollTarget: ScrollTarget?
        if let toolCallId = notificationPayload["toolCallId"] as? String {
            scrollTarget = .toolCall(id: toolCallId)
        } else if let eventId = notificationPayload["eventId"] as? String {
            scrollTarget = .event(id: eventId)
        } else {
            scrollTarget = nil
        }

        pendingIntent = .session(id: sessionId, scrollTo: scrollTarget)
    }

    /// Handle URL scheme (tron://session/{id}?tool={toolCallId})
    func handle(url: URL) -> Bool {
        guard url.scheme == "tron" || url.scheme == "tron-mobile" else { return false }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch pathComponents.first {
        case "session":
            guard pathComponents.count >= 2 else { return false }
            let sessionId = pathComponents[1]

            var scrollTarget: ScrollTarget?
            if let toolId = components?.queryItems?.first(where: { $0.name == "tool" })?.value {
                scrollTarget = .toolCall(id: toolId)
            } else if let eventId = components?.queryItems?.first(where: { $0.name == "event" })?.value {
                scrollTarget = .event(id: eventId)
            }

            pendingIntent = .session(id: sessionId, scrollTo: scrollTarget)
            return true

        case "settings":
            pendingIntent = .settings
            return true

        default:
            return false
        }
    }

    /// Consume and clear the pending intent
    func consumeIntent() -> NavigationIntent? {
        defer { pendingIntent = nil }
        return pendingIntent
    }
}
```

### Phase 4: Wire Navigation in TronMobileApp

**File: `packages/ios-app/Sources/App/TronMobileApp.swift`**

Changes at lines 91-96 (replace TODO):
1. Add `@StateObject private var deepLinkRouter = DeepLinkRouter()`
2. Add `@State private var pendingScrollTarget: ScrollTarget?`
3. Add `@State private var targetSessionId: String?` (separate from eventStoreManager)
4. Wire notification handling to pass to ContentView

```swift
// Replace the TODO at line 95:
.onReceive(NotificationCenter.default.publisher(for: .navigateToSession)) { notification in
    guard let userInfo = notification.userInfo else { return }
    deepLinkRouter.handle(notificationPayload: userInfo)
}
.onOpenURL { url in
    _ = deepLinkRouter.handle(url: url)
}
.onChange(of: deepLinkRouter.pendingIntent) { _, _ in
    guard let intent = deepLinkRouter.consumeIntent() else { return }
    switch intent {
    case .session(let sessionId, let scrollTarget):
        targetSessionId = sessionId
        pendingScrollTarget = scrollTarget
    case .settings, .voiceNotes:
        break // Handle other intents
    }
}
```

Then pass `targetSessionId` and `pendingScrollTarget` to ContentView via bindings or environment.

### Phase 5: Update ContentView to Accept Scroll Target

**File: `packages/ios-app/Sources/Views/ContentView.swift`**

Changes:
1. Accept `scrollTarget: Binding<ScrollTarget?>` from parent
2. Pass to `ChatView` initializer
3. When deep link arrives, set `selectedSessionId` to trigger navigation

### Phase 6: Implement Scroll-to-Tool in ChatView

**File: `packages/ios-app/Sources/Views/ChatView.swift`**

Changes to init (line 91-97):
```swift
init(rpcClient: RPCClient, sessionId: String, skillStore: SkillStore? = nil,
     workspaceDeleted: Bool = false, scrollTarget: ScrollTarget? = nil) {
    // ... existing init
    self.initialScrollTarget = scrollTarget
}

@State private var initialScrollTarget: ScrollTarget?
```

Changes to `.task` (after line 500):
```swift
// Mark initial load complete
initialLoadComplete = true

// Handle deep link scroll target after messages load
if let target = initialScrollTarget {
    // Brief delay for layout
    try? await Task.sleep(nanoseconds: 150_000_000)
    if let messageId = viewModel.findMessageId(for: target) {
        scrollCoordinator.scrollToDeepLinkTarget(messageId: messageId, using: scrollProxy)
    }
    initialScrollTarget = nil
}
```

**File: `packages/ios-app/Sources/ViewModels/ChatViewModel.swift`**

Add method to find message UUID:
```swift
func findMessageId(for target: ScrollTarget) -> UUID? {
    switch target {
    case .toolCall(let toolCallId):
        for message in messages {
            switch message.content {
            case .toolUse(let data) where data.toolCallId == toolCallId:
                return message.id
            case .toolResult(let data) where data.toolCallId == toolCallId:
                return message.id
            case .subagent(let data) where data.toolCallId == toolCallId:
                return message.id
            default:
                continue
            }
        }
        return nil

    case .event(let eventId):
        return messages.first(where: { $0.eventId == eventId })?.id

    case .bottom:
        return nil
    }
}
```

### Phase 7: AppDelegate Enhancement

**File: `packages/ios-app/Sources/App/AppDelegate.swift`**

Update `didReceive` (line 81-90) to pass full payload:
```swift
// Pass entire userInfo including toolCallId
NotificationCenter.default.post(
    name: .navigateToSession,
    object: nil,
    userInfo: userInfo  // Already passes full payload
)
```

### Phase 8: URL Scheme Registration

**File: `packages/ios-app/Sources/Info.plist`**

Add `tron` URL scheme alongside existing `tron-mobile`:
```xml
<dict>
    <key>CFBundleURLSchemes</key>
    <array>
        <string>tron</string>
        <string>tron-mobile</string>
    </array>
</dict>
```

## Files to Modify

| File | Changes |
|------|---------|
| `packages/server/src/event-store-orchestrator.ts` | Add `toolCallId` to notification payload |
| `packages/server/src/orchestrator/agent-factory.ts` | Pass `toolCallId` through `onNotify` callback |
| `packages/ios-app/Sources/Navigation/DeepLinkRouter.swift` | **NEW** - Central deep link router |
| `packages/ios-app/Sources/ViewModels/Managers/ScrollStateCoordinator.swift` | Add `scrollToDeepLinkTarget()` method |
| `packages/ios-app/Sources/App/TronMobileApp.swift` | Wire deep link router, navigation logic |
| `packages/ios-app/Sources/App/AppDelegate.swift` | Pass full payload in notification (already does) |
| `packages/ios-app/Sources/Views/ContentView.swift` | Accept and pass scroll target to ChatView |
| `packages/ios-app/Sources/Views/ChatView.swift` | Accept scroll target in init, scroll after load |
| `packages/ios-app/Sources/ViewModels/ChatViewModel.swift` | Add `findMessageId(for:)` method |
| `packages/ios-app/Sources/Info.plist` | Add `tron://` URL scheme |

## Test-Driven Development Plan

Follow this TDD approach: **Write tests FIRST**, then implement.

### Phase 0: Run Existing Tests (Baseline)

Before any changes, ensure all existing tests pass:
```bash
bun run build && bun run test
cd packages/ios-app && xcodebuild test -scheme TronMobile -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

### Tests for DeepLinkRouter (Write First)

**New File: `packages/ios-app/Tests/Navigation/DeepLinkRouterTests.swift`**

```swift
import XCTest
@testable import TronMobile

@MainActor
final class DeepLinkRouterTests: XCTestCase {

    // MARK: - Notification Payload Handling

    func testHandleNotificationWithSessionIdOnly() {
        let router = DeepLinkRouter()
        router.handle(notificationPayload: ["sessionId": "sess_123"])

        XCTAssertEqual(router.pendingIntent, .session(id: "sess_123", scrollTo: nil))
    }

    func testHandleNotificationWithToolCallId() {
        let router = DeepLinkRouter()
        router.handle(notificationPayload: [
            "sessionId": "sess_123",
            "toolCallId": "toolu_abc"
        ])

        XCTAssertEqual(router.pendingIntent,
            .session(id: "sess_123", scrollTo: .toolCall(id: "toolu_abc")))
    }

    func testHandleNotificationWithEventId() {
        let router = DeepLinkRouter()
        router.handle(notificationPayload: [
            "sessionId": "sess_123",
            "eventId": "evt_xyz"
        ])

        XCTAssertEqual(router.pendingIntent,
            .session(id: "sess_123", scrollTo: .event(id: "evt_xyz")))
    }

    func testHandleNotificationWithMissingSessionId() {
        let router = DeepLinkRouter()
        router.handle(notificationPayload: ["toolCallId": "toolu_abc"])

        XCTAssertNil(router.pendingIntent)
    }

    // MARK: - URL Scheme Handling

    func testHandleURLWithSessionOnly() {
        let router = DeepLinkRouter()
        let url = URL(string: "tron://session/sess_123")!

        XCTAssertTrue(router.handle(url: url))
        XCTAssertEqual(router.pendingIntent, .session(id: "sess_123", scrollTo: nil))
    }

    func testHandleURLWithToolQuery() {
        let router = DeepLinkRouter()
        let url = URL(string: "tron://session/sess_123?tool=toolu_abc")!

        XCTAssertTrue(router.handle(url: url))
        XCTAssertEqual(router.pendingIntent,
            .session(id: "sess_123", scrollTo: .toolCall(id: "toolu_abc")))
    }

    func testHandleURLWithEventQuery() {
        let router = DeepLinkRouter()
        let url = URL(string: "tron://session/sess_123?event=evt_xyz")!

        XCTAssertTrue(router.handle(url: url))
        XCTAssertEqual(router.pendingIntent,
            .session(id: "sess_123", scrollTo: .event(id: "evt_xyz")))
    }

    func testHandleURLWithTronMobileScheme() {
        let router = DeepLinkRouter()
        let url = URL(string: "tron-mobile://session/sess_123")!

        XCTAssertTrue(router.handle(url: url))
        XCTAssertEqual(router.pendingIntent, .session(id: "sess_123", scrollTo: nil))
    }

    func testHandleURLWithInvalidScheme() {
        let router = DeepLinkRouter()
        let url = URL(string: "https://session/sess_123")!

        XCTAssertFalse(router.handle(url: url))
        XCTAssertNil(router.pendingIntent)
    }

    func testHandleURLSettings() {
        let router = DeepLinkRouter()
        let url = URL(string: "tron://settings")!

        XCTAssertTrue(router.handle(url: url))
        XCTAssertEqual(router.pendingIntent, .settings)
    }

    // MARK: - Consume Intent

    func testConsumeIntentReturnsAndClears() {
        let router = DeepLinkRouter()
        router.handle(notificationPayload: ["sessionId": "sess_123"])

        let intent = router.consumeIntent()

        XCTAssertEqual(intent, .session(id: "sess_123", scrollTo: nil))
        XCTAssertNil(router.pendingIntent)
    }

    func testConsumeIntentReturnsNilWhenEmpty() {
        let router = DeepLinkRouter()

        XCTAssertNil(router.consumeIntent())
    }

    // MARK: - Multiple Intents (Last Wins)

    func testMultipleIntentsLastWins() {
        let router = DeepLinkRouter()
        router.handle(notificationPayload: ["sessionId": "sess_1"])
        router.handle(notificationPayload: ["sessionId": "sess_2"])

        XCTAssertEqual(router.pendingIntent, .session(id: "sess_2", scrollTo: nil))
    }
}
```

### Tests for ChatViewModel.findMessageId (Write First)

**Add to: `packages/ios-app/Tests/ViewModels/ChatViewModelTests.swift`** (or create if needed)

```swift
@MainActor
final class ChatViewModelFindMessageTests: XCTestCase {

    func testFindMessageIdForToolCallInToolUse() {
        let viewModel = createViewModelWithMessages([
            ChatMessage(id: UUID(), role: .assistant,
                content: .toolUse(ToolUseData(toolCallId: "toolu_abc", name: "notify_app", arguments: "{}")))
        ])

        let found = viewModel.findMessageId(for: .toolCall(id: "toolu_abc"))

        XCTAssertNotNil(found)
        XCTAssertEqual(found, viewModel.messages.first?.id)
    }

    func testFindMessageIdForToolCallInToolResult() {
        let viewModel = createViewModelWithMessages([
            ChatMessage(id: UUID(), role: .user,
                content: .toolResult(ToolResultData(toolCallId: "toolu_abc", content: "Success")))
        ])

        let found = viewModel.findMessageId(for: .toolCall(id: "toolu_abc"))

        XCTAssertNotNil(found)
    }

    func testFindMessageIdForToolCallNotFound() {
        let viewModel = createViewModelWithMessages([
            ChatMessage(id: UUID(), role: .assistant, content: .text("Hello"))
        ])

        let found = viewModel.findMessageId(for: .toolCall(id: "toolu_nonexistent"))

        XCTAssertNil(found)
    }

    func testFindMessageIdForEventId() {
        let messageId = UUID()
        let viewModel = createViewModelWithMessages([
            ChatMessage(id: messageId, role: .assistant, content: .text("Hello"), eventId: "evt_xyz")
        ])

        let found = viewModel.findMessageId(for: .event(id: "evt_xyz"))

        XCTAssertEqual(found, messageId)
    }

    func testFindMessageIdForBottomReturnsNil() {
        let viewModel = createViewModelWithMessages([
            ChatMessage(id: UUID(), role: .assistant, content: .text("Hello"))
        ])

        let found = viewModel.findMessageId(for: .bottom)

        XCTAssertNil(found) // Use "bottom" anchor instead
    }
}
```

### Tests for ScrollStateCoordinator Enhancement (Write First)

**Add to existing file or create: `packages/ios-app/Tests/ViewModels/ScrollStateCoordinatorTests.swift`**

```swift
@MainActor
final class ScrollStateCoordinatorDeepLinkTests: XCTestCase {

    func testScrollToDeepLinkTargetSetsReviewingMode() {
        let coordinator = ScrollStateCoordinator()
        coordinator.mode = .following  // Start in following mode

        coordinator.scrollToDeepLinkTarget(messageId: UUID(), using: nil)

        XCTAssertEqual(coordinator.mode, .reviewing)
    }

    func testScrollToDeepLinkTargetClearsUnreadContent() {
        let coordinator = ScrollStateCoordinator()
        coordinator.hasUnreadContent = true

        coordinator.scrollToDeepLinkTarget(messageId: UUID(), using: nil)

        XCTAssertFalse(coordinator.hasUnreadContent)
    }

    func testScrollToDeepLinkTargetSetsGracePeriod() {
        let coordinator = ScrollStateCoordinator()
        let beforeTime = Date()

        coordinator.scrollToDeepLinkTarget(messageId: UUID(), using: nil)

        // Grace period should be set to future
        XCTAssertTrue(coordinator.graceUntil > beforeTime)
    }
}
```

### Server-Side Tests for NotifyApp with toolCallId

**Add to: `packages/server/test/notify-app.test.ts`** (create if needed)

```typescript
import { describe, it, expect, beforeEach } from 'vitest';

describe('NotifyApp Tool with toolCallId', () => {
  it('should include toolCallId in notification payload', async () => {
    // Mock the onNotify callback and verify toolCallId is passed
    let receivedToolCallId: string | undefined;

    const mockOnNotify = async (
      sessionId: string,
      notification: { title: string; body: string; data?: Record<string, string> },
      toolCallId: string
    ) => {
      receivedToolCallId = toolCallId;
      return { successCount: 1, failureCount: 0 };
    };

    // Execute NotifyApp tool with mocked callback
    // ... tool execution ...

    expect(receivedToolCallId).toBe('toolu_expected_id');
  });

  it('should add toolCallId to APNS payload data', async () => {
    // Verify the APNS payload structure includes toolCallId
    const payload = buildAPNSPayload({
      title: 'Test',
      body: 'Test body',
      sessionId: 'sess_123',
      toolCallId: 'toolu_abc'
    });

    expect(payload.data.sessionId).toBe('sess_123');
    expect(payload.data.toolCallId).toBe('toolu_abc');
  });
});
```

## Implementation Order (TDD)

1. **Write DeepLinkRouterTests.swift** - Run tests, see them fail
2. **Implement DeepLinkRouter.swift** - Run tests, see them pass
3. **Write ChatViewModelFindMessageTests** - Run tests, see them fail
4. **Implement findMessageId in ChatViewModel** - Run tests, see them pass
5. **Write ScrollStateCoordinatorDeepLinkTests** - Run tests, see them fail
6. **Implement scrollToDeepLinkTarget** - Run tests, see them pass
7. **Write server-side notify-app.test.ts** - Run tests, see them fail
8. **Implement server-side toolCallId passing** - Run tests, see them pass
9. **Integration wiring** (TronMobileApp, ContentView, ChatView) - Manual testing
10. **Full regression test** - Run all tests, verify existing functionality

## Edge Cases

1. **Session not cached locally**: Sync from server first via `syncAndLoadMessagesForResume()`, then scroll
2. **Tool call not in loaded messages**: `findMessageId` returns nil, gracefully degrade to no scroll
3. **App cold start**: DeepLinkRouter holds intent until EventStoreManager initializes, ContentView observes
4. **Multiple rapid notifications**: Last one wins (single `pendingIntent` property)
5. **Already viewing target session**: Just scroll, don't re-navigate
6. **Invalid URL format**: Return false from handle(url:), log warning

## Regression Prevention

### Before Each Phase
- Run full test suite: `bun run build && bun run test`
- Run iOS tests: `cd packages/ios-app && xcodebuild test ...`

### After Implementation
- Verify existing notification flow still works (session navigation without scroll)
- Verify existing scroll behavior unchanged (following/reviewing modes)
- Verify URL scheme `tron-mobile://` still works for OAuth
- Test on both iPhone and iPad layouts

## Verification

1. **Automated Tests**: All new tests pass, zero regressions in existing tests
2. **Build Verification**: `bun run build && bun run test` succeeds
3. **Manual Testing**:
   - Send notification via notify_app tool from an agent session
   - Tap notification while app is:
     - In foreground (different session) - should switch session and scroll to NotifyApp chip
     - In background - should open app, navigate to session, scroll to chip
     - Killed - should cold start, navigate, and scroll
   - Test URL scheme: `xcrun simctl openurl booted "tron://session/{sessionId}?tool={toolCallId}"`
   - Verify scroll lands on the correct NotifyApp chip (centered in view)
4. **Regression Check**: Existing notification tap → dashboard behavior still works for notifications without toolCallId
