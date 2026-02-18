#!/usr/bin/env bash
# Linear CLI setup — install binary, auth, copy agent skill
set -euo pipefail

REPO="schpet/linear-cli"
SKILL_BRANCH="main"
SKILL_PATH="skills/linear-cli"

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
  --skill-only DIR  Copy skill into DIR only, skip install and auth
  --help            Show this help

TARGET_DIR defaults to current directory.

What it does:
  1. Installs linear CLI binary (schpet/linear-cli)
  2. Authenticates with Linear (opens browser)
  3. Copies the agent skill into your workspace for AI agent discovery
EOF
  exit 0
}

# --- Parse args ---
INSTALL_ONLY=false
SKILL_ONLY=false
TARGET_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-only) INSTALL_ONLY=true; shift ;;
    --skill-only)   SKILL_ONLY=true; TARGET_DIR="${2:?--skill-only requires a directory}"; shift 2 ;;
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
    
    read -rp "Reinstall/update? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || return 0
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

# --- Main ---
if $SKILL_ONLY; then
  copy_skill "$TARGET_DIR"
  info "Done! Skill copied. Restart your agent/editor to pick it up."
  exit 0
fi

if ! $SKILL_ONLY; then
  install_binary
fi

if ! $INSTALL_ONLY; then
  auth
  copy_skill "$TARGET_DIR"
fi

echo ""
info "Setup complete! Next steps:"
echo "  1. Restart your editor/agent to discover the skill"
echo "  2. (Optional) Create .linear.toml in your repo to set team defaults"
echo "  3. Try: linear issue list"
