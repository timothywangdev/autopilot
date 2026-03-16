#!/usr/bin/env bash
# initialize-feature.test.sh - Comprehensive tests for initialize-feature.sh
# Run with: bash test/initialize-feature.test.sh

set -euo pipefail

# ==============================================================================
# Test Framework
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/../scripts/bash"
INIT_FEATURE="$SCRIPTS_DIR/initialize-feature.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Temp directory for test fixtures
TEST_TMP=""

setup() {
    TEST_TMP=$(mktemp -d)

    # Create a mock git repository
    cd "$TEST_TMP"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"

    # Create initial commit so git commands work
    touch .gitkeep
    git add .gitkeep
    git commit -q -m "Initial commit"

    # Create specs directory
    mkdir -p "$TEST_TMP/specs"

    # Optionally create .autopilot directory (alternative repo root marker)
    mkdir -p "$TEST_TMP/.autopilot/memory"
}

teardown() {
    if [ -n "$TEST_TMP" ] && [ -d "$TEST_TMP" ]; then
        rm -rf "$TEST_TMP"
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    if [ "$expected" = "$actual" ]; then
        return 0
    else
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if echo "$haystack" | grep -qF "$needle"; then
        return 0
    else
        echo "  String does not contain: $needle"
        echo "  In: $haystack"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"

    if [ -f "$file" ]; then
        return 0
    else
        echo "  File does not exist: $file"
        return 1
    fi
}

assert_dir_exists() {
    local dir="$1"

    if [ -d "$dir" ]; then
        return 0
    else
        echo "  Directory does not exist: $dir"
        return 1
    fi
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"

    if grep -qF "$pattern" "$file" 2>/dev/null; then
        return 0
    else
        echo "  File $file does not contain: $pattern"
        return 1
    fi
}

assert_json_field() {
    local json="$1"
    local field="$2"
    local expected="$3"

    local actual
    actual=$(echo "$json" | jq -r ".$field" 2>/dev/null || echo "PARSE_ERROR")

    if [ "$actual" = "$expected" ]; then
        return 0
    else
        echo "  JSON field .$field"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        return 1
    fi
}

run_test() {
    local name="$1"
    local func="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  Testing: $name ... "

    # Reset test environment for each test
    teardown
    setup

    if $func; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ==============================================================================
# Helper Functions
# ==============================================================================

create_existing_feature() {
    local num="$1"
    local name="$2"
    local padded
    padded=$(printf "%03d" "$num")
    mkdir -p "$TEST_TMP/specs/${padded}-${name}"
}

# ==============================================================================
# Test Cases: Directory Creation
# ==============================================================================

test_creates_feature_directory() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" 2>/dev/null)

    assert_dir_exists "$TEST_TMP/specs/001-test-feature"
}

test_creates_contracts_subdirectory() {
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" >/dev/null 2>&1

    assert_dir_exists "$TEST_TMP/specs/001-test-feature/contracts"
}

test_creates_checklists_subdirectory() {
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" >/dev/null 2>&1

    assert_dir_exists "$TEST_TMP/specs/001-test-feature/checklists"
}

test_creates_spikes_subdirectory() {
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" >/dev/null 2>&1

    assert_dir_exists "$TEST_TMP/specs/001-test-feature/spikes"
}

# ==============================================================================
# Test Cases: Feature Numbering
# ==============================================================================

test_auto_increments_from_zero() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "First Feature" 2>/dev/null)

    assert_json_field "$output" "featureNumber" "001"
}

test_auto_increments_from_existing() {
    create_existing_feature 5 "existing-feature"

    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "New Feature" 2>/dev/null)

    assert_json_field "$output" "featureNumber" "006"
}

test_uses_explicit_number() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Specific Feature" --number 42 2>/dev/null)

    assert_json_field "$output" "featureNumber" "042"
}

test_pads_to_three_digits() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Padded Feature" --number 7 2>/dev/null)

    assert_json_field "$output" "featureNumber" "007"
}

test_handles_three_digit_numbers() {
    create_existing_feature 99 "ninety-nine"

    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Hundredth Feature" 2>/dev/null)

    assert_json_field "$output" "featureNumber" "100"
}

test_handles_four_digit_numbers() {
    # Create feature 999 to force 4-digit increment
    mkdir -p "$TEST_TMP/specs/999-almost-limit"

    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Thousand Feature" 2>/dev/null)

    # Four digit numbers are formatted with %03d which produces "1000"
    # (printf %03d 1000 = "1000" since it's already > 3 digits)
    assert_json_field "$output" "featureNumber" "1000"
}

test_explicit_four_digit_number() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Big Feature" --number 1234 2>/dev/null)

    assert_json_field "$output" "featureNumber" "1234"
}

test_handles_max_number_9999() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Max Feature" --number 9999 2>/dev/null)

    assert_json_field "$output" "featureNumber" "9999"
}

# ==============================================================================
# Test Cases: Template Files
# ==============================================================================

test_creates_spec_md() {
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" >/dev/null 2>&1

    assert_file_exists "$TEST_TMP/specs/001-test-feature/spec.md"
}

test_spec_md_has_sections() {
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" >/dev/null 2>&1

    local spec="$TEST_TMP/specs/001-test-feature/spec.md"
    assert_file_contains "$spec" "# Feature Specification" && \
    assert_file_contains "$spec" "## Goals" && \
    assert_file_contains "$spec" "## Requirements" && \
    assert_file_contains "$spec" "## User Stories"
}

test_creates_plan_md() {
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" >/dev/null 2>&1

    assert_file_exists "$TEST_TMP/specs/001-test-feature/plan.md"
}

test_plan_md_has_sections() {
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" >/dev/null 2>&1

    local plan="$TEST_TMP/specs/001-test-feature/plan.md"
    assert_file_contains "$plan" "# Implementation Plan" && \
    assert_file_contains "$plan" "## Architecture" && \
    assert_file_contains "$plan" "## Data Model"
}

test_creates_tasks_md() {
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" >/dev/null 2>&1

    assert_file_exists "$TEST_TMP/specs/001-test-feature/tasks.md"
}

test_tasks_md_has_template_tasks() {
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" >/dev/null 2>&1

    local tasks="$TEST_TMP/specs/001-test-feature/tasks.md"
    assert_file_contains "$tasks" "# Implementation Tasks" && \
    assert_file_contains "$tasks" "T001:" && \
    assert_file_contains "$tasks" "**Verify**:"
}

test_creates_research_md() {
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" >/dev/null 2>&1

    assert_file_exists "$TEST_TMP/specs/001-test-feature/research.md"
}

test_creates_data_model_md() {
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" >/dev/null 2>&1

    assert_file_exists "$TEST_TMP/specs/001-test-feature/data-model.md"
}

test_creates_api_contract() {
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" >/dev/null 2>&1

    assert_file_exists "$TEST_TMP/specs/001-test-feature/contracts/api.yaml"
}

test_creates_requirements_checklist() {
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" >/dev/null 2>&1

    assert_file_exists "$TEST_TMP/specs/001-test-feature/checklists/requirements.md"
}

test_creates_workflow_state() {
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" >/dev/null 2>&1

    assert_file_exists "$TEST_TMP/specs/001-test-feature/.workflow-state.json"
}

test_workflow_state_has_correct_structure() {
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" >/dev/null 2>&1

    local state
    state=$(cat "$TEST_TMP/specs/001-test-feature/.workflow-state.json")

    assert_json_field "$state" "version" "1" && \
    assert_json_field "$state" "status" "initialized" && \
    assert_json_field "$state" "currentPhase" "0"
}

# ==============================================================================
# Test Cases: JSON Output
# ==============================================================================

test_returns_valid_json() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" 2>/dev/null)

    echo "$output" | jq . >/dev/null 2>&1
}

test_json_has_status_success() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" 2>/dev/null)

    assert_json_field "$output" "status" "success"
}

test_json_has_feature_id() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "My Cool Feature" 2>/dev/null)

    assert_json_field "$output" "featureId" "001-cool-feature"
}

test_json_has_branch_name() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Branch Test" 2>/dev/null)

    local branch
    branch=$(echo "$output" | jq -r '.branchName' 2>/dev/null)

    assert_contains "$branch" "001-"
}

test_json_has_artifact_paths() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" 2>/dev/null)

    local spec_path
    spec_path=$(echo "$output" | jq -r '.artifacts.spec' 2>/dev/null)

    assert_contains "$spec_path" "spec.md"
}

test_json_has_absolute_path() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" 2>/dev/null)

    local abs_path
    abs_path=$(echo "$output" | jq -r '.absolutePath' 2>/dev/null)

    # Should start with /
    [[ "$abs_path" == /* ]]
}

# ==============================================================================
# Test Cases: Branch Name Generation
# ==============================================================================

test_branch_name_lowercase() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "UPPERCASE Feature" 2>/dev/null)

    local branch
    branch=$(echo "$output" | jq -r '.branchName' 2>/dev/null)

    # Should not contain uppercase
    [[ "$branch" =~ ^[0-9a-z-]+$ ]]
}

test_branch_name_removes_stop_words() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Add the new and improved feature" 2>/dev/null)

    local branch
    branch=$(echo "$output" | jq -r '.branchName' 2>/dev/null)

    # "the", "and" should be removed
    [[ "$branch" != *"-the-"* ]] && [[ "$branch" != *"-and-"* ]]
}

test_branch_name_limits_words() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "This is a very long description with many words to test limiting" 2>/dev/null)

    local branch
    branch=$(echo "$output" | jq -r '.branchName' 2>/dev/null)

    # Count hyphens (words - 1 + prefix hyphen)
    local hyphen_count
    hyphen_count=$(echo "$branch" | tr -cd '-' | wc -c)

    # Should have at most 5 hyphens (prefix + max 4 words)
    [ "$hyphen_count" -le 5 ]
}

test_branch_name_handles_special_chars() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Feature with 'quotes' & symbols!" 2>/dev/null)

    local branch
    branch=$(echo "$output" | jq -r '.branchName' 2>/dev/null)

    # Should only contain alphanumeric and hyphens
    [[ "$branch" =~ ^[0-9a-z-]+$ ]]
}

# ==============================================================================
# Test Cases: Error Handling
# ==============================================================================

test_fails_without_description() {
    local exit_code=0
    cd "$TEST_TMP" && bash "$INIT_FEATURE" 2>/dev/null || exit_code=$?

    [ "$exit_code" -ne 0 ]
}

test_fails_with_existing_directory() {
    # First creation
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Duplicate Feature" >/dev/null 2>&1

    # Second creation with same name and number should fail
    local exit_code=0
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Duplicate Feature" --number 1 2>/dev/null || exit_code=$?

    [ "$exit_code" -ne 0 ]
}

test_fails_with_unknown_argument() {
    local exit_code=0
    cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test" --bogus 2>/dev/null || exit_code=$?

    [ "$exit_code" -ne 0 ]
}

test_help_exits_zero() {
    local exit_code=0
    bash "$INIT_FEATURE" --help >/dev/null 2>&1 || exit_code=$?

    [ "$exit_code" -eq 0 ]
}

# ==============================================================================
# Test Cases: Constitution Detection
# ==============================================================================

test_detects_constitution_when_present() {
    # Create constitution
    cat > "$TEST_TMP/.autopilot/memory/constitution.md" << 'EOF'
# Project Constitution
Rules here
EOF

    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" 2>/dev/null)

    assert_json_field "$output" "constitution.exists" "true"
}

test_detects_constitution_missing() {
    # Remove .autopilot directory (don't create constitution)
    rm -rf "$TEST_TMP/.autopilot"

    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Test Feature" 2>/dev/null)

    assert_json_field "$output" "constitution.exists" "false"
}

# ==============================================================================
# Test Cases: Integration with Git
# ==============================================================================

test_works_in_git_repo() {
    # Already in git repo from setup
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Git Feature" 2>/dev/null)

    assert_json_field "$output" "status" "success"
}

test_considers_git_branches_for_numbering() {
    # Create a branch with higher number
    cd "$TEST_TMP"
    git checkout -q -b 010-other-feature
    git checkout -q -

    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "After Branch" 2>/dev/null)

    assert_json_field "$output" "featureNumber" "011"
}

# ==============================================================================
# Test Cases: Edge Cases
# ==============================================================================

test_empty_description_words() {
    # Description with only stop words/short words
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "a the an" 2>/dev/null)

    local branch
    branch=$(echo "$output" | jq -r '.branchName' 2>/dev/null)

    # Should fallback to "feature"
    assert_contains "$branch" "feature"
}

test_numeric_description() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "123 456 feature" 2>/dev/null)

    # Should handle numeric words
    local branch
    branch=$(echo "$output" | jq -r '.branchName' 2>/dev/null)

    assert_contains "$branch" "001-"
}

test_very_long_description() {
    local long_desc="This is an extremely long description that goes on and on and on with many many words to test how the system handles very lengthy input strings"

    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "$long_desc" 2>/dev/null)

    local branch
    branch=$(echo "$output" | jq -r '.branchName' 2>/dev/null)

    # Branch name should be reasonable length (number + max 4 words)
    [ "${#branch}" -lt 60 ]
}

test_unicode_description() {
    local output
    output=$(cd "$TEST_TMP" && bash "$INIT_FEATURE" --description "Feature with unicode cafe" 2>/dev/null)

    # Should handle gracefully (unicode stripped by tr)
    local exit_code
    exit_code=$?

    [ "$exit_code" -eq 0 ]
}

# ==============================================================================
# Main Test Runner
# ==============================================================================

main() {
    echo ""
    echo "=========================================="
    echo "  initialize-feature.sh Test Suite"
    echo "=========================================="
    echo ""

    # Check dependencies
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${RED}ERROR: jq is required for tests${NC}"
        exit 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        echo -e "${RED}ERROR: git is required for tests${NC}"
        exit 1
    fi

    echo "Directory Creation:"
    run_test "creates feature directory" test_creates_feature_directory
    run_test "creates contracts subdirectory" test_creates_contracts_subdirectory
    run_test "creates checklists subdirectory" test_creates_checklists_subdirectory
    run_test "creates spikes subdirectory" test_creates_spikes_subdirectory
    echo ""

    echo "Feature Numbering:"
    run_test "auto-increments from zero" test_auto_increments_from_zero
    run_test "auto-increments from existing" test_auto_increments_from_existing
    run_test "uses explicit number" test_uses_explicit_number
    run_test "pads to three digits" test_pads_to_three_digits
    run_test "handles three-digit numbers" test_handles_three_digit_numbers
    run_test "handles four-digit numbers" test_handles_four_digit_numbers
    run_test "explicit four-digit number" test_explicit_four_digit_number
    run_test "handles max number 9999" test_handles_max_number_9999
    echo ""

    echo "Template Files:"
    run_test "creates spec.md" test_creates_spec_md
    run_test "spec.md has sections" test_spec_md_has_sections
    run_test "creates plan.md" test_creates_plan_md
    run_test "plan.md has sections" test_plan_md_has_sections
    run_test "creates tasks.md" test_creates_tasks_md
    run_test "tasks.md has template tasks" test_tasks_md_has_template_tasks
    run_test "creates research.md" test_creates_research_md
    run_test "creates data-model.md" test_creates_data_model_md
    run_test "creates API contract" test_creates_api_contract
    run_test "creates requirements checklist" test_creates_requirements_checklist
    run_test "creates workflow state" test_creates_workflow_state
    run_test "workflow state has correct structure" test_workflow_state_has_correct_structure
    echo ""

    echo "JSON Output:"
    run_test "returns valid JSON" test_returns_valid_json
    run_test "JSON has status success" test_json_has_status_success
    run_test "JSON has feature ID" test_json_has_feature_id
    run_test "JSON has branch name" test_json_has_branch_name
    run_test "JSON has artifact paths" test_json_has_artifact_paths
    run_test "JSON has absolute path" test_json_has_absolute_path
    echo ""

    echo "Branch Name Generation:"
    run_test "branch name lowercase" test_branch_name_lowercase
    run_test "branch name removes stop words" test_branch_name_removes_stop_words
    run_test "branch name limits words" test_branch_name_limits_words
    run_test "branch name handles special chars" test_branch_name_handles_special_chars
    echo ""

    echo "Error Handling:"
    run_test "fails without description" test_fails_without_description
    run_test "fails with existing directory" test_fails_with_existing_directory
    run_test "fails with unknown argument" test_fails_with_unknown_argument
    run_test "help exits zero" test_help_exits_zero
    echo ""

    echo "Constitution Detection:"
    run_test "detects constitution when present" test_detects_constitution_when_present
    run_test "detects constitution missing" test_detects_constitution_missing
    echo ""

    echo "Git Integration:"
    run_test "works in git repo" test_works_in_git_repo
    run_test "considers git branches for numbering" test_considers_git_branches_for_numbering
    echo ""

    echo "Edge Cases:"
    run_test "empty description words" test_empty_description_words
    run_test "numeric description" test_numeric_description
    run_test "very long description" test_very_long_description
    run_test "unicode description" test_unicode_description
    echo ""

    echo "=========================================="
    echo "  Results: $TESTS_PASSED/$TESTS_RUN passed"
    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo -e "  ${RED}$TESTS_FAILED tests failed${NC}"
        echo "=========================================="
        exit 1
    else
        echo -e "  ${GREEN}All tests passed!${NC}"
        echo "=========================================="
        exit 0
    fi
}

main "$@"
