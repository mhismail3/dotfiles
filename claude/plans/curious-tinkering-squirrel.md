# Discord Bot UX Refactoring Plan

## Problem Summary
Current Discord bot shows raw terminal output in code blocks with no real-time feedback during processing. User sees "thinking" → nothing → final blob.

## Solution: Two-Phase Message Architecture with Threaded Subagent Support

### Core UX Flow (Single Agent)
```
🦌 Working on your request...
🧠 Analyzing the authentication flow...
📖 3 files · 🔍 2 searches · ⚡ 1 command
```
↓ (Phase transition when text response starts)
```
[Clean response with smart formatting - prose, code blocks, etc.]

✅ 45s · Opus 4.5 · 12.5k↓ 2.1k↑ · $0.08
```

### Multi-Agent UX (Threaded Architecture)
```
Main Channel
├── 🦌 Orchestrating analysis...
│   🤖 3 subagents active
│
├── Thread: "🔍 Code Reviewer"          ← Auto-created on SubagentStart
│   ├── 🤖 Started · Explore agent
│   ├── 🧠 Scanning for patterns...
│   ├── 📖 Read 8 files
│   └── ✅ Complete · Found 3 issues
│
├── Thread: "🧪 Test Generator"
│   ├── 🤖 Started · Plan agent
│   └── ⏳ Working...
│
└── Final Response (main channel)
    └── Synthesized output + stats
```

---

## Architecture Overview

### Key Components

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AgentTracker (NEW)                           │
│  Maps agent_id → { thread, phaseManager, stats, parentToolUseId }  │
│  Handles SubagentStart/Stop hooks                                   │
│  Creates Discord threads for subagents                              │
└─────────────────────────────────────────────────────────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         ↓                    ↓                    ↓
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  PhaseManager   │  │  PhaseManager   │  │  PhaseManager   │
│  (Parent Agent) │  │  (Subagent 1)   │  │  (Subagent 2)   │
│  Main channel   │  │  Thread 1       │  │  Thread 2       │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

### SDK Hook Integration

```typescript
// New hooks to handle (from SDK):
SubagentStart: {
  agent_id: string;       // Unique ID for this subagent
  agent_type: string;     // "Explore", "Plan", etc.
}

SubagentStop: {
  agent_id: string;
  agent_transcript_path: string;  // Can read full transcript
}

// Existing hooks to enhance:
PreToolUse: {
  tool_name: "Task";
  tool_input: { description, prompt, subagent_type, run_in_background }
}
```

---

## Implementation Steps

### Step 1: Create AgentTracker (`src/discord/agentTracker.ts`)

**Purpose:** Central registry for tracking all agents (parent + subagents) and their Discord contexts.

```typescript
interface TrackedAgent {
  agentId: string;
  agentType: string;              // "Explore", "Plan", "general-purpose"
  parentToolUseId: string | null; // null for root agent
  thread: ThreadChannel | null;   // Discord thread (null for parent in main channel)
  phaseManager: PhaseManager;
  stats: ActivityStats;
  startTime: Date;
  status: 'active' | 'complete' | 'error';
}

class AgentTracker {
  private agents: Map<string, TrackedAgent>;
  private rootAgentId: string | null;

  // Called on session init
  registerRootAgent(phaseManager: PhaseManager): string;

  // Called on SubagentStart hook
  async onSubagentStart(agentId: string, agentType: string, parentToolUseId: string): Promise<void>;

  // Called on SubagentStop hook
  async onSubagentStop(agentId: string, transcriptPath: string): Promise<void>;

  // Route SDK messages to correct agent's PhaseManager
  routeMessage(message: SDKMessage): PhaseManager;

  // Get all active subagents for parent status display
  getActiveSubagents(): TrackedAgent[];

  // Update parent's embed to show subagent activity
  async updateParentSubagentDisplay(): Promise<void>;
}
```

**Thread Creation Logic (on SubagentStart):**
```typescript
async onSubagentStart(agentId: string, agentType: string, parentToolUseId: string) {
  const rootAgent = this.agents.get(this.rootAgentId);
  const parentMessage = rootAgent.phaseManager.getMessage();

  // Create thread from parent's message
  const thread = await parentMessage.startThread({
    name: `${AGENT_EMOJI[agentType]} ${agentType} Agent`,
    autoArchiveDuration: 60,  // Archive after 1 hour
  });

  // Create PhaseManager for this subagent's thread
  const subPhaseManager = new PhaseManager(thread, config.streaming);
  await subPhaseManager.startWorking(`Subagent: ${agentType}`);

  this.agents.set(agentId, {
    agentId,
    agentType,
    parentToolUseId,
    thread,
    phaseManager: subPhaseManager,
    stats: createActivityStats(),
    startTime: new Date(),
    status: 'active',
  });

  // Update parent to show new subagent
  await this.updateParentSubagentDisplay();
}
```

---

### Step 2: Create ContentParser (`src/discord/contentParser.ts`)

**Purpose:** Parse Claude's mixed output into semantic segments for Discord formatting.

**Functions:**
- `extractCodeBlocks(text)` - Pull out fenced code blocks, return placeholders
- `formatForDiscord(text)` - Convert markdown, apply heuristic formatting
- `applyHeuristicFormatting(text)` - File paths → inline code, env vars → inline code
- `chunkMessage(text, maxLength)` - Split at natural boundaries (paragraphs > newlines > spaces)

**Key patterns to adapt from `src/telegram/formatter.ts`:**
- Code block extraction (lines 28-44)
- Heuristic formatting for paths/envvars (lines 208-251)
- Message chunking with natural boundaries (lines 300-338)

**Discord-specific:**
- No HTML escaping needed (Discord uses markdown natively)
- Headings (`# Foo`) → `**Foo**` (Discord doesn't render H1-H6)
- Tables → code block (Discord tables render poorly on mobile)

---

### Step 3: Create PhaseManager (`src/discord/phaseManager.ts`)

New file - orchestrates the two-phase message flow.

```typescript
class PhaseManager {
  private phase: 'working' | 'responding' | 'complete';
  private workingMessage: Message | null;
  private responseBuffer: string = '';
  private lastThinking: string = '';
  private activityCounts: ActivityStats;

  async startWorking(prompt, user, model): Promise<void>;
  async updateThinking(summary: string): Promise<void>;
  async updateActivity(stats: ActivityStats): Promise<void>;
  async startResponse(): Promise<void>;  // Transitions to response phase
  async appendResponse(text: string): Promise<void>;
  async finalize(stats: FinalStats): Promise<void>;
  async error(message: string): Promise<void>;
}
```

**Phase transition:**
- First `text_delta` event triggers `startResponse()`
- Working embed updates to show "Generating response..."
- Response text posts as new message(s) using ContentParser

**Rate limiting:**
- Reuse existing throttle logic from StreamBuffer (1500ms min interval)
- Batch thinking updates, show latest
- Accumulate activity counts

---

### Step 4: Modify Embeds (`src/discord/embeds.ts`)

**Remove code block wrapping:**
- Line 57: `createSessionStartEmbed` - remove triple backticks around prompt
- Line 135: `createCompletionEmbed` - remove triple backticks around output
- Line 178: `createErrorEmbed` - remove triple backticks

**Add new embed functions:**

```typescript
export function createWorkingEmbed(options: {
  thinking?: string;
  activity: ActivityStats;
  model?: string;
  duration?: number;
}): EmbedBuilder;

export function createStatsEmbed(options: {
  duration: number;
  model?: string;
  inputTokens?: number;
  outputTokens?: number;
  cost?: number;
  activity: ActivityStats;
}): EmbedBuilder;
```

**Working embed format:**
- Title: "🦌 Working on your request..."
- Description: thinking summary (if any) + activity line
- Color: Purple (working)
- Footer: Model name

**Stats embed format (compact, follows response):**
- No title (clean)
- Fields inline: Duration | Model | Tokens | Cost
- Activity summary line
- Color: Green (complete)

---

### Step 5: Modify Hooks (`src/discord/hooks.ts`)

**Update `createToolHooks` signature:**
```typescript
export function createToolHooks(
  agentTracker: AgentTracker,  // NEW: central tracker
  stats: ActivityStats
): Record<string, ...>;
```

**Add new hooks for subagent lifecycle:**
```typescript
SubagentStart: [{
  hooks: [async (input: SubagentStartHookInput) => {
    await agentTracker.onSubagentStart(
      input.agent_id,
      input.agent_type,
      input.parent_tool_use_id
    );
    return {};
  }]
}],

SubagentStop: [{
  hooks: [async (input: SubagentStopHookInput) => {
    await agentTracker.onSubagentStop(
      input.agent_id,
      input.agent_transcript_path
    );
    return {};
  }]
}],
```

**In PreToolUse hook (currently lines 75-82):**
```typescript
// Route to correct agent's PhaseManager based on parent_tool_use_id
const phaseManager = agentTracker.routeMessage(input);
await phaseManager.updateThinking(status);
await phaseManager.updateActivity(stats);
```

**Keep existing `formatToolStatus` function** - generates emoji + tool name strings.

---

### Step 6: Modify Processor (`src/discord/processor.ts`)

**Constructor change:**
```typescript
// OLD:
constructor(
  _channelId: string,
  private streamingMessage: StreamingMessage,
  ...
)

// NEW:
constructor(
  private channel: TextChannel,
  private agentTracker: AgentTracker,
  private stats: ActivityStats,
  config: Config
)
```

**Add phase tracking per agent:**
```typescript
private responsePhaseByAgent: Map<string, boolean> = new Map();
```

**Modify `processStreamEvent` (lines 127-143):**
```typescript
if (delta.type === 'text_delta') {
  // Route to correct agent's PhaseManager
  const phaseManager = this.agentTracker.routeMessage(message);
  const agentId = message.parent_tool_use_id || 'root';

  // Phase transition on first text for this agent
  if (!this.responsePhaseByAgent.get(agentId)) {
    await phaseManager.startResponse();
    this.responsePhaseByAgent.set(agentId, true);
  }
  this.hasReceivedStreamText = true;
  await phaseManager.appendResponse(delta.text);
} else if (delta.type === 'thinking_delta') {
  const phaseManager = this.agentTracker.routeMessage(message);
  const summary = this.thinkingProcessor.summarize(delta.thinking);
  if (summary) {
    await phaseManager.updateThinking(summary);  // NOW GOES TO DISCORD
  }
}
```

**Modify `sendStatus` (lines 178-183):**
```typescript
// OLD: console.log(`[Status] ${status}`);
// NEW:
const phaseManager = this.agentTracker.getRootAgent().phaseManager;
await phaseManager.updateThinking(status);
```

---

### Step 7: Modify Index (`src/discord/index.ts`)

**Update `runQuery` function:**
```typescript
async function runQuery(
  session: ClaudeSession,
  prompt: string,
  interaction: CommandInteraction,
  channel: TextChannel
): Promise<void> {
  const stats = createActivityStats();

  // NEW: AgentTracker manages all agents (parent + subagents)
  const agentTracker = new AgentTracker(channel, config.streaming);

  // Register root agent with its PhaseManager
  const rootPhaseManager = new PhaseManager(interaction, channel, config.streaming);
  agentTracker.registerRootAgent(rootPhaseManager);

  await rootPhaseManager.startWorking(
    prompt,
    interaction.user,
    getModelDisplayName(session.model)
  );

  // Pass agentTracker to hooks (handles SubagentStart/Stop + tool routing)
  const hooks = createToolHooks(agentTracker, stats);
  const processor = new MessageProcessor(channel, agentTracker, stats, config);

  try {
    for await (const message of session.query(prompt, config, hooks)) {
      // AgentTracker routes message to correct PhaseManager based on parent_tool_use_id
      await processor.process(message);
    }
    await processor.flush();
  } catch (error) {
    await rootPhaseManager.error(error.message);
  }
}
```

**Also update `handleMessage` for natural conversation** - same pattern.

---

### Step 8: Cleanup

- Deprecate `StreamingMessage` class (keep `StreamBuffer` for rate limiting)
- Remove console.log status messages
- Update imports across files

---

## Edge Cases to Handle

| Case | Handling |
|------|----------|
| Tool-only query (no text response) | Finalize working embed directly with "Completed" |
| Code block > 2000 chars | Split at function boundaries with continuation markers |
| Error during response phase | Post error as separate message, show partial stats |
| User aborts mid-stream | Flush buffer, post "Session stopped" embed |
| Rate limit (429) | Buffer updates, retry on next interval |
| Subagent spawned | Create thread, track in AgentTracker |
| Multiple parallel subagents | Each gets own thread, parent shows count |
| Subagent fails | Mark thread as error, continue parent |
| Nested subagents (agent spawns agent) | Create nested threads (up to Discord limit) |

---

## Files to Modify

| File | Changes |
|------|---------|
| `src/discord/agentTracker.ts` | **NEW** - central registry for multi-agent tracking |
| `src/discord/contentParser.ts` | **NEW** - content parsing and formatting |
| `src/discord/phaseManager.ts` | **NEW** - two-phase message orchestration |
| `src/discord/embeds.ts` | Remove code blocks, add working/stats/subagent embeds |
| `src/discord/hooks.ts` | Add SubagentStart/Stop hooks, route via AgentTracker |
| `src/discord/processor.ts` | Use AgentTracker for message routing |
| `src/discord/index.ts` | Wire AgentTracker into query flow |
| `src/discord/streamingMessage.ts` | Keep StreamBuffer, deprecate StreamingMessage |

---

## Testing Checklist

### Single Agent (Basic)
- [ ] Simple prompt → clean prose response (no code blocks)
- [ ] Code-heavy response → proper syntax highlighting
- [ ] Long response → proper chunking across messages
- [ ] Tool-heavy query → see activity updates during work
- [ ] Extended thinking → see thinking summaries
- [ ] User abort → clean termination
- [ ] Error during query → error displayed properly
- [ ] Rate limit hit → graceful retry

### Multi-Agent (Subagents)
- [ ] Prompt that spawns 1 subagent → thread created with progress
- [ ] Prompt that spawns 3+ parallel subagents → all threads created
- [ ] Parent embed updates to show "🤖 3 subagents active"
- [ ] Subagent completes → thread shows ✅, parent updated
- [ ] Subagent fails → thread shows ❌, parent continues
- [ ] Final response synthesizes subagent outputs
- [ ] Threads auto-archive after completion
