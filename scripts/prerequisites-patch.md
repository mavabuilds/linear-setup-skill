
The `linear` command must be available on PATH. **Before running any linear command, always check first:**

```bash
linear --version
```

### Install (if not found)

```bash
curl --proto '=https' --tlsv1.2 -LsSf \
  https://github.com/schpet/linear-cli/releases/latest/download/linear-installer.sh | sh
```

This installs to `~/.cargo/bin/`. If `linear` is still not found after install, add it to PATH:
```bash
export PATH="$HOME/.cargo/bin:$PATH"
```

### Authenticate (if not logged in)

Check auth status:
```bash
linear auth whoami
```

If not authenticated, **`linear auth login` does NOT work in embedded terminals** (Cursor, Claude Code, Codex) because it opens a browser OAuth flow with a localhost callback that can't reach the embedded shell. Instead:

1. **Ask the user** to run `linear auth login` from a standalone terminal (Terminal.app, iTerm, Warp, etc.)
2. **Or** ask the user to set a personal API key from https://linear.app/settings/api:
   ```bash
   export LINEAR_API_KEY="lin_api_..."
   ```

Do NOT attempt `linear auth login` from an agent terminal — it will hang indefinitely.
