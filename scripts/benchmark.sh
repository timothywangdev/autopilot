#!/bin/bash
# FeatureBench-aligned benchmark runner for autopilot
# Usage:
#   ./scripts/benchmark.sh                    # Run all benchmarks
#   ./scripts/benchmark.sh l1-add-endpoint    # Run specific task
#   ./scripts/benchmark.sh --report           # Show latest results

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
BENCHMARKS_DIR="$PLUGIN_DIR/test/benchmarks"
TASKS_DIR="$BENCHMARKS_DIR/tasks"
RESULTS_DIR="$BENCHMARKS_DIR/results"
WORKSPACE="/tmp/autopilot-benchmark"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "$1"; }
log_header() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

show_report() {
    local latest="$RESULTS_DIR/benchmark-latest.json"
    if [[ ! -f "$latest" ]]; then
        log "${RED}No benchmark results found.${NC}"
        log "Run: ./scripts/benchmark.sh"
        exit 1
    fi

    log_header "Autopilot Benchmark Report"

    jq -r '
        "Timestamp: \(.metadata.timestamp)",
        "Model: \(.metadata.model)",
        "",
        "== Summary ==",
        "Resolved Rate: \(.summary.resolved_rate * 100 | floor)%",
        "Passed Rate: \(.summary.passed_rate * 100 | floor)%",
        "Human Intervention: \(.summary.human_intervention_rate * 100 | floor)%",
        "Avg Time: \(.summary.avg_time | floor)s",
        "Avg Steps: \(.summary.avg_steps)",
        "Avg Tokens: \(.summary.avg_tokens)",
        "",
        "== By Task =="
    ' "$latest"

    jq -r '
        .tasks[] |
        "  \(.id) [\(.level)]: \(if .resolved then "✓ RESOLVED" else "✗ FAILED" end) (\(.metrics.passed_rate * 100 | floor)% passed, \(.metrics.steps) steps, \(.metrics.time_seconds | floor)s)"
    ' "$latest"

    echo ""
    log "Full results: $latest"
}

run_task() {
    local task_id="$1"
    local task_dir="$TASKS_DIR/$task_id"
    local work_dir="$WORKSPACE/$task_id"

    if [[ ! -d "$task_dir" ]]; then
        log "${RED}Task not found: $task_id${NC}"
        log "Available tasks:"
        ls -1 "$TASKS_DIR" 2>/dev/null | sed 's/^/  /'
        exit 1
    fi

    log_header "Running: $task_id"

    # Setup workspace
    rm -rf "$work_dir"
    mkdir -p "$work_dir"

    # Run setup script
    log "Setting up baseline project..."
    chmod +x "$task_dir/setup.sh"
    "$task_dir/setup.sh" "$work_dir"

    # Copy task description as plan file
    cp "$task_dir/task.md" "$work_dir/plan.md"

    # Track metrics
    local start_time=$(date +%s)
    local token_log="$work_dir/.token-usage.json"

    # Run autopilot:full
    log "Running autopilot:full..."
    cd "$work_dir"

    # Bypass nested session, capture output for token counting
    CLAUDECODE= claude -p "/autopilot:full plan.md" \
        --dangerously-skip-permissions \
        --output-format json \
        > "$work_dir/.autopilot-output.json" 2>&1 || true

    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    # Extract token usage from output
    local tokens_in=$(jq -r '[.[] | select(.type == "result") | .usage.input_tokens // 0] | add // 0' "$work_dir/.autopilot-output.json" 2>/dev/null || echo "0")
    local tokens_out=$(jq -r '[.[] | select(.type == "result") | .usage.output_tokens // 0] | add // 0' "$work_dir/.autopilot-output.json" 2>/dev/null || echo "0")
    local steps=$(jq -r '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")] | length // 0' "$work_dir/.autopilot-output.json" 2>/dev/null || echo "0")
    local human_interventions=$(grep -c "AskUserQuestion" "$work_dir/.autopilot-output.json" 2>/dev/null || echo "0")

    # Run verification
    log "Running verification..."
    chmod +x "$task_dir/verify.sh"
    "$task_dir/verify.sh" "$work_dir" "$work_dir/verify-results.json" || true

    # Read verification results
    local verify_results="$work_dir/verify-results.json"
    local passed_rate=$(jq -r '.passed_rate // 0' "$verify_results" 2>/dev/null || echo "0")
    local resolved=$(jq -r '.resolved // false' "$verify_results" 2>/dev/null || echo "false")

    # Determine level from task.md
    local level=$(grep -oP '(?<=\*\*Difficulty\*\*: )L[123]' "$task_dir/task.md" || echo "L1")

    # Output task result
    cat > "$work_dir/result.json" << EOF
{
  "id": "$task_id",
  "name": "$(head -1 "$task_dir/task.md" | sed 's/^# //')",
  "level": "$level",
  "resolved": $resolved,
  "metrics": {
    "passed_rate": $passed_rate,
    "token_input": $tokens_in,
    "token_output": $tokens_out,
    "steps": $steps,
    "time_seconds": $elapsed,
    "human_interventions": $human_interventions,
    "error_recoveries": 0,
    "errors_fatal": 0
  },
  "verifications": $(jq '.verifications // []' "$verify_results" 2>/dev/null || echo "[]")
}
EOF

    # Print summary
    if [[ "$resolved" == "true" ]]; then
        log "${GREEN}✓ RESOLVED${NC} in ${elapsed}s ($steps steps, $((tokens_in + tokens_out)) tokens)"
    else
        log "${RED}✗ FAILED${NC} - ${passed_rate}% passed"
    fi

    echo "$work_dir/result.json"
}

aggregate_results() {
    local results=("$@")
    local timestamp=$(date -Iseconds)
    local output="$RESULTS_DIR/benchmark-$(date +%Y%m%d-%H%M%S).json"

    mkdir -p "$RESULTS_DIR"

    # Combine all task results
    local tasks_json="["
    local first=true
    for result in "${results[@]}"; do
        if [[ -f "$result" ]]; then
            [[ "$first" == "false" ]] && tasks_json+=","
            tasks_json+=$(cat "$result")
            first=false
        fi
    done
    tasks_json+="]"

    # Calculate summary
    local summary=$(echo "$tasks_json" | jq '
        {
            resolved_rate: ([.[] | select(.resolved)] | length) / length,
            passed_rate: ([.[].metrics.passed_rate] | add) / length,
            human_intervention_rate: ([.[].metrics.human_interventions] | add) / ([.[] | 1] | add),
            avg_time: ([.[].metrics.time_seconds] | add) / length,
            avg_tokens: (([.[].metrics.token_input] | add) + ([.[].metrics.token_output] | add)) / length | floor,
            avg_steps: ([.[].metrics.steps] | add) / length | floor
        }
    ')

    # Write final benchmark result
    cat > "$output" << EOF
{
  "metadata": {
    "timestamp": "$timestamp",
    "autopilot_version": "1.0.0",
    "model": "claude-opus-4-5",
    "executor": "claude-code"
  },
  "tasks": $tasks_json,
  "summary": $summary
}
EOF

    cp "$output" "$RESULTS_DIR/benchmark-latest.json"
    log "\n${GREEN}Results saved: $output${NC}"
}

main() {
    case "${1:-}" in
        --report|-r)
            show_report
            ;;
        --help|-h)
            echo "Usage: $0 [task-id] [options]"
            echo ""
            echo "Commands:"
            echo "  (none)          Run all benchmark tasks"
            echo "  <task-id>       Run specific task (e.g., l1-add-endpoint)"
            echo ""
            echo "Options:"
            echo "  --report        Show latest benchmark results"
            echo "  --help          Show this help"
            echo ""
            echo "Available tasks:"
            ls -1 "$TASKS_DIR" 2>/dev/null | sed 's/^/  /'
            ;;
        "")
            # Run all tasks
            log_header "Autopilot FeatureBench"
            log "Running all benchmark tasks...\n"

            results=()
            for task_dir in "$TASKS_DIR"/*/; do
                task_id=$(basename "$task_dir")
                result=$(run_task "$task_id")
                results+=("$result")
            done

            aggregate_results "${results[@]}"
            show_report
            ;;
        *)
            # Run specific task
            result=$(run_task "$1")
            aggregate_results "$result"
            show_report
            ;;
    esac
}

main "$@"
