# Bug Fix: OpenAI Codex Reasoning Blocks Not Streaming

## Summary

**Root Cause**: OpenAI Codex **DOES** return reasoning/thinking blocks in the SSE stream, but our provider isn't handling them. The Codex CLI successfully displays reasoning summaries because it handles these events.

## Event Flow (Already Working for Other Providers)

```
Provider (openai-codex.ts)
    ↓ yields thinking_start/delta/end
Agent (turn-runner.ts)
    ↓ forwards to event handler
AgentEventHandler (agent-event-handler.ts:1021-1082)
    ↓ handleThinkingStart/Delta/End()
    ↓ accumulates in sessionContext
WebSocket
    ↓ agent.thinking_start/delta/end events
iOS (ChatViewModel+Events.swift:41-62)
    ↓ handleThinkingDelta()
ThinkingContentView.swift
    → Displays spinning brain icon + text
```

**The infrastructure is complete** - iOS already handles thinking events perfectly. We just need to emit them from the OpenAI Codex provider.

## Evidence from Codex CLI Session Data

From `~/.codex/sessions/2026/01/12/rollout-*.jsonl`:
```json
{"type":"event_msg","payload":{"type":"agent_reasoning","text":"**Preparing workspace...**"}}
{"type":"response_item","payload":{
  "type":"reasoning",
  "summary":[{"type":"summary_text","text":"**Preparing workspace...**"}],
  "content":null,
  "encrypted_content":"gAAAAABp..."
}}
```

OpenAI returns:
- `type: "reasoning"` response items
- `summary` array with displayable text
- `encrypted_content` for full reasoning (encrypted, not usable)

## SSE Events We're Missing

From Codex source (`codex-rs/codex-api/src/sse/responses.rs`):

| SSE Event | Description | Our Handling |
|-----------|-------------|--------------|
| `response.reasoning_summary_part.added` | Reasoning section started | ❌ Missing |
| `response.reasoning_summary_text.delta` | Delta for summary text | ❌ Missing |
| `response.reasoning_text.delta` | Delta for content | ❌ Missing |
| `response.output_item.added` (type=reasoning) | Full reasoning item | ❌ Missing |

## Current Provider Gap

**`openai-codex.ts` only handles:**
```typescript
case 'response.output_text.delta':      // ✅ text
case 'response.output_item.added':      // ⚠️ only function_call type
case 'response.function_call_arguments.delta':  // ✅ tool args
case 'response.completed':              // ✅ final
```

**Missing handling for:**
- `response.reasoning_summary_part.added`
- `response.reasoning_summary_text.delta`
- Reasoning items in `response.output_item.added`
- Reasoning items in `response.completed`

## Implementation Plan

### 1. Add Reasoning SSE Event Handling (`openai-codex.ts`)

Add cases to the switch statement in `streamInternal()`:

```typescript
case 'response.reasoning_summary_part.added':
  yield { type: 'thinking_start' };
  break;

case 'response.reasoning_summary_text.delta':
  if (event.delta) {
    yield { type: 'thinking_delta', delta: event.delta };
  }
  break;
```

### 2. Handle Reasoning in `response.output_item.added`

Currently only handles `function_call`:
```typescript
if (event.item?.type === 'function_call' ...) { ... }
```

Add:
```typescript
if (event.item?.type === 'reasoning') {
  yield { type: 'thinking_start' };
  // Handle summary text if present
}
```

### 3. Handle Reasoning in `response.completed`

Add reasoning item processing alongside message and function_call:
```typescript
if (item.type === 'reasoning' && item.summary) {
  // Extract summary text and yield thinking_end
}
```

### 4. Update ResponsesStreamEvent Type

Add reasoning-related fields:
```typescript
interface ResponsesStreamEvent {
  type: string;
  delta?: string;
  summary_index?: number;   // For reasoning_summary_text.delta
  content_index?: number;   // For reasoning_text.delta
  item?: {
    type: string;           // 'function_call' | 'message' | 'reasoning'
    summary?: Array<{ type: string; text?: string }>;  // For reasoning
    // ... existing fields
  };
}
```

### 5. Update Model Capabilities

Change `supportsReasoning` models to also have `supportsThinking: true` if they stream reasoning:
```typescript
'gpt-5.2-codex': {
  supportsReasoning: true,
  supportsThinking: true,  // ADD THIS
}
```

## Files to Modify

| File | Changes |
|------|---------|
| `packages/core/src/providers/openai-codex.ts:103-135` | Update `ResponsesStreamEvent` type |
| `packages/core/src/providers/openai-codex.ts:529-535` | Add reasoning accumulator variables |
| `packages/core/src/providers/openai-codex.ts:569-621` | Add reasoning SSE event cases to switch |
| `packages/core/src/providers/openai-codex.ts:646-687` | Handle reasoning in `response.completed` |
| `packages/core/src/providers/openai-codex.ts:141-186` | Add `supportsThinking: true` to OPENAI_CODEX_MODELS |

## Detailed Changes

### 1. Update `ResponsesStreamEvent` interface (~line 104)

```typescript
interface ResponsesStreamEvent {
  type: string;
  delta?: string;
  summary_index?: number;   // For reasoning_summary_text.delta
  content_index?: number;   // For reasoning_text.delta
  item?: {
    type: string;           // 'function_call' | 'message' | 'reasoning'
    id?: string;
    call_id?: string;
    name?: string;
    arguments?: string;
    content?: Array<{ type: string; text?: string }>;
    summary?: Array<{ type: string; text?: string }>;  // NEW: For reasoning
  };
  // ... existing fields
}
```

### 2. Add accumulator variables (~line 532)

```typescript
let accumulatedThinking = '';
let thinkingStarted = false;
```

### 3. Add reasoning cases to switch (~line 602, after function_call_arguments.delta)

```typescript
case 'response.reasoning_summary_part.added':
  if (!thinkingStarted) {
    thinkingStarted = true;
    yield { type: 'thinking_start' };
  }
  break;

case 'response.reasoning_summary_text.delta':
  if (event.delta) {
    if (!thinkingStarted) {
      thinkingStarted = true;
      yield { type: 'thinking_start' };
    }
    accumulatedThinking += event.delta;
    yield { type: 'thinking_delta', delta: event.delta };
  }
  break;

case 'response.output_item.added':
  // Existing function_call handling...
  if (event.item?.type === 'reasoning') {
    if (!thinkingStarted) {
      thinkingStarted = true;
      yield { type: 'thinking_start' };
    }
  }
  break;
```

### 4. Handle reasoning in `response.completed` (~line 646)

Add alongside message and function_call handling:
```typescript
else if (item.type === 'reasoning') {
  // Extract summary text
  if (item.summary) {
    for (const summaryItem of item.summary) {
      if (summaryItem.type === 'summary_text' && summaryItem.text) {
        if (!thinkingStarted) {
          thinkingStarted = true;
          yield { type: 'thinking_start' };
        }
        if (!accumulatedThinking.includes(summaryItem.text)) {
          accumulatedThinking += summaryItem.text;
        }
      }
    }
  }
}
```

### 5. Emit thinking_end before done event (~line 689)

```typescript
// Emit thinking_end if we had thinking
if (thinkingStarted) {
  yield { type: 'thinking_end', thinking: accumulatedThinking };
}

// Emit text_end if we had text
if (textStarted) {
  yield { type: 'text_end', text: accumulatedText };
}
```

### 6. Update OPENAI_CODEX_MODELS (~line 141)

Add `supportsThinking: true` to each model:
```typescript
'gpt-5.2-codex': {
  // ... existing fields
  supportsReasoning: true,
  supportsThinking: true,  // ADD
},
```

## Test-Driven Development Plan

### Phase 1: Write Tests First (Before Implementation)

Create `packages/core/test/providers/openai-codex.test.ts` following patterns from `openai.test.ts` and `google.test.ts`.

#### 1.1 Reasoning Stream Event Tests

```typescript
describe('Reasoning Events', () => {
  it('should emit thinking_start when reasoning_summary_part.added received', async () => {
    const mockStreamData = [
      'data: {"type":"response.reasoning_summary_part.added","summary_index":0}\n\n',
      'data: [DONE]\n\n',
    ];
    // Assert thinking_start event emitted
  });

  it('should emit thinking_delta for reasoning_summary_text.delta', async () => {
    const mockStreamData = [
      'data: {"type":"response.reasoning_summary_text.delta","delta":"**Analyzing...**","summary_index":0}\n\n',
      'data: [DONE]\n\n',
    ];
    // Assert thinking_delta with correct content
  });

  it('should emit thinking_end with accumulated text on response.completed', async () => {
    const mockStreamData = [
      'data: {"type":"response.reasoning_summary_part.added","summary_index":0}\n\n',
      'data: {"type":"response.reasoning_summary_text.delta","delta":"Step 1","summary_index":0}\n\n',
      'data: {"type":"response.reasoning_summary_text.delta","delta":" Step 2","summary_index":0}\n\n',
      'data: {"type":"response.completed","response":{"output":[{"type":"reasoning","summary":[{"type":"summary_text","text":"Step 1 Step 2"}]}]}}\n\n',
    ];
    // Assert thinking_end with "Step 1 Step 2"
  });

  it('should handle reasoning item in response.output_item.added', async () => {
    const mockStreamData = [
      'data: {"type":"response.output_item.added","item":{"type":"reasoning","summary":[]}}\n\n',
      'data: [DONE]\n\n',
    ];
    // Assert thinking_start emitted
  });
});
```

#### 1.2 Integration Tests with Text + Reasoning

```typescript
describe('Mixed Content Streaming', () => {
  it('should emit reasoning before text in correct order', async () => {
    const mockStreamData = [
      // Reasoning first
      'data: {"type":"response.reasoning_summary_part.added","summary_index":0}\n\n',
      'data: {"type":"response.reasoning_summary_text.delta","delta":"Thinking...","summary_index":0}\n\n',
      // Then text
      'data: {"type":"response.output_text.delta","delta":"Here is my answer"}\n\n',
      'data: {"type":"response.completed",...}\n\n',
    ];

    const events = [];
    for await (const event of provider.stream(context)) {
      events.push(event.type);
    }

    // Assert order: start → thinking_start → thinking_delta → thinking_end → text_start → text_delta → text_end → done
  });

  it('should include ThinkingContent in final message', async () => {
    // Verify message.content includes { type: 'thinking', thinking: '...' }
  });
});
```

#### 1.3 Edge Case Tests

```typescript
describe('Edge Cases', () => {
  it('should handle empty reasoning summary gracefully', async () => { });
  it('should handle reasoning without text response', async () => { });
  it('should handle text without reasoning (no regression)', async () => { });
  it('should handle tool calls with reasoning', async () => { });
  it('should not emit thinking events when reasoning disabled', async () => { });
});
```

### Phase 2: Implementation (Make Tests Pass)

#### 2.1 Update ResponsesStreamEvent Type

```typescript
interface ResponsesStreamEvent {
  type: string;
  delta?: string;
  summary_index?: number;
  content_index?: number;
  item?: {
    type: string;  // 'function_call' | 'message' | 'reasoning'
    id?: string;
    call_id?: string;
    name?: string;
    arguments?: string;
    content?: Array<{ type: string; text?: string }>;
    summary?: Array<{ type: string; text?: string }>;
  };
  response?: {
    id: string;
    output: Array<{
      type: string;
      summary?: Array<{ type: string; text?: string }>;
      // ... existing fields
    }>;
    usage?: { input_tokens: number; output_tokens: number };
  };
}
```

#### 2.2 Add Accumulator State

```typescript
// In streamInternal(), after existing state variables
let accumulatedThinking = '';
let thinkingStarted = false;
```

#### 2.3 Add SSE Event Cases

```typescript
case 'response.reasoning_summary_part.added':
  if (!thinkingStarted) {
    thinkingStarted = true;
    yield { type: 'thinking_start' };
  }
  break;

case 'response.reasoning_summary_text.delta':
  if (event.delta) {
    if (!thinkingStarted) {
      thinkingStarted = true;
      yield { type: 'thinking_start' };
    }
    accumulatedThinking += event.delta;
    yield { type: 'thinking_delta', delta: event.delta };
  }
  break;
```

#### 2.4 Update output_item.added Handler

```typescript
case 'response.output_item.added':
  if (event.item?.type === 'function_call' && ...) {
    // Existing tool call handling
  } else if (event.item?.type === 'reasoning') {
    if (!thinkingStarted) {
      thinkingStarted = true;
      yield { type: 'thinking_start' };
    }
  }
  break;
```

#### 2.5 Update response.completed Handler

```typescript
// In the output item processing loop:
} else if (item.type === 'reasoning' && item.summary) {
  for (const summaryItem of item.summary) {
    if (summaryItem.type === 'summary_text' && summaryItem.text) {
      if (!thinkingStarted) {
        thinkingStarted = true;
        yield { type: 'thinking_start' };
      }
      // Only add if not already accumulated via deltas
      if (!accumulatedThinking) {
        accumulatedThinking = summaryItem.text;
      }
    }
  }
}

// Before emitting done, emit thinking_end if needed:
if (thinkingStarted) {
  yield { type: 'thinking_end', thinking: accumulatedThinking };
}
```

#### 2.6 Include ThinkingContent in Final Message

```typescript
// In the content building section:
const content: (TextContent | ThinkingContent | ToolCall)[] = [];

if (accumulatedThinking) {
  content.push({ type: 'thinking', thinking: accumulatedThinking });
}
if (accumulatedText) {
  content.push({ type: 'text', text: accumulatedText });
}
// ... tool calls
```

### Phase 3: Regression Tests

#### 3.1 Verify Existing Functionality Still Works

```typescript
describe('Regression Tests', () => {
  it('should still stream text correctly (no reasoning)', async () => {
    // Existing text streaming must not break
  });

  it('should still stream tool calls correctly', async () => {
    // Existing tool call streaming must not break
  });

  it('should handle mixed text + tool calls', async () => {
    // Existing patterns must work
  });
});
```

### Phase 4: Integration Verification

#### 4.1 Server Event Handler (Already Works)

Verify `agent-event-handler.ts:1021-1082` receives and forwards events:
- `handleThinkingStart()` - emits `agent.thinking_start`
- `handleThinkingDelta()` - accumulates and emits `agent.thinking_delta`
- `handleThinkingEnd()` - emits `agent.thinking_end`

#### 4.2 iOS App (Already Works)

Verify `ChatViewModel+Events.swift:41-62` handles events:
- Creates `ChatMessage.thinking()` on first delta
- Updates message with streaming text
- Displays via `ThinkingContentView.swift`

### Phase 5: Model Capability Update

Update `OPENAI_CODEX_MODELS` to indicate thinking support:

```typescript
'gpt-5.2-codex': {
  // ... existing fields
  supportsReasoning: true,
  supportsThinking: true,  // NEW - enables thinking UI
},
```

## Files to Modify (In Order)

| Order | File | Purpose |
|-------|------|---------|
| 1 | `packages/core/test/providers/openai-codex.test.ts` | **CREATE** - Write tests first |
| 2 | `packages/core/src/providers/openai-codex.ts` | Add reasoning event handling |
| 3 | `packages/core/src/providers/openai-codex.ts` | Update model capabilities |

## Verification Checklist

### Automated Verification
- [ ] `bun run build` passes
- [ ] `bun run test` passes (all existing + new tests)
- [ ] New reasoning tests pass: thinking_start, thinking_delta, thinking_end
- [ ] Regression tests pass: text streaming, tool calls unchanged

### Manual Verification
- [ ] Start iOS app with GPT-5.2 Codex
- [ ] Send prompt: "Analyze this code and explain step by step"
- [ ] Verify thinking blocks appear with spinning brain icon
- [ ] Verify thinking text streams incrementally
- [ ] Verify text response appears after thinking
- [ ] Verify tap to expand thinking works
- [ ] Test session resume - thinking blocks should persist and display correctly

### Cross-Provider Consistency
- [ ] Anthropic thinking still works
- [ ] Google Gemini thinking still works
- [ ] OpenAI Codex reasoning now works
- [ ] All use same event types (thinking_start/delta/end)
- [ ] All display consistently in iOS app
