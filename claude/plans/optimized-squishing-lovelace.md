# Fix: Inflated Output Token Count on Dashboard Cards

## Problem
Output token counts on session cards show massively inflated values (804K, 993K instead of 1.7K) during real-time updates. Clicking into session and back fixes it.

## Root Cause
The status line regex patterns in `buffer.rs` make the `K` suffix OPTIONAL (`K?`). When Claude's terminal output contains patterns like `804/993` (file counts, progress indicators, etc.) at the start of any line, the regex matches it as token counts and multiplies by 1000.

**Evidence:** Screenshots show `2.2K/804.0K` where 804.0K = 804,000 raw tokens = regex matching "804" and multiplying by 1000.

**Compounding factor:** Frontend `Math.max()` logic prevents recovery - once inflated, smaller (correct) values can't replace it.

## Files to Modify

### Primary Fix (Backend)
1. **`crates/clauset-core/src/buffer.rs`** - Make `K` suffix required in regexes

### Secondary Fix (Frontend)
2. **`frontend/src/stores/sessions.ts`** - Remove problematic `Math.max()` for tokens

## Implementation Plan

### Step 1: Fix Regex Patterns (buffer.rs lines 785-797)

**Current (buggy):**
```rust
// STATUS_LINE_FULL (line 789)
r"...([0-9.]+)K?/([0-9.]+)K?..."

// STATUS_LINE_TOKENS (line 796)
r"^([0-9.]+)K?/([0-9.]+)K?..."
```

**Fixed:**
```rust
// STATUS_LINE_FULL - require K suffix
r"...([0-9.]+)K/([0-9.]+)K..."

// STATUS_LINE_TOKENS - require K suffix
r"^([0-9.]+)K/([0-9.]+)K..."
```

### Step 2: Add Token Value Validation (buffer.rs ~line 834)

After parsing tokens, add sanity check:
```rust
// Claude Code typically shows < 500K tokens per metric
// Reject obvious false positives
if input_k > 500.0 || output_k > 500.0 {
    continue; // Skip this line, likely a false positive
}
```

### Step 3: Remove Math.max() in Frontend (sessions.ts lines 119-121)

**Current (problematic):**
```typescript
input_tokens: update.input_tokens > 0 ? Math.max(update.input_tokens, session.input_tokens) : session.input_tokens,
output_tokens: update.output_tokens > 0 ? Math.max(update.output_tokens, session.output_tokens) : session.output_tokens,
```

**Fixed - trust backend values:**
```typescript
input_tokens: update.input_tokens > 0 ? update.input_tokens : session.input_tokens,
output_tokens: update.output_tokens > 0 ? update.output_tokens : session.output_tokens,
```

### Step 4: Add Debug Logging (optional)

Add trace-level logging in `parse_status_line()` when a match is found, to help diagnose future issues:
```rust
tracing::trace!(
    target: "clauset::activity::parse",
    "Parsed status line: model='{}', cost=${}, input={}K, output={}K",
    model, cost, input_k, output_k
);
```

## Testing Plan
1. Start server with `RUST_LOG=clauset::activity::parse=trace`
2. Open session that previously showed inflated tokens
3. Verify regex no longer matches false positives
4. Verify correct token counts appear on dashboard
5. Navigate away and back - should remain correct

## Risk Assessment
- **Low risk**: Regex change is stricter, reduces false positives
- **Potential edge case**: Very old Claude Code versions without K suffix - unlikely, Claude Code always shows K suffix
- **Frontend change**: Simpler logic, trusts backend source of truth
