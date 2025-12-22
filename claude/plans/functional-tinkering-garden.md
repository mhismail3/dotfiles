# Clauset Performance & Reliability Refactor Plan

## Summary
Deep analysis and refactor focusing on Critical + High severity issues. No regressions allowed.

## Key Issues to Fix

### CRITICAL: Backend

#### 1. Process Termination Broken (process.rs:440-443)
**Problem**: `terminate()` just removes from HashMap, doesn't kill child process.
**Impact**: Orphaned Claude processes accumulate indefinitely.

**Fix**:
```rust
// Change ManagedProcess::Terminal to store shutdown signal and child PID:
Terminal {
    handle: std::thread::JoinHandle<()>,  // Remove underscore
    writer: Arc<std::sync::Mutex<Box<dyn Write + Send>>>,
    master: Arc<std::sync::Mutex<Box<dyn portable_pty::MasterPty + Send>>>,
    shutdown: Arc<AtomicBool>,  // NEW: Signal thread to stop
    child_pid: u32,              // NEW: For sending signals
}

// In terminate():
pub async fn terminate(&self, session_id: Uuid) -> Result<()> {
    if let Some(process) = self.processes.write().await.remove(&session_id) {
        match process {
            ManagedProcess::Terminal { handle, shutdown, child_pid, .. } => {
                // 1. Signal thread to stop
                shutdown.store(true, Ordering::SeqCst);

                // 2. Send SIGTERM to child
                #[cfg(unix)]
                unsafe { libc::kill(child_pid as i32, libc::SIGTERM); }

                // 3. Wait up to 5s for graceful exit
                let start = Instant::now();
                while start.elapsed() < Duration::from_secs(5) {
                    if handle.is_finished() { break; }
                    tokio::time::sleep(Duration::from_millis(100)).await;
                }

                // 4. Force kill if still running
                if !handle.is_finished() {
                    #[cfg(unix)]
                    unsafe { libc::kill(child_pid as i32, libc::SIGKILL); }
                }

                // 5. Join thread (should complete quickly now)
                let _ = handle.join();
            }
            ManagedProcess::StreamJson { _handle, .. } => {
                _handle.abort();  // Tokio task can be aborted
            }
        }
    }
    Ok(())
}
```

#### 2. PTY Thread Never Joined (process.rs:296)
**Problem**: Reader thread continues running after cleanup.
**Impact**: Resource leaks, hung processes.

**Fix**:
- Store `JoinHandle` instead of `_handle`
- Add `shutdown` atomic flag for thread to check
- Join thread in `Drop` impl or explicit cleanup

### HIGH: Backend

#### 3. Broadcast Channel Events Silently Dropped (session.rs:59)
**Problem**: Fixed capacity 256, slow clients cause silent event loss.
**Impact**: Dashboard misses activity updates.

**Fix**:
- Track lag with `recv().await` error handling
- Send `events_missed` notification to clients when lagged
- Add tracing for lag events
- Consider increasing buffer or using bounded mpsc with backpressure

#### 4. No Input Validation/Rate Limiting (websocket.rs:184-213)
**Problem**: Accepts unlimited input messages, no size limits.
**Impact**: Potential DoS with malicious input.

**Fix**:
- Add max input size validation (10KB reasonable)
- Add rate limiter: max 10 messages/second per connection
- Validate UTF-8 for terminal input

#### 5. Database Updates Fail Silently (session.rs:354-367)
**Problem**: `let _ = self.db.update_stats(...)` ignores errors.
**Impact**: Stale stats in UI.

**Fix**:
- Log database errors with tracing::warn!
- Don't silently ignore - at minimum trace the failure

#### 6. WebSocket Send Errors Not Logged (websocket.rs:174-176)
**Problem**: Connection closes without error message.
**Impact**: Silent disconnects hard to debug.

**Fix**:
- Add tracing::debug! for send errors with context
- Include session_id and error details

### HIGH: Frontend

#### 7. No Message Buffering (ws.ts:102-108)
**Problem**: Messages sent while disconnected are silently dropped.
**Impact**: Users lose input on reconnect.

**Fix**:
```typescript
// Add to createWebSocketManager:
const MAX_QUEUE_SIZE = 50;
let messageQueue: unknown[] = [];

function send(data: unknown): boolean {
  if (ws?.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(data));
    return true;
  }
  // Queue message for later (cap size)
  if (messageQueue.length < MAX_QUEUE_SIZE) {
    messageQueue.push(data);
  }
  return false;
}

// In onopen callback, flush queue:
ws.onopen = () => {
  setState('connected');
  reconnectCount = 0;
  // Flush queued messages
  while (messageQueue.length > 0) {
    const msg = messageQueue.shift();
    ws!.send(JSON.stringify(msg));
  }
};
```

#### 8. Terminal Input Has No Fallback (Session.tsx:316-320)
**Problem**: Terminal input fails silently when WS disconnected.
**Impact**: User types but nothing happens.

**Fix**:
- Show visual indicator when WS disconnected
- Queue terminal input (limited buffer)
- Flush on reconnect

#### 9. cleanupOldSessions() Never Called (terminal.ts:148-168)
**Problem**: Function exists but never invoked.
**Impact**: Memory leak in localStorage over time.

**Fix**:
- Call on app startup
- Call when session is deleted
- Clean up sessions older than 7 days or beyond limit (50)

#### 10. Unbounded Terminal Data Queue (Session.tsx terminalData signal)
**Problem**: No max size on queue when terminal not ready.
**Impact**: Could OOM on long reconnection delay.

**Fix**:
- Cap queue to 100 chunks (400KB)
- Drop oldest when exceeded

#### 11. Session Store Inefficient Updates (sessions.ts:89-116)
**Problem**: Comment says "Uses produce()" but actually uses `.map()` with spreads. All memos invalidated.
**Impact**: 50+ re-renders per second with active sessions.

**Fix**:
```typescript
// Instead of: setSessionsStore('list', sessions => sessions.map(...))
// Use path-based updates:
const idx = sessionsStore.list.findIndex(s => s.id === update.session_id);
if (idx !== -1) {
  setSessionsStore('list', idx, {
    model: update.model || sessionsStore.list[idx].model,
    total_cost_usd: update.cost,
    // ... other fields
  });
}
```
- Use `produce()` from solid-js/store for complex nested updates
- Update only changed fields, not entire objects

#### 12. Multiple Resize Sends (Session.tsx:220-225)
**Problem**: Sends resize 5 times with hardcoded delays.
**Impact**: Code smell, wastes bandwidth.

**Fix**:
- Single debounced resize with 300ms delay
- Trust server to handle resize properly
- Add server acknowledgment if needed

---

## Files to Modify

### Backend (Rust)
| File | Changes |
|------|---------|
| `crates/clauset-core/src/process.rs` | Process termination with SIGTERM/SIGKILL, join threads, close PTY |
| `crates/clauset-core/src/session.rs` | Log DB errors, handle broadcast lag |
| `crates/clauset-server/src/websocket.rs` | Log send errors, add input validation, rate limiting |
| `crates/clauset-server/src/event_processor.rs` | Add tracing for event flow |
| `crates/clauset-core/src/error.rs` | Add new error variants if needed |
| `crates/clauset-server/Cargo.toml` | Add governor for rate limiting (if not using manual) |

### Frontend (TypeScript)
| File | Changes |
|------|---------|
| `frontend/src/lib/ws.ts` | Add message queue, flush on reconnect |
| `frontend/src/lib/terminal.ts` | Call cleanupOldSessions(), add queue cap |
| `frontend/src/stores/sessions.ts` | Fine-grained store updates |
| `frontend/src/components/Session.tsx` | Cap terminal queue, single resize, disconnect indicator |
| `frontend/src/components/TerminalView.tsx` | Remove multiple resize timeouts |

---

## Implementation Order

### Phase 1: Critical Backend Fixes (Must Do First)
1. Fix process termination in `process.rs`
   - Add `shutdown` flag (AtomicBool)
   - Store Child handle for signal sending
   - Implement graceful shutdown: SIGTERM → 5s wait → SIGKILL
   - Join PTY reader thread
2. Test: Verify processes actually terminate (`ps aux | grep claude`)

### Phase 2: High Backend Fixes
3. Add input validation and rate limiting to `websocket.rs`
4. Add broadcast lag detection and tracing to `session.rs`
5. Log DB errors instead of ignoring
6. Log WebSocket send errors

### Phase 3: Frontend Fixes
7. Add message queue to `ws.ts`
8. Cap terminal data queue in `Session.tsx`
9. Call `cleanupOldSessions()` in `terminal.ts`
10. Refactor `sessions.ts` for fine-grained updates
11. Fix resize send pattern in `Session.tsx`

### Phase 4: Tracing & Observability
12. Add tracing spans for:
    - Process lifecycle (spawn, terminate)
    - WebSocket events (connect, disconnect, message)
    - Buffer operations (append, overflow)
    - Event broadcast (sent, lagged)

---

## Verification Steps

After each phase:
1. Run `cargo build --release` - must compile
2. Run `cargo test` - all tests pass
3. Manual testing:
   - Create session, verify process starts
   - Delete session, verify process terminates (`ps aux | grep claude`)
   - Disconnect WiFi, reconnect, verify messages queued
   - Check localStorage doesn't grow unbounded
   - Monitor terminal output streaming for lag

---

## Rollback Strategy
- Each phase is a logical unit that can be reverted
- Keep changes small and incremental
- Test after each file modification
- No commits until full verification by user

---

## Non-Goals (Out of Scope)
- Medium/Low severity issues
- New features
- Architecture changes beyond necessary fixes
- Database schema changes
- API contract changes
