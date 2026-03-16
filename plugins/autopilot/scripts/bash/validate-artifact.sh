#!/usr/bin/env bash
# validate-artifact.sh - Validate feature artifacts (spec, plan, tasks, etc.)
# Usage: validate-artifact.sh --type <artifact_type> --file <path> [--strict]
# Output: JSON validation result

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# ==============================================================================
# Argument Parsing
# ==============================================================================

ARTIFACT_TYPE=""
FILE_PATH=""
STRICT_MODE="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --type)
            ARTIFACT_TYPE="$2"
            shift 2
            ;;
        --file)
            FILE_PATH="$2"
            shift 2
            ;;
        --strict)
            STRICT_MODE="true"
            shift
            ;;
        --help)
            echo "Usage: $0 --type <type> --file <path> [--strict]"
            echo ""
            echo "Artifact types:"
            echo "  spec       Validate spec.md structure"
            echo "  plan       Validate plan.md structure"
            echo "  tasks      Validate tasks.md structure"
            echo "  contract   Validate OpenAPI contract"
            echo "  checklist  Validate checklist structure"
            echo "  state      Validate workflow state JSON"
            echo ""
            echo "Options:"
            echo "  --strict   Fail on warnings (not just errors)"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [ -z "$ARTIFACT_TYPE" ]; then
    log_error "Missing required argument: --type"
    exit 1
fi

if [ -z "$FILE_PATH" ]; then
    log_error "Missing required argument: --file"
    exit 1
fi

# ==============================================================================
# Validation Helpers
# ==============================================================================

ERRORS=()
WARNINGS=()

add_error() {
    ERRORS+=("$1")
}

add_warning() {
    WARNINGS+=("$1")
}

check_section_exists() {
    local file="$1"
    local section="$2"
    local required="${3:-true}"

    if ! grep -qE "^##? $section" "$file"; then
        if [ "$required" = "true" ]; then
            add_error "Missing required section: $section"
        else
            add_warning "Missing optional section: $section"
        fi
        return 1
    fi
    return 0
}

check_min_content() {
    local file="$1"
    local min_lines="$2"

    local actual_lines
    actual_lines=$(grep -cE '^[^#].*[a-zA-Z]' "$file" | tr -d ' ')

    if [ "$actual_lines" -lt "$min_lines" ]; then
        add_warning "Low content: only $actual_lines lines of text (expected >= $min_lines)"
        return 1
    fi
    return 0
}

check_no_todo_placeholders() {
    local file="$1"

    if grep -qE '(TODO|FIXME|XXX|TBD)' "$file"; then
        local count
        count=$(grep -cE '(TODO|FIXME|XXX|TBD)' "$file" | tr -d ' ')
        add_warning "Contains $count unresolved placeholders (TODO/FIXME/XXX/TBD)"
    fi
}

# ==============================================================================
# Artifact-Specific Validation
# ==============================================================================

validate_spec() {
    local file="$1"

    # Required sections
    check_section_exists "$file" "Overview" true
    check_section_exists "$file" "Goals" true
    check_section_exists "$file" "Requirements" true

    # Optional but recommended
    check_section_exists "$file" "Non-Goals" false
    check_section_exists "$file" "Success Criteria" false

    # Content checks
    check_min_content "$file" 20
    check_no_todo_placeholders "$file"

    # Check for requirement IDs
    if ! grep -qE 'FR-[0-9]+|NFR-[0-9]+' "$file"; then
        add_warning "No requirement IDs found (expected FR-XXX or NFR-XXX format)"
    fi
}

validate_plan() {
    local file="$1"

    # Required sections
    check_section_exists "$file" "Architecture" true
    check_section_exists "$file" "Components" true

    # Optional but recommended
    check_section_exists "$file" "Data Model" false
    check_section_exists "$file" "API Design" false
    check_section_exists "$file" "Dependencies" false
    check_section_exists "$file" "Assumptions" false

    # Content checks
    check_min_content "$file" 30
    check_no_todo_placeholders "$file"
}

validate_tasks() {
    local file="$1"

    # Must have at least one task
    local task_count
    task_count=$(grep -cE '^[[:space:]]*-[[:space:]]*\[[ Xx]\][[:space:]]*T[0-9]+:' "$file" | tr -d ' ' || echo "0")

    if [ "$task_count" -eq 0 ]; then
        add_error "No tasks found (expected format: - [ ] T001: Description)"
        return
    fi

    # Check for verify lines
    local verify_count
    verify_count=$(grep -cE '\*\*Verify\*\*:' "$file" | tr -d ' ' || echo "0")

    if [ "$verify_count" -lt "$task_count" ]; then
        add_warning "Only $verify_count of $task_count tasks have Verify lines"
    fi

    # Check for valid verify types
    if grep -qE '\*\*Verify\*\*:' "$file"; then
        local invalid_types
        invalid_types=$(grep -E '\*\*Verify\*\*:' "$file" | grep -cvE '(UI|API|CLI|DB|TEST|E2E) \|' || echo "0")
        if [ "$invalid_types" -gt 0 ]; then
            add_warning "$invalid_types Verify lines have invalid type (expected UI|API|CLI|DB|TEST|E2E)"
        fi
    fi

    check_no_todo_placeholders "$file"
}

validate_contract() {
    local file="$1"

    # Check YAML syntax using python (more portable than node for YAML)
    # SECURITY: Pass file path via environment variable to prevent injection
    if command -v python3 >/dev/null 2>&1; then
        if ! FILE_PATH="$file" python3 -c "import os, yaml; yaml.safe_load(open(os.environ['FILE_PATH']))" 2>/dev/null; then
            add_error "Invalid YAML syntax"
            return
        fi
    elif command -v python >/dev/null 2>&1; then
        if ! FILE_PATH="$file" python -c "import os, yaml; yaml.safe_load(open(os.environ['FILE_PATH']))" 2>/dev/null; then
            # Python yaml module might not be installed, skip validation
            add_warning "Could not validate YAML syntax (pyyaml not installed)"
        fi
    fi

    # Check for OpenAPI structure
    if ! grep -qE '^openapi:|^swagger:' "$file"; then
        add_error "Missing OpenAPI/Swagger version declaration"
    fi

    if ! grep -qE '^paths:' "$file"; then
        add_error "Missing paths section"
    fi

    if ! grep -qE '^info:' "$file"; then
        add_warning "Missing info section"
    fi
}

validate_checklist() {
    local file="$1"

    # Must have checkbox items
    local checkbox_count
    checkbox_count=$(grep -cE '^[[:space:]]*-[[:space:]]*\[[ Xx]\]' "$file" | tr -d ' ' || echo "0")

    if [ "$checkbox_count" -eq 0 ]; then
        add_error "No checklist items found (expected format: - [ ] Item)"
        return
    fi

    check_no_todo_placeholders "$file"
}

validate_state() {
    local file="$1"

    # Must be valid JSON
    # SECURITY: Pass file path via environment variable to prevent injection
    if command -v node >/dev/null 2>&1; then
        if ! FILE_PATH="$file" node -e 'JSON.parse(require("fs").readFileSync(process.env.FILE_PATH, "utf8"))' 2>/dev/null; then
            add_error "Invalid JSON syntax"
            return
        fi

        # Check required fields
        local missing_fields
        missing_fields=$(FILE_PATH="$file" node -e '
            const state = JSON.parse(require("fs").readFileSync(process.env.FILE_PATH, "utf8"));
            const required = ["version", "featureId", "currentPhase", "status"];
            const missing = required.filter(f => state[f] === undefined);
            if (missing.length > 0) console.log(missing.join(", "));
        ')

        if [ -n "$missing_fields" ]; then
            add_error "Missing required state fields: $missing_fields"
        fi
    else
        # Fallback: basic JSON check
        if ! FILE_PATH="$file" python3 -c "import os, json; json.load(open(os.environ['FILE_PATH']))" 2>/dev/null; then
            add_error "Invalid JSON syntax"
        fi
    fi
}

# ==============================================================================
# Main Validation
# ==============================================================================

REPO_ROOT=$(get_repo_root)

# Resolve path
if [[ "$FILE_PATH" != /* ]]; then
    FILE_PATH="$REPO_ROOT/$FILE_PATH"
fi

# Check file exists
if [ ! -f "$FILE_PATH" ]; then
    json_output "status" "error" "file" "$FILE_PATH" "message" "File not found"
    exit 1
fi

# Check not empty
if [ ! -s "$FILE_PATH" ]; then
    json_output "status" "error" "file" "$FILE_PATH" "message" "File is empty"
    exit 1
fi

# Run type-specific validation
case "$ARTIFACT_TYPE" in
    spec)
        validate_spec "$FILE_PATH"
        ;;
    plan)
        validate_plan "$FILE_PATH"
        ;;
    tasks)
        validate_tasks "$FILE_PATH"
        ;;
    contract)
        validate_contract "$FILE_PATH"
        ;;
    checklist)
        validate_checklist "$FILE_PATH"
        ;;
    state)
        validate_state "$FILE_PATH"
        ;;
    *)
        log_error "Unknown artifact type: $ARTIFACT_TYPE"
        exit 1
        ;;
esac

# ==============================================================================
# Output Result
# ==============================================================================

ERROR_COUNT=${#ERRORS[@]}
WARNING_COUNT=${#WARNINGS[@]}

# Determine status
STATUS="valid"
EXIT_CODE=0

if [ "$ERROR_COUNT" -gt 0 ]; then
    STATUS="invalid"
    EXIT_CODE=1
elif [ "$WARNING_COUNT" -gt 0 ]; then
    if [ "$STRICT_MODE" = "true" ]; then
        STATUS="invalid"
        EXIT_CODE=1
    else
        STATUS="valid_with_warnings"
    fi
fi

# Build JSON output (use json_escape for safety)
{
    echo "{"
    echo "  \"status\": \"$STATUS\","
    echo "  \"file\": \"$(json_escape "$FILE_PATH")\","
    echo "  \"type\": \"$ARTIFACT_TYPE\","
    echo "  \"errors\": ["
    for i in "${!ERRORS[@]}"; do
        if [ "$i" -gt 0 ]; then echo ","; fi
        echo -n "    \"$(json_escape "${ERRORS[$i]}")\""
    done
    if [ "$ERROR_COUNT" -gt 0 ]; then echo; fi
    echo "  ],"
    echo "  \"warnings\": ["
    for i in "${!WARNINGS[@]}"; do
        if [ "$i" -gt 0 ]; then echo ","; fi
        echo -n "    \"$(json_escape "${WARNINGS[$i]}")\""
    done
    if [ "$WARNING_COUNT" -gt 0 ]; then echo; fi
    echo "  ],"
    echo "  \"errorCount\": $ERROR_COUNT,"
    echo "  \"warningCount\": $WARNING_COUNT"
    echo "}"
}

exit $EXIT_CODE
