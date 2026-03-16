#!/usr/bin/env bash
# Entry point for /autopilot:_full - determines what phase to execute
#
# Usage: entry-point.sh "<arguments>"
# Output: JSON with action, status, phase, feature_dir, plan_file

set -e

ARGS="${1:-}"

# Parse arguments
PLAN_FILE=""
RESUME_MODE="false"

# Check for --resume flag
if echo "$ARGS" | grep -q -- '--resume'; then
    RESUME_MODE="true"
    ARGS=$(echo "$ARGS" | sed 's/--resume//')
fi

# Extract .md file (first match)
PLAN_FILE=$(echo "$ARGS" | grep -oE '[^ ]+\.md' | head -1 || true)

# Find state file
STATE_FILE=""
if [ "$RESUME_MODE" = "true" ] || [ -z "$PLAN_FILE" ]; then
    # Find most recent in-progress workflow
    STATE_FILES=$(find specs -maxdepth 2 -name ".workflow-state.json" -type f 2>/dev/null || true)
    if [ -n "$STATE_FILES" ]; then
        STATE_FILE=$(echo "$STATE_FILES" | xargs ls -t 2>/dev/null | head -1 || true)
    fi
fi

# Determine action based on state
ACTION="initialize"
STATUS=""
CURRENT_PHASE="0"
FEATURE_DIR=""
ERROR=""

if [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
    STATUS=$(grep -o '"status": "[^"]*"' "$STATE_FILE" | cut -d'"' -f4 || true)
    CURRENT_PHASE=$(grep -o '"currentPhase": [0-9]*' "$STATE_FILE" | grep -o '[0-9]*' || echo "0")
    FEATURE_DIR=$(dirname "$STATE_FILE")

    if [ "$STATUS" = "completed" ]; then
        ACTION="complete"
    elif [ "$STATUS" = "halted" ]; then
        ACTION="halted"
    else
        ACTION="resume"
    fi
elif [ -z "$PLAN_FILE" ]; then
    ACTION="error"
    ERROR="No plan file provided and no existing workflow found"
fi

# Output JSON
cat <<EOF
{
  "action": "$ACTION",
  "status": "$STATUS",
  "current_phase": $CURRENT_PHASE,
  "feature_dir": "$FEATURE_DIR",
  "plan_file": "$PLAN_FILE",
  "state_file": "$STATE_FILE",
  "resume_mode": $RESUME_MODE,
  "error": "$ERROR"
}
EOF
