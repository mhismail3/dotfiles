# ContextManager Decomposition Plan

## Status: COMPLETED ✅

## Goal

Transform ContextManager from a 933-line "god object" with 32 methods spanning 6+ concerns into a clean coordinator that delegates to focused domain components.

**Current state:** Single class mixing message storage, token tracking, compaction logic, snapshot generation, model configuration, and turn validation.

**Target state:** Thin coordinator exposing domain components, each with single responsibility and comprehensive tests.

## Results

| Metric | Before | After |
|--------|--------|-------|
| ContextManager lines | 933 | 537 |
| New test files | 0 | 3 |
| New tests | 0 | 39 |
| Total tests passing | 3366 | 3425 |
| Build status | ✅ | ✅ |

### Extracted Components

| Component | Lines | Responsibility |
|-----------|-------|----------------|
| `message-store.ts` | 113 | Message storage with token caching |
| `compaction-engine.ts` | 304 | Context compaction logic |
| `context-snapshot-builder.ts` | 278 | Snapshot generation |
| `types.ts` | 188 | Shared type definitions |
| **Total extracted** | 883 | - |

### Phases Completed

- [x] Phase 1: Extract types to context/types.ts
- [x] Phase 2: Extract MessageStore
- [x] Phase 3: Extract CompactionEngine
- [x] Phase 4: Extract ContextSnapshotBuilder
- [x] Phase 5: Consolidate token estimation
- [x] Phase 6: Final cleanup and verification

---

## Current Analysis

### File Stats
- **Location:** `packages/agent/src/context/context-manager.ts`
- **Lines:** 933
- **Public Methods:** 32
- **Private Methods:** 5
- **Concerns Mixed:** 6+

### Current Responsibilities (Mixed Concerns)

| Concern | Methods | Lines (est.) |
|---------|---------|--------------|
| Message Storage | addMessage, setMessages, getMessages, clearMessages | ~40 |
| Token Tracking | getCurrentTokens, getApiContextTokens, setApiContextTokens, estimateMessageTokens, getMessagesTokens, cached estimates | ~80 |
| System Prompt | getSystemPrompt, getRawSystemPrompt, getToolClarificationMessage, requiresToolClarification | ~40 |
| Compaction | shouldCompact, previewCompaction, executeCompaction, onCompactionNeeded | ~180 |
| Model Config | switchModel, getModel, getContextLimit, getProviderType, getWorkingDirectory | ~50 |
| Turn Validation | canAcceptTurn, getThresholdLevel | ~30 |
| Snapshot Generation | getSnapshot, getDetailedSnapshot | ~100 |
| Tool Result Processing | processToolResult, getMaxToolResultSize | ~40 |
| Serialization | exportState | ~10 |
| Rules Management | setRulesContent, getRulesContent | ~15 |

### Key Consumers

1. **TronAgent** - Holds ContextManager, exposes via `getContextManager()`
2. **TurnRunner** - Uses for messages, system prompt, adding messages
3. **ContextOps** - Orchestrator wrapper delegating to agent's ContextManager
4. **AgentEventHandler** - Syncs API tokens after turn
5. **SessionManager** - Syncs API tokens on resume
6. **RPC Adapters** - Access via orchestrator.context.*

### Access Pattern
```
TronAgent
  └── contextManager: ContextManager
        ├── messages: MessageStore (new)
        ├── tokens: TokenTracker (new)
        ├── compaction: CompactionEngine (new)
        └── (coordinator methods remain)
```

---

## Design Principles

1. **Incremental Extraction** - Extract one component at a time, verify tests pass
2. **Preserve External API** - ContextManager public methods unchanged initially
3. **Internal Delegation** - Methods delegate to extracted components
4. **Test-Driven** - Write component tests before extraction
5. **Zero Regressions** - All 3366+ tests must pass after each phase

---

## Target Architecture

```
context/
├── context-manager.ts          # Coordinator (~200 lines, down from 933)
├── message-store.ts            # Message CRUD + token cache
├── compaction-engine.ts        # Compaction preview/execute
├── token-tracker.ts            # Token estimation (exists, extend)
├── context-snapshot.ts         # Snapshot generation
└── types.ts                    # Shared types (extract from context-manager.ts)
```

### Component Responsibilities

| Component | Responsibility | Methods |
|-----------|---------------|---------|
| **MessageStore** | Message CRUD, token caching | add, set, get, clear, getTokens |
| **CompactionEngine** | Compaction logic | shouldCompact, preview, execute |
| **ContextSnapshot** | Snapshot generation | getSnapshot, getDetailedSnapshot |
| **TokenTracker** | Token estimation | estimateMessage, estimateTools, estimateSystemPrompt |
| **ContextManager** | Coordination | constructor, switchModel, config getters, turn validation |

---

## Implementation Phases

### Phase 1: Extract Types to Dedicated File

**Goal:** Move all types out of context-manager.ts to reduce file size and improve reusability.

**Step 1.1: Create types file**
```typescript
// context/types.ts
export type ThresholdLevel = 'normal' | 'warning' | 'alert' | 'critical' | 'exceeded';

export interface ContextManagerConfig { ... }
export interface RulesFileSnapshot { ... }
export interface RulesSnapshot { ... }
export interface ContextSnapshot { ... }
export interface DetailedMessageInfo { ... }
export interface DetailedContextSnapshot { ... }
export interface PreTurnValidation { ... }
export interface CompactionPreview { ... }
export interface CompactionResult { ... }
export interface ProcessedToolResult { ... }
export interface ExportedState { ... }
```

**Step 1.2: Update context-manager.ts imports**

**Step 1.3: Update context/index.ts exports**

**Step 1.4: Verify**
```bash
bun run build && bun run test
```

**Lines reduced:** ~130 (types moved out)

---

### Phase 2: Extract MessageStore

**Goal:** Extract message storage and token caching into dedicated component.

**Step 2.1: Write tests first**

Create `context/__tests__/message-store.test.ts`:
- Test add message updates cache
- Test set messages rebuilds cache
- Test get messages returns copy
- Test clear messages resets state
- Test getTokens returns cached sum

**Step 2.2: Create MessageStore**

```typescript
// context/message-store.ts
import type { Message } from '../types/index.js';
import { estimateMessageTokens } from './token-estimator.js';

export interface MessageStoreConfig {
  initialMessages?: Message[];
}

export class MessageStore {
  private messages: Message[] = [];
  private tokenCache: WeakMap<Message, number> = new WeakMap();

  constructor(config?: MessageStoreConfig) {
    if (config?.initialMessages) {
      this.setMessages(config.initialMessages);
    }
  }

  add(message: Message): void {
    this.messages.push(message);
    this.tokenCache.set(message, estimateMessageTokens(message));
  }

  set(messages: Message[]): void {
    this.messages = [...messages];
    for (const msg of this.messages) {
      this.tokenCache.set(msg, estimateMessageTokens(msg));
    }
  }

  get(): Message[] {
    return [...this.messages];
  }

  clear(): void {
    this.messages = [];
  }

  getTokens(): number {
    let total = 0;
    for (const msg of this.messages) {
      total += this.tokenCache.get(msg) ?? estimateMessageTokens(msg);
    }
    return total;
  }

  getCachedTokens(message: Message): number | undefined {
    return this.tokenCache.get(message);
  }

  get length(): number {
    return this.messages.length;
  }
}

export function createMessageStore(config?: MessageStoreConfig): MessageStore {
  return new MessageStore(config);
}
```

**Step 2.3: Update ContextManager to use MessageStore**

```typescript
// In ContextManager
private messageStore: MessageStore;

constructor(config: ContextManagerConfig) {
  this.messageStore = new MessageStore();
  // ... rest of constructor
}

addMessage(message: Message): void {
  this.messageStore.add(message);
}

setMessages(messages: Message[]): void {
  this.messageStore.set(messages);
  this.lastApiContextTokens = 0;
}

getMessages(): Message[] {
  return this.messageStore.get();
}

clearMessages(): void {
  this.messageStore.clear();
  this.lastApiContextTokens = 0;
}
```

**Step 2.4: Verify**
```bash
bun run build && bun run test
```

**Lines reduced:** ~60 (message logic moved)

---

### Phase 3: Extract CompactionEngine

**Goal:** Extract compaction logic into dedicated component.

**Step 3.1: Write tests first**

Create `context/__tests__/compaction-engine.test.ts`:
- Test shouldCompact returns true at threshold
- Test shouldCompact returns false below threshold
- Test previewCompaction generates summary
- Test previewCompaction preserves recent turns
- Test executeCompaction updates messages
- Test executeCompaction uses edited summary when provided

**Step 3.2: Create CompactionEngine**

```typescript
// context/compaction-engine.ts
import type { Message } from '../types/index.js';
import type { Summarizer, ExtractedData } from './summarizer.js';
import type { CompactionPreview, CompactionResult } from './types.js';

export interface CompactionEngineConfig {
  threshold: number;
  preserveRecentTurns: number;
}

export interface CompactionDeps {
  getMessages: () => Message[];
  setMessages: (messages: Message[]) => void;
  getCurrentTokens: () => number;
  getContextLimit: () => number;
  estimateSystemPromptTokens: () => number;
  estimateToolsTokens: () => number;
  getMessageTokens: (msg: Message) => number;
}

export class CompactionEngine {
  private config: CompactionEngineConfig;
  private deps: CompactionDeps;
  private onNeededCallback?: () => void;

  constructor(config: CompactionEngineConfig, deps: CompactionDeps) {
    this.config = config;
    this.deps = deps;
  }

  shouldCompact(): boolean {
    const ratio = this.deps.getCurrentTokens() / this.deps.getContextLimit();
    return ratio >= this.config.threshold;
  }

  async preview(summarizer: Summarizer): Promise<CompactionPreview> {
    // ... move logic from ContextManager.previewCompaction
  }

  async execute(opts: {
    summarizer: Summarizer;
    editedSummary?: string;
  }): Promise<CompactionResult> {
    // ... move logic from ContextManager.executeCompaction
  }

  onNeeded(callback: () => void): void {
    this.onNeededCallback = callback;
  }

  triggerIfNeeded(): void {
    if (this.shouldCompact() && this.onNeededCallback) {
      this.onNeededCallback();
    }
  }
}

export function createCompactionEngine(
  config: CompactionEngineConfig,
  deps: CompactionDeps
): CompactionEngine {
  return new CompactionEngine(config, deps);
}
```

**Step 3.3: Update ContextManager to use CompactionEngine**

```typescript
// In ContextManager
private compactionEngine: CompactionEngine;

constructor(config: ContextManagerConfig) {
  // After messageStore is created
  this.compactionEngine = new CompactionEngine(
    {
      threshold: config.compaction?.threshold ?? 0.70,
      preserveRecentTurns: config.compaction?.preserveRecentTurns ?? 3,
    },
    {
      getMessages: () => this.messageStore.get(),
      setMessages: (msgs) => this.setMessages(msgs),
      getCurrentTokens: () => this.getCurrentTokens(),
      getContextLimit: () => this.contextLimit,
      estimateSystemPromptTokens: () => this.estimateSystemPromptTokens(),
      estimateToolsTokens: () => this.estimateToolsTokens(),
      getMessageTokens: (msg) => this.messageStore.getCachedTokens(msg) ?? estimateMessageTokens(msg),
    }
  );
}

shouldCompact(): boolean {
  return this.compactionEngine.shouldCompact();
}

async previewCompaction(opts: { summarizer: Summarizer }): Promise<CompactionPreview> {
  return this.compactionEngine.preview(opts.summarizer);
}

async executeCompaction(opts: { summarizer: Summarizer; editedSummary?: string }): Promise<CompactionResult> {
  return this.compactionEngine.execute(opts);
}

onCompactionNeeded(callback: () => void): void {
  this.compactionEngine.onNeeded(callback);
}
```

**Step 3.4: Verify**
```bash
bun run build && bun run test
```

**Lines reduced:** ~180 (compaction logic moved)

---

### Phase 4: Extract ContextSnapshot

**Goal:** Extract snapshot generation into dedicated component.

**Step 4.1: Write tests first**

Create `context/__tests__/context-snapshot.test.ts`:
- Test getSnapshot returns correct structure
- Test getSnapshot calculates usage percent
- Test getSnapshot determines threshold level
- Test getDetailedSnapshot includes message details
- Test getDetailedSnapshot handles tool calls
- Test getDetailedSnapshot handles tool results

**Step 4.2: Create ContextSnapshot**

```typescript
// context/context-snapshot.ts
import type { Message } from '../types/index.js';
import type { ContextSnapshot, DetailedContextSnapshot, ThresholdLevel } from './types.js';

const THRESHOLDS = {
  warning: 0.50,
  alert: 0.70,
  critical: 0.85,
  exceeded: 0.95,
};

export interface SnapshotDeps {
  getCurrentTokens: () => number;
  getContextLimit: () => number;
  getMessages: () => Message[];
  estimateSystemPromptTokens: () => number;
  estimateToolsTokens: () => number;
  estimateRulesTokens: () => number;
  getMessagesTokens: () => number;
  getMessageTokens: (msg: Message) => number;
  getSystemPrompt: () => string;
  getToolClarificationMessage: () => string | null;
  getTools: () => Array<{ name: string; description?: string }>;
}

export class ContextSnapshotBuilder {
  constructor(private deps: SnapshotDeps) {}

  getThresholdLevel(tokens: number): ThresholdLevel {
    const ratio = tokens / this.deps.getContextLimit();
    if (ratio >= THRESHOLDS.exceeded) return 'exceeded';
    if (ratio >= THRESHOLDS.critical) return 'critical';
    if (ratio >= THRESHOLDS.alert) return 'alert';
    if (ratio >= THRESHOLDS.warning) return 'warning';
    return 'normal';
  }

  build(): ContextSnapshot {
    const currentTokens = this.deps.getCurrentTokens();
    const contextLimit = this.deps.getContextLimit();
    // ... rest of getSnapshot logic
  }

  buildDetailed(): DetailedContextSnapshot {
    // ... rest of getDetailedSnapshot logic
  }
}
```

**Step 4.3: Update ContextManager to use ContextSnapshotBuilder**

**Step 4.4: Verify**
```bash
bun run build && bun run test
```

**Lines reduced:** ~100 (snapshot logic moved)

---

### Phase 5: Consolidate Token Estimation

**Goal:** Move remaining token estimation logic to TokenEstimator and use consistently.

The `token-estimator.ts` already exists with:
- `estimateMessageTokens()`
- `estimateRulesTokens()`
- `CHARS_PER_TOKEN`

**Step 5.1: Extend TokenEstimator**

Add to `token-estimator.ts`:
```typescript
export function estimateSystemPromptTokens(
  systemPrompt: string,
  toolClarification?: string | null
): number {
  const totalLength = systemPrompt.length + (toolClarification?.length ?? 0);
  return Math.ceil(totalLength / CHARS_PER_TOKEN);
}

export function estimateToolsTokens(tools: Tool[]): number {
  return Math.ceil(
    tools.reduce((sum, t) => sum + JSON.stringify(t).length / CHARS_PER_TOKEN, 0)
  );
}
```

**Step 5.2: Remove duplicate estimation from ContextManager**

**Step 5.3: Verify**
```bash
bun run build && bun run test
```

**Lines reduced:** ~30 (estimation consolidated)

---

### Phase 6: Final Cleanup

**Step 6.1: Verify final ContextManager structure**

The ContextManager should now be ~200 lines with:
```typescript
class ContextManager {
  // Dependencies
  private messageStore: MessageStore;
  private compactionEngine: CompactionEngine;
  private snapshotBuilder: ContextSnapshotBuilder;

  // Configuration
  private model: string;
  private providerType: ProviderType;
  private contextLimit: number;
  private workingDirectory: string;
  private tools: Tool[];
  private rulesContent: string | undefined;
  private customSystemPrompt: string | undefined;
  private lastApiContextTokens: number = 0;

  // Lifecycle
  constructor(config: ContextManagerConfig)

  // Message delegation
  addMessage(message: Message): void
  setMessages(messages: Message[]): void
  getMessages(): Message[]
  clearMessages(): void

  // System prompt (kept inline - simple delegation to system-prompts.ts)
  getSystemPrompt(): string
  getRawSystemPrompt(): string
  getToolClarificationMessage(): string | null
  requiresToolClarification(): boolean

  // Token tracking (kept inline - trivial)
  getCurrentTokens(): number
  getContextLimit(): number
  setApiContextTokens(tokens: number): void
  getApiContextTokens(): number

  // Model config (kept inline - trivial)
  getModel(): string
  getProviderType(): ProviderType
  getWorkingDirectory(): string
  setWorkingDirectory(dir: string): void
  getTools(): Tool[]
  setRulesContent(content: string | undefined): void
  getRulesContent(): string | undefined
  switchModel(newModel: string): void

  // Compaction delegation
  shouldCompact(): boolean
  previewCompaction(opts): Promise<CompactionPreview>
  executeCompaction(opts): Promise<CompactionResult>
  onCompactionNeeded(callback: () => void): void

  // Snapshot delegation
  getSnapshot(): ContextSnapshot
  getDetailedSnapshot(): DetailedContextSnapshot

  // Turn validation (kept inline - trivial)
  canAcceptTurn(opts): PreTurnValidation
  getThresholdLevel(tokens: number): ThresholdLevel

  // Tool result (kept inline - trivial)
  processToolResult(result): ProcessedToolResult
  getMaxToolResultSize(): number

  // Serialization (kept inline - trivial)
  exportState(): ExportedState
}
```

**Step 6.2: Update exports**

```typescript
// context/index.ts
export * from './types.js';
export { ContextManager, createContextManager } from './context-manager.js';
export { MessageStore, createMessageStore } from './message-store.js';
export { CompactionEngine, createCompactionEngine } from './compaction-engine.js';
export { ContextSnapshotBuilder } from './context-snapshot.js';
export * from './token-estimator.js';
```

**Step 6.3: Final verification**
```bash
bun run build && bun run test
```

---

## Files to Create

| File | Purpose | Est. Lines |
|------|---------|------------|
| `context/types.ts` | Shared types | ~130 |
| `context/message-store.ts` | Message CRUD + token cache | ~80 |
| `context/compaction-engine.ts` | Compaction logic | ~200 |
| `context/context-snapshot.ts` | Snapshot generation | ~150 |
| `context/__tests__/message-store.test.ts` | Tests | ~100 |
| `context/__tests__/compaction-engine.test.ts` | Tests | ~150 |
| `context/__tests__/context-snapshot.test.ts` | Tests | ~120 |

## Files to Modify

| File | Change |
|------|--------|
| `context/context-manager.ts` | Reduce from 933 to ~200 lines via delegation |
| `context/token-estimator.ts` | Add system prompt and tools estimation |
| `context/index.ts` | Export new components |

---

## Consumer Migration

### No External Changes Required

The ContextManager public API remains unchanged. All extraction is internal:

```typescript
// BEFORE (internal)
class ContextManager {
  private messages: Message[] = [];
  addMessage(msg) { this.messages.push(msg); }
}

// AFTER (internal delegation)
class ContextManager {
  private messageStore: MessageStore;
  addMessage(msg) { this.messageStore.add(msg); }
}

// External usage unchanged
contextManager.addMessage(msg);
```

---

## Verification Strategy

### After Each Phase
```bash
bun run build && bun run test
```

### Verify Line Count Reduction
```bash
wc -l packages/agent/src/context/context-manager.ts
# Target: ~200 lines (down from 933)
```

### Verify No API Changes
```bash
# Find all ContextManager method calls - should all still work
grep -rn "contextManager\." packages/agent/src --include="*.ts" | head -20
```

---

## Success Criteria

- [ ] Phase 1: Types extracted, all tests pass
- [ ] Phase 2: MessageStore extracted, all tests pass
- [ ] Phase 3: CompactionEngine extracted, all tests pass
- [ ] Phase 4: ContextSnapshot extracted, all tests pass
- [ ] Phase 5: Token estimation consolidated, all tests pass
- [ ] Phase 6: Final cleanup, all tests pass

**Final Verification:**
- [ ] ContextManager reduced from 933 to ~200 lines
- [ ] All 3366+ tests pass
- [ ] No external API changes
- [ ] Each extracted component has dedicated tests
- [ ] Build succeeds with zero errors

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Breaking external API | Keep all public methods, delegate internally |
| Token calculation drift | Tests verify token calculations match before/after |
| Compaction bugs | Extensive tests for preview/execute edge cases |
| Circular dependencies | Components receive callbacks, not manager reference |

---

## Estimated Outcome

### Before
```
context-manager.ts: 933 lines, 32 public methods, 6+ concerns
```

### After
```
context-manager.ts: ~200 lines (coordinator)
types.ts: ~130 lines
message-store.ts: ~80 lines
compaction-engine.ts: ~200 lines
context-snapshot.ts: ~150 lines
token-estimator.ts: ~100 lines (extended)
```

**Net result:** Same total lines, but clean separation of concerns with testable, focused components.
