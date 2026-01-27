# Fix: Plan Mode Not Being Triggered

## Root Cause Analysis

The plan mode feature was implemented but **frontmatter is not being passed through the skill loading chain**, causing plan mode detection to fail silently.

### The Bug Location

**File**: `packages/server/src/rpc/adapters/agent.adapter.ts:61-65`

```typescript
// CURRENT (BUG):
const loadedSkills: Array<{ name: string; content: string }> = [];
...
loadedSkills.push({ name: skill.name, content: skill.content });
// ❌ frontmatter is NOT included
```

### The Chain That Breaks

1. **SkillRegistry.get()** returns `SkillMetadata` which HAS `frontmatter: SkillFrontmatter` (including `planMode?: boolean`)
2. **agent.adapter.ts** calls registry but only passes `{ name, content }` - **drops frontmatter here**
3. **skill-loader.ts:236** checks `skill.frontmatter?.planMode === true` - **always undefined**
4. Plan mode never triggers

### Evidence from Logs

```
[SKILL-LOADER] Loaded skill content|{"contentLength":3792,"contentPreview":"# Plan Skill\n..."}
[SKILL-LOADER] Returning loaded skills|{"requestedCount":1,"loadedCount":1,"loadedNames":["plan"]}
```
- Note: no frontmatter in logs
- Note: no `[SKILL] Detected planMode skill` log message
- Note: no `plan.mode_entered` event in database

---

## Fix

### File: `packages/server/src/rpc/adapters/agent.adapter.ts`

**Change** (lines 61-65):

```typescript
// FROM:
const loadedSkills: Array<{ name: string; content: string }> = [];
for (const name of skillNames) {
  const skill = registry.get(name);
  if (skill) {
    loadedSkills.push({ name: skill.name, content: skill.content });

// TO:
const loadedSkills: Array<{ name: string; content: string; frontmatter?: Record<string, unknown> }> = [];
for (const name of skillNames) {
  const skill = registry.get(name);
  if (skill) {
    loadedSkills.push({
      name: skill.name,
      content: skill.content,
      frontmatter: skill.frontmatter,
    });
```

**Also update logging** (line 66-70):

```typescript
logger.info('[SKILL-LOADER] Loaded skill content', {
  name: skill.name,
  contentLength: skill.content.length,
  contentPreview: skill.content.substring(0, 100) + '...',
  hasFrontmatter: !!skill.frontmatter,
  planMode: skill.frontmatter?.planMode,  // Add for debugging
});
```

---

## Verification

After fix, test by:

1. Start tron server
2. Open iOS app, create session
3. Tap + → "Draft a Plan"
4. Send: "Draft a plan for adding a logout button"
5. **Expected logs**:
   ```
   [SKILL-LOADER] Loaded skill content|{...,"planMode":true}
   [SKILL] Detected planMode skill, entering plan mode
   [SKILL] Plan mode entered via skill
   ```
6. **Expected event**: `plan.mode_entered` in database
7. **Expected behavior**: Agent should use AskUserQuestion for approval

---

## Secondary Issue: AskUserQuestion Not Being Called

Even after plan mode enters, the agent may not call AskUserQuestion because:

1. The SKILL.md instructions say to use it for approval
2. But there's no enforcement mechanism - the LLM might ignore it
3. The skill instructions need to be clearer about the approval flow

### Recommendation

Update `~/.tron/skills/plan/SKILL.md` Phase 4 to be more emphatic:

```markdown
### Phase 4: Approval

**CRITICAL**: You MUST use `AskUserQuestion` to get explicit approval before exiting plan mode.

Call AskUserQuestion with:
- Summary of the plan
- Question: "Should I proceed with this implementation?"
- Options: "Yes, implement" / "No, revise plan"

Do NOT proceed to implementation without explicit user approval through AskUserQuestion.
```
