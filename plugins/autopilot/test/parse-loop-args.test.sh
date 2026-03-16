#!/usr/bin/env bash
# Tests for parse-loop-args.sh
#
# Run: ./parse-loop-args.test.sh
# Or:  bash parse-loop-args.test.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_SCRIPT="$SCRIPT_DIR/../scripts/bash/parse-loop-args.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# ============================================================================
# Test Helpers
# ============================================================================

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

    if $test_func; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ============================================================================
# Tests
# ============================================================================

test_parses_plan_file() {
    local output
    output=$("$PARSE_SCRIPT" "specs/feature-001/plan.md")

    assert_json_field "$output" "plan_file" "specs/feature-001/plan.md" "should parse plan file"
}

test_parses_plan_file_with_path() {
    local output
    output=$("$PARSE_SCRIPT" "/absolute/path/to/feature.md")

    assert_json_field "$output" "plan_file" "/absolute/path/to/feature.md" "should parse absolute path"
}

test_parses_resume_flag() {
    local output
    output=$("$PARSE_SCRIPT" "--resume")

    assert_json_field "$output" "resume_mode" "true" "should set resume_mode to true"
}

test_parses_resume_flag_with_plan() {
    local output
    output=$("$PARSE_SCRIPT" "feature.md --resume")

    assert_json_field "$output" "resume_mode" "true" "should set resume_mode with plan"
    assert_json_field "$output" "plan_file" "feature.md" "should also parse plan file"
}

test_parses_interval_flag() {
    local output
    output=$("$PARSE_SCRIPT" "plan.md --interval 5m")

    assert_json_field "$output" "interval" "5m" "should parse interval value"
}

test_parses_interval_with_seconds() {
    local output
    output=$("$PARSE_SCRIPT" "plan.md --interval 30s")

    assert_json_field "$output" "interval" "30s" "should parse interval in seconds"
}

test_default_interval() {
    local output
    output=$("$PARSE_SCRIPT" "plan.md")

    assert_json_field "$output" "interval" "1m" "should default interval to 1m"
}

test_builds_autopilot_cmd_with_plan() {
    local output
    output=$("$PARSE_SCRIPT" "specs/feature/plan.md")

    assert_json_field "$output" "autopilot_cmd" "/autopilot:_supervisor specs/feature/plan.md" "should build correct command"
}

test_builds_autopilot_cmd_with_resume() {
    local output
    output=$("$PARSE_SCRIPT" "--resume")

    assert_json_field "$output" "autopilot_cmd" "/autopilot:_supervisor --resume" "should build resume command"
}

test_error_when_no_plan_or_resume() {
    local output
    output=$("$PARSE_SCRIPT" "")

    assert_json_field "$output" "error" "Specify a plan file or use --resume" "should set error"
    assert_json_field "$output" "autopilot_cmd" "" "should have empty command"
}

test_error_with_random_args() {
    local output
    output=$("$PARSE_SCRIPT" "--invalid --flags here")

    assert_json_field "$output" "error" "Specify a plan file or use --resume" "should error on invalid args"
}

test_json_output_is_valid() {
    local output
    output=$("$PARSE_SCRIPT" "plan.md --interval 2m")

    # Check that output contains expected JSON structure
    assert_contains "$output" '"plan_file":' "should have plan_file field"
    assert_contains "$output" '"interval":' "should have interval field"
    assert_contains "$output" '"resume_mode":' "should have resume_mode field"
    assert_contains "$output" '"autopilot_cmd":' "should have autopilot_cmd field"
    assert_contains "$output" '"error":' "should have error field"
}

test_json_starts_and_ends_correctly() {
    local output
    output=$("$PARSE_SCRIPT" "plan.md")

    # Check JSON structure
    local first_char
    local last_char
    first_char=$(echo "$output" | head -1 | tr -d '[:space:]')
    last_char=$(echo "$output" | tail -1 | tr -d '[:space:]')

    assert_equals "{" "$first_char" "JSON should start with {"
    assert_equals "}" "$last_char" "JSON should end with }"
}

test_handles_multiple_md_files() {
    local output
    output=$("$PARSE_SCRIPT" "first.md second.md third.md")

    # Should take the first .md file
    assert_json_field "$output" "plan_file" "first.md" "should take first .md file"
}

test_resume_false_by_default() {
    local output
    output=$("$PARSE_SCRIPT" "plan.md")

    assert_json_field "$output" "resume_mode" "false" "resume_mode should default to false"
}

test_parses_complex_args() {
    local output
    output=$("$PARSE_SCRIPT" "specs/my-feature/plan.md --resume --interval 10s")

    assert_json_field "$output" "plan_file" "specs/my-feature/plan.md" "should parse plan file"
    assert_json_field "$output" "resume_mode" "true" "should parse resume"
    assert_json_field "$output" "interval" "10s" "should parse interval"
}

# ============================================================================
# Main
# ============================================================================

echo "Running parse-loop-args.sh tests..."
echo ""

# Verify script exists
if [ ! -f "$PARSE_SCRIPT" ]; then
    echo -e "${RED}ERROR${NC}: Script not found: $PARSE_SCRIPT"
    exit 1
fi

run_test "parses plan file" test_parses_plan_file
run_test "parses plan file with absolute path" test_parses_plan_file_with_path
run_test "parses --resume flag" test_parses_resume_flag
run_test "parses --resume flag with plan" test_parses_resume_flag_with_plan
run_test "parses --interval flag" test_parses_interval_flag
run_test "parses --interval with seconds" test_parses_interval_with_seconds
run_test "uses default interval" test_default_interval
run_test "builds autopilot command with plan" test_builds_autopilot_cmd_with_plan
run_test "builds autopilot command with --resume" test_builds_autopilot_cmd_with_resume
run_test "errors when no plan or --resume" test_error_when_no_plan_or_resume
run_test "errors with invalid args only" test_error_with_random_args
run_test "JSON output has all fields" test_json_output_is_valid
run_test "JSON structure is correct" test_json_starts_and_ends_correctly
run_test "handles multiple .md files (takes first)" test_handles_multiple_md_files
run_test "resume_mode defaults to false" test_resume_false_by_default
run_test "parses complex argument combination" test_parses_complex_args

echo ""
echo "============================================"
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed (of $TESTS_RUN)"
echo "============================================"

if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
fi
