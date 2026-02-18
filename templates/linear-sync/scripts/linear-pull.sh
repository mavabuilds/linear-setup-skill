#!/usr/bin/env bash
set -euo pipefail

ISSUES_DIR="$(git rev-parse --show-toplevel)/.linear/issues"
FORCE=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--force] <ISSUE_ID>

Pull a Linear issue into .linear/issues/<ISSUE_ID>.md with YAML frontmatter.

Options:
  --force   Overwrite local file even if it has unsaved local changes
  -h        Show this help

Examples:
  $(basename "$0") ENG-123
  $(basename "$0") --force ENG-123
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=true; shift ;;
    -h|--help) usage 0 ;;
    -*) echo "Unknown option: $1" >&2; usage 1 ;;
    *) ISSUE_ID="$1"; shift ;;
  esac
done

if [[ -z "${ISSUE_ID:-}" ]]; then
  echo "Error: ISSUE_ID is required" >&2
  usage 1
fi

LOCAL_FILE="$ISSUES_DIR/$ISSUE_ID.md"
mkdir -p "$ISSUES_DIR"

REPO_ROOT=$(git rev-parse --show-toplevel)
GITIGNORE="$REPO_ROOT/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
  grep -qxF '.linear/' "$GITIGNORE" || echo '.linear/' >> "$GITIGNORE"
else
  echo '.linear/' > "$GITIGNORE"
fi

# --- Fetch issue from Linear via GraphQL (includes url for org-agnostic links) ---
RAW=$(linear api --variable id="$ISSUE_ID" <<'GRAPHQL'
query($id: String!) {
  issueVcsBranchSearch(branchName: $id) {
    identifier title description priority updatedAt url
    state { name }
    team  { key }
    project { name }
    assignee { name }
  }
}
GRAPHQL
)

NODE=$(echo "$RAW" | jq -r '.data.issueVcsBranchSearch')
if [[ "$NODE" == "null" ]]; then
  echo "Error: issue $ISSUE_ID not found in Linear" >&2
  exit 1
fi

REMOTE_UPDATED=$(echo "$NODE" | jq -r '.updatedAt')
TITLE=$(echo "$NODE" | jq -r '.title // empty')
STATUS=$(echo "$NODE" | jq -r '.state.name // empty')
PRIORITY=$(echo "$NODE" | jq -r '.priority // empty')
TEAM=$(echo "$NODE" | jq -r '.team.key // empty')
PROJECT=$(echo "$NODE" | jq -r '.project.name // empty')
ASSIGNEE=$(echo "$NODE" | jq -r '.assignee.name // empty')
DESCRIPTION=$(echo "$NODE" | jq -r '.description // empty')
URL=$(echo "$NODE" | jq -r '.url // empty')

# --- Conflict detection ---
if [[ -f "$LOCAL_FILE" && "$FORCE" != "true" ]]; then
  LAST_SYNCED=$(awk '/^---$/{n++; next} n==0{next} n==1{print; next} n>=2{exit}' "$LOCAL_FILE" \
    | grep '^last_synced:' | sed 's/^last_synced: *//')

  if [[ -n "$LAST_SYNCED" ]]; then
    REL_PATH="${LOCAL_FILE#$REPO_ROOT/}"

    if git ls-files --error-unmatch "$REL_PATH" >/dev/null 2>&1; then
      if ! git diff --quiet -- "$LOCAL_FILE" 2>/dev/null || \
         ! git diff --cached --quiet -- "$LOCAL_FILE" 2>/dev/null; then
        echo "Warning: $LOCAL_FILE has uncommitted changes since last sync ($LAST_SYNCED)."
        echo "Use --force to overwrite."
        exit 1
      fi
    fi
  fi
fi

# --- Build frontmatter ---
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

{
  echo "---"
  echo "linear_id: $ISSUE_ID"
  [[ -n "$URL" ]]      && echo "url: $URL"
  [[ -n "$TITLE" ]]    && echo "title: $TITLE"
  [[ -n "$STATUS" ]]   && echo "status: $STATUS"
  [[ -n "$PRIORITY" ]] && echo "priority: $PRIORITY"
  [[ -n "$TEAM" ]]     && echo "team: $TEAM"
  [[ -n "$PROJECT" ]]  && echo "project: $PROJECT"
  [[ -n "$ASSIGNEE" ]] && echo "assignee: $ASSIGNEE"
  echo "last_synced: $NOW"
  echo "---"
  echo ""
  echo "$DESCRIPTION"
} > "$LOCAL_FILE"

echo "Pulled $ISSUE_ID -> $LOCAL_FILE (synced at $NOW)"
