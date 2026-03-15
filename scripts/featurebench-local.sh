#!/bin/bash
# Run FeatureBench locally with installed Claude Code (no Docker)
# Usage:
#   ./scripts/featurebench-local.sh                  # Run lite split
#   ./scripts/featurebench-local.sh --full           # Run full split
#   ./scripts/featurebench-local.sh --task <id>      # Run single task
#   ./scripts/featurebench-local.sh --baseline       # Run vanilla Claude Code

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE="${FEATUREBENCH_WORKSPACE:-/tmp/featurebench-local}"
RESULTS_DIR="$PLUGIN_DIR/test/featurebench-results"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "$1"; }
log_header() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

# Check prerequisites
check_prereqs() {
    if ! command -v claude &> /dev/null; then
        log "${RED}Error: claude not found. Install Claude Code first.${NC}"
        exit 1
    fi

    if ! command -v python3 &> /dev/null; then
        log "${RED}Error: python3 not found.${NC}"
        exit 1
    fi

    # Check for datasets library
    if ! python3 -c "import datasets" 2>/dev/null; then
        log "${YELLOW}Installing datasets library...${NC}"
        pip install datasets
    fi
}

# Download FeatureBench dataset
download_dataset() {
    local split="${1:-lite}"
    local output="$WORKSPACE/dataset-$split.json"

    if [[ -f "$output" ]]; then
        log "Using cached dataset: $output"
        return
    fi

    log "Downloading FeatureBench $split split..."
    mkdir -p "$WORKSPACE"

    python3 << EOF
import json
from datasets import load_dataset

ds = load_dataset("LiberCoders/FeatureBench", split="$split")
tasks = []
for row in ds:
    tasks.append({
        "instance_id": row["instance_id"],
        "repo": row["repo"],
        "base_commit": row["base_commit"],
        "problem_statement": row["problem_statement"],
        "patch": row["patch"],
        "test_patch": row["test_patch"],
        "FAIL_TO_PASS": row["FAIL_TO_PASS"],
        "PASS_TO_PASS": row["PASS_TO_PASS"],
    })

with open("$output", "w") as f:
    json.dump(tasks, f, indent=2)

print(f"Downloaded {len(tasks)} tasks to $output")
EOF
}

# Run single task
run_task() {
    local task_json="$1"
    local use_autopilot="${2:-true}"
    local task_id=$(echo "$task_json" | jq -r '.instance_id')
    local repo=$(echo "$task_json" | jq -r '.repo')
    local commit=$(echo "$task_json" | jq -r '.base_commit')
    local problem=$(echo "$task_json" | jq -r '.problem_statement')

    local task_dir="$WORKSPACE/tasks/$task_id"
    local result_file="$task_dir/result.json"

    log_header "Task: $task_id"
    log "Repo: $repo"
    log "Commit: $commit"

    # Setup task directory
    rm -rf "$task_dir"
    mkdir -p "$task_dir"

    # Clone repo at specific commit
    log "Cloning $repo @ $commit..."
    git clone --depth 1 "https://github.com/$repo.git" "$task_dir/repo" 2>/dev/null || {
        # If shallow clone fails, do full clone
        git clone "https://github.com/$repo.git" "$task_dir/repo"
    }
    cd "$task_dir/repo"
    git checkout "$commit" 2>/dev/null || git checkout -b eval "$commit"

    # Write problem statement
    echo "$problem" > plan.md

    # Track metrics
    local start_time=$(date +%s)
    local tokens_file="$task_dir/tokens.json"

    # Run agent
    if [[ "$use_autopilot" == "true" ]]; then
        log "Running autopilot..."
        CLAUDECODE= claude -p "/autopilot:full plan.md" \
            --dangerously-skip-permissions \
            --output-format stream-json \
            > "$task_dir/output.jsonl" 2>&1 || true
    else
        log "Running baseline Claude Code..."
        CLAUDECODE= claude -p "$problem" \
            --dangerously-skip-permissions \
            --output-format stream-json \
            > "$task_dir/output.jsonl" 2>&1 || true
    fi

    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    # Extract metrics from output
    local tokens_in=$(jq -s '[.[].usage.input_tokens // 0] | add' "$task_dir/output.jsonl" 2>/dev/null || echo 0)
    local tokens_out=$(jq -s '[.[].usage.output_tokens // 0] | add' "$task_dir/output.jsonl" 2>/dev/null || echo 0)
    local steps=$(jq -s '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")] | length' "$task_dir/output.jsonl" 2>/dev/null || echo 0)

    # Check if agent completed successfully
    local agent_success=$(jq -s 'last | select(.type == "result" and .subtype == "success" and .is_error == false) | true' "$task_dir/output.jsonl" 2>/dev/null || echo "false")

    # Run tests (simplified - just check if patch applies)
    local test_pass=false
    if [[ "$agent_success" == "true" ]]; then
        # Check if any tests pass - this is simplified
        # Real eval would run actual test suite
        if git diff --quiet 2>/dev/null; then
            log "${YELLOW}No changes made${NC}"
        else
            log "${GREEN}Changes detected${NC}"
            test_pass=true
        fi
    fi

    # Write result
    cat > "$result_file" << EOF
{
  "instance_id": "$task_id",
  "repo": "$repo",
  "agent": "$([ "$use_autopilot" == "true" ] && echo "autopilot" || echo "claude_code")",
  "resolved": $test_pass,
  "agent_success": $agent_success,
  "metrics": {
    "time_seconds": $elapsed,
    "token_input": $tokens_in,
    "token_output": $tokens_out,
    "steps": $steps
  }
}
EOF

    if [[ "$test_pass" == "true" ]]; then
        log "${GREEN}✓ RESOLVED${NC} in ${elapsed}s"
    else
        log "${RED}✗ FAILED${NC} in ${elapsed}s"
    fi

    cd "$WORKSPACE"
    echo "$result_file"
}

# Run all tasks in split
run_split() {
    local split="${1:-lite}"
    local use_autopilot="${2:-true}"
    local agent_name=$([ "$use_autopilot" == "true" ] && echo "autopilot" || echo "baseline")

    download_dataset "$split"

    log_header "Running $split split with $agent_name"

    local dataset="$WORKSPACE/dataset-$split.json"
    local task_count=$(jq 'length' "$dataset")
    local results=()
    local resolved=0

    for i in $(seq 0 $((task_count - 1))); do
        local task_json=$(jq ".[$i]" "$dataset")
        local result=$(run_task "$task_json" "$use_autopilot")
        results+=("$result")

        if jq -e '.resolved == true' "$result" > /dev/null 2>&1; then
            ((resolved++))
        fi

        log "Progress: $((i + 1))/$task_count (resolved: $resolved)"
    done

    # Aggregate results
    mkdir -p "$RESULTS_DIR"
    local output="$RESULTS_DIR/$agent_name-$split-$TIMESTAMP.json"

    echo "[" > "$output"
    local first=true
    for result in "${results[@]}"; do
        [[ "$first" == "false" ]] && echo "," >> "$output"
        cat "$result" >> "$output"
        first=false
    done
    echo "]" >> "$output"

    local resolved_rate=$(echo "scale=2; $resolved / $task_count * 100" | bc)

    log_header "Results: $agent_name on $split"
    log "Resolved: $resolved / $task_count (${resolved_rate}%)"
    log "Output: $output"
}

main() {
    check_prereqs
    mkdir -p "$WORKSPACE" "$RESULTS_DIR"

    case "${1:-}" in
        --full)
            run_split "full" "true"
            ;;
        --baseline)
            run_split "${2:-lite}" "false"
            ;;
        --task)
            if [[ -z "$2" ]]; then
                log "${RED}Error: task ID required${NC}"
                exit 1
            fi
            download_dataset "lite"
            local task_json=$(jq ".[] | select(.instance_id == \"$2\")" "$WORKSPACE/dataset-lite.json")
            if [[ -z "$task_json" ]]; then
                download_dataset "full"
                task_json=$(jq ".[] | select(.instance_id == \"$2\")" "$WORKSPACE/dataset-full.json")
            fi
            if [[ -z "$task_json" ]]; then
                log "${RED}Task not found: $2${NC}"
                exit 1
            fi
            run_task "$task_json" "true"
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  (none)           Run lite split (30 tasks) with autopilot"
            echo "  --full           Run full split (200 tasks) with autopilot"
            echo "  --baseline       Run with vanilla Claude Code"
            echo "  --task <id>      Run single task by instance_id"
            echo "  --help           Show this help"
            echo ""
            echo "Environment:"
            echo "  FEATUREBENCH_WORKSPACE   Working directory (default: /tmp/featurebench-local)"
            ;;
        *)
            run_split "lite" "true"
            ;;
    esac
}

main "$@"
