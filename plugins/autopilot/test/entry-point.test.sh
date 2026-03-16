#!/usr/bin/env bash
# Tests for entry-point.sh
#
# Run: ./entry-point.test.sh
# Or:  bash entry-point.test.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRY_SCRIPT="$SCRIPT_DIR/../scripts/bash/entry-point.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Temp directory for test isolation
TEST_TMP=""

# ============================================================================
# Test Helpers
# ============================================================================

setup() {
    TEST_TMP=$(mktemp -d)
    cd "$TEST_TMP"
    mkdir -p specs
}

teardown() {
    cd "$SCRIPT_DIR"
    if [ -n "$TEST_TMP" ] && [ -d "$TEST_TMP" ]; then
        rm -rf "$TEST_TMP"
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [ "$expected" = "$actual" ]; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED${NC}: $message"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    if echo "$haystack" | grep -q "$needle"; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED${NC}: $message"
        echo "  Expected to contain: $needle"
        echo "  Actual: $haystack"
        return 1
    fi
}

assert_json_field() {
    local json="$1"
    local field="$2"
    local expected="$3"
    local message="$4"

    # Extract field value from JSON (handles both string and non-string values)
    local actual
    if echo "$json" | grep -q "\"$field\": \""; then
        # String value
        actual=$(echo "$json" | grep -o "\"$field\": \"[^\"]*\"" | cut -d'"' -f4)
    else
        # Non-string value (boolean, number)
        actual=$(echo "$json" | grep -o "\"$field\": [^,}]*" | sed "s/\"$field\": //" | tr -d ' ')
    fi

    assert_equals "$expected" "$actual" "$message"
}

run_test() {
    local test_name="$1"
    local test_func="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  $test_name... "

    setup

    if $test_func; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    teardown
}

create_state_file() {
    local feature_dir="$1"
    local status="$2"
    local phase="${3:-0}"

    mkdir -p "$feature_dir"
    cat > "$feature_dir/.workflow-state.json" <<EOF
{
  "status": "$status",
  "currentPhase": $phase,
  "feature": "test-feature"
}
EOF
}

# ============================================================================
# Tests: Action determination based on state
# ============================================================================

test_initialize_with_plan_file() {
    local output
    output=$("$ENTRY_SCRIPT" "specs/feature/plan.md")

    assert_json_field "$output" "action" "initialize" "should set action to initialize"
    assert_json_field "$output" "plan_file" "specs/feature/plan.md" "should set plan_file"
}

test_error_when_no_plan_and_no_state() {
    local output
    output=$("$ENTRY_SCRIPT" "")

    assert_json_field "$output" "action" "error" "should set action to error"
    assert_contains "$output" "No plan file provided" "should have error message"
}

test_resume_from_existing_state() {
    create_state_file "specs/my-feature" "in_progress" 2

    local output
    output=$("$ENTRY_SCRIPT" "--resume")

    assert_json_field "$output" "action" "resume" "should set action to resume"
    assert_json_field "$output" "current_phase" "2" "should read current phase"
    assert_json_field "$output" "resume_mode" "true" "should set resume_mode"
}

test_resume_finds_most_recent_state() {
    # Create two state files with different timestamps
    create_state_file "specs/feature-old" "in_progress" 1
    sleep 0.1
    create_state_file "specs/feature-new" "in_progress" 3

    local output
    output=$("$ENTRY_SCRIPT" "--resume")

    assert_json_field "$output" "action" "resume" "should set action to resume"
    assert_json_field "$output" "current_phase" "3" "should find newer state file"
    assert_contains "$output" "specs/feature-new" "should use newer feature dir"
}

test_complete_status_returns_complete_action() {
    create_state_file "specs/completed-feature" "completed" 5

    local output
    output=$("$ENTRY_SCRIPT" "--resume")

    assert_json_field "$output" "action" "complete" "should set action to complete"
    assert_json_field "$output" "status" "completed" "should have completed status"
}

test_halted_status_returns_halted_action() {
    create_state_file "specs/halted-feature" "halted" 2

    local output
    output=$("$ENTRY_SCRIPT" "--resume")

    assert_json_field "$output" "action" "halted" "should set action to halted"
    assert_json_field "$output" "status" "halted" "should have halted status"
}

test_in_progress_status_returns_resume_action() {
    create_state_file "specs/wip-feature" "in_progress" 1

    local output
    output=$("$ENTRY_SCRIPT" "--resume")

    assert_json_field "$output" "action" "resume" "should set action to resume"
    assert_json_field "$output" "status" "in_progress" "should have in_progress status"
}

# ============================================================================
# Tests: State file detection
# ============================================================================

test_state_file_path_in_output() {
    create_state_file "specs/test-feature" "in_progress" 0

    local output
    output=$("$ENTRY_SCRIPT" "--resume")

    assert_contains "$output" "specs/test-feature/.workflow-state.json" "should output state file path"
}

test_feature_dir_extracted_from_state() {
    create_state_file "specs/my-awesome-feature" "in_progress" 1

    local output
    output=$("$ENTRY_SCRIPT" "--resume")

    assert_json_field "$output" "feature_dir" "specs/my-awesome-feature" "should extract feature dir"
}

test_no_state_file_when_initializing() {
    local output
    output=$("$ENTRY_SCRIPT" "plan.md")

    assert_json_field "$output" "state_file" "" "state_file should be empty for new workflow"
}

# ============================================================================
# Tests: JSON output structure
# ============================================================================

test_json_has_all_required_fields() {
    local output
    output=$("$ENTRY_SCRIPT" "plan.md")

    assert_contains "$output" '"action":' "should have action field"
    assert_contains "$output" '"status":' "should have status field"
    assert_contains "$output" '"current_phase":' "should have current_phase field"
    assert_contains "$output" '"feature_dir":' "should have feature_dir field"
    assert_contains "$output" '"plan_file":' "should have plan_file field"
    assert_contains "$output" '"state_file":' "should have state_file field"
    assert_contains "$output" '"resume_mode":' "should have resume_mode field"
    assert_contains "$output" '"error":' "should have error field"
}

test_json_structure_valid() {
    local output
    output=$("$ENTRY_SCRIPT" "plan.md")

    local first_char
    local last_char
    first_char=$(echo "$output" | head -1 | tr -d '[:space:]')
    last_char=$(echo "$output" | tail -1 | tr -d '[:space:]')

    assert_equals "{" "$first_char" "JSON should start with {"
    assert_equals "}" "$last_char" "JSON should end with }"
}

test_current_phase_is_number() {
    create_state_file "specs/test" "in_progress" 5

    local output
    output=$("$ENTRY_SCRIPT" "--resume")

    # Check that current_phase is a number (no quotes around it)
    assert_contains "$output" '"current_phase": 5' "current_phase should be numeric"
}

test_resume_mode_is_boolean() {
    local output
    output=$("$ENTRY_SCRIPT" "plan.md --resume")

    # Check that resume_mode is true (no quotes)
    assert_contains "$output" '"resume_mode": true' "resume_mode should be boolean true"
}

test_resume_mode_false_by_default() {
    local output
    output=$("$ENTRY_SCRIPT" "plan.md")

    assert_contains "$output" '"resume_mode": false' "resume_mode should be boolean false"
}

# ============================================================================
# Tests: Edge cases
# ============================================================================

test_empty_specs_directory() {
    # specs directory exists but has no state files
    local output
    output=$("$ENTRY_SCRIPT" "--resume")

    assert_json_field "$output" "action" "error" "should error with no state files"
}

test_plan_file_with_resume() {
    create_state_file "specs/existing" "in_progress" 2

    local output
    output=$("$ENTRY_SCRIPT" "new-plan.md --resume")

    # When --resume is set, it should look for existing state
    assert_json_field "$output" "resume_mode" "true" "should set resume_mode"
}

test_default_phase_is_zero() {
    local output
    output=$("$ENTRY_SCRIPT" "plan.md")

    assert_json_field "$output" "current_phase" "0" "default phase should be 0"
}

test_handles_state_without_phase() {
    # Create state file without currentPhase field
    mkdir -p specs/no-phase
    cat > specs/no-phase/.workflow-state.json <<EOF
{
  "status": "in_progress",
  "feature": "test"
}
EOF

    local output
    output=$("$ENTRY_SCRIPT" "--resume")

    assert_json_field "$output" "current_phase" "0" "should default to phase 0"
}

test_handles_nested_feature_dir() {
    create_state_file "specs/2026/q1/feature-001" "in_progress" 1

    local output
    output=$("$ENTRY_SCRIPT" "--resume")

    # Should still find the state file (maxdepth 2 limitation)
    # This test documents current behavior - it may NOT find deeply nested files
    assert_json_field "$output" "action" "error" "maxdepth 2 should not find deeply nested state"
}

test_strips_resume_from_args() {
    # The script should strip --resume from ARGS to avoid passing it further
    local output
    output=$("$ENTRY_SCRIPT" "plan.md --resume")

    assert_json_field "$output" "plan_file" "plan.md" "should still parse plan file after stripping --resume"
}

test_multiple_state_files_picks_newest() {
    # Create multiple state files
    create_state_file "specs/feature-a" "completed" 5
    sleep 0.1
    create_state_file "specs/feature-b" "in_progress" 2
    sleep 0.1
    create_state_file "specs/feature-c" "halted" 3

    local output
    output=$("$ENTRY_SCRIPT" "--resume")

    # Should find the most recently modified one (feature-c)
    assert_contains "$output" "specs/feature-c" "should find most recent state file"
}

# ============================================================================
# Tests: Error handling
# ============================================================================

test_error_field_empty_on_success() {
    local output
    output=$("$ENTRY_SCRIPT" "plan.md")

    assert_json_field "$output" "error" "" "error should be empty on success"
}

test_error_message_when_no_workflow() {
    local output
    output=$("$ENTRY_SCRIPT" "")

    assert_contains "$output" "No plan file provided and no existing workflow found" "should have descriptive error"
}

# ============================================================================
# Main
# ============================================================================

echo "Running entry-point.sh tests..."
echo ""

# Verify script exists
if [ ! -f "$ENTRY_SCRIPT" ]; then
    echo -e "${RED}ERROR${NC}: Script not found: $ENTRY_SCRIPT"
    exit 1
fi

run_test "initialize action with plan file" test_initialize_with_plan_file
run_test "error when no plan and no state" test_error_when_no_plan_and_no_state
run_test "resume from existing state file" test_resume_from_existing_state
run_test "finds most recent state file" test_resume_finds_most_recent_state
run_test "completed status returns complete action" test_complete_status_returns_complete_action
run_test "halted status returns halted action" test_halted_status_returns_halted_action
run_test "in_progress status returns resume action" test_in_progress_status_returns_resume_action
run_test "state file path in output" test_state_file_path_in_output
run_test "feature dir extracted from state" test_feature_dir_extracted_from_state
run_test "no state file when initializing" test_no_state_file_when_initializing
run_test "JSON has all required fields" test_json_has_all_required_fields
run_test "JSON structure is valid" test_json_structure_valid
run_test "current_phase is a number" test_current_phase_is_number
run_test "resume_mode is boolean true" test_resume_mode_is_boolean
run_test "resume_mode defaults to false" test_resume_mode_false_by_default
run_test "empty specs directory" test_empty_specs_directory
run_test "plan file with --resume flag" test_plan_file_with_resume
run_test "default phase is zero" test_default_phase_is_zero
run_test "handles state without phase field" test_handles_state_without_phase
run_test "handles nested feature dir (maxdepth 2)" test_handles_nested_feature_dir
run_test "strips --resume from args" test_strips_resume_from_args
run_test "multiple state files picks newest" test_multiple_state_files_picks_newest
run_test "error field empty on success" test_error_field_empty_on_success
run_test "error message when no workflow" test_error_message_when_no_workflow

echo ""
echo "============================================"
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed (of $TESTS_RUN)"
echo "============================================"

if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
fi
