#!/usr/bin/env bash
# Test suite for init-project.sh
#
# Usage: bash test/init-project.test.sh
# Run from plugin root: cd plugins/autopilot && bash test/init-project.test.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SCRIPT="$PLUGIN_ROOT/scripts/bash/init-project.sh"

# Create isolated temp directory for all tests
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# ============================================================================
# Test Framework
# ============================================================================

log_test() {
    echo -e "${YELLOW}TEST:${NC} $1"
}

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}PASS${NC}: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "  ${RED}FAIL${NC}: $1"
    if [ -n "$2" ]; then
        echo -e "        Expected: $2"
    fi
    if [ -n "$3" ]; then
        echo -e "        Got:      $3"
    fi
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$actual" = "$expected" ]; then
        pass "$msg"
    else
        fail "$msg" "$expected" "$actual"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -qF -- "$needle"; then
        pass "$msg"
    else
        fail "$msg" "contains '$needle'" "'$haystack'"
    fi
}

assert_file_exists() {
    local path="$1"
    local msg="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -e "$path" ]; then
        pass "$msg"
    else
        fail "$msg" "file exists" "file not found: $path"
    fi
}

assert_dir_exists() {
    local path="$1"
    local msg="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -d "$path" ]; then
        pass "$msg"
    else
        fail "$msg" "directory exists" "directory not found: $path"
    fi
}



assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$file" ] && grep -q "$pattern" "$file"; then
        pass "$msg"
    else
        fail "$msg" "file contains '$pattern'" "pattern not found in $file"
    fi
}

assert_valid_json() {
    local json="$1"
    local msg="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$json" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        pass "$msg"
    elif command -v jq >/dev/null 2>&1 && echo "$json" | jq . >/dev/null 2>&1; then
        pass "$msg"
    else
        fail "$msg" "valid JSON" "invalid JSON: $json"
    fi
}

json_get() {
    local json="$1"
    local key="$2"
    if command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -r "$key"
    else
        # Fallback: use python
        echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(eval('d$key'.replace('.', \"['\").replace('[', \"['\").replace(']', \"']\")))"
    fi
}

# Create a fresh test project directory
new_test_project() {
    local name="$1"
    local dir="$TEST_TMPDIR/$name"
    rm -rf "$dir"
    mkdir -p "$dir"
    echo "$dir"
}

# Run init-project.sh in a directory
run_init() {
    local dir="$1"
    shift
    (cd "$dir" && bash "$INIT_SCRIPT" "$@")
}

# ============================================================================
# Test Cases
# ============================================================================

test_fresh_creates_directories() {
    log_test "Fresh initialization creates all required directories"

    local proj
    proj=$(new_test_project "fresh_dirs")

    run_init "$proj" >/dev/null

    assert_dir_exists "$proj/.autopilot" ".autopilot directory created"
    assert_dir_exists "$proj/.autopilot/templates" ".autopilot/templates directory created"
    assert_dir_exists "$proj/specs" "specs directory created"
}

test_fresh_creates_claude_md() {
    log_test "Fresh initialization creates CLAUDE.md with correct content"

    local proj
    proj=$(new_test_project "fresh_claude")

    run_init "$proj" >/dev/null

    assert_file_exists "$proj/CLAUDE.md" "CLAUDE.md created"
    assert_file_contains "$proj/CLAUDE.md" "# Project Guidelines" "CLAUDE.md has header"
    assert_file_contains "$proj/CLAUDE.md" "## Principles" "CLAUDE.md has Principles section"
    assert_file_contains "$proj/CLAUDE.md" "## Commands" "CLAUDE.md has Commands section"
    assert_file_contains "$proj/CLAUDE.md" "## Code Style" "CLAUDE.md has Code Style section"
    assert_file_contains "$proj/CLAUDE.md" "## Active Context" "CLAUDE.md has Active Context section"
    assert_file_contains "$proj/CLAUDE.md" ".autopilot/context.md" "CLAUDE.md references context.md"
}


test_fresh_creates_context_md() {
    log_test "Fresh initialization creates .autopilot/context.md"

    local proj
    proj=$(new_test_project "fresh_context")

    run_init "$proj" >/dev/null

    assert_file_exists "$proj/.autopilot/context.md" ".autopilot/context.md created"
    assert_file_contains "$proj/.autopilot/context.md" "# Active Context" "context.md has header"
    assert_file_contains "$proj/.autopilot/context.md" "Auto-generated from feature plans" "context.md has auto-generated note"
    assert_file_contains "$proj/.autopilot/context.md" "## Active Technologies" "context.md has Technologies section"
    assert_file_contains "$proj/.autopilot/context.md" "## Recent Changes" "context.md has Recent Changes section"

    # Check date format (YYYY-MM-DD)
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qE "Last updated: [0-9]{4}-[0-9]{2}-[0-9]{2}" "$proj/.autopilot/context.md"; then
        pass "context.md has valid date format"
    else
        fail "context.md has valid date format" "YYYY-MM-DD date" "no valid date found"
    fi
}

test_rerun_without_force_returns_exists() {
    log_test "Re-running without --force returns 'exists' status"

    local proj
    proj=$(new_test_project "rerun_no_force")

    # First run
    run_init "$proj" >/dev/null

    # Second run (should return exists)
    local output
    output=$(run_init "$proj")

    assert_valid_json "$output" "output is valid JSON"

    local status
    status=$(json_get "$output" ".status")
    assert_eq "$status" "exists" "status is 'exists'"

    assert_contains "$output" "already exists" "message mentions already exists"
    assert_contains "$output" "--force" "message mentions --force option"
}

test_rerun_with_force_reinitializes() {
    log_test "Re-running with --force reinitializes correctly"

    local proj
    proj=$(new_test_project "rerun_force")

    # First run
    run_init "$proj" >/dev/null

    # Modify context.md to verify it gets recreated
    echo "MODIFIED" >> "$proj/.autopilot/context.md"


    # Second run with --force
    local output
    output=$(run_init "$proj" --force)

    assert_valid_json "$output" "output is valid JSON"

    local status
    status=$(json_get "$output" ".status")
    assert_eq "$status" "success" "status is 'success' after --force"

    local already_existed
    already_existed=$(json_get "$output" ".already_existed")
    assert_eq "$already_existed" "true" "already_existed is true"

    # Symlink should be recreated

    # context.md should still exist (not recreated because file exists)
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q "MODIFIED" "$proj/.autopilot/context.md"; then
        pass "context.md not overwritten (file existed)"
    else
        fail "context.md not overwritten" "MODIFIED marker present" "marker not found"
    fi
}

test_existing_claude_md_not_overwritten() {
    log_test "Existing CLAUDE.md is NOT overwritten"

    local proj
    proj=$(new_test_project "existing_claude")

    # Create existing CLAUDE.md with custom content AND context link (so it's skipped)
    mkdir -p "$proj"
    cat > "$proj/CLAUDE.md" <<'EOF'
# My Custom Project

This is my custom CLAUDE.md that should not be touched.

## My Custom Section

Important project-specific content here.

## Active Context

See [.autopilot/context.md](.autopilot/context.md) for current tech stack and recent changes.
EOF

    # Run init
    local output
    output=$(run_init "$proj")

    assert_valid_json "$output" "output is valid JSON"

    # Verify custom content preserved
    assert_file_contains "$proj/CLAUDE.md" "# My Custom Project" "custom header preserved"
    assert_file_contains "$proj/CLAUDE.md" "My Custom Section" "custom section preserved"

    # Should NOT contain default template content
    TESTS_RUN=$((TESTS_RUN + 1))
    if ! grep -q "# Project Guidelines" "$proj/CLAUDE.md"; then
        pass "default template content not injected"
    else
        fail "default template content not injected" "no '# Project Guidelines'" "found default content"
    fi

    # Check CLAUDE.md is in skipped list (has context link, so no update needed)
    assert_contains "$output" "CLAUDE.md" "CLAUDE.md mentioned in output"

    local skipped
    skipped=$(json_get "$output" ".skipped")
    assert_contains "$skipped" "CLAUDE.md" "CLAUDE.md in skipped array"
}

test_existing_claude_md_not_overwritten_with_force() {
    log_test "Existing CLAUDE.md is NOT overwritten even with --force"

    local proj
    proj=$(new_test_project "existing_claude_force")

    # Create existing CLAUDE.md with context link (so it's truly skipped)
    mkdir -p "$proj"
    cat > "$proj/CLAUDE.md" <<'EOF'
# DO NOT TOUCH THIS

See [.autopilot/context.md](.autopilot/context.md) for context.
EOF

    # Run init with --force
    run_init "$proj" --force >/dev/null

    # Verify original content preserved (first line should still be the header)
    TESTS_RUN=$((TESTS_RUN + 1))
    local first_line
    first_line=$(head -1 "$proj/CLAUDE.md")
    if [ "$first_line" = "# DO NOT TOUCH THIS" ]; then
        pass "CLAUDE.md content unchanged after --force"
    else
        fail "CLAUDE.md content unchanged after --force" "# DO NOT TOUCH THIS" "$first_line"
    fi
}

test_json_output_valid_fresh() {
    log_test "JSON output is valid on fresh initialization"

    local proj
    proj=$(new_test_project "json_fresh")

    local output
    output=$(run_init "$proj")

    assert_valid_json "$output" "output is valid JSON"

    # Check required fields
    local status
    status=$(json_get "$output" ".status")
    assert_eq "$status" "success" "status field is 'success'"

    local already_existed
    already_existed=$(json_get "$output" ".already_existed")
    assert_eq "$already_existed" "false" "already_existed is false on fresh init"

    # Check directories object
    assert_contains "$output" '"autopilot"' "directories.autopilot present"
    assert_contains "$output" '"templates"' "directories.templates present"
    assert_contains "$output" '"specs"' "directories.specs present"

    # Check created array contains expected items
    local created
    created=$(json_get "$output" ".created")
    assert_contains "$created" "CLAUDE.md" "CLAUDE.md in created array"
    assert_contains "$created" "context.md" "context.md in created array"
}

test_json_output_valid_exists() {
    log_test "JSON output is valid when returning 'exists' status"

    local proj
    proj=$(new_test_project "json_exists")

    # First run
    run_init "$proj" >/dev/null

    # Second run
    local output
    output=$(run_init "$proj")

    assert_valid_json "$output" "output is valid JSON"

    local status
    status=$(json_get "$output" ".status")
    assert_eq "$status" "exists" "status is 'exists'"

    assert_contains "$output" '"message"' "message field present"
    assert_contains "$output" '"autopilot_dir"' "autopilot_dir field present"
}

test_templates_copied_from_speckit() {
    log_test "Templates are copied from spec-kit if available"

    local proj
    proj=$(new_test_project "templates")

    local output
    output=$(run_init "$proj")

    # Check if spec-kit templates exist
    if [ -d "$PLUGIN_ROOT/vendor/spec-kit/templates" ]; then
        # Should have copied templates
        for tmpl in spec-template.md plan-template.md tasks-template.md checklist-template.md; do
            if [ -f "$PLUGIN_ROOT/vendor/spec-kit/templates/$tmpl" ]; then
                assert_file_exists "$proj/.autopilot/templates/$tmpl" "$tmpl copied from spec-kit"
            fi
        done

        # Verify created array mentions templates
        local created
        created=$(json_get "$output" ".created")
        assert_contains "$created" "templates/" "templates mentioned in created array"
    else
        # spec-kit not present, just verify no crash
        TESTS_RUN=$((TESTS_RUN + 1))
        pass "gracefully handles missing spec-kit templates"
    fi
}

test_templates_not_overwritten_without_force() {
    log_test "Existing templates are not overwritten without --force"

    local proj
    proj=$(new_test_project "templates_no_force")

    # First init
    run_init "$proj" >/dev/null

    # Modify a template
    if [ -f "$proj/.autopilot/templates/spec-template.md" ]; then
        echo "CUSTOM MODIFICATION" >> "$proj/.autopilot/templates/spec-template.md"
    else
        # Create a custom template
        mkdir -p "$proj/.autopilot/templates"
        echo "MY CUSTOM TEMPLATE" > "$proj/.autopilot/templates/spec-template.md"
    fi

    # Run init again with --force (but templates should be skipped if file exists)
    # Actually looking at the code, templates ARE overwritten with --force
    # Let's test the non-force case
    run_init "$proj" >/dev/null  # This will exit early with "exists"

    # Since it exits early, templates won't be touched
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$proj/.autopilot/templates/spec-template.md" ]; then
        if grep -q "CUSTOM\|MY CUSTOM" "$proj/.autopilot/templates/spec-template.md"; then
            pass "template modifications preserved when rerun exits early"
        else
            fail "template modifications preserved" "custom content" "content changed"
        fi
    else
        pass "template handling without spec-kit (no templates to check)"
    fi
}



test_context_md_has_current_date() {
    log_test "context.md contains current date"

    local proj
    proj=$(new_test_project "context_date")

    run_init "$proj" >/dev/null

    local today
    today=$(date +%Y-%m-%d)

    assert_file_contains "$proj/.autopilot/context.md" "$today" "context.md has today's date"
}

test_context_link_added_to_existing_claude_md() {
    log_test "Context link is added to existing CLAUDE.md without it"

    local proj
    proj=$(new_test_project "context_link")

    # Create existing CLAUDE.md WITHOUT context link
    mkdir -p "$proj"
    cat > "$proj/CLAUDE.md" <<'EOF'
# My Project

## Commands

```bash
yarn test
```
EOF

    local output
    output=$(run_init "$proj")

    # CLAUDE.md should be in created (updated with context link)
    local created
    created=$(json_get "$output" ".created")
    assert_contains "$created" "CLAUDE.md" "CLAUDE.md in created array (updated)"

    # Original content should be preserved
    assert_file_contains "$proj/CLAUDE.md" "# My Project" "original header preserved"
    assert_file_contains "$proj/CLAUDE.md" "yarn test" "original content preserved"

    # Context link should be added
    assert_file_contains "$proj/CLAUDE.md" ".autopilot/context.md" "context link added"
}

test_created_skipped_arrays() {
    log_test "Created and skipped arrays are correct"

    local proj
    proj=$(new_test_project "arrays")

    # Create existing CLAUDE.md with context link (so it's skipped)
    mkdir -p "$proj"
    cat > "$proj/CLAUDE.md" <<'EOF'
# Existing

See [.autopilot/context.md](.autopilot/context.md) for context.
EOF

    local output
    output=$(run_init "$proj")

    # CLAUDE.md should be in skipped (has context link, no update needed)
    local skipped
    skipped=$(json_get "$output" ".skipped")
    assert_contains "$skipped" "CLAUDE.md" "CLAUDE.md in skipped array"

    # context.md should be in created
    local created
    created=$(json_get "$output" ".created")
    assert_contains "$created" "context.md" "context.md in created array"
}

test_empty_arrays_valid_json() {
    log_test "Empty arrays produce valid JSON"

    local proj
    proj=$(new_test_project "empty_arrays")

    # Create all files beforehand (with context link so CLAUDE.md is skipped)
    mkdir -p "$proj/.autopilot/templates"
    mkdir -p "$proj/specs"
    cat > "$proj/CLAUDE.md" <<'EOF'
# Existing

See [.autopilot/context.md](.autopilot/context.md) for context.
EOF
    echo "# Context" > "$proj/.autopilot/context.md"

    # Now init with --force - should have things in skipped
    local output
    output=$(run_init "$proj" --force)

    assert_valid_json "$output" "output is valid JSON with potentially empty arrays"
}

test_idempotent_multiple_force_runs() {
    log_test "Multiple --force runs are idempotent"

    local proj
    proj=$(new_test_project "idempotent")

    # Run multiple times with --force
    run_init "$proj" --force >/dev/null
    run_init "$proj" --force >/dev/null
    local output
    output=$(run_init "$proj" --force)

    assert_valid_json "$output" "output valid after multiple runs"

    local status
    status=$(json_get "$output" ".status")
    assert_eq "$status" "success" "status is success after multiple runs"

    # All structures should exist
    assert_dir_exists "$proj/.autopilot" ".autopilot exists"
    assert_dir_exists "$proj/.autopilot/templates" "templates exists"
    assert_dir_exists "$proj/specs" "specs exists"
    assert_file_exists "$proj/CLAUDE.md" "CLAUDE.md exists"
    assert_file_exists "$proj/.autopilot/context.md" "context.md exists"
}

# ============================================================================
# Run All Tests
# ============================================================================

main() {
    echo "============================================================"
    echo "init-project.sh Test Suite"
    echo "============================================================"
    echo ""
    echo "Script under test: $INIT_SCRIPT"
    echo "Temp directory: $TEST_TMPDIR"
    echo ""

    # Verify script exists
    if [ ! -f "$INIT_SCRIPT" ]; then
        echo -e "${RED}ERROR: init-project.sh not found at $INIT_SCRIPT${NC}"
        exit 1
    fi

    # Run all tests
    test_fresh_creates_directories
    echo ""

    test_fresh_creates_claude_md
    echo ""

    echo ""

    test_fresh_creates_context_md
    echo ""

    test_rerun_without_force_returns_exists
    echo ""

    test_rerun_with_force_reinitializes
    echo ""

    test_existing_claude_md_not_overwritten
    echo ""

    test_existing_claude_md_not_overwritten_with_force
    echo ""

    test_json_output_valid_fresh
    echo ""

    test_json_output_valid_exists
    echo ""

    test_templates_copied_from_speckit
    echo ""

    test_templates_not_overwritten_without_force
    echo ""

    echo ""

    echo ""

    test_context_md_has_current_date
    echo ""

    test_context_link_added_to_existing_claude_md
    echo ""

    test_created_skipped_arrays
    echo ""

    test_empty_arrays_valid_json
    echo ""

    test_idempotent_multiple_force_runs
    echo ""

    # Summary
    echo "============================================================"
    echo "Test Summary"
    echo "============================================================"
    echo -e "Total:  $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}SOME TESTS FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}ALL TESTS PASSED${NC}"
        exit 0
    fi
}

main "$@"
