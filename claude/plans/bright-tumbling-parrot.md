# Logging & Observability Overhaul Plan

## Problem Statement
Current logging is cluttered with debug/info logs throughout the codebase. All crates default to `debug` level (main.rs:52), making it hard to identify important information during investigations. No CLI control, only `RUST_LOG` environment variable. The activity state machine in buffer.rs has particularly verbose logging that fires on every terminal chunk.

## Goals
1. **Categorized logging** - Group logs by functional area with dedicated targets
2. **Level presets** - Production, development, debug modes
3. **CLI control** - Flags to enable specific categories without environment variables
4. **Reduced noise** - Appropriate default levels for production use
5. **Deep debugging** - Ability to enable verbose logging for specific subsystems
6. **JSON output** - Optional structured JSON format for log aggregation (--log-format json)

---

## Logging Architecture

### Log Categories (Targets)

| Target | Description | Default Level | Contents |
|--------|-------------|---------------|----------|
| `clauset::startup` | Server initialization | INFO | Config loaded, state init, server listening |
| `clauset::api` | HTTP API requests | INFO | Request/response (not body), errors |
| `clauset::ws` | WebSocket lifecycle | INFO | Connect/disconnect events |
| `clauset::ws::ping` | WebSocket keepalive | TRACE | Ping/pong messages |
| `clauset::session` | Session lifecycle | INFO | Create/start/stop/resume events |
| `clauset::process` | Claude CLI process | INFO | Spawn, exit, errors |
| `clauset::activity` | Activity state machine | WARN | State transitions only |
| `clauset::activity::state` | Detailed state tracking | DEBUG | Busy/ready checks, all state variables |
| `clauset::activity::stats` | Stats parsing | DEBUG | Token/cost/context updates |
| `clauset::parser` | Output parsing | DEBUG | Parse failures, malformed data |
| `clauset::events` | Event processor | INFO | Processor start/stop, lag warnings |
| `clauset::hooks` | Hook processing | INFO | Hook events, action updates |
| `tower_http` | HTTP framework | WARN | Only errors/warnings |

### Level Definitions

| Level | Use Case |
|-------|----------|
| ERROR | Failures requiring attention |
| WARN | Unexpected but handled conditions |
| INFO | Key lifecycle events (startup, session create/stop) |
| DEBUG | Detailed operational data for troubleshooting |
| TRACE | High-frequency data (pings, every chunk) |

---

## CLI Interface

```bash
# Default (production-like)
clauset-server

# Verbose mode (all INFO + some DEBUG)
clauset-server --verbose
clauset-server -v

# Debug mode (all DEBUG)
clauset-server --debug
clauset-server -d

# Trace mode (everything including TRACE)
clauset-server --trace

# Specific category debugging
clauset-server --log activity=debug        # Debug activity state machine
clauset-server --log session=debug         # Debug session lifecycle
clauset-server --log ws=trace              # Trace all WebSocket traffic
clauset-server --log activity=debug,ws=debug  # Multiple categories

# Quiet mode (WARN and above only)
clauset-server --quiet
clauset-server -q

# JSON output for log aggregation
clauset-server --log-format json
```

### Environment Variable Override
```bash
# Still supported for compatibility and advanced use
RUST_LOG="clauset::activity::state=debug,clauset::ws::ping=trace" clauset-server
```

**Priority:** CLI flags > RUST_LOG > default preset

---

## Log Presets

### Production (default)
```
clauset::startup=info
clauset::api=info
clauset::ws=info
clauset::ws::ping=off
clauset::session=info
clauset::process=info
clauset::activity=warn
clauset::activity::state=off
clauset::activity::stats=off
clauset::parser=warn
clauset::events=info
clauset::hooks=info
tower_http=warn
```

### Verbose (`-v`)
```
clauset=info
clauset::activity=info
tower_http=info
```

### Debug (`-d`)
```
clauset=debug
clauset::ws::ping=off
tower_http=debug
```

### Trace (`--trace`)
```
clauset=trace
tower_http=trace
```

### Quiet (`-q`)
```
clauset=warn
tower_http=error
```

---

## Implementation Plan

### Phase 1: Add Dependencies & CLI Argument Parsing

**File:** `Cargo.toml` (workspace root)
1. Add `clap` to workspace dependencies:
   ```toml
   clap = { version = "4.5", features = ["derive"] }
   ```
2. Add `json` feature to tracing-subscriber:
   ```toml
   tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }
   ```

**File:** `crates/clauset-server/Cargo.toml`
1. Add `clap.workspace = true`

**File:** `crates/clauset-server/src/main.rs`
1. Define CLI struct with logging options:
   - `--verbose` / `-v`
   - `--debug` / `-d`
   - `--trace`
   - `--quiet` / `-q`
   - `--log <TARGET=LEVEL>` (repeatable)
   - `--log-format <text|json>`

### Phase 2: Create Logging Configuration Module
**File:** `crates/clauset-server/src/logging.rs` (new)

1. Define `LogPreset` enum (Production, Verbose, Debug, Trace, Quiet)
2. Define `LogConfig` struct with:
   - preset
   - overrides (HashMap<String, Level>)
   - format (Text, Json)
3. Function to build `EnvFilter` from config
4. Function to initialize tracing with config

### Phase 3: Refactor Existing Log Statements
**Files to modify:**

| File | Changes |
|------|---------|
| `clauset-server/src/main.rs` | Use `clauset::startup` target |
| `clauset-server/src/global_ws.rs` | Use `clauset::ws` and `clauset::ws::ping` targets |
| `clauset-server/src/routes/ws.rs` | Use `clauset::ws` target |
| `clauset-server/src/websocket.rs` | Use `clauset::ws::ping` target |
| `clauset-server/src/event_processor.rs` | Use `clauset::events` target |
| `clauset-server/src/routes/hooks.rs` | Use `clauset::hooks` target |
| `clauset-server/src/routes/sessions.rs` | Use `clauset::session` target |
| `clauset-core/src/session.rs` | Use `clauset::session` and `clauset::hooks` targets |
| `clauset-core/src/buffer.rs` | Use `clauset::activity`, `clauset::activity::state`, `clauset::activity::stats` targets |
| `clauset-core/src/parser.rs` | Use `clauset::parser` target |
| `clauset-core/src/process.rs` | Use `clauset::process` target |

### Phase 4: Update Level Appropriateness
Review each log statement and adjust level. **Key insight**: buffer.rs lines 278-286 fire on EVERY terminal chunk - this is the main source of noise.

**buffer.rs changes (highest impact - ~15 log statements):**
| Line | Current | New Target | New Level | Reason |
|------|---------|------------|-----------|--------|
| 187-190 | DEBUG | `clauset::activity::stats` | DEBUG | Stats changes |
| 223-226 | DEBUG | `clauset::activity::state` | DEBUG | Activity indicator in new chunk |
| 232-235 | DEBUG | `clauset::activity::state` | DEBUG | Activity ignored (redraw) |
| 278-286 | DEBUG | `clauset::activity::state` | **TRACE** | **HIGH FREQ** - fires every chunk |
| 315-318 | DEBUG | `clauset::activity::state` | DEBUG | Busy check |
| 324 | INFO | `clauset::activity` | INFO | Important transition |
| 397 | INFO | `clauset::session` | DEBUG | mark_busy called |
| 412 | INFO | `clauset::session` | DEBUG | mark_ready called |
| 426 | INFO | `clauset::session` | DEBUG | initialize_session called |
| 489-495 | DEBUG | `clauset::hooks` | DEBUG | Hook update |

**global_ws.rs changes:**
| Line | Current | New Target | New Level |
|------|---------|------------|-----------|
| 18 | INFO | `clauset::ws` | INFO |
| 39 | DEBUG | `clauset::ws` | DEBUG |
| 107 | DEBUG | `clauset::ws` | DEBUG |
| 120 | TRACE | `clauset::ws::ping` | TRACE |
| 123 | DEBUG | `clauset::ws` | DEBUG |
| 141 | INFO | `clauset::ws` | INFO |

**parser.rs changes:**
| Line | Current | New Target | New Level |
|------|---------|------------|-----------|
| 31 | DEBUG | `clauset::parser` | DEBUG |

### Phase 5: Add Request/Response Logging
**File:** `crates/clauset-server/src/main.rs`

Add tower-http tracing layer with:
- Request method, path, status code
- Response time
- Target: `clauset::api`

### Phase 6: Update launchd Script
**File:** `scripts/install-launchd.sh`

Update default RUST_LOG to use new targets:
```bash
RUST_LOG="clauset::startup=info,clauset::api=info,clauset::ws=info,clauset::session=info,clauset::process=info,clauset::activity=warn,clauset::events=info,clauset::hooks=info,tower_http=warn"
```

### Phase 7: Documentation
**File:** `docs/logging.md` (new)

Document:
- Available log targets and what they contain
- CLI flags and presets
- Environment variable usage
- Common debugging scenarios with recommended flags

---

## Files to Modify

### New Files
- `crates/clauset-server/src/logging.rs` - Logging configuration module
- `docs/logging.md` - Logging documentation

### Modified Files
- `crates/clauset-server/Cargo.toml` - Add clap dependency
- `crates/clauset-server/src/main.rs` - CLI parsing, logging init
- `crates/clauset-server/src/lib.rs` - Export logging module
- `crates/clauset-server/src/global_ws.rs` - Update targets
- `crates/clauset-server/src/routes/ws.rs` - Update targets
- `crates/clauset-server/src/websocket.rs` - Update targets
- `crates/clauset-server/src/event_processor.rs` - Update targets
- `crates/clauset-server/src/routes/hooks.rs` - Update targets
- `crates/clauset-server/src/routes/sessions.rs` - Update targets
- `crates/clauset-core/src/session.rs` - Update targets
- `crates/clauset-core/src/buffer.rs` - Update targets, adjust levels
- `crates/clauset-core/src/parser.rs` - Update targets
- `crates/clauset-core/src/process.rs` - Update targets
- `scripts/install-launchd.sh` - Update default RUST_LOG

---

## Verification

After implementation, test each mode:

```bash
# 1. Default (production-like) - minimal clean logs
clauset-server
# Expected: Only startup info, session create/stop, errors

# 2. Verbose - more operational detail
clauset-server -v
# Expected: API requests, WebSocket events

# 3. Debug - troubleshooting info
clauset-server -d
# Expected: Activity state changes, hook updates, parser info

# 4. Specific category debugging
clauset-server --log activity::state=debug
# Expected: Only activity state machine logs + defaults

# 5. Quiet mode
clauset-server -q
# Expected: Only WARN/ERROR level

# 6. JSON output
clauset-server --log-format json
# Expected: JSON structured output

# 7. Combined flags
clauset-server -v --log ws::ping=trace --log-format json
# Expected: Verbose + ping traces in JSON format
```

**Key validation**:
- Production mode should NOT show buffer.rs debug logs during normal Claude interaction
- Debug mode should show enough detail to diagnose status flickering issues
- Activity state machine can be isolated with `--log activity::state=debug`
