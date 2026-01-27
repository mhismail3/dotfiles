# Agent Package Architecture Analysis & Remediation Plan

## Executive Summary

**Current Score: 68/100**
**Target Score: 96/100**

The agent package has a solid foundation with clear layered architecture, sophisticated error handling, and good barrel file discipline. However, it has accumulated technical debt in the form of god objects (1000+ line files), global state access patterns, and insufficient integration testing.

---

## Critical Constraints

1. **ZERO REGRESSIONS** - Provider code is production-critical. Every refactor must maintain exact behavioral compatibility.
2. **TEST-DRIVEN DEVELOPMENT** - Write comprehensive tests BEFORE refactoring. Tests prove existing behavior, then guide the split.
3. **COMPREHENSIVE INTEGRATION TESTS** - Cover edge cases: provider switching mid-session, forking with tool state, concurrent sessions, error recovery combinations.

---

## Score Breakdown

| Category | Current | Target | Weight |
|----------|---------|--------|--------|
| Structural Cohesion | 14/20 | 19/20 | 20% |
| Dependency Management | 10/20 | 18/20 | 20% |
| Test Coverage | 15/20 | 19/20 | 20% |
| Type Safety | 12/15 | 14/15 | 15% |
| API Design | 10/15 | 14/15 | 15% |
| Error Handling | 7/10 | 9/10 | 10% |
| **Total** | **68/100** | **96/100** | |

---

## Current Strengths

1. **7-tier dependency hierarchy** - Foundation → Infrastructure → Provider → Business → Orchestration → Service → External
2. **Barrel file discipline** - All 57 modules use explicit re-exports, no wildcards
3. **TronError hierarchy** - Structured error classes with codes, categories, context
4. **Hook system** - Clean PreToolUse/PostToolUse abstraction
5. **Provider abstraction** - Common interface across Anthropic/OpenAI/Google
6. **Event sourcing** - Immutable event log with tree structure

---

## Critical Issues

### Issue 1: God Objects (files 700+ lines)

| File | Lines | Responsibilities |
|------|-------|------------------|
| `providers/google.ts` | 1200 | Auth + streaming + tools + retry + safety |
| `providers/anthropic.ts` | 1090 | Auth + streaming + tools + retry + thinking |
| `session/worktree-coordinator.ts` | 1001 | Git + worktrees + merge + recovery + events |
| `providers/openai-codex.ts` | 970 | Auth + streaming + responses API |
| `auth/google-oauth.ts` | 866 | OAuth flow + token refresh + project discovery |
| `orchestrator/session/session-manager.ts` | 787 | Create + resume + fork + cleanup + trackers |
| `utils/errors.ts` | 765 | 15+ error classes + categorization |
| `orchestrator/agent-runner.ts` | 715 | Turn execution + tool dispatch + streaming |
| `orchestrator/turn/turn-content-tracker.ts` | 701 | Content accumulation + reconstruction |

### Issue 2: Global State Access

`getSettings()` called directly in 18+ files instead of dependency injection:
- `providers/anthropic.ts`, `providers/openai-codex.ts`
- `auth/oauth.ts`, `auth/google-oauth.ts`
- `tools/system/bash.ts`, `tools/fs/read.ts`, `tools/fs/find.ts`, `tools/fs/grep.ts`
- `hooks/discovery.ts`, `hooks/engine.ts`
- `transcription/sidecar.ts`, `transcription/client.ts`
- And more...

### Issue 3: Integration Test Gap

- Only 1 `__integration__` directory with basic worktree tests
- No end-to-end event reconstruction tests
- No provider switching tests
- No concurrent session tests

### Issue 4: Mock Typing Issues

Tests use unsafe `as Type` casts:
```typescript
const mockEventStore = { append: vi.fn() } as EventStore; // Unsafe
```

---

## Remediation Plan

### Phase 1: Provider Decomposition (High Impact, Low Effort)

Split monolithic providers into focused modules.

**TDD APPROACH - CRITICAL:**
1. **Before ANY refactoring**, write comprehensive tests against the CURRENT monolithic provider
2. Tests must cover: streaming, tool calls, auth refresh, error handling, thinking mode
3. Run tests to prove they pass on current code
4. Only THEN begin splitting - tests ensure zero regressions
5. After split, ALL tests must still pass with NO modifications

#### 1.0 Provider Test Suite (WRITE FIRST)

**New:** `providers/__tests__/provider-contracts.test.ts`
```typescript
// Contract tests that ALL providers must pass
describe('Provider Contract Tests', () => {
  const providers = [
    () => createAnthropicProvider(mockConfig),
    () => createGoogleProvider(mockConfig),
    () => createOpenAIProvider(mockConfig),
  ];

  describe.each(providers)('Provider: %s', (createProvider) => {
    it('streams text deltas correctly', async () => { ... });
    it('handles tool calls with correct ID mapping', async () => { ... });
    it('resumes after rate limit errors', async () => { ... });
    it('preserves message order during streaming', async () => { ... });
    it('handles auth token refresh mid-stream', async () => { ... });
    it('propagates abort signals correctly', async () => { ... });
    it('returns correct token counts', async () => { ... });
  });
});
```

**New:** `providers/anthropic/__tests__/anthropic-provider.test.ts`
```typescript
// Anthropic-specific behavior tests
describe('AnthropicProvider', () => {
  describe('message conversion', () => {
    it('converts user messages with images', async () => { ... });
    it('converts tool results to correct format', async () => { ... });
    it('handles thinking blocks correctly', async () => { ... });
  });

  describe('streaming', () => {
    it('parses SSE events correctly', async () => { ... });
    it('accumulates content deltas in order', async () => { ... });
    it('emits tool_use blocks at correct timing', async () => { ... });
  });

  describe('auth', () => {
    it('refreshes OAuth token before expiry', async () => { ... });
    it('retries with fresh token on 401', async () => { ... });
  });

  describe('error handling', () => {
    it('maps API errors to ProviderError', async () => { ... });
    it('identifies retryable vs fatal errors', async () => { ... });
    it('respects rate limit headers', async () => { ... });
  });
});
```

#### 1.1 Anthropic Provider Split

**Current:** `providers/anthropic.ts` (1090 lines)

**Target Structure:**
```
providers/anthropic/
├── index.ts                  # Public exports, factory (EXACT same API)
├── anthropic-provider.ts     # Core provider class (~350 lines)
├── message-converter.ts      # Message/tool format conversion (~200 lines)
├── stream-handler.ts         # SSE parsing, event mapping (~200 lines)
├── auth.ts                   # OAuth refresh, token management (~150 lines)
├── thinking-mode.ts          # Extended thinking support (~100 lines)
└── __tests__/
    ├── anthropic-provider.test.ts
    ├── message-converter.test.ts
    └── stream-handler.test.ts
```

#### 1.2 Google Provider Split

**Current:** `providers/google.ts` (1200 lines)

**Target Structure:**
```
providers/google/
├── index.ts                  # Public exports, factory
├── google-provider.ts        # Core provider class (~300 lines)
├── message-converter.ts      # Gemini format conversion (~200 lines)
├── stream-handler.ts         # SSE parsing (~200 lines)
├── auth.ts                   # OAuth, project discovery (~200 lines)
├── safety-settings.ts        # Safety configuration (~100 lines)
├── thinking-mode.ts          # Thinking support (~100 lines)
└── __tests__/
```

#### 1.3 Shared Provider Infrastructure

**New:** `providers/shared/`
```
providers/shared/
├── retry.ts                  # Shared retry logic (move from base/)
├── tool-id-mapping.ts        # Cross-provider ID normalization
├── streaming-utils.ts        # Common SSE utilities
└── types.ts                  # Shared provider interfaces
```

---

### Phase 2: Dependency Injection Migration (High Impact, Medium Effort)

Replace global `getSettings()` with explicit DI.

#### 2.1 Create Settings Provider Interface

**New file:** `src/di/settings-provider.ts`
```typescript
export interface SettingsProvider {
  get<K extends keyof Settings>(key: K): Settings[K];
  getAll(): Settings;
}

export class DefaultSettingsProvider implements SettingsProvider {
  private settings: Settings;

  constructor() {
    this.settings = loadSettings(); // One-time load
  }

  get<K extends keyof Settings>(key: K): Settings[K] {
    return this.settings[key];
  }

  getAll(): Settings {
    return this.settings;
  }
}
```

#### 2.2 Update Consumers

**Pattern:**
```typescript
// Before (in anthropic.ts):
function getAnthropicSettings() {
  const settings = getSettings();
  return settings.api.anthropic;
}

// After:
export function createAnthropicProvider(
  config: AnthropicConfig,
  settings: SettingsProvider
): AnthropicProvider {
  return new AnthropicProvider(config, settings.get('api').anthropic);
}
```

#### 2.3 Files to Update

1. `providers/anthropic.ts` → inject settings
2. `providers/openai-codex.ts` → inject settings
3. `providers/google.ts` → inject settings
4. `tools/system/bash.ts` → inject timeout settings
5. `tools/fs/read.ts` → inject limit settings
6. `tools/fs/grep.ts` → inject skip directories
7. `hooks/engine.ts` → inject hook settings
8. `auth/oauth.ts` → inject auth settings

---

### Phase 3: God Object Decomposition (High Impact, Medium Effort)

#### 3.1 Split WorktreeCoordinator (1001 lines)

**Current:** `session/worktree-coordinator.ts`

**Target Structure:**
```
session/worktree/
├── index.ts                  # Public exports
├── worktree-coordinator.ts   # Facade (~200 lines)
├── worktree-lifecycle.ts     # Create/remove worktrees (~200 lines)
├── merge-handler.ts          # Merge strategies (~150 lines)
├── isolation-policy.ts       # shouldIsolate logic (~80 lines)
├── recovery.ts               # Orphan recovery (~100 lines)
├── git-executor.ts           # (existing, unchanged)
├── worktree-events.ts        # (existing, unchanged)
└── types.ts
```

**Facade Pattern:**
```typescript
export class WorktreeCoordinator {
  constructor(
    private lifecycle: WorktreeLifecycle,
    private mergeHandler: MergeHandler,
    private isolationPolicy: IsolationPolicy,
    private recovery: WorktreeRecovery
  ) {}

  async acquire(sessionId: string, workingDir: string, options?: AcquireOptions) {
    if (!this.isolationPolicy.shouldIsolate(sessionId, options)) {
      return this.lifecycle.acquireMainDirectory(sessionId);
    }
    return this.lifecycle.createWorktree(sessionId, workingDir, options);
  }
}
```

#### 3.2 Split SessionManager (787 lines)

**Current:** `orchestrator/session/session-manager.ts`

**Target Structure:**
```
orchestrator/session/
├── session-manager.ts        # Facade (~200 lines)
├── session-lifecycle.ts      # Create/terminate (~200 lines)
├── session-resume.ts         # Resume with reconstruction (~200 lines)
├── session-fork.ts           # Fork operations (~100 lines)
├── tracker-reconstructor.ts  # Rebuild trackers from events (~100 lines)
├── session-context.ts        # (existing, unchanged)
└── session-reconstructor.ts  # (existing, unchanged)
```

---

### Phase 4: Comprehensive Integration Test Suite (High Impact, High Priority)

**Goal:** Cover ALL edge cases including combinations of operations.

#### 4.1 Event Flow Tests

**New:** `__integration__/event-flow/`
```
__integration__/event-flow/
├── message-reconstruction.test.ts    # User/assistant message roundtrip
├── tool-call-reconstruction.test.ts  # Tool call/result pairing
├── fork-reconstruction.test.ts       # Fork with parent chain
├── compaction-reconstruction.test.ts # Compaction boundary handling
├── large-input-truncation.test.ts    # >5KB input restoration
└── streaming-interruption.test.ts    # Abort mid-stream, resume
```

#### 4.2 Session Lifecycle Tests

**New:** `__integration__/session-lifecycle/`
```
__integration__/session-lifecycle/
├── create-resume-end.test.ts         # Full lifecycle
├── concurrent-sessions.test.ts       # Parallel execution
├── interrupt-recovery.test.ts        # Graceful interrupt
├── session-cleanup.test.ts           # Cleanup on termination
├── session-timeout.test.ts           # Timeout handling
└── orphan-session-recovery.test.ts   # Recovery after crash
```

#### 4.3 Provider Switching Tests (CRITICAL)

**New:** `__integration__/provider-switching/`
```
__integration__/provider-switching/
├── anthropic-to-openai.test.ts       # Mid-session provider switch
├── openai-to-google.test.ts          # Different token formats
├── google-to-anthropic.test.ts       # Different auth mechanisms
├── switch-with-tool-state.test.ts    # Switch while tools active
├── switch-with-pending-results.test.ts # Switch with pending tool results
├── tool-id-remapping.test.ts         # Tool ID normalization across providers
└── context-preservation.test.ts      # Messages preserved across switch
```

**Key scenarios:**
```typescript
describe('Provider Switching', () => {
  it('preserves conversation history when switching providers', async () => {
    // Start with Anthropic, send messages
    // Switch to OpenAI mid-conversation
    // Verify all messages reconstructed correctly
  });

  it('remaps tool IDs when switching providers', async () => {
    // Start tool call with Anthropic (toolu_xxx format)
    // Switch to OpenAI mid-tool
    // Verify tool result matches correctly
  });

  it('handles auth differences transparently', async () => {
    // Anthropic OAuth → OpenAI API key → Google OAuth
    // Each switch should handle auth seamlessly
  });

  it('preserves streaming state during switch', async () => {
    // Abort stream on provider A
    // Resume on provider B
    // Verify no data loss
  });
});
```

#### 4.4 Fork Tests (COMPREHENSIVE)

**New:** `__integration__/forking/`
```
__integration__/forking/
├── basic-fork.test.ts                # Fork from any event
├── fork-with-tools.test.ts           # Fork with active tool calls
├── fork-with-subagents.test.ts       # Fork with spawned subagents
├── fork-chain.test.ts                # Fork of a fork of a fork
├── parallel-forks.test.ts            # Multiple forks from same point
├── fork-after-compaction.test.ts     # Fork after context compacted
├── fork-with-provider-switch.test.ts # Fork + switch provider
└── fork-reconstruction.test.ts       # Verify all forks reconstruct
```

**Key scenarios:**
```typescript
describe('Forking Edge Cases', () => {
  it('forks session with active tool calls in flight', async () => {
    // Start tool call
    // Fork BEFORE tool result
    // Both branches should handle tool result correctly
  });

  it('forks after context compaction', async () => {
    // Long session → compaction
    // Fork from pre-compaction event
    // Verify full history available in fork
  });

  it('handles fork chains (fork of fork)', async () => {
    // Create: A → B (fork) → C (fork of B)
    // Verify C has full ancestry
    // Verify independent mutations
  });

  it('forks with different providers', async () => {
    // Session on Anthropic
    // Fork to OpenAI provider
    // Both branches work independently
  });
});
```

#### 4.5 Combined Edge Cases

**New:** `__integration__/edge-cases/`
```
__integration__/edge-cases/
├── fork-switch-fork.test.ts          # Fork → switch provider → fork again
├── concurrent-forks-different-providers.test.ts
├── compaction-during-tool-call.test.ts
├── subagent-spawn-during-fork.test.ts
├── interrupt-during-fork.test.ts
├── rate-limit-during-fork.test.ts
├── network-error-recovery.test.ts
└── max-context-with-fork.test.ts
```

**Combination scenarios:**
```typescript
describe('Combined Edge Cases', () => {
  it('handles fork → provider switch → fork', async () => {
    // Anthropic session
    // Fork to session B
    // Switch B to OpenAI
    // Fork B to session C (on OpenAI)
    // Verify all three work independently
  });

  it('handles concurrent forks with different providers', async () => {
    // Fork session to A (Anthropic) and B (OpenAI) simultaneously
    // Send different messages to each
    // Verify isolation
  });

  it('handles tool call spanning fork point', async () => {
    // Tool call started
    // Fork at tool.call event
    // Original gets tool.result
    // Fork never gets result (new branch)
    // Verify both valid states
  });

  it('recovers from network error during provider switch', async () => {
    // Switch provider
    // Network fails mid-switch
    // Retry or rollback
    // Verify session integrity
  });
});
```

#### 4.6 Stress Tests

**New:** `__integration__/stress/`
```
__integration__/stress/
├── rapid-provider-switching.test.ts  # Switch 10 times quickly
├── many-concurrent-sessions.test.ts  # 50+ parallel sessions
├── deep-fork-tree.test.ts            # Fork 20 levels deep
├── large-context-fork.test.ts        # Fork at 180k tokens
└── rapid-fork-create.test.ts         # Create 100 forks in 1 second
```

---

### Phase 5: Polish (Lower Priority)

#### 5.1 Fix Mock Typing

Create proper mock factories:
```typescript
// __fixtures__/mocks/event-store.ts
export function createMockEventStore(
  overrides?: Partial<EventStore>
): EventStore {
  return {
    append: vi.fn().mockResolvedValue({ id: 'evt_123' }),
    getSession: vi.fn().mockResolvedValue(null),
    queryEvents: vi.fn().mockResolvedValue([]),
    ...overrides,
  };
}
```

#### 5.2 Centralize Fixtures

**New:** `__fixtures__/`
```
__fixtures__/
├── events/
│   ├── session-events.ts
│   ├── message-events.ts
│   └── tool-events.ts
├── messages/
│   ├── user-messages.ts
│   └── assistant-messages.ts
└── mocks/
    ├── event-store.ts
    ├── context-manager.ts
    └── providers.ts
```

---

## Implementation Priority (TDD Order)

**Key Principle:** Tests FIRST, then refactor. Never refactor without tests proving current behavior.

| Priority | Task | Impact | Effort | Score Gain | Prerequisite |
|----------|------|--------|--------|------------|--------------|
| 1 | Write provider contract tests | Critical | Medium | +2 | None |
| 2 | Write Anthropic-specific tests | Critical | Medium | +2 | #1 |
| 3 | Write provider switching integration tests | Critical | High | +4 | #1 |
| 4 | Write fork integration tests | Critical | High | +4 | None |
| 5 | Split Anthropic provider | High | Low | +3 | #1, #2 pass |
| 6 | Split Google provider | High | Low | +3 | #1 pass |
| 7 | Write combined edge case tests | High | Medium | +3 | #3, #4 |
| 8 | Create DI infrastructure | High | Medium | +2 | None |
| 9 | Split WorktreeCoordinator | High | Medium | +2 | Tests exist |
| 10 | Split SessionManager | Medium | Medium | +2 | Tests exist |
| 11 | Replace getSettings() calls | Medium | Low | +2 | #8 |
| 12 | Fix mock typing + centralize fixtures | Low | Low | +2 | None |

**Total potential gain: +28 points (68 → 96)**

**Critical Path:**
1. Write comprehensive tests (Priority 1-4) - BLOCKS refactoring
2. Refactor providers (Priority 5-6) - Tests prove no regression
3. Add edge case tests (Priority 7) - Proves robustness
4. Continue with remaining refactors

---

## Verification Protocol

### Before ANY Refactoring

```bash
# 1. Run ALL existing tests - establish baseline
bun run test

# 2. Run type check
bun run typecheck

# 3. Capture test count
bun run test 2>&1 | grep -E "Tests.*passed"
# Example: "Tests: 3796 passed"
```

### After Each Refactor Step

```bash
# 1. Build must succeed
bun run build

# 2. ALL tests must pass - ZERO regressions
bun run test

# 3. Test count must be >= baseline (new tests added, none removed)
bun run test 2>&1 | grep -E "Tests.*passed"

# 4. Type check
bun run typecheck
```

### Provider-Specific Verification

```bash
# After provider split, run provider-specific tests
bun run test src/providers/

# Run integration tests
bun run test:agent:integration

# Verify provider contract tests pass for ALL providers
bun run test src/providers/__tests__/provider-contracts.test.ts
```

### Integration Test Coverage

```bash
# Run all integration tests
bun run test:agent:integration

# Verify edge cases covered
bun run test src/__integration__/provider-switching/
bun run test src/__integration__/forking/
bun run test src/__integration__/edge-cases/
```

### Regression Checklist

Before considering any phase complete:

- [ ] `bun run build` succeeds
- [ ] `bun run test` passes with ZERO failures
- [ ] Test count >= baseline (no tests deleted)
- [ ] `bun run typecheck` has no errors
- [ ] Provider contract tests pass for all providers
- [ ] Integration tests pass
- [ ] No `as any` or `as Type` casts added
- [ ] No new eslint warnings

---

## Files to Modify

### Phase 1 (Provider Split)
- `packages/agent/src/providers/anthropic.ts` → split into `anthropic/` folder
- `packages/agent/src/providers/google.ts` → split into `google/` folder
- `packages/agent/src/providers/index.ts` → update exports

### Phase 2 (DI Migration)
- `packages/agent/src/di/` → new module (settings-provider.ts)
- `packages/agent/src/settings/index.ts` → add SettingsProvider export
- 18 files using getSettings() → update to use injected settings

### Phase 3 (God Object Split)
- `packages/agent/src/session/worktree-coordinator.ts` → split into `worktree/` folder
- `packages/agent/src/orchestrator/session/session-manager.ts` → split into focused files

### Phase 4 (Integration Tests)
- `packages/agent/src/__integration__/` → add new test directories

### Phase 5 (Polish)
- `packages/agent/src/__fixtures__/` → new centralized fixtures
- Various test files → update to use mock factories
