# Plan: Blocking SpawnSubagent with Real-Time iOS Streaming

## Overview

Transform SpawnSubagent from a fire-and-forget tool into a **blocking tool** that:
1. Spawns the subagent
2. Blocks until completion (while streaming progress to iOS)
3. Returns the full result to the parent agent

This eliminates the need for separate `WaitForSubagent` calls and provides a better UX where one chip represents the entire subagent lifecycle.

## Current Problems (From Screenshots)

1. SpawnSubagent chip immediately shows "Agent Completed" (wrong - it just spawned)
2. Detail sheet shows "Spawning..." indefinitely until done, then jumps to completion
3. Second chip appears for WaitForSubagent (should be ONE unified chip)
4. WaitForSubagent chip is not interactive
5. No real-time progress visible in detail sheet

## Target UX

1. **One chip per subagent** - SpawnSubagent is the only tool, it blocks until done
2. **Chip shows accurate status** - "Spawning..." → "Running (T3)" → "Completed"
3. **Detail sheet streams live** - Shows tool calls, text output, progress AS IT HAPPENS
4. **Multiple subagents** - If parent spawns 3 subagents in parallel, all 3 block together
5. **Result returned to parent** - Full output injected as tool result when done

---

## Part 1: Backend - Make SpawnSubagent Blocking

### 1.1 Update SpawnSubagentParams

**File: `packages/core/src/tools/spawn-subagent.ts`**

```typescript
export interface SpawnSubagentParams {
  task: string;
  model?: string;
  tools?: string[];
  skills?: string[];
  workingDirectory?: string;
  maxTurns?: number;
  // NEW - blocking config (extensible for future non-blocking mode)
  blocking?: boolean;   // Default: true (for now, always blocking)
  timeout?: number;     // Default: 30 minutes (1800000ms)
}

export interface SpawnSubagentResult {
  sessionId: string;
  success: boolean;
  // NEW - full result when blocking
  output?: string;
  summary?: string;
  totalTurns?: number;
  duration?: number;
  tokenUsage?: { inputTokens: number; outputTokens: number };
  error?: string;
}
```

### 1.2 Update SpawnSubagentToolConfig

```typescript
export interface SpawnSubagentToolConfig {
  sessionId: string;
  workingDirectory: string;
  model: string;
  onSpawn: SpawnSubagentCallback;
  // NEW - for blocking behavior
  getSubagentTracker: () => SubAgentTracker;
}
```

### 1.3 Modify execute() to Block

**Current flow:**
1. Call `onSpawn()` → creates session
2. Return immediately with "spawned successfully"

**New flow (blocking by default, extensible for future non-blocking):**
1. Call `onSpawn()` → creates session, starts async execution
2. Check `blocking` param (default: true)
3. If blocking: call `tracker.waitFor(sessionId, timeout)` → **BLOCKS HERE**
4. Return full result (output, turns, duration, tokens)

```typescript
async execute(toolCallId: string, args: SpawnSubagentParams): Promise<TronToolResult<SpawnSubagentResult>> {
  // Spawn the subagent (starts async execution)
  const spawnResult = await this.config.onSpawn(this.config.sessionId, args);

  if (!spawnResult.success) {
    return { success: false, error: spawnResult.error };
  }

  // Determine blocking behavior (default: true, extensible for future)
  const isBlocking = args.blocking !== false;  // Default to blocking

  if (!isBlocking) {
    // FUTURE: Non-blocking mode - return immediately with session ID
    // User would use WaitForSubagent or QuerySubagent to check status
    return {
      success: true,
      result: {
        sessionId: spawnResult.sessionId,
        success: true,
        // Note: No output/summary yet - subagent still running
      }
    };
  }

  // BLOCKING MODE (current default): Wait for subagent to complete
  const tracker = this.config.getSubagentTracker();
  const timeout = args.timeout ?? 1800000; // 30 min default

  try {
    const result = await tracker.waitFor(spawnResult.sessionId, timeout);

    return {
      success: result.success,
      result: {
        sessionId: spawnResult.sessionId,
        success: result.success,
        output: result.output,
        summary: result.summary,
        totalTurns: result.totalTurns,
        duration: result.duration,
        tokenUsage: result.tokenUsage,
        error: result.error,
      }
    };
  } catch (error) {
    return {
      success: false,
      error: `Subagent timed out after ${timeout}ms`,
      result: { sessionId: spawnResult.sessionId, success: false, error: 'timeout' }
    };
  }
}
```

### 1.4 Update Agent Factory

**File: `packages/server/src/orchestrator/agent-factory.ts`**

Pass `getSubagentTracker` to SpawnSubagentTool:

```typescript
new SpawnSubagentTool({
  sessionId: config.sessionId,
  workingDirectory: config.workingDirectory,
  model: config.model,
  onSpawn: (parentId, params) => subagentOps.spawnSubsession(parentId, params),
  getSubagentTracker: () => session.subagentTracker,  // NEW
})
```

---

## Part 2: Backend - Stream Subagent Events to Parent

### 2.1 Forward Subagent Turn Events

**File: `packages/server/src/orchestrator/subagent-ops.ts`**

Currently, only high-level events (spawned, status, completed) are emitted. For real-time detail sheet, we need to forward the subagent's actual events.

**Add in `runSubagentAsync()` - after each subagent turn:**

```typescript
// After subagent turn completes, forward key events to parent
const turnEvents = await this.config.eventStore.getEventsSince(
  subagentSessionId,
  lastEventId
);

for (const event of turnEvents) {
  // Forward text, tool, thinking events to parent via WebSocket
  if (['text_delta', 'tool_start', 'tool_end', 'thinking_delta'].includes(event.type)) {
    this.config.emit('agent_event', {
      type: `agent.subagent_event`,
      sessionId: parentSessionId,
      timestamp: new Date().toISOString(),
      data: {
        subagentSessionId,
        event: {
          type: event.type,
          data: event.data,
          timestamp: event.timestamp,
        }
      }
    });
  }
}
```

### 2.2 Add RPC Event Type

**File: `packages/core/src/rpc/types.ts`**

```typescript
// Add to RpcEventType union
| 'agent.subagent_event'  // Forwarded event from subagent

// Add interface
export interface RpcSubagentEventData {
  subagentSessionId: string;
  event: {
    type: string;  // text_delta, tool_start, tool_end, thinking_delta
    data: unknown;
    timestamp: string;
  };
}
```

---

## Part 3: iOS - Fix Chip Status Display

### 3.1 Update MessageBubble Parsing

**File: `Sources/Views/MessageBubble/MessageBubble.swift`**

The issue: Chip shows "Completed" immediately because we're parsing the tool result text which says "spawned successfully".

**Fix:** Determine status from tool execution state, not result text:

```swift
private func createSubagentToolData(from tool: ToolUseData) -> SubagentToolData? {
    let task = extractTaskFromArguments(tool.arguments)
    let sessionId = extractSessionId(from: tool.result) ?? tool.toolCallId

    // Determine status from TOOL STATUS, not result text
    let status: SubagentStatus
    switch tool.status {
    case .running:
        status = .running  // Tool still executing = subagent still running
    case .success:
        // Tool completed = subagent completed (blocking behavior)
        status = .completed
    case .error:
        status = .failed
    }

    // ... rest unchanged
}
```

### 3.2 Remove WaitForSubagent Chip

Since SpawnSubagent is now blocking, WaitForSubagent won't be called. But for safety:

```swift
case "waitforsubagent":
    // Should not appear with blocking SpawnSubagent
    // Hide completely - the SpawnSubagent chip handles everything
    EmptyView()
```

---

## Part 4: iOS - Real-Time Detail Sheet

### 4.1 Create SubagentDetailViewModel

**New File: `Sources/ViewModels/SubagentDetailViewModel.swift`**

```swift
@Observable
@MainActor
final class SubagentDetailViewModel {
    let subagentSessionId: String
    let rpcClient: RPCClient

    private(set) var events: [SubagentEventItem] = []
    private(set) var status: SubagentStatus = .running
    private(set) var currentTurn: Int = 0
    private(set) var summary: String?
    private(set) var error: String?

    init(subagentSessionId: String, rpcClient: RPCClient) {
        self.subagentSessionId = subagentSessionId
        self.rpcClient = rpcClient
    }

    func startListening() {
        // Subscribe to subagent events via RPCClient
        rpcClient.onSubagentEvent = { [weak self] event in
            guard event.subagentSessionId == self?.subagentSessionId else { return }
            self?.handleEvent(event)
        }

        rpcClient.onSubagentStatus = { [weak self] event in
            guard event.subagentSessionId == self?.subagentSessionId else { return }
            self?.status = .running
            self?.currentTurn = event.currentTurn
        }

        rpcClient.onSubagentCompleted = { [weak self] event in
            guard event.subagentSessionId == self?.subagentSessionId else { return }
            self?.status = .completed
            self?.summary = event.resultSummary
        }

        rpcClient.onSubagentFailed = { [weak self] event in
            guard event.subagentSessionId == self?.subagentSessionId else { return }
            self?.status = .failed
            self?.error = event.error
        }
    }

    private func handleEvent(_ event: SubagentForwardedEvent) {
        let item = SubagentEventItem(from: event)
        events.append(item)
    }
}
```

### 4.2 Update SubagentDetailSheet

**File: `Sources/Views/SubagentDetailSheet.swift`**

```swift
@available(iOS 26.0, *)
struct SubagentDetailSheet: View {
    let initialData: SubagentToolData
    let rpcClient: RPCClient

    @State private var viewModel: SubagentDetailViewModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header card (status, turns, duration)
                    headerCard

                    // Task section
                    taskSection

                    // LIVE EVENT STREAM (new)
                    if let vm = viewModel {
                        eventStreamSection(events: vm.events)
                    }

                    // Summary section (when completed)
                    if let summary = viewModel?.summary ?? initialData.resultSummary {
                        summarySection(summary: summary)
                    }

                    // Error section (when failed)
                    if let error = viewModel?.error ?? initialData.error {
                        errorSection(error: error)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            viewModel = SubagentDetailViewModel(
                subagentSessionId: initialData.subagentSessionId,
                rpcClient: rpcClient
            )
            viewModel?.startListening()
        }
    }

    @ViewBuilder
    private func eventStreamSection(events: [SubagentEventItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))

            ForEach(events) { event in
                SubagentEventRow(event: event)
            }
        }
    }
}
```

### 4.3 Add Event Row Component

**Add to SubagentDetailSheet.swift or new file:**

```swift
struct SubagentEventRow: View {
    let event: SubagentEventItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            eventIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))

                if let detail = event.detail {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(3)
                }
            }

            Spacer()
        }
        .padding(10)
        .background(Color.tronSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var eventIcon: some View {
        Group {
            switch event.type {
            case .toolStart:
                Image(systemName: "gearshape")
                    .foregroundStyle(.tronEmerald)
            case .toolEnd:
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.tronSuccess)
            case .textDelta:
                Image(systemName: "text.bubble")
                    .foregroundStyle(.tronMint)
            case .thinking:
                Image(systemName: "brain")
                    .foregroundStyle(.tronPurple)
            }
        }
        .font(.system(size: 12))
    }
}
```

### 4.4 Add Event Data Models

**File: `Sources/Models/Events.swift`**

```swift
// Forwarded subagent event
struct SubagentForwardedEvent: Decodable {
    let subagentSessionId: String
    let event: InnerEvent

    struct InnerEvent: Decodable {
        let type: String
        let data: AnyCodable  // or specific union type
        let timestamp: String
    }
}

// For display in detail sheet
struct SubagentEventItem: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: SubagentEventType
    let title: String
    let detail: String?

    init(from event: SubagentForwardedEvent) {
        self.timestamp = ISO8601DateFormatter().date(from: event.event.timestamp) ?? Date()

        switch event.event.type {
        case "tool_start":
            self.type = .toolStart
            self.title = "Tool: \(event.event.data["toolName"] ?? "unknown")"
            self.detail = nil
        case "tool_end":
            self.type = .toolEnd
            self.title = "Tool completed"
            self.detail = event.event.data["result"] as? String
        case "text_delta":
            self.type = .textDelta
            self.title = "Output"
            self.detail = event.event.data["text"] as? String
        case "thinking_delta":
            self.type = .thinking
            self.title = "Thinking..."
            self.detail = nil
        default:
            self.type = .textDelta
            self.title = event.event.type
            self.detail = nil
        }
    }
}

enum SubagentEventType {
    case toolStart, toolEnd, textDelta, thinking
}
```

### 4.5 Update RPCClient

**File: `Sources/Services/RPCClient.swift`**

```swift
// Add callback
var onSubagentEvent: ((SubagentForwardedEvent) -> Void)?

// In handleEventData(), add case:
case .subagentEvent(let e):
    logger.debug("Subagent event for \(e.subagentSessionId): \(e.event.type)")
    onSubagentEvent?(e)
```

---

## Part 5: Keep WaitForSubagent for Advanced Use

Keep `WaitForSubagent` available for:
- Waiting for multiple subagents spawned with `blocking: false` (future)
- Custom timeout handling after spawn
- Compatibility with existing workflows

**No changes needed** - WaitForSubagent remains as-is.

**iOS handling:** Keep EmptyView() for WaitForSubagent since blocking SpawnSubagent won't trigger it. If non-blocking mode is used in future, WaitForSubagent chip can be shown.

---

## File Change Summary

### Backend (TypeScript):

| File | Change |
|------|--------|
| `packages/core/src/tools/spawn-subagent.ts` | Add blocking behavior, update result type |
| `packages/core/src/rpc/types.ts` | Add `agent.subagent_event` type |
| `packages/server/src/orchestrator/agent-factory.ts` | Pass `getSubagentTracker` to tool |
| `packages/server/src/orchestrator/subagent-ops.ts` | Forward subagent events to parent |

### iOS (Swift):

| File | Change |
|------|--------|
| `Sources/Views/MessageBubble/MessageBubble.swift` | Fix status determination from tool state |
| `Sources/Views/SubagentDetailSheet.swift` | Add live event stream, connect to view model |
| `Sources/ViewModels/SubagentDetailViewModel.swift` | NEW - manage real-time event subscription |
| `Sources/Models/Events.swift` | Add SubagentForwardedEvent, SubagentEventItem |
| `Sources/Services/RPCClient.swift` | Add onSubagentEvent callback |

---

## Verification

1. **Backend Build**: `bun run build` in packages/core and packages/server
2. **iOS Build**: Xcode build for simulator
3. **Manual Test**:
   - Start server, connect iOS app
   - Ask agent: "Spawn a subagent to list files in the current directory"
   - Verify: ONE chip appears showing "Running..."
   - Tap chip: Detail sheet shows live tool calls
   - Wait for completion: Chip updates to "Completed"
   - Tap again: Shows summary + full event history
   - Verify: Parent agent receives full result, no separate WaitForSubagent
4. **Multiple Subagents Test**:
   - Ask agent to spawn 3 subagents in parallel
   - Verify: All 3 chips appear
   - Verify: All 3 complete before parent continues
   - Verify: Each chip independently tappable with own detail view
