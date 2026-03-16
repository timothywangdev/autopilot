#!/usr/bin/env bash
# workflow-status.sh - Get comprehensive workflow status
# Usage: workflow-status.sh [--feature-dir <path>] [--branch <name>]
# Output: JSON with full workflow state

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# ==============================================================================
# Argument Parsing
# ==============================================================================

FEATURE_DIR=""
BRANCH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --feature-dir)
            FEATURE_DIR="$2"
            shift 2
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--feature-dir <path>] [--branch <name>]"
            echo ""
            echo "Options:"
            echo "  --feature-dir  Path to feature directory"
            echo "  --branch       Branch name (auto-detected if not specified)"
            echo ""
            echo "Output: JSON with workflow status"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# ==============================================================================
# Auto-detect Feature
# ==============================================================================

REPO_ROOT=$(get_repo_root)

if [ -z "$BRANCH" ]; then
    BRANCH=$(get_current_branch)
fi

if [ -z "$FEATURE_DIR" ]; then
    FEATURE_DIR=$(find_feature_dir "$REPO_ROOT" "$BRANCH" 2>/dev/null || echo "")
fi

# If still no feature dir, check if we can find one
if [ -z "$FEATURE_DIR" ] || [ ! -d "$FEATURE_DIR" ]; then
    # Try to find most recent feature
    FEATURE_DIR=$(ls -td "$REPO_ROOT/$SPECS_DIR"/[0-9][0-9][0-9]-* 2>/dev/null | head -1 || echo "")
fi

# ==============================================================================
# Collect Status
# ==============================================================================

# Default values
STATE_EXISTS="false"
CURRENT_PHASE=0
STATUS="unknown"
FEATURE_ID=""
CREATED_AT=""
UPDATED_AT=""
SPEC_EXISTS="false"
PLAN_EXISTS="false"
TASKS_EXISTS="false"
RESEARCH_EXISTS="false"
DATAMODEL_EXISTS="false"
CONTRACTS_EXISTS="false"
SPIKE_REPORT_EXISTS="false"
VERIFICATION_EXISTS="false"
REVIEW_EXISTS="false"
TASKS_TOTAL=0
TASKS_COMPLETE=0
ITERATIONS_SPIKE=0
ITERATIONS_IMPLEMENT=0
ITERATIONS_VERIFY=0
ITERATIONS_REVIEW=0

if [ -n "$FEATURE_DIR" ] && [ -d "$FEATURE_DIR" ]; then
    STATE_FILE="$FEATURE_DIR/$STATE_FILE_NAME"

    # Check artifacts
    [ -f "$FEATURE_DIR/spec.md" ] && [ -s "$FEATURE_DIR/spec.md" ] && SPEC_EXISTS="true"
    [ -f "$FEATURE_DIR/plan.md" ] && [ -s "$FEATURE_DIR/plan.md" ] && PLAN_EXISTS="true"
    [ -f "$FEATURE_DIR/tasks.md" ] && [ -s "$FEATURE_DIR/tasks.md" ] && TASKS_EXISTS="true"
    [ -f "$FEATURE_DIR/research.md" ] && [ -s "$FEATURE_DIR/research.md" ] && RESEARCH_EXISTS="true"
    [ -f "$FEATURE_DIR/data-model.md" ] && [ -s "$FEATURE_DIR/data-model.md" ] && DATAMODEL_EXISTS="true"
    [ -d "$FEATURE_DIR/contracts" ] && [ -n "$(ls -A "$FEATURE_DIR/contracts" 2>/dev/null)" ] && CONTRACTS_EXISTS="true"
    [ -f "$FEATURE_DIR/spike-report.md" ] && SPIKE_REPORT_EXISTS="true"
    [ -f "$FEATURE_DIR/verification-report.md" ] && VERIFICATION_EXISTS="true"
    [ -f "$FEATURE_DIR/review-report.md" ] && REVIEW_EXISTS="true"

    # Task counts
    if [ "$TASKS_EXISTS" = "true" ]; then
        TASKS_TOTAL=$(grep -cE '^[[:space:]]*-[[:space:]]*\[[ Xx]\][[:space:]]*T[0-9]+:' "$FEATURE_DIR/tasks.md" | tr -d ' ' || echo "0")
        TASKS_COMPLETE=$(grep -cE '^[[:space:]]*-[[:space:]]*\[[Xx]\][[:space:]]*T[0-9]+:' "$FEATURE_DIR/tasks.md" | tr -d ' ' || echo "0")
    fi

    # Parse state file
    if [ -f "$STATE_FILE" ]; then
        STATE_EXISTS="true"

        if command -v node >/dev/null 2>&1; then
            # Use node to output JSON, then parse with grep/sed (avoids eval)
            # SECURITY: Pass file path via environment variable to prevent injection
            STATE_JSON=$(STATE_FILE_PATH="$STATE_FILE" node -e '
                const fs = require("fs");
                const state = JSON.parse(fs.readFileSync(process.env.STATE_FILE_PATH, "utf8"));
                console.log(JSON.stringify({
                    currentPhase: state.currentPhase || 0,
                    status: state.status || "unknown",
                    featureId: state.featureId || "",
                    createdAt: state.createdAt || "",
                    updatedAt: state.updatedAt || "",
                    spike: state.iterations?.spike || 0,
                    implement: state.iterations?.implement || 0,
                    verify: state.iterations?.verify || 0,
                    review: state.iterations?.review || 0
                }));
            ' 2>/dev/null || echo '{}')

            # Parse JSON fields safely (no eval)
            CURRENT_PHASE=$(echo "$STATE_JSON" | grep -o '"currentPhase":[0-9]*' | grep -o '[0-9]*' || echo "0")
            STATUS=$(echo "$STATE_JSON" | grep -o '"status":"[^"]*"' | sed 's/"status":"//;s/"$//' || echo "unknown")
            FEATURE_ID=$(echo "$STATE_JSON" | grep -o '"featureId":"[^"]*"' | sed 's/"featureId":"//;s/"$//' || echo "")
            CREATED_AT=$(echo "$STATE_JSON" | grep -o '"createdAt":"[^"]*"' | sed 's/"createdAt":"//;s/"$//' || echo "")
            UPDATED_AT=$(echo "$STATE_JSON" | grep -o '"updatedAt":"[^"]*"' | sed 's/"updatedAt":"//;s/"$//' || echo "")
            ITERATIONS_SPIKE=$(echo "$STATE_JSON" | grep -o '"spike":[0-9]*' | grep -o '[0-9]*' || echo "0")
            ITERATIONS_IMPLEMENT=$(echo "$STATE_JSON" | grep -o '"implement":[0-9]*' | grep -o '[0-9]*' || echo "0")
            ITERATIONS_VERIFY=$(echo "$STATE_JSON" | grep -o '"verify":[0-9]*' | grep -o '[0-9]*' || echo "0")
            ITERATIONS_REVIEW=$(echo "$STATE_JSON" | grep -o '"review":[0-9]*' | grep -o '[0-9]*' || echo "0")
        fi
    fi
fi

# ==============================================================================
# Calculate Derived Values
# ==============================================================================

# Progress percentage
PROGRESS=0
if [ "$TASKS_TOTAL" -gt 0 ]; then
    PROGRESS=$((TASKS_COMPLETE * 100 / TASKS_TOTAL))
fi

# Phase name
PHASE_NAMES=("Parse" "Initialize" "Spike" "Specify" "Plan" "Tasks" "Analyze" "Implement" "Verify" "Review" "Complete")
PHASE_NAME="${PHASE_NAMES[$CURRENT_PHASE]:-Unknown}"

# Next action
NEXT_ACTION="Continue with phase $CURRENT_PHASE ($PHASE_NAME)"
if [ "$STATUS" = "completed" ]; then
    NEXT_ACTION="Feature complete"
elif [ "$STATUS" = "halted" ]; then
    NEXT_ACTION="Manual intervention required"
elif [ "$STATUS" = "checkpoint" ]; then
    NEXT_ACTION="Waiting for user input"
fi

# ==============================================================================
# Output
# ==============================================================================

cat << EOF
{
    "branch": "$BRANCH",
    "featureDir": "${FEATURE_DIR#$REPO_ROOT/}",
    "featureId": "$FEATURE_ID",
    "stateExists": $STATE_EXISTS,
    "status": "$STATUS",
    "currentPhase": $CURRENT_PHASE,
    "phaseName": "$PHASE_NAME",
    "progress": $PROGRESS,
    "artifacts": {
        "spec": $SPEC_EXISTS,
        "plan": $PLAN_EXISTS,
        "tasks": $TASKS_EXISTS,
        "research": $RESEARCH_EXISTS,
        "dataModel": $DATAMODEL_EXISTS,
        "contracts": $CONTRACTS_EXISTS,
        "spikeReport": $SPIKE_REPORT_EXISTS,
        "verificationReport": $VERIFICATION_EXISTS,
        "reviewReport": $REVIEW_EXISTS
    },
    "tasks": {
        "total": $TASKS_TOTAL,
        "complete": $TASKS_COMPLETE,
        "incomplete": $((TASKS_TOTAL - TASKS_COMPLETE)),
        "progressPercent": $PROGRESS
    },
    "iterations": {
        "spike": $ITERATIONS_SPIKE,
        "implement": $ITERATIONS_IMPLEMENT,
        "verify": $ITERATIONS_VERIFY,
        "review": $ITERATIONS_REVIEW
    },
    "timestamps": {
        "created": "$CREATED_AT",
        "updated": "$UPDATED_AT"
    },
    "nextAction": "$NEXT_ACTION"
}
EOF
