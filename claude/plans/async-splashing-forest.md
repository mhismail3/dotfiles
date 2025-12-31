# Claude Code Terminal UI Architecture - Reverse Engineering Analysis

**File**: `/Users/moose/Downloads/projects/clauset/cli.js`
**Version**: 2.0.76
**Size**: 10.5MB (5039 lines minified)

---

## Executive Summary

Claude Code uses **Ink** (React for the terminal) with **Yoga** (flexbox layout engine) to render a reactive terminal UI. The architecture follows React patterns with heavy use of hooks and context for state management, while leveraging streaming APIs for real-time content updates.

---

## Core Architecture

### 1. Rendering Framework: Ink + React

**Ink Components** (React for CLI):
- `ink-box` (5 refs) - Container component with flexbox layout
- `ink-text` (9 refs) - Text rendering with ANSI styling
- `ink-link` (5 refs) - Clickable hyperlinks in terminal
- `ink-progress` (3 refs) - Progress bar components
- `ink-virtual-text` (5 refs) - Virtualized text for performance
- `ink-root` (2 refs) - Root container

**React Internals**:
- `Fiber` (86 refs) + `Reconciler` (5 refs) - React's concurrent rendering
- `Scheduler` (83 refs) - Async update scheduling
- Single `<App` entry point with `render()` (99 refs)

### 2. State Management

**React Context Pattern** (29 `createContext` calls):
- Multiple context providers for different concerns
- No external state library (zustand/redux/etc)

**React Hooks Usage**:
| Hook | Count |
|------|-------|
| useState | 476 |
| useEffect | 232 |
| useCallback | 214 |
| useMemo | 167 |
| useRef | 100 |
| useContext | 33 |
| useReducer | 13 |

### 3. Layout System: Yoga (Flexbox)

Heavy flexbox usage for terminal layout:
- `flexDirection` (850 refs) - Primary layout direction
- `flexShrink` (39 refs) / `flexGrow` (14 refs)
- `alignItems` (21 refs) / `justifyContent` (36 refs)
- `flexWrap` (25 refs)

Box model properties:
- `padding` (407 refs) / `margin` (661 refs)
- `width` (591 refs) / `height` (342 refs)
- `borderStyle` (105 refs) / `borderColor` (62 refs)

---

## Content Rendering Pipeline

### 1. Streaming Text (Claude API)

**Protocol**:
- `content_block` (36 refs) - Message content blocks
- `content_block_delta` (9 refs) - Incremental updates
- `text_delta` (7 refs) - Text streaming chunks
- `delta` (127 refs) - Generic deltas

**Transport**:
- `SSE` (63 refs) - Server-Sent Events
- `EventSource` (6 refs) - SSE client
- Heavy stream usage (1434 total stream/Stream refs)

### 2. Markdown Rendering

- `marked` (12 refs) - Markdown parser
- `markdown` (57 refs) - Markdown content handling
- Converts markdown to styled terminal output

### 3. Syntax Highlighting

- `Prism` (12 refs) - Code syntax highlighting
- `highlight` (92 refs) + `Highlight` (21 refs)
- `syntaxHighlight` (7 refs)
- Renders code blocks with ANSI colors

### 4. ANSI Terminal Styling

- `ansi` (409 refs) - ANSI escape sequences
- Color management: `color` (1507) + `Color` (1448)
- Theme support: `theme` (97) + `Theme` (49)
- Palette: `palette` (32) + `Palette` (20)

---

## UI Components

### Message Display

- `MessageList` (3 refs) - Container for messages
- `UserMessage` (13 refs) - User input display
- `AssistantMessage` (1 ref) - AI response display
- `ToolResult` (99 refs) - Tool execution results

### Interactive Elements

- `Permission` (439 refs) / `permission` (468 refs) - Permission prompts
- `Dialog` (94 refs) / `dialog` (64 refs) - Modal dialogs
- `confirm` (63 refs) / `Confirm` (49 refs) - Confirmation UI
- `approve` (58 refs) / `Approve` (10 refs) - Approval buttons

### Status Indicators

- `ora` (797 refs) - Spinner/loading library
- `Spinner` (19 refs) - Loading spinners
- `Progress` (228 refs) / `Loading` (74 refs)
- `StatusLine` (4 refs) - Status bar

### Task Management

- `TodoList` (4 refs) - Task list component
- `todo` (112 refs) / `Todo` (33 refs)
- `checkbox` (29 refs) - Checkbox elements

### Code Display

- `CodeBlock` (2 refs) / `codeBlock` (4 refs)
- `Diff` (89 refs) / `diff` (288 refs) - Code diffs
- `Collapsible` (4 refs) / `Expandable` (2 refs)
- `toggle` (68 refs) - Expand/collapse

### Text Handling

- `truncate` (144 refs) / `Truncate` (16 refs)
- `overflow` (99 refs) - Overflow handling
- `ellipsis` (19 refs) - Text truncation indicator

---

## Input Handling

### Text Input

- `TextInput` (12 refs) - Primary text input component
- `InputBox` (2 refs) - Input container
- `stdin` (113 refs) - Standard input handling

### Keyboard Events

- `onKey` (56 refs) - Key event handlers
- `keypress` (12 refs) - Keypress events
- `shortcut` (150 refs) - Keyboard shortcuts
- `hotkey` (7 refs) - Hotkey bindings

### Terminal Mode

- `rawMode` (7 refs) / `setRawMode` (11 refs) - Raw input mode
- `isRaw` (10 refs) - Raw mode detection
- `alternate` (106 refs) / `alternateScreen` (1 ref) - Full-screen mode

---

## Shell Execution

### PTY (Pseudo-Terminal)

- `pty` (583 refs) - Pseudo-terminal for shell
- `xterm` (10 refs) - xterm emulation
- `tty` (151 refs) - Terminal type

### Process Management

- `child_process` (44 refs) - Node.js child processes
- `spawn` (57 refs) - Process spawning
- `fork` (130 refs) - Process forking
- `exec` (188 refs) - Command execution
- `execa` (3 refs) - Enhanced execution

### Output Handling

- `stdout.write` (53 refs) / `stderr.write` (88 refs)
- `write()` (256 refs) - General output

---

## Rendering Updates

### React-Style Updates

- `refresh` (418 refs) - Trigger re-renders
- `forceUpdate` (16 refs) - Force component updates
- `rerender` (6 refs) - Re-render calls
- `invalidate` (9 refs) - Mark for update

### Viewport Management

- `scroll` (67 refs) / `Scroll` (35 refs)
- `viewport` (26 refs) / `Viewport` (6 refs)
- `window` (455 refs) - Window/viewport calculations
- `Virtual` (15 refs) - Virtualization

---

## Key Dependencies

| Library | Purpose | Evidence |
|---------|---------|----------|
| Ink | React for terminals | ink-* components |
| Yoga | Flexbox layout | flexDirection, etc |
| marked | Markdown parsing | marked refs |
| Prism | Syntax highlighting | Prism refs |
| ora | Spinners | 797 refs |
| node-pty | Shell execution | pty refs |
| chalk | Terminal colors | chalk.* |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Claude Code CLI                         │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   <App>     │  │   Context   │  │   State (hooks)     │  │
│  │  (ink-root) │  │  Providers  │  │ useState/useEffect  │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │
│         │                │                     │             │
│  ┌──────▼────────────────▼─────────────────────▼──────────┐  │
│  │                    Ink Renderer                        │  │
│  │  ┌─────────┐ ┌─────────┐ ┌──────────┐ ┌─────────────┐  │  │
│  │  │ ink-box │ │ink-text │ │ink-link  │ │ink-progress │  │  │
│  │  └────┬────┘ └────┬────┘ └────┬─────┘ └──────┬──────┘  │  │
│  └───────┼───────────┼───────────┼──────────────┼─────────┘  │
│          │           │           │              │            │
│  ┌───────▼───────────▼───────────▼──────────────▼─────────┐  │
│  │                  Yoga Layout Engine                    │  │
│  │            (flexbox calculations)                      │  │
│  └───────────────────────┬────────────────────────────────┘  │
│                          │                                   │
│  ┌───────────────────────▼────────────────────────────────┐  │
│  │               ANSI Output Generator                    │  │
│  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────────────┐   │  │
│  │  │ Colors │ │ Styles │ │ Cursor │ │ Screen Control │   │  │
│  │  └────────┘ └────────┘ └────────┘ └────────────────┘   │  │
│  └───────────────────────┬────────────────────────────────┘  │
│                          │                                   │
│  ┌───────────────────────▼────────────────────────────────┐  │
│  │                  stdout.write()                        │  │
│  └────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                    Content Pipeline                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐   │
│  │ SSE/     │  │ Markdown │  │  Prism   │  │   Diff     │   │
│  │ Streaming│→ │ (marked) │→ │ Syntax   │→ │  Render    │   │
│  │ deltas   │  │          │  │ Highlight│  │            │   │
│  └──────────┘  └──────────┘  └──────────┘  └────────────┘   │
├─────────────────────────────────────────────────────────────┤
│                    Shell Execution                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                   │
│  │   PTY    │  │  xterm   │  │  stdout  │                   │
│  │ (spawn)  │→ │ emulation│→ │ capture  │                   │
│  └──────────┘  └──────────┘  └──────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Insights for Building Similar UIs

1. **Use Ink** for React-based terminal UIs with familiar component patterns
2. **Yoga layout** provides CSS flexbox in the terminal
3. **Stream content** using SSE with delta updates for real-time feel
4. **marked + Prism** for markdown with syntax highlighting
5. **ora** for consistent spinner/loading states
6. **React Context** is sufficient for state management in CLI apps
7. **PTY** enables full shell emulation for command execution
8. **ANSI escape sequences** for colors, cursor control, screen management

---

*This is a research document - no implementation changes needed.*
