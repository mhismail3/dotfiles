# Fix: iOS Context Manager Shows Empty System Prompt for Codex Models

## Problem

When switching from Claude Opus to GPT-5.2 Codex (or other Codex models), the iOS app's context manager sheet shows an empty system prompt container, even though the token count is correctly displayed.

## Root Cause

**Token calculation vs content return mismatch:**

1. `estimateSystemPromptTokens()` at `context-manager.ts:821-831` correctly calculates tokens from BOTH:
   - `getSystemPrompt()` (empty for Codex)
   - `getToolClarificationMessage()` (contains actual Tron context for Codex)

2. `getDetailedSnapshot()` at `context-manager.ts:509` only returns:
   ```typescript
   systemPromptContent: this.getSystemPrompt()
   ```
   For Codex, this returns `''` (empty string) because `buildSystemPrompt()` in `system-prompts.ts:222-225` explicitly returns empty for Codex providers.

3. iOS `SystemPromptSection` displays both values independently - resulting in token count showing but content empty.

## Solution

Return the **effective** system prompt content - whichever text actually contains the system-level context sent to the model.

## Implementation

### 1. Modify `getDetailedSnapshot()` in `packages/core/src/context/context-manager.ts`

**Lines 506-511** - Change from:
```typescript
return {
  ...snapshot,
  messages: detailedMessages,
  systemPromptContent: this.getSystemPrompt(),
  toolsContent: this.tools.map(t => `${t.name}: ${t.description || 'No description'}`),
};
```

**To:**
```typescript
// Use the effective system-level context: tool clarification for Codex, system prompt for others
const systemPrompt = this.getSystemPrompt();
const toolClarification = this.getToolClarificationMessage();
const effectiveSystemContent = toolClarification || systemPrompt;

return {
  ...snapshot,
  messages: detailedMessages,
  systemPromptContent: effectiveSystemContent,
  toolClarificationContent: toolClarification ?? undefined,
  toolsContent: this.tools.map(t => `${t.name}: ${t.description || 'No description'}`),
};
```

### 2. Update `DetailedContextSnapshot` interface in same file

**Around line 118** - Add optional field:
```typescript
export interface DetailedContextSnapshot extends ContextSnapshot {
  messages: DetailedMessageInfo[];
  /** Effective system-level context sent to the model */
  systemPromptContent: string;
  /** Raw tool clarification content if applicable (for debugging) */
  toolClarificationContent?: string;
  toolsContent: string[];
}
```

### 3. Update iOS data model in `packages/ios-app/Sources/Models/Payloads/ExtendedPayloads.swift`

**Line 254** - Add optional field:
```swift
struct DetailedContextSnapshotResult: Codable {
    let currentTokens: Int
    let contextLimit: Int
    let usagePercent: Double
    let thresholdLevel: String
    let breakdown: ContextSnapshotResult.ContextBreakdown
    let messages: [DetailedMessageInfo]
    let systemPromptContent: String
    let toolClarificationContent: String?  // Add this line
    let toolsContent: [String]
    let addedSkills: [AddedSkillInfo]
    let rules: LoadedRules?
}
```

### 4. No iOS view changes needed

`SystemPromptSection` in `ContextSectionViews.swift` already displays `systemPromptContent` correctly - it will now receive non-empty content for Codex models.

## Critical Files

- `packages/core/src/context/context-manager.ts` - Main logic change
- `packages/ios-app/Sources/Models/Payloads/ExtendedPayloads.swift` - Data model update

## Verification

1. Run tests: `bun run test` in packages/core
2. Manual test in iOS app:
   - Start a session with Claude Opus
   - Open context manager sheet - verify system prompt shows content
   - Switch to GPT-5.2 Codex
   - Open context manager sheet - verify system prompt shows "[TRON CONTEXT]..." content
   - Verify token count matches displayed content length
3. Test model switching back to Anthropic - content should revert to standard system prompt
