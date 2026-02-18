---
name: linear
description: "Set up and use Linear CLI for issue management. Installs schpet/linear-cli, authenticates, and copies the agent skill into the workspace. Use when onboarding a new engineer to Linear tooling, setting up Linear CLI, or when an agent needs to manage Linear issues (create, list, update, search, comment). Triggers: 'setup linear', 'install linear cli', 'linear onboarding'."
---

# Linear CLI Setup & Usage

Sets up [schpet/linear-cli](https://github.com/schpet/linear-cli) and installs its agent skill so any AI coding agent (Cursor, Claude Code, Codex) can manage Linear issues.

## Setup (run `scripts/setup.sh`)

```bash
# Full setup: install binary + auth + copy skill
./scripts/setup.sh

# Just install binary (no auth prompt)
./scripts/setup.sh --install-only

# Just copy the skill into a project
./scripts/setup.sh --skill-only /path/to/project
```

The setup script:
1. Installs `linear` CLI binary (via official installer)
2. Runs `linear auth login` (opens browser for Linear OAuth — one-time)
3. Copies the linear-cli agent skill into the target workspace

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

3. **Copy the skill** (agent can do this after auth):
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

## Where the skill gets copied

After setup, the agent skill lives at:
- **Claude Code:** `.claude/skills/linear-cli/SKILL.md` (auto-discovered)
- **Cursor:** `.cursor/skills/linear-cli/SKILL.md` (auto-discovered)
- **Generic/OpenClaw:** `skills/linear-cli/SKILL.md`

The copied skill is schpet's official skill — auto-generated from CLI help, stays comprehensive.

## Project config (optional)

Create `.linear.toml` in a repo root to set defaults:

```toml
[issue.create]
team = "ENG"           # default team key
# label = "bug"        # default label
# project = "Backend"  # default project
```

This way `linear issue create --title "Fix thing"` auto-targets the right team.

## Post-setup usage

Once set up, the agent reads the copied skill and knows all commands. Key operations:

```bash
linear issue list                          # list issues
linear issue create --title "Bug" --team ENG
linear issue view ENG-123                  # view issue details
linear issue update ENG-123 --state "In Progress"
linear issue comment add ENG-123 --body "Working on it"

# Search (via GraphQL fallback)
linear api --variable term="search query" <<'GRAPHQL'
query($term: String!) { searchIssues(term: $term, first: 20) { nodes { identifier title state { name } } } }
GRAPHQL
```

## Updating

To update the CLI: `linear self-update` (or re-run `scripts/setup.sh`)
To update the skill: re-run `scripts/setup.sh --skill-only /path/to/project`
