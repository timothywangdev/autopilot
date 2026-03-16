#!/usr/bin/env bash
# check-prerequisites.sh - Check prerequisites for a workflow phase
# Usage: check-prerequisites.sh --phase <number> --feature-dir <path>
# Output: JSON with prerequisite status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# ==============================================================================
# Argument Parsing
# ==============================================================================

PHASE=""
FEATURE_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --phase)
            PHASE="$2"
            shift 2
            ;;
        --feature-dir)
            FEATURE_DIR="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 --phase <number> --feature-dir <path>"
            echo ""
            echo "Phases:"
            echo "  0  Parse        - Need plan file"
            echo "  1  Initialize   - Need parsed description"
            echo "  2  Spike        - Need feature dir with plan"
            echo "  3  Specify      - Need validated plan"
            echo "  4  Plan         - Need spec.md"
            echo "  5  Tasks        - Need plan.md"
            echo "  6  Analyze      - Need tasks.md"
            echo "  7  Implement    - Need tasks.md (analyzed)"
            echo "  8  Verify       - Need completed tasks"
            echo "  9  Review       - Need verified tasks"
            echo "  10 Complete     - Need passed review"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [ -z "$PHASE" ]; then
    log_error "Missing required argument: --phase"
    exit 1
fi

if [ -z "$FEATURE_DIR" ]; then
    log_error "Missing required argument: --feature-dir"
    exit 1
fi

# ==============================================================================
# Prerequisite Definitions
# ==============================================================================

REPO_ROOT=$(get_repo_root)

# Resolve feature dir
if [[ "$FEATURE_DIR" != /* ]]; then
    FEATURE_DIR="$REPO_ROOT/$FEATURE_DIR"
fi

# Standard paths
STATE_FILE="$FEATURE_DIR/$STATE_FILE_NAME"
SPEC_FILE="$FEATURE_DIR/spec.md"
PLAN_FILE="$FEATURE_DIR/plan.md"
TASKS_FILE="$FEATURE_DIR/tasks.md"
SPIKE_REPORT="$FEATURE_DIR/spike-report.md"
VALIDATED_PLAN="$FEATURE_DIR/validated-plan.md"
VERIFICATION_REPORT="$FEATURE_DIR/verification-report.md"
REVIEW_REPORT="$FEATURE_DIR/review-report.md"

# Check results
MISSING=()
PRESENT=()

check_file() {
    local file="$1"
    local name="$2"

    if [ -f "$file" ] && [ -s "$file" ]; then
        PRESENT+=("$name")
        return 0
    else
        MISSING+=("$name")
        return 1
    fi
}

check_dir() {
    local dir="$1"
    local name="$2"

    if [ -d "$dir" ]; then
        PRESENT+=("$name")
        return 0
    else
        MISSING+=("$name")
        return 1
    fi
}

check_state_field() {
    local field="$1"
    local expected="$2"
    local name="$3"

    if [ ! -f "$STATE_FILE" ]; then
        MISSING+=("$name (state file missing)")
        return 1
    fi

    local actual
    actual=$("$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" --get "$field" 2>/dev/null || echo "")

    if [ "$actual" = "$expected" ]; then
        PRESENT+=("$name")
        return 0
    else
        MISSING+=("$name (current: $actual, expected: $expected)")
        return 1
    fi
}

check_tasks_status() {
    local min_complete="$1"
    local name="$2"

    if [ ! -f "$TASKS_FILE" ]; then
        MISSING+=("$name (tasks.md missing)")
        return 1
    fi

    local total
    total=$(grep -cE '^[[:space:]]*-[[:space:]]*\[[ Xx]\][[:space:]]*T[0-9]+:' "$TASKS_FILE" | tr -d ' ' || echo "0")
    local complete
    complete=$(grep -cE '^[[:space:]]*-[[:space:]]*\[[Xx]\][[:space:]]*T[0-9]+:' "$TASKS_FILE" | tr -d ' ' || echo "0")

    if [ "$total" -eq 0 ]; then
        MISSING+=("$name (no tasks found)")
        return 1
    fi

    local percent=$((complete * 100 / total))
    if [ "$percent" -ge "$min_complete" ]; then
        PRESENT+=("$name ($complete/$total = ${percent}%)")
        return 0
    else
        MISSING+=("$name ($complete/$total = ${percent}%, need >= ${min_complete}%)")
        return 1
    fi
}

# ==============================================================================
# Phase-Specific Checks
# ==============================================================================

case "$PHASE" in
    0) # Parse
        # Only need input plan file (passed externally)
        check_file "$PLAN_FILE" "plan.md (or input plan)" || true
        ;;

    1) # Initialize
        # Need repo root
        check_dir "$REPO_ROOT/$SPECS_DIR" "specs directory"
        ;;

    2) # Spike
        check_dir "$FEATURE_DIR" "feature directory"
        check_file "$PLAN_FILE" "plan.md"
        check_file "$STATE_FILE" "workflow state"
        ;;

    3) # Specify
        check_dir "$FEATURE_DIR" "feature directory"
        # Either validated plan from spike or original plan
        if [ -f "$VALIDATED_PLAN" ]; then
            check_file "$VALIDATED_PLAN" "validated-plan.md"
        else
            check_file "$PLAN_FILE" "plan.md"
        fi
        check_file "$STATE_FILE" "workflow state"
        ;;

    4) # Plan
        check_dir "$FEATURE_DIR" "feature directory"
        check_file "$SPEC_FILE" "spec.md"
        check_file "$STATE_FILE" "workflow state"
        ;;

    5) # Tasks
        check_dir "$FEATURE_DIR" "feature directory"
        check_file "$SPEC_FILE" "spec.md"
        check_file "$PLAN_FILE" "plan.md"
        check_file "$STATE_FILE" "workflow state"
        ;;

    6) # Analyze
        check_dir "$FEATURE_DIR" "feature directory"
        check_file "$SPEC_FILE" "spec.md"
        check_file "$PLAN_FILE" "plan.md"
        check_file "$TASKS_FILE" "tasks.md"
        check_file "$STATE_FILE" "workflow state"
        ;;

    7) # Implement
        check_dir "$FEATURE_DIR" "feature directory"
        check_file "$TASKS_FILE" "tasks.md"
        check_file "$STATE_FILE" "workflow state"
        # Verify tasks exist
        if [ -f "$TASKS_FILE" ]; then
            local task_count
            task_count=$(grep -cE '^[[:space:]]*-[[:space:]]*\[[ Xx]\][[:space:]]*T[0-9]+:' "$TASKS_FILE" | tr -d ' ' || echo "0")
            if [ "$task_count" -eq 0 ]; then
                MISSING+=("tasks in tasks.md")
            else
                PRESENT+=("$task_count tasks ready")
            fi
        fi
        ;;

    8) # Verify
        check_dir "$FEATURE_DIR" "feature directory"
        check_file "$TASKS_FILE" "tasks.md"
        check_file "$STATE_FILE" "workflow state"
        # Need at least 50% tasks complete to start verify
        check_tasks_status 50 "implementation progress"
        ;;

    9) # Review
        check_dir "$FEATURE_DIR" "feature directory"
        check_file "$TASKS_FILE" "tasks.md"
        check_file "$STATE_FILE" "workflow state"
        check_file "$VERIFICATION_REPORT" "verification-report.md"
        ;;

    10) # Complete
        check_dir "$FEATURE_DIR" "feature directory"
        check_file "$TASKS_FILE" "tasks.md"
        check_file "$STATE_FILE" "workflow state"
        check_file "$VERIFICATION_REPORT" "verification-report.md"
        check_file "$REVIEW_REPORT" "review-report.md"
        # Check review passed
        if [ -f "$REVIEW_REPORT" ]; then
            if grep -qE 'Overall.*PASS' "$REVIEW_REPORT"; then
                PRESENT+=("review passed")
            else
                MISSING+=("passing review (check review-report.md)")
            fi
        fi
        ;;

    *)
        log_error "Unknown phase: $PHASE"
        exit 1
        ;;
esac

# ==============================================================================
# Output Result
# ==============================================================================

MISSING_COUNT=${#MISSING[@]}
PRESENT_COUNT=${#PRESENT[@]}

if [ "$MISSING_COUNT" -eq 0 ]; then
    STATUS="ready"
    EXIT_CODE=0
else
    STATUS="blocked"
    EXIT_CODE=1
fi

# Build JSON output (use json_escape for safety)
{
    echo "{"
    echo "  \"status\": \"$STATUS\","
    echo "  \"phase\": $PHASE,"
    echo "  \"featureDir\": \"$(json_escape "$FEATURE_DIR")\","
    echo "  \"present\": ["
    for i in "${!PRESENT[@]}"; do
        if [ "$i" -gt 0 ]; then echo ","; fi
        echo -n "    \"$(json_escape "${PRESENT[$i]}")\""
    done
    if [ "$PRESENT_COUNT" -gt 0 ]; then echo; fi
    echo "  ],"
    echo "  \"missing\": ["
    for i in "${!MISSING[@]}"; do
        if [ "$i" -gt 0 ]; then echo ","; fi
        echo -n "    \"$(json_escape "${MISSING[$i]}")\""
    done
    if [ "$MISSING_COUNT" -gt 0 ]; then echo; fi
    echo "  ],"
    echo "  \"ready\": $( [ "$STATUS" = "ready" ] && echo "true" || echo "false" )"
    echo "}"
}

exit $EXIT_CODE
