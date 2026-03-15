---
description: End-to-end feature implementation orchestrator. Takes a plan file and drives through spike (assumption validation) → specify → plan → tasks → analyze → implement → verify (prove tasks work) → review with automated iteration loops, human checkpoints for significant deviations, and team spawning.

# Evaluation test cases for skill-creator
evals:
  # Critical path tests
  - prompt: "/autopilot:full test/fixtures/simple-plan.md"
    expect: |
      - Creates spec.md with requirements from plan
      - Creates plan.md with technical architecture
      - Creates tasks.md with ordered task list
      - Creates .workflow-state.json with correct schema
      - All phases execute: spike → specify → plan → tasks → analyze → implement → verify → review
      - Final status is "done" or workflow state shows progress

  - prompt: "/autopilot:full --resume"
    expect: |
      - Reads existing .workflow-state.json
      - Continues from saved phase (not restart)
      - Preserves completed work
      - Updates timestamps on resume

  # Error handling tests
  - prompt: "/autopilot:full nonexistent-file.md"
    expect: |
      - Returns error about file not found
      - Does NOT crash or hang
      - Suggests correct usage

  - prompt: "/autopilot:full"
    expect: |
      - Shows usage instructions
      - Mentions <plan-file> argument
      - Mentions --resume option

  # Spike phase tests
  - prompt: "/autopilot:full test/fixtures/risky-assumptions-plan.md"
    expect: |
      - Extracts risky assumptions from plan
      - Creates spike experiments
      - Runs spikes in parallel (team spawn)
      - Creates spike-report.md
      - Checkpoints if significant deviation found

  # Verification tests
  - prompt: "/autopilot:full test/fixtures/simple-plan.md"
    expect: |
      - Runs existing test suite (yarn test or npm test)
      - Runs E2E tests if playwright/cypress configured
      - Runs TypeScript type check
      - Halts if tests fail after retry limit
      - Creates verification-report.md

  # Review tests
  - prompt: "/autopilot:full test/fixtures/simple-plan.md"
    expect: |
      - Spawns 5 reviewer agents in parallel
      - Reviews: functional, architecture, contract, quality, coverage
      - Creates review-report.md
      - Auto-fixes critical issues
      - Halts if critical issues remain after limit

  # State persistence tests
  - prompt: "/autopilot:full test/fixtures/simple-plan.md"
    expect: |
      - Updates .workflow-state.json after each phase
      - Tracks iterations count
      - Records completed tasks
      - Stores timestamps (started, lastUpdated, phaseStarted)

  # Watchdog tests
  - prompt: "/autopilot:full test/fixtures/complex-plan.md"
    expect: |
      - Spawns background watchdog agent
      - Watchdog monitors heartbeat
      - Heartbeat updated every phase
      - Recovery triggered if stale > 5 minutes
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
    "spike": 0,
    "analyze": 0,
    "clarify": 0,
    "verify": 0,
    "review": 0,
    "workflow": 0
  },
  "spikeResults": [],
  "checkpointDecisions": [],
  "verificationResults": [],
  "taskRetries": {},
  "limits": {
    "analyze": 5,
    "clarify": 3,
    "implementTaskRetry": 3,
    "verify": 3,
    "verifyRetry": 2,
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

### Phase 2: Spike (Assumption Validation)

**Purpose**: Validate risky assumptions from the user's plan BEFORE committing to implementation. Run experiments, score findings, checkpoint if significant deviations.

1. Update state: `phase: "spike"`

2. **Extract Assumptions**: Parse plan file for risky assumptions:
   - External API dependencies (endpoints, auth, rate limits)
   - Package/library capabilities ("library X supports feature Y")
   - Integration points ("service A can connect to service B")
   - Performance assumptions ("this approach handles N requests/sec")
   - Data format assumptions ("API returns JSON with field X")

3. **Generate Spike Tasks**: For each assumption, create a spike experiment:
   ```
   spikes/
   ├── spike-001-api-validation.md
   ├── spike-002-package-eval.md
   └── spike-003-integration-test.md
   ```

4. **Run Spikes in Parallel** (team spawn):
   ```
   SPAWN TEAM: Multiple agents, each validating one assumption
   All agents run with: run_in_background: true, isolation: "worktree"

   FOR each spike:
       Agent(
           description: "Spike: {assumption_summary}",
           prompt: |
               You are validating a technical assumption.

               ## Assumption
               {assumption_description}

               ## Experiment
               1. Write minimal throwaway code to test this assumption
               2. Execute and observe results
               3. Document: CONFIRMED | REFUTED | PARTIAL

               ## Output Format
               ```json
               {
                   "assumption": "{description}",
                   "status": "CONFIRMED|REFUTED|PARTIAL",
                   "confidence": 0-100,
                   "evidence": "{what you observed}",
                   "impact": "LOW|MEDIUM|HIGH",
                   "deviation_type": "none|param_change|tech_swap|arch_change|blocker",
                   "proposed_change": "{if refuted, what to do instead}",
                   "code_location": "{path to spike code}"
               }
               ```

               ## Constraints
               - Throwaway code only (branch/worktree)
               - Max 15 minutes per spike
               - No production changes
       )
   ```

5. **Aggregate Spike Results**: Collect all spike findings into `spike-report.md`

6. **Classify Deviations**:

   | Deviation Type | Confidence | Impact | Action |
   |----------------|------------|--------|--------|
   | `none` | ≥85% | Any | Auto-continue |
   | `param_change` | ≥85% | LOW | Auto-update plan, continue |
   | `tech_swap` | Any | MEDIUM | **CHECKPOINT** |
   | `arch_change` | Any | HIGH | **CHECKPOINT** |
   | `blocker` | Any | BLOCKER | **HALT** |

7. **Auto-Continue Path** (confidence ≥85% AND impact=LOW):
   ```
   Log: "Spike validated: {assumption} ✓"
   Update original-plan.md → validated-plan.md with minor adjustments
   Continue to Phase 3: Specify
   ```

8. **Checkpoint Path** (confidence <85% OR impact≥MEDIUM):
   ```
   Save state: phase: "spike_checkpoint"

   Display to user:
   ┌─────────────────────────────────────────────────────────────┐
   │  SPIKE CHECKPOINT                                          │
   │                                                             │
   │  Assumption: "Redis supports feature X"                    │
   │  Finding: Redis does NOT support X                         │
   │  Confidence: 95%                                           │
   │  Impact: MEDIUM (tech swap required)                       │
   │                                                             │
   │  Proposed Change:                                          │
   │    Switch to Memcached (supports X natively)               │
   │    +1 new dependency, ~2 additional tasks                  │
   │                                                             │
   │  Evidence:                                                 │
   │    > spike code at: spikes/spike-002/test.ts               │
   │    > Redis SCAN command lacks filter capability            │
   │                                                             │
   │  Options:                                                  │
   │    [1] Approve proposed change                             │
   │    [2] Provide alternative approach                        │
   │    [3] Abort workflow                                      │
   └─────────────────────────────────────────────────────────────┘

   WAIT for user input (this is the ONLY blocking prompt in the workflow)

   IF user selects [1] (Approve):
       Apply proposed change to validated-plan.md
       Log: "User approved: {change_description}"
       Continue to Phase 3: Specify

   IF user selects [2] (Alternative):
       Read user's alternative approach
       Update validated-plan.md with user's approach
       Re-run affected spike if needed
       Continue to Phase 3: Specify

   IF user selects [3] (Abort):
       Update state: status: "aborted", reason: "User aborted at spike checkpoint"
       Log: "Workflow aborted. State preserved for resume."
       EXIT
   ```

9. **HALT Path** (blocker found):
   ```
   Display:
   ┌─────────────────────────────────────────────────────────────┐
   │  SPIKE BLOCKER - CANNOT PROCEED                            │
   │                                                             │
   │  Assumption: "External API provides endpoint /v2/data"     │
   │  Finding: API endpoint does not exist                      │
   │  Confidence: 100%                                          │
   │  Impact: BLOCKER                                           │
   │                                                             │
   │  This blocks the core goal of the feature.                 │
   │  Manual intervention required.                             │
   │                                                             │
   │  Suggestions:                                               │
   │    - Contact API provider                                  │
   │    - Find alternative data source                          │
   │    - Revise feature scope                                  │
   └─────────────────────────────────────────────────────────────┘

   Update state: status: "blocked", blocker: {description}
   EXIT
   ```

10. **Spike Artifacts**:
    ```
    specs/NNN-feature/
    ├── original-plan.md      # User's input (never modified)
    ├── spike-report.md       # All spike findings
    ├── validated-plan.md     # Plan with validated/adjusted assumptions
    └── spikes/               # Spike experiment code (throwaway)
        ├── spike-001/
        ├── spike-002/
        └── ...
    ```

11. Update state: mark spike complete, proceed with `validated-plan.md`

### Phase 3: Specify

1. Update state: `phase: "specify"`
2. Execute `/autopilot:specify` with **validated-plan.md** content (not original)
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

### Phase 8: Verify (Prove Tasks Work)

**Purpose**: Prove each task ACTUALLY works through real execution. Code written ≠ task complete.

1. Update state: `phase: "verify"`

2. **Parse Verification Criteria**: Extract from tasks.md the `Verify:` line for each task:
   ```markdown
   - [X] T001: Add login button to navbar
     - **Verify**: UI | Click login button → modal appears

   - [X] T002: Create /api/auth endpoint
     - **Verify**: API | POST /api/auth {email, pass} → 200 + token

   - [X] T003: Add user to database on signup
     - **Verify**: DB | After signup, query users table → new row exists
   ```

3. **Classify Verification Method**:

   | Task Type | Indicator | Verification Tool | Method |
   |-----------|-----------|-------------------|--------|
   | UI | `Verify: UI \|` | Playwright MCP | Browser automation |
   | API | `Verify: API \|` | fetch/curl | HTTP request |
   | CLI | `Verify: CLI \|` | Bash | Execute command |
   | DB | `Verify: DB \|` | DB client | Query database |
   | Test | `Verify: TEST \|` | vitest/jest | Run test file |
   | Integration | `Verify: E2E \|` | Playwright MCP | Full flow test |

4. **Run Verifications in Parallel** (team spawn by type):

   ```
   # Group tasks by verification type for efficient execution
   ui_tasks = [t for t in tasks if t.verify_type == "UI"]
   api_tasks = [t for t in tasks if t.verify_type == "API"]
   # ... etc

   # Spawn verification agents - one per task type group
   # UI tasks MUST use Playwright MCP browser tools

   FOR each task:
       Agent(
           description: "Verify: {task_id}",
           run_in_background: true,
           prompt: |
               You are verifying task {task_id} ACTUALLY works.

               ## Task
               {task_description}

               ## Verification Criteria
               Type: {verify_type}
               Expected: {expected_behavior}

               ## Instructions by Type

               ### If UI verification:
               Use Playwright MCP browser tools:
               1. browser_navigate to the relevant page (localhost or deployed URL)
               2. browser_snapshot to see current state
               3. browser_click / browser_fill_form as needed
               4. browser_snapshot to capture result
               5. Compare against expected behavior

               ### If API verification:
               1. Make actual HTTP request using fetch or curl
               2. Capture response status, headers, body
               3. Compare against expected response

               ### If CLI verification:
               1. Execute the command via Bash
               2. Capture stdout, stderr, exit code
               3. Compare against expected output

               ### If DB verification:
               1. Connect to database
               2. Execute query
               3. Verify expected state exists

               ### If TEST verification:
               1. Run the specific test file/suite
               2. Capture pass/fail results
               3. All tests must pass

               ## Output Format
               ```json
               {
                   "task_id": "{task_id}",
                   "status": "VERIFIED|FAILED",
                   "verify_type": "{type}",
                   "evidence": {
                       "method": "{what was executed}",
                       "command_or_url": "{actual command/URL}",
                       "expected": "{expected outcome}",
                       "actual": "{actual outcome}",
                       "screenshot_path": "{if UI, path to screenshot}",
                       "response_body": "{if API, response content}",
                       "stdout": "{if CLI, command output}"
                   },
                   "match": true|false,
                   "failure_reason": "{if failed, why}"
               }
               ```

               ## Constraints
               - MUST execute real verification (no assumptions)
               - MUST capture evidence (screenshots, outputs, responses)
               - For UI: Use Playwright MCP tools (browser_navigate, browser_click, etc.)
               - For API: Make actual HTTP requests
               - For CLI: Execute actual commands
               - Report honestly - failed verification is valuable information
       )
   ```

5. **Aggregate Verification Results**:

   ```
   FOR each verification result:
       IF status == "VERIFIED":
           Mark task as VERIFIED in tasks.md: [X] → [V]
           Log: "✓ {task_id} verified"
           Store evidence in verification-report.md

       IF status == "FAILED":
           INCREMENT taskRetries[task_id]
           Log: "✗ {task_id} failed verification: {failure_reason}"

           IF taskRetries[task_id] < limits.verifyRetry:
               # Re-implement the task with failure context
               Spawn fix agent with:
                   - Original task description
                   - Verification failure reason
                   - Evidence of what went wrong
               THEN re-verify
           ELSE:
               Mark task as VERIFICATION_FAILED in state
               Add to verification-report.md as unresolved
   ```

6. **Generate Verification Report** (`verification-report.md`):

   ```markdown
   # Verification Report: {feature_name}

   **Date**: {timestamp}
   **Tasks Verified**: {verified_count}/{total_count}

   ## Summary

   | Status | Count |
   |--------|-------|
   | VERIFIED | {n} |
   | FAILED | {n} |
   | SKIPPED | {n} |

   ## Verified Tasks

   | Task | Type | Evidence |
   |------|------|----------|
   | T001 | UI | [screenshot](./verify/T001.png) |
   | T002 | API | 200 OK, token returned |
   | T003 | DB | Row exists: id=123 |

   ## Failed Tasks

   | Task | Type | Expected | Actual | Attempts |
   |------|------|----------|--------|----------|
   | T004 | UI | Modal appears | Button not found | 3 |

   ## Evidence Artifacts

   ./verify/
   ├── T001-screenshot.png
   ├── T002-response.json
   └── T003-query-result.txt
   ```

7. **Run Existing Test Suites** (regression check):

   ```
   # CRITICAL: Ensure we haven't broken existing functionality

   # Step 1: Run unit/integration tests
   test_result = Bash("yarn test" or "npm test" or project's test command)

   IF test_result.exit_code != 0:
       Log: "✗ Existing tests failed"
       Parse failed tests from output
       FOR each failed test:
           Add to verification-report.md as REGRESSION

       # Attempt to fix regressions
       INCREMENT iterations.verify
       IF iterations.verify < limits.verify:
           Spawn fix agents for each regression
           Re-run tests
       ELSE:
           HALT: "Regression tests failed after {limit} attempts"
           EXIT

   Log: "✓ Unit/integration tests passed"

   # Step 2: Run E2E tests (if they exist)
   IF project has E2E tests (playwright.config.ts, cypress.config.ts, etc.):
       e2e_result = Bash("yarn test:e2e" or "npx playwright test" or project's E2E command)

       IF e2e_result.exit_code != 0:
           Log: "✗ E2E tests failed"
           Parse failed E2E tests
           FOR each failed test:
               Add to verification-report.md as E2E_REGRESSION

           INCREMENT iterations.verify
           IF iterations.verify < limits.verify:
               Spawn fix agents for E2E failures
               Re-run E2E tests
           ELSE:
               HALT: "E2E tests failed after {limit} attempts"
               EXIT

       Log: "✓ E2E tests passed"

   # Step 3: Type checking (if TypeScript)
   IF project uses TypeScript:
       type_result = Bash("yarn tsc --noEmit" or "npx tsc --noEmit")

       IF type_result.exit_code != 0:
           Log: "✗ Type errors found"
           Add type errors to verification-report.md
           # Type errors are blockers
           HALT: "TypeScript compilation failed"
           EXIT

       Log: "✓ Type check passed"

   # Step 4: Linting (if configured)
   IF project has linter (eslint, biome, etc.):
       lint_result = Bash("yarn lint" or project's lint command)

       IF lint_result.exit_code != 0:
           Log: "⚠ Lint warnings/errors"
           # Try auto-fix
           Bash("yarn lint --fix")
           # Re-check
           lint_result = Bash("yarn lint")
           IF lint_result.exit_code != 0:
               Add lint errors to verification-report.md as warnings
               # Don't block on lint, but report
   ```

8. **Verification Gate**:

   ```
   # All gates must pass:
   # 1. Task verifications (UI/API/CLI/DB/TEST)
   # 2. Existing test suite
   # 3. E2E tests
   # 4. Type check

   verified_ratio = verified_count / total_verifiable_count
   tests_passed = unit_tests_passed AND e2e_tests_passed AND type_check_passed

   IF NOT tests_passed:
       HALT: "Existing tests or type check failed"
       EXIT

   IF verified_ratio >= 0.95:
       Log: "Verification passed ({verified_count}/{total_count})"
       Continue to Phase 9: Review

   IF verified_ratio >= 0.80:
       Log: "Verification mostly passed ({verified_count}/{total_count})"
       Log: "Proceeding with {failed_count} unverified tasks"
       Continue to Phase 9: Review (with warnings)

   IF verified_ratio < 0.80:
       Log: "Verification failed ({verified_count}/{total_count})"
       INCREMENT iterations.verify
       IF iterations.verify < limits.verify:
           GOTO Phase 7 (re-implement failed tasks)
       ELSE:
           HALT: "Verification loop limit reached"
           EXIT
   ```

8. **State Updates**:
   ```json
   {
       "iterations": {
           "verify": 0
       },
       "limits": {
           "verify": 3,
           "verifyRetry": 2
       },
       "verificationResults": []
   }
   ```

### Phase 9: Review (Team Spawn)

1. Update state: `phase: "review"`
2. Log: "Verification complete. Starting code review..."

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

### Phase 10: Completion

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
