# BrowserService Decomposition Plan

## Status: PENDING

## Goal

Decompose `BrowserService` (745 lines) into focused handler classes following the same pattern used for `AgentEventHandler`. The coordinator will become a slim router (~150 lines) that delegates to specialized handlers.

---

## Current State

**File:** `packages/agent/src/external/browser/browser-service.ts` (745 lines)

**Problem:** Single class handling 17 different browser actions via a large switch statement in `execute()`. This violates single responsibility principle and makes the code harder to test, maintain, and extend.

**Current Structure:**
```
BrowserService (745 lines)
├── Session Management (lines 59-138)
│   ├── constructor
│   ├── createSession
│   ├── hasSession
│   ├── getSession
│   └── closeSession
│
├── Main Dispatcher (lines 140-200)
│   └── execute() - 17-case switch statement
│
├── Navigation Actions (lines 202-502)
│   ├── navigate
│   ├── goBack
│   ├── goForward
│   └── reload
│
├── Input Actions (lines 224-544)
│   ├── click
│   ├── fill
│   ├── type
│   ├── select
│   ├── hover
│   └── pressKey
│
├── Capture Actions (lines 314-611)
│   ├── screenshot
│   ├── snapshot
│   └── pdf
│
├── Query Actions (lines 546-588)
│   ├── getText
│   └── getAttribute
│
├── State Actions (lines 390-454)
│   ├── wait
│   └── scroll
│
├── Screencast (lines 613-700)
│   ├── startScreencast
│   └── stopScreencast
│
└── Utilities (lines 702-745)
    ├── getLocator
    ├── resolveSelector
    └── cleanup
```

**Existing Tests:** 40+ tests in `__tests__/browser-service.test.ts`

---

## Proposed Structure

```
external/browser/
├── browser-service.ts           # Slim coordinator (~150 lines)
├── handlers/
│   ├── navigation-handler.ts    # navigate, goBack, goForward, reload
│   ├── input-handler.ts         # click, fill, type, select, hover, pressKey
│   ├── capture-handler.ts       # screenshot, snapshot, pdf
│   ├── query-handler.ts         # getText, getAttribute
│   ├── state-handler.ts         # wait, scroll
│   ├── screencast-handler.ts    # startScreencast, stopScreencast
│   └── index.ts                 # Unified exports
├── __tests__/
│   ├── browser-service.test.ts  # Existing coordinator tests (updated)
│   └── handlers/
│       ├── navigation-handler.test.ts
│       ├── input-handler.test.ts
│       ├── capture-handler.test.ts
│       ├── query-handler.test.ts
│       ├── state-handler.test.ts
│       └── screencast-handler.test.ts
└── index.ts                     # Public exports
```

---

## Handler Design

### Shared Dependencies Interface

All handlers receive the same dependencies:

```typescript
export interface BrowserHandlerDeps {
  /** Get locator for selector or ref */
  getLocator: (session: BrowserSession, selectorOrRef: string) => Locator;
  /** Resolve selector (convert jQuery-style to Playwright) */
  resolveSelector: (session: BrowserSession, selector: string) => string;
}
```

### Handler Mapping

| Handler | Actions | Lines (est.) |
|---------|---------|--------------|
| `NavigationHandler` | navigate, goBack, goForward, reload | ~80 |
| `InputHandler` | click, fill, type, select, hover, pressKey | ~150 |
| `CaptureHandler` | screenshot, snapshot, pdf | ~120 |
| `QueryHandler` | getText, getAttribute | ~60 |
| `StateHandler` | wait, scroll | ~80 |
| `ScreencastHandler` | startScreencast, stopScreencast | ~100 |

### Handler Interface Pattern

Each handler follows this pattern:

```typescript
export interface NavigationHandlerDeps extends BrowserHandlerDeps {}

export class NavigationHandler {
  constructor(private deps: NavigationHandlerDeps) {}

  async navigate(session: BrowserSession, params: Record<string, unknown>): Promise<ActionResult> { ... }
  async goBack(session: BrowserSession): Promise<ActionResult> { ... }
  async goForward(session: BrowserSession): Promise<ActionResult> { ... }
  async reload(session: BrowserSession): Promise<ActionResult> { ... }
}

export function createNavigationHandler(deps: NavigationHandlerDeps): NavigationHandler {
  return new NavigationHandler(deps);
}
```

---

## Implementation Phases

### Phase 1: Create Handler Infrastructure

**Step 1.1: Create handlers directory**
```bash
mkdir -p packages/agent/src/external/browser/handlers
mkdir -p packages/agent/src/external/browser/handlers/__tests__
```

**Step 1.2: Create shared types file**

Create `handlers/types.ts` with shared interfaces:
- `BrowserHandlerDeps`
- Re-export `ActionResult`, `BrowserSession` from parent

**Verify:** Build passes

---

### Phase 2: Extract NavigationHandler

**Step 2.1: Create `handlers/navigation-handler.ts`**

Extract methods:
- `navigate(session, params)` → lines 205-221
- `goBack(session)` → lines 459-470
- `goForward(session)` → lines 475-486
- `reload(session)` → lines 491-502

**Step 2.2: Create `handlers/__tests__/navigation-handler.test.ts`**

Test cases:
- navigate with valid URL
- navigate without URL (error)
- goBack success
- goForward success
- reload success
- Error handling for each

**Step 2.3: Update BrowserService**

- Import `createNavigationHandler`
- Create handler in constructor
- Update `execute()` switch cases to delegate

**Verify:** `bun run build && bun run test`

---

### Phase 3: Extract InputHandler

**Step 3.1: Create `handlers/input-handler.ts`**

Extract methods:
- `click(session, params)` → lines 226-242
- `fill(session, params)` → lines 247-265
- `type(session, params)` → lines 270-288
- `select(session, params)` → lines 293-312
- `hover(session, params)` → lines 507-523
- `pressKey(session, params)` → lines 528-544

**Step 3.2: Create `handlers/__tests__/input-handler.test.ts`**

Test cases:
- click with selector
- click without selector (error)
- fill with selector and value
- fill missing params (error)
- type with selector and text
- select single value
- select multiple values
- hover with selector
- pressKey with key
- Error handling for each

**Step 3.3: Update BrowserService**

- Import `createInputHandler`
- Create handler in constructor
- Update `execute()` switch cases to delegate

**Verify:** `bun run build && bun run test`

---

### Phase 4: Extract CaptureHandler

**Step 4.1: Create `handlers/capture-handler.ts`**

Extract methods:
- `screenshot(session)` → lines 318-341
- `snapshot(session)` → lines 346-388
- `pdf(session, params)` → lines 593-611

**Step 4.2: Create `handlers/__tests__/capture-handler.test.ts`**

Test cases:
- screenshot returns base64
- screenshot uses viewport-only (fullPage: false)
- snapshot returns tree and refs
- pdf with path
- pdf without path (returns base64)
- Error handling

**Step 4.3: Update BrowserService**

- Import `createCaptureHandler`
- Create handler in constructor
- Update `execute()` switch cases to delegate

**Verify:** `bun run build && bun run test`

---

### Phase 5: Extract QueryHandler

**Step 5.1: Create `handlers/query-handler.ts`**

Extract methods:
- `getText(session, params)` → lines 549-565
- `getAttribute(session, params)` → lines 570-588

**Step 5.2: Create `handlers/__tests__/query-handler.test.ts`**

Test cases:
- getText with selector
- getText without selector (error)
- getAttribute with selector and attribute
- getAttribute missing params (error)
- Error handling

**Step 5.3: Update BrowserService**

- Import `createQueryHandler`
- Create handler in constructor
- Update `execute()` switch cases to delegate

**Verify:** `bun run build && bun run test`

---

### Phase 6: Extract StateHandler

**Step 6.1: Create `handlers/state-handler.ts`**

Extract methods:
- `wait(session, params)` → lines 393-415
- `scroll(session, params)` → lines 420-454

**Step 6.2: Create `handlers/__tests__/state-handler.test.ts`**

Test cases:
- wait for selector
- wait for timeout
- wait without params (error)
- scroll down
- scroll up
- scroll with selector
- invalid scroll direction (error)
- Error handling

**Step 6.3: Update BrowserService**

- Import `createStateHandler`
- Create handler in constructor
- Update `execute()` switch cases to delegate

**Verify:** `bun run build && bun run test`

---

### Phase 7: Extract ScreencastHandler

**Step 7.1: Create `handlers/screencast-handler.ts`**

Extract methods:
- `startScreencast(session, sessionId, options, emit)` → lines 617-674
- `stopScreencast(session)` → lines 679-700

Note: This handler needs access to `emit` for frame events.

**Step 7.2: Create `handlers/__tests__/screencast-handler.test.ts`**

Test cases:
- startScreencast success
- startScreencast restarts if already streaming
- stopScreencast success
- stopScreencast when not streaming
- Error handling

**Step 7.3: Update BrowserService**

- Import `createScreencastHandler`
- Create handler in constructor
- Update `startScreencast()` and `stopScreencast()` to delegate

**Verify:** `bun run build && bun run test`

---

### Phase 8: Create handlers/index.ts and Final Cleanup

**Step 8.1: Create `handlers/index.ts`**

Unified exports for all handlers:
```typescript
export * from './types.js';
export * from './navigation-handler.js';
export * from './input-handler.js';
export * from './capture-handler.js';
export * from './query-handler.js';
export * from './state-handler.js';
export * from './screencast-handler.js';
```

**Step 8.2: Update BrowserService imports**

Change individual imports to use `handlers/index.js`.

**Step 8.3: Update file header**

Update `browser-service.ts` docstring to reflect new role as coordinator.

**Step 8.4: Verify no dead code**

- Remove any unused private methods
- Check for unused imports
- Ensure all handlers are used

**Verify:** `bun run build && bun run test`

---

### Phase 9: Final Verification

**Step 9.1: Run full test suite**
```bash
bun run build && bun run test
```

**Step 9.2: Verify line count reduction**
```bash
wc -l packages/agent/src/external/browser/browser-service.ts
# Target: ~150 lines (down from 745)
```

**Step 9.3: Check for regressions**
- All 40+ existing tests pass
- New handler tests pass
- No TypeScript errors

**Step 9.4: Commit**
```bash
git add -A
git commit -m "Decompose BrowserService into 6 focused handlers

- NavigationHandler: navigate, goBack, goForward, reload
- InputHandler: click, fill, type, select, hover, pressKey
- CaptureHandler: screenshot, snapshot, pdf
- QueryHandler: getText, getAttribute
- StateHandler: wait, scroll
- ScreencastHandler: startScreencast, stopScreencast

BrowserService is now a slim coordinator (~150 lines, down from 745).
All handlers have comprehensive test coverage.
No public API changes - execute() still routes to handlers internally."
```

---

## Files to Create

| File | Purpose | Est. Lines |
|------|---------|------------|
| `handlers/types.ts` | Shared types and deps interface | ~30 |
| `handlers/navigation-handler.ts` | Navigation actions | ~80 |
| `handlers/input-handler.ts` | Input actions | ~150 |
| `handlers/capture-handler.ts` | Capture actions | ~120 |
| `handlers/query-handler.ts` | Query actions | ~60 |
| `handlers/state-handler.ts` | State actions | ~80 |
| `handlers/screencast-handler.ts` | Screencast actions | ~100 |
| `handlers/index.ts` | Unified exports | ~20 |
| `handlers/__tests__/navigation-handler.test.ts` | Navigation tests | ~80 |
| `handlers/__tests__/input-handler.test.ts` | Input tests | ~150 |
| `handlers/__tests__/capture-handler.test.ts` | Capture tests | ~80 |
| `handlers/__tests__/query-handler.test.ts` | Query tests | ~60 |
| `handlers/__tests__/state-handler.test.ts` | State tests | ~80 |
| `handlers/__tests__/screencast-handler.test.ts` | Screencast tests | ~80 |

## Files to Modify

| File | Change |
|------|--------|
| `browser-service.ts` | Remove action methods, add handler delegation |
| `browser-service.test.ts` | Keep as coordinator integration tests |
| `index.ts` | No changes (exports BrowserService) |

---

## Key Design Decisions

1. **Utility methods stay in BrowserService**: `getLocator()` and `resolveSelector()` are shared across all handlers, so they stay in the coordinator and are passed via deps.

2. **Session management stays in BrowserService**: `createSession`, `hasSession`, `getSession`, `closeSession` are core coordinator responsibilities.

3. **Handlers are stateless**: All state (sessions map) remains in BrowserService. Handlers receive session as a parameter.

4. **Screencast handler gets emit callback**: Since screencast emits frame events, the handler receives an emit callback in its deps.

5. **No public API changes**: External code continues to call `service.execute(sessionId, action, params)`. The decomposition is internal.

---

## Verification Commands

```bash
# After each phase
bun run build && bun run test

# Check line counts
wc -l packages/agent/src/external/browser/browser-service.ts
wc -l packages/agent/src/external/browser/handlers/*.ts

# Verify no unused exports
grep -r "from '.*browser-service" packages/agent/src/ --include="*.ts" | grep -v test | head -20
```

---

## Success Criteria

- [ ] `browser-service.ts` reduced to ~150 lines
- [ ] 6 focused handlers created with clear single responsibilities
- [ ] All 40+ existing tests pass
- [ ] New handler tests added (~60+ new tests)
- [ ] Build succeeds with zero TypeScript errors
- [ ] No public API changes
- [ ] No dead code or unused imports

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Breaking existing tests | Run tests after each phase, don't proceed if failing |
| Missing edge cases | Handler tests mirror existing test patterns |
| Circular dependencies | Handlers import types only, not BrowserService |
| Performance regression | Handlers are thin wrappers, no overhead |

---

## Out of Scope

1. Adding new browser actions
2. Changing the public API
3. Modifying session management logic
4. Refactoring other browser-related files
