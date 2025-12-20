# ReTerm: Claude Code Mobile Terminal App

## Overview

A native iOS app for SSH-ing into Mac Mini and interacting with Claude Code sessions running in TMux. The app provides full terminal interactivity, session management, sub-agent visibility, and a mobile-optimized interface.

## Key Decisions (User Confirmed)

| Decision | Choice |
|----------|--------|
| Backend Language | Node.js + TypeScript |
| Networking | Tailscale (zero-config VPN) |
| Build Tools | xcede + XcodeBuildMCP (Claude-assisted building) |
| Authentication | mTLS (mutual TLS certificates) |

## Architecture: Native iOS + WebSocket Proxy + mTLS

**Why this approach (vs pure SSH or React Native):**
- Claude Code's complex TUI renders poorly on narrow mobile terminals
- WebSocket proxy maintains connection during network transitions
- Backend can parse Claude Code session state for rich mobile UI
- Terminal resize race conditions avoided (backend has stable dimensions)
- mTLS provides strong authentication without passwords
- Tailscale provides encrypted tunnel + mTLS adds app-layer auth

```
┌─────────────────────┐    mTLS/WebSocket     ┌──────────────────────┐
│   iOS App (Swift)   │◄────────────────────►│  Proxy on Mac Mini   │
│                     │   over Tailscale      │                      │
│  - SwiftTerm render │                       │  - PTY to tmux/shell │
│  - Client cert auth │                       │  - Server cert + CA  │
│  - Session list     │                       │  - TMux management   │
│  - Todo dashboard   │                       │  - Claude state API  │
│  - Sub-agent peek   │                       │  - File watcher      │
└─────────────────────┘                       └──────────────────────┘
        │                                              │
        │ Bundled: ios-client.p12, ca.crt             │ Reads: ~/.claude/
        └──────────────────────────────────────────────┴─────────────────
```

---

## Component Breakdown

### 1. Backend Proxy (Runs on Mac Mini)

**Technology**: Node.js + TypeScript (or Go for lower footprint)

**Core Features:**
- WebSocket server for terminal I/O streaming
- TMux session creation/attachment/management
- Claude Code session introspection API
- File watcher on `~/.claude/` for real-time updates

**Endpoints/Messages:**
```
WebSocket Messages:
  - terminal:input    → Send keystrokes to PTY
  - terminal:output   → Receive terminal output
  - terminal:resize   → Change terminal dimensions
  - session:list      → List TMux sessions
  - session:attach    → Attach to existing session
  - session:create    → Create new TMux session + start Claude Code
  - session:kill      → Terminate a session

REST API:
  GET  /api/claude/sessions     → List Claude Code sessions from ~/.claude/
  GET  /api/claude/session/:id  → Get session details (messages, agents)
  GET  /api/claude/agents/:id   → Get sub-agent activity
  GET  /api/claude/todos/:id    → Get todo list for session
  GET  /api/health              → Health check
```

**Claude Code Introspection:**
- Parse `~/.claude/history.jsonl` for session list
- Parse `~/.claude/projects/{path}/*.jsonl` for messages
- Watch `~/.claude/todos/*.json` for live todo updates
- Track sub-agents via `isSidechain: true` and `agentId` fields

### 2. iOS App (Native Swift)

**Technology**: SwiftUI + SwiftTerm + URLSession/WebSocket

**Screens:**
1. **Home/Sessions List** - Active TMux sessions with status
2. **Terminal View** - Full-screen terminal with extended keyboard
3. **Claude Dashboard** - Session todos, sub-agents, activity feed
4. **Sub-Agent Peek** - Drill into specific agent's messages
5. **Settings** - Connection config, appearance, keyboard customization

**Key UI Components:**
- **Extended Keyboard Row**: Ctrl, Tab, Esc, |, {}, [], $, #, arrows
- **Bottom Tab Bar**: Sessions | Terminal | Dashboard | Settings
- **Session Switcher**: Swipe between active sessions
- **Todo Panel**: Collapsible accordion showing task status
- **Activity Feed**: Live streaming of Claude's actions

### 3. TMux Integration

**Session Naming Convention:**
```
claude-{project-name}-{timestamp}
```

**Commands the proxy executes:**
```bash
# Create new session with Claude Code
tmux new-session -d -s "claude-reterm-1234" "claude"

# Attach to existing session
tmux attach-session -t "claude-reterm-1234"

# List sessions
tmux list-sessions -F "#{session_name}:#{session_activity}"

# Kill session
tmux kill-session -t "claude-reterm-1234"
```

---

## Directory Structure

```
reterm/
├── certs/                      # mTLS certificates (gitignored)
│   ├── ca/                     # Certificate Authority
│   ├── server/                 # Server cert for Node.js
│   ├── client/                 # iOS client cert (.p12)
│   └── .credentials            # P12 password
│
├── scripts/                    # Setup and maintenance scripts
│   ├── setup-all-certs.sh      # Generate all certificates
│   ├── generate-ca.sh          # Generate CA only
│   ├── generate-server-cert.sh # Generate server cert
│   ├── generate-client-cert.sh # Generate iOS client cert
│   ├── rotate-certs.sh         # Rotate expiring certs
│   ├── check-cert-expiry.sh    # Cron job for expiry alerts
│   ├── install-backend.sh      # Setup Node.js backend
│   ├── install-build-tools.sh  # Install xcede + XcodeBuildMCP
│   └── start-backend.sh        # launchd startup script
│
├── backend/                    # Node.js/TypeScript proxy server
│   ├── src/
│   │   ├── index.ts            # Entry point
│   │   ├── server/
│   │   │   ├── mtls-websocket-server.ts  # mTLS WebSocket server
│   │   │   ├── certificate-validator.ts   # Cert validation utils
│   │   │   └── terminal-proxy.ts          # PTY management
│   │   ├── tmux/
│   │   │   ├── manager.ts      # TMux session lifecycle
│   │   │   └── parser.ts       # Parse tmux output
│   │   ├── claude/
│   │   │   ├── sessions.ts     # Session discovery (~/.claude/)
│   │   │   ├── messages.ts     # JSONL message parsing
│   │   │   ├── agents.ts       # Sub-agent tracking (isSidechain)
│   │   │   ├── todos.ts        # Todo file introspection
│   │   │   └── watcher.ts      # chokidar file watcher
│   │   └── api/
│   │       ├── routes.ts       # Express routes
│   │       └── handlers.ts     # REST API handlers
│   ├── package.json
│   └── tsconfig.json
│
├── ios/                        # Native iOS app
│   ├── ReTerm/
│   │   ├── App/
│   │   │   ├── ReTermApp.swift
│   │   │   └── ContentView.swift
│   │   ├── Views/
│   │   │   ├── SessionsListView.swift
│   │   │   ├── TerminalView.swift
│   │   │   ├── ClaudeDashboardView.swift
│   │   │   ├── SubAgentPeekView.swift
│   │   │   └── SettingsView.swift
│   │   ├── Components/
│   │   │   ├── ExtendedKeyboard.swift   # Ctrl/Tab/Esc/arrows
│   │   │   ├── TodoPanel.swift          # Accordion todo list
│   │   │   ├── ActivityFeed.swift       # Live tool call stream
│   │   │   └── SessionCard.swift        # Session list item
│   │   ├── Networking/
│   │   │   ├── MTLSConfiguration.swift  # Load certs from bundle
│   │   │   ├── MTLSWebSocketClient.swift # mTLS URLSession delegate
│   │   │   ├── CertificateManager.swift  # Rotation status
│   │   │   └── ClaudeAPIClient.swift     # REST API calls
│   │   ├── Terminal/
│   │   │   ├── TerminalWrapper.swift     # SwiftTerm integration
│   │   │   └── TerminalInputHandler.swift
│   │   ├── Models/
│   │   │   ├── Session.swift
│   │   │   ├── ClaudeMessage.swift
│   │   │   ├── Agent.swift
│   │   │   └── Todo.swift
│   │   └── Resources/
│   │       ├── Assets.xcassets
│   │       ├── ios-client.p12   # Client certificate bundle
│   │       └── ca.crt           # CA for server validation
│   ├── ReTerm.xcodeproj
│   └── Package.swift           # SwiftTerm dependency
│
├── docs/
│   └── architecture.md
│
├── .gitignore
└── README.md
```

---

## Implementation Phases

### Phase 0: Environment Setup
- [ ] Install xcede (Xcode CLI alternative)
  ```bash
  git clone https://codeberg.org/luxmentis/xcede.git
  cd xcede && ./build.sh && cp xcede /usr/local/bin/
  ```
- [ ] Install XcodeBuildMCP for Claude-assisted iOS building
  ```bash
  # Add to Claude Code MCP config
  ```
- [ ] Verify Tailscale is installed and Mac Mini is accessible
- [ ] Initialize git repo and project structure

### Phase 1: Certificate Infrastructure
- [ ] Create `scripts/generate-ca.sh` - Generate Certificate Authority
- [ ] Create `scripts/generate-server-cert.sh` - Server cert with Tailscale SANs
- [ ] Create `scripts/generate-client-cert.sh` - iOS client P12 bundle
- [ ] Create `scripts/setup-all-certs.sh` - Master orchestration script
- [ ] Create `scripts/rotate-certs.sh` - Monthly rotation script
- [ ] Run initial certificate generation
- [ ] Document P12 password in secure location

### Phase 2: Backend Foundation
- [ ] Initialize Node.js/TypeScript project (`npm init`, `tsconfig.json`)
- [ ] Install deps: `ws`, `node-pty`, `express`, `chokidar`, `zod`
- [ ] Implement `mtls-websocket-server.ts` with client cert validation
- [ ] Implement `terminal-proxy.ts` with PTY spawning
- [ ] Implement `tmux/manager.ts` for session lifecycle
- [ ] Create REST API routes (`/api/health`, `/api/sessions`)
- [ ] Test mTLS connection with `curl --cert`

### Phase 3: Claude Code Introspection
- [ ] Implement `claude/sessions.ts` - Parse `~/.claude/history.jsonl`
- [ ] Implement `claude/messages.ts` - Parse project JSONL files
- [ ] Implement `claude/agents.ts` - Track sub-agents (`isSidechain: true`)
- [ ] Implement `claude/todos.ts` - Read `~/.claude/todos/*.json`
- [ ] Implement `claude/watcher.ts` - Real-time file watching
- [ ] Expose via REST: `GET /api/claude/sessions`, `/agents/:id`, `/todos/:id`
- [ ] Add WebSocket events for live updates

### Phase 4: iOS App Shell
- [ ] Create Xcode project with SwiftUI
- [ ] Add SwiftTerm via Swift Package Manager
- [ ] Bundle `ios-client.p12` and `ca.crt` in Resources
- [ ] Implement `MTLSConfiguration.swift` - Load certs from bundle/Keychain
- [ ] Implement `MTLSWebSocketClient.swift` - URLSession delegate for mTLS
- [ ] Implement `CertificateManager.swift` - Rotation status checks
- [ ] Create basic connection test view

### Phase 5: Terminal Experience
- [ ] Implement `TerminalWrapper.swift` - SwiftTerm integration
- [ ] Build `ExtendedKeyboard.swift` - Ctrl/Tab/Esc/|/{}[]/arrows row
- [ ] Create `TerminalView.swift` - Full-screen terminal with keyboard
- [ ] Implement terminal resizing on orientation change
- [ ] Add copy/paste with haptic feedback
- [ ] Support external keyboard shortcuts (Cmd+K, etc.)

### Phase 6: Session Management
- [ ] Implement `SessionsListView.swift` - TMux session cards
- [ ] Add "New Session" flow (start Claude in fresh tmux)
- [ ] Implement session attach/detach handling
- [ ] Add swipe-to-switch between sessions
- [ ] Persist connection settings in UserDefaults
- [ ] Kill session with swipe-to-delete + confirmation

### Phase 7: Claude Dashboard
- [ ] Implement `ClaudeDashboardView.swift` - Main dashboard layout
- [ ] Build `TodoPanel.swift` - Accordion with status badges
- [ ] Build `ActivityFeed.swift` - Streaming tool call display
- [ ] Implement `SubAgentPeekView.swift` - Drill into agent messages
- [ ] Add real-time updates via WebSocket subscription
- [ ] Progress indicators for long-running operations

### Phase 8: Polish & Distribution
- [ ] Dark/light mode support with system preference
- [ ] Font size slider and theme options
- [ ] VoiceOver accessibility labels
- [ ] Robust error handling and auto-reconnect
- [ ] Virtual scrolling for large outputs
- [ ] Create `launchd` plist for backend auto-start
- [ ] Setup TestFlight for personal deployment
- [ ] Write README with setup instructions

---

## mTLS Certificate Infrastructure

### Certificate Hierarchy
```
certs/
├── ca/
│   ├── ca.key              # CA private key (password protected, KEEP SECURE)
│   ├── ca.crt              # CA certificate (both sides trust this)
│   └── ca.srl              # Serial number file
├── server/
│   ├── server.key          # Server private key
│   ├── server.crt          # Server certificate (signed by CA)
│   └── server.cnf          # OpenSSL config with Tailscale SANs
├── client/
│   ├── ios-client.key      # iOS client private key
│   ├── ios-client.crt      # iOS client certificate
│   └── ios-client.p12      # PKCS#12 bundle for iOS (key + cert + CA chain)
└── .credentials            # P12 password (gitignored)
```

### Certificate Generation Scripts
- `scripts/setup-all-certs.sh` - Master script (generates CA, server, client certs)
- `scripts/rotate-certs.sh` - Monthly rotation (backs up old, generates new)
- `scripts/check-cert-expiry.sh` - Weekly cron check for expiring certs

### Server mTLS Config (Node.js)
```typescript
// Key settings for HTTPS server
{
  cert: serverCert,
  key: serverKey,
  ca: caCert,
  requestCert: true,        // Require client certificate
  rejectUnauthorized: true, // Reject invalid client certs
  minVersion: 'TLSv1.2',
}
```

### iOS mTLS Config
- Bundle `ios-client.p12` and `ca.crt` in app resources
- Load client identity from Keychain (or import from P12 on first launch)
- Custom `URLSessionDelegate` for server trust + client certificate challenges
- `CertificateManager` class handles rotation status checks

---

## Dependencies

### Backend
- `ws` - WebSocket server
- `node-pty` - PTY spawning
- `chokidar` - File watching
- `express` - REST API
- `zod` - Schema validation

### iOS
- `SwiftTerm` - Terminal emulator (github.com/migueldeicaza/SwiftTerm)
- `Starscream` - WebSocket client (or native URLSessionWebSocketTask)
- Native SwiftUI components

---

## Claude Code Session Introspection (Key Feature)

### Data Sources on Mac Mini
| Path | Content | Format |
|------|---------|--------|
| `~/.claude/history.jsonl` | Global command history | JSONL with sessionId, timestamp |
| `~/.claude/projects/{path}/*.jsonl` | Session messages | JSONL with agentId, isSidechain |
| `~/.claude/todos/{sessionId}-agent-{agentId}.json` | Todo lists | JSON array with status |
| `~/.claude/session-env/{UUID}/` | Session environment | Directory per session |

### Sub-Agent Tracking
- Main agent messages: `isSidechain: false`
- Sub-agent messages: `isSidechain: true`, unique `agentId`
- Parent-child links via `parentUuid` field
- Query: `grep '"isSidechain":\s*true' ~/.claude/projects/{path}/*.jsonl`

### Real-Time Updates
- Use `chokidar` to watch `~/.claude/` for file changes
- Push updates via WebSocket when JSONL files change
- Emit events: `session:updated`, `todo:changed`, `agent:spawned`

---

## iOS App Key Screens

### 1. Sessions List (Home)
- Cards showing each tmux session with Claude
- Status badge: running/idle/disconnected
- Last activity timestamp
- Swipe to delete, tap to connect

### 2. Terminal View
- Full-screen SwiftTerm terminal
- Extended keyboard row at bottom (Ctrl, Tab, Esc, arrows, |, {}, [])
- Swipe left/right to switch sessions
- Pull down for session info overlay

### 3. Claude Dashboard
- Split view: Terminal + sidebar
- Collapsible todo panel with live status
- Activity feed showing tool calls
- Sub-agent tree with peek buttons

### 4. Sub-Agent Peek
- Read-only view of agent's message history
- Tool calls with expandable output
- Scroll to bottom for latest activity
- Back to parent agent

### 5. Settings
- Server URL (Tailscale hostname)
- Certificate status + rotation alert
- Theme (dark/light/system)
- Font size slider
- Keyboard customization

---

## Security Considerations

- Backend listens on Tailscale interface only (100.x.x.x)
- mTLS ensures only your iOS app can connect
- Certificate pinning in iOS app (trust only your CA)
- P12 password stored in iOS Keychain (not hardcoded)
- Claude session data stays on Mac Mini (not synced to cloud)
- File permissions on ~/.claude/ respected (user-only read)
