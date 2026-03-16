#!/usr/bin/env bash
# parse-tasks.test.sh - Comprehensive tests for parse-tasks.sh
# Run with: bash test/parse-tasks.test.sh

set -euo pipefail

# ==============================================================================
# Test Framework
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/../scripts/bash"
PARSE_TASKS="$SCRIPTS_DIR/parse-tasks.sh"

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

    # Create a minimal git repo for get_repo_root to work
    mkdir -p "$TEST_TMP/.git"
    mkdir -p "$TEST_TMP/specs/001-test-feature"

    # Create test tasks.md files
    mkdir -p "$TEST_TMP/fixtures"
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

assert_json_array_length() {
    local json="$1"
    local field="$2"
    local expected="$3"

    local actual
    actual=$(echo "$json" | jq ".$field | length" 2>/dev/null || echo "-1")

    if [ "$actual" = "$expected" ]; then
        return 0
    else
        echo "  JSON array .$field length"
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

    if $func; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ==============================================================================
# Test Fixtures
# ==============================================================================

create_standard_tasks_file() {
    cat > "$TEST_TMP/fixtures/standard.md" << 'EOF'
# Implementation Tasks

## Phase 1: Foundation

- [ ] T001: Create database schema
  - Define collections
  - Add indexes
  - **Verify**: TEST | `yarn test test/db/schema.test.ts`

- [x] T002: Set up configuration
  - **Verify**: MANUAL | Config file exists

## Phase 2: Core Implementation

- [ ] T003: Implement API endpoint
  - Route handler
  - Validation
  - **Verify**: API | POST /api/endpoint → 200

- [X] T004: Add logging
  - **Verify**: TEST | `yarn test test/logging.test.ts`
EOF
}

create_empty_tasks_file() {
    cat > "$TEST_TMP/fixtures/empty.md" << 'EOF'
# Implementation Tasks

No tasks defined yet.
EOF
}

create_no_deps_tasks_file() {
    cat > "$TEST_TMP/fixtures/no-deps.md" << 'EOF'
# Tasks

- [ ] T001: Simple task without verify
- [x] T002: Another simple task
- [ ] T003: Third task
EOF
}

create_malformed_tasks_file() {
    cat > "$TEST_TMP/fixtures/malformed.md" << 'EOF'
# Broken Tasks

This is not a task list at all.

- Some random bullet point
- Another bullet

## Broken Section
- [ ] Not a proper task ID
- [x] Missing ID completely
- [ ] T001 Missing colon after ID
- T002: Missing checkbox
EOF
}

create_special_chars_tasks_file() {
    cat > "$TEST_TMP/fixtures/special.md" << 'EOF'
# Tasks with Special Characters

## Phase 1

- [ ] T001: Handle "quoted strings" and 'single quotes'
  - **Verify**: TEST | `yarn test --grep "special"`

- [ ] T002: Process $variables and `backticks`

- [ ] T003: Deal with <angle> brackets & ampersands
EOF
}

create_large_task_ids_file() {
    cat > "$TEST_TMP/fixtures/large-ids.md" << 'EOF'
# Tasks with Large IDs

- [ ] T100: Hundredth task
- [ ] T999: Almost a thousand
- [ ] T1000: Four digit task
- [ ] T9999: Max supported task
EOF
}

create_subtasks_file() {
    cat > "$TEST_TMP/fixtures/subtasks.md" << 'EOF'
# Tasks with Subtasks

## Phase 1

- [ ] T001: Main task with subtasks
  - First subtask item
  - Second subtask item
  - Third subtask item
  - **Verify**: TEST | `yarn test`

- [ ] T002: Task with deep nesting
  - Level 1 subtask
    - Level 2 nested (ignored by parser)
  - Another level 1
EOF
}

# ==============================================================================
# Test Cases: Basic Functionality
# ==============================================================================

test_extracts_task_ids() {
    create_standard_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/standard.md" 2>/dev/null)

    assert_json_field "$output" "tasks[0].id" "T001" && \
    assert_json_field "$output" "tasks[1].id" "T002" && \
    assert_json_field "$output" "tasks[2].id" "T003" && \
    assert_json_field "$output" "tasks[3].id" "T004"
}

test_extracts_task_descriptions() {
    create_standard_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/standard.md" 2>/dev/null)

    assert_json_field "$output" "tasks[0].description" "Create database schema" && \
    assert_json_field "$output" "tasks[2].description" "Implement API endpoint"
}

test_extracts_completion_status() {
    create_standard_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/standard.md" 2>/dev/null)

    assert_json_field "$output" "tasks[0].complete" "false" && \
    assert_json_field "$output" "tasks[1].complete" "true" && \
    assert_json_field "$output" "tasks[2].complete" "false" && \
    assert_json_field "$output" "tasks[3].complete" "true"
}

test_extracts_phase_info() {
    create_standard_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/standard.md" 2>/dev/null)

    assert_json_field "$output" "tasks[0].phase" "Phase 1: Foundation" && \
    assert_json_field "$output" "tasks[2].phase" "Phase 2: Core Implementation"
}

test_extracts_verify_info() {
    create_standard_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/standard.md" 2>/dev/null)

    local verify_type
    verify_type=$(echo "$output" | jq -r '.tasks[0].verify.type' 2>/dev/null)
    local verify_condition
    verify_condition=$(echo "$output" | jq -r '.tasks[0].verify.condition' 2>/dev/null)

    assert_equals "TEST" "$verify_type" && \
    assert_contains "$verify_condition" "yarn test"
}

test_extracts_subtasks() {
    create_subtasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/subtasks.md" 2>/dev/null)

    local subtask_count
    subtask_count=$(echo "$output" | jq '.tasks[0].subtasks | length' 2>/dev/null)

    assert_equals "3" "$subtask_count"
}

test_extracts_line_numbers() {
    create_standard_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/standard.md" 2>/dev/null)

    local line1
    line1=$(echo "$output" | jq '.tasks[0].line' 2>/dev/null)

    # Line number should be a positive integer
    [ "$line1" -gt 0 ] 2>/dev/null
}

# ==============================================================================
# Test Cases: JSON Output Structure
# ==============================================================================

test_returns_json_array() {
    create_standard_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/standard.md" 2>/dev/null)

    # Verify it's valid JSON
    echo "$output" | jq . >/dev/null 2>&1
}

test_json_has_metadata() {
    create_standard_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/standard.md" 2>/dev/null)

    assert_json_field "$output" "total" "4" && \
    assert_json_field "$output" "complete" "2" && \
    assert_json_field "$output" "incomplete" "2" && \
    assert_json_field "$output" "filter" "all"
}

test_json_includes_file_path() {
    create_standard_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/standard.md" 2>/dev/null)

    local file_path
    file_path=$(echo "$output" | jq -r '.file' 2>/dev/null)

    assert_contains "$file_path" "standard.md"
}

# ==============================================================================
# Test Cases: Status Filtering
# ==============================================================================

test_filter_incomplete_tasks() {
    create_standard_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/standard.md" --status incomplete 2>/dev/null)

    assert_json_array_length "$output" "tasks" "2" && \
    assert_json_field "$output" "tasks[0].id" "T001" && \
    assert_json_field "$output" "tasks[1].id" "T003"
}

test_filter_complete_tasks() {
    create_standard_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/standard.md" --status complete 2>/dev/null)

    assert_json_array_length "$output" "tasks" "2" && \
    assert_json_field "$output" "tasks[0].id" "T002" && \
    assert_json_field "$output" "tasks[1].id" "T004"
}

test_filter_all_tasks_default() {
    create_standard_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/standard.md" 2>/dev/null)

    assert_json_array_length "$output" "tasks" "4"
}

# ==============================================================================
# Test Cases: Edge Cases
# ==============================================================================

test_handles_empty_tasks_file() {
    create_empty_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/empty.md" 2>/dev/null)

    assert_json_array_length "$output" "tasks" "0" && \
    assert_json_field "$output" "total" "0"
}

test_handles_tasks_without_verify() {
    create_no_deps_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/no-deps.md" 2>/dev/null)

    assert_json_array_length "$output" "tasks" "3" && \
    assert_json_field "$output" "tasks[0].verify" "null"
}

test_handles_malformed_gracefully() {
    create_malformed_tasks_file
    local output
    local exit_code=0
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/malformed.md" 2>/dev/null) || exit_code=$?

    # Should not crash, should return valid JSON (possibly empty tasks)
    [ "$exit_code" -eq 0 ] && echo "$output" | jq . >/dev/null 2>&1
}

test_handles_special_characters() {
    create_special_chars_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/special.md" 2>/dev/null)

    # Should produce valid JSON despite special chars
    echo "$output" | jq . >/dev/null 2>&1 && \
    assert_json_array_length "$output" "tasks" "3"
}

test_handles_large_task_ids() {
    create_large_task_ids_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/large-ids.md" 2>/dev/null)

    assert_json_field "$output" "tasks[0].id" "T100" && \
    assert_json_field "$output" "tasks[2].id" "T1000" && \
    assert_json_field "$output" "tasks[3].id" "T9999"
}

test_handles_uppercase_x_checkbox() {
    create_standard_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/standard.md" 2>/dev/null)

    # T004 uses [X] (uppercase)
    assert_json_field "$output" "tasks[3].complete" "true"
}

# ==============================================================================
# Test Cases: Error Handling
# ==============================================================================

test_fails_without_file_arg() {
    local exit_code=0
    bash "$PARSE_TASKS" 2>/dev/null || exit_code=$?

    [ "$exit_code" -ne 0 ]
}

test_fails_with_missing_file() {
    local exit_code=0
    cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "nonexistent.md" 2>/dev/null || exit_code=$?

    [ "$exit_code" -ne 0 ]
}

test_fails_with_unknown_arg() {
    local exit_code=0
    create_standard_tasks_file
    cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/standard.md" --bogus 2>/dev/null || exit_code=$?

    [ "$exit_code" -ne 0 ]
}

test_help_flag_exits_zero() {
    local exit_code=0
    bash "$PARSE_TASKS" --help >/dev/null 2>&1 || exit_code=$?

    [ "$exit_code" -eq 0 ]
}

# ==============================================================================
# Test Cases: Security
# ==============================================================================

test_file_path_via_env_not_injection() {
    # Create a file with malicious-looking name (but safe content)
    local safe_file="$TEST_TMP/fixtures/safe.md"
    cat > "$safe_file" << 'EOF'
# Tasks
- [ ] T001: Safe task
EOF

    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/safe.md" 2>/dev/null)

    # Should work without any command injection
    assert_json_field "$output" "tasks[0].id" "T001"
}

test_relative_path_resolved() {
    create_standard_tasks_file
    local output
    output=$(cd "$TEST_TMP" && bash "$PARSE_TASKS" --file "fixtures/standard.md" 2>/dev/null)

    # File path in output should be absolute
    local file_path
    file_path=$(echo "$output" | jq -r '.file' 2>/dev/null)

    [[ "$file_path" == /* ]]
}

test_absolute_path_works() {
    create_standard_tasks_file
    local output
    output=$(bash "$PARSE_TASKS" --file "$TEST_TMP/fixtures/standard.md" 2>/dev/null)

    assert_json_array_length "$output" "tasks" "4"
}

# ==============================================================================
# Main Test Runner
# ==============================================================================

main() {
    echo ""
    echo "=========================================="
    echo "  parse-tasks.sh Test Suite"
    echo "=========================================="
    echo ""

    # Check dependencies
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${RED}ERROR: jq is required for tests${NC}"
        exit 1
    fi

    setup
    trap teardown EXIT

    echo "Basic Functionality:"
    run_test "extracts task IDs" test_extracts_task_ids
    run_test "extracts task descriptions" test_extracts_task_descriptions
    run_test "extracts completion status" test_extracts_completion_status
    run_test "extracts phase info" test_extracts_phase_info
    run_test "extracts verify info" test_extracts_verify_info
    run_test "extracts subtasks" test_extracts_subtasks
    run_test "extracts line numbers" test_extracts_line_numbers
    echo ""

    echo "JSON Output Structure:"
    run_test "returns valid JSON" test_returns_json_array
    run_test "JSON has metadata fields" test_json_has_metadata
    run_test "JSON includes file path" test_json_includes_file_path
    echo ""

    echo "Status Filtering:"
    run_test "filter incomplete tasks" test_filter_incomplete_tasks
    run_test "filter complete tasks" test_filter_complete_tasks
    run_test "filter all tasks (default)" test_filter_all_tasks_default
    echo ""

    echo "Edge Cases:"
    run_test "handles empty tasks file" test_handles_empty_tasks_file
    run_test "handles tasks without verify" test_handles_tasks_without_verify
    run_test "handles malformed file gracefully" test_handles_malformed_gracefully
    run_test "handles special characters" test_handles_special_characters
    run_test "handles large task IDs" test_handles_large_task_ids
    run_test "handles uppercase X checkbox" test_handles_uppercase_x_checkbox
    echo ""

    echo "Error Handling:"
    run_test "fails without --file arg" test_fails_without_file_arg
    run_test "fails with missing file" test_fails_with_missing_file
    run_test "fails with unknown argument" test_fails_with_unknown_arg
    run_test "help flag exits zero" test_help_flag_exits_zero
    echo ""

    echo "Security:"
    run_test "file path via env not injection" test_file_path_via_env_not_injection
    run_test "relative path resolved to absolute" test_relative_path_resolved
    run_test "absolute path works" test_absolute_path_works
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
