---
name: linear
description: "Set up and use Linear CLI for issue management. Installs schpet/linear-cli, authenticates, and copies agent skills (CLI reference + issue sync) into the workspace. Use when onboarding a new engineer to Linear tooling, setting up Linear CLI, or when an agent needs to manage Linear issues (create, list, update, search, comment, pull, push, sync). Triggers: 'setup linear', 'install linear cli', 'linear onboarding'."
---

# Linear CLI Setup & Usage

Sets up [schpet/linear-cli](https://github.com/schpet/linear-cli) and installs agent skills so any AI coding agent (Cursor, Claude Code, Codex) can manage Linear issues — including bidirectional sync with local markdown files.

## What gets installed

1. **linear CLI binary** — command-line tool for Linear
2. **linear-cli skill** — comprehensive CLI reference for the agent
3. **linear-sync skill** — bidirectional issue sync between Linear and local `.linear/issues/*.md` files
4. **Sync scripts** — `scripts/linear-pull.sh`, `scripts/linear-push.sh`, `scripts/linear-pull-all.sh`
5. **`.linear/issues/` directory** — gitignored local issue store

## Setup (run `scripts/setup.sh`)

```bash
# Full setup: install binary + auth + copy skills + sync scripts
./scripts/setup.sh

# Full setup targeting a specific project directory
./scripts/setup.sh /path/to/project

# Just install binary (no auth prompt)
./scripts/setup.sh --install-only

# Just copy the skills into a project
./scripts/setup.sh --skill-only /path/to/project

# Skip sync skill/scripts (CLI skill only)
./scripts/setup.sh --no-sync
```

The setup script:
1. Installs `linear` CLI binary (via official installer)
2. Runs `linear auth login` (opens browser for Linear OAuth — one-time)
3. Copies the linear-cli agent skill into the target workspace
4. Copies the linear-sync agent skill and pull/push scripts
5. Creates `.linear/issues/` directory (gitignored)

## Authentication in embedded terminals (Cursor, Claude Code, Codex)

`linear auth login` starts an OAuth flow that opens a browser and listens for a callback on localhost. This **does not work** in embedded/agent terminals (Cursor's integrated terminal, Claude Code shell, etc.) because the browser redirect can't reach the callback server.

**When running setup from an AI agent, use this two-step approach:**

1. **Install the binary** (agent can do this):
   ```bash
   ./scripts/setup.sh --install-only
   ```

2. **Authenticate from a regular terminal** (user must do this):
   Open a standalone terminal (Terminal.app, iTerm, etc.) and run:
   ```bash
   linear auth login
   ```
   This opens the browser, completes OAuth, and stores credentials that persist across all terminals.

3. **Copy the skills** (agent can do this after auth):
   ```bash
   ./scripts/setup.sh --skill-only /path/to/project
   ```

**Alternative — API key auth** (no browser needed):
1. Create a personal API key at https://linear.app/settings/api
2. Set it via environment variable or config:
   ```bash
   export LINEAR_API_KEY="lin_api_..."
   ```
   Or add to `.linear.toml` in the repo root:
   ```toml
   api_key = "lin_api_..."
   ```

**Verify auth works:** `linear auth whoami`

## Project configuration

Create `.linear.toml` in a repo root to set defaults:

```toml
[issue.create]
team = "ENG"           # default team key (run 'linear team list' to find yours)
# label = "bug"        # default label
# project = "Backend"  # default project
```

This way `linear issue create --title "Fix thing"` auto-targets the right team.

To discover your team key: `linear team list`

## Where skills get copied

After setup, the agent skills live at:
- **Cursor:** `.cursor/skills/linear-cli/SKILL.md` and `.cursor/skills/linear-sync/SKILL.md`
- **Claude Code:** `.claude/skills/linear-cli/SKILL.md` and `.claude/skills/linear-sync/SKILL.md`
- **Generic/OpenClaw:** `skills/linear-cli/SKILL.md` and `skills/linear-sync/SKILL.md`

Sync scripts are always installed to `scripts/` in the target workspace root.

## Post-setup usage

### CLI operations

```bash
linear issue list                          # list issues
linear issue create --title "Bug" --team ENG
linear issue view ENG-123                  # view issue details
linear issue update ENG-123 --state "In Progress"
linear issue comment add ENG-123 --body "Working on it"
linear team list                           # list available teams

# Search (via GraphQL fallback)
linear api --variable term="search query" <<'GRAPHQL'
query($term: String!) { searchIssues(term: $term, first: 20) { nodes { identifier title state { name } } } }
GRAPHQL
```

### Issue sync operations

```bash
# Pull a single issue from Linear to local markdown
scripts/linear-pull.sh ENG-123

# Push local changes back to Linear
scripts/linear-push.sh ENG-123

# Pull all in-progress issues for your team
scripts/linear-pull-all.sh --team ENG

# Pull all issues (all states)
scripts/linear-pull-all.sh --team ENG --all-states
```

Synced issues live in `.linear/issues/<ID>.md` with YAML frontmatter for metadata and the issue description as the body.

## Updating

To update the CLI: `linear self-update` (or re-run `scripts/setup.sh`)
To update the skills: re-run `scripts/setup.sh --skill-only /path/to/project`
