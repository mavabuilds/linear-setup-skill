---
name: linear-sync
description: Bidirectional sync between Linear issues and local .linear/issues/*.md files. Pull issues from Linear, edit locally, push changes back. Use when the user asks to pull, push, or sync a Linear issue.
allowed-tools: Bash(linear:*), Bash(*/linear-pull.sh:*), Bash(*/linear-push.sh:*), Bash(*/linear-pull-all.sh:*), Read, Write, StrReplace
---

# Linear Issue Sync

Bidirectional sync between Linear issues and local markdown files in `.linear/issues/`.

## When to use

- User says "pull ENG-123" or "pull issue ENG-123" — fetch from Linear to local
- User says "pull all my issues" or "pull all issues" — bulk pull
- User says "push ENG-123" — push local changes back to Linear
- User says "sync ENG-123" — pull then push (or just pull if no local changes)
- User edits a `.linear/issues/*.md` file and wants to update Linear

## Configuration

Set default team in `.linear.toml` at the repo root:

```toml
[issue.create]
team = "ENG"           # your team key (run 'linear team list' to find it)
```

No organization slug is needed — issue URLs are fetched directly from the Linear API.

## File format

Each issue lives at `.linear/issues/<ISSUE_ID>.md` with YAML frontmatter:

```yaml
---
linear_id: ENG-123
url: https://linear.app/your-org/issue/ENG-123
title: Example issue title
status: In Progress
priority: 2
team: ENG
project: My Project
assignee: Jane Smith
last_synced: 2026-01-15T10:00:00Z
---

(issue description body in markdown)
```

- `linear_id` is the canonical key
- `url` is fetched from Linear's API (org-specific URL is resolved automatically)
- `last_synced` tracks when the file was last synced with Linear
- The body below the frontmatter is the issue description (same markdown Linear stores)

## Commands

### Pull an issue from Linear

```bash
scripts/linear-pull.sh ENG-123
```

Fetches the issue from Linear's API and writes/overwrites `.linear/issues/ENG-123.md`.
If the local file has uncommitted changes, it will abort unless `--force` is given.

### Push local changes to Linear

```bash
scripts/linear-push.sh ENG-123
```

Reads `.linear/issues/ENG-123.md`, extracts the body, and updates the Linear issue description.
Also pushes metadata changes (title, status, priority) from frontmatter.
If Linear was updated since last sync, it aborts unless `--force` is given.

### Pull all issues (bulk)

```bash
scripts/linear-pull-all.sh --team ENG
scripts/linear-pull-all.sh --team ENG --all-states
scripts/linear-pull-all.sh --team ENG --state backlog --all-assignees
scripts/linear-pull-all.sh --team ENG --force
```

Pulls all issues matching the filters into `.linear/issues/`. Calls `linear-pull.sh` for each one.

Options:
- `--team <key>` (required) — team key. Run `linear team list` to see available teams.
- `--state <state>` — filter by state (default: `started`). Values: triage, backlog, unstarted, started, completed, canceled
- `--all-states` — pull from all states
- `--assignee <name>` — filter by username (default: your issues)
- `--all-assignees` — pull for everyone on the team
- `--force` — overwrite local conflicts

### Sync (pull then push)

There is no single sync command. To sync:

1. Pull first to get any remote changes: `scripts/linear-pull.sh ENG-123`
2. Make your edits to the local file
3. Push when ready: `scripts/linear-push.sh ENG-123`

## Setup

Before the first pull, ensure the `.linear/` directory exists and is gitignored:

```bash
mkdir -p .linear/issues
grep -qxF '.linear/' .gitignore 2>/dev/null || echo '.linear/' >> .gitignore
```

The agent should run this automatically on the first pull if `.linear/issues/` doesn't exist yet.

## Discovering your team

If you don't know your team key, run:

```bash
linear team list
```

This lists all teams in your Linear workspace with their keys (e.g., ENG, CORE, PLAT).

## Workflow for the agent

When the user asks to **pull** an issue:
1. Run `scripts/linear-pull.sh <ID>`
2. Read the resulting `.linear/issues/<ID>.md` and summarize what was pulled

When the user asks to **push** an issue:
1. Run `scripts/linear-push.sh <ID>`
2. Confirm the push succeeded

When the user asks to **edit and push** an issue:
1. Read `.linear/issues/<ID>.md`
2. Use StrReplace to make the requested changes to the body
3. Run `scripts/linear-push.sh <ID>`

When the user asks to **pull a new issue** (not yet tracked locally):
1. Ask for the issue identifier (e.g. ENG-42) if not provided
2. Run `scripts/linear-pull.sh <ID>`
3. The file will be created at `.linear/issues/<ID>.md`

When the user asks to **pull all issues** (bulk):
1. Determine the team — check `.linear.toml` for a default, or run `linear team list`, or ask the user
2. Run `scripts/linear-pull-all.sh --team <TEAM>` (add `--all-states` if they want everything)
3. Summarize how many issues were pulled

## Conflict handling

Both scripts detect conflicts:
- **Pull** checks if the local file has uncommitted git changes since `last_synced`
- **Push** checks if Linear's `updatedAt` is newer than `last_synced`

If a conflict is detected, the script prints a warning and exits. Use `--force` to override.
