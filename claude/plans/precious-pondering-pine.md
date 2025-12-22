# Refactor: Claude Agent SDK → tmux-based Claude Code CLI

## Summary

Replace the Claude Agent SDK (which consumes API credits) with tmux-based Claude Code CLI sessions to use the Claude Max subscription. One tmux session per Discord channel, streaming CLI output to rich Discord embeds.

## User Requirements

- **Sessions**: One tmux session per Discord channel (isolated workspaces)
- **Display**: Rich embeds with colors and structure (parse ANSI → Discord markdown)
- **SWOT Feature**: Remove entirely
- **Key Input**: Escape sequences in text (`\e`, `^C`, `^D`, etc.)
- **TDD**: Set up Jest, write tests before implementation

---

## Files to Delete

```
src/discord/swot/           # Entire directory (5 files)
src/discord/agentTracker.ts # No longer needed (CLI shows all in one output)
src/discord/toolStepManager.ts # SDK-specific tool tracking
src/discord/hooks.ts        # SDK hooks (replaced by output parsing)
```

## Files to Create

### Core tmux Management
```
src/discord/tmux/
  TmuxSessionManager.ts   # Create/destroy tmux sessions, send input
  TmuxOutputCapture.ts    # Capture output via polling, emit events
  types.ts                # TmuxSession, TmuxConfig interfaces
```

### CLI Output Processing
```
src/discord/cli/
  AnsiParser.ts           # Parse ANSI codes → segments → Discord markdown
  OutputParser.ts         # Detect phases (thinking/working/responding)
  types.ts                # ParsedOutput, OutputPhase interfaces
```

### Input Handling
```
src/discord/input/
  EscapeSequenceParser.ts # Parse \e, ^C, ^D → tmux send-keys format
  InputHandler.ts         # Process Discord input, send to tmux
  types.ts                # InputCommand interface
```

### Discord Output
```
src/discord/output/
  DiscordOutputManager.ts # Stream parsed output to embeds, handle chunking
```

### Tests
```
src/__tests__/
  setup.ts                # Jest setup
  mocks/
    tmuxMock.ts           # Mock child_process.exec for tmux
    discordMock.ts        # Mock Discord.js
  fixtures/
    ansiOutput.ts         # Sample ANSI-encoded CLI output
  unit/
    AnsiParser.test.ts
    EscapeSequenceParser.test.ts
    OutputParser.test.ts
    TmuxSessionManager.test.ts
    DiscordOutputManager.test.ts
```

## Files to Modify

### `src/discord/session.ts` → Complete Rewrite
- Remove SDK import and `query()` generator
- Replace `ClaudeSession` with `TmuxSession` wrapper
- `SessionManager` now manages tmux sessions via `TmuxSessionManager`

### `src/discord/processor.ts` → Simplify
- Remove SDK message type handling
- Add CLI output phase detection
- Route parsed output to `DiscordOutputManager`

### `src/discord/index.ts` → Remove SDK, Wire New Managers
- Remove SDK imports, SWOT imports
- Remove SWOT command registration and handler
- Update `runQuery()` to use tmux instead of SDK
- Update `/input` to use `InputHandler` with escape sequence support

### `src/discord/config.ts` → Add tmux Config
```typescript
tmux: {
  sessionPrefix: 'claude-moose',
  outputPollInterval: 100,  // ms
  maxOutputBuffer: 4000,
  claudeCommand: 'claude',
}
```

### `package.json`
- Remove: `@anthropic-ai/claude-agent-sdk`
- Add: `jest`, `@types/jest`, `ts-jest`
- Add scripts: `test`, `test:watch`, `test:coverage`

---

## Implementation Order (TDD)

### Phase 1: Test Infrastructure
1. Add Jest dependencies to package.json
2. Create `jest.config.js` with ts-jest preset
3. Create test setup and mocks (`tmuxMock.ts`, `discordMock.ts`)

### Phase 2: Pure Parsing Functions (Easiest to Test)
4. **AnsiParser** - Write tests first:
   - Parse ANSI color/style codes → segments
   - Convert to Discord markdown (`**bold**`, `*italic*`)
   - Strip all codes
   - Handle 256-color and RGB codes

5. **EscapeSequenceParser** - Write tests first:
   - Parse `\e` → Escape, `^C` → C-c, `\n` → Enter
   - Mixed text and escape sequences
   - Convert to tmux send-keys format

6. **OutputParser** - Write tests first:
   - Detect thinking phase (spinners, "Thinking...")
   - Detect tool use (file operations, bash commands)
   - Detect response phase (actual output)
   - Detect waiting for input

### Phase 3: Tmux Management
7. **TmuxSessionManager** - Write tests first (mock exec):
   - `createSession(channelId, workingDir)` → `tmux new-session -d -s {name} -c {dir}`
   - `destroySession(channelId)` → `tmux kill-session -t {name}`
   - `sendInput(channelId, text)` → `tmux send-keys -t {name} "{text}" Enter`
   - `sendKeys(channelId, keys)` → `tmux send-keys -t {name} {keys}` (no quotes)
   - Handle special character escaping

8. **TmuxOutputCapture** - Write tests first:
   - Poll `tmux capture-pane -t {name} -p` at interval
   - Diff new output vs last captured
   - Emit 'output' events with new content
   - Handle session death

### Phase 4: Input Handling
9. **InputHandler** - Combines EscapeSequenceParser + TmuxSessionManager:
   - Parse user input for escape sequences
   - Send via appropriate tmux method

### Phase 5: Discord Output
10. **DiscordOutputManager** - Write tests first (mock Discord):
    - Buffer output with rate limiting (reuse streaming config)
    - Build embeds based on phase (thinking: orange, responding: blue, complete: green)
    - Chunk messages at 4000 char limit
    - Start new message when limit reached

### Phase 6: Integration
11. Rewrite `session.ts`:
    - `TmuxSession` class wrapping tmux session lifecycle
    - `SessionManager` using `TmuxSessionManager` internally

12. Update `processor.ts`:
    - Process raw CLI output instead of SDK messages
    - Use `OutputParser` for phase detection
    - Route to `DiscordOutputManager`

13. Update `index.ts`:
    - Remove all SDK and SWOT imports
    - Remove SWOT command
    - Update `runQuery()` to:
      - Create tmux session if needed
      - Start output capture
      - Send prompt to CLI
      - Stream output to Discord
    - Update `/input` handler for escape sequences

14. Delete old files:
    - `src/discord/swot/` (entire directory)
    - `src/discord/agentTracker.ts`
    - `src/discord/toolStepManager.ts`
    - `src/discord/hooks.ts`

### Phase 7: Final Testing
15. Integration tests for full flow
16. Manual testing with actual Discord

---

## Key Implementation Details

### tmux Session Naming
```
claude-moose-{channelId}
```

### Claude CLI Invocation
```bash
tmux new-session -d -s claude-moose-123 -c /path/to/workdir
tmux send-keys -t claude-moose-123 "claude" Enter
```

### Output Capture (Polling)
```bash
tmux capture-pane -t claude-moose-123 -p -S -1000  # Last 1000 lines
```

### Send Input
```bash
# Text with Enter
tmux send-keys -t claude-moose-123 "user prompt here" Enter

# Special keys (no quotes)
tmux send-keys -t claude-moose-123 Escape
tmux send-keys -t claude-moose-123 C-c
```

### Escape Sequence Mapping
| User Input | tmux Format |
|------------|-------------|
| `\e`       | `Escape`    |
| `^C`       | `C-c`       |
| `^D`       | `C-d`       |
| `^Z`       | `C-z`       |
| `\n`       | `Enter`     |
| `\t`       | `Tab`       |

### Discord Embed Limits
- Embed description: 4096 chars
- Total embed: 6000 chars
- When approaching limit: finish current paragraph, start new message

### Phase Detection Patterns
```typescript
const PATTERNS = {
  thinking: /⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏|thinking/i,
  toolUse: /Reading|Writing|Editing|Running|Searching/i,
  waiting: /\(y\/n\)|continue\?|Enter to confirm/i,
  complete: /Session complete|tokens:|cost:/i,
};
```

---

## Risk Mitigations

| Risk | Mitigation |
|------|------------|
| tmux not installed | Check on startup, show clear error |
| Session dies mid-query | Detect via capture failure, auto-cleanup |
| Discord rate limits | Aggressive batching (reuse streaming config) |
| ANSI parsing edge cases | Comprehensive test fixtures, fallback to strip |
| Very long CLI output | Truncate with "... (truncated)" indicator |

---

## Success Criteria

1. No API credit consumption (uses Claude Max via CLI)
2. Sessions properly isolated per channel
3. Rich Discord embeds with parsed output
4. Escape sequences work (`\e`, `^C` interrupt Claude)
5. 80%+ test coverage on new code
6. All existing commands work (except SWOT removed)

---

## Critical Files Reference

**To Replace:**
- `/Users/moose/Downloads/projects/claude-moose/src/discord/session.ts`

**To Modify:**
- `/Users/moose/Downloads/projects/claude-moose/src/discord/index.ts`
- `/Users/moose/Downloads/projects/claude-moose/src/discord/processor.ts`
- `/Users/moose/Downloads/projects/claude-moose/src/discord/config.ts`
- `/Users/moose/Downloads/projects/claude-moose/package.json`

**To Delete:**
- `/Users/moose/Downloads/projects/claude-moose/src/discord/swot/` (directory)
- `/Users/moose/Downloads/projects/claude-moose/src/discord/agentTracker.ts`
- `/Users/moose/Downloads/projects/claude-moose/src/discord/toolStepManager.ts`
- `/Users/moose/Downloads/projects/claude-moose/src/discord/hooks.ts`

**To Keep (Reuse):**
- `/Users/moose/Downloads/projects/claude-moose/src/discord/contentParser.ts`
- `/Users/moose/Downloads/projects/claude-moose/src/discord/streamingMessage.ts`
- `/Users/moose/Downloads/projects/claude-moose/src/discord/embeds.ts`
- `/Users/moose/Downloads/projects/claude-moose/src/discord/phaseManager.ts` (simplify)
