# Plan: Fix Context Percentage Display and Mode Status Bar

## Issue 1: Context Percentage Missing from Session Cards

**Root Cause**: `SessionCard.tsx:465` has condition `<Show when={props.session.context_percent > 0}>` which hides context at 0%.

**Fix**: Change to `>= 0` to always show context percentage.

**File**: `frontend/src/components/SessionCard.tsx:465`

```tsx
// Before:
<Show when={props.session.context_percent > 0}>

// After:
<Show when={props.session.context_percent >= 0}>
```

---

## Issue 2: Mode Status Bar Not Updating

**Root Cause** (confirmed): When mode changes via `/mode` command:
- Claude Code updates its visual status line display (not terminal text output)
- **No text is printed to terminal** → `parse_permission_mode()` can't detect it
- Mode only syncs when NEXT hook event fires (contains `permission_mode` field)

**Current flow**:
1. User clicks quick action → sends `/mode plan` to terminal
2. Claude Code changes mode internally (status line updates visually)
3. **No hook fires immediately** → Clauset doesn't know mode changed
4. When Claude next uses a tool or user sends message → hook fires with new `permission_mode`
5. `hooks.rs:71-73` → `update_permission_mode()` → `ModeChange` event → frontend updates

**Fix**: Add debug logging to verify hooks include `permission_mode`, ensure sync works.

**File**: `crates/clauset-server/src/routes/hooks.rs:71-75`

```rust
// Add logging to see permission_mode values:
if let Some(ref raw_mode) = permission_mode {
    tracing::debug!(target: "clauset::hooks", "Hook permission_mode: {:?}", raw_mode);
    if let Some(mode) = PermissionMode::from_hook_value(raw_mode) {
        tracing::info!(target: "clauset::hooks", "Mode change detected: {:?}", mode);
        state.session_manager.update_permission_mode(session_id, mode).await;
    }
} else {
    tracing::debug!(target: "clauset::hooks", "Hook missing permission_mode");
}
```

---

## Implementation Steps

1. **Issue 1** (1 line): Change `> 0` to `>= 0` in SessionCard.tsx:465
2. **Issue 2** (diagnostic): Add debug logging to hooks.rs
3. **Test Issue 2**: Change mode, then send a message (triggers hook), verify mode updates

## Files to Modify

- `frontend/src/components/SessionCard.tsx` - line 465
- `crates/clauset-server/src/routes/hooks.rs` - lines 71-75
