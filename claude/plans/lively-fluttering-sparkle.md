# Plan: Unified Result Content Rendering for iOS App

## Problem Summary

Result blocks across the iOS app have inconsistent rendering:
- **Only `ReadResultViewer`** strips server-side line prefixes ("1→", "2→")
- Other viewers (Bash, StandaloneToolResult, Generic) add their own line numbers without stripping
- **Context audit** shows raw content with "1→", "2→" prefixes
- Duplicated expand/collapse logic across 6+ viewers

## Solution Overview

Create a shared `LineNumberedContentView` component and `ContentLineParser` utility that all viewers use, ensuring consistent line number handling and display.

## Files to Create

### 1. `Sources/Views/Components/ContentLineParser.swift` (NEW)

```swift
import Foundation

/// Utility for parsing content with server-side line number prefixes
/// Centralizes the logic from ReadResultViewer for reuse across all viewers
struct ContentLineParser {
    struct ParsedLine: Identifiable {
        let id: Int  // For ForEach - uses offset
        let lineNum: Int
        let content: String
    }

    /// Parse content, stripping server-side line number prefixes
    /// Handles patterns: "123→content", "  123\tcontent", "123:content"
    static func parse(_ content: String) -> [ParsedLine] {
        content.components(separatedBy: "\n").enumerated().map { index, line in
            // Match server-side line number prefixes (from Read tool output)
            if let match = line.firstMatch(of: /^\s*(\d+)[→\t:](.*)/) {
                return ParsedLine(
                    id: index,
                    lineNum: Int(match.1) ?? (index + 1),
                    content: String(match.2)
                )
            }
            // No server-side prefix - use sequential numbering
            return ParsedLine(id: index, lineNum: index + 1, content: line)
        }
    }
}
```

### 2. `Sources/Views/Components/LineNumberedContentView.swift` (NEW)

```swift
import SwiftUI

/// Unified view for displaying content with line numbers
/// Strips server-side line prefixes and displays clean formatted output
struct LineNumberedContentView: View {
    let content: String
    let maxCollapsedLines: Int
    @Binding var isExpanded: Bool

    // Customization with defaults matching existing viewers
    var fontSize: CGFloat = 11
    var lineNumFontSize: CGFloat = 9
    var maxCollapsedHeight: CGFloat = 200
    var lineHeight: CGFloat = 16
    var showExpandButton: Bool = true

    private var parsedLines: [ContentLineParser.ParsedLine] {
        ContentLineParser.parse(content)
    }

    private var displayLines: [ContentLineParser.ParsedLine] {
        isExpanded ? parsedLines : Array(parsedLines.prefix(maxCollapsedLines))
    }

    /// Calculate optimal width for line numbers based on max line number
    private var lineNumWidth: CGFloat {
        let maxNum = parsedLines.last?.lineNum ?? parsedLines.count
        let digits = String(maxNum).count
        return CGFloat(max(digits * 8, 16)) // ~8pt per digit, min 16pt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(displayLines) { line in
                        HStack(spacing: 0) {
                            // Line number gutter
                            Text("\(line.lineNum)")
                                .font(.system(size: lineNumFontSize, design: .monospaced))
                                .foregroundStyle(.tronTextMuted.opacity(0.4))
                                .frame(width: lineNumWidth, alignment: .trailing)
                                .padding(.leading, 4)
                                .padding(.trailing, 8)

                            // Content
                            Text(line.content.isEmpty ? " " : line.content)
                                .font(.system(size: fontSize, design: .monospaced))
                                .foregroundStyle(.tronTextSecondary)
                        }
                        .frame(minHeight: lineHeight)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: isExpanded ? .infinity : maxCollapsedHeight)

            // Expand/collapse button
            if showExpandButton && parsedLines.count > maxCollapsedLines {
                Button {
                    withAnimation(.tronFast) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text(isExpanded ? "Show less" : "Show more (\(parsedLines.count) lines)")
                            .font(.system(size: 10, design: .monospaced))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.tronTextMuted)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.tronSurface)
                }
            }
        }
    }
}

// MARK: - Convenience initializer for simpler cases

extension LineNumberedContentView {
    /// Convenience initializer with internal state management
    init(content: String, maxCollapsedLines: Int = 12, maxCollapsedHeight: CGFloat = 200) {
        self.content = content
        self.maxCollapsedLines = maxCollapsedLines
        self._isExpanded = .constant(false) // Will be overridden by wrapper
        self.maxCollapsedHeight = maxCollapsedHeight
    }
}

/// Wrapper that manages its own expansion state
struct LineNumberedContentViewWithState: View {
    let content: String
    let maxCollapsedLines: Int
    var fontSize: CGFloat = 11
    var lineNumFontSize: CGFloat = 9
    var maxCollapsedHeight: CGFloat = 200

    @State private var isExpanded = false

    var body: some View {
        LineNumberedContentView(
            content: content,
            maxCollapsedLines: maxCollapsedLines,
            isExpanded: $isExpanded,
            fontSize: fontSize,
            lineNumFontSize: lineNumFontSize,
            maxCollapsedHeight: maxCollapsedHeight
        )
    }
}
```

## Files to Modify

### 1. `ContextMessageViews.swift` - DetailedMessageRow

**Current (lines 11, 136-148):**
```swift
@State private var isExpanded = false
// ...
if !message.content.isEmpty {
    ScrollView {
        Text(message.content)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .textSelection(.enabled)
    }
    .frame(maxHeight: 200)
    .background(Color.black.opacity(0.2))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
}
```

**New:**
```swift
@State private var isExpanded = false
@State private var contentExpanded = false  // ADD this new state
// ...
if !message.content.isEmpty {
    LineNumberedContentView(
        content: message.content,
        maxCollapsedLines: 12,
        isExpanded: $contentExpanded,
        fontSize: 10,
        lineNumFontSize: 9,
        maxCollapsedHeight: 200
    )
    .background(Color.black.opacity(0.2))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
}
```

### 2. `FileToolViewer.swift` - ReadResultViewer

**Current (lines 10-22):**
```swift
private var parsedLines: [(lineNum: Int, content: String)] {
    content.components(separatedBy: "\n").enumerated().map { index, line in
        if let match = line.firstMatch(of: /^\s*(\d+)[→\t:](.*)/) {
            return (Int(match.1) ?? (index + 1), String(match.2))
        }
        return (index + 1, line)
    }
}
```

**New:**
```swift
private var parsedLines: [ContentLineParser.ParsedLine] {
    ContentLineParser.parse(content)
}
```

Also update references from `parsedLines.last?.lineNum` to `parsedLines.last?.lineNum` (no change needed - same property name).

Update `displayLines` return type:
```swift
private var displayLines: [ContentLineParser.ParsedLine] {
    isExpanded ? parsedLines : Array(parsedLines.prefix(12))
}
```

Update ForEach usage (line ~101):
```swift
ForEach(displayLines) { line in
    HStack(spacing: 0) {
        Text("\(line.lineNum)")
        // ...
        Text(line.content.isEmpty ? " " : line.content)
        // ...
    }
}
```

### 3. `BashToolViewer.swift`

**Current (lines 10-73):** Full inline implementation with own line numbering.

**New:** Replace the entire body content section with `LineNumberedContentView`:

```swift
struct BashResultViewer: View {
    let command: String
    let output: String
    @Binding var isExpanded: Bool

    var body: some View {
        LineNumberedContentView(
            content: output,
            maxCollapsedLines: 8,
            isExpanded: $isExpanded,
            fontSize: 11,
            lineNumFontSize: 9,
            maxCollapsedHeight: 140,
            lineHeight: 16
        )
    }
}
```

**Note:** This is a significant simplification but maintains exact same behavior:
- 8 collapsed lines (was `prefix(8)`)
- 140px max height (was `frame(maxHeight: 140)`)
- Same font sizes (9px line numbers, 11px content)
- Same animation (.tronFast)

### 4. `ToolResultViews.swift` - StandaloneToolResultView

**Current (lines 112-155):** Inline line rendering with header.

Keep the header section (lines 68-110) unchanged. Replace only the content display section:

```swift
// REPLACE lines 112-155 with:
// Content lines
LineNumberedContentView(
    content: result.content,
    maxCollapsedLines: 8,
    isExpanded: $isExpanded,
    fontSize: 11,
    lineNumFontSize: 10,
    maxCollapsedHeight: 160,
    lineHeight: 18
)
```

Note slightly different styling to match existing:
- lineNumFontSize: 10 (was 10 in this viewer)
- lineHeight: 18 (was `minHeight: 18`)
- maxCollapsedHeight: 160 (was 160)

### 5. `GenericToolViewer.swift`

**Current (lines 9-43):** Character-based truncation without line numbers.

**New:** Convert to line-based display with line numbers:

```swift
struct GenericResultViewer: View {
    let result: String
    @Binding var isExpanded: Bool

    var body: some View {
        LineNumberedContentView(
            content: result,
            maxCollapsedLines: 12,
            isExpanded: $isExpanded,
            maxCollapsedHeight: 200
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
```

**Behavioral change:** This changes from character-based (500 chars) to line-based (12 lines) truncation. This is an improvement for consistency.

## Xcode Project File Update

Add the two new files to the Xcode project. The files should be added to:
- Target: TronMobile
- Group: Sources/Views/Components (create this group)

## Verification Checklist

### Build
```bash
cd packages/ios-app && xcodebuild -scheme TronMobile -sdk iphonesimulator -configuration Debug build 2>&1 | head -100
```

### Test Each Viewer

1. **Context Audit Result Blocks** (original issue)
   - Open context manager sheet
   - Expand a result block
   - Verify: Clean line numbers on left, no "1→" prefixes in content

2. **Read Tool Results**
   - Read a file in chat
   - Verify: Line numbers match file line numbers (not 1, 2, 3 sequential)
   - Verify: Content properly stripped of prefixes

3. **Bash Tool Results**
   - Run a bash command
   - Verify: Clean sequential line numbers
   - Verify: 8 lines shown collapsed, expand works

4. **Standalone Tool Results** (toolResult content type)
   - Verify header still shows tool name, icon, duration
   - Verify content has clean line numbers

5. **Generic Tool Results**
   - Use an unknown tool type
   - Verify clean display with line numbers

### Regression Checks

- [ ] EditResultViewer diff colors still work (+green, -red)
- [ ] GrepResultViewer shows match counts
- [ ] FindResultViewer shows file list
- [ ] LsResultViewer shows directory icons
- [ ] AstGrepResultViewer shows captures
- [ ] Expand/collapse animations smooth (.tronFast)
- [ ] Horizontal scroll works for long lines
- [ ] Large files (1000+ lines) perform well

## Summary of Changes

| File | Change | Risk |
|------|--------|------|
| `Components/ContentLineParser.swift` | CREATE | None (new file) |
| `Components/LineNumberedContentView.swift` | CREATE | None (new file) |
| `ContextAudit/ContextMessageViews.swift` | MODIFY - use LineNumberedContentView | Low - isolated change |
| `ToolViewers/FileToolViewer.swift` | MODIFY - use ContentLineParser | Low - same logic, shared util |
| `ToolViewers/BashToolViewer.swift` | MODIFY - use LineNumberedContentView | Medium - full replacement but same behavior |
| `MessageBubble/ToolResultViews.swift` | MODIFY - use LineNumberedContentView | Medium - content section only |
| `ToolViewers/GenericToolViewer.swift` | MODIFY - use LineNumberedContentView | Low - improved display |

## Implementation Order

1. Create `ContentLineParser.swift` - pure utility, no dependencies
2. Create `LineNumberedContentView.swift` - depends on parser
3. Update `FileToolViewer.swift` - validate parser works correctly
4. Update `ContextMessageViews.swift` - fixes original issue
5. Update `BashToolViewer.swift` - major simplification
6. Update `ToolResultViews.swift` - keeps header, replaces content
7. Update `GenericToolViewer.swift` - improved display
8. Build and test all scenarios
