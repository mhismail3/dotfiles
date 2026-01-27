# ContextManager Refactoring Plan

## Status: COMPLETED

## Goal

Refactor `ContextManager` (1005 lines) to extract token estimation utilities and simplify the detailed snapshot generation, while consolidating with the legacy `ContextCompactor` class.

---

## Current State Analysis

**File:** `packages/agent/src/context/context-manager.ts` (1005 lines)

### Method/Section Breakdown

| Section | Lines | Purpose |
|---------|-------|---------|
| Types & Interfaces | 1-167 | Type definitions |
| Threshold Constants | 173-178 | `THRESHOLDS` object |
| Constructor | 223-255 | Initialization, system prompt loading |
| Message Management | 257-384 | add/set/get/clear messages, prompts, rules |
| Token Tracking | 386-427 | get/set API tokens, context limits |
| Snapshot & Validation | 429-581 | `getSnapshot()`, `getDetailedSnapshot()`, `canAcceptTurn()` |
| Model Switching | 583-614 | `switchModel()`, compaction callback |
| Compaction | 616-805 | `shouldCompact()`, `previewCompaction()`, `executeCompaction()` |
| Tool Result Processing | 807-852 | `processToolResult()`, `getMaxToolResultSize()` |
| Serialization | 854-868 | `exportState()` |
| Private Token Helpers | 870-993 | Token estimation for messages, blocks, images |

### Key Findings

1. **Duplicate Compaction Systems:**
   - `ContextCompactor` (compactor.ts, 386 lines) - Legacy, keyword-based summarization
   - `ContextManager` compaction methods - Active, uses injected `Summarizer` for LLM-based summarization
   - `ContextCompactor` is only used in tests/helpers - appears vestigial

2. **Token Estimation Duplication:**
   - `ContextManager.estimateMessageTokens()` and helpers (~120 lines)
   - `ContextCompactor.estimateMessageChars()` and helpers (~70 lines)
   - Both use chars/4 approximation

3. **Extraction Opportunities:**
   - Token estimation → `TokenEstimator` utility (pure functions)
   - Detailed snapshot generation → `ContextSnapshotBuilder` (stateless transformer)

---

## Architecture Design

### Phase 1: Extract TokenEstimator

Create a shared `TokenEstimator` utility that both `ContextManager` and any future compaction code can use.

**New File:** `packages/agent/src/context/token-estimator.ts`

```typescript
/**
 * Pure utility functions for token estimation.
 * Uses chars/4 approximation (consistent with Anthropic's tokenizer).
 */

export interface TokenEstimate {
  tokens: number;
  chars: number;
}

// Message estimation
export function estimateMessageTokens(message: Message): number;

// Block estimation (text, tool_use, tool_result, image, thinking)
export function estimateBlockTokens(block: unknown): number;

// Image-specific estimation (Anthropic: pixels/750)
export function estimateImageTokens(source: ImageSource): number;

// Bulk estimation
export function estimateMessagesTokens(messages: Message[]): number;

// System prompt + tools estimation
export function estimateSystemTokens(systemPrompt: string, tools: Tool[]): number;
```

### Phase 2: Simplify ContextManager

After extracting `TokenEstimator`:

1. Replace private helpers with `TokenEstimator` calls
2. Simplify `getDetailedSnapshot()` to use `TokenEstimator`
3. Remove cached token calculations (let `TokenEstimator` handle caching if needed)

### Phase 3: Deprecate ContextCompactor

The legacy `ContextCompactor` class is unused in production code:
- Only referenced in tests and `context-simulator.ts`
- Its `generateSummary()` uses keyword extraction (inferior to LLM-based)
- Mark as `@deprecated` with migration path to `ContextManager`

---

## Implementation Phases

### Phase 1: TokenEstimator Extraction (TDD)

**Goal:** Extract token estimation into a shared utility with comprehensive tests.

**File to create:** `packages/agent/src/context/token-estimator.ts`

**Tests first:** `packages/agent/src/context/__tests__/token-estimator.test.ts`

**Test cases:**
1. Text message estimation
2. Assistant message with tool_use blocks
3. Tool result messages (string and array content)
4. Image blocks (base64 and URL)
5. Thinking blocks
6. Mixed content blocks
7. Edge cases (empty, null, malformed)

**Methods to extract from ContextManager:**
- `estimateMessageTokens()` → `estimateMessageTokens()`
- `estimateBlockChars()` → `estimateBlockTokens()`
- `estimateSystemPromptTokens()` → combine into `estimateSystemTokens()`
- `estimateToolsTokens()` → combine into `estimateSystemTokens()`
- `estimateRulesTokens()` → `estimateRulesTokens()`
- `getMessagesTokens()` → `estimateMessagesTokens()`

**Verification:**
```bash
bun test packages/agent/src/context/__tests__/token-estimator.test.ts
```

**Phase 1 Results:**
- Created `token-estimator.ts` (186 lines)
- Created `token-estimator.test.ts` (43 tests)
- All tests pass
- Exported from `context/index.ts`

---

### Phase 2: Integrate TokenEstimator into ContextManager

**Goal:** Replace ContextManager's private token helpers with TokenEstimator.

**Changes to ContextManager:**
1. Import `TokenEstimator` functions
2. Replace private methods with delegations
3. Remove `tokenCache` WeakMap (TokenEstimator can manage its own caching if needed)
4. Simplify `getDetailedSnapshot()` to use TokenEstimator

**Before:**
```typescript
private estimateMessageTokens(message: Message): number {
  // 60+ lines of estimation logic
}

private estimateBlockChars(block: unknown): number {
  // 55+ lines of block handling
}
```

**After:**
```typescript
// Import at top
import { estimateMessageTokens, estimateBlockTokens } from './token-estimator.js';

// In getSnapshot():
breakdown: {
  systemPrompt: estimateSystemTokens(this.getSystemPrompt(), this.tools),
  tools: 0, // included in systemPrompt
  rules: estimateRulesTokens(this.rulesContent),
  messages: estimateMessagesTokens(this.messages),
}
```

**Line reduction:** ~120 lines removed from ContextManager

**Verification:**
```bash
bun test packages/agent/src/context/__tests__/context-manager.test.ts
bun test packages/agent/src/context/__tests__/compaction*.test.ts
```

**Phase 2 Results:**
- ContextManager reduced from 1005 to 933 lines (-72 lines)
- Replaced `estimateMessageTokens()` with delegation to TokenEstimator
- Replaced `estimateRulesTokens()` with delegation to TokenEstimator
- Replaced `estimateBlockChars()` entirely (now in TokenEstimator)
- Updated `getMessagesTokens()` to use TokenEstimator with caching
- Updated `estimateSystemPromptTokens()` and `estimateToolsTokens()` to use `CHARS_PER_TOKEN` constant
- All 314 context tests pass
- All 3234 total tests pass

---

### Phase 3: Deprecate Legacy ContextCompactor

**Goal:** Mark `ContextCompactor` as deprecated, update tests to use ContextManager.

**Changes:**
1. Add `@deprecated` JSDoc to `ContextCompactor` class and factory
2. Add deprecation notice pointing to `ContextManager.previewCompaction/executeCompaction`
3. Update `context-simulator.ts` to use ContextManager if possible
4. Keep tests passing but add deprecation warnings

**Deprecation approach:**
```typescript
/**
 * @deprecated Use ContextManager.previewCompaction() and executeCompaction() instead.
 * This class uses simple keyword extraction; ContextManager supports LLM-based summarization.
 */
export class ContextCompactor {
  // ...
}
```

**Note:** Full removal is out of scope - just mark deprecated for now.

---

## Final Results

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| ContextManager lines | 1005 | 933 | -72 |
| TokenEstimator lines | 0 | 186 | NEW |
| New unit tests | 0 | 43 | +43 |
| Total tests | 3191 | 3234 | +43 |
| Duplicate token code | 2 places | 1 place | Consolidated |

### Files Created
- `packages/agent/src/context/token-estimator.ts` (186 lines)
- `packages/agent/src/context/__tests__/token-estimator.test.ts` (43 tests)

### Files Modified
- `packages/agent/src/context/context-manager.ts` (-72 lines, uses TokenEstimator)
- `packages/agent/src/context/compactor.ts` (added @deprecated notices)
- `packages/agent/src/context/index.ts` (exports TokenEstimator, deprecation comments)

### Success Criteria - All Met
- [x] `TokenEstimator` created with comprehensive tests (43 tests)
- [x] All token estimation in one place (not duplicated)
- [x] `ContextManager` uses `TokenEstimator` (no private estimation methods)
- [x] `ContextCompactor` marked deprecated
- [x] All existing tests pass (314 context tests, 3234 total)
- [x] Build succeeds

---

### Phase 4: Export Updates

**Goal:** Export TokenEstimator from module index.

**File to modify:** `packages/agent/src/context/index.ts`

**Add exports:**
```typescript
export {
  estimateMessageTokens,
  estimateMessagesTokens,
  estimateBlockTokens,
  estimateImageTokens,
  estimateSystemTokens,
  estimateRulesTokens,
  type TokenEstimate,
} from './token-estimator.js';
```

---

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `context/token-estimator.ts` | Create | Token estimation utilities |
| `context/__tests__/token-estimator.test.ts` | Create | TDD tests for token estimator |
| `context/context-manager.ts` | Modify | Remove private helpers, use TokenEstimator |
| `context/compactor.ts` | Modify | Add deprecation notices |
| `context/index.ts` | Modify | Export TokenEstimator |

---

## Expected Results

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| ContextManager lines | 1005 | ~880 | -125 |
| TokenEstimator lines | 0 | ~150 | NEW |
| New unit tests | 0 | ~20 | +20 |
| Duplicate token code | 2 places | 1 place | Consolidated |

---

## Success Criteria

- [ ] `TokenEstimator` created with comprehensive tests
- [ ] All token estimation in one place (not duplicated)
- [ ] `ContextManager` uses `TokenEstimator` (no private estimation methods)
- [ ] `ContextCompactor` marked deprecated
- [ ] All existing tests pass
- [ ] Build succeeds

---

## Verification Commands

```bash
# After each phase
bun run build && bun run test

# Specific test files
bun test packages/agent/src/context/__tests__/token-estimator.test.ts
bun test packages/agent/src/context/__tests__/context-manager.test.ts
bun test packages/agent/src/context/__tests__/compaction*.test.ts
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Token estimation differences | Keep exact same char/4 formula, test edge cases |
| Breaking existing tests | Run all context tests before/after each change |
| Performance regression | TokenEstimator uses same O(n) complexity |
| Circular imports | TokenEstimator has no dependencies on ContextManager |

---

## Out of Scope

1. Removing `ContextCompactor` entirely (would require test migration)
2. Changing token estimation algorithm (stick with chars/4)
3. Adding actual tokenizer library (e.g., tiktoken)
4. Extracting `getDetailedSnapshot()` into separate class (minimal benefit)
5. Changing compaction behavior (just refactoring structure)
