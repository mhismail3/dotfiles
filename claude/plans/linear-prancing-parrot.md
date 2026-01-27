# RenderAppUI Auto-Retry on Validation Failure

## Problem

Currently, when RenderAppUI validation fails:
1. Tool returns `isError: true` with validation errors
2. LLM sees the error and responds with text (e.g., "I'll fix that")
3. Turn ends because LLM didn't call any tools
4. iOS sheet shows error state
5. User has to manually prompt the agent to retry

## Goal

**Automatic retry with continuous streaming:**
1. Validation runs before tool "officially" completes
2. If validation fails, agent automatically retries without returning an error
3. iOS sheet stays open and updates in real-time during retries
4. Only show errors for connection issues (not validation failures)

## Current Architecture

```
LLM generates tool call → Tool executes → Validation → Return result
                                              ↓
                              If error: isError=true, turn ends
```

## Proposed Architecture

```
LLM generates tool call → Tool executes → Validation
                                              ↓
                              If error: return stopTurn=false with errors
                                              ↓
                              Turn continues → LLM sees errors → Retries
                                              ↓
                              iOS sheet stays open, updates with new attempt
```

---

## Implementation Plan

### Step 1: Modify RenderAppUI Tool - Return Non-Error on Validation Failure

**File:** `packages/core/src/tools/render-app-ui.ts`

Change validation failure handling to NOT return `isError: true`. Instead:
- Return validation errors in content
- Set `stopTurn: false` so turn continues
- LLM will see errors and can retry with corrections

```typescript
// Current behavior (lines ~108-114):
if (!validation.valid) {
  return {
    content: `Invalid UI definition:\n${validation.errors.join('\n')}`,
    isError: true,  // ← This causes the problem
    details: { validation },
  };
}

// New behavior:
if (!validation.valid) {
  return {
    content: `UI validation failed. Please fix these errors and call RenderAppUI again with the same canvasId:\n${validation.errors.join('\n')}\n\nKeep the iOS sheet open - user is waiting.`,
    isError: false,      // ← Not an error, just needs retry
    stopTurn: false,     // ← Let turn continue so LLM can retry
    details: {
      validation,
      needsRetry: true,
      canvasId: params.canvasId,
    },
  };
}
```

### Step 2: Track Retry Count to Prevent Infinite Loops

**File:** `packages/core/src/tools/render-app-ui.ts`

Add retry tracking per canvasId:

```typescript
// Add class property
private retryCount: Map<string, number> = new Map();
private readonly MAX_RETRIES = 3;

// In execute():
const currentRetries = this.retryCount.get(params.canvasId) || 0;

if (!validation.valid) {
  if (currentRetries >= this.MAX_RETRIES) {
    // Give up after max retries
    this.retryCount.delete(params.canvasId);
    return {
      content: `Failed to render valid UI after ${this.MAX_RETRIES} attempts:\n${validation.errors.join('\n')}`,
      isError: true,
      stopTurn: true,
    };
  }

  this.retryCount.set(params.canvasId, currentRetries + 1);
  return {
    content: `UI validation failed (attempt ${currentRetries + 1}/${this.MAX_RETRIES}). Fix these errors:\n${validation.errors.join('\n')}`,
    isError: false,
    stopTurn: false,
    details: { needsRetry: true, canvasId: params.canvasId },
  };
}

// On successful validation, clear retry count
this.retryCount.delete(params.canvasId);
```

### Step 3: iOS Sheet Persistence Across Retries

**File:** `packages/ios-app/Sources/ViewModels/State/UICanvasState.swift`

Ensure sheet stays open when same canvasId gets a new render attempt:

```swift
func startRender(canvasId: String, title: String?, toolCallId: String) {
    // Check if this is a retry for an existing canvas
    if let existing = canvases[canvasId] {
        // Keep the sheet open, just update status to rendering
        var updated = existing
        updated.status = .rendering
        updated.toolCallId = toolCallId
        updated.partialJSON = ""
        canvases[canvasId] = updated
        logger.info("Canvas retry started: \(canvasId)", category: .ui)
    } else {
        // New canvas
        let canvas = UICanvasData(
            canvasId: canvasId,
            title: title,
            toolCallId: toolCallId,
            status: .rendering
        )
        canvases[canvasId] = canvas
        activeCanvasId = canvasId
        showSheet = true
        logger.info("Canvas render started: \(canvasId)", category: .ui)
    }
}
```

### Step 4: Server-Side - Emit Retry Events

**File:** `packages/server/src/orchestrator/agent-event-handler.ts`

When a RenderAppUI tool result indicates `needsRetry`, emit a special event:

```typescript
// In handleToolExecutionEnd for RenderAppUI:
if (detailsObj?.needsRetry) {
  this.config.emit('agent_event', {
    type: 'agent.ui_render_retry',
    sessionId,
    timestamp,
    data: {
      canvasId: detailsObj.canvasId,
      attempt: detailsObj.attempt,
      errors: resultContent,
    },
  });
  // Don't emit ui_render_complete or ui_render_error
  return;
}
```

### Step 5: iOS - Handle Retry Events

**File:** `packages/ios-app/Sources/Models/Events.swift`

Add new event type:

```swift
case uiRenderRetry = "agent.ui_render_retry"

struct UIRenderRetryEvent: Decodable {
    let canvasId: String
    let attempt: Int
    let errors: String
}
```

**File:** `packages/ios-app/Sources/ViewModels/ChatViewModel+Events.swift`

```swift
func handleUIRenderRetry(_ event: UIRenderRetryEvent) {
    logger.info("UI render retry: canvasId=\(event.canvasId), attempt=\(event.attempt)", category: .events)

    // Update canvas to show retry status (keep sheet open)
    uiCanvasState.setRetrying(
        canvasId: event.canvasId,
        attempt: event.attempt,
        errors: event.errors
    )
}
```

### Step 6: UICanvasState - Add Retry Status

**File:** `packages/ios-app/Sources/ViewModels/State/UICanvasState.swift`

```swift
enum UICanvasStatus {
    case rendering
    case retrying(attempt: Int, errors: String)  // ← New
    case complete
    case error(String)
}

func setRetrying(canvasId: String, attempt: Int, errors: String) {
    guard var canvas = canvases[canvasId] else { return }
    canvas.status = .retrying(attempt: attempt, errors: errors)
    canvases[canvasId] = canvas
    // Sheet stays open, shows "Fixing... (attempt 2/3)"
}
```

### Step 7: UICanvasSheet - Show Retry Status

**File:** `packages/ios-app/Sources/Views/UICanvasSheet.swift`

```swift
case .retrying(let attempt, let errors):
    retryingView(canvas: canvas, attempt: attempt, errors: errors)

private func retryingView(canvas: UICanvasData, attempt: Int, errors: String) -> some View {
    VStack(spacing: 16) {
        // Show current progressive render (if any)
        if let root = canvas.parsedRoot {
            ScrollView { UIComponentView(component: root, state: state) }
        }

        // Retry indicator at bottom
        HStack(spacing: 10) {
            ProgressView().tint(.tronWarning)
            VStack(alignment: .leading) {
                Text("Fixing issues (attempt \(attempt)/3)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tronWarning)
                Text(errors.prefix(100))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tronTextMuted)
            }
        }
        .padding()
        .background(Color.tronSurface.opacity(0.9))
    }
}
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `packages/core/src/tools/render-app-ui.ts` | Add retry logic, return `stopTurn: false` on validation failure |
| `packages/server/src/orchestrator/agent-event-handler.ts` | Emit `ui_render_retry` events |
| `packages/ios-app/Sources/Models/Events.swift` | Add `UIRenderRetryEvent` |
| `packages/ios-app/Sources/Services/RPCClient.swift` | Add `onUIRenderRetry` callback |
| `packages/ios-app/Sources/ViewModels/ChatViewModel.swift` | Wire callback |
| `packages/ios-app/Sources/ViewModels/ChatViewModel+Events.swift` | Add handler |
| `packages/ios-app/Sources/ViewModels/State/UICanvasState.swift` | Add retry status, update `startRender` |
| `packages/ios-app/Sources/Views/UICanvasSheet.swift` | Add retry view |

---

## Flow Diagram

```
User asks for UI
       ↓
LLM calls RenderAppUI(canvasId: "demo")
       ↓
iOS: Sheet opens, shows "Rendering..."
       ↓
Tool validates → FAILS
       ↓
Tool returns: stopTurn=false, needsRetry=true
       ↓
Server emits: ui_render_retry
       ↓
iOS: Shows "Fixing... (attempt 1/3)"  ← Sheet stays open!
       ↓
Turn continues → LLM sees error message
       ↓
LLM calls RenderAppUI(canvasId: "demo") again  ← Same canvasId
       ↓
iOS: Updates existing sheet with new streaming content
       ↓
Tool validates → PASSES
       ↓
Server emits: ui_render_complete
       ↓
iOS: Shows final UI
```

---

## Edge Cases

1. **Max retries exceeded**: Return actual error, iOS shows error view
2. **User dismisses sheet during retry**: Clean up state, let retry complete silently
3. **Different canvasId on retry**: LLM should use same canvasId (prompted in error message)
4. **Concurrent retries**: Map keyed by canvasId handles this
5. **Connection lost during retry**: Existing reconnection logic handles this

---

## Verification

1. **Happy path**: Ask for complex UI, watch it render progressively
2. **Validation failure**: Intentionally request invalid UI structure, observe:
   - Sheet stays open
   - "Fixing..." status appears
   - Agent retries automatically
   - Final valid UI renders
3. **Max retries**: Create intentionally unfixable UI, verify error after 3 attempts
4. **Connection test**: Disconnect during render, reconnect, verify recovery

---

## Risk Assessment

- **Medium risk**: Changes to tool return behavior
- **Requires iOS changes**: New event type and UI state
- **Backward compatible**: Only affects RenderAppUI validation failures

---

## Test-Driven Development Plan

### Phase 1: Write Tests FIRST (Before Implementation)

#### 1.1 RenderAppUI Tool Tests
**File:** `packages/core/test/tools/render-app-ui.test.ts` (NEW)

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { RenderAppUITool } from '../../src/tools/render-app-ui.js';

describe('RenderAppUITool', () => {
  let tool: RenderAppUITool;

  beforeEach(() => {
    tool = new RenderAppUITool({ workingDirectory: '/test' });
  });

  describe('tool definition', () => {
    it('should have correct name', () => {
      expect(tool.name).toBe('RenderAppUI');
    });

    it('should require canvasId and ui parameters', () => {
      expect(tool.parameters.required).toContain('canvasId');
      expect(tool.parameters.required).toContain('ui');
    });
  });

  describe('validation success', () => {
    it('should return success with stopTurn=true for valid UI', async () => {
      const result = await tool.execute({
        canvasId: 'test-canvas',
        ui: { $tag: 'VStack', $children: [{ $tag: 'Text', $children: 'Hello' }] }
      });

      expect(result.isError).toBe(false);
      expect(result.stopTurn).toBe(true);
      expect(result.details?.canvasId).toBe('test-canvas');
    });

    it('should clear retry count after successful validation', async () => {
      // First call with invalid UI
      await tool.execute({
        canvasId: 'retry-test',
        ui: { $tag: 'Button' } // Missing required props
      });

      // Second call with valid UI
      const result = await tool.execute({
        canvasId: 'retry-test',
        ui: { $tag: 'Button', $props: { label: 'OK', actionId: 'ok' } }
      });

      expect(result.isError).toBe(false);
      expect(result.stopTurn).toBe(true);
    });
  });

  describe('validation failure - retry behavior', () => {
    it('should return stopTurn=false on first validation failure', async () => {
      const result = await tool.execute({
        canvasId: 'test',
        ui: { $tag: 'Button' } // Missing label and actionId
      });

      expect(result.isError).toBe(false); // NOT an error
      expect(result.stopTurn).toBe(false); // Allow turn to continue
      expect(result.details?.needsRetry).toBe(true);
      expect(result.content).toContain('validation failed');
    });

    it('should track retry attempts per canvasId', async () => {
      const result1 = await tool.execute({
        canvasId: 'canvas-a',
        ui: { $tag: 'Button' }
      });
      expect(result1.content).toContain('attempt 1');

      const result2 = await tool.execute({
        canvasId: 'canvas-a',
        ui: { $tag: 'Button' }
      });
      expect(result2.content).toContain('attempt 2');

      // Different canvasId should have independent counter
      const resultB = await tool.execute({
        canvasId: 'canvas-b',
        ui: { $tag: 'Button' }
      });
      expect(resultB.content).toContain('attempt 1');
    });

    it('should return actual error after MAX_RETRIES', async () => {
      // Exhaust retries
      for (let i = 0; i < 3; i++) {
        await tool.execute({ canvasId: 'max-test', ui: { $tag: 'Button' } });
      }

      // Fourth attempt should be actual error
      const result = await tool.execute({
        canvasId: 'max-test',
        ui: { $tag: 'Button' }
      });

      expect(result.isError).toBe(true);
      expect(result.stopTurn).toBe(true);
      expect(result.content).toContain('Failed to render valid UI after');
    });

    it('should include validation errors in content', async () => {
      const result = await tool.execute({
        canvasId: 'test',
        ui: { $tag: 'Button' }
      });

      expect(result.content).toContain('label');
      expect(result.content).toContain('actionId');
    });
  });
});
```

#### 1.2 Validators Tests
**File:** `packages/core/test/ui/validators.test.ts` (NEW)

```typescript
import { describe, it, expect } from 'vitest';
import {
  validateRenderAppUIParams,
  validateComponentTree
} from '../../src/ui/validators.js';

describe('UI Validators', () => {
  describe('validateRenderAppUIParams', () => {
    it('should validate minimal valid params', () => {
      const result = validateRenderAppUIParams({
        canvasId: 'test',
        ui: { $tag: 'Text', $children: 'Hello' }
      });
      expect(result.valid).toBe(true);
      expect(result.errors).toHaveLength(0);
    });

    it('should require canvasId', () => {
      const result = validateRenderAppUIParams({
        ui: { $tag: 'Text' }
      } as any);
      expect(result.valid).toBe(false);
      expect(result.errors).toContain(expect.stringContaining('canvasId'));
    });

    it('should require ui', () => {
      const result = validateRenderAppUIParams({
        canvasId: 'test'
      } as any);
      expect(result.valid).toBe(false);
      expect(result.errors).toContain(expect.stringContaining('ui'));
    });
  });

  describe('validateComponentTree', () => {
    it('should validate Button requires label and actionId', () => {
      const result = validateComponentTree({ $tag: 'Button' });
      expect(result.errors).toContain(expect.stringContaining('label'));
      expect(result.errors).toContain(expect.stringContaining('actionId'));
    });

    it('should validate Toggle requires label and bindingId', () => {
      const result = validateComponentTree({ $tag: 'Toggle' });
      expect(result.errors).toContain(expect.stringContaining('label'));
      expect(result.errors).toContain(expect.stringContaining('bindingId'));
    });

    it('should validate nested components', () => {
      const result = validateComponentTree({
        $tag: 'VStack',
        $children: [
          { $tag: 'Button' }, // Invalid - missing props
          { $tag: 'Text', $children: 'Valid' }
        ]
      });
      expect(result.errors.length).toBeGreaterThan(0);
      expect(result.errors.some(e => e.includes('Button'))).toBe(true);
    });

    it('should reject unknown tags', () => {
      const result = validateComponentTree({ $tag: 'UnknownComponent' });
      expect(result.valid).toBe(false);
      expect(result.errors).toContain(expect.stringContaining('Unknown'));
    });

    it('should enforce depth limit', () => {
      // Create deeply nested structure
      let ui: any = { $tag: 'Text', $children: 'deep' };
      for (let i = 0; i < 60; i++) {
        ui = { $tag: 'VStack', $children: [ui] };
      }
      const result = validateComponentTree(ui);
      expect(result.valid).toBe(false);
      expect(result.errors).toContain(expect.stringContaining('depth'));
    });
  });
});
```

#### 1.3 Server Event Handler Tests
**File:** `packages/server/test/orchestrator/handlers/ui-render.test.ts` (NEW)

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { AgentEventHandler } from '../../../src/orchestrator/agent-event-handler.js';

describe('AgentEventHandler - UI Render Events', () => {
  let handler: AgentEventHandler;
  let mockEmit: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockEmit = vi.fn();
    handler = new AgentEventHandler({
      emit: mockEmit,
      sessionId: 'test-session',
    });
  });

  describe('ui_render_retry event', () => {
    it('should emit ui_render_retry when tool returns needsRetry', () => {
      handler.handleAgentEvent({
        type: 'tool_execution_end',
        sessionId: 'test-session',
        timestamp: new Date().toISOString(),
        toolCallId: 'tc-1',
        toolName: 'RenderAppUI',
        isError: false,
        result: {
          content: 'Validation failed...',
          details: {
            needsRetry: true,
            canvasId: 'test-canvas',
            attempt: 1,
          },
        },
      });

      expect(mockEmit).toHaveBeenCalledWith('agent_event', expect.objectContaining({
        type: 'agent.ui_render_retry',
        data: expect.objectContaining({
          canvasId: 'test-canvas',
          attempt: 1,
        }),
      }));
    });

    it('should NOT emit ui_render_complete when needsRetry is true', () => {
      handler.handleAgentEvent({
        type: 'tool_execution_end',
        sessionId: 'test-session',
        timestamp: new Date().toISOString(),
        toolCallId: 'tc-1',
        toolName: 'RenderAppUI',
        isError: false,
        result: {
          content: 'Validation failed...',
          details: { needsRetry: true, canvasId: 'test' },
        },
      });

      const completeCall = mockEmit.mock.calls.find(
        call => call[1]?.type === 'agent.ui_render_complete'
      );
      expect(completeCall).toBeUndefined();
    });

    it('should emit ui_render_complete when validation passes', () => {
      handler.handleAgentEvent({
        type: 'tool_execution_end',
        sessionId: 'test-session',
        timestamp: new Date().toISOString(),
        toolCallId: 'tc-1',
        toolName: 'RenderAppUI',
        isError: false,
        result: {
          content: 'UI rendered',
          details: {
            canvasId: 'test-canvas',
            ui: { $tag: 'Text' },
          },
        },
      });

      expect(mockEmit).toHaveBeenCalledWith('agent_event', expect.objectContaining({
        type: 'agent.ui_render_complete',
      }));
    });
  });
});
```

### Phase 2: Regression Test Coverage

#### 2.1 Existing Behavior Tests (Must Not Break)

```typescript
describe('RenderAppUI - Regression Tests', () => {
  it('should still return stopTurn=true on successful render', async () => {
    // Existing behavior - must not change
    const result = await tool.execute({
      canvasId: 'test',
      ui: { $tag: 'Text', $children: 'Hello' }
    });
    expect(result.stopTurn).toBe(true);
  });

  it('should still include component counts in summary', async () => {
    const result = await tool.execute({
      canvasId: 'test',
      ui: {
        $tag: 'VStack',
        $children: [
          { $tag: 'Button', $props: { label: 'OK', actionId: 'ok' } },
          { $tag: 'Toggle', $props: { label: 'On', bindingId: 'toggle1' } }
        ]
      }
    });
    expect(result.content).toContain('1 button');
    expect(result.content).toContain('1 toggle');
  });

  it('should still include ui and state in details', async () => {
    const ui = { $tag: 'Text', $children: 'Hello' };
    const state = { key: 'value' };
    const result = await tool.execute({ canvasId: 'test', ui, state });

    expect(result.details?.ui).toEqual(ui);
    expect(result.details?.state).toEqual(state);
  });

  it('should still log warnings without failing', async () => {
    // UI with warnings but no errors should still succeed
    const result = await tool.execute({
      canvasId: 'test',
      ui: { $tag: 'VStack', $children: [] } // Empty children - warning
    });
    expect(result.isError).toBe(false);
  });
});
```

### Phase 3: Integration Tests

#### 3.1 End-to-End Retry Flow Test
**File:** `packages/server/test/ui-render-retry-integration.test.ts` (NEW)

```typescript
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { EventStoreOrchestrator } from '../src/event-store-orchestrator.js';
// ... setup imports

describe('UI Render Retry Integration', () => {
  let orchestrator: EventStoreOrchestrator;
  let events: any[];

  beforeEach(async () => {
    events = [];
    orchestrator = await createTestOrchestrator({
      onEvent: (event) => events.push(event),
    });
  });

  it('should complete full retry flow', async () => {
    // 1. Send prompt that will trigger invalid UI
    await orchestrator.sendMessage('Create a UI with just a button');

    // 2. Wait for retry events
    await waitForEvent(events, 'agent.ui_render_retry');

    // 3. Agent should auto-retry with fixed UI
    await waitForEvent(events, 'agent.ui_render_complete');

    // 4. Verify no error events
    const errorEvents = events.filter(e => e.type === 'agent.ui_render_error');
    expect(errorEvents).toHaveLength(0);
  });

  it('should emit error after max retries', async () => {
    // Force persistent validation failure
    // ... test max retry exhaustion
  });
});
```

### Phase 4: Test Execution Order

1. **Run existing tests** - Ensure baseline passes:
   ```bash
   bun run test
   ```

2. **Add new test files** (tests will fail initially - TDD):
   ```bash
   bun run test packages/core/test/tools/render-app-ui.test.ts
   bun run test packages/core/test/ui/validators.test.ts
   bun run test packages/server/test/orchestrator/handlers/ui-render.test.ts
   ```

3. **Implement features** - Make tests pass one by one

4. **Run full suite** - Verify no regressions:
   ```bash
   bun run test
   ```

---

## Implementation Order (Test-Driven)

| Step | Test File | Implementation File | Description |
|------|-----------|---------------------|-------------|
| 1 | `validators.test.ts` | - | Write validator tests (already passing) |
| 2 | `render-app-ui.test.ts` | `render-app-ui.ts` | Write retry logic tests, then implement |
| 3 | `ui-render.test.ts` | `agent-event-handler.ts` | Write event handler tests, then implement |
| 4 | - | iOS files | Implement iOS changes (no tests - manual) |
| 5 | `integration.test.ts` | - | Write and run integration tests |
| 6 | Run full suite | - | Verify zero regressions |

---

## Files to Create/Modify

### New Test Files
| File | Purpose |
|------|---------|
| `packages/core/test/tools/render-app-ui.test.ts` | RenderAppUI retry logic tests |
| `packages/core/test/ui/validators.test.ts` | Validator coverage tests |
| `packages/server/test/orchestrator/handlers/ui-render.test.ts` | Event handler tests |
| `packages/server/test/ui-render-retry-integration.test.ts` | End-to-end integration tests |

### Implementation Files (from earlier plan)
| File | Changes |
|------|---------|
| `packages/core/src/tools/render-app-ui.ts` | Add retry logic |
| `packages/server/src/orchestrator/agent-event-handler.ts` | Emit retry events |
| `packages/ios-app/Sources/Models/Events.swift` | Add retry event |
| `packages/ios-app/Sources/Services/RPCClient.swift` | Add callback |
| `packages/ios-app/Sources/ViewModels/ChatViewModel.swift` | Wire callback |
| `packages/ios-app/Sources/ViewModels/ChatViewModel+Events.swift` | Add handler |
| `packages/ios-app/Sources/ViewModels/State/UICanvasState.swift` | Add retry status |
| `packages/ios-app/Sources/Views/UICanvasSheet.swift` | Add retry view |
