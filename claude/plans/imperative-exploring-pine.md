# Fix Chat-to-Terminal Enter Key Mapping

## Problem
When sending a message from chat mode (e.g., typing "hello world" and pressing Enter), the text appears in the terminal but the Enter keypress doesn't execute the command. Switching to terminal view shows the text followed by a new prompt line, but the command wasn't submitted.

## Root Cause
PTY terminals expect `\r` (carriage return) to execute commands, but `send_input()` sends `\n` (line feed).

**Evidence:**
- Initial prompt sending (process.rs:385) correctly uses `b"\r"` and works
- Chat input (process.rs:436) incorrectly uses `"\n"` and doesn't execute
- Terminal raw input sends bytes as-is (xterm.js sends `\r` for Enter), which works

## Fix

### File: `crates/clauset-core/src/process.rs`

**Line 436** - Change from:
```rust
let input_with_newline = format!("{}\n", input);
```

To:
```rust
let input_with_newline = format!("{}\r", input);
```

## Verification
1. Start a session
2. Switch to chat mode
3. Type a message and press Enter
4. Switch to terminal mode - verify the message was executed (not just displayed)
5. Verify Claude responds to the message

## Files Changed
- `crates/clauset-core/src/process.rs` (1 line change)
