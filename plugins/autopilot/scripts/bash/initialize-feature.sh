#!/usr/bin/env bash
# initialize-feature.sh - Create feature directory structure with all artifacts
# Usage: initialize-feature.sh --description "Feature description" [--number NNN]
# Output: JSON with paths to created artifacts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# ==============================================================================
# Argument Parsing
# ==============================================================================

DESCRIPTION=""
FEATURE_NUMBER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --description)
            DESCRIPTION="$2"
            shift 2
            ;;
        --number)
            FEATURE_NUMBER="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 --description \"Feature description\" [--number NNN]"
            echo ""
            echo "Options:"
            echo "  --description  Feature description (required)"
            echo "  --number       Feature number (auto-increments if not specified)"
            echo ""
            echo "Output: JSON with created paths"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [ -z "$DESCRIPTION" ]; then
    log_error "Missing required argument: --description"
    exit 1
fi

# ==============================================================================
# Main Logic
# ==============================================================================

REPO_ROOT=$(get_repo_root)

# Calculate feature number
if [ -z "$FEATURE_NUMBER" ]; then
    HIGHEST=$(get_highest_feature_number "$REPO_ROOT")
    FEATURE_NUMBER=$((HIGHEST + 1))
fi

# Format as 3-digit padded
FEATURE_NUMBER=$(printf "%03d" "$((10#$FEATURE_NUMBER))")

# Generate branch name from description
BRANCH_SUFFIX=$(generate_branch_name "$DESCRIPTION")
BRANCH_NAME="${FEATURE_NUMBER}-${BRANCH_SUFFIX}"

# Create feature directory
FEATURE_DIR="$REPO_ROOT/$SPECS_DIR/$BRANCH_NAME"

if [ -d "$FEATURE_DIR" ]; then
    log_error "Feature directory already exists: $FEATURE_DIR"
    exit 1
fi

mkdir -p "$FEATURE_DIR"
mkdir -p "$FEATURE_DIR/contracts"
mkdir -p "$FEATURE_DIR/checklists"
mkdir -p "$FEATURE_DIR/spikes"

# ==============================================================================
# Create Artifact Templates
# ==============================================================================

# spec.md - Requirements specification
cat > "$FEATURE_DIR/spec.md" << 'SPEC_EOF'
# Feature Specification

## Overview

<!-- Brief description of the feature -->

## Goals

<!-- What this feature aims to achieve -->

## Non-Goals

<!-- Explicitly out of scope -->

## User Stories

<!-- As a [user type], I want [goal] so that [benefit] -->

## Requirements

### Functional Requirements

<!-- FR-001: Description -->

### Non-Functional Requirements

<!-- NFR-001: Description -->

## Success Criteria

<!-- How we know this feature is complete -->

## Open Questions

<!-- Unresolved decisions -->
SPEC_EOF

# plan.md - Implementation design
cat > "$FEATURE_DIR/plan.md" << 'PLAN_EOF'
# Implementation Plan

## Architecture

<!-- High-level design decisions -->

## Components

<!-- Key components and their responsibilities -->

## Data Model

<!-- Schema changes, new collections/tables -->

## API Design

<!-- Endpoints, request/response formats -->

## Dependencies

<!-- External services, packages, prerequisites -->

## Assumptions

<!-- Technical assumptions to validate in spike phase -->

## Risks

<!-- Known risks and mitigations -->
PLAN_EOF

# tasks.md - Implementation checklist
cat > "$FEATURE_DIR/tasks.md" << 'TASKS_EOF'
# Implementation Tasks

## Phase 1: Foundation

- [ ] T001: Task description
  - **Verify**: TEST | `yarn test path/to/test.ts`

## Phase 2: Core Implementation

- [ ] T002: Task description
  - **Verify**: API | POST /endpoint → 200

## Phase 3: Integration

- [ ] T003: Task description
  - **Verify**: E2E | Full flow test
TASKS_EOF

# research.md - Background research and references
cat > "$FEATURE_DIR/research.md" << 'RESEARCH_EOF'
# Research Notes

## Background

<!-- Context and motivation -->

## Prior Art

<!-- Existing solutions, alternatives considered -->

## References

<!-- Links to docs, specs, discussions -->

## Technical Investigation

<!-- Findings from research phase -->
RESEARCH_EOF

# data-model.md - Database schema documentation
cat > "$FEATURE_DIR/data-model.md" << 'DATAMODEL_EOF'
# Data Model

## Collections/Tables

### collection_name

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| _id | ObjectId | Yes | Primary key |

### Indexes

- `{ field: 1 }` - Description

## Relationships

<!-- How entities relate to each other -->

## Migrations

<!-- Required data migrations -->
DATAMODEL_EOF

# contracts/api.yaml - API contract template
cat > "$FEATURE_DIR/contracts/api.yaml" << 'CONTRACT_EOF'
# API Contract
# This file defines the expected API interface

openapi: 3.0.3
info:
  title: Feature API
  version: 1.0.0

paths:
  /api/endpoint:
    post:
      summary: Endpoint description
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                field:
                  type: string
              required:
                - field
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: object
                properties:
                  result:
                    type: string
        '400':
          description: Bad request
        '500':
          description: Internal error
CONTRACT_EOF

# checklists/requirements.md - Requirements checklist
cat > "$FEATURE_DIR/checklists/requirements.md" << 'CHECKLIST_EOF'
# Requirements Checklist

## Functional Requirements

- [ ] FR-001: Requirement description
- [ ] FR-002: Requirement description

## Non-Functional Requirements

- [ ] NFR-001: Performance target met
- [ ] NFR-002: Security review passed

## Acceptance Criteria

- [ ] All unit tests pass
- [ ] All E2E tests pass
- [ ] Type check passes
- [ ] Code review approved
- [ ] Documentation updated
CHECKLIST_EOF

# .workflow-state.json - Initial state
cat > "$FEATURE_DIR/$STATE_FILE_NAME" << STATE_EOF
{
    "version": 1,
    "featureId": "$BRANCH_NAME",
    "featureDir": "$SPECS_DIR/$BRANCH_NAME",
    "currentPhase": 0,
    "status": "initialized",
    "createdAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "updatedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "iterations": {
        "spike": 0,
        "implement": 0,
        "verify": 0,
        "review": 0
    },
    "completedTasks": [],
    "checkpoints": [],
    "errors": []
}
STATE_EOF

# ==============================================================================
# Check for constitution.md
# ==============================================================================

CONSTITUTION_PATH="$REPO_ROOT/.autopilot/memory/constitution.md"
HAS_CONSTITUTION="false"

if [ -f "$CONSTITUTION_PATH" ]; then
    HAS_CONSTITUTION="true"
    log_info "Found constitution at: $CONSTITUTION_PATH"
fi

# ==============================================================================
# Output
# ==============================================================================

log_success "Created feature directory: $FEATURE_DIR"

# Output JSON result
cat << EOF
{
    "status": "success",
    "featureId": "$BRANCH_NAME",
    "featureNumber": "$FEATURE_NUMBER",
    "branchName": "$BRANCH_NAME",
    "featureDir": "$SPECS_DIR/$BRANCH_NAME",
    "absolutePath": "$FEATURE_DIR",
    "artifacts": {
        "spec": "$SPECS_DIR/$BRANCH_NAME/spec.md",
        "plan": "$SPECS_DIR/$BRANCH_NAME/plan.md",
        "tasks": "$SPECS_DIR/$BRANCH_NAME/tasks.md",
        "research": "$SPECS_DIR/$BRANCH_NAME/research.md",
        "dataModel": "$SPECS_DIR/$BRANCH_NAME/data-model.md",
        "state": "$SPECS_DIR/$BRANCH_NAME/$STATE_FILE_NAME",
        "contracts": "$SPECS_DIR/$BRANCH_NAME/contracts/",
        "checklists": "$SPECS_DIR/$BRANCH_NAME/checklists/"
    },
    "constitution": {
        "exists": $HAS_CONSTITUTION,
        "path": ".autopilot/memory/constitution.md"
    }
}
EOF
