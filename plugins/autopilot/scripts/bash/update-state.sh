#!/usr/bin/env bash
# update-state.sh - Atomic state file operations
# Usage: update-state.sh --state-file <path> --set <key>=<value> [--set <key>=<value>...]
#        update-state.sh --state-file <path> --push <array>=<value>
#        update-state.sh --state-file <path> --get <key>
# Output: Updated state JSON or requested value

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# ==============================================================================
# Argument Parsing
# ==============================================================================

STATE_FILE=""
OPERATION=""
SETS=()
PUSH_ARRAY=""
PUSH_VALUE=""
GET_KEY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --state-file)
            STATE_FILE="$2"
            shift 2
            ;;
        --set)
            OPERATION="set"
            SETS+=("$2")
            shift 2
            ;;
        --push)
            OPERATION="push"
            PUSH_ARRAY="${2%%=*}"
            PUSH_VALUE="${2#*=}"
            shift 2
            ;;
        --get)
            OPERATION="get"
            GET_KEY="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 --state-file <path> <operation>"
            echo ""
            echo "Operations:"
            echo "  --set <key>=<value>    Set a top-level key (repeatable)"
            echo "  --push <array>=<value> Push value to array"
            echo "  --get <key>            Get value of key"
            echo ""
            echo "Examples:"
            echo "  $0 --state-file state.json --set currentPhase=5 --set status=implementing"
            echo "  $0 --state-file state.json --push completedTasks=T001"
            echo "  $0 --state-file state.json --get currentPhase"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [ -z "$STATE_FILE" ]; then
    log_error "Missing required argument: --state-file"
    exit 1
fi

if [ -z "$OPERATION" ]; then
    log_error "No operation specified. Use --set, --push, or --get"
    exit 1
fi

# ==============================================================================
# Validation
# ==============================================================================

REPO_ROOT=$(get_repo_root)

# Resolve to absolute path
if [[ "$STATE_FILE" != /* ]]; then
    STATE_FILE="$REPO_ROOT/$STATE_FILE"
fi

# Security: validate path is within repo
REAL_PATH=$(realpath "$STATE_FILE" 2>/dev/null || echo "")

# SECURITY: Fail if realpath returns empty (file doesn't exist or path is invalid)
if [ -z "$REAL_PATH" ]; then
    log_error "Invalid state file path: cannot resolve"
    exit 1
fi

case "$REAL_PATH" in
    "$REPO_ROOT"/*) ;;
    *)
        log_error "State file must be within project directory"
        exit 1
        ;;
esac

# Must be .json file
if ! echo "$STATE_FILE" | grep -qE '\.json$'; then
    log_error "State file must be a .json file"
    exit 1
fi

# ==============================================================================
# File Locking (prevents race conditions with concurrent autopilot runs)
# ==============================================================================

LOCK_FILE="${STATE_FILE}.lock"

acquire_lock() {
    # Create lock file directory if needed
    mkdir -p "$(dirname "$LOCK_FILE")"

    # Use flock if available (Linux), otherwise fall back to mkdir-based locking
    if command -v flock >/dev/null 2>&1; then
        exec 200>"$LOCK_FILE"
        if ! flock -n 200; then
            log_error "Another autopilot process is updating state. Please wait."
            exit 1
        fi
    else
        # macOS fallback: mkdir is atomic
        if ! mkdir "$LOCK_FILE" 2>/dev/null; then
            log_error "Another autopilot process is updating state. Please wait."
            exit 1
        fi
        trap 'rmdir "$LOCK_FILE" 2>/dev/null' EXIT
    fi
}

release_lock() {
    if command -v flock >/dev/null 2>&1; then
        # flock releases automatically when fd closes
        :
    else
        rmdir "$LOCK_FILE" 2>/dev/null || true
    fi
}

# ==============================================================================
# Operations
# ==============================================================================

case "$OPERATION" in
    get)
        if [ ! -f "$STATE_FILE" ]; then
            log_error "State file not found: $STATE_FILE"
            exit 1
        fi

        # Use node for reliable JSON parsing
        # SECURITY: Pass values via environment variables to prevent injection
        if command -v node >/dev/null 2>&1; then
            STATE_FILE_PATH="$STATE_FILE" GET_KEY_NAME="$GET_KEY" node -e '
                const fs = require("fs");
                const state = JSON.parse(fs.readFileSync(process.env.STATE_FILE_PATH, "utf8"));
                const keys = process.env.GET_KEY_NAME.split(".");
                let value = state;
                for (const key of keys) {
                    value = value?.[key];
                }
                if (value === undefined) {
                    process.exit(1);
                }
                console.log(typeof value === "object" ? JSON.stringify(value) : value);
            '
        else
            # Fallback to grep/sed for simple cases
            grep "\"$GET_KEY\"" "$STATE_FILE" | sed 's/.*: *"\?\([^",}]*\)"\?.*/\1/' | head -1
        fi
        ;;

    set)
        if [ ! -f "$STATE_FILE" ]; then
            log_error "State file not found: $STATE_FILE"
            exit 1
        fi

        # Acquire lock to prevent concurrent modifications
        acquire_lock

        # Build node script for atomic update
        TEMP_FILE=$(mktemp)
        UPDATES_FILE=$(mktemp)
        trap 'rm -f "$TEMP_FILE" "$UPDATES_FILE"' EXIT

        # Write updates to a temp file (avoids shell escaping issues)
        for update in "${SETS[@]}"; do
            echo "$update" >> "$UPDATES_FILE"
        done

        # SECURITY: Pass file paths via environment variables to prevent injection
        if command -v node >/dev/null 2>&1; then
            STATE_FILE_PATH="$STATE_FILE" UPDATES_FILE_PATH="$UPDATES_FILE" TEMP_FILE_PATH="$TEMP_FILE" node -e '
                const fs = require("fs");
                const state = JSON.parse(fs.readFileSync(process.env.STATE_FILE_PATH, "utf8"));
                const updates = fs.readFileSync(process.env.UPDATES_FILE_PATH, "utf8").trim().split("\n");

                for (const update of updates) {
                    const eqIndex = update.indexOf("=");
                    if (eqIndex === -1) continue;
                    const key = update.slice(0, eqIndex);
                    let value = update.slice(eqIndex + 1);

                    // Try to parse as JSON, otherwise keep as string
                    try {
                        value = JSON.parse(value);
                    } catch {}

                    // Handle nested keys
                    const keys = key.split(".");
                    let obj = state;
                    for (let i = 0; i < keys.length - 1; i++) {
                        if (!obj[keys[i]]) obj[keys[i]] = {};
                        obj = obj[keys[i]];
                    }
                    obj[keys[keys.length - 1]] = value;
                }

                // Update timestamp
                state.updatedAt = new Date().toISOString();

                fs.writeFileSync(process.env.TEMP_FILE_PATH, JSON.stringify(state, null, 2));
            '
            mv "$TEMP_FILE" "$STATE_FILE"
            log_success "Updated state file"
            cat "$STATE_FILE"
        else
            log_error "Node.js required for state updates"
            exit 1
        fi
        ;;

    push)
        if [ ! -f "$STATE_FILE" ]; then
            log_error "State file not found: $STATE_FILE"
            exit 1
        fi

        # Acquire lock to prevent concurrent modifications
        acquire_lock

        TEMP_FILE=$(mktemp)
        VALUE_FILE=$(mktemp)
        trap 'rm -f "$TEMP_FILE" "$VALUE_FILE"' EXIT

        # Write value to temp file to avoid shell escaping issues
        printf '%s' "$PUSH_VALUE" > "$VALUE_FILE"

        # SECURITY: Pass all paths via environment variables to prevent injection
        if command -v node >/dev/null 2>&1; then
            STATE_FILE_PATH="$STATE_FILE" VALUE_FILE_PATH="$VALUE_FILE" TEMP_FILE_PATH="$TEMP_FILE" ARRAY_KEY="$PUSH_ARRAY" node -e '
                const fs = require("fs");
                const state = JSON.parse(fs.readFileSync(process.env.STATE_FILE_PATH, "utf8"));

                const arrayKey = process.env.ARRAY_KEY;
                let value = fs.readFileSync(process.env.VALUE_FILE_PATH, "utf8");

                // Try to parse as JSON
                try {
                    value = JSON.parse(value);
                } catch {}

                // Initialize array if needed
                if (!Array.isArray(state[arrayKey])) {
                    state[arrayKey] = [];
                }

                // Avoid duplicates for simple values
                if (typeof value === "string" && state[arrayKey].includes(value)) {
                    console.log(JSON.stringify({ status: "already_exists", array: arrayKey, value }));
                    process.exit(0);
                }

                state[arrayKey].push(value);
                state.updatedAt = new Date().toISOString();

                fs.writeFileSync(process.env.TEMP_FILE_PATH, JSON.stringify(state, null, 2));
                console.log(JSON.stringify({ status: "pushed", array: arrayKey, value, length: state[arrayKey].length }));
            '
            # Only move if temp file was written (not on duplicate detection early exit)
            if [ -s "$TEMP_FILE" ]; then
                mv "$TEMP_FILE" "$STATE_FILE"
            fi
        else
            log_error "Node.js required for state updates"
            exit 1
        fi
        ;;
esac
