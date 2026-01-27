# iOS App Architecture Refactoring Plan - Phase 2

## Current Score: 78/100
## Target Score: 88-92/100

---

## Phase 6: Extract Token Formatting Utility (Low Risk)

**Goal:** Eliminate 14 duplicate `formatTokens()` functions with a shared utility

### 6.1 Create TokenFormatter Utility (TDD)

**Files to create:**
- `Sources/Utilities/TokenFormatter.swift`
- `Tests/Utilities/TokenFormatterTests.swift`

**Write tests first:**
```swift
func test_formatTokens_returnsRawNumber_under1000()
func test_formatTokens_returns1kFormat_at1000()
func test_formatTokens_returns1_5kFormat_at1500()
func test_formatTokens_handlesLargeNumbers()
func test_formatTokens_handlesZero()
func test_formatTokens_handlesNegative()
```

**Implementation:**
```swift
enum TokenFormatter {
    /// Format token count for display (e.g., 1500 -> "1.5k")
    static func format(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    /// Format with explicit suffix (e.g., "1.5k tokens")
    static func formatWithSuffix(_ count: Int, suffix: String = "tokens") -> String {
        "\(format(count)) \(suffix)"
    }
}
```

### 6.2 Replace All Duplicate Implementations

**Files to modify (14 locations):**
| File | Lines to Remove |
|------|-----------------|
| `Database/EventTypes.swift` | ~281 |
| `Models/Messages/Message.swift` | ~250-255 |
| `Views/System/CompactionDetailSheet.swift` | ~158, ~192 |
| `Views/ContextAudit/ContextMessageViews.swift` | ~47, ~188, ~311 |
| `Views/ContextAudit/ToolSectionViews.swift` | ~11, ~137 |
| `Views/ContextAudit/SystemPromptSection.swift` | ~11 |
| `Views/ContextAudit/RulesSectionViews.swift` | ~11 |
| `Views/ContextAudit/SkillSectionViews.swift` | ~21 |
| `Views/ContextAudit/TurnBreakdownViews.swift` | ~10, ~96 |

**Search/Replace Pattern:**
```swift
// FROM:
private func formatTokens(_ count: Int) -> String {
    if count >= 1000 {
        return String(format: "%.1fk", Double(count) / 1000)
    }
    return "\(count)"
}
// ... later in code:
Text(formatTokens(tokens))

// TO:
Text(TokenFormatter.format(tokens))
```

### 6.3 Success Criteria
- [ ] `TokenFormatterTests.swift` has 6+ passing tests
- [ ] All 14 duplicate functions removed
- [ ] All usages replaced with `TokenFormatter.format()`
- [ ] iOS build succeeds
- [ ] All existing tests pass

---

## Phase 7: Split Message.swift (Medium Risk)

**Goal:** Break 863-line Message.swift into focused model files

### 7.1 Analyze Current Structure

Message.swift contains:
1. **Model Name Formatting** (lines 1-42) - 42 lines
2. **ChatMessage struct** (lines 44-161) - 118 lines
3. **MessageRole enum** (lines 163-179) - 17 lines
4. **SystemEvent enum** (lines 181-256) - 76 lines
5. **MessageContent enum** (lines 258-412) - 155 lines
6. **ToolUseData struct** (lines 414-454) - 41 lines
7. **ToolStatus enum** (lines 456-470) - 15 lines
8. **ToolResultData struct** (lines 472-497) - 26 lines
9. **ImageContent struct** (lines 499-511) - 13 lines
10. **Message Extensions** (lines 513-606) - 94 lines
11. **RenderAppUI Types** (lines 608-642) - 35 lines
12. **TodoWrite Types** (lines 644-656) - 13 lines
13. **NotifyApp Types** (lines 658-688) - 31 lines
14. **Subagent Types** (lines 690-742) - 53 lines
15. **AskUserQuestion Types** (lines 744-863) - 120 lines

### 7.2 Create Split Files

**New file structure:**
```
Sources/Models/Messages/
├── ChatMessage.swift           # ChatMessage struct + MessageRole (135 lines)
├── MessageContent.swift        # MessageContent enum (155 lines)
├── SystemEvent.swift           # SystemEvent enum (76 lines)
├── ToolTypes.swift             # ToolUseData, ToolStatus, ToolResultData (82 lines)
├── ImageContent.swift          # ImageContent struct (13 lines)
├── MessageExtensions.swift     # Message helper extensions (94 lines)
├── RenderAppUITypes.swift      # RenderAppUI chip data (35 lines)
├── TodoWriteTypes.swift        # TodoWrite action types (13 lines)
├── NotifyAppTypes.swift        # NotifyApp notification types (31 lines)
├── SubagentTypes.swift         # Subagent tool data types (53 lines)
├── AskUserQuestionTypes.swift  # AskUserQuestion types (120 lines)
└── ModelNameFormatter.swift    # Model display name formatting (42 lines)
```

### 7.3 Write Tests for Each Split (TDD)

**File to create:** `Tests/Models/MessageTypesTests.swift`

```swift
// Test each type's core functionality
func test_chatMessage_canBeDeleted_requiresEventId()
func test_chatMessage_formattedLatency_formatsMilliseconds()
func test_messageRole_displayName_returnsCorrect()
func test_systemEvent_textContent_formatsCompaction()
func test_messageContent_convenienceFactories_work()
func test_toolUseData_displayTitle_usesNameOrId()
func test_toolStatus_color_matchesState()
```

### 7.4 Implementation Order

1. Create `ModelNameFormatter.swift` (standalone, no dependencies)
2. Create `SystemEvent.swift` (uses TokenFormatter)
3. Create `ToolTypes.swift` (standalone)
4. Create `ImageContent.swift` (standalone)
5. Create `RenderAppUITypes.swift`, `TodoWriteTypes.swift`, `NotifyAppTypes.swift` (standalone)
6. Create `SubagentTypes.swift`, `AskUserQuestionTypes.swift` (standalone)
7. Create `MessageContent.swift` (imports tool types)
8. Create `ChatMessage.swift` (imports MessageContent, MessageRole)
9. Create `MessageExtensions.swift` (imports ChatMessage)
10. Delete original `Message.swift`
11. Update Xcode project

### 7.5 Success Criteria
- [ ] 12 new files created, each <200 lines
- [ ] Original `Message.swift` deleted
- [ ] `MessageTypesTests.swift` has 7+ passing tests
- [ ] All existing tests pass
- [ ] iOS build succeeds

---

## Phase 8: Split NewSessionFlow.swift (Medium Risk)

**Goal:** Break 707-line NewSessionFlow into focused components

### 8.1 Analyze Current Structure

```
NewSessionFlow.swift contains:
- NewSessionFlow view (lines 1-525) - Main flow
  - State properties (lines 16-36)
  - Computed properties (lines 38-65)
  - Body (lines 67-304)
  - Actions (lines 336-454)
  - Recent Sessions Section (lines 456-524)
- RecentSessionRow view (lines 526-620) - 95 lines
- SessionPreviewSheetWrapper (lines 621-707) - 87 lines
```

### 8.2 Create Split Files

**New file structure:**
```
Sources/Views/Session/
├── NewSessionFlow.swift          # Main flow (reduced to ~350 lines)
├── NewSessionFlowState.swift     # @Observable state class (~80 lines)
├── RecentSessionRow.swift        # Server session row (~95 lines)
├── SessionPreviewSheet.swift     # Preview wrapper (~87 lines)
└── WorkspaceSelectorButton.swift # Extracted workspace button (~60 lines)
```

### 8.3 Extract State to Observable Class

```swift
// NewSessionFlowState.swift
@Observable
@MainActor
final class NewSessionFlowState {
    var workingDirectory = ""
    var selectedModel: String = ""
    var isCreating = false
    var errorMessage: String?
    var showWorkspaceSelector = false
    var availableModels: [ModelInfo] = []
    var isLoadingModels = false
    var serverSessions: [SessionInfo] = []
    var isLoadingServerSessions = false
    var serverSessionsError: String? = nil
    var previewSession: SessionInfo? = nil
    var showCloneSheet = false
    var invalidWorkspacePaths: Set<String> = []

    var canCreate: Bool {
        !isCreating && !workingDirectory.isEmpty && !selectedModel.isEmpty
    }

    func filteredRecentSessions(excluding localSessionIds: Set<String>) -> [SessionInfo] {
        // Move filtering logic here
    }
}
```

### 8.4 Success Criteria
- [ ] 4 new files created
- [ ] `NewSessionFlow.swift` reduced to ~350 lines
- [ ] Each extracted file <150 lines
- [ ] iOS build succeeds
- [ ] Manual testing: create new session, select workspace, fork session

---

## Phase 9: Split SubagentDetailSheet.swift (Medium Risk)

**Goal:** Break 652-line SubagentDetailSheet into focused components

### 9.1 Analyze Current Structure

```
SubagentDetailSheet.swift contains:
- SubagentDetailSheet view (lines 1-517) - Main sheet
  - Header card (lines 129-161)
  - Task section (lines 162-188)
  - Activity section (lines 189-281)
  - Show more button (lines 282-311)
  - Summary section (lines 312-407)
  - Error section (lines 408-444)
  - Helpers (lines 445-517)
- StatusBadge view (lines 518-543) - 26 lines
- SubagentEventRow view (lines 544-652) - 109 lines
```

### 9.2 Create Split Files

**New file structure:**
```
Sources/Views/Subagents/
├── SubagentDetailSheet.swift     # Main sheet (reduced to ~250 lines)
├── SubagentHeaderCard.swift      # Status/turns/duration card (~80 lines)
├── SubagentTaskSection.swift     # Task description section (~60 lines)
├── SubagentActivitySection.swift # Activity list section (~120 lines)
├── SubagentSummarySection.swift  # Output summary section (~100 lines)
├── SubagentEventRow.swift        # Individual event row (~110 lines)
└── SubagentStatusBadge.swift     # Status badge view (~30 lines)
```

### 9.3 Success Criteria
- [ ] 6 new files created
- [ ] `SubagentDetailSheet.swift` reduced to ~250 lines
- [ ] Each extracted file <150 lines
- [ ] iOS build succeeds
- [ ] Manual testing: open subagent detail, verify all sections render

---

## Phase 10: Split InputBar.swift (Medium Risk)

**Goal:** Break 640-line InputBar into focused components

### 10.1 Analyze Current Structure

```
InputBar.swift contains:
- InputBar view (lines 1-594) - Main input
  - State properties (lines 19-44)
  - Computed properties (lines 46-74)
  - Body (lines 76-303)
  - Content area (lines 304-344)
  - Text field (lines 345-378)
  - Skill mention detection (lines 379-478)
  - Spell mention detection (lines 479-594)
- iOS 26 workaround notifications (lines 595-605)
- Preview (lines 606-640)
```

### 10.2 Create Split Files

**New file structure:**
```
Sources/Views/InputBar/
├── InputBar.swift                # Main container (reduced to ~200 lines)
├── InputBarTextField.swift       # Text field with @ detection (~100 lines)
├── InputBarActionButtons.swift   # Send/abort/mic buttons (~80 lines)
├── SkillMentionPopup.swift       # Skill autocomplete popup (~120 lines)
├── SpellMentionPopup.swift       # Spell autocomplete popup (~120 lines)
└── InputBarContentArea.swift     # Attachments/skills display (~80 lines)
```

### 10.3 Success Criteria
- [ ] 5 new files created
- [ ] `InputBar.swift` reduced to ~200 lines
- [ ] Each extracted file <150 lines
- [ ] iOS build succeeds
- [ ] Manual testing: type message, use @ mentions, send with attachments

---

## Phase 11: Extract Pagination Coordinator from ChatViewModel (High Risk)

**Goal:** Extract ChatViewModel+Pagination.swift (312 lines) to dedicated coordinator

### 11.1 Create PaginationCoordinator

**Files to create:**
- `Sources/ViewModels/Handlers/PaginationCoordinator.swift`
- `Sources/ViewModels/Handlers/PaginationContext.swift`
- `Tests/ViewModels/PaginationCoordinatorTests.swift`

**Write tests first:**
```swift
func test_loadInitialMessages_setsMessages()
func test_loadMoreMessages_appendsOlderMessages()
func test_loadMoreMessages_setsHasMore()
func test_findMessage_byId_returnsCorrectIndex()
func test_scrollToMessage_updatesScrollTarget()
```

### 11.2 Implementation

```swift
// PaginationContext.swift
@MainActor
protocol PaginationContext: AnyObject {
    var messages: [ChatMessage] { get set }
    var hasMoreMessages: Bool { get set }
    var isLoadingMoreMessages: Bool { get set }
    var sessionId: String { get }
    var eventStoreManager: EventStoreManager { get }

    func logDebug(_ message: String)
    func logError(_ message: String)
}

// PaginationCoordinator.swift
@MainActor
final class PaginationCoordinator {
    private weak var context: PaginationContext?

    init(context: PaginationContext) {
        self.context = context
    }

    func loadInitialMessages() async { ... }
    func loadMoreMessages() async { ... }
    func findMessage(byId: UUID) -> Int? { ... }
    func findMessage(byEventId: String) -> Int? { ... }
    func appendMessage(_ message: ChatMessage) { ... }
    func insertMessage(_ message: ChatMessage, at index: Int) { ... }
}
```

### 11.3 Success Criteria
- [ ] `PaginationCoordinator.swift` created (~200 lines)
- [ ] `PaginationContext.swift` created (~30 lines)
- [ ] `PaginationCoordinatorTests.swift` has 5+ passing tests
- [ ] `ChatViewModel+Pagination.swift` reduced to thin wrapper (~50 lines)
- [ ] iOS build succeeds
- [ ] Manual testing: scroll to load older messages

---

## Verification Checklist

After each phase:
```bash
# Build iOS
cd packages/ios-app && xcodebuild -scheme TronMobile -destination 'generic/platform=iOS' build

# Run iOS tests
xcodebuild test -scheme TronMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TronMobileTests

# Run TypeScript tests
bun run build && bun run test
```

---

## Summary Table

| Phase | Task | Files Created | Lines Saved | Risk | Score Impact |
|-------|------|---------------|-------------|------|--------------|
| 6 | TokenFormatter utility | 2 | ~100 | Low | +2-3 |
| 7 | Split Message.swift | 12 | 0 (reorg) | Medium | +2-3 |
| 8 | Split NewSessionFlow.swift | 4 | 0 (reorg) | Medium | +1-2 |
| 9 | Split SubagentDetailSheet.swift | 6 | 0 (reorg) | Medium | +1-2 |
| 10 | Split InputBar.swift | 5 | 0 (reorg) | Medium | +1-2 |
| 11 | PaginationCoordinator | 3 | ~260 | High | +2-3 |

**Total Potential Improvement: +10-14 points → Target: 88-92/100**

---

## Execution Order

1. **Phase 6** first - Simplest, establishes shared utility pattern
2. **Phase 7** second - Largest impact on model layer
3. **Phase 8-10** in parallel - View layer splits are independent
4. **Phase 11** last - Highest risk, benefits from earlier patterns

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Breaking imports | Each phase updates Xcode project before testing |
| Missing type references | Run build after each file creation |
| Test failures | Write tests first, verify after each step |
| View rendering issues | Manual testing after view splits |

---

## Anti-Patterns Addressed

| Anti-Pattern | Phase | Resolution |
|--------------|-------|------------|
| formatTokens duplication (14x) | 6 | Single TokenFormatter utility |
| Message.swift god model (863 lines) | 7 | 12 focused type files |
| NewSessionFlow large view (707 lines) | 8 | State class + 4 focused views |
| SubagentDetailSheet large view (652 lines) | 9 | 6 focused section views |
| InputBar large view (640 lines) | 10 | 5 focused components |
| ChatViewModel+Pagination (312 lines) | 11 | Dedicated coordinator |
