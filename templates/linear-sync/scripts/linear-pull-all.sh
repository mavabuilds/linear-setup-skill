#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FORCE=false
TEAM=""
STATES="started"
ASSIGNEE=""
ALL_ASSIGNEES=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Pull multiple Linear issues into .linear/issues/ based on filters.
Calls linear-pull.sh for each matching issue.

Options:
  --team <key>       Team to pull from (e.g. ENG). Required.
                     Run 'linear team list' to see available teams.
  --state <state>    Issue state filter (default: started).
                     Values: triage, backlog, unstarted, started, completed, canceled
                     Use --all-states instead to pull all states.
  --all-states       Pull issues from all states
  --assignee <name>  Filter by assignee username (default: your issues)
  --all-assignees    Pull issues for all assignees
  --force            Pass --force to each linear-pull.sh invocation
  -h                 Show this help

Examples:
  $(basename "$0") --team ENG
  $(basename "$0") --team ENG --all-states
  $(basename "$0") --team ENG --state backlog --all-assignees
  $(basename "$0") --team ENG --force
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team) TEAM="$2"; shift 2 ;;
    --state) STATES="$2"; shift 2 ;;
    --all-states) STATES="all"; shift ;;
    --assignee) ASSIGNEE="$2"; shift 2 ;;
    --all-assignees) ALL_ASSIGNEES=true; shift ;;
    --force) FORCE=true; shift ;;
    -h|--help) usage 0 ;;
    -*) echo "Unknown option: $1" >&2; usage 1 ;;
    *) echo "Unexpected argument: $1" >&2; usage 1 ;;
  esac
done

if [[ -z "$TEAM" ]]; then
  echo "Error: --team is required (run 'linear team list' to see available teams)" >&2
  usage 1
fi

# Build the linear issue list command
LIST_ARGS=(--team "$TEAM" --sort priority --no-pager --limit 0)

if [[ "$STATES" == "all" ]]; then
  LIST_ARGS+=(--all-states)
else
  LIST_ARGS+=(--state "$STATES")
fi

if [[ "$ALL_ASSIGNEES" == "true" ]]; then
  LIST_ARGS+=(--all-assignees)
elif [[ -n "$ASSIGNEE" ]]; then
  LIST_ARGS+=(--assignee "$ASSIGNEE")
fi

# Parse issue identifiers from the list output (second column, matches TEAM-NNN pattern)
ISSUES=$(linear issue list "${LIST_ARGS[@]}" 2>&1 | grep -oE '[A-Z]+-[0-9]+' | sort -u)

if [[ -z "$ISSUES" ]]; then
  echo "No issues found matching filters (team=$TEAM, state=$STATES)"
  exit 0
fi

COUNT=$(echo "$ISSUES" | wc -l | tr -d ' ')
echo "Found $COUNT issue(s) to pull:"
echo "$ISSUES"
echo ""

PULLED=0
FAILED=0

for ID in $ISSUES; do
  PULL_ARGS=()
  [[ "$FORCE" == "true" ]] && PULL_ARGS+=(--force)
  PULL_ARGS+=("$ID")

  if "$SCRIPT_DIR/linear-pull.sh" "${PULL_ARGS[@]}"; then
    ((PULLED++))
  else
    echo "  Failed to pull $ID (use --force to overwrite conflicts)"
    ((FAILED++))
  fi
done

echo ""
echo "Done: $PULLED pulled, $FAILED failed (out of $COUNT)"
