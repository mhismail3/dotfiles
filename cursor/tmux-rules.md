# tmux Session Management Rules for AI Agents

## Why This Matters

tmux sessions are your **superpower** for managing long-running processes, parallel workstreams, and maintaining context across disconnections. Proper tmux usage prevents:
- Lost work when terminal connections drop
- Process collisions from duplicate servers
- Context switching overhead from juggling multiple terminal windows
- Confusion about what's running where

**Following these rules makes you a more effective, reliable agent.**

---

## Core Principles

### 1. Always Check Before Creating

**Never blindly create a session.** First, list existing sessions:

```bash
tmux list-sessions
# or shorthand:
tmux ls
```

If a relevant session exists, attach to it instead of creating a duplicate.

### 2. Use Descriptive Session Names

Sessions should be named by **purpose**, not arbitrary identifiers:

```bash
# Good - descriptive and scoped
tmux new-session -d -s "dev-server"
tmux new-session -d -s "api-backend"
tmux new-session -d -s "tests-watch"
tmux new-session -d -s "logs-tail"

# Bad - meaningless
tmux new-session -d -s "session1"
tmux new-session -d -s "work"
tmux new-session -d -s "temp"
```

### 3. Detached Sessions for Background Work

When starting long-running processes, **always use `-d` (detached)**:

```bash
# Start a dev server in a detached session
tmux new-session -d -s "dev-server" "npm run dev"

# Start with a specific working directory
tmux new-session -d -s "project-x" -c "/path/to/project-x"
```

This keeps your main terminal free while the process runs.

---

## Essential Commands Reference

### Session Management

| Command | Purpose |
|---------|---------|
| `tmux new-session -d -s "name"` | Create detached session |
| `tmux new-session -d -s "name" "command"` | Create session running a command |
| `tmux new-session -d -s "name" -c "/path"` | Create session in specific directory |
| `tmux ls` | List all sessions |
| `tmux attach -t "name"` | Attach to existing session |
| `tmux kill-session -t "name"` | Terminate a session |
| `tmux has-session -t "name" 2>/dev/null` | Check if session exists (for scripting) |

### Window Management (within sessions)

| Command | Purpose |
|---------|---------|
| `tmux new-window -t "session:1"` | Add window to session |
| `tmux send-keys -t "session:0" "command" Enter` | Send command to session window |
| `tmux capture-pane -t "session:0" -p` | Read output from session window |

### Conditional Session Creation

Use this pattern to create-or-attach idempotently:

```bash
tmux has-session -t "dev-server" 2>/dev/null || tmux new-session -d -s "dev-server"
```

---

## Workflow Patterns

### Pattern 1: Development Server

When starting a dev server that should persist:

```bash
# Check if already running
tmux has-session -t "dev-server" 2>/dev/null && echo "Dev server already running" && exit 0

# Create and start
tmux new-session -d -s "dev-server" -c "$PROJECT_ROOT"
tmux send-keys -t "dev-server" "npm run dev" Enter
```

### Pattern 2: Parallel Test Runners

When you need multiple processes for a task:

```bash
# Unit tests in one session
tmux new-session -d -s "tests-unit" "npm run test:unit -- --watch"

# Integration tests in another
tmux new-session -d -s "tests-integration" "npm run test:integration -- --watch"

# E2E tests in a third
tmux new-session -d -s "tests-e2e" "npm run test:e2e"
```

### Pattern 3: Log Monitoring

For tailing logs while working:

```bash
tmux new-session -d -s "logs"
tmux send-keys -t "logs" "tail -f /var/log/app.log" Enter
```

### Pattern 4: Multi-Service Stack

When orchestrating multiple services:

```bash
# Create sessions for each service
tmux new-session -d -s "frontend" -c "$HOME/project/frontend" "npm run dev"
tmux new-session -d -s "backend" -c "$HOME/project/backend" "npm run start"
tmux new-session -d -s "database" "docker compose up postgres redis"
```

---

## Before You Act: Pre-Flight Checklist

**Every time you consider using tmux, run through this:**

1. **List sessions first**: `tmux ls` — Know what's already running
2. **Check for conflicts**: Is there already a session for this purpose?
3. **Choose the right action**:
   - Session exists and correct → attach or send commands to it
   - Session exists but stale → kill it, then create fresh
   - No relevant session → create with descriptive name
4. **Use detached mode**: Unless you specifically need to watch output live, use `-d`
5. **Document what you start**: If creating sessions for the user, tell them the session names

---

## Reading Session Output

To inspect what's happening in a session without attaching:

```bash
# Capture last 100 lines from session's first window
tmux capture-pane -t "dev-server:0" -p -S -100
```

This is invaluable for checking server status, error messages, or build output.

---

## Cleanup Responsibility

**Don't leave orphaned sessions.** When your task is complete:

1. Check if sessions you created are still needed
2. Kill sessions that were temporary: `tmux kill-session -t "name"`
3. Inform the user about any sessions left running intentionally

---

## Quick Reference Card

```bash
# The commands you'll use 90% of the time:
tmux ls                                    # What's running?
tmux new-session -d -s "name"              # Create detached
tmux new-session -d -s "name" "cmd"        # Create with command
tmux send-keys -t "name" "cmd" Enter       # Run in existing
tmux capture-pane -t "name" -p             # Read output
tmux kill-session -t "name"                # Clean up
tmux attach -t "name"                      # Connect to session
```

---

## Summary

Using tmux well demonstrates **professionalism and attention to detail**. It shows you understand:
- Process lifecycle management
- Resource efficiency (not spawning duplicates)
- User experience (clean, organized sessions)
- Reliability (processes survive disconnection)

**An agent that masters tmux is an agent users trust with complex, long-running operations.**

