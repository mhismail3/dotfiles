# Telegram Bot Formatting Polish

## Issues to Fix

### 1. Inconsistent Path Formatting
**Problem**: "Downloads/projects" not formatted as code, but "claude-moose/" is.

**Root cause** (`formatter.ts:168-171`): Directory regex requires paths to start with `/`, `~/`, or `./`:
```typescript
/(?<!<code>|href="|>)((?:\/|~\/|\.\/)?[a-zA-Z0-9_\-]+(?:\/[a-zA-Z0-9_\-]+)*\/)(?!<\/code>)/g
```

This misses relative paths like `Downloads/projects` that don't have the leading prefix.

**Fix**: Improve heuristics to catch:
- Paths containing `/` (like `Downloads/projects`)
- Hidden files starting with `.` (like `.DS_Store`, `.env`)

### 2. Separate Stats Messages
**Problem**: Cost and activity summary sent as TWO separate messages.

**Root cause** (`processor.ts:121-132`):
```typescript
// Two separate sendStatus calls
this.sender.sendStatus(this.chatId, `\n${summary}`);  // Activity
this.sender.sendStatus(this.chatId, `💰 Cost: $${cost}`);  // Cost
```

**Fix**: Combine into ONE consolidated stats message.

### 3. Grammar: "1 commands"
**Problem**: Should be "1 command" (singular).

**Root cause** (`hooks.ts:150`):
```typescript
if (stats.commandsRun > 0) parts.push(`⚡ ${stats.commandsRun} commands`);
```

**Fix**: Use singular/plural based on count.

---

## Implementation

### File 1: `src/telegram/formatter.ts`

Update `applyHeuristicFormatting()`:

```typescript
function applyHeuristicFormatting(text: string): string {
  // Simple relative paths containing / (e.g., Downloads/projects)
  text = text.replace(
    /\b([A-Za-z][\w-]*(?:\/[\w.-]+)+)\b/g,
    (match) => {
      // Skip if already in code tags or is a URL
      if (match.includes('://')) return match;
      return `<code>${match}</code>`;
    }
  );

  // Dotfiles: .DS_Store, .env, .gitignore
  text = text.replace(
    /(?<![/\w])(\.[a-zA-Z][\w.-]*)\b/g,
    '<code>$1</code>'
  );

  // ... existing patterns ...
}
```

### File 2: `src/claude/hooks.ts`

Update `formatActivitySummary()` with pluralization:

```typescript
function plural(count: number, singular: string, pluralForm?: string): string {
  return count === 1 ? singular : (pluralForm || singular + 's');
}

export function formatActivitySummary(stats: ActivityStats): string | null {
  const parts: string[] = [];

  if (stats.filesRead > 0)
    parts.push(`📖 ${stats.filesRead} ${plural(stats.filesRead, 'file')} read`);
  if (stats.filesEdited > 0)
    parts.push(`🔧 ${stats.filesEdited} ${plural(stats.filesEdited, 'file')} edited`);
  if (stats.filesWritten > 0)
    parts.push(`✏️ ${stats.filesWritten} ${plural(stats.filesWritten, 'file')} written`);
  if (stats.commandsRun > 0)
    parts.push(`⚡ ${stats.commandsRun} ${plural(stats.commandsRun, 'command')}`);
  if (stats.searches > 0)
    parts.push(`🔍 ${stats.searches} ${plural(stats.searches, 'search', 'searches')}`);

  if (parts.length === 0) return null;
  return parts.join(' · ');
}
```

### File 3: `src/claude/processor.ts`

Update `processResult()` to send ONE combined stats message:

```typescript
private async processResult(message: Extract<SDKMessage, { type: 'result' }>): Promise<void> {
  await this.flush();

  if (message.subtype === 'success') {
    // Build ONE combined stats message
    const statsParts: string[] = [];

    const activitySummary = formatActivitySummary(this.stats);
    if (activitySummary) {
      statsParts.push(activitySummary);
    }

    if (message.total_cost_usd > 0.01) {
      statsParts.push(`💰 $${message.total_cost_usd.toFixed(4)}`);
    }

    // Send ONE message with all stats
    if (statsParts.length > 0) {
      this.sender.sendStatus(this.chatId, statsParts.join(' · '));
    }
  }
  // ... error handling unchanged ...
}
```

**Result**: `📖 3 files read · ⚡ 1 command · 💰 $0.0378`

---

## Files to Modify

| File | Changes |
|------|---------|
| `src/telegram/formatter.ts` | Improve path/dotfile detection in `applyHeuristicFormatting()` |
| `src/claude/hooks.ts` | Add `plural()` helper, fix grammar in `formatActivitySummary()` |
| `src/claude/processor.ts` | Consolidate stats into ONE message in `processResult()` |
