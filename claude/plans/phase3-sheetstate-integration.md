# Phase 3: SheetState Integration Plan (Revised)

## Research Summary

Based on research from [Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-present-multiple-sheets), [Swift Forums](https://github.com/pointfreeco/swift-composable-architecture/discussions/2922), [SwiftLee](https://www.avanderlee.com/swiftui/presenting-sheets/), [Masilotti.com](https://masilotti.com/multiple-sheets-swiftui/), and [AzamSharp's Global Sheets Pattern](https://azamsharp.com/2024/08/18/global-sheets-pattern-swiftui.html):

**Root Cause Confirmed:** The Swift compiler's type-checker has exponential complexity with chained modifiers. Multiple `.sheet()` modifiers (5+) reliably cause type-check timeouts regardless of framework.

**Canonical Solution:** Use a **single `.sheet(item:)` modifier** with an **Identifiable enum** instead of multiple `.sheet()` modifiers. This is the recommended SwiftUI pattern.

---

## Problem Analysis

### Current State (ChatView.swift)
```swift
// 14 separate .sheet() modifiers chained together
.sheet(isPresented: safariURLPresented) { ... }
.sheet(isPresented: browserWindowPresented) { ... }
.sheet(isPresented: $viewModel.showSettings) { ... }
.sheet(isPresented: $showContextAudit) { ... }
.sheet(isPresented: $showSessionHistory) { ... }
.sheet(isPresented: $showSkillDetailSheet) { ... }
.sheet(isPresented: $showCompactionDetail) { ... }
.sheet(isPresented: askUserQuestionPresented) { ... }
.sheet(isPresented: subagentDetailPresented) { ... }
.sheet(isPresented: uiCanvasPresented) { ... }
.sheet(isPresented: todoPresented) { ... }
.sheet(item: $notifyAppSheetData) { ... }
.sheet(isPresented: thinkingPresented) { ... }
.alert(...) { ... }
```

**Why This Fails:**
- Each `.sheet()` adds a closure for the compiler to type-check
- Swift's type-checker complexity grows exponentially with chained modifiers
- Adding SheetState forces re-type-checking all 14 sheets simultaneously

---

## Solution: Enum-Based Single Sheet Pattern

### Step 1: Define Sheet Enum with Associated Values

**File:** `Sources/ViewModels/State/SheetState.swift` (update existing)

```swift
import Foundation

/// Identifiable enum representing all possible sheets in ChatView
enum ChatSheet: Identifiable, Equatable {
    // Browser sheets
    case safari(URL)
    case browser

    // Settings & Info
    case settings
    case contextAudit
    case sessionHistory

    // Skill/Spell details
    case skillDetail(Skill, ChipMode)
    case compactionDetail(CompactionData)

    // Tool sheets
    case askUserQuestion
    case subagentDetail
    case uiCanvas
    case todoList

    // Notification sheets
    case notifyApp(NotifyAppChipData)
    case thinkingDetail(String)

    var id: String {
        switch self {
        case .safari(let url): return "safari-\(url.absoluteString)"
        case .browser: return "browser"
        case .settings: return "settings"
        case .contextAudit: return "contextAudit"
        case .sessionHistory: return "sessionHistory"
        case .skillDetail(let skill, _): return "skill-\(skill.id)"
        case .compactionDetail: return "compaction"
        case .askUserQuestion: return "askUserQuestion"
        case .subagentDetail: return "subagent"
        case .uiCanvas: return "uiCanvas"
        case .todoList: return "todoList"
        case .notifyApp(let data): return "notifyApp-\(data.toolCallId)"
        case .thinkingDetail: return "thinking"
        }
    }
}

struct CompactionData: Equatable {
    let tokensBefore: Int
    let tokensAfter: Int
    let reason: String
    let summary: String?
}
```

### Step 2: Create Sheet Coordinator

**File:** `Sources/ViewModels/State/SheetState.swift` (continue)

```swift
/// Manages sheet presentation state for ChatView
/// Uses single sheet(item:) modifier pattern per Apple/community best practices
@Observable
@MainActor
final class SheetCoordinator {
    /// Currently active sheet (nil = no sheet)
    var activeSheet: ChatSheet?

    /// Dismissal callback (optional)
    var onDismiss: (() -> Void)?

    // MARK: - Presentation Methods

    func present(_ sheet: ChatSheet, onDismiss: (() -> Void)? = nil) {
        self.activeSheet = sheet
        self.onDismiss = onDismiss
    }

    func dismiss() {
        activeSheet = nil
    }

    // MARK: - Convenience Presenters

    func showSafari(_ url: URL) {
        present(.safari(url))
    }

    func showSkillDetail(_ skill: Skill, mode: ChipMode) {
        present(.skillDetail(skill, mode))
    }

    func showCompactionDetail(tokensBefore: Int, tokensAfter: Int, reason: String, summary: String?) {
        present(.compactionDetail(CompactionData(
            tokensBefore: tokensBefore,
            tokensAfter: tokensAfter,
            reason: reason,
            summary: summary
        )))
    }

    func showThinkingDetail(_ content: String) {
        present(.thinkingDetail(content))
    }

    func showNotifyApp(_ data: NotifyAppChipData) {
        present(.notifyApp(data))
    }
}
```

### Step 3: Create Sheet Content View

**File:** `Sources/Views/Chat/ChatSheetContent.swift`

```swift
import SwiftUI

/// Renders the appropriate sheet content based on ChatSheet enum
/// Isolates sheet content from main view body to aid type-checking
@available(iOS 26.0, *)
struct ChatSheetContent: View {
    let sheet: ChatSheet
    let viewModel: ChatViewModel
    let rpcClient: RPCClient
    let sessionId: String
    let skillStore: SkillStore?
    let workspaceDeleted: Bool
    @EnvironmentObject var eventStoreManager: EventStoreManager

    var body: some View {
        switch sheet {
        case .safari(let url):
            SafariView(url: url)

        case .browser:
            BrowserSheetView(
                frameImage: viewModel.browserState.browserFrame,
                currentUrl: viewModel.browserState.browserStatus?.currentUrl,
                isStreaming: viewModel.browserState.browserStatus?.isStreaming ?? false,
                onCloseBrowser: { viewModel.userDismissedBrowser() }
            )

        case .settings:
            SettingsView(rpcClient: rpcClient)

        case .contextAudit:
            ContextAuditView(
                rpcClient: rpcClient,
                sessionId: sessionId,
                skillStore: skillStore,
                readOnly: workspaceDeleted
            )

        case .sessionHistory:
            SessionHistorySheet(
                sessionId: sessionId,
                rpcClient: rpcClient,
                eventStoreManager: eventStoreManager
            )

        case .skillDetail(let skill, let mode):
            if let store = skillStore {
                SkillDetailSheet(skill: skill, skillStore: store, mode: mode)
            }

        case .compactionDetail(let data):
            CompactionDetailSheet(
                tokensBefore: data.tokensBefore,
                tokensAfter: data.tokensAfter,
                reason: data.reason,
                summary: data.summary
            )
            .adaptivePresentationDetents([.medium, .large])

        case .askUserQuestion:
            if let data = viewModel.askUserQuestionState.currentData {
                AskUserQuestionSheet(
                    toolData: data,
                    onSubmit: { answers in
                        Task { await viewModel.submitAskUserQuestionAnswers(answers) }
                    },
                    onDismiss: { viewModel.dismissAskUserQuestionSheet() },
                    readOnly: data.status == .answered
                )
            }

        case .subagentDetail:
            if let data = viewModel.subagentState.selectedSubagent {
                SubagentDetailSheet(
                    data: data,
                    subagentState: viewModel.subagentState,
                    eventStoreManager: eventStoreManager
                )
                .adaptivePresentationDetents([.medium, .large])
            }

        case .uiCanvas:
            UICanvasSheet(state: viewModel.uiCanvasState)

        case .todoList:
            TodoDetailSheet(
                rpcClient: rpcClient,
                sessionId: sessionId,
                workspaceId: viewModel.workspaceId,
                todoState: viewModel.todoState
            )

        case .notifyApp(let data):
            NotifyAppDetailSheet(data: data)

        case .thinkingDetail(let content):
            ThinkingDetailSheet(content: content)
        }
    }
}
```

### Step 4: Update ChatView with Single Sheet Modifier

**File:** `Sources/Views/Chat/ChatView.swift`

```swift
@available(iOS 26.0, *)
struct ChatView: View {
    // ... existing properties ...

    // REPLACE: 8 @State sheet properties with single coordinator
    @State private var sheetCoordinator = SheetCoordinator()

    var body: some View {
        messagesScrollView
            .safeAreaInset(edge: .bottom, spacing: 0) { /* InputBar */ }
            // ... toolbar, navigation ...

            // SINGLE sheet modifier replaces 14 separate modifiers
            .sheet(item: $sheetCoordinator.activeSheet, onDismiss: {
                sheetCoordinator.onDismiss?()
            }) { sheet in
                ChatSheetContent(
                    sheet: sheet,
                    viewModel: viewModel,
                    rpcClient: rpcClient,
                    sessionId: sessionId,
                    skillStore: skillStore,
                    workspaceDeleted: workspaceDeleted
                )
                .environmentObject(eventStoreManager)
            }
            .alert(...) // Keep alert separate (different modifier type)
            // ... onChange, onReceive handlers ...
    }
}
```

### Step 5: Update Sheet Triggers

Replace direct @State mutations with coordinator calls:

```swift
// Before
showContextAudit = true

// After
sheetCoordinator.present(.contextAudit)

// Before
skillForDetailSheet = skill
skillDetailMode = .skill
showSkillDetailSheet = true

// After
sheetCoordinator.showSkillDetail(skill, mode: .skill)

// Before
notifyAppSheetData = data

// After
sheetCoordinator.showNotifyApp(data)
```

---

## Test Strategy

### Update SheetStateTests.swift

```swift
@Suite("SheetCoordinator Tests")
struct SheetCoordinatorTests {
    // Presentation tests
    @Test("Present sheet sets activeSheet")
    @Test("Present with onDismiss stores callback")
    @Test("Dismiss clears activeSheet")

    // Convenience method tests
    @Test("showSkillDetail creates correct enum case")
    @Test("showCompactionDetail creates correct data")
    @Test("showThinkingDetail creates correct enum case")

    // Edge cases
    @Test("Presenting new sheet replaces current sheet")
    @Test("Dismiss when no sheet is no-op")
}

@Suite("ChatSheet Enum Tests")
struct ChatSheetTests {
    @Test("Each case has unique id")
    @Test("Safari with different URLs have different ids")
    @Test("SkillDetail with same skill has same id")
    @Test("Equatable works correctly for associated values")
}
```

### Integration Test

```swift
@Test("ChatView compiles with single sheet modifier")
func testChatViewCompiles() async throws {
    // This test passing means the view type-checks successfully
    // Timeout = type-check failure
    #expect(true)
}
```

---

## Migration Checklist

- [ ] Create `ChatSheet` enum with all 14 cases
- [ ] Create `CompactionData` struct for associated value
- [ ] Create `SheetCoordinator` class
- [ ] Create `ChatSheetContent` view
- [ ] Remove 8 @State sheet properties from ChatView
- [ ] Add single `@State private var sheetCoordinator`
- [ ] Replace 14 `.sheet()` modifiers with single `.sheet(item:)`
- [ ] Update all sheet triggers to use coordinator
- [ ] Update MessageBubble callbacks to use coordinator
- [ ] Update InputBar callbacks to use coordinator
- [ ] Update menu action handlers to use coordinator
- [ ] Run full test suite
- [ ] Verify build time improvement

---

## Why This Is Better Than ViewModifier Groups

| Aspect | ViewModifier Groups | Single Sheet Pattern |
|--------|--------------------|--------------------|
| Type-checking | Still 14 sheets, just grouped | 1 sheet modifier total |
| Code complexity | Adds intermediate types | Simplifies to enum + switch |
| Apple recommendation | Not standard pattern | Canonical SwiftUI pattern |
| State management | Still 8 @State | 1 @State coordinator |
| Extensibility | Add new modifier group | Add enum case |
| Debugging | Multiple bindings | Single activeSheet |

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Enum case explosion | Group related cases, use associated values |
| Sheet-specific onDismiss | Store callback in coordinator |
| ViewModel sheet bindings | Keep viewModel.showSettings etc, sync with coordinator |
| Legacy iOS support | ChatSheetContent can have #available checks |

---

## Estimated Effort

| Step | Effort |
|------|--------|
| Create ChatSheet enum | 30 min |
| Create SheetCoordinator | 30 min |
| Create ChatSheetContent | 1 hour |
| Update ChatView | 1 hour |
| Update all triggers | 1 hour |
| Testing | 1 hour |
| **Total** | **5 hours** |

---

## Sources

- [How to present multiple sheets - Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-present-multiple-sheets)
- [How to manage multiple sheets in SwiftUI - Masilotti.com](https://masilotti.com/multiple-sheets-swiftui/)
- [Sheets in SwiftUI explained - SwiftLee](https://www.avanderlee.com/swiftui/presenting-sheets/)
- [Global Sheets Pattern - AzamSharp](https://azamsharp.com/2024/08/18/global-sheets-pattern-swiftui.html)
- [TCA Discussion on sheet type-checking](https://github.com/pointfreeco/swift-composable-architecture/discussions/2922)
- [Using Enums for varied sheet presentation - Medium](https://medium.com/@jenya.dev/using-enums-in-swiftui-for-varied-sheet-presentation-b71068b63365)
