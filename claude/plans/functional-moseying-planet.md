# Recursive Font Integration Plan for Tron iOS App

## Overview

Update the Tron iOS app to use [Recursive](https://recursive.design/) font family uniformly across all screens, replacing the current system fonts (San Francisco).

**Why Recursive?**
- Variable font with MONO axis: seamlessly switches between proportional (sans) and monospace
- Perfect match for the app's heavy use of both regular and monospaced fonts
- Open source (OFL license)
- Modern, highly legible design

---

## Phase 1: Font Asset Setup

### 1.1 Download Font Files

Download static instances from https://recursive.design/ (or Google Fonts):

```
Sources/Resources/Fonts/
  RecursiveMono-Regular.ttf      (code, messages)
  RecursiveMono-Medium.ttf       (emphasis)
  RecursiveMono-SemiBold.ttf     (headers)
  RecursiveMono-Bold.ttf         (strong emphasis)
  RecursiveSans-Regular.ttf      (body text)
  RecursiveSans-Medium.ttf       (labels)
  RecursiveSans-SemiBold.ttf     (buttons)
  RecursiveSans-Bold.ttf         (titles)
```

**Note:** Using static instances instead of variable font for better SwiftUI compatibility.

### 1.2 Update Info.plist

Add UIAppFonts key to register fonts:

**File:** `packages/ios-app/Sources/Info.plist`

```xml
<key>UIAppFonts</key>
<array>
    <string>Fonts/RecursiveMono-Regular.ttf</string>
    <string>Fonts/RecursiveMono-Medium.ttf</string>
    <string>Fonts/RecursiveMono-SemiBold.ttf</string>
    <string>Fonts/RecursiveMono-Bold.ttf</string>
    <string>Fonts/RecursiveSans-Regular.ttf</string>
    <string>Fonts/RecursiveSans-Medium.ttf</string>
    <string>Fonts/RecursiveSans-SemiBold.ttf</string>
    <string>Fonts/RecursiveSans-Bold.ttf</string>
</array>
```

### 1.3 Update project.yml

Add fonts as resources:

**File:** `packages/ios-app/project.yml`

```yaml
targets:
  TronMobile:
    sources:
      - path: Sources
        createIntermediateGroups: true
      - path: Sources/Resources/Fonts
        type: folder
        buildPhase: resources
```

### 1.4 Create Font Loader

**File:** `packages/ios-app/Sources/Theme/TronFontLoader.swift` (new file)

Utility to register fonts at app startup and verify availability.

---

## Phase 2: Typography System Restructure

### 2.1 Rewrite TronTypography.swift

**File:** `packages/ios-app/Sources/Theme/TronTypography.swift`

Replace current system font definitions with Recursive fonts:

**Key Changes:**
- Add font name constants for all 8 variants
- Keep existing size scale (8pt-20pt)
- Add new sizes: 7pt (XXS), 11pt (Body2), 13pt (Body3), 22pt (XXL), 24pt (Hero), 32pt (Display), 56pt (Timer)
- Create semantic presets mapped to Recursive fonts
- Add `mono(size:weight:)` and `sans(size:weight:)` factory methods
- Add `uiFont(mono:size:weight:)` for UIKit components
- Expand View extensions for common patterns

**Typography Presets:**

| Preset | Font | Size | Use Case |
|--------|------|------|----------|
| `code` | Mono Regular | 15pt | Code blocks |
| `messageBody` | Mono Regular | 14pt | Chat messages |
| `codeCaption` | Mono Regular | 11pt | Secondary code text |
| `codeSM` | Mono Regular | 10pt | Small code/metrics |
| `input` | Mono Regular | 15pt | Input fields |
| `filePath` | Mono Medium | 11pt | File paths |
| `button` | Sans SemiBold | 16pt | Primary buttons |
| `buttonSM` | Sans SemiBold | 14pt | Compact buttons |
| `pill` | Sans Medium | 9pt | Status pills |
| `badge` | Sans Bold | 8pt | Badges/counters |
| `caption` | Sans Regular | 10pt | Captions |
| `headline` | Sans SemiBold | 16pt | Section headers |

---

## Phase 3: View Migration

### 3.1 Migration Order (by priority)

**Priority 1: Core Chat Experience**
1. `Views/MessageBubble/TextContentView.swift`
2. `Views/MessageBubble/StreamingContentView.swift`
3. `Views/InputBar/InputBar.swift`
4. `Views/InputBar/InputTextField.swift`
5. `Views/InputBar/StatusPillBar.swift`

**Priority 2: Tool Viewers**
6. `Views/ToolViewers/FileToolViewer.swift`
7. `Views/ToolViewers/SearchToolViewer.swift`
8. `Views/ToolViewers/BrowserToolViewer.swift`
9. `Views/ToolViewers/ToolResultRouter.swift`

**Priority 3: UI Canvas**
10. `Views/UICanvas/ContentComponents.swift`
11. `Views/UICanvas/InteractiveComponents.swift`
12. `Views/UICanvas/DataComponents.swift`

**Priority 4: Sheets & Modals**
13. `Views/SubagentDetailSheet.swift`
14. `Views/VoiceNoteDetailSheet.swift`
15. `Views/SkillDetailSheet.swift`

**Priority 5: Remaining Views (~40 files)**
- Settings, sidebars, model switcher, context audit, etc.

### 3.2 Common Replacements

| Current | Replacement |
|---------|-------------|
| `.font(.system(size: 14, design: .monospaced))` | `.font(TronTypography.messageBody)` |
| `.font(.system(size: 15, design: .monospaced))` | `.font(TronTypography.code)` |
| `.font(.system(size: 11, design: .monospaced))` | `.font(TronTypography.codeCaption)` |
| `.font(.system(size: 10, design: .monospaced))` | `.font(TronTypography.codeSM)` |
| `.font(.system(.subheadline, design: .monospaced))` | `.font(TronTypography.input)` |
| `.font(.system(size: 16, weight: .semibold))` | `.font(TronTypography.button)` |
| `.font(.system(size: 14, weight: .semibold))` | `.font(TronTypography.buttonSM)` |
| `.font(.system(size: 9, weight: .medium))` | `.font(TronTypography.pill)` |
| `.font(.system(size: 8, weight: .bold))` | `.font(TronTypography.badge)` |
| `.font(.caption)` | `.font(TronTypography.caption)` |
| `.font(.headline)` | `.font(TronTypography.headline)` |

### 3.3 Special Cases

**UIKit Component (MultiLineTextView.swift):**
```swift
font: TronTypography.uiFont(mono: true, size: 15)
```

**UICanvas Dynamic Fonts:**
Update `CanvasText` to use `TronTypography.mono(size:weight:)` based on style props.

**Timer Display (56pt):**
```swift
.font(TronTypography.timerDisplay)
```

---

## Phase 4: App Initialization

**File:** `packages/ios-app/Sources/App/TronMobileApp.swift`

Add font registration at app launch:

```swift
init() {
    TronFontLoader.registerFonts()
    // ... existing init
}
```

---

## Phase 5: Verification

### 5.1 Build Steps
```bash
cd packages/ios-app
xcodegen generate
xcodebuild -scheme TronMobile -configuration Debug-Prod build
```

### 5.2 Manual Testing Screens

| Screen | What to Check |
|--------|--------------|
| Chat View | Messages, input field, status pills |
| Tool Viewers | File paths, code blocks, line numbers |
| Voice Notes | Timer (56pt), transcription text |
| Subagent Sheet | All monospaced content |
| Settings | Labels, toggles, headers |
| UI Canvas | Dynamic text rendering |

### 5.3 Automated Test

Add `Tests/FontTests.swift` to verify:
- Font registration succeeds
- Typography presets return valid fonts
- UIFont variants work correctly

---

## Files to Modify

### New Files
- `Sources/Resources/Fonts/` (8 .ttf files)
- `Sources/Theme/TronFontLoader.swift`
- `Tests/FontTests.swift`

### Modified Files
- `Sources/Info.plist` (add UIAppFonts)
- `project.yml` (add font resources)
- `Sources/Theme/TronTypography.swift` (rewrite)
- `Sources/App/TronMobileApp.swift` (add font registration)
- ~53 view files (font migration)

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Font metrics differ from system fonts | Test thoroughly; adjust spacing as needed |
| Bundle size increase (~500KB) | Acceptable for design consistency |
| Very small sizes (7-8pt) may render poorly | Test carefully; bump minimum if needed |
| UIKit/SwiftUI API differences | `TronTypography.uiFont()` handles explicitly |

---

## Estimated Scope

- **Phase 1-2:** 4-5 files, foundation work
- **Phase 3:** ~55 view files with font changes
- **Phase 4-5:** App init + verification

Total: ~60 files touched
