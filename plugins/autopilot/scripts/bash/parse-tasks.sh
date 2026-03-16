#!/usr/bin/env bash
# parse-tasks.sh - Parse tasks.md and extract task information
# Usage: parse-tasks.sh --file <path> [--status all|incomplete|complete]
# Output: JSON array of tasks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# ==============================================================================
# Argument Parsing
# ==============================================================================

TASKS_FILE=""
STATUS_FILTER="all"

while [[ $# -gt 0 ]]; do
    case $1 in
        --file)
            TASKS_FILE="$2"
            shift 2
            ;;
        --status)
            STATUS_FILTER="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 --file <path> [--status all|incomplete|complete]"
            echo ""
            echo "Options:"
            echo "  --file    Path to tasks.md"
            echo "  --status  Filter by status (default: all)"
            echo "            all        - All tasks"
            echo "            incomplete - Only [ ] tasks"
            echo "            complete   - Only [x] tasks"
            echo ""
            echo "Output: JSON array of task objects"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [ -z "$TASKS_FILE" ]; then
    log_error "Missing required argument: --file"
    exit 1
fi

# ==============================================================================
# Main Logic
# ==============================================================================

REPO_ROOT=$(get_repo_root)

# Resolve path
if [[ "$TASKS_FILE" != /* ]]; then
    TASKS_FILE="$REPO_ROOT/$TASKS_FILE"
fi

if [ ! -f "$TASKS_FILE" ]; then
    log_error "Tasks file not found: $TASKS_FILE"
    exit 1
fi

# Parse with Node.js for reliable processing
# SECURITY: Pass values via environment variables to prevent injection
if command -v node >/dev/null 2>&1; then
    TASKS_FILE_PATH="$TASKS_FILE" STATUS_FILTER_VAL="$STATUS_FILTER" node -e '
        const fs = require("fs");
        const content = fs.readFileSync(process.env.TASKS_FILE_PATH, "utf8");
        const lines = content.split("\n");

        const tasks = [];
        let currentTask = null;
        let currentPhase = "";

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const lineNum = i + 1;

            // Phase header (## Phase N: Name)
            const phaseMatch = line.match(/^##\s+(.+)/);
            if (phaseMatch) {
                currentPhase = phaseMatch[1].trim();
                continue;
            }

            // Task line: - [X] T001: Description or - [ ] T001: Description
            const taskMatch = line.match(/^\s*-\s*\[([Xx ])\]\s*(T\d+):\s*(.+)/);
            if (taskMatch) {
                // Save previous task
                if (currentTask) {
                    tasks.push(currentTask);
                }

                const isComplete = taskMatch[1].toLowerCase() === "x";
                currentTask = {
                    id: taskMatch[2],
                    description: taskMatch[3].trim(),
                    complete: isComplete,
                    phase: currentPhase,
                    line: lineNum,
                    verify: null,
                    subtasks: []
                };
                continue;
            }

            // Verify line: **Verify**: TYPE | condition
            if (currentTask) {
                const verifyMatch = line.match(/\*\*Verify\*\*:\s*(\w+)\s*\|\s*(.+)/);
                if (verifyMatch) {
                    currentTask.verify = {
                        type: verifyMatch[1].trim(),
                        condition: verifyMatch[2].trim()
                    };
                    continue;
                }

                // Subtask: - Sub-item
                const subtaskMatch = line.match(/^\s{2,}-\s+(.+)/);
                if (subtaskMatch && !line.includes("**Verify**")) {
                    currentTask.subtasks.push(subtaskMatch[1].trim());
                }
            }
        }

        // Dont forget last task
        if (currentTask) {
            tasks.push(currentTask);
        }

        // Apply status filter
        const filter = process.env.STATUS_FILTER_VAL;
        let filtered = tasks;
        if (filter === "incomplete") {
            filtered = tasks.filter(t => !t.complete);
        } else if (filter === "complete") {
            filtered = tasks.filter(t => t.complete);
        }

        // Output
        const result = {
            file: process.env.TASKS_FILE_PATH,
            filter: filter,
            total: tasks.length,
            complete: tasks.filter(t => t.complete).length,
            incomplete: tasks.filter(t => !t.complete).length,
            tasks: filtered
        };

        console.log(JSON.stringify(result, null, 2));
    '
else
    # Fallback: basic grep-based extraction
    log_warning "Node.js not available, using basic extraction"

    TOTAL=$(grep -cE '^[[:space:]]*-[[:space:]]*\[[ Xx]\][[:space:]]*T[0-9]+:' "$TASKS_FILE" | tr -d ' ' || echo "0")
    COMPLETE=$(grep -cE '^[[:space:]]*-[[:space:]]*\[[Xx]\][[:space:]]*T[0-9]+:' "$TASKS_FILE" | tr -d ' ' || echo "0")
    INCOMPLETE=$((TOTAL - COMPLETE))

    # Extract task IDs based on filter
    case "$STATUS_FILTER" in
        incomplete)
            PATTERN='^[[:space:]]*-[[:space:]]*\[ \][[:space:]]*(T[0-9]+):'
            ;;
        complete)
            PATTERN='^[[:space:]]*-[[:space:]]*\[[Xx]\][[:space:]]*(T[0-9]+):'
            ;;
        *)
            PATTERN='^[[:space:]]*-[[:space:]]*\[[ Xx]\][[:space:]]*(T[0-9]+):'
            ;;
    esac

    # Collect tasks into array to avoid subshell issues
    TASK_JSON_ITEMS=()
    while IFS=: read -r line_num rest; do
        [ -z "$line_num" ] && continue
        TASK_ID=$(echo "$rest" | grep -oE 'T[0-9]+' | head -1)
        DESC=$(echo "$rest" | sed 's/.*T[0-9][0-9]*:[[:space:]]*//')
        IS_COMPLETE=$(echo "$rest" | grep -qE '\[[Xx]\]' && echo "true" || echo "false")
        # Escape description for JSON
        DESC_ESC=$(json_escape "$DESC")
        TASK_JSON_ITEMS+=("{\"id\": \"$TASK_ID\", \"line\": $line_num, \"complete\": $IS_COMPLETE, \"description\": \"$DESC_ESC\"}")
    done < <(grep -nE "$PATTERN" "$TASKS_FILE" 2>/dev/null || true)

    # Output JSON
    {
        echo "{"
        echo "  \"file\": \"$(json_escape "$TASKS_FILE")\","
        echo "  \"filter\": \"$STATUS_FILTER\","
        echo "  \"total\": $TOTAL,"
        echo "  \"complete\": $COMPLETE,"
        echo "  \"incomplete\": $INCOMPLETE,"
        echo "  \"tasks\": ["
        FIRST=true
        for item in "${TASK_JSON_ITEMS[@]}"; do
            if [ "$FIRST" = "true" ]; then
                FIRST=false
            else
                echo ","
            fi
            echo -n "    $item"
        done
        if [ ${#TASK_JSON_ITEMS[@]} -gt 0 ]; then echo; fi
        echo "  ]"
        echo "}"
    }
fi
