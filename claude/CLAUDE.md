
# Start Every Session by Getting Your Bearings
1. `git status`
2. Read `README.md` and `docs/architecture.md` (if present).
3. Discover the canonical build/test/lint entrypoints (see “Commands” below). If discovered, use them consistently.


# Agent Ledger

**CRITICAL**: This is your cross-session memory. Future sessions query `~/.claude/LEDGER.jsonl` to recover context. You MUST write to it.

## On Session Start

Query for prior context:
```bash
PROJECT_PATH=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
jq -c '{id:._meta.id, ts:._meta.ts, title:.front.title, status:.front.status}' ~/.claude/LEDGER.jsonl 2>/dev/null | grep -i "$(basename "$PROJECT_PATH")" | tail -5
jq -r 'select(.front.path | test("'"$PROJECT_PATH"'"; "i")) | .body.lessons[]' ~/.claude/LEDGER.jsonl 2>/dev/null | sort -u
```

## On Session End — YOU MUST DO THIS

**Trigger**: When you have completed the user's request and are about to give your final response, FIRST append to the ledger, THEN respond.

**Non-negotiable**: Every session that does meaningful work MUST append a record. No exceptions. If you skip this, future sessions lose context.

```bash
cat >> ~/.claude/LEDGER.jsonl << 'RECORD'
{"_meta":{"id":"<uuid>","ts":"<iso8601>","v":1},"front":{"project":"<name>","path":"<abs-path>","title":"<one-line>","type":"feature|bugfix|refactor|docs|config|research","status":"completed|partial|failed","tags":[]},"body":{"input":"<original-request>","actions":["<what-you-did>"],"files":[{"path":"<file>","op":"C|M|D","why":"<purpose>"}],"decisions":[{"choice":"<what>","reason":"<why>"}],"lessons":["<patterns-for-future-sessions>"]},"history":{"embedded":false}}
RECORD
```

**Key fields**: `front.path` (absolute path for matching), `body.lessons` (what future sessions should know), `body.actions` (what you did).


# Testing Browser Changes
- Use the `dev-browser` Skill to test any front-end or UI/UX changes in the browser.


# Diff Hygiene (“Remove AI code slop”)
Before finishing, scan the diff and remove AI-generated slop introduced in this branch:
- comments a human wouldn’t write / inconsistent comment style
- abnormal defensive checks (extra try/catch, redundant validation) in trusted codepaths
- `any` casts (or similar type escapes) to bypass type issues
- inconsistent style vs surrounding code