---
description: End-to-end feature implementation orchestrator. Takes a plan file and drives through specify → plan → tasks → analyze → implement → review with automated iteration loops and team spawning.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Overview

This is a **meta-orchestrator** that drives the complete autopilot workflow from plan to shipped code. It handles:

- Sequential phase execution with dependency ordering
- Automated iteration loops with bounded retries
- Team spawning for parallel implementation and review
- State persistence for resume after interruption
- Audit trail via persisted reports

## Input Modes

Parse `$ARGUMENTS` to determine mode:

1. **New feature**: `<path-to-plan-file>` — Start fresh from a plan file
2. **Resume**: `--resume` — Continue from `.workflow-state.json`

If `$ARGUMENTS` is empty, check if `.workflow-state.json` exists in current feature dir:
- If exists: Prompt user "Resume from saved state? (yes/no)"
- If not: ERROR "Usage: /autopilot.full <plan-file> or /autopilot.full --resume"

## State Management

### State File Location

```
specs/NNN-feature/.workflow-state.json
```

### State Schema

```json
{
  "version": 1,
  "feature": "NNN-feature-name",
  "planFile": "/absolute/path/to/original/plan.md",
  "phase": "analyze",
  "status": "in_progress",
  "iterations": {
    "analyze": 0,
    "clarify": 0,
    "review": 0,
    "workflow": 0
  },
  "taskRetries": {},
  "limits": {
    "analyze": 5,
    "clarify": 3,
    "implementTaskRetry": 3,
    "review": 5,
    "workflow": 3
  },
  "issues": [],
  "completedTasks": [],
  "timestamps": {
    "started": "2026-03-15T10:00:00Z",
    "lastUpdated": "2026-03-15T10:30:00Z",
    "phaseStarted": "2026-03-15T10:25:00Z"
  },
  "agents": {
    "spawned": 0,
    "completed": 0,
    "failed": 0
  }
}
```

### State Transitions

Update state file **after each phase completion** and **before each phase start**. This enables accurate resume.

## Execution Flow

### Phase 1: Initialize

1. Parse input mode (new vs resume)
2. If new:
   - Read plan file content
   - Run `.specify/scripts/bash/create-new-feature.sh` to create feature branch (extract short name from plan)
   - Initialize `.workflow-state.json`
3. If resume:
   - Load `.workflow-state.json`
   - Validate state integrity
   - Report current position and resume

### Phase 2: Specify

1. Update state: `phase: "specify"`
2. Execute `/autopilot.specify` with plan file content as arguments
3. Validate outputs exist: `spec.md`, `checklists/requirements.md`
4. Update state: mark specify complete

### Phase 3: Plan

1. Update state: `phase: "plan"`
2. Execute `/autopilot.plan`
3. Validate outputs: `plan.md`, `research.md` (optional: `data-model.md`, `contracts/*`, `quickstart.md`)
4. Update state: mark plan complete

### Phase 4: Tasks

1. Update state: `phase: "tasks"`
2. Execute `/autopilot.tasks`
3. Validate output: `tasks.md` with proper format
4. Parse task count and store in state
5. Update state: mark tasks complete

### Phase 5: Analyze Loop

```
iterations.analyze = 0
WHILE iterations.analyze < limits.analyze:
    1. Update state: phase: "analyze", increment iterations.analyze
    2. Execute /autopilot.analyze
    3. Parse analysis report for issues
    4. Persist analysis-report.md (versioned: analysis-report-v{N}.md)

    IF no CRITICAL or HIGH issues:
        BREAK → proceed to Phase 6

    IF CRITICAL issues found:
        5. Display issues to user
        6. For each issue, attempt automated fix OR prompt user
        7. Re-run affected phases (specify/plan/tasks) as needed
        8. Continue loop

IF iterations.analyze >= limits.analyze AND issues remain:
    HALT with error: "Analyze loop exceeded {limit} iterations. {N} issues remain."
    Display issues and suggest manual intervention
    Save state for resume
    EXIT
```

### Phase 6: Clarify Review

1. Update state: `phase: "clarify"`
2. Load original plan file (from `state.planFile`)
3. Compare all autopilot artifacts against original plan intent:
   - spec.md captures all requirements from plan?
   - plan.md architecture aligns with plan constraints?
   - tasks.md covers all functionality?
4. Execute `/autopilot.clarify` if gaps found
5. Track if any changes made to spec.md

```
IF changes made to spec.md:
    INCREMENT iterations.clarify
    IF iterations.clarify < limits.clarify:
        GOTO Phase 5 (re-analyze)
    ELSE:
        WARN "Clarify loop limit reached, proceeding with current state"
```

### Phase 7: Implement (Team Spawn)

1. Update state: `phase: "implement"`
2. Parse `tasks.md` to extract all tasks
3. Group tasks by phase and respect dependencies
4. Display task summary (informational only, no blocking prompt)

**Parallel Execution Strategy**:

```
FOR each phase in tasks.md (sequential by phase):
    # Step 1: Build parallel batches from tasks with [P] marker
    parallel_tasks = [t for t in phase.tasks if t.has_marker("[P]") and t.dependencies_met()]
    sequential_tasks = [t for t in phase.tasks if not t.has_marker("[P]") or not t.dependencies_met()]

    # Step 2: Execute ALL parallel tasks simultaneously as a team
    IF parallel_tasks.length > 0:
        SPAWN TEAM: Use SINGLE message with MULTIPLE Agent tool calls
        All agents run with: run_in_background: true, isolation: "worktree"

        # Example: 5 parallel tasks = 5 agents spawned in ONE message
        parallel_agents = []
        FOR each task in parallel_tasks:
            parallel_agents.append(Agent(
                description: "Implement {task_id}",
                subagent_type: "general-purpose",
                isolation: "worktree",
                run_in_background: true,
                prompt: <task_prompt>
            ))

        # CRITICAL: Spawn ALL in single message, then wait
        INVOKE all parallel_agents simultaneously
        WAIT for all to complete (system notifies on completion)
        AGGREGATE results

    # Step 3: Execute sequential tasks one at a time
    FOR each task in sequential_tasks:
        Spawn single agent, WAIT for completion before next
```

**Agent Prompt Template**:

```
FOR each task:
    prompt: |
        You are implementing a single task for feature {feature_name}.

        ## Task
        {task_id}: {task_description}

        ## Context
        Read these files for context:
        - {FEATURE_DIR}/spec.md (requirements)
        - {FEATURE_DIR}/plan.md (architecture)
        - {FEATURE_DIR}/data-model.md (if exists)
        - {FEATURE_DIR}/contracts/* (if exists)

        ## Instructions
        1. Read the relevant context files
        2. Implement ONLY this task
        3. Follow the architecture in plan.md exactly
        4. Write tests if task specifies testing
        5. Report completion with files created/modified

        ## Constraints
        - Do NOT implement other tasks
        - Do NOT refactor unrelated code
        - Do NOT add features not specified
        - Ask if blocked, don't guess
```

**Result Handling**:

```
FOR each completed agent:
    Parse agent result:
        - Success: Mark task [X] in tasks.md, add to completedTasks
        - Failure:
            INCREMENT taskRetries[task_id]
            IF taskRetries[task_id] < limits.implementTaskRetry:
                Log failure reason
                Retry task with adjusted prompt (include error context)
            ELSE:
                Mark task as FAILED in state
                Log: "Task {task_id} failed after {limit} attempts"
                Continue (don't block entire feature)

    Update state after processing each result
```

5. After all tasks: Validate all tasks marked complete
6. If incomplete tasks remain: Report which failed and why

### Phase 8: Review (Team Spawn)

1. Update state: `phase: "review"`
2. Log: "Implementation complete. Starting code review..."

**Spawn 5 Review Agents in Parallel**:

| Agent | Focus | Artifacts |
|-------|-------|-----------|
| functional-reviewer | Requirements coverage | spec.md |
| architecture-reviewer | Design adherence | plan.md |
| contract-reviewer | API/schema compliance | contracts/*, data-model.md |
| quality-reviewer | Code quality, security | (code itself) |
| coverage-reviewer | Task completion, tests | tasks.md |

**SPAWN ALL 5 REVIEWERS IN SINGLE MESSAGE** (team spawn):

```
# CRITICAL: Use ONE message with 5 Agent tool calls to maximize parallelism
# All reviewers are read-only, so safe to run simultaneously

INVOKE simultaneously:
    Agent(description: "Review functional requirements", run_in_background: true, prompt: <functional_prompt>)
    Agent(description: "Review architecture adherence", run_in_background: true, prompt: <architecture_prompt>)
    Agent(description: "Review contract compliance", run_in_background: true, prompt: <contract_prompt>)
    Agent(description: "Review code quality", run_in_background: true, prompt: <quality_prompt>)
    Agent(description: "Review task coverage", run_in_background: true, prompt: <coverage_prompt>)

# System will notify as each completes - do NOT poll or sleep
WAIT for all 5 notifications
AGGREGATE results into review-report.md
```

**Reviewer Prompt Template**:

```
prompt: |
    You are the {reviewer_type} reviewer for feature {feature_name}.

    ## Your Focus
    {reviewer_specific_instructions}

    ## Artifacts to Review
    {artifact_list}

    ## Code to Review
    {list of files created/modified during implementation}

    ## Output Format
    Produce a structured review:

    ### Summary
    PASS | FAIL | WARN

    ### Findings
    For each issue:
    - Severity: CRITICAL | HIGH | MEDIUM | LOW
    - Location: file:line
    - Description: what's wrong
    - Recommendation: how to fix

    ### Checklist
    - [ ] or [X] for each review criterion

    Be thorough but fair. Flag real issues, not style preferences.
```

3. Aggregate review results into `review-report.md`:

```markdown
# Code Review Report: {feature_name}

**Date**: {timestamp}
**Reviewers**: 5 (functional, architecture, contract, quality, coverage)
**Overall**: PASS | FAIL

## Summary by Reviewer

| Reviewer | Status | Critical | High | Medium | Low |
|----------|--------|----------|------|--------|-----|
| functional | PASS | 0 | 0 | 1 | 2 |
| ... | ... | ... | ... | ... | ... |

## Critical Issues (blocking)

{list}

## High Issues (should fix)

{list}

## Recommendations

{aggregated recommendations}
```

4. Evaluate review outcome:

```
IF any CRITICAL issues:
    INCREMENT iterations.review
    IF iterations.review < limits.review:
        Log: "Critical issues found. Auto-fixing and re-reviewing..."
        FOR each critical issue:
            Spawn fix agent (automated)
        GOTO Phase 5 (full re-analyze after fixes)
    ELSE:
        HALT: "Review loop limit reached with critical issues"
        EXIT

IF only HIGH/MEDIUM/LOW:
    Log: "Non-critical issues found. Proceeding to completion (issues logged in review-report.md)"
    Proceed to completion
```

### Phase 9: Completion

1. Update state: `phase: "complete"`, `status: "done"`
2. Generate final summary:

```markdown
## autopilot.full Complete

**Feature**: {feature_name}
**Branch**: {branch_name}
**Duration**: {total_time}

### Artifacts
- specs/{feature}/spec.md
- specs/{feature}/plan.md
- specs/{feature}/tasks.md ({completed}/{total} tasks)
- specs/{feature}/review-report.md

### Code Changes
{list of files created/modified with line counts}

### Stats
| Metric | Value |
|--------|-------|
| Iterations (analyze) | {n} |
| Iterations (clarify) | {n} |
| Iterations (review) | {n} |
| Agents spawned | {n} |
| Tasks completed | {n}/{total} |

### Next Steps
- Review: `git diff main...HEAD`
- Commit: `/commit-and-push`
- PR: `gh pr create`
```

3. Auto-run `/commit-and-push` to finalize

## Error Handling

### Recoverable Errors

- Agent timeout: Retry once, then mark task failed and continue
- File not found: Check if phase was skipped, suggest re-running phase
- Parse error: Log detailed error, attempt fallback parsing

### Non-Recoverable Errors

- State file corrupted: Offer to reset from scratch or manual recovery
- Git conflicts: HALT and require manual resolution
- Iteration limit exceeded: HALT with full diagnostic

### Rollback Strategy

For implementation failures:
1. Track all files created/modified in state
2. On critical failure: Offer `git checkout -- {files}` to revert
3. Never auto-rollback without user confirmation

## Operating Principles

### Senior Staff Engineer Mindset

1. **Fail fast, fail informatively**: Don't retry blindly. Diagnose, report, suggest.
2. **Full automation**: No blocking prompts. Log progress, auto-fix issues, HALT only on unrecoverable errors.
3. **Audit trail**: Every decision persisted. Every iteration versioned.
4. **Idempotency**: Re-running a phase with same inputs should produce same outputs.
5. **Graceful degradation**: If optional artifact missing, proceed with warning, don't fail.
6. **Bounded iteration**: Hard limits prevent runaway loops burning tokens.
7. **Incremental progress**: Save state after each task, not just each phase.

### Parallelization Rules

**MAXIMIZE PARALLELISM** — spawn teams whenever possible:

| Scenario | Strategy | Why |
| -------- | -------- | --- |
| Tasks with [P] marker | Spawn ALL in single message | Different files, no conflicts |
| Review agents (5) | Spawn ALL in single message | Read-only, no conflicts |
| Fix agents | Sequential | May touch same files |
| Cross-phase tasks | Sequential by phase | Phase dependencies |
| Retry after failure | Single agent | Needs error context |

**Team Spawn Pattern** (use this exact pattern):

```text
# CORRECT: Single message, multiple agents = true parallelism
Message 1:
  - Agent(task: T005, run_in_background: true)
  - Agent(task: T006, run_in_background: true)
  - Agent(task: T007, run_in_background: true)
→ All 3 start simultaneously

# WRONG: Multiple messages = sequential execution
Message 1: Agent(task: T005) → wait
Message 2: Agent(task: T006) → wait
Message 3: Agent(task: T007) → wait
→ 3x slower
```

### Context Window Management

- Each spawned agent gets **minimal context**: only artifacts relevant to its task
- Never dump entire codebase into agent prompt
- Use file paths and let agent read what it needs
- For large features: Consider phase-based checkpoints with `/clear` between phases

## Constraints

- Maximum 50 agents spawned per `/autopilot.full` invocation
- Maximum 3 hours wall-clock time (warn at 2 hours)
- State file max 1MB (truncate old issues if exceeds)
- If tasks.md has >30 tasks: Require user confirmation before implementation

## Context

$ARGUMENTS
