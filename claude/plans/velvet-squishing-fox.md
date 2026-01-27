# Tool System Analysis & Improvement Plan

## Current Architecture Overview

### Tool Definition & Management
- **Location**: `packages/core/src/tools/` (21 tools)
- **Interface**: `TronTool<TParams, TDetails>` with `name`, `description`, `parameters`, `execute()`
- **Registry**: Tools instantiated per-session via `AgentFactory.createAgentForSession()`
- **Lookup**: `Map<string, TronTool>` for O(1) access
- **Execution Pipeline**: TronAgent → TurnRunner → ToolExecutor → Tool.execute()

### Tool Access Control Mechanisms

#### 1. Plan Mode Blocking
- **Handler**: `packages/server/src/orchestrator/handlers/plan-mode.ts`
- **Default blocked**: `['Write', 'Edit', 'Bash', 'NotebookEdit']`
- **Enforcement**: Guardrail rule `SESSION_PLAN_MODE` in `packages/core/src/guardrails/builtin/default-rules.ts`
- **Customization**: Skills can specify allowed tools via frontmatter

#### 2. Subagent Nesting Prevention
- **Location**: `packages/server/src/orchestrator/agent-factory.ts` (lines 131-231)
- **Mechanism**: `isSubagent` flag excludes `SpawnSubagentTool`, `QuerySubagentTool`, `WaitForSubagentTool`

### Key Files
| Component | File |
|-----------|------|
| Tool Interface | `packages/core/src/types/tools.ts` |
| Tool Implementations | `packages/core/src/tools/*.ts` |
| Agent Factory | `packages/server/src/orchestrator/agent-factory.ts` |
| Tool Executor | `packages/core/src/agent/tool-executor.ts` |
| Plan Mode Handler | `packages/server/src/orchestrator/handlers/plan-mode.ts` |
| Guardrail Rules | `packages/core/src/guardrails/builtin/default-rules.ts` |
| Subagent Spawn | `packages/core/src/tools/spawn-subagent.ts` |
| Subagent Ops | `packages/server/src/orchestrator/subagent-ops.ts` |

---

## Critical Findings: Gaps & Issues

### 🔴 Issue 1: Subagent Tool Restrictions Not Enforced

**The Problem**: The `SpawnSubagentTool` accepts a `tools` parameter that lists which tools the subagent should have access to, but this is **never enforced**.

**Evidence from code:**

```typescript
// spawn-subagent.ts (line 136-139) - Parameter is defined
tools: {
  type: 'array',
  items: { type: 'string' },
  description: 'Specific tools to enable for the sub-agent...'
}

// subagent-ops.ts (lines 168-169) - Recorded in events but not used
{
  tools: params.tools,  // ← Stored in event for audit
  skills: params.skills,
  ...
}

// agent-factory.ts (line 138-143) - No tools parameter!
async createAgentForSession(
  sessionId: SessionId,
  workingDirectory: string,
  model: string,
  systemPrompt?: string,
  isSubagent?: boolean  // ← Only controls spawn tool exclusion
): Promise<TronAgent>
```

**Impact**: Parent agents cannot spawn restricted subagents. The `tools` param is dead code.

### 🔴 Issue 2: No Bash Command Allowlisting

**The Problem**: No mechanism to restrict what bash commands a subagent can execute.

**Current behavior**: `BashTool` executes ANY command. Plan mode blocks Bash entirely (all or nothing).

**Missing capability**:
```typescript
// Not implemented - but would be useful
SpawnSubagent({
  task: "Run tests",
  tools: ['Read', 'Bash'],
  bashAllowedCommands: ['npm test', 'npm run build']  // ← Doesn't exist
})
```

### 🟡 Issue 3: Disconnect Between Parameters and Implementation

**The data flow is broken:**

```
SpawnSubagentTool.execute()
  → params.tools passed to onSpawn callback
    → SubagentOps.spawnSubsession()
      → tools recorded in 'subagent.spawned' event  ✓ (audit only)
      → createSession() called WITHOUT tools param  ✗
        → AgentFactory.createAgentForSession()
          → Full tool set instantiated regardless    ✗
```

### 🟡 Issue 4: Skills Parameter Similarly Broken

The `skills` parameter has the same issue - it's recorded but not loaded for subagents.

### 🟢 What Works Well

1. **Tool interface is clean** - `TronTool` interface is simple and consistent
2. **Guardrail system is extensible** - Rules can be added for custom restrictions
3. **Event sourcing** - Tool calls/results properly persisted for session resume
4. **Plan mode blocking** - Works correctly for session-level blocking
5. **Subagent nesting prevention** - `isSubagent` flag works correctly

---

## Robustness Assessment

| Aspect | Rating | Notes |
|--------|--------|-------|
| Tool definition pattern | ✅ Good | Clean interface, consistent implementation |
| Tool registration | ✅ Good | Per-session instantiation, proper isolation |
| Plan mode restrictions | ✅ Good | Guardrail-based, event-persisted |
| Subagent tool restrictions | ❌ Broken | Parameter exists but not enforced |
| Bash command restrictions | ❌ Missing | No mechanism exists |
| Skills for subagents | ❌ Broken | Parameter exists but not loaded |
| Session resume | ✅ Good | Plan mode state reconstructs correctly |

---

## Improvement Options

### Option A: Minimal Fix - Wire Up Existing Parameters

**Scope**: Make `tools` and `skills` parameters actually work

**Changes**:
1. Add `allowedTools?: string[]` param to `AgentFactory.createAgentForSession()`
2. Filter tool instantiation based on allowlist
3. Pass `params.tools` through the spawn chain
4. Similarly wire up `skills` loading

**Pros**: Low effort, fixes the immediate broken functionality
**Cons**: No bash command filtering, no argument-level restrictions

### Option B: Tool Policy System

**Scope**: Comprehensive tool access control

**Features**:
- Tool allowlist/blocklist per subagent
- Bash command pattern matching (glob patterns)
- Tool argument validation rules
- Configurable via spawn params or guardrails

**Changes**:
1. New `ToolPolicy` type and `ToolPolicyEngine`
2. Extend `SpawnSubagentParams` with policy options
3. Integrate with guardrail system for enforcement
4. Add bash command filtering to `BashTool`

**Pros**: Full control over subagent capabilities
**Cons**: More complex, requires careful design

### Option C: Hybrid Approach

**Phase 1**: Wire up existing `tools` parameter (Option A)
**Phase 2**: Add bash command filtering as separate enhancement
**Phase 3**: Consider full policy system if needed

---

## Implementation Plan: Tool Policy System

### Overview

Create a comprehensive **ToolPolicy** system that enables:
1. Tool allowlist/blocklist per subagent
2. Bash command pattern matching (glob patterns)
3. Integration with existing guardrail system
4. Event persistence for session resume

### New Types

```typescript
// packages/core/src/tools/policy/types.ts

export type ToolPolicyMode = 'allowlist' | 'blocklist';

export interface BashCommandFilter {
  allow?: string[];      // Glob patterns for allowed commands
  block?: string[];      // Glob patterns for blocked commands
  blockInteractive?: boolean;  // Block vim, less, etc. (default: true)
  maxTimeoutMs?: number;
}

export interface ToolPolicy {
  mode: ToolPolicyMode;
  tools: string[];
  bash?: BashCommandFilter;
  inheritGuardrails?: boolean;  // Default: true
}
```

### API Example

```typescript
// Parent spawns a read-only research subagent
SpawnSubagent({
  task: "Research the codebase structure",
  toolPolicy: {
    mode: "allowlist",
    tools: ["Read", "Grep", "Find", "Ls", "Bash"],
    bash: {
      allow: ["ls *", "cat *", "head *", "tail *", "wc *", "git log *", "git status"],
      block: ["rm *", "mv *", "echo * > *"],
      blockInteractive: true
    }
  }
})

// Parent spawns a testing subagent
SpawnSubagent({
  task: "Run the test suite",
  toolPolicy: {
    mode: "allowlist",
    tools: ["Read", "Bash"],
    bash: {
      allow: ["npm test", "npm run test*", "bun test", "jest *", "vitest *"]
    }
  }
})
```

---

## Files to Create

| File | Purpose |
|------|---------|
| `packages/core/src/tools/policy/types.ts` | Type definitions for ToolPolicy |
| `packages/core/src/tools/policy/resolver.ts` | Validate and resolve policies |
| `packages/core/src/tools/policy/enforcer.ts` | Runtime enforcement |
| `packages/core/src/tools/policy/wrapped-bash.ts` | Policy-wrapped BashTool |
| `packages/core/src/tools/policy/index.ts` | Module exports |

## Files to Modify

| File | Changes |
|------|---------|
| `packages/core/src/tools/spawn-subagent.ts` | Add `toolPolicy` param to schema |
| `packages/core/src/events/types.ts` | Add `SerializedToolPolicy` to spawn event |
| `packages/server/src/orchestrator/agent-factory.ts` | Add `createAgentForSubagent()` with policy |
| `packages/server/src/orchestrator/subagent-ops.ts` | Resolve policy, pass to agent creation |
| `packages/server/src/orchestrator/types.ts` | Add `toolPolicy` to `CreateSessionOptions` |

---

## Implementation Phases

### Phase 1: Core Types and Resolver
1. Create `policy/types.ts` - ToolPolicy, BashCommandFilter, ResolvedToolPolicy
2. Create `policy/resolver.ts` - Validate policies, compile glob patterns to regex
3. Add restricted tools list (SpawnSubagent, QuerySubagent, etc. always blocked)
4. Unit tests

### Phase 2: Enforcer and Wrapped Bash
1. Create `policy/enforcer.ts` - `isToolAllowed()`, `isBashCommandAllowed()`
2. Create `policy/wrapped-bash.ts` - Wraps BashTool with command filtering
3. Generate guardrail rules from policies
4. Integration tests

### Phase 3: Event Schema
1. Update `events/types.ts` - Add `toolPolicy` to SubagentSpawnedEvent
2. Handle backwards compatibility (legacy `tools` field still works)

### Phase 4: AgentFactory Integration
1. Add `createAgentForSubagent(sessionId, workDir, model, toolPolicy)`
2. Filter tool instantiation based on `resolvedPolicy.enabledTools`
3. Wrap BashTool with PolicyWrappedBashTool if bash filtering configured

### Phase 5: Spawn Integration
1. Update `spawn-subagent.ts` - Add `toolPolicy` to parameters schema
2. Update `subagent-ops.ts` - Resolve policy at spawn time, persist in events
3. Keep `tools` param for backwards compatibility (converts to allowlist policy)

### Phase 6: Testing & Documentation
1. End-to-end tests for policy enforcement
2. Test bash command filtering with various patterns
3. Test session resume with policy reconstruction

---

## Backwards Compatibility

1. **Legacy `tools` parameter**: Converted to `{ mode: 'allowlist', tools: [...] }`
2. **Events without toolPolicy**: Fall back to `tools` field or default policy
3. **Default policy**: All tools enabled (minus restricted) if no policy specified

## Security Defaults

1. **Always restricted**: SpawnSubagent, QuerySubagent, WaitForSubagent, NotifyApp
2. **Interactive commands blocked by default**: vim, nano, less, man, top, python REPL
3. **Guardrails inherited by default**: Child gets parent's guardrails
4. **Dangerous patterns inherited**: rm -rf, sudo, etc.

---

## Verification Plan

1. **Unit tests**: Policy resolver, enforcer, glob-to-regex conversion
2. **Integration tests**:
   - Spawn subagent with allowlist → verify only those tools available
   - Spawn subagent with bash filter → verify commands blocked/allowed
   - Resume session → verify policy reconstructs from events
3. **Manual testing**:
   - Spawn read-only subagent, verify it cannot write files
   - Spawn testing subagent, verify it can only run test commands
