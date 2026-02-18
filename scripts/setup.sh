#!/usr/bin/env bash
# Linear CLI setup — install binary, auth, copy agent skill
set -euo pipefail

REPO="schpet/linear-cli"
SKILL_BRANCH="main"
SKILL_PATH="skills/linear-cli"
SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SETUP_DIR}/../templates"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; }
die()   { error "$@"; exit 1; }

usage() {
  cat <<'EOF'
Usage: setup.sh [OPTIONS] [TARGET_DIR]

Options:
  --install-only    Install binary only, skip auth and skill copy
  --skill-only DIR  Copy skills into DIR only, skip install and auth
  --no-sync         Skip installing the linear-sync skill and scripts
  --help            Show this help

TARGET_DIR defaults to current directory.

What it does:
  1. Installs linear CLI binary (schpet/linear-cli)
  2. Authenticates with Linear (opens browser)
  3. Copies the linear-cli agent skill into your workspace
  4. Copies the linear-sync skill and scripts (pull/push/pull-all)
  5. Creates .linear/issues/ directory (gitignored)
EOF
  exit 0
}

# --- Parse args ---
INSTALL_ONLY=false
SKILL_ONLY=false
NO_SYNC=false
TARGET_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-only) INSTALL_ONLY=true; shift ;;
    --skill-only)   SKILL_ONLY=true; TARGET_DIR="${2:?--skill-only requires a directory}"; shift 2 ;;
    --no-sync)      NO_SYNC=true; shift ;;
    --help)         usage ;;
    -*)             die "Unknown option: $1" ;;
    *)              TARGET_DIR="$1"; shift ;;
  esac
done

TARGET_DIR="${TARGET_DIR:-.}"

# --- Install binary ---
install_binary() {
  if command -v linear &>/dev/null; then
    local current_version
    current_version=$(linear --version 2>/dev/null || echo "unknown")
    info "linear CLI already installed ($current_version)"
    
    if [[ -t 0 ]]; then
      read -rp "Reinstall/update? [y/N] " answer
      [[ "$answer" =~ ^[Yy]$ ]] || return 0
    else
      info "Non-interactive terminal — skipping reinstall prompt (use linear self-update to update)"
      return 0
    fi
  fi

  info "Installing linear CLI..."
  if command -v curl &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -LsSf \
      "https://github.com/${REPO}/releases/latest/download/linear-installer.sh" | sh
  else
    die "curl is required to install linear CLI"
  fi

  # Verify
  if command -v linear &>/dev/null; then
    info "Installed: $(linear --version)"
  else
    warn "Binary installed but 'linear' not on PATH. You may need to restart your shell or add ~/.cargo/bin to PATH."
  fi
}

# --- Auth ---
auth() {
  if linear auth whoami &>/dev/null 2>&1; then
    local user
    user=$(linear auth whoami 2>/dev/null | head -1)
    info "Already authenticated as: $user"
    return 0
  fi

  # linear auth login requires a browser + localhost callback, which fails in
  # embedded terminals (Cursor, Claude Code, Codex). Detect and guide the user.
  if [[ ! -t 0 ]] || [[ "${CURSOR_TERMINAL:-}" == "1" ]] || [[ -n "${CLAUDE_CODE:-}" ]] || [[ -n "${CODEX:-}" ]]; then
    warn "Embedded/non-interactive terminal detected."
    warn "linear auth login requires a browser callback that won't work here."
    echo ""
    echo "  Option 1: Run in a standalone terminal (Terminal.app, iTerm, etc.):"
    echo "    linear auth login"
    echo ""
    echo "  Option 2: Set a personal API key from https://linear.app/settings/api :"
    echo "    export LINEAR_API_KEY=\"lin_api_...\""
    echo ""
    warn "Skipping auth — complete it manually, then re-run this script or run:"
    echo "    $0 --skill-only ${TARGET_DIR}"
    return 0
  fi

  info "Authenticating with Linear (opening browser)..."
  linear auth login
  
  if linear auth whoami &>/dev/null 2>&1; then
    info "Authentication successful"
  else
    warn "Auth may not have completed. Run 'linear auth login' manually if needed."
  fi
}

# --- Copy skill ---
copy_skill() {
  local dest="$1"
  
  info "Fetching latest agent skill from ${REPO}..."
  
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" EXIT
  
  # Download skill files from GitHub
  local base_url="https://raw.githubusercontent.com/${REPO}/${SKILL_BRANCH}/${SKILL_PATH}"
  
  # Get SKILL.md
  if ! curl -fsSL "${base_url}/SKILL.md" -o "${tmpdir}/SKILL.md" 2>/dev/null; then
    die "Failed to download skill from ${REPO}. Check your network connection."
  fi

  # Patch Prerequisites: replace the upstream "follow the link" section with
  # actionable install/auth instructions that work in embedded agent terminals.
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local patch_file="${script_dir}/prerequisites-patch.md"
  local patch_marker="If not installed, follow the instructions at:"

  if [[ -f "$patch_file" ]] && grep -q "$patch_marker" "${tmpdir}/SKILL.md" 2>/dev/null; then
    info "Patching Prerequisites with install/auth instructions..."
    awk -v patch_file="$patch_file" '
      /^## Prerequisites$/ { print; in_prereq=1; while ((getline line < patch_file) > 0) print line; next }
      in_prereq && /^## / { in_prereq=0 }
      !in_prereq { print }
    ' "${tmpdir}/SKILL.md" > "${tmpdir}/SKILL.md.patched"
    mv "${tmpdir}/SKILL.md.patched" "${tmpdir}/SKILL.md"
    info "Prerequisites patched successfully"
  fi
  
  # Try to get the references directory listing
  local refs_url="https://api.github.com/repos/${REPO}/contents/${SKILL_PATH}/references"
  local refs_json
  if refs_json=$(curl -fsSL "$refs_url" 2>/dev/null); then
    mkdir -p "${tmpdir}/references"
    # Download each reference file
    echo "$refs_json" | grep -o '"download_url":"[^"]*"' | sed 's/"download_url":"//;s/"$//' | while read -r url; do
      local filename
      filename=$(basename "$url")
      curl -fsSL "$url" -o "${tmpdir}/references/${filename}" 2>/dev/null && \
        info "  Fetched references/${filename}" || \
        warn "  Failed to fetch references/${filename}"
    done
  fi
  
  # Detect target location based on workspace
  local skill_dest=""
  if [[ -d "${dest}/.claude" ]] || [[ -f "${dest}/.claude/settings.json" ]]; then
    skill_dest="${dest}/.claude/skills/linear-cli"
    info "Detected Claude Code workspace"
  elif [[ -d "${dest}/.cursor" ]]; then
    skill_dest="${dest}/.cursor/skills/linear-cli"
    info "Detected Cursor workspace"
  else
    # Generic — works for OpenClaw and others
    skill_dest="${dest}/skills/linear-cli"
  fi
  
  mkdir -p "$skill_dest"
  cp -r "${tmpdir}/"* "$skill_dest/"
  
  info "Agent skill copied to: ${skill_dest}/"
  info "Files:"
  find "$skill_dest" -type f | while read -r f; do
    echo "  $(realpath --relative-to="$dest" "$f" 2>/dev/null || echo "$f")"
  done
}

# --- Copy sync skill + scripts ---
copy_sync() {
  local dest="$1"

  if [[ ! -d "$TEMPLATES_DIR/linear-sync" ]]; then
    warn "Sync templates not found at $TEMPLATES_DIR/linear-sync — skipping sync setup"
    return 0
  fi

  # Copy scripts
  local scripts_dest="${dest}/scripts"
  mkdir -p "$scripts_dest"
  cp "${TEMPLATES_DIR}/linear-sync/scripts/linear-pull.sh" "$scripts_dest/"
  cp "${TEMPLATES_DIR}/linear-sync/scripts/linear-push.sh" "$scripts_dest/"
  cp "${TEMPLATES_DIR}/linear-sync/scripts/linear-pull-all.sh" "$scripts_dest/"
  chmod +x "$scripts_dest"/linear-*.sh
  info "Sync scripts copied to: ${scripts_dest}/"

  # Copy skill
  local skill_dest=""
  if [[ -d "${dest}/.claude" ]] || [[ -f "${dest}/.claude/settings.json" ]]; then
    skill_dest="${dest}/.claude/skills/linear-sync"
  elif [[ -d "${dest}/.cursor" ]]; then
    skill_dest="${dest}/.cursor/skills/linear-sync"
  else
    skill_dest="${dest}/skills/linear-sync"
  fi

  mkdir -p "$skill_dest"
  cp "${TEMPLATES_DIR}/linear-sync/SKILL.md" "$skill_dest/"
  info "Sync skill copied to: ${skill_dest}/"

  # Set up .linear directory
  mkdir -p "${dest}/.linear/issues"
  local gitignore="${dest}/.gitignore"
  if [[ -f "$gitignore" ]]; then
    grep -qxF '.linear/' "$gitignore" || echo '.linear/' >> "$gitignore"
  else
    echo '.linear/' > "$gitignore"
  fi
  info "Created .linear/issues/ directory (gitignored)"
}

# --- Suggest team configuration ---
suggest_config() {
  local dest="$1"
  local toml="${dest}/.linear.toml"

  if [[ -f "$toml" ]]; then
    info ".linear.toml already exists — skipping config suggestion"
    return 0
  fi

  if ! command -v linear &>/dev/null || ! linear auth whoami &>/dev/null 2>&1; then
    return 0
  fi

  echo ""
  info "Tip: create .linear.toml in your repo root to set default team:"
  echo ""
  echo "  [issue.create]"
  echo "  team = \"YOUR_TEAM_KEY\""
  echo ""
  echo "  Run 'linear team list' to see available teams."
}

# --- Main ---
if $SKILL_ONLY; then
  copy_skill "$TARGET_DIR"
  if ! $NO_SYNC; then
    copy_sync "$TARGET_DIR"
  fi
  info "Done! Skills copied. Restart your agent/editor to pick them up."
  exit 0
fi

if ! $SKILL_ONLY; then
  install_binary
fi

if ! $INSTALL_ONLY; then
  auth
  copy_skill "$TARGET_DIR"
  if ! $NO_SYNC; then
    copy_sync "$TARGET_DIR"
  fi
  suggest_config "$TARGET_DIR"
fi

echo ""
info "Setup complete! Next steps:"
echo "  1. Restart your editor/agent to discover the skills"
echo "  2. (Optional) Create .linear.toml in your repo to set team defaults"
echo "  3. Run 'linear team list' to find your team key"
echo "  4. Try: linear issue list"
echo "  5. Try: scripts/linear-pull.sh <ISSUE_ID>"
