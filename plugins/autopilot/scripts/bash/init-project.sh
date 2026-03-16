#!/usr/bin/env bash
# Initialize autopilot in a project directory
#
# Structure:
#   CLAUDE.md              - Constitution (principles, static, user-maintained)
#   .autopilot/context.md  - Active context (tech stack, recent changes, auto-updated)
#   .autopilot/templates/  - Spec/plan/tasks templates
#   specs/                 - Feature directories
#
# Usage: init-project.sh [--force]
# Output: JSON with status and created files

set -e

FORCE="false"
if [ "$1" = "--force" ]; then
    FORCE="true"
fi

# Resolve plugin root (relative to this script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SPECKIT_TEMPLATES="$PLUGIN_ROOT/vendor/spec-kit/templates"

# Project directories to create
AUTOPILOT_DIR=".autopilot"
TEMPLATES_DIR="$AUTOPILOT_DIR/templates"
SPECS_DIR="specs"

# Check if already initialized
ALREADY_EXISTS="false"
if [ -d "$AUTOPILOT_DIR" ]; then
    ALREADY_EXISTS="true"
    if [ "$FORCE" != "true" ]; then
        cat <<EOF
{
  "status": "exists",
  "message": ".autopilot directory already exists. Use --force to reinitialize.",
  "autopilot_dir": "$AUTOPILOT_DIR"
}
EOF
        exit 0
    fi
fi

# Create directories
mkdir -p "$TEMPLATES_DIR"
mkdir -p "$SPECS_DIR"

CREATED_FILES=()
SKIPPED_FILES=()

# Copy templates from spec-kit submodule (skip constitution-template, we use CLAUDE.md)
if [ -d "$SPECKIT_TEMPLATES" ]; then
    for tmpl in spec-template.md plan-template.md tasks-template.md checklist-template.md; do
        src="$SPECKIT_TEMPLATES/$tmpl"
        dst="$TEMPLATES_DIR/$tmpl"
        if [ -f "$src" ]; then
            if [ -f "$dst" ] && [ "$FORCE" != "true" ]; then
                SKIPPED_FILES+=("$tmpl")
            else
                cp "$src" "$dst"
                CREATED_FILES+=("templates/$tmpl")
            fi
        fi
    done
else
    echo "Warning: spec-kit templates not found at $SPECKIT_TEMPLATES" >&2
fi

# Initialize CLAUDE.md as constitution if not exists
CLAUDE_MD="CLAUDE.md"
CONTEXT_LINK_TEXT="See [.autopilot/context.md](.autopilot/context.md) for current tech stack and recent changes."

if [ ! -f "$CLAUDE_MD" ]; then
    cat > "$CLAUDE_MD" <<CLAUDEMD
# Project Guidelines

## Principles

<!-- Add your project principles here -->
<!-- These guide all AI-assisted development -->

## Commands

\`\`\`bash
# Add your project commands here
\`\`\`

## Code Style

<!-- Add language-specific conventions here -->

## Active Context

$CONTEXT_LINK_TEXT
CLAUDEMD
    CREATED_FILES+=("CLAUDE.md")
else
    # CLAUDE.md exists - check if it has the context link, add if missing
    if ! grep -qF ".autopilot/context.md" "$CLAUDE_MD"; then
        # Append the context link section
        cat >> "$CLAUDE_MD" <<APPENDMD

## Active Context

$CONTEXT_LINK_TEXT
APPENDMD
        CREATED_FILES+=("CLAUDE.md (updated with context link)")
    else
        SKIPPED_FILES+=("CLAUDE.md")
    fi
fi

# Initialize .autopilot/context.md for dynamic tech stack
CONTEXT_FILE="$AUTOPILOT_DIR/context.md"
if [ ! -f "$CONTEXT_FILE" ]; then
    CURRENT_DATE=$(date +%Y-%m-%d)
    cat > "$CONTEXT_FILE" <<CONTEXTMD
# Active Context

Auto-generated from feature plans. Last updated: $CURRENT_DATE

## Active Technologies

<!-- Auto-populated by autopilot from plan.md -->

## Recent Changes

<!-- Auto-populated by autopilot after each feature -->
CONTEXTMD
    CREATED_FILES+=("context.md")
else
    SKIPPED_FILES+=("context.md")
fi

# Build JSON arrays (with jq fallback)
build_json_array() {
    local arr=("$@")
    if [ ${#arr[@]} -eq 0 ]; then
        echo "[]"
        return
    fi
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "${arr[@]}" | jq -R . | jq -s .
    else
        # Manual JSON array building without jq
        local result="["
        local first=true
        for item in "${arr[@]}"; do
            if [ "$first" = true ]; then
                first=false
            else
                result+=","
            fi
            # Escape quotes and backslashes
            item="${item//\\/\\\\}"
            item="${item//\"/\\\"}"
            result+="\"$item\""
        done
        result+="]"
        echo "$result"
    fi
}

CREATED_JSON=$(build_json_array "${CREATED_FILES[@]}")
SKIPPED_JSON=$(build_json_array "${SKIPPED_FILES[@]}")

cat <<EOF
{
  "status": "success",
  "already_existed": $ALREADY_EXISTS,
  "directories": {
    "autopilot": "$AUTOPILOT_DIR",
    "templates": "$TEMPLATES_DIR",
    "specs": "$SPECS_DIR"
  },
  "created": $CREATED_JSON,
  "skipped": $SKIPPED_JSON,
  "constitution": "CLAUDE.md",
  "context": "$CONTEXT_FILE"
}
EOF
