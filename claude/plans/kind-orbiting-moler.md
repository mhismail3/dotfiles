# Consolidated Guardrail System Design

## Overview

Create a unified guardrail system in `packages/core/src/guardrails/` that consolidates all safety mechanisms currently scattered across the codebase.

## ~/.tron Folder Structure (as of commit c9b7bc7)

```
~/.tron/
├── db/           # Database files (prod.db, beta.db)
├── rules/        # Global markdown rules (SYSTEM.md, claude.md, AGENTS.md)
├── mods/         # Extensions (transcribe/)
├── app/          # Deployed server
├── notes/        # Voice notes
├── skills/       # Global skills
├── auth.json     # OAuth tokens
└── settings.json # JSON configuration (guardrails go here)
```

**Key distinction**:
- `rules/` = Markdown files for prompts/instructions
- `settings.json` = Structured JSON config (where guardrails belong)

## Current State (to consolidate)

| Location | What it does |
|----------|--------------|
| `settings/defaults.ts` | Dangerous bash patterns in `tools.bash.dangerousPatterns` |
| `tools/bash.ts` | `checkDangerous()` method |
| `agent/tool-executor.ts` | PreToolUse hook blocking |
| `orchestrator/handlers/plan-mode.ts` | Plan mode tool restrictions |
| `rpc/handlers/filesystem.handler.ts` | Path traversal, hidden file blocking |

## Proposed Architecture

```
packages/core/src/guardrails/
├── index.ts              # Public exports
├── types.ts              # Core type definitions
├── engine.ts             # Rule evaluation engine
├── registry.ts           # Rule registration
├── rules/
│   ├── bash-patterns.ts  # Dangerous command patterns
│   ├── path-safety.ts    # Filesystem path rules
│   ├── resource-limits.ts # Timeout/size limits
│   └── session-context.ts # Plan mode, etc.
├── builtin/
│   └── default-rules.ts  # Default rule configuration
└── audit/
    └── audit-logger.ts   # Structured audit logging
```

## Core Types

```typescript
type GuardrailSeverity = 'block' | 'warn' | 'audit';
type GuardrailScope = 'global' | 'tool' | 'session' | 'directory';
type GuardrailTier = 'core' | 'standard' | 'custom';

interface GuardrailRule {
  id: string;
  name: string;
  description: string;
  severity: GuardrailSeverity;
  scope: GuardrailScope;
  tier: GuardrailTier;   // Core rules cannot be disabled
  tools?: string[];      // Empty = all tools
  priority?: number;     // Higher = evaluated first
  enabled: boolean;      // Ignored for core tier
  tags?: string[];
}

// Rule types
type PatternRule     // Regex matching (bash commands)
type PathRule        // Filesystem safety (traversal, hidden)
type ResourceRule    // Limits (timeout, size)
type ContextRule     // Session state (plan mode)
type CompositeRule   // AND/OR/NOT combinations
```

## Key Features

1. **Single source of truth** - All rules in one module
2. **Configurable** - JSON config files for customization
3. **Extensible** - Multiple rule types with custom evaluators
4. **Auditable** - Structured logging of all guardrail decisions
5. **Composable** - Rules can be combined with AND/OR/NOT
6. **Context-aware** - Rules can check session state
7. **Tiered immutability** - Core rules cannot be disabled

## Rule Tiers

| Tier | Can Disable? | Override Location | Examples |
|------|--------------|-------------------|----------|
| **Core** | No | Manual edit of source only | rm -rf /, fork bombs, ~/.tron/ protection |
| **Standard** | Yes | `~/.tron/settings.json` | sudo blocking, path traversal |
| **Custom** | Yes | Project `.tron/settings.json` | Project-specific rules |

**Protected paths**: The entire `~/.tron/` directory tree is core-protected - the agent cannot write, edit, or delete any files there (`db/`, `rules/`, `mods/`, `settings.json`, etc.). Users must manually edit these files.

## Default Rules (migrated)

| Rule ID | Tier | Type | Severity | What it blocks |
|---------|------|------|----------|----------------|
| `core.destructive-commands` | **Core** | pattern | block | rm -rf /, fork bombs, dd to devices |
| `core.tron-folder-protection` | **Core** | path | block | Write/Edit/Delete to entire ~/.tron/ tree |
| `bash.sudo` | Standard | pattern | block | sudo commands |
| `bash.mkfs` | Standard | pattern | block | Filesystem formatting |
| `path.traversal` | Standard | path | block | `..` in file paths |
| `path.hidden` | Standard | path | block | Hidden dirs in mkdir |
| `bash.timeout` | Standard | resource | block | Timeout > 10 minutes |
| `session.plan-mode` | Standard | context | block | Write/Edit/Bash during planning |

### Core Rules (immutable)

These cannot be disabled via config - only by editing source code:

```typescript
const CORE_RULES = [
  'core.destructive-commands',     // rm -rf /, fork bombs, dd to /dev/*
  'core.tron-folder-protection',   // Protects entire ~/.tron/ tree from agent writes
];
```

The `core.tron-folder-protection` rule blocks:
- Write/Edit tools targeting any file under `~/.tron/`
- Bash commands that would write to `~/.tron/` (e.g., `echo > ~/.tron/settings.json`)
- Covers: `db/`, `rules/`, `mods/`, `app/`, `notes/`, `skills/`, `auth.json`, `settings.json`

## Integration Point

```typescript
// In tool-executor.ts execute() method
if (this.guardrailEngine) {
  const evaluation = await this.guardrailEngine.evaluate({
    toolName: request.toolName,
    toolArguments: request.arguments,
    sessionState: this.getSessionState(),
    // ...
  });

  if (evaluation.blocked) {
    return { isError: true, content: evaluation.blockReason };
  }
}
// Then continue with existing hooks and tool execution
```

## User Configuration

Guardrails integrate into the existing `~/.tron/settings.json` structure (agent cannot modify this file):

```typescript
// In settings/types.ts - add to TronSettings interface
export interface GuardrailSettings {
  /** Override standard rules (by ID) */
  rules?: {
    [ruleId: string]: { enabled?: boolean; [key: string]: unknown };
  };
  /** Additional custom rules */
  customRules?: CustomGuardrailRule[];
  /** Audit logging options */
  audit?: {
    enabled?: boolean;
    maxEntries?: number;
  };
}

export interface TronSettings {
  // ... existing fields
  guardrails?: GuardrailSettings;  // NEW
}
```

Example `~/.tron/settings.json`:
```json
{
  "guardrails": {
    "rules": {
      "bash.sudo": { "enabled": false },
      "bash.timeout": { "maxValue": 300000 }
    },
    "customRules": [{
      "id": "my.docker-warning",
      "type": "pattern",
      "tier": "custom",
      "severity": "warn",
      "tools": ["Bash"],
      "targetArgument": "command",
      "patterns": ["docker.*--privileged"]
    }]
  }
}
```

**Note**: Core rules cannot be disabled via settings - attempts are silently ignored.

**Deprecation**: `tools.bash.dangerousPatterns` will be deprecated in favor of `guardrails.rules['bash.dangerous-commands'].patterns`.

## Implementation Phases

### Phase 1: Create guardrail module
- [ ] Add `GuardrailSettings` interface to `settings/types.ts`
- [ ] Add default guardrail settings to `settings/defaults.ts`
- [ ] Create `guardrails/types.ts` with rule type definitions
- [ ] Create `guardrails/engine.ts` with `GuardrailEngine` class
- [ ] Create `guardrails/builtin/default-rules.ts` with migrated rules
- [ ] Create `guardrails/audit/audit-logger.ts`
- [ ] Export from `guardrails/index.ts`

### Phase 2: Integrate with tool executor
- [ ] Add optional `guardrailEngine` to `ToolExecutorDependencies`
- [ ] Add evaluation as first step in `execute()` (before hooks)
- [ ] Keep existing checks as fallbacks

### Phase 3: Migrate existing rules
- [ ] Move `DEFAULT_DANGEROUS_PATTERNS` from settings to guardrail rules
- [ ] Move path validation from filesystem handler to guardrail rules
- [ ] Add plan mode as context rule

### Phase 4: Configuration loading
- [ ] Update guardrail engine to read from `getSettings().guardrails`
- [ ] Apply user rule overrides from settings
- [ ] Register user custom rules from settings

### Phase 5: Deprecate legacy code
- [ ] Remove `checkDangerous()` from BashTool
- [ ] Remove inline path validation from filesystem handler
- [ ] Update plan mode handler to delegate to guardrails

## Files to Modify

- `packages/core/src/settings/types.ts` - Add `GuardrailSettings` interface and extend `TronSettings`
- `packages/core/src/settings/defaults.ts` - Add default guardrail settings
- `packages/core/src/agent/tool-executor.ts` - Add guardrail engine integration
- `packages/core/src/tools/bash.ts` - Eventually remove checkDangerous (Phase 5)
- `packages/core/src/rpc/handlers/filesystem.handler.ts` - Delegate to guardrails (Phase 5)

## Files to Create

- `packages/core/src/guardrails/types.ts`
- `packages/core/src/guardrails/engine.ts`
- `packages/core/src/guardrails/index.ts`
- `packages/core/src/guardrails/builtin/default-rules.ts`
- `packages/core/src/guardrails/audit/audit-logger.ts`

## Verification

1. Unit tests for each rule type evaluation
2. Unit test: core rules cannot be disabled via config
3. Integration test: dangerous bash command gets blocked
4. Integration test: agent cannot write to ~/.tron/ directory
5. Integration test: plan mode blocks Write/Edit
6. Integration test: custom config overrides standard rules (but not core)
7. Manual test: run agent and verify audit logs capture decisions
