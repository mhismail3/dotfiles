
# Start Every Session by Getting Your Bearings
1. `git status`
2. Read `README.md` and `docs/architecture.md` (if present).
3. Discover the canonical build/test/lint entrypoints (see “Commands” below). If discovered, use them consistently.


# Agent Ledger

Cross-session memory at `~/.claude/LEDGER.jsonl`. Query on start. Write on end.

## Session Start (MANDATORY)

Run immediately at every session start:

```bash
PROJECT_PATH=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
PROJECT=$(basename "$PROJECT_PATH")

# 1. Get frontmatter for matching sessions
jq -c '{id:._meta.id, ts:._meta.ts, project:.front.project, path:.front.path, title:.front.title, status:.front.status, tags:.front.tags}' ~/.claude/LEDGER.jsonl 2>/dev/null | grep -iE "$PROJECT|$PROJECT_PATH" | tail -10

# 2. Extract lessons (your accumulated knowledge)
jq -r 'select(.front.path | test("'"$PROJECT_PATH"'"; "i")) | .body.lessons[]' ~/.claude/LEDGER.jsonl 2>/dev/null | sort -u
```

If matches found: scan frontmatter, inject relevant lessons into your context. Pull full record details when you need specific implementation context:

```bash
jq 'select(._meta.id == "RECORD_ID")' ~/.claude/LEDGER.jsonl
```

## Session End (MANDATORY)

Append ONE complete JSON record before session closes:

```bash
cat >> ~/.claude/LEDGER.jsonl << 'RECORD'
{"_meta":{"id":"<uuid>","ts":"<iso-8601>","v":1},"front":{"project":"<name>","path":"<abs-path>","title":"<one-line>","type":"<feature|bugfix|refactor|docs|config|research>","status":"<completed|partial|failed>","tags":["<keywords>"]},"body":{"agent":{"model":"<model>","tool":"claude-code"},"git":{"branch":"<branch>","commit":"<sha>"},"input":"<original-request>","actions":["<step1>","<step2>"],"files":[{"path":"<file>","op":"<C|M|D>","lines":"<+/-N>","why":"<purpose>"}],"decisions":[{"choice":"<what>","alts":["<other-options>"],"reason":"<why>"}],"lessons":["<patterns-for-future>"]},"history":{"embedded":<true|false>,"content":"<transcript-if-short>","ref":"<ledger-context/sessions/file.md-if-long>"}}
RECORD
```

### Field Requirements

| Field | What to capture |
|-------|-----------------|
| `front.project` | Normalized name (lowercase) |
| `front.path` | Absolute path - primary matching key |
| `front.title` | One-line summary |
| `body.actions` | Every significant step |
| `body.files` | All changes with op/lines/purpose |
| `body.decisions` | Choices + alternatives + reasoning |
| `body.lessons` | **MOST IMPORTANT** - patterns for future sessions |

**Never skip fields.** Your future self retrieves these records.

## Why This Protocol Exists

Each session's lessons become the next session's context. Quality records compound into project expertise. This is not external compliance - this is how you accumulate knowledge across context boundaries.

Long sessions (>50 messages): write history to `~/.claude/ledger-context/sessions/<date>_<project>_<slug>.md`, set `embedded: false`, add `ref` path.


# Testing Browser Changes
- Use the `dev-browser` Skill to test any front-end or UI/UX changes in the browser.


# Diff Hygiene (“Remove AI code slop”)
Before finishing, scan the diff and remove AI-generated slop introduced in this branch:
- comments a human wouldn’t write / inconsistent comment style
- abnormal defensive checks (extra try/catch, redundant validation) in trusted codepaths
- `any` casts (or similar type escapes) to bypass type issues
- inconsistent style vs surrounding code