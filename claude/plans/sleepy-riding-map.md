# Agent Moose - Discord Bot for Claude Code Control

## Overview

A Discord bot that provides full control over Claude Code sessions running on a Mac Mini, enabling interaction via phone through Discord with real-time streaming, interactive input, and session management.

---

## Prerequisites (Before Implementation)

### Required Setup
1. **Discord Bot Token**: Create at https://discord.com/developers/applications
   - Enable "Message Content Intent" in Bot settings
   - Add bot to your server with `applications.commands` + `bot` scopes
   - Required permissions: Send Messages, Create Public/Private Threads, Embed Links, Read Message History

2. **Claude Code CLI**: Installed and authenticated on Mac Mini
   - Run `claude` in terminal to verify it works
   - Your Claude Max subscription must be active

3. **tmux**: Installed on macOS
   - `brew install tmux`

4. **Node.js 20+**: For running the bot
   - `brew install node@20`

### Information Needed
- Discord Bot Token
- Discord Application Client ID
- Discord Server (Guild) ID
- Default project directory path

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AGENT MOOSE                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────────┐    │
│  │   Discord   │◄──►│   Session    │◄──►│  Process Manager    │    │
│  │   Client    │    │   Manager    │    │  (node-pty + Claude)│    │
│  └─────────────┘    └──────────────┘    └─────────────────────┘    │
│         │                  │                      │                 │
│         ▼                  ▼                      ▼                 │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────────┐    │
│  │   Slash     │    │   SQLite     │    │   Output Parser     │    │
│  │  Commands   │    │   Storage    │    │   (stream-json)     │    │
│  └─────────────┘    └──────────────┘    └─────────────────────┘    │
│         │                                         │                 │
│         ▼                                         ▼                 │
│  ┌─────────────┐                        ┌─────────────────────┐    │
│  │   Modals    │                        │  Message Buffer     │    │
│  │  (input)    │                        │  (rate limiting)    │    │
│  └─────────────┘                        └─────────────────────┘    │
│                                                   │                 │
│  ┌─────────────────────────────────────┐         │                 │
│  │         Guardrail System            │◄────────┘                 │
│  │  (command filtering, approvals)     │                           │
│  └─────────────────────────────────────┘                           │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Core Technical Decisions

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Runtime | Node.js 20+ / TypeScript | Native TS, async/await, node-pty support |
| Discord | discord.js v14 | Most mature, best TypeScript support |
| PTY | node-pty + tmux | Session persistence across bot restarts |
| Database | SQLite (better-sqlite3) | Simple, file-based, single-server |
| Process Mgmt | PM2 | Auto-restart, monitoring, logs |
| Testing | Vitest | Fast, TS-native, Jest-compatible |
| Logging | pino | Fast structured logging |
| Browser | Native + Playwright MCP | WebFetch for simple, Playwright for automation |
| Concurrency | 5-10 sessions | Resource monitoring required |

---

## Project Structure

```
agent-moose/
├── src/
│   ├── index.ts                    # Entry point
│   ├── bot.ts                      # Discord client init
│   ├── config/
│   │   ├── index.ts                # Config loader
│   │   └── schema.ts               # Zod validation
│   ├── core/
│   │   ├── SessionManager.ts       # Session tracking
│   │   ├── ProcessManager.ts       # PTY process control
│   │   ├── TmuxManager.ts          # tmux session lifecycle
│   │   ├── OutputParser.ts         # stream-json parsing
│   │   ├── OutputFormatter.ts      # Discord formatting
│   │   ├── MessageBuffer.ts        # Rate-limited updates
│   │   └── ResourceMonitor.ts      # System resource tracking
│   ├── discord/
│   │   ├── commands/               # Slash commands
│   │   │   ├── start.ts
│   │   │   ├── stop.ts
│   │   │   ├── ask.ts
│   │   │   ├── sessions.ts
│   │   │   ├── history.ts
│   │   │   ├── resume.ts
│   │   │   ├── project.ts
│   │   │   ├── resources.ts
│   │   │   └── kill.ts
│   │   ├── handlers/
│   │   │   ├── commandHandler.ts
│   │   │   ├── modalHandler.ts
│   │   │   └── buttonHandler.ts
│   │   └── components/
│   │       ├── InputModal.ts
│   │       └── SessionEmbed.ts
│   ├── guardrails/
│   │   ├── index.ts                # Orchestrator
│   │   ├── CommandFilter.ts
│   │   └── rules/
│   │       ├── dangerousCommands.ts
│   │       ├── sensitiveFiles.ts
│   │       └── networkAccess.ts
│   ├── storage/
│   │   ├── SessionStore.ts
│   │   └── HistoryStore.ts
│   └── types/
│       └── claude.ts
├── tests/
│   ├── unit/
│   ├── integration/
│   └── mocks/
│       ├── claudeProcess.ts
│       ├── pty.mock.ts
│       └── discord.mock.ts
├── config/
│   └── default.json
├── .env.example
├── package.json
├── tsconfig.json
├── vitest.config.ts
└── ecosystem.config.js             # PM2 config
```

---

## Slash Commands

| Command | Description | Options |
|---------|-------------|---------|
| `/start` | Start new Claude session | `project`, `model` |
| `/stop` | Stop current session | `session` (optional) |
| `/ask` | Send message to Claude | `message` (required) |
| `/sessions` | List active sessions | `all` (optional) |
| `/history` | View session history | `limit` |
| `/resume` | Resume previous session | `session` (required) |
| `/status` | Show current status | - |
| `/approve` | Approve dangerous action | `action_id` |
| `/project` | Manage project mappings | `set [path]`, `show`, `clear` |
| `/resources` | Show system resource usage | - |
| `/kill` | Force kill stuck session | `session` (required) |

---

## Data Flow

### User Command → Claude → Discord Output

```
1. User types /ask "help me refactor this function"
2. Discord → Command Handler → SessionManager (lookup)
3. ProcessManager.sendInput(sessionId, prompt)
4. Claude Code process receives input
5. Claude outputs stream-json events (NDJSON)
6. OutputParser parses events (init, text, tool_use, etc.)
7. OutputFormatter converts to Discord embeds/messages
8. MessageBuffer throttles updates (~1/sec for rate limits)
9. Discord message edited with latest content
10. On result event → final message, session stays active
```

### Interactive Input (Claude asks a question)

```
1. OutputParser detects input_required pattern
2. SessionManager sets status = 'waiting_input'
3. Discord Modal shown to user with Claude's question
4. User submits response in modal
5. modalHandler → ProcessManager.sendInput(response)
6. Resume normal output flow
```

---

## Guardrail System

### Blocked by Default
- `rm -rf /` and similar destructive patterns
- `sudo` commands
- `chmod 777`
- Fork bombs
- Direct disk writes (`dd`, `mkfs`)

### Require Approval
- `git push --force`
- `git reset --hard`
- `npm publish`
- Docker system prune

### Sensitive File Protection
- `.env` files
- Credentials/secrets
- SSH keys
- AWS/GCP configs

### Implementation
Pass to Claude Code via `--disallowedTools`:
```bash
claude -p --output-format stream-json \
  --disallowedTools "Bash(rm -rf:*),Bash(sudo:*)" \
  "user prompt"
```

---

## Session Management

### Session States
- `starting` - Process spawning
- `active` - Claude processing/responding
- `waiting_input` - Claude asked a question
- `stopping` - Graceful shutdown in progress
- `stopped` - Session ended
- `error` - Crashed/failed

### Thread Model
- Each session gets its own Discord thread
- Keeps main channel clean
- Thread archived when session ends
- History preserved for resume

### tmux Integration (Persistence)
```
Bot spawns Claude in tmux session:
  tmux new-session -d -s "moose-{sessionId}" "claude -p --output-format stream-json ..."

Bot reads output via:
  tmux pipe-pane -t "moose-{sessionId}" -O "cat >> /tmp/moose-{sessionId}.pipe"

On bot restart:
  1. List existing tmux sessions: tmux list-sessions
  2. Reattach to sessions matching "moose-*" pattern
  3. Resume piping output to Discord
  4. Notify users their sessions are reconnected
```

### Per-Channel Project Mapping
```typescript
// config/projects.json
{
  "channels": {
    "1234567890": {  // Discord channel ID
      "name": "web-app",
      "path": "/Users/moose/projects/my-web-app",
      "model": "sonnet"
    },
    "0987654321": {
      "name": "api-server",
      "path": "/Users/moose/projects/api-server",
      "model": "opus"
    }
  },
  "default": {
    "path": "/Users/moose/projects",
    "model": "sonnet"
  }
}
```

Slash command: `/project set [path]` - Map current channel to a project directory

### Persistence
- SQLite database for sessions, history
- tmux sessions survive bot restarts
- Session recovery via tmux reattach
- Can resume using `--session-id` flag

---

## Rate Limit Handling

### Discord Limits
- 5 messages per 5 seconds per channel
- 50 requests/second global

### Strategy
- MessageBuffer accumulates output for ~1 second
- Single message edit per buffer flush
- Threads bypass main channel slow mode
- discord.js handles rate limit retries automatically

---

## Testing Strategy (TDD)

### Framework: Vitest

### Coverage Targets
- Overall: 90% line, 85% branch
- Guardrails: 95%+ (security-critical)
- Output Parser: 95%+ (core logic)

### Mock Patterns
- Mock Claude Code CLI with stream-json fixtures
- Mock node-pty without real processes
- Mock Discord.js with factory functions

### Test Categories
- **Unit**: 75+ tests across components
- **Integration**: Session flows, command→output
- **E2E**: Real Discord test server

---

## Implementation Phases

### Phase 1: Foundation
- [ ] Project scaffolding (TypeScript, ESLint, Vitest)
- [ ] Configuration system (Zod validation)
- [ ] Logger setup (pino)
- [ ] Discord client + slash command registration
- [ ] SQLite database setup

### Phase 2: Core Engine
- [ ] ProcessManager with node-pty
- [ ] OutputParser for stream-json
- [ ] SessionManager with persistence
- [ ] /start and /stop commands

### Phase 3: Discord Integration
- [ ] Thread management
- [ ] MessageBuffer with rate limiting
- [ ] OutputFormatter for embeds
- [ ] /ask command with streaming

### Phase 4: Interactive Features
- [ ] Input detection + modal prompts
- [ ] Button interactions
- [ ] /sessions and /history commands
- [ ] Session resume functionality

### Phase 5: Guardrails & Polish
- [ ] Guardrail rule system
- [ ] Dangerous command detection
- [ ] Approval workflow
- [ ] Error handling/recovery
- [ ] Comprehensive testing

### Phase 6: Production
- [ ] PM2 configuration
- [ ] Monitoring/logging
- [ ] Documentation
- [ ] Deployment scripts

---

## Configuration

### Environment Variables
```bash
DISCORD_TOKEN=your_bot_token
DISCORD_CLIENT_ID=your_client_id
DISCORD_GUILD_ID=your_server_id
CLAUDE_PATH=/usr/local/bin/claude
DEFAULT_PROJECT_PATH=/Users/moose/projects
DATABASE_PATH=./data/sessions.db
LOG_LEVEL=info
```

### Project Config (config/default.json)
```json
{
  "claude": {
    "defaultModel": "sonnet",
    "sessionTimeoutMinutes": 60,
    "maxConcurrentSessions": 5
  },
  "discord": {
    "threadAutoArchiveDuration": 1440
  },
  "guardrails": {
    "enabled": true,
    "requireApproval": ["git push --force", "npm publish"]
  }
}
```

---

## Key Files to Create

1. `src/core/ProcessManager.ts` - PTY process control
2. `src/core/OutputParser.ts` - stream-json parsing
3. `src/core/SessionManager.ts` - Session state management
4. `src/discord/commands/ask.ts` - Primary user interaction
5. `src/guardrails/index.ts` - Security orchestration
6. `tests/mocks/claudeProcess.ts` - Claude CLI mock
7. `vitest.config.ts` - Test configuration

---

## Browser Automation

### Native Claude Code (Simple Tasks)
- `WebFetch` - Fetch and read web pages
- `WebSearch` - Search the web for information
- Good for: documentation lookup, API exploration, content fetching

### Playwright MCP Server (Complex Automation)
Install and configure MCP server for full browser control:

```bash
# Install Playwright MCP
npm install -g @anthropic/mcp-playwright

# Add to Claude MCP config (~/.claude/mcp.json)
{
  "servers": {
    "playwright": {
      "command": "mcp-playwright",
      "args": ["--headless"]
    }
  }
}
```

Capabilities:
- Navigate to URLs
- Click elements, fill forms
- Take screenshots
- Execute JavaScript
- Handle authentication flows
- Scrape dynamic content

Use cases:
- Automated testing
- Web scraping with JS rendering
- Form submissions
- Screenshot captures for debugging

---

## Resource Monitoring (5-10 Sessions)

### System Requirements
- **RAM**: ~500MB per Claude session (5-10GB recommended)
- **CPU**: Claude Code is CPU-light, mostly I/O bound
- **Disk**: Session logs, SQLite DB (~50MB base + history)

### Monitoring Strategy
```typescript
// src/core/ResourceMonitor.ts
class ResourceMonitor {
  checkMemory(): { used: number; available: number; percent: number };
  checkCpu(): { load1m: number; load5m: number };
  getActiveProcessCount(): number;

  // Alerts when resources low
  shouldThrottleNewSessions(): boolean;
  shouldWarnUser(): boolean;
}
```

### Limits
- Max 10 concurrent sessions (configurable)
- Session timeout: 60 minutes idle (configurable)
- Auto-cleanup of zombie tmux sessions
- Memory threshold warning at 80% usage

### Slash Command
`/resources` - Show current resource usage:
```
📊 Agent Moose Resources
├── Sessions: 7/10 active
├── Memory: 4.2GB / 16GB (26%)
├── tmux sessions: 7 running
└── Oldest session: 45 minutes
```

---

## User Preferences (Confirmed)

- ✅ **Session Persistence**: tmux integration (sessions survive restarts)
- ✅ **Browser**: Native + Playwright MCP (both options)
- ✅ **Directory**: Per-channel project mapping
- ✅ **Concurrency**: 5-10 sessions with resource monitoring
