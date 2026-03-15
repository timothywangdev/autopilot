#!/bin/bash
# Run autopilot evals from within Claude Code session
# Usage:
#   ./scripts/eval.sh              # Run all evals
#   ./scripts/eval.sh init         # Run specific command
#   ./scripts/eval.sh --viewer     # Start eval viewer on localhost:3117

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PLUGIN_DIR/test/results"
WORKSPACE="/tmp/autopilot-test"
VIEWER_SCRIPT="$HOME/.claude/plugins/cache/claude-plugins-official/skill-creator/d5c15b861cd2/skills/skill-creator/eval-viewer/generate_review.py"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

case "${1:-}" in
    --viewer|-v)
        if [[ -d "$WORKSPACE/autopilot-workspace" ]]; then
            echo -e "${BLUE}Starting eval viewer on http://localhost:3117${NC}"
            python3 "$VIEWER_SCRIPT" "$WORKSPACE/autopilot-workspace" --port 3117
        else
            echo "No eval results found. Run evals first: ./scripts/eval.sh"
            exit 1
        fi
        ;;
    --help|-h)
        echo "Usage: $0 [command] [options]"
        echo ""
        echo "Commands:"
        echo "  (none)      Run all autopilot evals"
        echo "  init        Run autopilot:init evals"
        echo "  full        Run autopilot:full evals"
        echo "  specify     Run autopilot:specify evals"
        echo "  plan        Run autopilot:plan evals"
        echo "  tasks       Run autopilot:tasks evals"
        echo ""
        echo "Options:"
        echo "  --viewer    Start eval viewer (after running evals)"
        echo "  --help      Show this help"
        ;;
    *)
        TARGET="${1:-autopilot}"
        [[ "$TARGET" != autopilot* ]] && TARGET="autopilot:$TARGET"

        # Setup workspace
        rm -rf "$WORKSPACE"
        mkdir -p "$WORKSPACE"
        cd "$WORKSPACE"
        git init -q

        echo -e "${BLUE}Running evals: $TARGET${NC}"
        echo "Workspace: $WORKSPACE"
        echo ""

        # Bypass nested session check
        CLAUDECODE= claude -p "/skill-creator eval $TARGET" --dangerously-skip-permissions

        # Save results to repo
        TIMESTAMP=$(date +%Y%m%d-%H%M%S)
        mkdir -p "$RESULTS_DIR"
        if [[ -f "$WORKSPACE/autopilot-workspace/iteration-1/benchmark.json" ]]; then
            cp "$WORKSPACE/autopilot-workspace/iteration-1/benchmark.json" "$RESULTS_DIR/benchmark-$TIMESTAMP.json"
            cp "$WORKSPACE/autopilot-workspace/iteration-1/benchmark.json" "$RESULTS_DIR/benchmark-latest.json"
            echo -e "${GREEN}Results saved to: test/results/benchmark-$TIMESTAMP.json${NC}"
        fi

        echo ""
        echo -e "${GREEN}Evals complete.${NC}"
        echo "View results: ./scripts/eval.sh --viewer"
        ;;
esac
