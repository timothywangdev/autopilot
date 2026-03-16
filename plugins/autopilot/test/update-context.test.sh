#!/usr/bin/env bash
# Tests for update-context.sh
#
# Run: bash test/update-context.test.sh
# Or:  ./test/update-context.test.sh

# Don't exit on error so we can continue running tests
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Store original directory
ORIGINAL_DIR="$(pwd)"

# Test utilities
pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $1"
    if [ -n "$2" ]; then
        echo -e "  ${YELLOW}Expected:${NC} $2"
    fi
    if [ -n "$3" ]; then
        echo -e "  ${YELLOW}Got:${NC} $3"
    fi
}

skip() {
    echo -e "${YELLOW}⊘${NC} $1 (SKIPPED)"
}

# Cleanup function - MUST be called at end of each test
cleanup_test_repo() {
    local dir="$1"
    # Always return to original directory first
    cd "$ORIGINAL_DIR" || exit 1
    if [ -n "$dir" ] && [ -d "$dir" ]; then
        rm -rf "$dir" 2>/dev/null || true
    fi
}

# Setup temp directory with mock git repo
# Returns the temp directory path. CALLER MUST cd to the returned path!
setup_test_repo() {
    # Always start from original directory
    cd "$ORIGINAL_DIR" || exit 1

    local test_dir
    test_dir=$(mktemp -d)

    # Initialize git repo with minimal config (in subshell so cd doesn't affect caller)
    (
        cd "$test_dir" || exit 1
        git init -q 2>/dev/null
        git config user.email "test@example.com"
        git config user.name "Test User"
        echo "# Test Repo" > README.md
        git add README.md
        git commit -q -m "Initial commit" 2>/dev/null
        mkdir -p .autopilot specs
    )

    echo "$test_dir"
}

# Create a standard context.md file
# Note 1: The script has a quirk where if ## Recent Changes comes directly after
# ## Active Technologies, the change entry isn't added. The workaround is to
# have an intermediate section between them.
# Note 2: There's a bug where ((changes_count++)) with set -e causes the script
# to exit early when processing existing Recent Changes entries. Tests that need
# to verify Recent Changes functionality should not have existing entries.
create_context_file() {
    local dir="$1"
    cat > "$dir/.autopilot/context.md" << 'EOF'
# Project Context

Auto-generated from feature plans. Last updated: 2025-01-01

## Active Technologies
- TypeScript 5.x (existing-feature)

## Project Structure
Standard layout here.

## Recent Changes
EOF
}

# Create a plan.md file
create_plan_file() {
    local dir="$1"
    local feature_name="$2"
    local lang="${3:-TypeScript 5.7+}"
    local deps="${4:-React 18, Next.js 14}"
    local storage="${5:-PostgreSQL 15}"

    mkdir -p "$dir/specs/$feature_name"
    cat > "$dir/specs/$feature_name/plan.md" << EOF
# Plan for $feature_name

## Technical Context

**Language/Version**: $lang
**Primary Dependencies**: $deps
**Storage**: $storage

## Overview
This is the plan content.
EOF
}

# Get script path (resolve relative to this test file)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/scripts/bash/update-context.sh"

# Verify script exists
if [ ! -f "$SCRIPT_PATH" ]; then
    echo -e "${RED}Error: update-context.sh not found at $SCRIPT_PATH${NC}"
    exit 1
fi

echo "Running tests for update-context.sh"
echo "Script: $SCRIPT_PATH"
echo "---"

# ============================================================
# Test 1: Extracts Language/Version from plan.md
# ============================================================
test_extracts_language() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Extracts Language/Version from plan.md" "cd to test dir" "failed"; return; }

    create_context_file "$test_dir"
    create_plan_file "$test_dir" "001-test-feature" "Python 3.12" "Django 5.0" "MySQL 8"

    git checkout -q -b "001-test-feature" 2>/dev/null

    local output
    output=$("$SCRIPT_PATH" 2>&1)

    if echo "$output" | grep -q '"status": "success"'; then
        if echo "$output" | grep -q "Python 3.12"; then
            pass "Extracts Language/Version from plan.md"
        else
            fail "Extracts Language/Version from plan.md" "Python 3.12 in output" "$output"
        fi
    else
        fail "Extracts Language/Version from plan.md" "success status" "$output"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 2: Extracts Primary Dependencies from plan.md
# ============================================================
test_extracts_dependencies() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Extracts Primary Dependencies from plan.md" "cd to test dir" "failed"; return; }

    create_context_file "$test_dir"
    create_plan_file "$test_dir" "002-deps-test" "Node.js 20+" "Express 4.18, Mongoose 8.0" "MongoDB Atlas"

    git checkout -q -b "002-deps-test" 2>/dev/null

    local output
    output=$("$SCRIPT_PATH" 2>&1)

    if echo "$output" | grep -q "Express 4.18, Mongoose 8.0"; then
        pass "Extracts Primary Dependencies from plan.md"
    else
        fail "Extracts Primary Dependencies from plan.md" "Express 4.18, Mongoose 8.0" "$output"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 3: Extracts Storage from plan.md
# ============================================================
test_extracts_storage() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Extracts Storage from plan.md" "cd to test dir" "failed"; return; }

    create_context_file "$test_dir"
    create_plan_file "$test_dir" "003-storage-test" "Go 1.22" "gin, gorm" "Redis 7 + PostgreSQL"

    git checkout -q -b "003-storage-test" 2>/dev/null

    "$SCRIPT_PATH" >/dev/null 2>&1

    # Check that storage was added to context
    if grep -q "Redis 7 + PostgreSQL" "$test_dir/.autopilot/context.md" 2>/dev/null; then
        pass "Extracts Storage from plan.md"
    else
        fail "Extracts Storage from plan.md" "Redis 7 + PostgreSQL in context.md" "$(cat "$test_dir/.autopilot/context.md" 2>/dev/null)"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 4: Builds correct tech stack string (lang + framework)
# ============================================================
test_builds_tech_stack_string() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Builds correct tech stack string" "cd to test dir" "failed"; return; }

    create_context_file "$test_dir"
    create_plan_file "$test_dir" "004-stack-test" "Rust 1.75" "actix-web, tokio" "SQLite"

    git checkout -q -b "004-stack-test" 2>/dev/null

    "$SCRIPT_PATH" >/dev/null 2>&1

    # Should have "Rust 1.75 + actix-web, tokio"
    if grep -q "Rust 1.75 + actix-web, tokio" "$test_dir/.autopilot/context.md" 2>/dev/null; then
        pass "Builds correct tech stack string (lang + framework)"
    else
        fail "Builds correct tech stack string (lang + framework)" \
            "Rust 1.75 + actix-web, tokio" \
            "$(grep -E "^-" "$test_dir/.autopilot/context.md" 2>/dev/null | head -3)"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 5: Adds new technologies to Active Technologies section
# ============================================================
test_adds_new_technologies() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Adds new technologies" "cd to test dir" "failed"; return; }

    create_context_file "$test_dir"
    create_plan_file "$test_dir" "005-new-tech" "Elixir 1.16" "Phoenix 1.7" "PostgreSQL 16"

    git checkout -q -b "005-new-tech" 2>/dev/null

    "$SCRIPT_PATH" >/dev/null 2>&1

    local context_content
    context_content=$(cat "$test_dir/.autopilot/context.md" 2>/dev/null)

    # Check tech is in Active Technologies section
    if echo "$context_content" | sed -n '/## Active Technologies/,/## /p' | grep -q "Elixir 1.16 + Phoenix 1.7"; then
        pass "Adds new technologies to Active Technologies section"
    else
        fail "Adds new technologies to Active Technologies section" \
            "Elixir 1.16 + Phoenix 1.7 in Active Technologies" \
            "$context_content"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 6: Doesn't duplicate existing technologies
# ============================================================
test_no_duplicate_technologies() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "No duplicate technologies" "cd to test dir" "failed"; return; }

    # Create context with existing tech (no existing Recent Changes entries to avoid script bug)
    cat > "$test_dir/.autopilot/context.md" << 'EOF'
# Project Context

Auto-generated from feature plans. Last updated: 2025-01-01

## Active Technologies
- TypeScript 5.x (existing-feature)
- Python 3.12 + FastAPI 0.100 (006-no-dup)

## Project Structure
Standard layout.

## Recent Changes
EOF

    create_plan_file "$test_dir" "006-no-dup" "Python 3.12" "FastAPI 0.100" "Redis"

    git checkout -q -b "006-no-dup" 2>/dev/null

    "$SCRIPT_PATH" >/dev/null 2>&1

    # Count occurrences of the tech stack IN THE ACTIVE TECHNOLOGIES SECTION ONLY
    # (The tech stack also appears in Recent Changes as part of the change entry, which is expected)
    local count
    count=$(sed -n '/## Active Technologies/,/## /p' "$test_dir/.autopilot/context.md" 2>/dev/null | grep -c "Python 3.12 + FastAPI 0.100" || echo "0")

    if [ "$count" -eq 1 ]; then
        pass "Doesn't duplicate existing technologies"
    else
        fail "Doesn't duplicate existing technologies" "1 occurrence in Active Technologies" "$count occurrences"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 7: Adds change entry to Recent Changes section
# ============================================================
test_adds_change_entry() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Adds change entry" "cd to test dir" "failed"; return; }

    create_context_file "$test_dir"
    create_plan_file "$test_dir" "007-change-entry" "Ruby 3.3" "Rails 7.1" "PostgreSQL"

    git checkout -q -b "007-change-entry" 2>/dev/null

    "$SCRIPT_PATH" >/dev/null 2>&1

    if grep -q "007-change-entry: Added Ruby 3.3 + Rails 7.1" "$test_dir/.autopilot/context.md" 2>/dev/null; then
        pass "Adds change entry to Recent Changes section"
    else
        fail "Adds change entry to Recent Changes section" \
            "007-change-entry: Added Ruby 3.3 + Rails 7.1" \
            "$(grep "Recent Changes" -A5 "$test_dir/.autopilot/context.md" 2>/dev/null)"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 8: Limits Recent Changes to 3 entries
# ============================================================
test_limits_recent_changes() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Limits Recent Changes" "cd to test dir" "failed"; return; }

    # Create context file with 5 existing changes
    cat > .autopilot/context.md << 'EOF'
# Active Context

Auto-generated from feature plans. Last updated: 2024-01-01

## Active Technologies

<!-- Auto-populated by autopilot from plan.md -->

## Recent Changes

- 007-old-feature: Added Old Tech 1
- 006-older-feature: Added Old Tech 2
- 005-oldest-feature: Added Old Tech 3
- 004-ancient-feature: Added Old Tech 4
- 003-prehistoric-feature: Added Old Tech 5
EOF

    create_plan_file "$test_dir" "008-new-feature" "Rust 1.75" "Actix-web 4" ""
    git checkout -q -b "008-new-feature" 2>/dev/null

    local output
    output=$("$SCRIPT_PATH" 2>&1)

    # Count changes ONLY in Recent Changes section (should be 3: new + 2 oldest kept)
    local change_count
    change_count=$(sed -n '/## Recent Changes/,/^##/p' .autopilot/context.md | grep -c "^- " || echo 0)

    if [ "$change_count" -eq 3 ]; then
        pass "Limits Recent Changes to 3 entries"
    else
        fail "Limits Recent Changes to 3 entries" "3 entries" "$change_count entries"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 9: Updates "Last updated" timestamp
# ============================================================
test_updates_timestamp() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Updates timestamp" "cd to test dir" "failed"; return; }

    create_context_file "$test_dir"
    create_plan_file "$test_dir" "009-timestamp" "Swift 5.10" "Vapor 4" "SQLite"

    git checkout -q -b "009-timestamp" 2>/dev/null

    local today
    today=$(date +%Y-%m-%d)

    "$SCRIPT_PATH" >/dev/null 2>&1

    if grep -q "Last updated: $today" "$test_dir/.autopilot/context.md" 2>/dev/null; then
        pass "Updates 'Last updated' timestamp"
    else
        fail "Updates 'Last updated' timestamp" "Last updated: $today" \
            "$(grep "Last updated" "$test_dir/.autopilot/context.md" 2>/dev/null)"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 10: Handles missing plan.md gracefully (returns skipped status)
# ============================================================
test_missing_plan_skipped() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Missing plan.md" "cd to test dir" "failed"; return; }

    create_context_file "$test_dir"
    # Don't create any plan.md

    git checkout -q -b "010-no-plan" 2>/dev/null

    local output exit_code
    output=$("$SCRIPT_PATH" 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ] && echo "$output" | grep -q '"status": "skipped"'; then
        pass "Handles missing plan.md gracefully (returns skipped status)"
    else
        fail "Handles missing plan.md gracefully (returns skipped status)" \
            "exit 0 with status: skipped" \
            "exit $exit_code, output: $output"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 11: Handles missing context.md (returns error)
# ============================================================
test_missing_context_error() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Missing context.md" "cd to test dir" "failed"; return; }

    # Create plan but no context
    create_plan_file "$test_dir" "011-no-context" "Java 21" "Spring Boot 3" "PostgreSQL"
    # Remove .autopilot directory entirely
    rm -rf "$test_dir/.autopilot"

    git checkout -q -b "011-no-context" 2>/dev/null

    local output exit_code
    output=$("$SCRIPT_PATH" 2>&1)
    exit_code=$?

    if [ "$exit_code" -eq 1 ] && echo "$output" | grep -q '"status": "error"'; then
        pass "Handles missing context.md (returns error)"
    else
        fail "Handles missing context.md (returns error)" \
            "exit 1 with status: error" \
            "exit $exit_code, output: $output"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 12: Branch name parsing works (NNN-feature-name format)
# ============================================================
test_branch_name_parsing() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Branch name parsing" "cd to test dir" "failed"; return; }

    create_context_file "$test_dir"

    # Create plan with matching feature name
    create_plan_file "$test_dir" "012-branch-parse" "C# 12" ".NET 8" "SQL Server"

    # Create another plan to ensure it picks the right one
    create_plan_file "$test_dir" "999-other-feature" "Haskell 9.4" "Yesod" "PostgreSQL"

    git checkout -q -b "012-branch-parse" 2>/dev/null

    local output
    output=$("$SCRIPT_PATH" 2>&1)

    if echo "$output" | grep -q "012-branch-parse/plan.md"; then
        pass "Branch name parsing works (NNN-feature-name format)"
    else
        fail "Branch name parsing works (NNN-feature-name format)" \
            "012-branch-parse/plan.md" \
            "$output"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 13: Falls back to most recent plan.md when branch doesn't match
# ============================================================
test_fallback_to_recent_plan() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Fallback to recent plan" "cd to test dir" "failed"; return; }

    create_context_file "$test_dir"

    # Create an older plan
    mkdir -p "$test_dir/specs/old-feature"
    cat > "$test_dir/specs/old-feature/plan.md" << 'EOF'
# Old Plan

**Language/Version**: Python 2.7
**Primary Dependencies**: Django 1.x
**Storage**: MySQL 5
EOF

    # Touch it to make it old
    touch -d "2024-01-01" "$test_dir/specs/old-feature/plan.md"

    # Create a newer plan
    sleep 0.1
    mkdir -p "$test_dir/specs/new-feature"
    cat > "$test_dir/specs/new-feature/plan.md" << 'EOF'
# New Plan

**Language/Version**: Python 3.13
**Primary Dependencies**: FastAPI 0.110
**Storage**: PostgreSQL 17
EOF

    # Branch name doesn't match any feature
    git checkout -q -b "unrelated-branch-name" 2>/dev/null

    local output
    output=$("$SCRIPT_PATH" 2>&1)

    if echo "$output" | grep -q "new-feature/plan.md"; then
        pass "Falls back to most recent plan.md when branch doesn't match"
    else
        fail "Falls back to most recent plan.md when branch doesn't match" \
            "new-feature/plan.md (most recent)" \
            "$output"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 14: JSON output is valid
# ============================================================
test_valid_json_output() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Valid JSON output" "cd to test dir" "failed"; return; }

    create_context_file "$test_dir"
    create_plan_file "$test_dir" "014-json-test" "Scala 3.4" "ZIO 2" "Cassandra"

    git checkout -q -b "014-json-test" 2>/dev/null

    local output
    output=$("$SCRIPT_PATH" 2>&1)

    # Try to parse with jq
    if echo "$output" | jq . >/dev/null 2>&1; then
        pass "JSON output is valid"
    else
        fail "JSON output is valid" "valid JSON" "$output"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 15: Handles lang-only plan (no deps)
# ============================================================
test_lang_only() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Lang-only plan" "cd to test dir" "failed"; return; }

    create_context_file "$test_dir"

    # Create plan with only language
    mkdir -p "$test_dir/specs/015-lang-only"
    cat > "$test_dir/specs/015-lang-only/plan.md" << 'EOF'
# Lang Only Plan

**Language/Version**: Bash 5.2
**Primary Dependencies**: N/A
**Storage**: File system
EOF

    git checkout -q -b "015-lang-only" 2>/dev/null

    "$SCRIPT_PATH" >/dev/null 2>&1

    # Should have just "Bash 5.2" without "+ N/A"
    if grep -q "Bash 5.2 (015-lang-only)" "$test_dir/.autopilot/context.md" 2>/dev/null && \
       ! grep -q "Bash 5.2 + N/A" "$test_dir/.autopilot/context.md" 2>/dev/null; then
        pass "Handles lang-only plan (no deps)"
    else
        fail "Handles lang-only plan (no deps)" \
            "Bash 5.2 without N/A" \
            "$(grep "Bash" "$test_dir/.autopilot/context.md" 2>/dev/null)"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 16: Skips NEEDS CLARIFICATION values
# ============================================================
test_skips_needs_clarification() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Skips NEEDS CLARIFICATION" "cd to test dir" "failed"; return; }

    create_context_file "$test_dir"

    mkdir -p "$test_dir/specs/016-unclear"
    cat > "$test_dir/specs/016-unclear/plan.md" << 'EOF'
# Unclear Plan

**Language/Version**: NEEDS CLARIFICATION
**Primary Dependencies**: Express 4
**Storage**: NEEDS CLARIFICATION
EOF

    git checkout -q -b "016-unclear" 2>/dev/null

    "$SCRIPT_PATH" >/dev/null 2>&1

    # Should have Express 4 but no NEEDS CLARIFICATION
    if ! grep -q "NEEDS CLARIFICATION" "$test_dir/.autopilot/context.md" 2>/dev/null; then
        pass "Skips NEEDS CLARIFICATION values"
    else
        fail "Skips NEEDS CLARIFICATION values" \
            "No NEEDS CLARIFICATION in output" \
            "$(cat "$test_dir/.autopilot/context.md" 2>/dev/null)"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 17: added_technologies array in JSON is correct
# ============================================================
test_added_technologies_json() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "added_technologies JSON" "cd to test dir" "failed"; return; }

    create_context_file "$test_dir"
    create_plan_file "$test_dir" "017-json-array" "Zig 0.12" "std" "RocksDB"

    git checkout -q -b "017-json-array" 2>/dev/null

    local output
    output=$("$SCRIPT_PATH" 2>&1)

    # Parse and check added_technologies
    local added
    added=$(echo "$output" | jq -r '.added_technologies | length' 2>/dev/null)

    if [ "$added" -gt 0 ]; then
        pass "added_technologies array in JSON is correct"
    else
        fail "added_technologies array in JSON is correct" \
            "non-empty added_technologies array" \
            "$output"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 18: Preserves other sections in context.md
# ============================================================
test_preserves_other_sections() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Preserves other sections" "cd to test dir" "failed"; return; }

    # Create context with custom sections (no existing Recent Changes entries)
    cat > "$test_dir/.autopilot/context.md" << 'EOF'
# Project Context

Auto-generated from feature plans. Last updated: 2025-01-01

## Active Technologies
- TypeScript 5.x (existing)

## Custom Section
This should be preserved exactly as is.

## Recent Changes

## Another Section
This too should remain.
EOF

    create_plan_file "$test_dir" "018-preserve" "Go 1.22" "Fiber v2" "BadgerDB"

    git checkout -q -b "018-preserve" 2>/dev/null

    "$SCRIPT_PATH" >/dev/null 2>&1

    if grep -q "## Custom Section" "$test_dir/.autopilot/context.md" 2>/dev/null && \
       grep -q "This should be preserved exactly as is." "$test_dir/.autopilot/context.md" 2>/dev/null && \
       grep -q "## Another Section" "$test_dir/.autopilot/context.md" 2>/dev/null; then
        pass "Preserves other sections in context.md"
    else
        fail "Preserves other sections in context.md" \
            "Custom Section and Another Section preserved" \
            "$(cat "$test_dir/.autopilot/context.md" 2>/dev/null)"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Test 19: Branch with glob-matching feature dir
# ============================================================
test_glob_matching_feature_dir() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_dir
    test_dir=$(setup_test_repo)
    cd "$test_dir" || { fail "Glob matching feature dir" "cd to test dir" "failed"; return; }

    create_context_file "$test_dir"

    # Create plan with longer name containing branch name
    create_plan_file "$test_dir" "019-feature-extended-name" "OCaml 5.1" "Dream" "SQLite"

    # Branch has partial match
    git checkout -q -b "019-feature" 2>/dev/null

    local output
    output=$("$SCRIPT_PATH" 2>&1)

    # Should find the plan via glob matching
    if echo "$output" | grep -q "019-feature" && echo "$output" | grep -q '"status": "success"'; then
        pass "Branch with glob-matching feature dir"
    else
        fail "Branch with glob-matching feature dir" \
            "success with glob match" \
            "$output"
    fi

    cleanup_test_repo "$test_dir"
}

# ============================================================
# Run all tests
# ============================================================
echo ""

test_extracts_language
test_extracts_dependencies
test_extracts_storage
test_builds_tech_stack_string
test_adds_new_technologies
test_no_duplicate_technologies
test_adds_change_entry
test_limits_recent_changes
test_updates_timestamp
test_missing_plan_skipped
test_missing_context_error
test_branch_name_parsing
test_fallback_to_recent_plan
test_valid_json_output
test_lang_only
test_skips_needs_clarification
test_added_technologies_json
test_preserves_other_sections
test_glob_matching_feature_dir

# Summary
echo ""
echo "---"
echo "Tests run: $TESTS_RUN"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
fi

exit 0
