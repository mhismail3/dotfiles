# Model Picker Cleanup Plan

## Summary
Reorganize the model picker to reorder sections, move GPT 5.1 Codex Max and Gemini 2.5 to legacy, remove Gemini 2.0 entirely, and consolidate all legacy models into a single section.

## Changes

### 1. Backend: Remove Gemini 2.0 models
**File:** `packages/core/src/providers/google.ts`

Remove from `GEMINI_MODELS`:
- `gemini-2.0-flash`
- `gemini-2.0-flash-lite`

### 2. iOS: Reorganize Model Picker Sections
**File:** `packages/ios-app/Sources/Views/ModelPickerMenu.swift`

**New section order:**
1. Latest Anthropic (4.5) - sparkles icon
2. Latest GPT (5.2 Codex only) - bolt icon
3. Gemini 3 - atom icon
4. Legacy (unified) - clock icon

**New categorization logic:**

| Category | Filter |
|----------|--------|
| `latestAnthropicModels` | Anthropic + `is45Model` (unchanged) |
| `latestCodexModels` | Codex + contains "5.2" |
| `gemini3Models` | Gemini + `isGemini3` (unchanged) |
| `legacyModels` | Combined: legacy Anthropic + Codex 5.1 + Gemini 2.5 |

**Remove:** `codexModels` and `geminiLegacyModels` (replaced by combined logic)

**Body changes:**
- Remove separate Codex section
- Remove separate Gemini legacy section
- Single unified legacy section at the bottom

## Verification
1. Run build: `bun run build`
2. Run tests: `bun run test`
3. Open iOS app in Xcode, verify model picker shows:
   - New Session sheet: correct ordering and grouping
   - Chat view pill picker: same ordering and grouping
   - No Gemini 2.0 models appear
   - GPT 5.1 Codex Max appears in Legacy section
   - Gemini 2.5 models appear in Legacy section
