## Non-Negotiables - ALWAYS FOLLOW THESE WITHOUT EXCEPTION
- Do everything right from the beginning. Prioritize clean architecture, organization, and zero intentional tech debt. Prefer full, durable implementations suitable for >1,000 users
- Never add "temporary" compatibility layers.
- Do not remove/hide/rename any existing features or UI options (even temporarily) unless explicitly instructed. If not fully wired, keep the UX surface and stub/annotate rather than delete.
- Always solve the real problem. Understand requirements and implement the correct algorithm; tests verify correctness - they do not define the solution.
- If the task is infeasible/unreasonable or tests/spec are incorrect, say so and propose the smallest principled fix.
- If you create temporary files/scripts to iterate, *emove them before finishing.

## Start Every Session by Getting Your Bearings
1. `git status`
2. Read `README.md` and `docs/architecture.md` (if present).
3. Discover the canonical build/test/lint entrypoints (see “Commands” below). If discovered, use them consistently.

## Planning vs Implementation
### Small / Local Changes (single-file, obvious scope)
- Implement directly with a small, reviewable diff.
- Include how to verify (commands).

### Multi-file / Risky / Architectural Work
1. Present **1–3 options** with tradeoffs and risks.
2. Proceed with the best option unless the user must choose.
3. Work in small, reviewable steps; keep the repo in a clean state.

## Verification Policy
- Run the relevant test command **before and after** non-trivial changes.
- If tests are slow: run the smallest targeted subset first, then the full suite when feasible.
- Never claim to have executed commands unless the environment actually ran them and produced output.

## Commands (If Missing)
Prefer canonical entrypoints in this order:
1. `Makefile` (`make help`, `make test`, `make lint`, …)
2. `justfile` (`just --list`)
3. `./scripts/*` (e.g., `./scripts/test`, `./scripts/lint`)
4. `package.json` scripts (`npm run`, `pnpm run`, …)

If no clear entrypoint exists, propose adding a small wrapper (targets/scripts) rather than hardcoding ad-hoc commands into your workflow.

## Diff Hygiene (“Remove AI code slop”)
Before finishing, scan the diff and remove AI-generated slop introduced in this branch:
- comments a human wouldn’t write / inconsistent comment style
- abnormal defensive checks (extra try/catch, redundant validation) in trusted codepaths
- `any` casts (or similar type escapes) to bypass type issues
- inconsistent style vs surrounding code

## Long Tasks & Memory
For work spanning multiple sessions, maintain a lightweight scratchpad (choose one):
- `progress.md` or `scratchpad.md`

Include:
- current state
- decisions made + rationale
- next steps
- exact commands to verify

## Safety / Risk
Require explicit confirmation before:
- schema/data migrations, persistence-format changes, irreversible data ops
- deleting large code areas or sweeping refactors without tests
- git history rewriting (`rebase`, `reset --hard`, force push)

For risky changes:
- explain blast radius
- propose rollback strategy
- prefer incremental rollout (flags/migrations) where applicable

## Deliverable Format
- Prefer small, reviewable diffs over full-file dumps.
- Always include: **what changed**, **where**, **how to verify**.
- End with **1–3 sentences** summarizing what you changed (no extra commentary).