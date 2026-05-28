# Mac Mini Codex Handoff Prompt

Use this prompt in Codex on the freshly reset Mac Mini after cloning this dotfiles repo.

```text
You are running on Moose's freshly reset Mac Mini. Your job is to continue the home-device architecture setup specifically for the Mac Mini personal-server role.

Current target architecture:
- Mac Mini = personal-server: owns NAS read/write access, Syncthing hub duties, personal indexes, review queues, approved personal-file application, and lightweight always-on coordination.
- MacBook Server = agent-server: runs Codex agents, local models, experiments, and scheduled runner jobs. It may read personal context through approved read-only mirrors/mounts, but must not directly write canonical personal files.
- GitHub is canonical for code. Mission Control is canonical for agent-visible work records.
- Personal-file writes by agents must go through AgentOutbox -> ReviewQueue -> human approval -> apply from personal-server with audit and rollback.

Start by getting your bearings:
1. Run `git status` in `~/.dotfiles`.
2. Read `README.md`, `codex/README.md`, and `codex/mac-mini-handoff-prompt.md`.
3. Check the active branch. It should be `mac-mini`. If not, run `git fetch origin && git checkout mac-mini && git pull --rebase`.
4. Inspect `setup.sh`, `Brewfile`, and `macos/.macos` before running anything.

Then implement and verify in small steps:
1. Run `./setup.sh` from `~/.dotfiles` and follow the prompts.
2. Authenticate the required apps manually when prompted: Tailscale, Codex, GitHub CLI, Synology Drive or NAS access, Docker Desktop if needed.
3. Run `~/.codex/portable/codex_portable.py sync-pull --yes` if a CodexPortable backup exists, then run `~/.codex/portable/codex_portable.py doctor --verify-remote`.
4. Verify Tailscale identifies this device as the Mac Mini and can reach the other tailnet devices.
5. Update dotfiles as needed for the Mac Mini personal-server role. Preserve existing Claude setup; do not remove or rewrite it.

Mac Mini personal-server changes to add if not already present:
- A documented folder layout under `~/HomeServer`:
  - `PersonalVault`
  - `PersonalWorking`
  - `AgentReadable`
  - `AgentOutbox`
  - `ReviewQueue`
  - `Audit`
  - `Rollback`
- Idempotent setup logic that creates those directories with conservative permissions.
- Clear docs for NAS mount expectations: Mac Mini has read/write access; agent server gets read-only access later.
- Syncthing guidance/config plan with Mac Mini as the hub for `PersonalWorking`.
- Agent outbox/review queue rules that prevent agents from directly mutating canonical personal files.
- Any LaunchAgent or maintenance scripts should be explicit, minimal, and documented before enabling.

Safety rules:
- Do not commit secrets, auth tokens, cookies, private keys, or local personal data.
- Do not copy Codex `auth.json`; log in separately on this Mac.
- Do not sync Codex runtime DBs, plugin caches, worktrees, or temp files.
- Do not run destructive cleanup or broad deletes without explicit approval.
- Keep project code worktrees out of filesystem sync; use GitHub clones and branches.

Before finishing:
1. Run `zsh -n setup.sh`.
2. Run `python3 -m py_compile codex/portable/codex_portable.py` with a Python that supports `tomllib`.
3. Run `git diff --check`.
4. Run any new validation or dry-run command you add.
5. Commit changes on branch `mac-mini` with a concise message.
6. Push `mac-mini` to `origin`.

Final response should include:
- What changed.
- What setup commands ran and their result.
- What remains manual.
- The pushed branch and commit hash.
```
