#!/bin/bash
# Autopilot Plugin Evaluation Runner
# Run this script OUTSIDE of Claude Code sessions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR="/tmp/autopilot-eval-$$"
RESULTS_DIR="$PLUGIN_DIR/test/results"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0
SKIP=0

log() {
    echo -e "$1"
}

log_pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    ((PASS++))
}

log_fail() {
    echo -e "${RED}FAIL${NC}: $1"
    ((FAIL++))
}

log_skip() {
    echo -e "${YELLOW}SKIP${NC}: $1"
    ((SKIP++))
}

setup_test_dir() {
    log "Setting up test directory: $TEST_DIR"
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    git init -q
    echo '{"name": "test-project", "version": "1.0.0"}' > package.json
    echo '{"compilerOptions": {"strict": true}}' > tsconfig.json
}

cleanup_test_dir() {
    if [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

run_claude_eval() {
    local name="$1"
    local prompt="$2"
    local setup="$3"
    local timeout="${4:-120}"

    log "\n--- Running: $name ---"

    # Setup if provided
    if [[ -n "$setup" ]]; then
        eval "$setup" 2>/dev/null || true
    fi

    # Run claude with the prompt
    local output
    local exit_code

    output=$(timeout "${timeout}s" claude -p "$prompt" --output-format text 2>&1) || exit_code=$?

    echo "$output" > "$RESULTS_DIR/${name// /_}.txt"

    # Return output for verification
    echo "$output"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    if ! command -v claude &> /dev/null; then
        log "${RED}Error: claude command not found. Install Claude Code first.${NC}"
        exit 1
    fi

    if [[ -n "$CLAUDECODE" ]]; then
        log "${RED}Error: Cannot run inside Claude Code session.${NC}"
        log "Please run this script in a regular terminal."
        exit 1
    fi

    # Check if autopilot plugin is installed
    if ! claude plugin list 2>/dev/null | grep -q "autopilot"; then
        log "${YELLOW}Warning: autopilot plugin not found. Installing...${NC}"
        claude plugin install autopilot || true
    fi

    # Check if skill-creator is installed
    if ! claude plugin list 2>/dev/null | grep -q "skill-creator"; then
        log "${YELLOW}Warning: skill-creator plugin not found. Installing...${NC}"
        claude plugin install skill-creator || true
    fi

    mkdir -p "$RESULTS_DIR"
    log "${GREEN}Prerequisites OK${NC}"
}

# ============================================================================
# EVAL TESTS
# ============================================================================

test_init_creates_structure() {
    local output
    output=$(run_claude_eval "init_creates_structure" "/autopilot:init")

    if [[ -d ".specify" && -d ".specify/templates" && -d "specs" ]]; then
        log_pass "init creates directory structure"
    else
        log_fail "init creates directory structure"
        log "  Missing directories. Found:"
        ls -la
    fi
}

test_init_idempotent() {
    mkdir -p .specify/templates
    echo "existing content" > .specify/templates/spec-template.md
    local original_content
    original_content=$(cat .specify/templates/spec-template.md)

    local output
    output=$(run_claude_eval "init_idempotent" "/autopilot:init" "" 60)

    if echo "$output" | grep -qi "exist\|skip\|already"; then
        log_pass "init detects existing setup"
    else
        log_fail "init detects existing setup"
    fi
}

test_full_missing_file() {
    local output
    output=$(run_claude_eval "full_missing_file" "/autopilot:full nonexistent-file.md" "" 30)

    if echo "$output" | grep -qi "not found\|error\|does not exist"; then
        log_pass "full handles missing file gracefully"
    else
        log_fail "full handles missing file gracefully"
        log "  Output: ${output:0:200}"
    fi
}

test_full_no_args() {
    local output
    output=$(run_claude_eval "full_no_args" "/autopilot:full" "" 30)

    if echo "$output" | grep -qi "usage\|plan-file\|--resume"; then
        log_pass "full shows usage without args"
    else
        log_fail "full shows usage without args"
        log "  Output: ${output:0:200}"
    fi
}

test_specify_creates_spec() {
    local output
    output=$(run_claude_eval "specify_creates_spec" "/autopilot:specify Add a hello world endpoint" "" 120)

    if [[ -f "spec.md" ]] || echo "$output" | grep -qi "spec.md\|specification"; then
        log_pass "specify creates spec.md"
    else
        log_fail "specify creates spec.md"
    fi
}

test_plan_requires_spec() {
    local output
    output=$(run_claude_eval "plan_requires_spec" "/autopilot:plan" "" 30)

    if echo "$output" | grep -qi "spec.md\|not found\|specify first"; then
        log_pass "plan requires spec.md"
    else
        log_fail "plan requires spec.md"
    fi
}

test_tasks_requires_plan() {
    local output
    output=$(run_claude_eval "tasks_requires_plan" "/autopilot:tasks" "" 30)

    if echo "$output" | grep -qi "plan.md\|not found\|plan first"; then
        log_pass "tasks requires plan.md"
    else
        log_fail "tasks requires plan.md"
    fi
}

test_analyze_requires_artifacts() {
    local output
    output=$(run_claude_eval "analyze_requires_artifacts" "/autopilot:analyze" "" 30)

    if echo "$output" | grep -qi "not found\|missing\|required"; then
        log_pass "analyze requires artifacts"
    else
        log_fail "analyze requires artifacts"
    fi
}

test_full_with_simple_plan() {
    # Copy fixture
    cp "$PLUGIN_DIR/test/fixtures/simple-plan.md" ./simple-plan.md

    local output
    output=$(run_claude_eval "full_simple_plan" "/autopilot:full simple-plan.md" "" 300)

    # Check for workflow state
    if find . -name ".workflow-state.json" -type f | grep -q .; then
        log_pass "full creates workflow state"
    else
        log_fail "full creates workflow state"
    fi

    # Check for spec artifacts
    if find . -name "spec.md" -type f | grep -q .; then
        log_pass "full creates spec.md"
    else
        log_fail "full creates spec.md"
    fi
}

test_resume_requires_state() {
    local output
    output=$(run_claude_eval "resume_requires_state" "/autopilot:full --resume" "" 30)

    if echo "$output" | grep -qi "no.*state\|not found\|workflow"; then
        log_pass "resume requires existing state"
    else
        log_fail "resume requires existing state"
    fi
}

# ============================================================================
# SKILL-CREATOR EVALS (if available)
# ============================================================================

test_with_skill_creator() {
    log "\n=== Running skill-creator evals ==="

    local output
    output=$(timeout 600s claude -p "/skill-creator eval autopilot" --output-format text 2>&1) || true

    echo "$output" > "$RESULTS_DIR/skill-creator-eval.txt"

    if echo "$output" | grep -qi "pass"; then
        log_pass "skill-creator eval completed"
        log "  Results saved to: $RESULTS_DIR/skill-creator-eval.txt"
    else
        log_skip "skill-creator eval (may not be available)"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    log "============================================"
    log "  Autopilot Plugin Evaluation Suite"
    log "============================================"

    check_prerequisites

    # Trap cleanup
    trap cleanup_test_dir EXIT

    setup_test_dir

    log "\n=== Running Basic Tests ==="

    # Error handling tests (fast)
    test_full_missing_file
    test_full_no_args
    test_plan_requires_spec
    test_tasks_requires_plan
    test_analyze_requires_artifacts
    test_resume_requires_state

    # Reset test dir
    cleanup_test_dir
    setup_test_dir

    log "\n=== Running Init Tests ==="
    test_init_creates_structure

    # Reset test dir
    cleanup_test_dir
    setup_test_dir

    test_init_idempotent

    # Reset test dir
    cleanup_test_dir
    setup_test_dir

    log "\n=== Running Specify Tests ==="
    test_specify_creates_spec

    # Reset test dir for full test
    cleanup_test_dir
    setup_test_dir

    log "\n=== Running Full Workflow Test (may take several minutes) ==="
    test_full_with_simple_plan

    # Optionally run skill-creator evals
    if [[ "${RUN_SKILL_CREATOR:-0}" == "1" ]]; then
        cleanup_test_dir
        setup_test_dir
        test_with_skill_creator
    fi

    # Summary
    log "\n============================================"
    log "  RESULTS"
    log "============================================"
    log "${GREEN}PASS${NC}: $PASS"
    log "${RED}FAIL${NC}: $FAIL"
    log "${YELLOW}SKIP${NC}: $SKIP"
    log ""
    log "Results saved to: $RESULTS_DIR/"

    if [[ $FAIL -gt 0 ]]; then
        exit 1
    fi
}

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --with-skill-creator)
            export RUN_SKILL_CREATOR=1
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --with-skill-creator  Also run skill-creator evals (slower)"
            echo "  --help                Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

main
