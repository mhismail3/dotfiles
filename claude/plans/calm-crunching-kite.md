# iPad Sheet Detent Implementation Plan

## Goal
Make iPad sheets default to **large detent** when opened, while keeping iPhone sheets at **medium detent**. Users on both devices can still resize sheets.

## Approach
Create a reusable `AdaptiveDetentModifier` in `View+Extensions.swift` that:
- Detects device type via `@Environment(\.horizontalSizeClass)`
- Sets initial detent to `.large` on iPad (`.regular` size class)
- Sets initial detent to `.medium` on iPhone (`.compact` size class)
- Allows user to resize between available detents

## Files to Modify

### 1. Add Modifier (1 file)

**`packages/ios-app/Sources/Extensions/View+Extensions.swift`**

Add after the existing View extension (around line 68):

```swift
// MARK: - Adaptive Presentation Detents

/// ViewModifier that makes sheets default to large on iPad, medium on iPhone
struct AdaptiveDetentModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedDetent: PresentationDetent = .medium

    let detents: Set<PresentationDetent>

    func body(content: Content) -> some View {
        content
            .presentationDetents(detents, selection: $selectedDetent)
            .onAppear {
                // iPad (regular) defaults to large, iPhone (compact) defaults to medium
                if horizontalSizeClass == .regular {
                    selectedDetent = detents.contains(.large) ? .large : (detents.first ?? .medium)
                } else {
                    selectedDetent = detents.contains(.medium) ? .medium : (detents.first ?? .large)
                }
            }
    }
}

extension View {
    /// Presentation detents with adaptive default: large on iPad, medium on iPhone
    func adaptivePresentationDetents(_ detents: Set<PresentationDetent>) -> some View {
        modifier(AdaptiveDetentModifier(detents: detents))
    }
}
```

### 2. Update Sheet Files (18 call sites in 15 files)

Replace `.presentationDetents([.medium, .large])` with `.adaptivePresentationDetents([.medium, .large])`:

| File | Line |
|------|------|
| `Views/Session/NewSessionFlow.swift` | 299 |
| `Views/Session/WorkspaceSelector.swift` | 83 |
| `Views/TodoDetailSheet.swift` | 48 |
| `Views/ThinkingDetailSheet.swift` | 32, 59 |
| `Views/AskUser/AskUserQuestionSheet.swift` | 69 |
| `Views/SessionTreeView.swift` | 1648, 1782 |
| `Views/ChatView.swift` | 358, 387 |
| `Views/NotifyAppDetailSheet.swift` | 39 |
| `Views/Settings/SettingsView.swift` | 223 |
| `Views/Skills/SkillDetailSheet.swift` | 58 |
| `Views/ContextAudit/ContextAuditView.swift` | 184 |
| `Views/Browser/BrowserSheetView.swift` | 70 |
| `Views/UICanvasSheet.swift` | 47, 243 |
| `Views/VoiceNotes/VoiceNoteDetailSheet.swift` | 69 |
| `Views/VoiceNotes/VoiceNotesRecordingSheet.swift` | 75 |

### 3. Update LogViewer.swift (special case)

**`Views/LogViewer.swift`**
- Remove `@State private var sheetDetent: PresentationDetent = .large` (line 12)
- Replace line 60: `.presentationDetents([.medium, .large], selection: $sheetDetent)`
- With: `.adaptivePresentationDetents([.medium, .large])`

### 4. Files to NOT modify (keep fixed detents)

| File | Reason |
|------|--------|
| `CloneRepoSheet.swift:103` | Fixed `.medium` only (compact form) |
| `NewSessionFlow.swift:686` | Fixed `.large` only (workspace browser) |
| `SessionPreviewSheet.swift:92` | Fixed `.large` only (history view) |
| `CameraCaptureSheet.swift:80` | Fixed `.medium` only (camera picker) |

## Verification

1. **Build**: `cd packages/ios-app && xcodebuild -scheme Tron -destination 'platform=iOS Simulator,name=iPhone 16' build`
2. **Test on iPhone Simulator**: Open any sheet (Settings, Skills, etc.) - should start at medium
3. **Test on iPad Simulator**: Open same sheets - should start at large
4. **Test resizing**: Drag sheets on both devices - should allow resizing between medium/large
5. **Run tests**: `xcodebuild test -scheme Tron -destination 'platform=iOS Simulator,name=iPhone 16'`
