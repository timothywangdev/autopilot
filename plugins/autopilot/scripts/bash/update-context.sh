#!/usr/bin/env bash
# Update .autopilot/context.md with tech stack from plan.md
#
# This is autopilot's version of spec-kit's update-agent-context.sh.
# Key difference: writes to .autopilot/context.md (not CLAUDE.md).
# CLAUDE.md is the constitution (static principles), context.md is dynamic.
#
# Usage: update-context.sh
# Output: JSON with status and changes made

set -e

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONTEXT_FILE="$REPO_ROOT/.autopilot/context.md"

# Get current branch/feature
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
CURRENT_DATE=$(date +%Y-%m-%d)

# Find plan.md for current feature
FEATURE_DIR=""
if [[ "$CURRENT_BRANCH" =~ ^([0-9]+-[^/]+)$ ]]; then
    # Branch format: NNN-feature-name
    FEATURE_NAME="${BASH_REMATCH[1]}"
    for dir in "$REPO_ROOT/specs/$FEATURE_NAME" "$REPO_ROOT/specs/"*"$FEATURE_NAME"*; do
        if [ -d "$dir" ] && [ -f "$dir/plan.md" ]; then
            FEATURE_DIR="$dir"
            break
        fi
    done
fi

# Fallback: find most recent plan.md (portable - works on macOS and Linux)
if [ -z "$FEATURE_DIR" ]; then
    FEATURE_DIR=$(find "$REPO_ROOT/specs" -name "plan.md" -type f 2>/dev/null | while read -r f; do
        echo "$(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f" 2>/dev/null) $(dirname "$f")"
    done | sort -rn | head -1 | cut -d' ' -f2-)
fi

if [ -z "$FEATURE_DIR" ] || [ ! -f "$FEATURE_DIR/plan.md" ]; then
    cat <<EOF
{
  "status": "skipped",
  "message": "No plan.md found for current feature",
  "branch": "$CURRENT_BRANCH"
}
EOF
    exit 0
fi

PLAN_FILE="$FEATURE_DIR/plan.md"

# Extract tech info from plan.md
extract_field() {
    local pattern="$1"
    grep "^\*\*${pattern}\*\*: " "$PLAN_FILE" 2>/dev/null | \
        head -1 | \
        sed "s|^\*\*${pattern}\*\*: ||" | \
        sed 's/^[ \t]*//;s/[ \t]*$//' | \
        grep -v "NEEDS CLARIFICATION" | \
        grep -v "^N/A$" || echo ""
}

NEW_LANG=$(extract_field "Language/Version")
NEW_FRAMEWORK=$(extract_field "Primary Dependencies")
NEW_DB=$(extract_field "Storage")

# Build tech stack string
TECH_STACK=""
if [ -n "$NEW_LANG" ] && [ -n "$NEW_FRAMEWORK" ]; then
    TECH_STACK="$NEW_LANG + $NEW_FRAMEWORK"
elif [ -n "$NEW_LANG" ]; then
    TECH_STACK="$NEW_LANG"
elif [ -n "$NEW_FRAMEWORK" ]; then
    TECH_STACK="$NEW_FRAMEWORK"
fi

# Check if context file exists
if [ ! -f "$CONTEXT_FILE" ]; then
    cat <<EOF
{
  "status": "error",
  "message": "Context file not found. Run /autopilot:init first.",
  "expected": "$CONTEXT_FILE"
}
EOF
    exit 1
fi

# Update context file
TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE"' EXIT
ADDED_TECH=()
ADDED_CHANGE=""

# Track sections
in_tech_section=false
in_changes_section=false
tech_added=false
change_added=false
changes_count=0

while IFS= read -r line || [[ -n "$line" ]]; do
    # Update timestamp
    if [[ "$line" =~ Last\ updated:.*[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
        echo "Auto-generated from feature plans. Last updated: $CURRENT_DATE" >> "$TEMP_FILE"
        continue
    fi

    # Handle Active Technologies section
    if [[ "$line" == "## Active Technologies" ]]; then
        echo "$line" >> "$TEMP_FILE"
        in_tech_section=true
        continue
    elif [[ $in_tech_section == true ]] && [[ "$line" =~ ^##[[:space:]] ]]; then
        # End of tech section - add new entries before next section
        if [[ $tech_added == false ]] && [[ -n "$TECH_STACK" ]]; then
            if ! grep -q "$TECH_STACK" "$CONTEXT_FILE"; then
                echo "- $TECH_STACK ($CURRENT_BRANCH)" >> "$TEMP_FILE"
                ADDED_TECH+=("$TECH_STACK")
            fi
            if [[ -n "$NEW_DB" ]] && ! grep -q "$NEW_DB" "$CONTEXT_FILE"; then
                echo "- $NEW_DB ($CURRENT_BRANCH)" >> "$TEMP_FILE"
                ADDED_TECH+=("$NEW_DB")
            fi
            tech_added=true
        fi
        echo "$line" >> "$TEMP_FILE"
        in_tech_section=false
        # If transitioning to Recent Changes, set up that section
        if [[ "$line" == "## Recent Changes" ]]; then
            if [[ -n "$TECH_STACK" ]]; then
                echo "- $CURRENT_BRANCH: Added $TECH_STACK" >> "$TEMP_FILE"
                ADDED_CHANGE="$CURRENT_BRANCH: Added $TECH_STACK"
            fi
            in_changes_section=true
            change_added=true
        fi
        continue
    elif [[ $in_tech_section == true ]] && [[ -z "$line" ]]; then
        # Empty line in tech section - add entries here
        if [[ $tech_added == false ]] && [[ -n "$TECH_STACK" ]]; then
            if ! grep -q "$TECH_STACK" "$CONTEXT_FILE"; then
                echo "- $TECH_STACK ($CURRENT_BRANCH)" >> "$TEMP_FILE"
                ADDED_TECH+=("$TECH_STACK")
            fi
            if [[ -n "$NEW_DB" ]] && ! grep -q "$NEW_DB" "$CONTEXT_FILE"; then
                echo "- $NEW_DB ($CURRENT_BRANCH)" >> "$TEMP_FILE"
                ADDED_TECH+=("$NEW_DB")
            fi
            tech_added=true
        fi
        echo "$line" >> "$TEMP_FILE"
        continue
    fi

    # Handle Recent Changes section
    if [[ "$line" == "## Recent Changes" ]]; then
        echo "$line" >> "$TEMP_FILE"
        # Add new change right after heading
        if [[ -n "$TECH_STACK" ]]; then
            echo "- $CURRENT_BRANCH: Added $TECH_STACK" >> "$TEMP_FILE"
            ADDED_CHANGE="$CURRENT_BRANCH: Added $TECH_STACK"
        fi
        in_changes_section=true
        change_added=true
        continue
    elif [[ $in_changes_section == true ]] && [[ "$line" =~ ^##[[:space:]] ]]; then
        echo "$line" >> "$TEMP_FILE"
        in_changes_section=false
        continue
    elif [[ $in_changes_section == true ]] && [[ "$line" == "- "* ]]; then
        # Keep only first 2 existing changes (plus our new one = 3 total)
        if [[ $changes_count -lt 2 ]]; then
            echo "$line" >> "$TEMP_FILE"
            changes_count=$((changes_count + 1))
        fi
        continue
    fi

    echo "$line" >> "$TEMP_FILE"
done < "$CONTEXT_FILE"

# Move temp file to context
mv "$TEMP_FILE" "$CONTEXT_FILE"

# Build JSON output
ADDED_TECH_JSON=$(printf '%s\n' "${ADDED_TECH[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")
if [ ${#ADDED_TECH[@]} -eq 0 ]; then
    ADDED_TECH_JSON="[]"
fi

cat <<EOF
{
  "status": "success",
  "branch": "$CURRENT_BRANCH",
  "plan_file": "$PLAN_FILE",
  "context_file": "$CONTEXT_FILE",
  "added_technologies": $ADDED_TECH_JSON,
  "added_change": "$ADDED_CHANGE"
}
EOF
