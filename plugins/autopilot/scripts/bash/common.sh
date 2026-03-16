#!/usr/bin/env bash
# common.sh - Shared utilities for autopilot scripts
# Sourced by other scripts, not executed directly

# ==============================================================================
# Configuration
# ==============================================================================

AUTOPILOT_VERSION="1.0.0"
SPECS_DIR="specs"
STATE_FILE_NAME=".workflow-state.json"

# ==============================================================================
# Output Helpers
# ==============================================================================

log_info() {
    echo "INFO: $1" >&2
}

log_success() {
    echo "✓ $1" >&2
}

log_error() {
    echo "ERROR: $1" >&2
}

log_warning() {
    echo "WARNING: $1" >&2
}

# ==============================================================================
# Repository Detection
# ==============================================================================

# Find repository root by looking for .git or .autopilot
get_repo_root() {
    local dir="${1:-$(pwd)}"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.git" ] || [ -d "$dir/.autopilot" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    # Fallback to current directory
    pwd
}

# Check if git is available and we're in a git repo
has_git() {
    command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1
}

# Get current branch name
get_current_branch() {
    # Priority 1: AUTOPILOT_FEATURE environment variable
    if [ -n "${AUTOPILOT_FEATURE:-}" ]; then
        echo "$AUTOPILOT_FEATURE"
        return 0
    fi

    # Priority 2: Git branch (if available)
    if has_git; then
        local branch
        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
            echo "$branch"
            return 0
        fi
    fi

    # Priority 3: Most recent specs directory
    local repo_root
    repo_root=$(get_repo_root)
    if [ -d "$repo_root/$SPECS_DIR" ]; then
        local latest
        latest=$(ls -td "$repo_root/$SPECS_DIR"/[0-9][0-9][0-9]-* 2>/dev/null | head -1)
        if [ -n "$latest" ]; then
            basename "$latest"
            return 0
        fi
    fi

    # Fallback
    echo "main"
}

# ==============================================================================
# Feature Directory Functions
# ==============================================================================

# Get highest feature number from specs directory
get_highest_feature_number() {
    local repo_root="${1:-$(get_repo_root)}"
    local highest=0

    if [ -d "$repo_root/$SPECS_DIR" ]; then
        # Enable nullglob so empty dirs don't cause glob to return literal pattern
        local prev_nullglob
        prev_nullglob=$(shopt -p nullglob 2>/dev/null || echo "shopt -u nullglob")
        shopt -s nullglob
        # Support both 3-digit (001-999) and 4-digit (0001-9999) feature numbers
        for dir in "$repo_root/$SPECS_DIR"/[0-9]*-*; do
            [ -d "$dir" ] || continue
            local num
            num=$(basename "$dir" | grep -oE '^[0-9]+' || echo "0")
            # Safely handle numbers up to 9999
            num=$((10#$num))
            if [ "$num" -gt 9999 ]; then
                log_warning "Feature number $num exceeds limit (9999)"
                continue
            fi
            if [ "$num" -gt "$highest" ]; then
                highest=$num
            fi
        done
        # Restore previous nullglob setting
        eval "$prev_nullglob"
    fi

    # Also check git branches if available (scoped to repo_root)
    if [ -d "$repo_root/.git" ] || git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
        local branch_nums
        branch_nums=$(git -C "$repo_root" branch -a 2>/dev/null | grep -oE '[0-9]+-' | grep -oE '[0-9]+' || true)
        for num in $branch_nums; do
            num=$((10#$num))
            if [ "$num" -le 9999 ] && [ "$num" -gt "$highest" ]; then
                highest=$num
            fi
        done
    fi

    echo "$highest"
}

# Find feature directory by branch name or prefix
find_feature_dir() {
    local repo_root="${1:-$(get_repo_root)}"
    local branch="${2:-$(get_current_branch)}"

    # Extract numeric prefix from branch
    local prefix
    prefix=$(echo "$branch" | grep -oE '^[0-9]+' || echo "")

    if [ -z "$prefix" ]; then
        return 1
    fi

    # Pad to 3 or 4 digits (4 if > 999)
    local num=$((10#$prefix))
    if [ "$num" -gt 999 ]; then
        prefix=$(printf "%04d" "$num")
    else
        prefix=$(printf "%03d" "$num")
    fi

    # Find matching directory
    local matches
    matches=$(ls -d "$repo_root/$SPECS_DIR/$prefix"-* 2>/dev/null | head -1)

    if [ -n "$matches" ] && [ -d "$matches" ]; then
        echo "$matches"
        return 0
    fi

    return 1
}

# Escape a string for safe shell single-quote inclusion
# Replaces ' with '\'' (end quote, escaped quote, start quote)
shell_escape() {
    local str="$1"
    printf '%s' "$str" | sed "s/'/'\\\\''/g"
}

# Get all standard feature paths
get_feature_paths() {
    local repo_root
    repo_root=$(get_repo_root)
    local branch
    branch=$(get_current_branch)
    local feature_dir
    feature_dir=$(find_feature_dir "$repo_root" "$branch" 2>/dev/null || echo "")
    local has_git_repo="false"

    if has_git; then
        has_git_repo="true"
    fi

    # Escape values for safe shell eval
    local esc_repo_root esc_branch esc_feature_dir
    esc_repo_root=$(shell_escape "$repo_root")
    esc_branch=$(shell_escape "$branch")
    esc_feature_dir=$(shell_escape "$feature_dir")

    cat <<EOF
REPO_ROOT='$esc_repo_root'
CURRENT_BRANCH='$esc_branch'
HAS_GIT='$has_git_repo'
FEATURE_DIR='$esc_feature_dir'
SPEC_FILE='$esc_feature_dir/spec.md'
PLAN_FILE='$esc_feature_dir/plan.md'
TASKS_FILE='$esc_feature_dir/tasks.md'
STATE_FILE='$esc_feature_dir/$STATE_FILE_NAME'
RESEARCH_FILE='$esc_feature_dir/research.md'
DATA_MODEL_FILE='$esc_feature_dir/data-model.md'
CONTRACTS_DIR='$esc_feature_dir/contracts'
CHECKLISTS_DIR='$esc_feature_dir/checklists'
EOF
}

# ==============================================================================
# Validation Functions
# ==============================================================================

# Portable realpath alternative (works on macOS/BSD)
get_realpath() {
    local path="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath "$path" 2>/dev/null
    elif [ -e "$path" ]; then
        # Fallback: resolve path manually
        local dir
        local base
        dir=$(cd "$(dirname "$path")" 2>/dev/null && pwd)
        base=$(basename "$path")
        if [ -n "$dir" ]; then
            echo "$dir/$base"
        fi
    fi
}

# Validate plan file path (security check)
validate_plan_path() {
    local plan_file="$1"
    local repo_root="${2:-$(get_repo_root)}"

    # Check not empty
    if [ -z "$plan_file" ]; then
        log_error "No plan file specified"
        return 1
    fi

    # Reject shell metacharacters
    if echo "$plan_file" | grep -qE '[$`|;&(){}]|\.\.'; then
        log_error "Invalid characters in plan file path"
        return 1
    fi

    # Must be .md file
    if ! echo "$plan_file" | grep -qE '\.md$'; then
        log_error "Plan file must be a .md file"
        return 1
    fi

    # Resolve to absolute path
    local real_path
    real_path=$(get_realpath "$plan_file")
    if [ -z "$real_path" ]; then
        log_error "Plan file not found: $plan_file"
        return 1
    fi

    # Must be within project
    case "$real_path" in
        "$repo_root"/*) ;;
        *)
            log_error "Plan file must be within project directory"
            return 1
            ;;
    esac

    # Must exist and be a file
    if [ ! -f "$real_path" ]; then
        log_error "Plan file not found: $plan_file"
        return 1
    fi

    # Check not a symlink (security)
    if [ -L "$real_path" ]; then
        log_error "Plan file cannot be a symlink"
        return 1
    fi

    echo "$real_path"
    return 0
}

# Check if file exists and is not empty
check_file_exists() {
    local file="$1"
    local name="${2:-$file}"

    if [ ! -f "$file" ]; then
        echo "✗ $name (missing)"
        return 1
    elif [ ! -s "$file" ]; then
        echo "✗ $name (empty)"
        return 1
    else
        echo "✓ $name"
        return 0
    fi
}

# Check if directory exists and is not empty
check_dir_exists() {
    local dir="$1"
    local name="${2:-$dir}"

    if [ ! -d "$dir" ]; then
        echo "✗ $name (missing)"
        return 1
    elif [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
        echo "✗ $name (empty)"
        return 1
    else
        echo "✓ $name"
        return 0
    fi
}

# ==============================================================================
# Branch Name Generation
# ==============================================================================

# Clean a string for use in branch name
clean_branch_name() {
    local name="$1"
    echo "$name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-50
}

# Generate branch name from description
generate_branch_name() {
    local description="$1"

    # Remove common stop words
    local stop_words="a an the and or but in on at to for of with by from as is are was were be been being have has had do does did will would could should may might must shall can"

    # Convert to lowercase, split into words
    local words
    words=$(echo "$description" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' ' ')

    # Filter out stop words and short words
    local filtered=""
    local count=0
    for word in $words; do
        # Skip stop words
        if echo " $stop_words " | grep -q " $word "; then
            continue
        fi
        # Skip short words (less than 3 chars)
        if [ ${#word} -lt 3 ]; then
            continue
        fi
        # Add word
        if [ -z "$filtered" ]; then
            filtered="$word"
        else
            filtered="$filtered-$word"
        fi
        count=$((count + 1))
        # Max 4 words
        if [ "$count" -ge 4 ]; then
            break
        fi
    done

    # Fallback if no words remain
    if [ -z "$filtered" ]; then
        filtered="feature"
    fi

    echo "$filtered"
}

# ==============================================================================
# JSON Output Helper
# ==============================================================================

# Escape a string for safe JSON inclusion
# Usage: json_escape "string with \"quotes\" and \\ backslashes"
json_escape() {
    local str="$1"
    # Escape backslashes first, then quotes, then control characters
    str=$(printf '%s' "$str" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' | tr '\n' ' ' | tr '\r' ' ')
    printf '%s' "$str"
}

# Output JSON object from key=value pairs
# Usage: json_output "KEY1" "value1" "KEY2" "value2"
json_output() {
    local first=true
    echo -n "{"
    while [ $# -ge 2 ]; do
        local key="$1"
        local value="$2"
        shift 2

        if [ "$first" = true ]; then
            first=false
        else
            echo -n ","
        fi

        # Escape special characters in value
        value=$(json_escape "$value")
        echo -n "\"$key\":\"$value\""
    done
    echo "}"
}

# Output JSON array from values
# Usage: json_array "value1" "value2" "value3"
json_array() {
    local first=true
    echo -n "["
    for value in "$@"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo -n ","
        fi
        value=$(json_escape "$value")
        echo -n "\"$value\""
    done
    echo "]"
}
