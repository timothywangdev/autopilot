#!/usr/bin/env bash
# Parse /autopilot:loop arguments and output JSON for Claude to consume
#
# Usage: parse-loop-args.sh "<arguments>"
# Output: JSON with plan_file, interval, resume_mode, autopilot_cmd

set -e

ARGS="${1:-}"

# Defaults
PLAN_FILE=""
INTERVAL="1m"
RESUME_MODE="false"

# Check for --resume flag
if echo "$ARGS" | grep -q -- '--resume'; then
    RESUME_MODE="true"
fi

# Check for --interval and extract value
if echo "$ARGS" | grep -q -- '--interval'; then
    INTERVAL=$(echo "$ARGS" | grep -oE '\-\-interval[[:space:]]+[^ ]+' | sed 's/--interval[[:space:]]*//')
    INTERVAL=${INTERVAL:-1m}
fi

# Extract .md file (first match)
PLAN_FILE=$(echo "$ARGS" | grep -oE '[^ ]+\.md' | head -1 || true)

# Build autopilot command
AUTOPILOT_CMD=""
ERROR=""

if [ -n "$PLAN_FILE" ]; then
    AUTOPILOT_CMD="/autopilot:_supervisor $PLAN_FILE"
elif [ "$RESUME_MODE" = "true" ]; then
    AUTOPILOT_CMD="/autopilot:_supervisor --resume"
else
    ERROR="Specify a plan file or use --resume"
fi

# Output JSON
cat <<EOF
{
  "plan_file": "$PLAN_FILE",
  "interval": "$INTERVAL",
  "resume_mode": $RESUME_MODE,
  "autopilot_cmd": "$AUTOPILOT_CMD",
  "error": "$ERROR"
}
EOF
