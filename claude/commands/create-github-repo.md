# GitHub Repository Creation

When asked to create a GitHub repository from a local folder:

## Quick Command
gh repo create <repo-name> --public --source=. --push

## Prerequisites Check
1. Verify git repo exists: `git status`
2. If not a repo:
   git init && git add . && git commit -m "Initial commit"

## Options
- `--public` or `--private` for visibility
- `--source=.` uses current directory
- `--push` pushes immediately after creation

## Permissions Required
- `network` (GitHub API)
- `git_write` (push operations)

## Output
Returns the repository URL (e.g., `https://github.com/username/repo-name`)
