# Production/Beta Deployment Plan for Clauset

## Goal
Set up a robust dual-environment system on Mac Mini where:
- **Production**: Runs persistently via launchd, auto-restarts, always available
- **Beta**: Runs in terminal for testing, completely isolated from production
- **Promotion**: Simple script to push beta changes to production

## Architecture

```
Production (launchd)          Beta (terminal)
├── Port: 8080                ├── Port: 8081
├── DB: sessions.db           ├── DB: sessions-beta.db
├── Binary: ~/.local/bin/     ├── Binary: ./target/release/
├── Config: production.toml   ├── Config: beta.toml
└── Logs: ~/.local/share/     └── Logs: terminal stdout
```

---

## Implementation Steps

### 1. Add CLI flags for runtime config override
**File**: `crates/clauset-server/src/main.rs`

Add to CLI struct:
```rust
/// Path to config file (default: config/default.toml)
#[arg(short, long, value_name = "FILE")]
config: Option<PathBuf>,

/// Override port
#[arg(short, long)]
port: Option<u16>,
```

**File**: `crates/clauset-server/src/config.rs`

Add method:
```rust
pub fn load_from(path: &Path) -> Result<Self> { ... }
```

Modify `main.rs` to use `--config` path if provided, then apply `--port` override.

### 2. Create environment-specific config files

**File**: `config/production.toml`
```toml
host = "0.0.0.0"
port = 8080
static_dir = "./frontend/dist"
db_path = "~/.local/share/clauset/sessions.db"
```

**File**: `config/beta.toml`
```toml
host = "0.0.0.0"
port = 8081
static_dir = "./frontend/dist"
db_path = "~/.local/share/clauset/sessions-beta.db"
```

> **Note**: The database includes `chat_messages` and `chat_tool_calls` tables for chat persistence (added in recent commits). Schema auto-migrates via `CREATE TABLE IF NOT EXISTS`.

### 3. Create management CLI script

**File**: `scripts/clauset` (executable bash script)

```bash
#!/bin/bash
# Clauset service manager

case "$1" in
  status)   # Show if production is running, PID, uptime
  start)    # Load launchd service
  stop)     # Unload launchd service
  restart)  # Stop + start
  logs)     # tail -f the log files
  beta)     # Run beta server in foreground
  deploy)   # Build release, copy binary, restart service
esac
```

Commands:
- `clauset status` - Check if production is running
- `clauset start` - Start production service
- `clauset stop` - Stop production service
- `clauset restart` - Restart production
- `clauset logs` - Tail production logs
- `clauset beta` - Run beta server (port 8081) in terminal
- `clauset deploy` - Promote current code to production

### 4. Update launchd installation script

**File**: `scripts/install-launchd.sh`

Changes:
- Install binary to `~/.local/bin/clauset-server`
- Use `config/production.toml` explicitly
- Create symlink for `clauset` CLI to `~/.local/bin/`

### 5. Create deploy script

**File**: `scripts/deploy.sh`

Steps:
1. Build release binary: `cargo build --release`
2. Build frontend: `cd frontend && npm run build`
3. Copy binary to `~/.local/bin/clauset-server`
4. Restart launchd service

### 6. Update vite config for beta proxy

**File**: `frontend/vite.config.ts`

Add environment variable support:
```ts
const BACKEND_PORT = process.env.CLAUSET_BACKEND_PORT || '8080';
proxy: {
  '/api': { target: `http://localhost:${BACKEND_PORT}` },
  '/ws': { target: `ws://localhost:${BACKEND_PORT}`, ws: true },
}
```

---

## Usage After Implementation

### Daily Development Workflow

```bash
# Start beta backend (port 8081)
./scripts/clauset beta

# In another terminal, start frontend dev server pointing to beta
CLAUSET_BACKEND_PORT=8081 npm run dev --prefix frontend

# Test at http://localhost:5173 (proxies to beta backend)
```

### Deploy to Production

```bash
# When happy with changes
./scripts/clauset deploy

# Verify production is running
./scripts/clauset status
./scripts/clauset logs
```

### Monitor Production

```bash
./scripts/clauset status   # Is it running?
./scripts/clauset logs     # Watch logs
./scripts/clauset restart  # If something's wrong
```

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `crates/clauset-server/src/main.rs` | Add `--config` and `--port` CLI flags |
| `crates/clauset-server/src/config.rs` | Add `load_from()` method |
| `config/production.toml` | Create (copy from default.toml) |
| `config/beta.toml` | Create (port 8081, beta db) |
| `scripts/clauset` | Create management CLI |
| `scripts/deploy.sh` | Create deploy script |
| `scripts/install-launchd.sh` | Update for production setup |
| `frontend/vite.config.ts` | Add env var for backend port |

---

## Decisions Made

- **CLI Location**: Global install - symlink to `~/.local/bin/clauset`
- **Deploy Tests**: Yes - `clauset deploy` runs `cargo test` before building/deploying
