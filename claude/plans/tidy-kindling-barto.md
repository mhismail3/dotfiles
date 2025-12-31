# Fix: Initial Prompt Not Executing When Creating New Session

## Problem
When user enters an initial prompt in the "Initial Prompt" field and clicks "create session":
- The message text appears in the terminal ✓
- A newline appears after the message (cursor on next line) ✓
- But Claude doesn't execute/respond - the `\r` isn't triggering submit ✗

Same issue that was fixed for chat mode - need to apply the same fix to initial prompts.

## Root Cause
Initial prompt uses a **different code path** than chat messages:
- **Chat messages**: Frontend → `sendInput()` API → `process_manager.send_input()` ← **WORKS**
- **Initial prompt**: spawn_terminal() reader thread writes directly to PTY ← **BROKEN**

## Fix
Make the initial prompt use the **same code path** as chat messages by calling `send_input()` instead of writing directly in spawn_terminal().

### Changes

**1. `crates/clauset-core/src/process.rs`** - Remove direct PTY writing for initial prompt

In `spawn_terminal()` (lines 366-392), remove the prompt writing code. Keep the "ready" detection but just set `prompt_sent = true` without writing:

```rust
// Before (remove this block):
if ready {
    std::thread::sleep(Duration::from_millis(800));
    if let Ok(mut w) = writer_clone.lock() {
        let _ = w.write_all(initial_prompt.as_bytes());
        let _ = w.flush();
        std::thread::sleep(Duration::from_millis(50));
        let _ = w.write_all(b"\r");
        let _ = w.flush();
    }
    prompt_sent = true;
}
```

Remove all the initial prompt handling from spawn_terminal() - don't pass prompt to spawn at all.

**2. `crates/clauset-core/src/session.rs`** - Send initial prompt via send_input()

In `start_session()`, after spawn completes and session is active, send the prompt with a delay to ensure Claude is ready:

```rust
// After line 188 (initialize_session_activity):
if !prompt.is_empty() {
    // Wait for Claude to be fully ready (matches the ~800ms the old code waited)
    tokio::time::sleep(std::time::Duration::from_millis(1000)).await;
    // Use send_input() - same code path as chat messages
    self.process_manager.send_input(session_id, prompt).await?;
}
```

The 1000ms delay ensures Claude's TUI is fully initialized before sending input.

**3. `crates/clauset-core/src/process.rs`** - Update SpawnOptions

Remove `prompt` field from `SpawnOptions` since it's no longer used in spawn_terminal().

## Verification
1. Create a new session with an initial prompt
2. Verify the prompt executes and Claude responds
3. Ensure chat tab shows Claude's response
4. Test sending messages in chat mode still works (regression check)
