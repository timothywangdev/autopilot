---
description: Perform a non-destructive cross-artifact consistency and quality analysis across spec.md, plan.md, and tasks.md after task generation.

evals:
  - prompt: "/autopilot:analyze"
    setup: |
      mkdir -p .specify/memory .specify/scripts/bash specs/001-feature
      cat > specs/001-feature/spec.md << 'EOF'
      # Feature
      ## Requirements
      - Feature A
      - Feature B
      - Feature C
      EOF
      cat > specs/001-feature/plan.md << 'EOF'
      # Plan
      - Implement A
      - Implement B
      - Implement C
      EOF
      cat > specs/001-feature/tasks.md << 'EOF'
      # Tasks
      - [ ] T001: Implement Feature A
      - [ ] T002: Implement Feature B
      - [ ] T003: Implement Feature C
      EOF
      cat > .specify/memory/constitution.md << 'EOF'
      # Project Constitution
      EOF
      cat > .specify/scripts/bash/check-prerequisites.sh << 'EOF'
      #!/bin/bash
      echo '{"FEATURE_DIR": "specs/001-feature", "AVAILABLE_DOCS": ["spec.md", "plan.md", "tasks.md"]}'
      EOF
      chmod +x .specify/scripts/bash/check-prerequisites.sh
      git init 2>/dev/null || true
      git checkout -b 001-feature 2>/dev/null || true
    expect: |
      - Reports PASS or no critical issues for consistent artifacts
      - Coverage is 100% (all requirements have tasks)
      - Output contains analysis summary or metrics

  - prompt: "/autopilot:analyze"
    setup: |
      mkdir -p .specify/memory .specify/scripts/bash specs/001-incomplete
      cat > specs/001-incomplete/spec.md << 'EOF'
      # Feature
      ## Requirements
      - Feature A
      - Feature B
      - Feature C
      EOF
      cat > specs/001-incomplete/plan.md << 'EOF'
      # Plan
      - Implement all features
      EOF
      cat > specs/001-incomplete/tasks.md << 'EOF'
      # Tasks
      - [ ] T001: Implement Feature A
      - [ ] T002: Implement Feature B
      EOF
      cat > .specify/memory/constitution.md << 'EOF'
      # Project Constitution
      EOF
      cat > .specify/scripts/bash/check-prerequisites.sh << 'EOF'
      #!/bin/bash
      echo '{"FEATURE_DIR": "specs/001-incomplete", "AVAILABLE_DOCS": ["spec.md", "plan.md", "tasks.md"]}'
      EOF
      chmod +x .specify/scripts/bash/check-prerequisites.sh
      git init 2>/dev/null || true
      git checkout -b 001-incomplete 2>/dev/null || true
    expect: |
      - Detects missing requirement coverage for Feature C
      - Reports coverage gap in analysis output
      - Issue severity is HIGH or CRITICAL

  - prompt: "/autopilot:analyze"
    setup: |
      mkdir -p .specify/memory .specify/scripts/bash specs/001-conflict
      cat > specs/001-conflict/spec.md << 'EOF'
      # Feature
      ## Requirements
      - User authentication required
      EOF
      cat > specs/001-conflict/plan.md << 'EOF'
      # Plan
      - Use JWT tokens for stateless auth
      - Use session cookies for stateful auth
      EOF
      cat > specs/001-conflict/tasks.md << 'EOF'
      # Tasks
      - [ ] T001: Implement auth
      EOF
      cat > .specify/memory/constitution.md << 'EOF'
      # Project Constitution
      EOF
      cat > .specify/scripts/bash/check-prerequisites.sh << 'EOF'
      #!/bin/bash
      echo '{"FEATURE_DIR": "specs/001-conflict", "AVAILABLE_DOCS": ["spec.md", "plan.md", "tasks.md"]}'
      EOF
      chmod +x .specify/scripts/bash/check-prerequisites.sh
      git init 2>/dev/null || true
      git checkout -b 001-conflict 2>/dev/null || true
    expect: |
      - Detects ambiguity or conflict between JWT and session approaches
      - Reports inconsistency in authentication strategy
      - Suggests clarification or decision needed

  - prompt: "/autopilot:analyze"
    setup: |
      mkdir -p .specify/scripts/bash
      cat > .specify/scripts/bash/check-prerequisites.sh << 'EOF'
      #!/bin/bash
      echo '{"error": "Required artifacts not found"}'
      exit 1
      EOF
      chmod +x .specify/scripts/bash/check-prerequisites.sh
    expect: |
      - Shows error about missing artifacts
      - Lists which files (spec.md, plan.md, tasks.md) are missing
      - Suggests running /autopilot:specify, /autopilot:plan, or /autopilot:tasks
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Goal

Identify inconsistencies, duplications, ambiguities, and underspecified items across the three core artifacts (`spec.md`, `plan.md`, `tasks.md`) before implementation. This command MUST run only after `/autopilot.tasks` has successfully produced a complete `tasks.md`.

## Operating Constraints

**STRICTLY READ-ONLY**: Do **not** modify any files. Output a structured analysis report. Offer an optional remediation plan (user must explicitly approve before any follow-up editing commands would be invoked manually).

**Constitution Authority**: The project constitution (`.specify/memory/constitution.md`) is **non-negotiable** within this analysis scope. Constitution conflicts are automatically CRITICAL and require adjustment of the spec, plan, or tasks—not dilution, reinterpretation, or silent ignoring of the principle. If a principle itself needs to change, that must occur in a separate, explicit constitution update outside `/autopilot.analyze`.

## Execution Steps

### 1. Initialize Analysis Context

Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` once from repo root and parse JSON for FEATURE_DIR and AVAILABLE_DOCS. Derive absolute paths:

- SPEC = FEATURE_DIR/spec.md
- PLAN = FEATURE_DIR/plan.md
- TASKS = FEATURE_DIR/tasks.md

Abort with an error message if any required file is missing (instruct the user to run missing prerequisite command).
For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

### 2. Load Artifacts (Progressive Disclosure)

Load only the minimal necessary context from each artifact:

**From spec.md:**

- Overview/Context
- Functional Requirements
- Non-Functional Requirements
- User Stories
- Edge Cases (if present)

**From plan.md:**

- Architecture/stack choices
- Data Model references
- Phases
- Technical constraints

**From tasks.md:**

- Task IDs
- Descriptions
- Phase grouping
- Parallel markers [P]
- Referenced file paths

**From constitution:**

- Load `.specify/memory/constitution.md` for principle validation

### 3. Build Semantic Models

Create internal representations (do not include raw artifacts in output):

- **Requirements inventory**: Each functional + non-functional requirement with a stable key (derive slug based on imperative phrase; e.g., "User can upload file" → `user-can-upload-file`)
- **User story/action inventory**: Discrete user actions with acceptance criteria
- **Task coverage mapping**: Map each task to one or more requirements or stories (inference by keyword / explicit reference patterns like IDs or key phrases)
- **Constitution rule set**: Extract principle names and MUST/SHOULD normative statements

### 4. Detection Passes (Token-Efficient Analysis)

Focus on high-signal findings. Limit to 50 findings total; aggregate remainder in overflow summary.

#### A. Duplication Detection

- Identify near-duplicate requirements
- Mark lower-quality phrasing for consolidation

#### B. Ambiguity Detection

- Flag vague adjectives (fast, scalable, secure, intuitive, robust) lacking measurable criteria
- Flag unresolved placeholders (TODO, TKTK, ???, `<placeholder>`, etc.)

#### C. Underspecification

- Requirements with verbs but missing object or measurable outcome
- User stories missing acceptance criteria alignment
- Tasks referencing files or components not defined in spec/plan

#### D. Constitution Alignment

- Any requirement or plan element conflicting with a MUST principle
- Missing mandated sections or quality gates from constitution

#### E. Coverage Gaps

- Requirements with zero associated tasks
- Tasks with no mapped requirement/story
- Non-functional requirements not reflected in tasks (e.g., performance, security)

#### F. Inconsistency

- Terminology drift (same concept named differently across files)
- Data entities referenced in plan but absent in spec (or vice versa)
- Task ordering contradictions (e.g., integration tasks before foundational setup tasks without dependency note)
- Conflicting requirements (e.g., one requires Next.js while other specifies Vue)

### 5. Severity Assignment

Use this heuristic to prioritize findings:

- **CRITICAL**: Violates constitution MUST, missing core spec artifact, or requirement with zero coverage that blocks baseline functionality
- **HIGH**: Duplicate or conflicting requirement, ambiguous security/performance attribute, untestable acceptance criterion
- **MEDIUM**: Terminology drift, missing non-functional task coverage, underspecified edge case
- **LOW**: Style/wording improvements, minor redundancy not affecting execution order

### 6. Produce Compact Analysis Report

Output a Markdown report (no file writes) with the following structure:

## Specification Analysis Report

| ID | Category | Severity | Location(s) | Summary | Recommendation |
|----|----------|----------|-------------|---------|----------------|
| A1 | Duplication | HIGH | spec.md:L120-134 | Two similar requirements ... | Merge phrasing; keep clearer version |

(Add one row per finding; generate stable IDs prefixed by category initial.)

**Coverage Summary Table:**

| Requirement Key | Has Task? | Task IDs | Notes |
|-----------------|-----------|----------|-------|

**Constitution Alignment Issues:** (if any)

**Unmapped Tasks:** (if any)

**Metrics:**

- Total Requirements
- Total Tasks
- Coverage % (requirements with >=1 task)
- Ambiguity Count
- Duplication Count
- Critical Issues Count

### 7. Provide Next Actions

At end of report, output a concise Next Actions block:

- If CRITICAL issues exist: Recommend resolving before `/autopilot.implement`
- If only LOW/MEDIUM: User may proceed, but provide improvement suggestions
- Provide explicit command suggestions: e.g., "Run /autopilot.specify with refinement", "Run /autopilot.plan to adjust architecture", "Manually edit tasks.md to add coverage for 'performance-metrics'"

### 8. Offer Remediation

Ask the user: "Would you like me to suggest concrete remediation edits for the top N issues?" (Do NOT apply them automatically.)

## Operating Principles

### Context Efficiency

- **Minimal high-signal tokens**: Focus on actionable findings, not exhaustive documentation
- **Progressive disclosure**: Load artifacts incrementally; don't dump all content into analysis
- **Token-efficient output**: Limit findings table to 50 rows; summarize overflow
- **Deterministic results**: Rerunning without changes should produce consistent IDs and counts

### Analysis Guidelines

- **NEVER modify files** (this is read-only analysis)
- **NEVER hallucinate missing sections** (if absent, report them accurately)
- **Prioritize constitution violations** (these are always CRITICAL)
- **Use examples over exhaustive rules** (cite specific instances, not generic patterns)
- **Report zero issues gracefully** (emit success report with coverage statistics)

## Context

$ARGUMENTS
