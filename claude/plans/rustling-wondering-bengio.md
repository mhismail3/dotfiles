# Clauset: Claude Code Session Dashboard

**Project**: Remote Claude Code session manager accessible from iPhone via Tailscale
**Stack**: Rust backend + SolidJS PWA frontend
**Security**: Tailscale-only (no additional auth layer)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Mac Mini (Always On)                     │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    Clauset Server (Rust)                    ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ ││
│  │  │ REST API    │  │ WebSocket   │  │ Static File Server  │ ││
│  │  │ (Axum)      │  │ (Real-time) │  │ (PWA Assets)        │ ││
│  │  └──────┬──────┘  └──────┬──────┘  └─────────────────────┘ ││
│  │         │                │                                  ││
│  │  ┌──────┴────────────────┴──────┐                          ││
│  │  │      Session Manager          │                          ││
│  │  │  ┌─────────┐  ┌────────────┐ │                          ││
│  │  │  │ Stream  │  │ Terminal   │ │                          ││
│  │  │  │ JSON    │  │ (PTY)      │ │                          ││
│  │  │  │ Mode    │  │ Mode       │ │                          ││
│  │  │  └────┬────┘  └─────┬──────┘ │                          ││
│  │  └───────┼─────────────┼────────┘                          ││
│  │          │             │                                    ││
│  │  ┌───────┴─────────────┴────────┐                          ││
│  │  │     Claude CLI Processes     │                          ││
│  │  │   /opt/homebrew/bin/claude   │                          ││
│  │  └──────────────────────────────┘                          ││
│  │                                                             ││
│  │  ┌─────────────┐  ┌─────────────────────────────────────┐  ││
│  │  │ SQLite DB   │  │ ~/.claude/ (sessions, history)      │  ││
│  │  └─────────────┘  └─────────────────────────────────────┘  ││
│  └─────────────────────────────────────────────────────────────┘│
│                              │                                   │
│                    Tailscale Network                             │
└──────────────────────────────┼───────────────────────────────────┘
                               │
                    ┌──────────┴──────────┐
                    │   iPhone (Safari)    │
                    │   ┌──────────────┐   │
                    │   │  PWA         │   │
                    │   │  (SolidJS)   │   │
                    │   └──────────────┘   │
                    └─────────────────────┘
```

---

## Project Structure

```
clauset/
├── Cargo.toml                      # Workspace root
├── crates/
│   ├── clauset-core/               # Session & process management
│   ├── clauset-server/             # HTTP/WebSocket server (Axum)
│   └── clauset-types/              # Shared DTOs
├── frontend/                       # SolidJS PWA
│   ├── src/
│   │   ├── components/
│   │   │   ├── chat/               # Chat UI components
│   │   │   ├── terminal/           # xterm.js integration
│   │   │   └── ui/                 # Shared primitives
│   │   ├── stores/                 # SolidJS signals/stores
│   │   ├── lib/                    # WebSocket, API, utils
│   │   └── pages/                  # Route components
│   ├── public/                     # PWA manifest, icons
│   └── vite.config.ts
├── config/
│   └── default.toml                # Server configuration
└── scripts/
    └── install-launchd.sh          # Auto-start on boot
```

---

## Implementation Plan

### Phase 1: Project Setup
1. Initialize Cargo workspace with three crates
2. Initialize frontend with Vite + SolidJS + TypeScript
3. Configure Tailwind CSS with dark theme tokens
4. Set up basic PWA manifest and icons

### Phase 2: Backend Core (`clauset-core`)
1. **Types** (`clauset-types/`):
   - Session state machine (Created → Starting → Active → Stopped)
   - Claude event types (matching `--output-format stream-json`)
   - WebSocket message protocol (client ↔ server)

2. **Session Manager**:
   - Create/list/terminate sessions
   - SQLite persistence for session metadata
   - Session recovery on server restart

3. **Process Manager**:
   - **Stream-JSON mode**: Spawn `claude -p --output-format stream-json`
   - **Terminal mode**: Spawn with PTY via `portable-pty`
   - Parse streaming output into typed events
   - Handle stdin for user input

4. **History Reader**:
   - Parse `~/.claude/history.jsonl` for past sessions
   - Watch for changes with `notify` crate

### Phase 3: Backend Server (`clauset-server`)
1. **REST API** (Axum):
   ```
   GET  /api/sessions          - List sessions
   POST /api/sessions          - Create session
   GET  /api/sessions/:id      - Get session details
   DELETE /api/sessions/:id    - Terminate session
   GET  /api/history           - Past sessions from history.jsonl
   GET  /health                - Health check
   ```

2. **WebSocket** (`/ws/sessions/:id`):
   - Real-time streaming of Claude output
   - Bidirectional: receive user input, send terminal resize
   - Connection management with ping/pong keepalive

3. **Static File Server**:
   - Serve built PWA from embedded assets or `./dist`

### Phase 4: Frontend Core
1. **App Shell**:
   - iOS safe area handling
   - Bottom navigation (Sessions / Settings)
   - Connection status indicator

2. **Session List Page**:
   - Cards showing active/recent sessions
   - Status badges (active/idle/completed)
   - "New Session" button with project picker

3. **Chat Interface**:
   - Virtualized message list for performance
   - `MessageBubble` with markdown rendering
   - `CodeBlock` with Shiki syntax highlighting
   - Collapsible `ToolCall` components
   - Streaming text with delta updates

4. **Input Bar**:
   - Mobile-optimized text input
   - Visual Viewport API for keyboard handling
   - Send button with loading state

### Phase 5: Terminal Integration
1. **xterm.js Setup**:
   - Dark theme matching app colors
   - FitAddon for responsive sizing
   - WebLinksAddon for clickable URLs

2. **Terminal Overlay**:
   - Toggle button in chat header (`[>_]`)
   - Full-screen overlay with controls
   - Font size adjustment (A+ / A-)
   - Back to chat button

3. **Input Handling**:
   - Send raw bytes over WebSocket
   - Handle resize events
   - iOS keyboard workarounds

### Phase 6: PWA & Offline
1. **Service Worker**:
   - Pre-cache static assets
   - NetworkFirst for API with cache fallback
   - Update prompt when new version available

2. **IndexedDB Storage**:
   - Cache sessions and messages for offline viewing
   - Sync when back online

### Phase 7: Deployment
1. **Build**:
   - `cargo build --release` for server
   - `pnpm build` for frontend (outputs to `dist/`)

2. **Launchd Service**:
   - Create plist for auto-start on boot
   - Restart on crash

3. **Configuration**:
   - Server binds to `0.0.0.0:8080`
   - Access via Tailscale IP (e.g., `http://100.x.x.x:8080`)

---

## Key Dependencies

### Backend (Rust)
| Crate | Purpose |
|-------|---------|
| `axum` | HTTP/WebSocket server |
| `tokio` | Async runtime |
| `portable-pty` | PTY for terminal mode |
| `rusqlite` | Session persistence |
| `serde` / `serde_json` | JSON serialization |
| `notify` | File watching for history |
| `dashmap` | Concurrent session storage |
| `tracing` | Logging |

### Frontend (SolidJS)
| Package | Purpose |
|---------|---------|
| `solid-js` | UI framework |
| `@solidjs/router` | Client-side routing |
| `@xterm/xterm` | Terminal emulation |
| `marked` | Markdown parsing |
| `shiki` | Syntax highlighting |
| `idb` | IndexedDB wrapper |
| `tailwindcss` | Styling |
| `vite-plugin-pwa` | PWA support |

---

## Critical Files

### Backend
- `crates/clauset-core/src/session.rs` - Session state machine & manager
- `crates/clauset-core/src/process.rs` - Claude CLI spawning (stream-json + PTY)
- `crates/clauset-server/src/routes/ws.rs` - WebSocket handler
- `crates/clauset-types/src/ws.rs` - WebSocket message protocol

### Frontend
- `frontend/src/lib/ws.ts` - WebSocket manager with reconnection
- `frontend/src/components/chat/ChatView.tsx` - Main chat container
- `frontend/src/components/chat/MessageBubble.tsx` - Message rendering
- `frontend/src/components/terminal/TerminalView.tsx` - xterm.js wrapper
- `frontend/vite.config.ts` - PWA configuration

---

## WebSocket Protocol

### Client → Server
```typescript
{ type: "input", content: "Fix the auth bug" }
{ type: "terminal_input", data: [27, 91, 65] }  // Raw bytes (e.g., arrow up)
{ type: "resize", rows: 24, cols: 80 }
{ type: "ping", timestamp: 1703001234567 }
```

### Server → Client
```typescript
{ type: "session_init", session_id: "...", model: "sonnet", tools: [...] }
{ type: "text", content: "I'll analyze...", is_complete: false }
{ type: "tool_use", tool_id: "...", tool_name: "Read", input: {...} }
{ type: "tool_result", tool_id: "...", output: "...", is_error: false }
{ type: "terminal_output", data: [27, 91, 72, ...] }
{ type: "status_change", old_status: "active", new_status: "idle" }
{ type: "error", code: "session_not_found", message: "..." }
```

---

## Running

### Development
```bash
# Terminal 1: Backend
cargo run -p clauset-server

# Terminal 2: Frontend (with proxy to backend)
cd frontend && pnpm dev
```

### Production
```bash
# Build everything
cargo build --release
cd frontend && pnpm build

# Run (serves frontend from ./frontend/dist)
./target/release/clauset-server

# Access from iPhone via Tailscale
# http://100.x.x.x:8080
```

### Auto-start (launchd)
```bash
./scripts/install-launchd.sh
# Creates ~/Library/LaunchAgents/com.clauset.server.plist
```

---

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Backend language | Rust | Long-running server, memory safety, single binary |
| Frontend framework | SolidJS | Smallest bundle, best mobile perf, fine-grained reactivity |
| Process mode | Dual (stream-json + PTY) | Chat UI uses structured JSON; terminal uses raw PTY |
| Database | SQLite | Simple, embedded, sufficient for single-server |
| Auth | Tailscale only | Already authenticated at network level |
| Mobile access | PWA | No App Store, easy updates, works offline |
