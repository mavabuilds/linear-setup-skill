#!/usr/bin/env bash
set -euo pipefail

ISSUES_DIR="$(git rev-parse --show-toplevel)/.linear/issues"
FORCE=false
ISSUE_ID=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [--force] <ISSUE_ID>

Push a local .linear/issues/<ISSUE_ID>.md back to Linear.

Updates the issue description and optionally title/status/priority from
the YAML frontmatter. Aborts if Linear was updated since last sync
unless --force is given.

Options:
  --force   Push even if Linear was modified since last sync
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

if [[ -z "$ISSUE_ID" ]]; then
  echo "Error: ISSUE_ID is required" >&2
  usage 1
fi

LOCAL_FILE="$ISSUES_DIR/$ISSUE_ID.md"

if [[ ! -f "$LOCAL_FILE" ]]; then
  echo "Error: $LOCAL_FILE does not exist. Pull first with: linear-pull.sh $ISSUE_ID" >&2
  exit 1
fi

# --- Parse frontmatter ---
parse_frontmatter() {
  awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$LOCAL_FILE"
}

fm_get() {
  parse_frontmatter | grep "^$1:" | sed "s/^$1: *//"
}

LOCAL_ID=$(fm_get "linear_id")
LAST_SYNCED=$(fm_get "last_synced")
LOCAL_TITLE=$(fm_get "title")
LOCAL_STATUS=$(fm_get "status")
LOCAL_PRIORITY=$(fm_get "priority")

if [[ -z "$LOCAL_ID" ]]; then
  echo "Error: no linear_id in frontmatter of $LOCAL_FILE" >&2
  exit 1
fi

# --- Conflict detection: check if Linear changed since last sync ---
if [[ "$FORCE" != "true" && -n "$LAST_SYNCED" ]]; then
  REMOTE_UPDATED=$(linear api --variable id="$LOCAL_ID" <<'GRAPHQL' | jq -r '.data.issueVcsBranchSearch.updatedAt'
query($id: String!) {
  issueVcsBranchSearch(branchName: $id) { updatedAt }
}
GRAPHQL
)

  if [[ "$REMOTE_UPDATED" != "null" && -n "$REMOTE_UPDATED" ]]; then
    REMOTE_TS=$(date -jf "%Y-%m-%dT%H:%M:%S" "${REMOTE_UPDATED%%.*}" "+%s" 2>/dev/null || date -d "${REMOTE_UPDATED}" "+%s" 2>/dev/null || echo "0")
    LOCAL_TS=$(date -jf "%Y-%m-%dT%H:%M:%S" "${LAST_SYNCED%%.*}" "+%s" 2>/dev/null || date -d "${LAST_SYNCED}" "+%s" 2>/dev/null || echo "0")

    if [[ "$REMOTE_TS" -gt "$LOCAL_TS" ]]; then
      echo "Warning: Linear issue $LOCAL_ID was updated at $REMOTE_UPDATED, after your last sync at $LAST_SYNCED."
      echo "Pull first to see remote changes, or use --force to overwrite."
      exit 1
    fi
  fi
fi

# --- Extract body (everything after the second ---) ---
BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/linear-push-XXXXXX.md")
trap 'rm -f "$BODY_FILE"' EXIT

awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$LOCAL_FILE" > "$BODY_FILE"

# --- Push description ---
linear issue update "$LOCAL_ID" --description-file "$BODY_FILE"

# --- Push metadata if present ---
UPDATE_ARGS=()
[[ -n "$LOCAL_TITLE" ]]    && UPDATE_ARGS+=(--title "$LOCAL_TITLE")
[[ -n "$LOCAL_STATUS" ]]   && UPDATE_ARGS+=(--state "$LOCAL_STATUS")
[[ -n "$LOCAL_PRIORITY" ]] && UPDATE_ARGS+=(--priority "$LOCAL_PRIORITY")

if [[ ${#UPDATE_ARGS[@]} -gt 0 ]]; then
  linear issue update "$LOCAL_ID" "${UPDATE_ARGS[@]}"
fi

# --- Update last_synced in local file ---
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if grep -q "^last_synced:" "$LOCAL_FILE"; then
  perl -i -pe "s/^last_synced: .*/last_synced: $NOW/" "$LOCAL_FILE"
else
  perl -i -pe "s/^---$/last_synced: $NOW\n---/ if \$. > 1 && !(\$found++)" "$LOCAL_FILE"
fi

echo "Pushed $LOCAL_ID <- $LOCAL_FILE (synced at $NOW)"
