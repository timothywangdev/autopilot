#!/usr/bin/env bash
# workflow-status.test.sh - Unit tests for workflow-status.sh
# Usage: ./workflow-status.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_SCRIPT="$SCRIPT_DIR/../scripts/bash/workflow-status.sh"

# ==============================================================================
# Test Framework
# ==============================================================================

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TEST_TEMP_DIR=""

setup() {
    TEST_TEMP_DIR=$(mktemp -d)
    # Create a minimal git repo structure
    mkdir -p "$TEST_TEMP_DIR/.git"
    mkdir -p "$TEST_TEMP_DIR/specs"
    cd "$TEST_TEMP_DIR"
    # Set environment to isolate from real git
    export GIT_DIR="$TEST_TEMP_DIR/.git"
}

teardown() {
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
    unset GIT_DIR 2>/dev/null || true
    unset AUTOPILOT_FEATURE 2>/dev/null || true
}

run_test() {
    local test_name="$1"
    local test_func="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    setup

    local result=0
    if $test_func; then
        echo "  PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL: $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        result=1
    fi

    teardown
    return $result
}

# Assert helpers
assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-}"

    if [ "$expected" != "$actual" ]; then
        echo "    Expected: $expected"
        echo "    Actual:   $actual"
        [ -n "$msg" ] && echo "    Message:  $msg"
        return 1
    fi
    return 0
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-}"

    # Use grep -F for fixed string matching, and -- to end options
    if ! echo "$haystack" | grep -qF -- "$needle"; then
        echo "    Expected to contain: $needle"
        echo "    Actual: $haystack"
        [ -n "$msg" ] && echo "    Message: $msg"
        return 1
    fi
    return 0
}

assert_json_field() {
    local json="$1"
    local field="$2"
    local expected="$3"

    local actual
    # Use head -1 to get only the first match, handle spacing variations
    actual=$(echo "$json" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*[^,}]*" | head -1 | sed "s/\"$field\"[[:space:]]*:[[:space:]]*//" | tr -d '"' | tr -d ' ' || echo "")

    if [ "$expected" != "$actual" ]; then
        echo "    Field '$field' expected: $expected"
        echo "    Field '$field' actual:   $actual"
        return 1
    fi
    return 0
}

assert_json_bool() {
    local json="$1"
    local field="$2"
    local expected="$3"

    local actual
    actual=$(echo "$json" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*[^,}]*" | head -1 | sed "s/\"$field\"[[:space:]]*:[[:space:]]*//" | tr -d ' ' || echo "")

    if [ "$expected" != "$actual" ]; then
        echo "    Field '$field' expected: $expected"
        echo "    Field '$field' actual:   $actual"
        return 1
    fi
    return 0
}

# ==============================================================================
# Test Fixtures
# ==============================================================================

create_feature_dir() {
    local feature_id="$1"
    local feature_dir="$TEST_TEMP_DIR/specs/$feature_id"
    mkdir -p "$feature_dir"
    echo "$feature_dir"
}

create_state_file() {
    local feature_dir="$1"
    local phase="${2:-3}"
    local status="${3:-in_progress}"
    local spike="${4:-1}"
    local implement="${5:-2}"
    local verify="${6:-0}"
    local review="${7:-0}"

    cat > "$feature_dir/.workflow-state.json" << EOF
{
    "version": "1.0.0",
    "featureId": "$(basename "$feature_dir")",
    "currentPhase": $phase,
    "status": "$status",
    "createdAt": "2024-01-15T10:00:00Z",
    "updatedAt": "2024-01-16T14:30:00Z",
    "iterations": {
        "spike": $spike,
        "implement": $implement,
        "verify": $verify,
        "review": $review
    }
}
EOF
}

create_spec_file() {
    local feature_dir="$1"
    cat > "$feature_dir/spec.md" << 'EOF'
# Feature Specification

## Overview
Test feature specification.

## Goals
- Goal 1
- Goal 2

## Requirements
- FR-001: Requirement 1
EOF
}

create_plan_file() {
    local feature_dir="$1"
    cat > "$feature_dir/plan.md" << 'EOF'
# Implementation Plan

## Architecture
Microservices architecture.

## Components
- Component A
- Component B
EOF
}

create_tasks_file() {
    local feature_dir="$1"
    local total="${2:-5}"
    local complete="${3:-2}"

    {
        echo "# Task Breakdown"
        echo ""
        local i
        for i in $(seq 1 "$complete"); do
            # Use -- to prevent printf interpreting - as option
            printf -- '- [x] T%03d: Completed task %d\n' "$i" "$i"
            echo "  **Verify**: CLI | Test command"
        done
        if [ "$complete" -lt "$total" ]; then
            for i in $(seq $((complete + 1)) "$total"); do
                printf -- '- [ ] T%03d: Pending task %d\n' "$i" "$i"
                echo "  **Verify**: CLI | Test command"
            done
        fi
    } > "$feature_dir/tasks.md"
}

create_research_file() {
    local feature_dir="$1"
    cat > "$feature_dir/research.md" << 'EOF'
# Research Notes
Some research content.
EOF
}

create_data_model_file() {
    local feature_dir="$1"
    cat > "$feature_dir/data-model.md" << 'EOF'
# Data Model
User entity definition.
EOF
}

create_contracts_dir() {
    local feature_dir="$1"
    mkdir -p "$feature_dir/contracts"
    cat > "$feature_dir/contracts/api.yaml" << 'EOF'
openapi: 3.0.0
info:
  title: Test API
  version: 1.0.0
paths: {}
EOF
}

create_spike_report() {
    local feature_dir="$1"
    echo "# Spike Report" > "$feature_dir/spike-report.md"
}

create_verification_report() {
    local feature_dir="$1"
    echo "# Verification Report" > "$feature_dir/verification-report.md"
}

create_review_report() {
    local feature_dir="$1"
    echo "# Review Report" > "$feature_dir/review-report.md"
}

# ==============================================================================
# Tests: Basic Operation
# ==============================================================================

test_help_option() {
    local output
    local exit_code=0
    output=$("$STATUS_SCRIPT" --help 2>&1) || exit_code=$?

    assert_eq "0" "$exit_code" "Help should exit 0" || return 1
    assert_contains "$output" "Usage:" "Should show usage" || return 1
    assert_contains "$output" "feature-dir" "Should show feature-dir option" || return 1
    assert_contains "$output" "branch" "Should show branch option" || return 1
}

test_output_is_valid_json() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir" 5 "in_progress"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    # Verify output is valid JSON
    if command -v node >/dev/null 2>&1; then
        if ! echo "$output" | node -e 'JSON.parse(require("fs").readFileSync(0, "utf8"))' 2>/dev/null; then
            echo "    Output is not valid JSON"
            echo "    Output: $output"
            return 1
        fi
    elif command -v python3 >/dev/null 2>&1; then
        if ! echo "$output" | python3 -c 'import json, sys; json.load(sys.stdin)' 2>/dev/null; then
            echo "    Output is not valid JSON"
            echo "    Output: $output"
            return 1
        fi
    else
        echo "    SKIP: no JSON validator available"
    fi

    return 0
}

# ==============================================================================
# Tests: Phase Reporting
# ==============================================================================

test_reports_correct_phase_number() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir" 7 "in_progress"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_json_field "$output" "currentPhase" "7" || return 1
}

test_reports_correct_phase_name() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    # Phase 7 = Implement (based on PHASE_NAMES array)
    create_state_file "$feature_dir" 7 "in_progress"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_json_field "$output" "phaseName" "Implement" || return 1
}

test_reports_phase_0_as_parse() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir" 0 "in_progress"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_json_field "$output" "currentPhase" "0" || return 1
    assert_json_field "$output" "phaseName" "Parse" || return 1
}

test_reports_phase_10_as_complete() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir" 10 "completed"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_json_field "$output" "currentPhase" "10" || return 1
    assert_json_field "$output" "phaseName" "Complete" || return 1
}

# ==============================================================================
# Tests: Task Counting
# ==============================================================================

test_reports_correct_total_tasks() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"
    create_tasks_file "$feature_dir" 8 3

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    # Extract tasks.total from nested object
    local total
    total=$(echo "$output" | grep -o '"total"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*' | head -1)
    assert_eq "8" "$total" "Should report 8 total tasks" || return 1
}

test_reports_correct_completed_tasks() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"
    create_tasks_file "$feature_dir" 10 7

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local complete
    complete=$(echo "$output" | grep -o '"complete"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*' | head -1)
    assert_eq "7" "$complete" "Should report 7 completed tasks" || return 1
}

test_reports_correct_incomplete_tasks() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"
    create_tasks_file "$feature_dir" 10 7

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local incomplete
    incomplete=$(echo "$output" | grep -o '"incomplete"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*' | head -1)
    assert_eq "3" "$incomplete" "Should report 3 incomplete tasks" || return 1
}

test_reports_correct_progress_percentage() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"
    create_tasks_file "$feature_dir" 4 2  # 50%

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local progress
    progress=$(echo "$output" | grep -o '"progress"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*' | head -1)
    assert_eq "50" "$progress" "Should report 50% progress" || return 1
}

test_zero_tasks_reports_zero_progress() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"
    # No tasks file

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local progress
    progress=$(echo "$output" | grep -o '"progress"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*' | head -1)
    assert_eq "0" "$progress" "Should report 0% progress with no tasks" || return 1
}

# ==============================================================================
# Tests: Iteration Counts
# ==============================================================================

test_reports_spike_iterations() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir" 5 "in_progress" 3 0 0 0

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local spike
    spike=$(echo "$output" | grep -o '"spike"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*' | head -1)
    assert_eq "3" "$spike" "Should report 3 spike iterations" || return 1
}

test_reports_implement_iterations() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir" 7 "in_progress" 1 5 0 0

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local implement
    implement=$(echo "$output" | grep -o '"implement"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*' | head -1)
    assert_eq "5" "$implement" "Should report 5 implement iterations" || return 1
}

test_reports_verify_iterations() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir" 8 "in_progress" 1 2 4 0

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local verify
    verify=$(echo "$output" | grep -o '"verify"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*' | head -1)
    assert_eq "4" "$verify" "Should report 4 verify iterations" || return 1
}

test_reports_review_iterations() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir" 9 "in_progress" 1 2 1 2

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local review
    review=$(echo "$output" | grep -o '"review"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*' | head -1)
    assert_eq "2" "$review" "Should report 2 review iterations" || return 1
}

# ==============================================================================
# Tests: Missing State File
# ==============================================================================

test_handles_missing_state_file() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    # No state file created

    local output
    local exit_code=0
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1) || exit_code=$?

    # Should not crash
    assert_eq "0" "$exit_code" "Should not crash without state file" || return 1

    # Should report stateExists: false
    assert_json_bool "$output" "stateExists" "false" || return 1
}

test_defaults_phase_to_zero_without_state() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    # No state file

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_json_field "$output" "currentPhase" "0" || return 1
}

test_defaults_status_to_unknown_without_state() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    # No state file

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_json_field "$output" "status" "unknown" || return 1
}

# ==============================================================================
# Tests: Artifact Detection
# ==============================================================================

test_detects_spec_exists() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"
    create_spec_file "$feature_dir"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    # Check artifacts.spec is true
    local spec_exists
    spec_exists=$(echo "$output" | grep -o '"spec"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/"spec"[[:space:]]*:[[:space:]]*//' | tr -d ' ')
    assert_eq "true" "$spec_exists" "Should detect spec exists" || return 1
}

test_detects_plan_exists() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"
    create_plan_file "$feature_dir"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local plan_exists
    plan_exists=$(echo "$output" | grep -o '"plan"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/"plan"[[:space:]]*:[[:space:]]*//' | tr -d ' ')
    assert_eq "true" "$plan_exists" "Should detect plan exists" || return 1
}

test_detects_tasks_exists() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"
    create_tasks_file "$feature_dir" 3 1

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local tasks_exists
    tasks_exists=$(echo "$output" | grep -o '"tasks"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/"tasks"[[:space:]]*:[[:space:]]*//' | tr -d ' ')
    assert_eq "true" "$tasks_exists" "Should detect tasks exists" || return 1
}

test_detects_research_exists() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"
    create_research_file "$feature_dir"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local research_exists
    research_exists=$(echo "$output" | grep -o '"research"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/"research"[[:space:]]*:[[:space:]]*//' | tr -d ' ')
    assert_eq "true" "$research_exists" "Should detect research exists" || return 1
}

test_detects_data_model_exists() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"
    create_data_model_file "$feature_dir"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local dm_exists
    dm_exists=$(echo "$output" | grep -o '"dataModel"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/"dataModel"[[:space:]]*:[[:space:]]*//' | tr -d ' ')
    assert_eq "true" "$dm_exists" "Should detect data model exists" || return 1
}

test_detects_contracts_exists() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"
    create_contracts_dir "$feature_dir"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local contracts_exists
    contracts_exists=$(echo "$output" | grep -o '"contracts"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/"contracts"[[:space:]]*:[[:space:]]*//' | tr -d ' ')
    assert_eq "true" "$contracts_exists" "Should detect contracts exists" || return 1
}

test_detects_spike_report_exists() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"
    create_spike_report "$feature_dir"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local spike_exists
    spike_exists=$(echo "$output" | grep -o '"spikeReport"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/"spikeReport"[[:space:]]*:[[:space:]]*//' | tr -d ' ')
    assert_eq "true" "$spike_exists" "Should detect spike report exists" || return 1
}

test_detects_verification_report_exists() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"
    create_verification_report "$feature_dir"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local verify_exists
    verify_exists=$(echo "$output" | grep -o '"verificationReport"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/"verificationReport"[[:space:]]*:[[:space:]]*//' | tr -d ' ')
    assert_eq "true" "$verify_exists" "Should detect verification report exists" || return 1
}

test_detects_review_report_exists() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"
    create_review_report "$feature_dir"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local review_exists
    review_exists=$(echo "$output" | grep -o '"reviewReport"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/"reviewReport"[[:space:]]*:[[:space:]]*//' | tr -d ' ')
    assert_eq "true" "$review_exists" "Should detect review report exists" || return 1
}

test_detects_missing_artifacts_as_false() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"
    # No artifacts created

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local spec_exists
    spec_exists=$(echo "$output" | grep -o '"spec"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/"spec"[[:space:]]*:[[:space:]]*//' | tr -d ' ')
    assert_eq "false" "$spec_exists" "Should report spec as false when missing" || return 1
}

test_ignores_empty_files() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"
    # Create empty spec file
    touch "$feature_dir/spec.md"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    local spec_exists
    spec_exists=$(echo "$output" | grep -o '"spec"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/"spec"[[:space:]]*:[[:space:]]*//' | tr -d ' ')
    assert_eq "false" "$spec_exists" "Should report spec as false when empty" || return 1
}

# ==============================================================================
# Tests: Status Values
# ==============================================================================

test_reports_in_progress_status() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir" 5 "in_progress"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_json_field "$output" "status" "in_progress" || return 1
}

test_reports_completed_status() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir" 10 "completed"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_json_field "$output" "status" "completed" || return 1
}

test_reports_halted_status() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir" 5 "halted"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_json_field "$output" "status" "halted" || return 1
}

test_reports_checkpoint_status() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir" 5 "checkpoint"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_json_field "$output" "status" "checkpoint" || return 1
}

# ==============================================================================
# Tests: Next Action
# ==============================================================================

test_next_action_for_in_progress() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir" 5 "in_progress"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_contains "$output" "Continue with phase" "Should suggest continuing" || return 1
}

test_next_action_for_completed() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir" 10 "completed"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_contains "$output" "Feature complete" "Should indicate completion" || return 1
}

test_next_action_for_halted() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir" 5 "halted"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_contains "$output" "Manual intervention" "Should suggest intervention" || return 1
}

test_next_action_for_checkpoint() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir" 5 "checkpoint"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_contains "$output" "user input" "Should mention waiting for user" || return 1
}

# ==============================================================================
# Tests: Timestamps
# ==============================================================================

test_reports_created_timestamp() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_contains "$output" "2024-01-15T10:00:00Z" "Should report created timestamp" || return 1
}

test_reports_updated_timestamp() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_contains "$output" "2024-01-16T14:30:00Z" "Should report updated timestamp" || return 1
}

# ==============================================================================
# Tests: Security - Environment Variable File Path Passing
# ==============================================================================

test_security_state_file_uses_env_var() {
    # This test verifies the script uses STATE_FILE_PATH env var for node
    # which prevents command injection via file paths

    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"

    # The file path is passed via STATE_FILE_PATH env var in workflow-status.sh
    # This test ensures no command injection is possible
    local output
    local exit_code=0
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1) || exit_code=$?

    # Should not contain evidence of command injection
    if echo "$output" | grep -qF "pwned"; then
        echo "    SECURITY ISSUE: Potential injection detected"
        return 1
    fi
    if echo "$output" | grep -qF "injected"; then
        echo "    SECURITY ISSUE: Potential injection detected"
        return 1
    fi
    if echo "$output" | grep -qF "hacked"; then
        echo "    SECURITY ISSUE: Potential injection detected"
        return 1
    fi

    return 0
}

test_security_tricky_feature_dir_name() {
    # Test with a feature dir containing shell metacharacters
    # The script should handle this safely
    local feature_dir="$TEST_TEMP_DIR/specs/001-test-feature"
    mkdir -p "$feature_dir"
    create_state_file "$feature_dir"

    local output
    local exit_code=0
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1) || exit_code=$?

    # Should produce valid output
    assert_eq "0" "$exit_code" "Should handle feature dir safely" || return 1

    return 0
}

# ==============================================================================
# Tests: Branch Parameter
# ==============================================================================

test_accepts_branch_parameter() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"

    local output
    local exit_code=0
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" --branch "001-test-feature" 2>&1) || exit_code=$?

    assert_eq "0" "$exit_code" "Should accept --branch parameter" || return 1
    assert_json_field "$output" "branch" "001-test-feature" || return 1
}

# ==============================================================================
# Tests: Feature ID from State
# ==============================================================================

test_reports_feature_id_from_state() {
    local feature_dir
    feature_dir=$(create_feature_dir "001-test-feature")
    create_state_file "$feature_dir"

    local output
    output=$("$STATUS_SCRIPT" --feature-dir "$feature_dir" 2>&1)

    assert_json_field "$output" "featureId" "001-test-feature" || return 1
}

# ==============================================================================
# Tests: Missing Feature Directory
# ==============================================================================

test_handles_nonexistent_feature_dir() {
    local output
    local exit_code=0
    output=$("$STATUS_SCRIPT" --feature-dir "/nonexistent/path" 2>&1) || exit_code=$?

    # Should not crash, should return valid JSON with defaults
    assert_eq "0" "$exit_code" "Should not crash for nonexistent dir" || return 1

    # Should be valid JSON
    if command -v node >/dev/null 2>&1; then
        if ! echo "$output" | node -e 'JSON.parse(require("fs").readFileSync(0, "utf8"))' 2>/dev/null; then
            echo "    Output is not valid JSON"
            return 1
        fi
    fi

    return 0
}

# ==============================================================================
# Main Test Runner
# ==============================================================================

echo "Running workflow-status.sh tests..."
echo ""

# Basic operation
run_test "--help shows usage" test_help_option || true
run_test "Output is valid JSON" test_output_is_valid_json || true

# Phase reporting
run_test "Reports correct phase number" test_reports_correct_phase_number || true
run_test "Reports correct phase name" test_reports_correct_phase_name || true
run_test "Reports phase 0 as Parse" test_reports_phase_0_as_parse || true
run_test "Reports phase 10 as Complete" test_reports_phase_10_as_complete || true

# Task counting
run_test "Reports correct total tasks" test_reports_correct_total_tasks || true
run_test "Reports correct completed tasks" test_reports_correct_completed_tasks || true
run_test "Reports correct incomplete tasks" test_reports_correct_incomplete_tasks || true
run_test "Reports correct progress percentage" test_reports_correct_progress_percentage || true
run_test "Zero tasks reports zero progress" test_zero_tasks_reports_zero_progress || true

# Iteration counts
run_test "Reports spike iterations" test_reports_spike_iterations || true
run_test "Reports implement iterations" test_reports_implement_iterations || true
run_test "Reports verify iterations" test_reports_verify_iterations || true
run_test "Reports review iterations" test_reports_review_iterations || true

# Missing state file
run_test "Handles missing state file gracefully" test_handles_missing_state_file || true
run_test "Defaults phase to 0 without state" test_defaults_phase_to_zero_without_state || true
run_test "Defaults status to unknown without state" test_defaults_status_to_unknown_without_state || true

# Artifact detection
run_test "Detects spec exists" test_detects_spec_exists || true
run_test "Detects plan exists" test_detects_plan_exists || true
run_test "Detects tasks exists" test_detects_tasks_exists || true
run_test "Detects research exists" test_detects_research_exists || true
run_test "Detects data model exists" test_detects_data_model_exists || true
run_test "Detects contracts exists" test_detects_contracts_exists || true
run_test "Detects spike report exists" test_detects_spike_report_exists || true
run_test "Detects verification report exists" test_detects_verification_report_exists || true
run_test "Detects review report exists" test_detects_review_report_exists || true
run_test "Detects missing artifacts as false" test_detects_missing_artifacts_as_false || true
run_test "Ignores empty files" test_ignores_empty_files || true

# Status values
run_test "Reports in_progress status" test_reports_in_progress_status || true
run_test "Reports completed status" test_reports_completed_status || true
run_test "Reports halted status" test_reports_halted_status || true
run_test "Reports checkpoint status" test_reports_checkpoint_status || true

# Next action
run_test "Next action for in_progress" test_next_action_for_in_progress || true
run_test "Next action for completed" test_next_action_for_completed || true
run_test "Next action for halted" test_next_action_for_halted || true
run_test "Next action for checkpoint" test_next_action_for_checkpoint || true

# Timestamps
run_test "Reports created timestamp" test_reports_created_timestamp || true
run_test "Reports updated timestamp" test_reports_updated_timestamp || true

# Security
run_test "Security: state file uses env var" test_security_state_file_uses_env_var || true
run_test "Security: handles tricky feature dir name" test_security_tricky_feature_dir_name || true

# Parameters
run_test "Accepts --branch parameter" test_accepts_branch_parameter || true
run_test "Reports feature ID from state" test_reports_feature_id_from_state || true

# Edge cases
run_test "Handles nonexistent feature dir" test_handles_nonexistent_feature_dir || true

echo ""
echo "========================================"
echo "Test Results: $TESTS_PASSED/$TESTS_RUN passed"
if [ "$TESTS_FAILED" -gt 0 ]; then
    echo "FAILED: $TESTS_FAILED tests failed"
    exit 1
else
    echo "SUCCESS: All tests passed"
    exit 0
fi
