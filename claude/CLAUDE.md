
# Start Every Session by Getting Your Bearings
1. `git status`
2. Read `README.md` and `docs/architecture.md` (if present).
3. Discover the canonical build/test/lint entrypoints (see "Commands" below). If discovered, use them consistently.
4. **If this session will do meaningful work**: Add "Update LEDGER.jsonl" to your todo list using TodoWrite. This is critical - the todo system will remind you throughout the session, preventing context decay from causing you to forget.


# Agent Ledger

**CRITICAL**: This is your cross-session memory. Future sessions query `~/.claude/LEDGER.jsonl` to recover context. You MUST write to it.

## On Session Start

1. Query for prior context:
```bash
PROJECT_PATH="$(git rev-parse --show-toplevel 2>/dev/null || pwd)" && jq -c '{id:._meta.id, ts:._meta.ts, title:.front.title, status:.front.status}' ~/.claude/LEDGER.jsonl 2>/dev/null | grep -i "$(basename "$PROJECT_PATH")" | tail -5
```
```bash
PROJECT_PATH="$(git rev-parse --show-toplevel 2>/dev/null || pwd)" && jq -r 'select(.front.path | test("'"$PROJECT_PATH"'"; "i")) | .body.lessons[]' ~/.claude/LEDGER.jsonl 2>/dev/null | sort -u
```

2. **Add to todo list** (if meaningful work expected):
```
TodoWrite: Add item "Update LEDGER.jsonl before final response" with status "pending"
```
This ensures the system reminds you throughout the session. Context decay over long sessions WILL cause you to forget otherwise.

## On Session End — YOU MUST DO THIS

**Trigger**: When you have completed the user's request and are about to give your final response, FIRST append to the ledger, THEN respond.

**Non-negotiable**: Every session that does meaningful work MUST append a record. No exceptions. If you skip this, future sessions lose context.

**Process**:
1. Mark the "Update LEDGER.jsonl" todo as "in_progress"
2. Append the record (see template below)
3. Mark the todo as "completed"
4. Then give your final response

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