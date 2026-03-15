#!/bin/bash
# Run FeatureBench evaluation with autopilot
# Usage:
#   ./scripts/featurebench.sh setup         # Install FeatureBench + register agent
#   ./scripts/featurebench.sh lite          # Run lite split (30 tasks)
#   ./scripts/featurebench.sh full          # Run full split (200 tasks)
#   ./scripts/featurebench.sh baseline      # Run baseline Claude Code for comparison
#   ./scripts/featurebench.sh eval <path>   # Evaluate results

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
FB_DIR="${FEATUREBENCH_DIR:-$HOME/FeatureBench}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "$1"; }
log_header() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

setup() {
    log_header "Setting up FeatureBench with Autopilot"

    # Check if FeatureBench is installed
    if ! command -v fb &> /dev/null; then
        log "Installing FeatureBench..."
        pip install featurebench
    fi

    # Clone FeatureBench repo if needed
    if [[ ! -d "$FB_DIR" ]]; then
        log "Cloning FeatureBench repo..."
        git clone https://github.com/LiberCoders/FeatureBench.git "$FB_DIR"
    fi

    # Copy autopilot agent
    log "Installing autopilot agent..."
    cp "$PLUGIN_DIR/featurebench/autopilot_agent.py" \
       "$FB_DIR/featurebench/infer/agents/autopilot.py"

    # Register agent in __init__.py
    INIT_FILE="$FB_DIR/featurebench/infer/agents/__init__.py"
    if ! grep -q "AutopilotAgent" "$INIT_FILE" 2>/dev/null; then
        echo 'from .autopilot import AutopilotAgent' >> "$INIT_FILE"
        log "Registered AutopilotAgent in __init__.py"
    fi

    # Copy config if not exists
    if [[ ! -f "$FB_DIR/config.toml" ]]; then
        cp "$PLUGIN_DIR/featurebench/config_autopilot.toml" "$FB_DIR/config.toml"
        log "${YELLOW}Created config.toml - please add your ANTHROPIC_API_KEY${NC}"
    fi

    log "${GREEN}Setup complete!${NC}"
    log ""
    log "Next steps:"
    log "  1. Edit $FB_DIR/config.toml with your API key"
    log "  2. Run: ./scripts/featurebench.sh lite"
}

run_infer() {
    local agent="$1"
    local split="$2"
    local model="${3:-claude-opus-4-5}"

    log_header "Running FeatureBench: agent=$agent, split=$split, model=$model"

    cd "$FB_DIR"
    fb infer --agent "$agent" --model "$model" --split "$split"
}

run_eval() {
    local output_path="$1"

    if [[ -z "$output_path" ]]; then
        # Find latest run
        output_path=$(ls -td "$FB_DIR/runs/"*/ 2>/dev/null | head -1)
        if [[ -z "$output_path" ]]; then
            log "${RED}No runs found. Run inference first.${NC}"
            exit 1
        fi
        output_path="$output_path/output.jsonl"
    fi

    log_header "Evaluating: $output_path"
    cd "$FB_DIR"
    fb eval -p "$output_path"
}

compare() {
    log_header "Comparison: Autopilot vs Claude Code"

    # Find latest runs for each
    local autopilot_run=$(ls -td "$FB_DIR/runs/"*autopilot*/ 2>/dev/null | head -1)
    local baseline_run=$(ls -td "$FB_DIR/runs/"*claude_code*/ 2>/dev/null | head -1)

    if [[ -n "$autopilot_run" ]]; then
        log "Autopilot results:"
        fb eval -p "$autopilot_run/output.jsonl" 2>/dev/null | grep -E "Resolved|Passed" || true
    fi

    if [[ -n "$baseline_run" ]]; then
        log "\nBaseline results:"
        fb eval -p "$baseline_run/output.jsonl" 2>/dev/null | grep -E "Resolved|Passed" || true
    fi
}

main() {
    case "${1:-}" in
        setup)
            setup
            ;;
        lite)
            run_infer "autopilot" "lite" "${2:-claude-opus-4-5}"
            ;;
        full)
            run_infer "autopilot" "full" "${2:-claude-opus-4-5}"
            ;;
        baseline)
            run_infer "claude_code" "${2:-lite}" "${3:-claude-opus-4-5}"
            ;;
        eval)
            run_eval "$2"
            ;;
        compare)
            compare
            ;;
        --help|-h)
            echo "Usage: $0 <command> [options]"
            echo ""
            echo "Commands:"
            echo "  setup              Install FeatureBench + register autopilot agent"
            echo "  lite [model]       Run autopilot on lite split (30 tasks, ~\$45-90)"
            echo "  full [model]       Run autopilot on full split (200 tasks, ~\$300-600)"
            echo "  baseline [split]   Run baseline Claude Code for comparison"
            echo "  eval [path]        Evaluate results (defaults to latest run)"
            echo "  compare            Compare autopilot vs baseline results"
            echo ""
            echo "Environment:"
            echo "  FEATUREBENCH_DIR   FeatureBench repo location (default: ~/FeatureBench)"
            ;;
        *)
            log "${RED}Unknown command: $1${NC}"
            log "Run: $0 --help"
            exit 1
            ;;
    esac
}

main "$@"
