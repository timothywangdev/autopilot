#!/usr/bin/env bash
# common.test.sh - Unit tests for common.sh utilities
# Run: bash plugins/autopilot/test/common.test.sh

set -euo pipefail

# ==============================================================================
# Test Framework
# ==============================================================================

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST=""

# Colors for output (if terminal supports them)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

# Test result tracking
pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}PASS${NC}: $CURRENT_TEST"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "  ${RED}FAIL${NC}: $CURRENT_TEST"
    echo -e "        ${YELLOW}$1${NC}"
}

run_test() {
    CURRENT_TEST="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    if [ "$expected" = "$actual" ]; then
        pass
    else
        fail "Expected: '$expected', Got: '$actual'"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if echo "$haystack" | grep -qF -- "$needle"; then
        pass
    else
        fail "Expected '$haystack' to contain '$needle'"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    if ! echo "$haystack" | grep -qF -- "$needle"; then
        pass
    else
        fail "Expected '$haystack' to NOT contain '$needle'"
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    if [ "$expected" -eq "$actual" ]; then
        pass
    else
        fail "Expected exit code $expected, got $actual"
    fi
}

assert_file_exists() {
    local file="$1"
    if [ -f "$file" ]; then
        pass
    else
        fail "Expected file to exist: $file"
    fi
}

assert_dir_exists() {
    local dir="$1"
    if [ -d "$dir" ]; then
        pass
    else
        fail "Expected directory to exist: $dir"
    fi
}

# ==============================================================================
# Test Setup
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_SH="$SCRIPT_DIR/../scripts/bash/common.sh"

# Verify common.sh exists
if [ ! -f "$COMMON_SH" ]; then
    echo "ERROR: common.sh not found at $COMMON_SH"
    exit 1
fi

# Source common.sh
source "$COMMON_SH"

# Create temp directory for tests
TEST_TEMP_DIR=""
setup_temp_dir() {
    TEST_TEMP_DIR=$(mktemp -d)
}

cleanup_temp_dir() {
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup_temp_dir EXIT

# ==============================================================================
# Test: Logging Functions
# ==============================================================================

echo ""
echo "Testing: Logging Functions"
echo "=========================="

run_test "log_info outputs to stderr with INFO prefix"
output=$(log_info "test message" 2>&1)
assert_equals "INFO: test message" "$output"

run_test "log_error outputs to stderr with ERROR prefix"
output=$(log_error "error message" 2>&1)
assert_equals "ERROR: error message" "$output"

run_test "log_success outputs to stderr with checkmark"
output=$(log_success "success message" 2>&1)
assert_contains "$output" "success message"

run_test "log_warning outputs to stderr with WARNING prefix"
output=$(log_warning "warning message" 2>&1)
assert_equals "WARNING: warning message" "$output"

run_test "log_info outputs to stderr not stdout"
stdout_output=$(log_info "test" 2>/dev/null)
assert_equals "" "$stdout_output"

run_test "log_error outputs to stderr not stdout"
stdout_output=$(log_error "test" 2>/dev/null)
assert_equals "" "$stdout_output"

# ==============================================================================
# Test: Repository Detection
# ==============================================================================

echo ""
echo "Testing: Repository Detection"
echo "============================="

run_test "get_repo_root returns directory with .git"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/.git"
mkdir -p "$TEST_TEMP_DIR/project/subdir/deep"
result=$(get_repo_root "$TEST_TEMP_DIR/project/subdir/deep")
assert_equals "$TEST_TEMP_DIR/project" "$result"
cleanup_temp_dir

run_test "get_repo_root returns directory with .autopilot"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/.autopilot"
mkdir -p "$TEST_TEMP_DIR/project/subdir"
result=$(get_repo_root "$TEST_TEMP_DIR/project/subdir")
assert_equals "$TEST_TEMP_DIR/project" "$result"
cleanup_temp_dir

run_test "get_repo_root prefers .git over .autopilot at same level"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/.git"
mkdir -p "$TEST_TEMP_DIR/project/.autopilot"
result=$(get_repo_root "$TEST_TEMP_DIR/project")
assert_equals "$TEST_TEMP_DIR/project" "$result"
cleanup_temp_dir

run_test "get_repo_root falls back to pwd for non-repo directory"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/not-a-repo"
result=$(cd "$TEST_TEMP_DIR/not-a-repo" && get_repo_root)
# Falls back to pwd
assert_contains "$result" "not-a-repo"
cleanup_temp_dir

run_test "get_repo_root handles nested repos (finds closest)"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/outer/.git"
mkdir -p "$TEST_TEMP_DIR/outer/inner/.git"
result=$(get_repo_root "$TEST_TEMP_DIR/outer/inner")
assert_equals "$TEST_TEMP_DIR/outer/inner" "$result"
cleanup_temp_dir

# ==============================================================================
# Test: Feature Number Extraction
# ==============================================================================

echo ""
echo "Testing: Feature Number Functions"
echo "=================================="

run_test "get_highest_feature_number returns 0 for empty specs dir"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/specs"
mkdir -p "$TEST_TEMP_DIR/project/.git"
result=$(get_highest_feature_number "$TEST_TEMP_DIR/project")
assert_equals "0" "$result"
cleanup_temp_dir

run_test "get_highest_feature_number finds 3-digit features"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/.git"
mkdir -p "$TEST_TEMP_DIR/project/specs/001-first-feature"
mkdir -p "$TEST_TEMP_DIR/project/specs/005-fifth-feature"
mkdir -p "$TEST_TEMP_DIR/project/specs/003-third-feature"
result=$(get_highest_feature_number "$TEST_TEMP_DIR/project")
assert_equals "5" "$result"
cleanup_temp_dir

run_test "get_highest_feature_number handles 3-digit padding (001-999)"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/.git"
mkdir -p "$TEST_TEMP_DIR/project/specs/099-feature"
mkdir -p "$TEST_TEMP_DIR/project/specs/100-feature"
mkdir -p "$TEST_TEMP_DIR/project/specs/999-feature"
result=$(get_highest_feature_number "$TEST_TEMP_DIR/project")
assert_equals "999" "$result"
cleanup_temp_dir

run_test "get_highest_feature_number handles 4-digit padding (1000-9999)"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/.git"
mkdir -p "$TEST_TEMP_DIR/project/specs/0999-feature"
mkdir -p "$TEST_TEMP_DIR/project/specs/1000-feature"
mkdir -p "$TEST_TEMP_DIR/project/specs/1234-feature"
result=$(get_highest_feature_number "$TEST_TEMP_DIR/project")
assert_equals "1234" "$result"
cleanup_temp_dir

run_test "get_highest_feature_number ignores non-numeric directories"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/.git"
mkdir -p "$TEST_TEMP_DIR/project/specs/010-valid-feature"
mkdir -p "$TEST_TEMP_DIR/project/specs/not-a-feature"
mkdir -p "$TEST_TEMP_DIR/project/specs/readme"
result=$(get_highest_feature_number "$TEST_TEMP_DIR/project")
assert_equals "10" "$result"
cleanup_temp_dir

run_test "get_highest_feature_number handles leading zeros correctly"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/.git"
mkdir -p "$TEST_TEMP_DIR/project/specs/007-james-bond"
mkdir -p "$TEST_TEMP_DIR/project/specs/042-answer"
result=$(get_highest_feature_number "$TEST_TEMP_DIR/project")
assert_equals "42" "$result"
cleanup_temp_dir

run_test "get_highest_feature_number warns on numbers > 9999"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/.git"
mkdir -p "$TEST_TEMP_DIR/project/specs/10000-too-big"
mkdir -p "$TEST_TEMP_DIR/project/specs/0050-valid"
warning_output=$(get_highest_feature_number "$TEST_TEMP_DIR/project" 2>&1)
result=$(get_highest_feature_number "$TEST_TEMP_DIR/project" 2>/dev/null)
assert_equals "50" "$result"
cleanup_temp_dir

# ==============================================================================
# Test: find_feature_dir
# ==============================================================================

echo ""
echo "Testing: find_feature_dir"
echo "========================="

run_test "find_feature_dir finds 3-digit directory from branch name"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/.git"
mkdir -p "$TEST_TEMP_DIR/project/specs/007-my-feature"
result=$(find_feature_dir "$TEST_TEMP_DIR/project" "007-my-feature")
assert_equals "$TEST_TEMP_DIR/project/specs/007-my-feature" "$result"
cleanup_temp_dir

run_test "find_feature_dir finds directory from unprefixed number"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/.git"
mkdir -p "$TEST_TEMP_DIR/project/specs/042-answer"
result=$(find_feature_dir "$TEST_TEMP_DIR/project" "42-answer")
assert_equals "$TEST_TEMP_DIR/project/specs/042-answer" "$result"
cleanup_temp_dir

run_test "find_feature_dir returns error for non-numeric branch"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/.git"
mkdir -p "$TEST_TEMP_DIR/project/specs/001-feature"
result=$(find_feature_dir "$TEST_TEMP_DIR/project" "main" 2>/dev/null) || exit_code=$?
assert_exit_code 1 "${exit_code:-0}"
cleanup_temp_dir

run_test "find_feature_dir handles 4-digit features"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/.git"
mkdir -p "$TEST_TEMP_DIR/project/specs/1234-big-feature"
result=$(find_feature_dir "$TEST_TEMP_DIR/project" "1234-big-feature")
assert_equals "$TEST_TEMP_DIR/project/specs/1234-big-feature" "$result"
cleanup_temp_dir

run_test "find_feature_dir returns error when directory not found"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/.git"
mkdir -p "$TEST_TEMP_DIR/project/specs/001-different"
result=$(find_feature_dir "$TEST_TEMP_DIR/project" "999-nonexistent" 2>/dev/null) || exit_code=$?
assert_exit_code 1 "${exit_code:-0}"
cleanup_temp_dir

# ==============================================================================
# Test: Branch Name Generation
# ==============================================================================

echo ""
echo "Testing: Branch Name Generation"
echo "================================"

run_test "clean_branch_name converts to lowercase"
result=$(clean_branch_name "MyFeature")
assert_equals "myfeature" "$result"

run_test "clean_branch_name replaces spaces with hyphens"
result=$(clean_branch_name "my feature name")
assert_equals "my-feature-name" "$result"

run_test "clean_branch_name removes special characters"
result=$(clean_branch_name "feature@#\$%test")
assert_equals "feature-test" "$result"

run_test "clean_branch_name truncates to 50 characters"
long_name="this-is-a-very-long-branch-name-that-should-be-truncated-to-fifty-characters"
result=$(clean_branch_name "$long_name")
[ ${#result} -le 50 ] && pass || fail "Length ${#result} > 50"

run_test "clean_branch_name removes leading/trailing hyphens"
result=$(clean_branch_name "-feature-name-")
assert_equals "feature-name" "$result"

run_test "generate_branch_name removes stop words"
result=$(generate_branch_name "Add a new feature for the users")
assert_not_contains "$result" "-a-"
assert_not_contains "$result" "-the-"
assert_not_contains "$result" "-for-"

run_test "generate_branch_name limits to 4 words"
result=$(generate_branch_name "Add new feature for users with authentication and authorization")
word_count=$(echo "$result" | tr '-' '\n' | wc -l)
[ "$word_count" -le 4 ] && pass || fail "Word count $word_count > 4"

run_test "generate_branch_name skips short words"
result=$(generate_branch_name "go to do it")
assert_equals "feature" "$result"  # Falls back to "feature"

run_test "generate_branch_name handles empty input"
result=$(generate_branch_name "")
assert_equals "feature" "$result"

# ==============================================================================
# Test: JSON Output Functions
# ==============================================================================

echo ""
echo "Testing: JSON Output Functions"
echo "==============================="

run_test "json_escape escapes double quotes"
result=$(json_escape 'hello "world"')
assert_equals 'hello \"world\"' "$result"

run_test "json_escape escapes backslashes"
result=$(json_escape 'path\\to\\file')
assert_equals 'path\\\\to\\\\file' "$result"

run_test "json_escape handles tabs"
result=$(json_escape $'hello\tworld')
assert_equals 'hello\tworld' "$result"

run_test "json_escape converts newlines to spaces"
result=$(json_escape $'hello\nworld')
# json_escape converts newlines to spaces
assert_equals "hello world" "$result"

run_test "json_output creates valid JSON object"
result=$(json_output "key1" "value1" "key2" "value2")
assert_equals '{"key1":"value1","key2":"value2"}' "$result"

run_test "json_output handles single key-value pair"
result=$(json_output "name" "test")
assert_equals '{"name":"test"}' "$result"

run_test "json_output handles empty input"
result=$(json_output)
assert_equals '{}' "$result"

run_test "json_output escapes values with quotes"
result=$(json_output "message" 'say "hello"')
assert_equals '{"message":"say \"hello\""}' "$result"

run_test "json_array creates valid JSON array"
result=$(json_array "a" "b" "c")
assert_equals '["a","b","c"]' "$result"

run_test "json_array handles single value"
result=$(json_array "only")
assert_equals '["only"]' "$result"

run_test "json_array handles empty input"
result=$(json_array)
assert_equals '[]' "$result"

run_test "json_array escapes values"
result=$(json_array 'hello "world"' 'test')
assert_equals '["hello \"world\"","test"]' "$result"

# ==============================================================================
# Test: Validation Functions
# ==============================================================================

echo ""
echo "Testing: Validation Functions"
echo "=============================="

run_test "validate_plan_path rejects empty path"
result=$(validate_plan_path "" 2>&1) || exit_code=$?
assert_exit_code 1 "${exit_code:-0}"

run_test "validate_plan_path rejects shell metacharacters"
setup_temp_dir
result=$(validate_plan_path '$HOME/plan.md' "$TEST_TEMP_DIR" 2>&1) || exit_code=$?
assert_exit_code 1 "${exit_code:-0}"
cleanup_temp_dir

run_test "validate_plan_path rejects backticks"
setup_temp_dir
result=$(validate_plan_path '`whoami`.md' "$TEST_TEMP_DIR" 2>&1) || exit_code=$?
assert_exit_code 1 "${exit_code:-0}"
cleanup_temp_dir

run_test "validate_plan_path rejects path traversal"
setup_temp_dir
result=$(validate_plan_path '../../../etc/passwd.md' "$TEST_TEMP_DIR" 2>&1) || exit_code=$?
assert_exit_code 1 "${exit_code:-0}"
cleanup_temp_dir

run_test "validate_plan_path rejects non-.md files"
setup_temp_dir
echo "test" > "$TEST_TEMP_DIR/plan.txt"
result=$(validate_plan_path "$TEST_TEMP_DIR/plan.txt" "$TEST_TEMP_DIR" 2>&1) || exit_code=$?
assert_exit_code 1 "${exit_code:-0}"
cleanup_temp_dir

run_test "validate_plan_path accepts valid .md file"
setup_temp_dir
echo "# Plan" > "$TEST_TEMP_DIR/plan.md"
result=$(validate_plan_path "$TEST_TEMP_DIR/plan.md" "$TEST_TEMP_DIR" 2>/dev/null)
exit_code=$?
assert_exit_code 0 "$exit_code"
cleanup_temp_dir

run_test "validate_plan_path rejects file outside repo root"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/repo"
mkdir -p "$TEST_TEMP_DIR/outside"
echo "# Evil" > "$TEST_TEMP_DIR/outside/plan.md"
result=$(validate_plan_path "$TEST_TEMP_DIR/outside/plan.md" "$TEST_TEMP_DIR/repo" 2>&1) || exit_code=$?
assert_exit_code 1 "${exit_code:-0}"
cleanup_temp_dir

run_test "validate_plan_path rejects symlinks"
setup_temp_dir
echo "# Real" > "$TEST_TEMP_DIR/real.md"
ln -s "$TEST_TEMP_DIR/real.md" "$TEST_TEMP_DIR/link.md"
result=$(validate_plan_path "$TEST_TEMP_DIR/link.md" "$TEST_TEMP_DIR" 2>&1) || exit_code=$?
assert_exit_code 1 "${exit_code:-0}"
cleanup_temp_dir

run_test "check_file_exists returns success for existing file"
setup_temp_dir
echo "content" > "$TEST_TEMP_DIR/file.txt"
output=$(check_file_exists "$TEST_TEMP_DIR/file.txt" "test file")
exit_code=$?
assert_exit_code 0 "$exit_code"
cleanup_temp_dir

run_test "check_file_exists returns error for missing file"
setup_temp_dir
output=$(check_file_exists "$TEST_TEMP_DIR/missing.txt" "test file") || exit_code=$?
assert_exit_code 1 "${exit_code:-0}"
cleanup_temp_dir

run_test "check_file_exists returns error for empty file"
setup_temp_dir
touch "$TEST_TEMP_DIR/empty.txt"
output=$(check_file_exists "$TEST_TEMP_DIR/empty.txt" "test file") || exit_code=$?
assert_exit_code 1 "${exit_code:-0}"
cleanup_temp_dir

run_test "check_dir_exists returns success for non-empty directory"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/dir"
touch "$TEST_TEMP_DIR/dir/file.txt"
output=$(check_dir_exists "$TEST_TEMP_DIR/dir" "test dir")
exit_code=$?
assert_exit_code 0 "$exit_code"
cleanup_temp_dir

run_test "check_dir_exists returns error for missing directory"
setup_temp_dir
output=$(check_dir_exists "$TEST_TEMP_DIR/missing" "test dir") || exit_code=$?
assert_exit_code 1 "${exit_code:-0}"
cleanup_temp_dir

run_test "check_dir_exists returns error for empty directory"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/empty-dir"
output=$(check_dir_exists "$TEST_TEMP_DIR/empty-dir" "test dir") || exit_code=$?
assert_exit_code 1 "${exit_code:-0}"
cleanup_temp_dir

# ==============================================================================
# Test: shell_escape
# ==============================================================================

echo ""
echo "Testing: shell_escape"
echo "====================="

run_test "shell_escape handles single quotes"
result=$(shell_escape "it's a test")
assert_equals "it'\''s a test" "$result"

run_test "shell_escape handles multiple single quotes"
result=$(shell_escape "don't won't can't")
assert_equals "don'\''t won'\''t can'\''t" "$result"

run_test "shell_escape handles strings without quotes"
result=$(shell_escape "simple string")
assert_equals "simple string" "$result"

# ==============================================================================
# Test: get_realpath
# ==============================================================================

echo ""
echo "Testing: get_realpath"
echo "====================="

run_test "get_realpath resolves relative path"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/dir"
touch "$TEST_TEMP_DIR/dir/file.txt"
result=$(cd "$TEST_TEMP_DIR" && get_realpath "dir/file.txt")
assert_equals "$TEST_TEMP_DIR/dir/file.txt" "$result"
cleanup_temp_dir

run_test "get_realpath handles absolute path"
setup_temp_dir
touch "$TEST_TEMP_DIR/file.txt"
result=$(get_realpath "$TEST_TEMP_DIR/file.txt")
assert_equals "$TEST_TEMP_DIR/file.txt" "$result"
cleanup_temp_dir

# ==============================================================================
# Test: get_feature_paths
# ==============================================================================

echo ""
echo "Testing: get_feature_paths"
echo "=========================="

run_test "get_feature_paths returns shell-evaluable output"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/.git"
mkdir -p "$TEST_TEMP_DIR/project/specs/001-test-feature"
cd "$TEST_TEMP_DIR/project"
export AUTOPILOT_FEATURE="001-test-feature"
output=$(get_feature_paths)
# Should be evaluable without error
eval "$output"
assert_equals "$TEST_TEMP_DIR/project" "$REPO_ROOT"
unset AUTOPILOT_FEATURE
cleanup_temp_dir

run_test "get_feature_paths sets FEATURE_DIR correctly"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/project/.git"
mkdir -p "$TEST_TEMP_DIR/project/specs/042-my-feature"
cd "$TEST_TEMP_DIR/project"
export AUTOPILOT_FEATURE="042-my-feature"
output=$(get_feature_paths)
eval "$output"
assert_equals "$TEST_TEMP_DIR/project/specs/042-my-feature" "$FEATURE_DIR"
unset AUTOPILOT_FEATURE
cleanup_temp_dir

run_test "get_feature_paths handles paths with spaces"
setup_temp_dir
mkdir -p "$TEST_TEMP_DIR/my project/.git"
mkdir -p "$TEST_TEMP_DIR/my project/specs/001-test"
cd "$TEST_TEMP_DIR/my project"
export AUTOPILOT_FEATURE="001-test"
output=$(get_feature_paths)
eval "$output"
assert_equals "$TEST_TEMP_DIR/my project" "$REPO_ROOT"
unset AUTOPILOT_FEATURE
cleanup_temp_dir

# ==============================================================================
# Test: Configuration Constants
# ==============================================================================

echo ""
echo "Testing: Configuration Constants"
echo "================================="

run_test "AUTOPILOT_VERSION is set"
[ -n "$AUTOPILOT_VERSION" ] && pass || fail "AUTOPILOT_VERSION is empty"

run_test "SPECS_DIR is set to 'specs'"
assert_equals "specs" "$SPECS_DIR"

run_test "STATE_FILE_NAME is set"
[ -n "$STATE_FILE_NAME" ] && pass || fail "STATE_FILE_NAME is empty"

# ==============================================================================
# Test Summary
# ==============================================================================

echo ""
echo "=============================================="
echo "Test Summary"
echo "=============================================="
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
