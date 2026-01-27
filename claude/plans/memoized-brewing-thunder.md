# Gemini 3 Pro/Flash Integration Plan

## Summary

Robustly integrate Gemini 3 Pro and Flash models into Tron with full thinking mode support, safety settings, and UI integration across all platforms. Uses **Test-Driven Development** to ensure zero regressions to existing provider implementations.

## Current State

Tron already has a basic Google/Gemini provider at `packages/core/src/providers/google.ts` with:
- Basic streaming via REST API
- Function/tool calling
- Model registry with Gemini 2.5 and 3 models (in google.ts, not models.ts)
- API key authentication
- **Missing**: Thinking mode, safety settings, correct model specs, UI integration, model registry export

## Key Gemini 3 Specifics

| Feature | Gemini 3 | Gemini 2.5 |
|---------|----------|------------|
| Thinking parameter | `thinkingLevel` (minimal/low/medium/high) | `thinkingBudget` (0-32768 tokens) |
| Temperature | **Must be 1.0** (enforced) | Configurable |
| Context window | 1,048,576 tokens | 1M - 2M tokens |
| Max output | 65,536 tokens | 16,384 tokens |
| Safety default | OFF | OFF |

## Critical Path for Model Switching

Model switching flows: **UI → RPC → Orchestrator → Agent → ContextManager**

Key invariants to preserve:
1. **Tool ID remapping** - Each provider converts IDs during `convertMessages()`. Gemini uses `call_*` format (already supported via OpenAI pattern)
2. **Message preservation** - All messages survive provider switches
3. **Context limit recalculation** - ContextManager updates limits and may trigger compaction
4. **System prompt adaptation** - Each provider may have different system prompt handling

---

## TDD Implementation Strategy

### Phase 0: Write Tests FIRST (Before Implementation)

Write failing tests for all new functionality before implementing. This ensures:
- Clear requirements definition
- Regression protection
- Confidence in implementation correctness

---

## Implementation Tasks

### Phase 1: TDD - Write Failing Tests

**File: `packages/core/test/providers/google.test.ts`**

Add comprehensive tests (will fail initially):

```typescript
describe('Gemini 3 Thinking Mode', () => {
  it('should configure thinkingLevel for Gemini 3 models')
  it('should use thinkingBudget for Gemini 2.5 models')
  it('should yield thinking_start/thinking_delta/thinking_end events')
  it('should enforce temperature=1.0 for Gemini 3')
  it('should log warning when temperature override attempted for Gemini 3')
})

describe('Safety Handling', () => {
  it('should emit error event on SAFETY finish reason')
  it('should include blocked categories in error')
  it('should apply default OFF safety settings for Gemini 3')
})

describe('Model Registry Updates', () => {
  it('should have correct context window for gemini-3-pro-preview (1048576)')
  it('should have correct max output for gemini-3-pro-preview (65536)')
  it('should mark supportsThinking=true for Gemini 3 models')
  it('should include supportedThinkingLevels for Flash (includes minimal)')
})
```

**File: `packages/core/test/context/model-switching.test.ts`**

Add Gemini to model switching circuit:

```typescript
describe('Anthropic → Google Gemini', () => {
  it('preserves messages when switching from Claude to Gemini')
  it('updates context limit (200k Claude → 1M Gemini)')
  it('handles tool ID remapping (toolu_* → call_*)')
})

describe('Google Gemini → Anthropic', () => {
  it('preserves messages when switching from Gemini to Claude')
  it('remaps tool IDs back to Anthropic format')
})

describe('Full Circuit with Gemini', () => {
  it('preserves context: Anthropic → Gemini → Codex → Anthropic')
})
```

**File: `packages/core/test/rpc/handlers/model.handler.test.ts`**

Add Gemini validation tests:

```typescript
it('should accept gemini-3-pro-preview as valid model')
it('should accept gemini-3-flash-preview as valid model')
it('should include Gemini models in model.list response')
```

---

### Phase 2: Core Provider Implementation (`packages/core/src/providers/google.ts`)

1. **Update model specs** to match official docs:
   - `gemini-3-pro-preview`: 1,048,576 input / 65,536 output
   - `gemini-3-flash-preview`: 1,048,576 input / 65,536 output
   - Add `supportsThinking: true` flag

2. **Add thinking mode support**:
   - Add `GeminiThinkingLevel` type: `'minimal' | 'low' | 'medium' | 'high'`
   - Detect Gemini 3 vs 2.5 models and use appropriate parameter
   - Handle `thought: true` parts in streaming response
   - Yield `thinking_start`, `thinking_delta`, `thinking_end` events

3. **Add safety settings**:
   - Add `SafetySetting` type with categories and thresholds
   - Apply default `OFF` threshold for agentic use
   - Handle `SAFETY` finish reason with proper error event

4. **Enforce Gemini 3 constraints**:
   - Force `temperature: 1.0` for Gemini 3 models
   - Log warning if different temperature requested

### Phase 3: Factory Integration (`packages/core/src/providers/factory.ts`)

1. Add to `ProviderConfig`:
   - `thinkingLevel?: GeminiThinkingLevel`
   - `geminiThinkingBudget?: number`
   - `safetySettings?: SafetySetting[]`

2. Add to `ProviderStreamOptions`:
   - `thinkingLevel?: GeminiThinkingLevel`
   - `geminiThinkingBudget?: number`

3. Update `createGoogleProvider()` to wire new options

4. Update `getModelCapabilities()` to read Gemini thinking support

### Phase 4: Model Registry (`packages/core/src/providers/models.ts`)

1. Add `GeminiModelInfo` interface with:
   - `tier: 'pro' | 'flash' | 'flash-lite'`
   - `supportsThinking: boolean`
   - `defaultThinkingLevel?: string`
   - `supportedThinkingLevels?: string[]`
   - `preview?: boolean`

2. Add `GEMINI_MODELS` array with all Gemini models

3. Add `GEMINI_MODEL_CATEGORIES` for organized display

### Phase 5: RPC Handler (`packages/core/src/rpc/handlers/model.handler.ts`)

1. Import `GEMINI_MODELS` from models.ts
2. Add to `handleModelSwitch()` validation:
   ```typescript
   const geminiModel = GEMINI_MODELS.find((m) => m.id === params.model);
   if (!anthropicModel && !codexModel && !geminiModel) {
     return MethodRegistry.errorResponse(...)
   }
   ```
3. Add Gemini models to `handleModelList()`:
   ```typescript
   ...GEMINI_MODELS.map((m) => ({
     id: m.id,
     name: m.shortName,
     provider: 'google',
     contextWindow: m.contextWindow,
     supportsThinking: m.supportsThinking,
     thinkingLevel: m.defaultThinkingLevel,
     supportedThinkingLevels: m.supportedThinkingLevels,
     isPreview: m.preview,
     tier: m.tier,
   }))
   ```

### Phase 6: UI Updates

**TUI** (`packages/tui/src/components/ModelSwitcher.tsx`):
- Import `GEMINI_MODELS` from `@tron/core`
- Add Gemini tier colors (purple for Pro, cyan for Flash)
- Combine with Anthropic models in display list
- Add `(preview)` badge for Gemini 3 models

**Web** (`packages/chat-web/src/components/overlay/ModelSwitcher.tsx`):
- Same changes as TUI

**iOS** (`packages/ios-app/Sources/Views/ModelPickerMenu.swift`):
- Add `geminiModels` computed property
- Add `isGemini` extension to `ModelInfo`
- Include Gemini section with different icon (e.g., "sparkle")

### Phase 7: Context Manager Updates (`packages/core/src/context/context-manager.ts`)

Ensure `getContextLimit()` includes Gemini context windows:
- `gemini-3-pro-preview`: 1,048,576
- `gemini-3-flash-preview`: 1,048,576
- `gemini-2.5-pro`: 2,097,152
- `gemini-2.5-flash`: 1,048,576

---

## Files to Modify

| File | Changes |
|------|---------|
| `packages/core/src/providers/google.ts` | Types, model specs, thinking mode, safety |
| `packages/core/src/providers/factory.ts` | Config types, createGoogleProvider |
| `packages/core/src/providers/models.ts` | GeminiModelInfo type, GEMINI_MODELS array |
| `packages/core/src/context/context-manager.ts` | Add Gemini context limits |
| `packages/core/src/rpc/handlers/model.handler.ts` | Add Gemini to model list/validation |
| `packages/tui/src/components/ModelSwitcher.tsx` | Add Gemini models to display |
| `packages/chat-web/src/components/overlay/ModelSwitcher.tsx` | Add Gemini models to display |
| `packages/ios-app/Sources/Views/ModelPickerMenu.swift` | Add Gemini section |
| `packages/ios-app/Sources/Models/RPCTypes.swift` | Add isGemini extension |

## Test Files to Create/Update

| File | Changes |
|------|---------|
| `packages/core/test/providers/google.test.ts` | Add thinking mode, safety, model spec tests |
| `packages/core/test/context/model-switching.test.ts` | Add Gemini switching circuit tests |
| `packages/core/test/rpc/handlers/model.handler.test.ts` | Add Gemini validation tests |

---

## Verification Strategy (TDD Flow)

### Step 1: Run Existing Tests (Baseline)
```bash
bun run test
```
Ensure **all existing tests pass** before making changes.

### Step 2: Write Failing Tests
Write tests per Phase 1 above. Run tests - they should fail.

### Step 3: Implement Features
Implement each phase, running tests after each change:
```bash
bun run test --filter google
bun run test --filter model-switching
bun run test --filter model.handler
```

### Step 4: Build Verification
```bash
bun run build
```
Ensure no TypeScript errors.

### Step 5: Full Test Suite
```bash
bun run test
```
All tests including existing Anthropic/Codex tests must pass.

### Step 6: Manual Integration Testing

1. **Model Selection**:
   - TUI: Press model selector, verify Gemini models appear
   - Web: Open model switcher, verify Gemini models appear
   - iOS: Check ModelPickerMenu shows Gemini section

2. **Model Switching**:
   - Start session with Claude → switch to Gemini 3 Pro
   - Verify messages preserved
   - Start session with Gemini → switch to Claude
   - Verify tool call IDs remapped correctly

3. **Thinking Mode** (requires Google API key):
   - Enable thinking with Gemini 3 Pro
   - Verify thinking events stream
   - Test with Gemini 2.5 (thinkingBudget)

4. **Function Calling**:
   - Use tool with Gemini 3
   - Verify function call/response cycle works

5. **Edge Cases**:
   - Safety block handling
   - Large context (test compaction trigger on switch FROM Gemini)

### Step 7: Regression Check

Run the full circuit test to ensure no regressions:
```bash
bun run test packages/core/test/context/model-switching.test.ts
```

Verify the "Full Circuit with Gemini" test passes:
- Anthropic → Gemini → Codex → Anthropic

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Breaking existing providers | TDD ensures tests written first; full test suite run before merge |
| Tool ID incompatibility | Use existing ID remapping pattern (already works for OpenAI→Anthropic) |
| Context limit miscalculation | Add specific tests for Gemini context limits |
| Safety block UX issues | Handle SAFETY finish reason with clear error message |
| Temperature override silent failure | Log warning when Gemini 3 temperature override attempted |
