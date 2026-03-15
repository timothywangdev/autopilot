---
description: Execute the implementation planning workflow using the plan template to generate design artifacts.
handoffs:
  - label: Create Tasks
    agent: autopilot.tasks
    prompt: Break the plan into tasks
    send: true
  - label: Create Checklist
    agent: autopilot.checklist
    prompt: Create a checklist for the following domain...

evals:
  - prompt: "/autopilot:plan"
    setup: |
      mkdir -p .specify/templates .specify/memory .specify/scripts/bash specs/001-comments
      cat > specs/001-comments/spec.md << 'EOF'
      # Feature: User Comments
      ## Requirements
      - Users can post comments on articles
      - Comments have author, content, timestamp
      - Comments can be nested (replies)
      EOF
      cat > .specify/templates/plan-template.md << 'EOF'
      # Implementation Plan
      ## Technical Context
      ## Architecture
      ## Phases
      EOF
      cat > .specify/memory/constitution.md << 'EOF'
      # Project Constitution
      EOF
      cat > .specify/scripts/bash/setup-plan.sh << 'EOF'
      #!/bin/bash
      echo '{"FEATURE_SPEC": "specs/001-comments/spec.md", "IMPL_PLAN": "specs/001-comments/plan.md", "SPECS_DIR": "specs/001-comments", "BRANCH": "001-comments"}'
      EOF
      chmod +x .specify/scripts/bash/setup-plan.sh
      git init 2>/dev/null || true
      git checkout -b 001-comments 2>/dev/null || true
    expect: |
      - Creates plan.md in specs/001-comments directory
      - Plan contains architecture or implementation details
      - Plan references comment functionality from spec

  - prompt: "/autopilot:plan"
    setup: |
      mkdir -p .specify/templates .specify/memory .specify/scripts/bash specs/001-payments
      cat > specs/001-payments/spec.md << 'EOF'
      # Feature: Payment Integration
      ## Requirements
      - Stripe integration for payments
      - Store payment history
      - Handle refunds
      EOF
      cat > .specify/templates/plan-template.md << 'EOF'
      # Implementation Plan
      ## Technical Context
      ## Architecture
      ## Data Model
      ## Phases
      EOF
      cat > .specify/memory/constitution.md << 'EOF'
      # Project Constitution
      EOF
      cat > .specify/scripts/bash/setup-plan.sh << 'EOF'
      #!/bin/bash
      echo '{"FEATURE_SPEC": "specs/001-payments/spec.md", "IMPL_PLAN": "specs/001-payments/plan.md", "SPECS_DIR": "specs/001-payments", "BRANCH": "001-payments"}'
      EOF
      chmod +x .specify/scripts/bash/setup-plan.sh
      git init 2>/dev/null || true
      git checkout -b 001-payments 2>/dev/null || true
    expect: |
      - Creates plan.md with payment architecture
      - Creates data-model.md with payment/transaction schema
      - Plan addresses payment security considerations

  - prompt: "/autopilot:plan"
    setup: |
      mkdir -p .specify/scripts/bash
      cat > .specify/scripts/bash/setup-plan.sh << 'EOF'
      #!/bin/bash
      echo '{"error": "spec.md not found"}'
      exit 1
      EOF
      chmod +x .specify/scripts/bash/setup-plan.sh
    expect: |
      - Shows error about spec.md not found
      - Suggests running /autopilot:specify first
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

1. **Setup**: Run `.specify/scripts/bash/setup-plan.sh --json` from repo root and parse JSON for FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, BRANCH. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load context**: Read FEATURE_SPEC and `.specify/memory/constitution.md`. Load IMPL_PLAN template (already copied).

3. **Execute plan workflow**: Follow the structure in IMPL_PLAN template to:
   - Fill Technical Context (mark unknowns as "NEEDS CLARIFICATION")
   - Fill Constitution Check section from constitution
   - Evaluate gates (ERROR if violations unjustified)
   - Phase 0: Generate research.md (resolve all NEEDS CLARIFICATION)
   - Phase 1: Generate data-model.md, contracts/, quickstart.md
   - Phase 1: Update agent context by running the agent script
   - Re-evaluate Constitution Check post-design

4. **Stop and report**: Command ends after Phase 2 planning. Report branch, IMPL_PLAN path, and generated artifacts.

## Phases

### Phase 0: Outline & Research

1. **Extract unknowns from Technical Context** above:
   - For each NEEDS CLARIFICATION → research task
   - For each dependency → best practices task
   - For each integration → patterns task

2. **Generate and dispatch research agents**:

   ```text
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen]
   - Alternatives considered: [what else evaluated]

**Output**: research.md with all NEEDS CLARIFICATION resolved

### Phase 1: Design & Contracts

**Prerequisites:** `research.md` complete

1. **Extract entities from feature spec** → `data-model.md`:
   - Entity name, fields, relationships
   - Validation rules from requirements
   - State transitions if applicable

2. **Generate API contracts** from functional requirements:
   - For each user action → endpoint
   - Use standard REST/GraphQL patterns
   - Output OpenAPI/GraphQL schema to `/contracts/`

3. **Agent context update**:
   - Run `.specify/scripts/bash/update-agent-context.sh claude`
   - These scripts detect which AI agent is in use
   - Update the appropriate agent-specific context file
   - Add only new technology from current plan
   - Preserve manual additions between markers

**Output**: data-model.md, /contracts/*, quickstart.md, agent-specific file

## Key rules

- Use absolute paths
- ERROR on gate failures or unresolved clarifications
