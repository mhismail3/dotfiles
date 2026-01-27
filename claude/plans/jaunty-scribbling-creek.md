# Spells Implementation Plan

## Overview
Implement "Spells" as ephemeral skills that apply only to a single prompt and are automatically removed afterward. Spells use the same source folder as skills (`~/.tron/skills/`) but differ in persistence behavior.

**Key Difference:**
- **Skills**: Persist in session via `skill.added` events, included in all subsequent prompts until removed
- **Spells**: Ephemeral - injected into the current prompt only, no events created, automatically gone after the turn

## Critical: Removal Instruction Handling

When skills are removed, the system injects a `<removed-skills>` block telling the LLM to stop applying those skills. For spells, we need similar behavior.

### Skills: Re-adding after removal
**Already handled** (skill-tracker.ts:62-63): When a skill is re-added, it's automatically removed from `removedSkillNames`:
```typescript
addSkill(skillName, source, addedVia, eventId): void {
  this.addedSkills.set(skillName, { eventId, source, addedVia });
  // If re-adding a previously removed skill, take it off the removed list
  this.removedSkillNames.delete(skillName);  // ✓ Already implemented
}
```

### Spells: Re-using after previous use
Spells are ephemeral, so the semantics differ from skills:

1. **Use spell A (turn 1)** → add to `usedSpellNames`, inject content
2. **Turn 2 (no spell A)** → spell A in removal instruction
3. **Re-use spell A (turn 3)** → inject content, **exclude from removal instruction for THIS prompt only**
4. **Turn 4 (no spell A)** → spell A back in removal instruction

**Key insight**: We do NOT remove from `usedSpellNames` when re-using a spell. Instead, we conditionally exclude it from the removal instruction only for the current prompt where it's being used. After that prompt, it goes back into the removal instruction.

**Implementation**: Add `usedSpellNames: Set<string>` to `SkillTracker`:
- When spell is used → add to `usedSpellNames` (idempotent - Set handles duplicates)
- When building removal instruction → include `usedSpellNames` EXCEPT any spells being used in current prompt
- On context clear/compact → clear `usedSpellNames`

This ensures robust behavior:
- Re-using a spell works correctly (excluded from removal only for that prompt)
- Subsequent prompts still get the removal instruction
- No edge cases with multiple re-uses (Set is idempotent)

## Files to Modify

### Backend (TypeScript)

#### 1. `packages/agent/src/orchestrator/types.ts`
Add `spells` field to `AgentRunOptions`:
```typescript
export interface AgentRunOptions {
  // ... existing fields ...
  skills?: PromptSkillRef[];
  /** Spells (ephemeral skills) - injected for one prompt only, not tracked */
  spells?: PromptSkillRef[];
  // ...
}
```

#### 2. `packages/agent/src/skills/skill-tracker.ts`
Add spell tracking to SkillTracker:
```typescript
class SkillTracker {
  // ... existing fields ...

  /** Spells used in this session (for "stop following" instruction on next prompts) */
  private usedSpellNames: Set<string> = new Set();

  /** Record that a spell was used (adds to removal list for subsequent prompts) */
  addUsedSpell(spellName: string): void {
    this.usedSpellNames.add(spellName);
  }

  /** Get spell names that were used (for removal instruction) */
  getUsedSpellNames(): string[] {
    return Array.from(this.usedSpellNames);
  }

  /** Clear also clears used spells */
  clear(): void {
    this.addedSkills.clear();
    this.removedSkillNames.clear();
    this.usedSpellNames.clear();  // NEW
  }
}
```

#### 3. `packages/agent/src/orchestrator/skill-loader.ts`
Modify `loadSkillContextForPrompt()` to handle spells:
- Collect spell names from `options.spells` (ephemeral)
- Merge with skill names for content loading
- **Do NOT create events for spells** - just add to `usedSpellNames` set
- Include used spells in removal instruction on subsequent prompts
- Inject both skills and spells into the same `<skills>` context block

Key changes:
```typescript
// 1. Collect current prompt's spell names FIRST (for conditional exclusion)
const currentSpellNames = new Set<string>();
if (options.spells && options.spells.length > 0) {
  for (const spell of options.spells) {
    currentSpellNames.add(spell.name);
  }
}

// 2. Get previously used spells (for removal instruction)
const usedSpells = skillTracker.getUsedSpellNames();

// 3. Build removal instruction including:
//    - Explicitly removed skills (removedSkillNames)
//    - Previously used spells, EXCLUDING any being re-used in current prompt
const removedSkills = skillTracker.getRemovedSkillNames();
const allRemoved: string[] = [...removedSkills];

for (const spellName of usedSpells) {
  // Only include if NOT being re-used in current prompt
  // This handles the re-use case: spell is excluded from removal for THIS prompt
  // but will be back in removal instruction on subsequent prompts
  if (!currentSpellNames.has(spellName)) {
    allRemoved.push(spellName);
  }
}

// 4. Add spells to skillNames for content loading + track as used
if (options.spells && options.spells.length > 0) {
  for (const spell of options.spells) {
    skillNames.add(spell.name);
    // Track as used - idempotent (Set handles duplicates)
    // Note: We DO NOT remove from usedSpellNames when re-using
    // The spell stays in usedSpellNames forever (until context clear)
    skillTracker.addUsedSpell(spell.name);
  }
}

// 5. Build <removed-skills> block if there are any removed skills/spells
if (allRemoved.length > 0) {
  const skillList = allRemoved.map((s) => `@${s}`).join(', ');
  removedSkillsInstruction = `<removed-skills>
CRITICAL: The following skills/spells have been REMOVED from this session: ${skillList}
...
</removed-skills>`;
}
```

#### 4. `packages/agent/src/rpc/types.ts`
Add `spells` to RPC params type (if exists, or handled in gateway adapter).

#### 5. `packages/agent/src/gateway/rpc/adapters/agent.adapter.ts`
Pass `spells` from RPC params to `runAgent()` options.

### iOS App (Swift)

#### 6. `packages/ios-app/Sources/Theme/TronColors.swift`
Add pink color for spells:
```swift
static let tronPink = Color(hex: "#EC4899")      // Pink-500
static let tronPinkLight = Color(hex: "#F472B6") // Pink-400
```

#### 7. `packages/ios-app/Sources/Models/RPCTypes.swift`
Add `spells` to `AgentPromptParams`:
```swift
struct AgentPromptParams: Encodable {
    // ... existing fields ...
    let skills: [SkillReferenceParam]?
    let spells: [SkillReferenceParam]?  // NEW

    init(/* ... */, skills: [Skill]? = nil, spells: [Skill]? = nil) {
        // ...
        self.skills = skills?.map { SkillReferenceParam(from: $0) }
        self.spells = spells?.map { SkillReferenceParam(from: $0) }
    }
}
```

#### 8. `packages/ios-app/Sources/Views/SkillChip.swift`
Refactor to support both skills and spells via a `mode` parameter:
```swift
enum ChipMode {
    case skill      // Cyan color, sparkles icon
    case spell      // Pink color, wand.and.stars icon
}

struct SkillChip: View {
    let skill: Skill
    var mode: ChipMode = .skill
    // ... rest of implementation with color/icon based on mode
}
```

Add `SpellChipRow` and `MessageSpellChips` variants (or parameterize existing).

#### 9. `packages/ios-app/Sources/Views/InputBar/InputBar.swift`
Add spell state and `%` trigger character detection:
```swift
@Binding var selectedSpells: [Skill]  // NEW
var onSpellSelect: ((Skill) -> Void)?  // NEW
var onSpellRemove: ((Skill) -> Void)?  // NEW

// Detect `%skillname` pattern for spells
private func detectSpellMention(in newText: String) { ... }
```

Display spell chips in content area with pink styling.

#### 10. `packages/ios-app/Sources/Views/InputBar/ContentAreaView.swift`
Display both skill chips and spell chips:
```swift
struct ContentAreaView: View {
    let selectedSkills: [Skill]
    let selectedSpells: [Skill]  // NEW
    // ... render both with different colors
}
```

#### 11. `packages/ios-app/Sources/Views/SpellMentionPopup.swift` (NEW)
Create spell mention popup triggered by `%`:
- Similar to `SkillMentionPopup` but with pink theming
- Header: "Spells" with wand icon
- Reuse skill data from `SkillStore`

#### 12. `packages/ios-app/Sources/Views/ChatView.swift`
- Add `@State private var selectedSpells: [Skill] = []`
- Pass spells to InputBar
- **Clear spells after send** (they're one-time)
- Pass spells to `sendPrompt()` call

#### 13. `packages/ios-app/Sources/Services/RPCClient.swift`
Add `spells` parameter to `sendPrompt()`:
```swift
func sendPrompt(
    sessionId: String,
    prompt: String,
    // ... existing params ...
    skills: [Skill]?,
    spells: [Skill]?  // NEW
) async throws -> AgentPromptResult
```

## Implementation Order (Test-Driven Development)

### Phase 1: Backend - Tests First
1. **Run existing tests to establish baseline**:
   ```bash
   bun run test -- packages/agent/src/skills/
   ```
   Ensure all existing skill tests pass before any changes.

2. **Write new tests for spell functionality** (`packages/agent/src/skills/__tests__/skill-tracker.test.ts`):
   - Test `addUsedSpell()` adds to set
   - Test `getUsedSpellNames()` returns array
   - Test `clear()` clears used spells
   - Test used spells persist across calls (not removed on re-add)

3. **Write tests for skill-loader spell handling** (`packages/agent/src/orchestrator/__tests__/skill-loader.test.ts`):
   - Test spells are injected but no events created
   - Test spells appear in `<skills>` context block
   - Test used spells appear in removal instruction on next prompt
   - Test re-used spell is excluded from removal instruction for that prompt
   - Test re-used spell is back in removal instruction on subsequent prompt

4. **Implement backend changes** (tests should fail, then pass):
   - `types.ts` - Add spells to AgentRunOptions
   - `skill-tracker.ts` - Add usedSpellNames tracking
   - `skill-loader.ts` - Handle spells, add to usedSpellNames, include in removal instruction
   - RPC adapter - Wire through spells parameter

5. **Verify all tests pass**:
   ```bash
   bun run build && bun run test
   ```

### Phase 2: iOS App UI
6. **iOS App implementation**:
   - `TronColors.swift` - Add pink color
   - `SkillChip.swift` - Add mode parameter for skill/spell styling
   - `SpellMentionPopup.swift` - Create spell autocomplete popup (triggered by `%`)
   - `ContentAreaView.swift` - Display spell chips
   - `InputBar.swift` - Add spell state and `%` detection
   - `RPCTypes.swift` - Add spells to params
   - `RPCClient.swift` - Pass spells in RPC call
   - `ChatView.swift` - Manage spell state, clear after send

7. **Build iOS app** and test manually in simulator

## Verification

### Pre-Implementation: Establish Baseline
```bash
bun run build && bun run test
```
Record which tests pass. All existing tests MUST continue to pass after implementation.

### Unit Tests to Write (Before Implementation)

**SkillTracker tests** (`packages/agent/src/skills/__tests__/skill-tracker.test.ts`):
```typescript
describe('spell tracking', () => {
  it('addUsedSpell adds to usedSpellNames set', () => { ... });
  it('getUsedSpellNames returns array of used spells', () => { ... });
  it('addUsedSpell is idempotent (set behavior)', () => { ... });
  it('clear() clears usedSpellNames', () => { ... });
  it('used spells persist across multiple addUsedSpell calls', () => { ... });
});
```

**SkillLoader tests** (`packages/agent/src/orchestrator/__tests__/skill-loader.test.ts`):
```typescript
describe('spell injection', () => {
  it('spells are injected into <skills> context block', () => { ... });
  it('spells do NOT create skill.added events', () => { ... });
  it('used spells appear in removal instruction on next prompt', () => { ... });
  it('re-used spell is excluded from removal instruction for that prompt', () => { ... });
  it('re-used spell is back in removal instruction on subsequent prompt', () => { ... });
  it('mixed skills + spells work correctly', () => { ... });
});

describe('existing skill functionality (regression)', () => {
  it('skills still create skill.added events', () => { ... });
  it('removed skills still appear in removal instruction', () => { ... });
  it('re-added skill is removed from removal instruction', () => { ... });
});
```

### Integration Tests (Manual)

1. **Backend test - spell injection**:
   - Send RPC with `spells: [{name: "test-skill", source: "global"}]`
   - Verify spell content appears in `<skills>` block
   - Verify NO `skill.added` event is created

2. **Backend test - spell removal instruction**:
   - Send prompt with spell A
   - Send second prompt WITHOUT spell A
   - Verify second prompt includes spell A in `<removed-skills>` block

3. **Backend test - spell re-use**:
   - Send prompt with spell A (turn 1)
   - Send prompt WITHOUT spell A (turn 2) → A in removal instruction
   - Send prompt WITH spell A again (turn 3) → A NOT in removal instruction, A injected
   - Send prompt WITHOUT spell A (turn 4) → A back in removal instruction

4. **Backend test - skill re-add after removal** (regression):
   - Add skill B (persistent)
   - Remove skill B → B in removal instruction
   - Re-add skill B → B NOT in removal instruction, B injected

5. **iOS integration test**:
   - Type `%` to trigger spell popup (pink themed)
   - Select a spell - appears as pink chip
   - Send message - spell injected into prompt
   - Next message - spell chip is gone (cleared automatically)
   - Re-use same spell with `%` → works correctly

### Post-Implementation: Verify No Regressions
```bash
bun run build && bun run test
```
All original tests PLUS new spell tests must pass.
