#!/bin/bash
# Autopilot Plugin Evaluation Runner
# Wrapper around skill-creator evals
#
# Usage:
#   ./test/run-evals.sh              # Run all evals
#   ./test/run-evals.sh full         # Run specific command evals
#   ./test/run-evals.sh --benchmark  # Run benchmarks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PLUGIN_DIR/test/results"
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
check_prerequisites() {
    log_header "Checking Prerequisites"

    if ! command -v claude &> /dev/null; then
        log "${RED}Error: claude command not found${NC}"
        log "Install: npm install -g @anthropic/claude-code"
        exit 1
    fi

    if [[ -n "$CLAUDECODE" ]]; then
        log "${RED}Error: Cannot run inside Claude Code session${NC}"
        log "Run this script in a regular terminal."
        exit 1
    fi

    # Check plugins
    if ! claude plugin list 2>/dev/null | grep -q "autopilot"; then
        log "${YELLOW}Installing autopilot plugin...${NC}"
        claude plugin install autopilot
    fi

    if ! claude plugin list 2>/dev/null | grep -q "skill-creator"; then
        log "${YELLOW}Installing skill-creator plugin...${NC}"
        claude plugin install skill-creator
    fi

    mkdir -p "$RESULTS_DIR"
    log "${GREEN}Prerequisites OK${NC}"
}

# Run evals using skill-creator
run_evals() {
    local target="${1:-autopilot}"
    local result_file="$RESULTS_DIR/eval-${target//:/-}-$TIMESTAMP.json"

    log_header "Running Evals: $target"

    # Run skill-creator eval and capture output
    if claude -p "/skill-creator eval $target" --output-format json > "$result_file" 2>&1; then
        log "${GREEN}Evals completed${NC}"
    else
        log "${YELLOW}Evals completed with issues${NC}"
    fi

    # Parse and display results
    if command -v jq &> /dev/null && [[ -f "$result_file" ]]; then
        local pass_count=$(jq '.results | map(select(.status == "pass")) | length' "$result_file" 2>/dev/null || echo "?")
        local fail_count=$(jq '.results | map(select(.status == "fail")) | length' "$result_file" 2>/dev/null || echo "?")
        local total=$(jq '.results | length' "$result_file" 2>/dev/null || echo "?")

        log "\n${GREEN}PASS${NC}: $pass_count"
        log "${RED}FAIL${NC}: $fail_count"
        log "Total: $total"
        log "\nResults: $result_file"
    else
        log "Results saved to: $result_file"
        log "(Install jq for parsed summary)"
    fi

    echo "$result_file"
}

# Run benchmarks
run_benchmarks() {
    local result_file="$RESULTS_DIR/benchmark-$TIMESTAMP.json"

    log_header "Running Benchmarks"

    if claude -p "/skill-creator benchmark autopilot" --output-format json > "$result_file" 2>&1; then
        log "${GREEN}Benchmarks completed${NC}"
    else
        log "${YELLOW}Benchmarks completed with issues${NC}"
    fi

    # Parse and display results
    if command -v jq &> /dev/null && [[ -f "$result_file" ]]; then
        log "\nBenchmark Results:"
        jq -r '.benchmarks[] | "  \(.name): \(.elapsed_time)s, \(.token_usage) tokens"' "$result_file" 2>/dev/null || cat "$result_file"
    fi

    log "\nResults: $result_file"
}

# Run all commands' evals
run_all() {
    local commands=("init" "specify" "plan" "tasks" "analyze" "full")
    local results=()

    log_header "Running All Evals"

    for cmd in "${commands[@]}"; do
        log "\n${BLUE}--- autopilot:$cmd ---${NC}"
        result_file=$(run_evals "autopilot:$cmd")
        results+=("$result_file")
    done

    # Summary
    log_header "Summary"
    for result in "${results[@]}"; do
        if [[ -f "$result" ]] && command -v jq &> /dev/null; then
            local name=$(basename "$result" .json)
            local pass=$(jq '.results | map(select(.status == "pass")) | length' "$result" 2>/dev/null || echo "?")
            local total=$(jq '.results | length' "$result" 2>/dev/null || echo "?")
            log "  $name: $pass/$total passed"
        fi
    done
}

# Main
main() {
    check_prerequisites

    case "${1:-}" in
        --benchmark|-b)
            run_benchmarks
            ;;
        --all|-a)
            run_all
            ;;
        --help|-h)
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  (none)        Run all autopilot evals"
            echo "  init          Run autopilot:init evals"
            echo "  full          Run autopilot:full evals"
            echo "  specify       Run autopilot:specify evals"
            echo "  plan          Run autopilot:plan evals"
            echo "  tasks         Run autopilot:tasks evals"
            echo "  analyze       Run autopilot:analyze evals"
            echo ""
            echo "Options:"
            echo "  --benchmark   Run benchmarks instead of evals"
            echo "  --all         Run evals for each command separately"
            echo "  --help        Show this help"
            ;;
        "")
            run_evals "autopilot"
            ;;
        *)
            run_evals "autopilot:$1"
            ;;
    esac
}

main "$@"
