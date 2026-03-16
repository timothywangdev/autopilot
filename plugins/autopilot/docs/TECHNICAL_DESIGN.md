# Autopilot Technical Design Document

## Overview

### Purpose

Autopilot is a Claude Code plugin that provides fully autonomous feature implementation. It transforms a high-level plan file into a complete, tested implementation through a 10-phase workflow orchestrated by a supervisor/worker pattern.

### Goals

1. **Autonomous execution**: Run a complete feature implementation from plan to production with minimal human intervention
2. **State persistence**: Survive interruptions and resume from the last known state
3. **Safety boundaries**: Prevent infinite loops and runaway execution through iteration limits
4. **Quality gates**: Validate artifacts at each phase before proceeding

### Key Features

- **Single entry point**: `/autopilot:loop plan.md` starts the entire workflow
- **Phase-based execution**: Each invocation executes exactly one phase, then persists state
- **Worker agents**: Spawns specialized subagents for spec generation, implementation, review
- **Artifact validation**: Automated checks for spec, plan, tasks, and state files
- **Exit signals**: Clean protocol for loop control (AUTOPILOT_COMPLETE, CONTINUE, HALTED)

---

## Architecture

### System Components Diagram

```
                                    ┌─────────────────────────────────────┐
                                    │              /loop                  │
                                    │        (interval timer)             │
                                    │                                     │
                                    │  Invokes /autopilot:_supervisor     │
                                    │  every N seconds/minutes            │
                                    │                                     │
                                    │  Monitors exit signals:             │
                                    │  - AUTOPILOT_COMPLETE → stop        │
                                    │  - AUTOPILOT_HALTED  → stop         │
                                    │  - AUTOPILOT_CONTINUE → repeat      │
                                    └─────────────────────────────────────┘
                                                      │
                                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           /autopilot:_supervisor                                │
│                                                                                 │
│  ┌──────────────────────┐    ┌──────────────────────┐    ┌────────────────┐    │
│  │   entry-point.sh     │───▶│   Phase Dispatcher   │───▶│ Worker Agents  │    │
│  │                      │    │                      │    │                │    │
│  │ - Detect action      │    │ - Phase 1-10 logic   │    │ - specify      │    │
│  │ - Read state file    │    │ - Call worker agents │    │ - plan         │    │
│  │ - Return JSON        │    │ - Validate outputs   │    │ - implement    │    │
│  └──────────────────────┘    └──────────────────────┘    │ - review       │    │
│                                        │                  └────────────────┘    │
│                                        ▼                                        │
│                        ┌──────────────────────────────────┐                     │
│                        │        update-state.sh           │                     │
│                        │                                  │                     │
│                        │  - Atomic JSON updates           │                     │
│                        │  - File locking                  │                     │
│                        │  - Phase advancement             │                     │
│                        └──────────────────────────────────┘                     │
└─────────────────────────────────────────────────────────────────────────────────┘
                                                      │
                                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              State & Artifacts                                  │
│                                                                                 │
│  specs/NNN-feature-name/                                                        │
│  ├── .workflow-state.json     # Persistent state (phase, status, iterations)   │
│  ├── original-plan.md         # Input plan (copied from user)                  │
│  ├── validated-plan.md        # Post-spike validated plan                      │
│  ├── spec.md                  # Generated specification                        │
│  ├── plan.md                  # Implementation plan                            │
│  ├── tasks.md                 # Task breakdown (T001, T002, ...)               │
│  ├── spike-report.md          # Assumption validation results                  │
│  ├── review-report.md         # Code review findings                           │
│  └── verification-report.md   # Test/build results                             │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
User Plan (.md)
      │
      ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Phase 1:    │     │  Phase 2:    │     │  Phase 3:    │
│  Initialize  │────▶│    Spike     │────▶│   Specify    │
│              │     │              │     │              │
│ - Validate   │     │ - Validate   │     │ - Generate   │
│ - Create dir │     │   assumptions│     │   spec.md    │
│ - Copy plan  │     │ - Write      │     │              │
│              │     │   spike-     │     │              │
│              │     │   report.md  │     │              │
└──────────────┘     └──────────────┘     └──────────────┘
                                                │
      ┌─────────────────────────────────────────┘
      ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Phase 4:    │     │  Phase 5:    │     │  Phase 6:    │
│    Plan      │────▶│    Tasks     │────▶│   Analyze    │
│              │     │              │     │              │
│ - Generate   │     │ - Generate   │     │ - Cross-     │
│   plan.md    │     │   tasks.md   │     │   artifact   │
│ - Update     │     │ - T001...    │     │   checks     │
│   context.md │     │   format     │     │              │
└──────────────┘     └──────────────┘     └──────────────┘
                                                │
      ┌─────────────────────────────────────────┘
      ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Phase 7:    │     │  Phase 8:    │     │  Phase 9:    │
│  Implement   │────▶│   Verify     │────▶│   Review     │
│   (loops)    │     │              │     │              │
│              │     │ - Run tests  │     │ - Code       │
│ - Execute    │◀────│ - Build      │◀────│   review     │
│   one task   │ fix │ - May go     │ fix │ - Security   │
│ - Mark [x]   │     │   back to 7  │     │   check      │
└──────────────┘     └──────────────┘     └──────────────┘
                                                │
      ┌─────────────────────────────────────────┘
      ▼
┌──────────────┐
│  Phase 10:   │
│  Complete    │
│              │
│ - Final      │
│   validation │
│ - Output     │
│   COMPLETE   │
└──────────────┘
```

### State Management

All workflow state is persisted in `.workflow-state.json`:

```json
{
  "version": 1,
  "feature": "NNN-feature-name",
  "featureDir": "specs/NNN-feature-name",
  "planFile": "/absolute/path/to/original-plan.md",
  "currentPhase": 7,
  "status": "in_progress",
  "iterations": {
    "spike": 1,
    "specify": 1,
    "plan": 1,
    "tasks": 1,
    "analyze": 1,
    "implement": 15,
    "verify": 0,
    "review": 0
  },
  "completedTasks": ["T001", "T002", "T003"],
  "timestamps": {
    "started": "2026-03-15T10:00:00Z",
    "lastUpdated": "2026-03-15T11:30:00Z",
    "completed": null
  }
}
```

**Key fields:**
- `currentPhase`: Which phase to execute (1-10)
- `status`: `in_progress` | `completed` | `halted`
- `iterations`: Retry counts per phase (safety limits apply)
- `completedTasks`: Task IDs marked complete in tasks.md

---

## Phase Workflow

### Phase 1: Initialize

**Purpose**: Set up the feature directory and validate prerequisites.

**Entry Conditions**:
- Plan file provided as argument
- `.autopilot/` directory exists (run `/autopilot:init` first)
- Templates available in `.autopilot/templates/`

**Execution**:
1. Pre-flight validation (check .autopilot exists, templates present)
2. Validate plan file path (security checks, within project)
3. Extract feature name from H1 heading or filename
4. Find next feature number (scans specs/ and git branches)
5. Create `specs/NNN-feature-name/` directory
6. Copy plan to `original-plan.md`
7. Initialize `.workflow-state.json` with phase=2

**Exit Conditions**:
- Feature directory created
- State file initialized
- Output: `AUTOPILOT_CONTINUE`

**Artifacts Produced**:
- `specs/NNN-feature-name/`
- `specs/NNN-feature-name/original-plan.md`
- `specs/NNN-feature-name/.workflow-state.json`

---

### Phase 2: Spike (Assumption Validation)

**Purpose**: Validate risky assumptions before implementation.

**Entry Conditions**:
- Feature directory exists
- original-plan.md present

**Execution**:
1. Spawn worker agent to analyze the plan
2. Identify risky assumptions (API availability, performance, dependencies)
3. Run spike experiments in isolation
4. Write `spike-report.md` with findings
5. Create `validated-plan.md` with confidence levels

**Decision Points**:
- Confidence >= 85%: Proceed to Phase 3
- Confidence < 85%: May create CHECKPOINT for user input
- Blockers found: HALT workflow

**Exit Conditions**:
- spike-report.md exists (or placeholder if no risks)
- validated-plan.md exists
- Output: `AUTOPILOT_CONTINUE`

**Artifacts Produced**:
- `spike-report.md`
- `validated-plan.md`

---

### Phase 3: Specify

**Purpose**: Generate a detailed specification from the validated plan.

**Entry Conditions**:
- validated-plan.md (or original-plan.md as fallback)
- State file at phase 3

**Execution**:
1. Read spec-kit specify prompt from `vendor/spec-kit/templates/commands/specify.md`
2. Spawn worker agent to generate spec
3. Input: validated-plan.md content
4. Output: spec.md with:
   - Overview, Goals, Non-Goals
   - User Stories
   - Functional Requirements (FR-XXX)
   - Non-Functional Requirements (NFR-XXX)
   - Success Criteria

**Validation**:
- spec.md exists and >= 2000 bytes
- No unfilled placeholders (`[FEATURE NAME]`, `{{FEATURE}}`, etc.)

**Exit Conditions**:
- spec.md validated
- Output: `AUTOPILOT_CONTINUE`

**Artifacts Produced**:
- `spec.md`

---

### Phase 4: Plan

**Purpose**: Create an implementation plan from the specification.

**Entry Conditions**:
- spec.md exists and valid

**Execution**:
1. Read spec-kit plan prompt
2. Spawn worker agent to generate plan
3. Create plan.md with:
   - Architecture decisions
   - Components and responsibilities
   - Data Model
   - API Design
   - Dependencies
   - Assumptions and Risks

**Post-processing**:
- Update `.autopilot/context.md` with tech stack extracted from plan

**Validation**:
- plan.md exists and >= 1000 bytes
- Contains architecture/design/technical section

**Exit Conditions**:
- plan.md validated
- context.md updated
- Output: `AUTOPILOT_CONTINUE`

**Artifacts Produced**:
- `plan.md`
- Updates to `.autopilot/context.md`

---

### Phase 5: Tasks

**Purpose**: Break down the implementation into actionable tasks.

**Entry Conditions**:
- spec.md and plan.md exist

**Execution**:
1. Read spec-kit tasks prompt
2. Spawn worker agent to generate tasks
3. Create tasks.md with:
   - Phased task groups
   - Task format: `- [ ] T001: Description`
   - Verify lines: `**Verify**: TYPE | condition`

**Task Format**:
```markdown
## Phase 1: Foundation

- [ ] T001: Create database schema
  - **Verify**: TEST | `yarn test src/db/schema.test.ts`

- [ ] T002: Implement API endpoint
  - **Verify**: API | POST /endpoint → 200
```

**Validation**:
- At least 1 task in T001 format

**Exit Conditions**:
- tasks.md validated
- Output: `AUTOPILOT_CONTINUE`

**Artifacts Produced**:
- `tasks.md`

---

### Phase 6: Analyze

**Purpose**: Cross-artifact consistency check before implementation.

**Entry Conditions**:
- spec.md, plan.md, tasks.md all exist

**Execution**:
1. Spawn worker agent for analysis
2. Check for:
   - Inconsistencies between artifacts
   - Coverage gaps (requirements without tasks)
   - Quality issues
3. Report findings (read-only, does not modify files)

**Exit Conditions**:
- Analysis complete
- Output: `AUTOPILOT_CONTINUE`

**Artifacts Produced**:
- None (analysis output only)

---

### Phase 7: Implement

**Purpose**: Execute tasks one at a time until all complete.

**Entry Conditions**:
- tasks.md exists with incomplete tasks

**Safety Limits**:
- Maximum 100 implement iterations (prevents infinite loops)
- Per-task retry limit of 3

**Execution** (per iteration):
1. Check iteration limit (halt if exceeded)
2. Parse tasks.md for first incomplete task
3. If all complete: advance to Phase 8
4. Spawn worker agent to implement one task:
   - Read task description
   - Implement following spec and plan
   - Run verification command if specified
   - Mark task complete: `[ ]` → `[x]`
5. Stay on Phase 7 for next iteration

**Loop Behavior**:
- This phase loops: each invocation does one task, then exits
- The loop restarts supervisor, which runs another task
- Continues until all tasks marked `[x]`

**Exit Conditions**:
- One task completed OR all tasks done
- Output: `AUTOPILOT_CONTINUE`

**Artifacts Modified**:
- `tasks.md` (marks tasks complete)
- Source code files (implementation)

---

### Phase 8: Verify

**Purpose**: Run tests and build to verify implementation.

**Entry Conditions**:
- At least 50% of tasks complete (via tasks.md)

**Execution**:
1. Run `yarn test` if package.json has test script
2. Run `yarn build` if package.json has build script
3. Check all verifications pass

**Failure Handling**:
- Tests fail: Increment verify retry count
- If retries < 3: Go back to Phase 7 to fix
- If retries >= 3: HALT workflow

**Exit Conditions**:
- All tests and build pass
- Output: `AUTOPILOT_CONTINUE` or `AUTOPILOT_HALTED`

**Artifacts Produced**:
- `verification-report.md` (optional)

---

### Phase 9: Review

**Purpose**: Self-review the implementation for quality issues.

**Entry Conditions**:
- Verification passed

**Execution**:
1. Spawn worker agent for code review
2. Check for:
   - Code quality and best practices
   - Security issues
   - Missing error handling
   - Test coverage gaps
3. Write findings to `review-report.md`

**Decision Points**:
- Critical issues found (CRITICAL keyword): Go back to Phase 7
- No critical issues: Proceed to Phase 10

**Exit Conditions**:
- review-report.md created
- Output: `AUTOPILOT_CONTINUE`

**Artifacts Produced**:
- `review-report.md`

---

### Phase 10: Complete

**Purpose**: Final validation and workflow completion.

**Entry Conditions**:
- All prior phases complete
- No critical review issues

**Execution**:
1. Check all required files exist:
   - original-plan.md
   - spec.md
   - plan.md
   - tasks.md
2. Verify all tasks marked complete (no `[ ]` tasks)
3. If validation fails: Go back to Phase 7

**Final Steps**:
- Set status to `completed`
- Set `timestamps.completed`
- Output feature summary

**Exit Conditions**:
- All validations pass
- Output: `AUTOPILOT_COMPLETE` (loop terminates)

**Final State**:
```json
{
  "status": "completed",
  "timestamps": {
    "completed": "2026-03-15T14:30:00Z"
  }
}
```

---

## Directory Structure

### Project Layout After Initialization

```
project-root/
├── CLAUDE.md                      # Constitution (static principles)
├── .autopilot/
│   ├── context.md                 # Active tech stack (auto-updated)
│   └── templates/
│       ├── spec-template.md       # Specification template
│       ├── plan-template.md       # Implementation plan template
│       ├── tasks-template.md      # Task breakdown template
│       └── checklist-template.md  # Checklist template
└── specs/
    └── NNN-feature-name/          # Feature directories
        ├── .workflow-state.json   # Workflow state
        ├── original-plan.md       # User's input plan
        ├── validated-plan.md      # Post-spike validated plan
        ├── spec.md                # Generated specification
        ├── plan.md                # Implementation plan
        ├── tasks.md               # Task breakdown
        ├── spike-report.md        # Assumption validation
        ├── review-report.md       # Code review findings
        └── verification-report.md # Test/build results
```

### State Files

| File | Purpose | Updated By |
|------|---------|------------|
| `.workflow-state.json` | Phase, status, iterations | `update-state.sh` |
| `.autopilot/context.md` | Tech stack registry | `update-context.sh` |

### Templates Source

Templates are sourced from the spec-kit submodule:
```
vendor/spec-kit/templates/
├── spec-template.md
├── plan-template.md
├── tasks-template.md
└── checklist-template.md
```

---

## Security Model

### Path Validation

All file paths are validated before use:

```bash
# Security checks in common.sh validate_plan_path()

# 1. Reject shell metacharacters
if echo "$plan_file" | grep -qE '[$`|;&(){}]|\.\.'; then
    log_error "Invalid characters in plan file path"
    return 1
fi

# 2. Must be .md file
if ! echo "$plan_file" | grep -qE '\.md$'; then
    log_error "Plan file must be a .md file"
    return 1
fi

# 3. Must be within project directory
case "$real_path" in
    "$repo_root"/*) ;;
    *)
        log_error "Plan file must be within project directory"
        return 1
        ;;
esac

# 4. Cannot be a symlink
if [ -L "$real_path" ]; then
    log_error "Plan file cannot be a symlink"
    return 1
fi
```

### Command Injection Prevention

Scripts use environment variables instead of string interpolation for user input:

```bash
# SECURITY: Pass values via environment variables to prevent injection
STATE_FILE_PATH="$STATE_FILE" GET_KEY_NAME="$GET_KEY" node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.env.STATE_FILE_PATH, "utf8"));
    // ...
'
```

### File Locking

Concurrent state modifications are prevented via locking:

```bash
# update-state.sh file locking

acquire_lock() {
    # Use flock if available (Linux)
    if command -v flock >/dev/null 2>&1; then
        exec 200>"$LOCK_FILE"
        if ! flock -n 200; then
            log_error "Another autopilot process is updating state. Please wait."
            exit 1
        fi
    else
        # macOS fallback: mkdir is atomic
        if ! mkdir "$LOCK_FILE" 2>/dev/null; then
            log_error "Another autopilot process is updating state. Please wait."
            exit 1
        fi
        trap 'rmdir "$LOCK_FILE" 2>/dev/null' EXIT
    fi
}
```

### Sandboxing

Worker agents can use worktree isolation for risky code:

```
Agent(
    description: "Spike: validate assumptions",
    subagent_type: "general-purpose",
    isolation: "worktree",  # Isolated git worktree
    prompt: ...
)
```

---

## Error Handling

### Exit Signals

| Signal | Meaning | Loop Action | When Used |
|--------|---------|-------------|-----------|
| `AUTOPILOT_COMPLETE` | All phases done successfully | Stop loop | Phase 10 final validation passes |
| `AUTOPILOT_HALTED` | Unrecoverable error | Stop loop | Max retries exceeded, blockers, validation failures |
| `AUTOPILOT_CONTINUE` | Phase completed, more work | Continue loop | Any phase completing normally |

### Retry Logic

```
Phase 7 (Implement):
  - Max 100 total iterations (hard limit)
  - Per-task retries: 3 attempts before marking blocked

Phase 8 (Verify):
  - Max 3 retry iterations
  - On failure: Go back to Phase 7 to fix issues
  - After 3 failures: HALT

Phase 9 (Review):
  - Critical issues: Go back to Phase 7
  - No retry limit (one-shot per cycle)
```

### Iteration Limits

```bash
# Phase 7 safety check
MAX_IMPLEMENT_ITERATIONS=100
IMPLEMENT_COUNT=$(grep -o '"implement": [0-9]*' "$STATE_FILE" | grep -o '[0-9]*')

if [ "$IMPLEMENT_COUNT" -ge "$MAX_IMPLEMENT_ITERATIONS" ]; then
    echo "ERROR: Maximum implement iterations ($MAX_IMPLEMENT_ITERATIONS) exceeded"
    echo "This usually indicates a task that cannot be completed."
    "$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" --set status=halted
    echo "AUTOPILOT_HALTED"
    exit 1
fi
```

### State Recovery

On restart, the entry-point script:
1. Looks for existing `.workflow-state.json` in specs/
2. Finds most recently modified state file
3. Reads `status` and `currentPhase`
4. Returns appropriate action (resume/complete/halted/error)

```bash
# entry-point.sh action determination
if [ "$STATUS" = "completed" ]; then
    ACTION="complete"
elif [ "$STATUS" = "halted" ]; then
    ACTION="halted"
else
    ACTION="resume"
fi
```

---

## Extension Points

### Adding New Phases

1. Update `_supervisor.md` with new phase section:
```markdown
### Phase N: NewPhase

<execution>

**Step N.1: Description**

```bash
echo "[N/10] Phase: NEWPHASE"
# Phase logic here
```

</execution>
```

2. Update phase routing table:
```markdown
| Phase | Name | Description |
|-------|------|-------------|
| N | NewPhase | What it does |
```

3. Update `workflow-status.sh` PHASE_NAMES array:
```bash
PHASE_NAMES=("Parse" "Initialize" ... "NewPhase" "Complete")
```

4. Add prerequisite checks in `check-prerequisites.sh`:
```bash
N) # NewPhase
    check_file "$REQUIRED_FILE" "required-file.md"
    ;;
```

### Customizing Templates

1. Templates live in `.autopilot/templates/`
2. Copy and modify from `vendor/spec-kit/templates/`
3. Supervisor reads templates via spec-kit prompts

### Adding Custom Validation

1. Extend `validate-artifact.sh`:
```bash
validate_custom() {
    local file="$1"

    # Add custom checks
    if ! grep -qE 'required-pattern' "$file"; then
        add_error "Missing required pattern"
    fi
}

case "$ARTIFACT_TYPE" in
    custom)
        validate_custom "$FILE_PATH"
        ;;
esac
```

### Custom Worker Agents

Spawn custom agents in phase execution:

```markdown
Agent(
    description: "Custom task",
    subagent_type: "general-purpose",
    prompt: |
        Your custom prompt here.
        Feature dir: $FEATURE_DIR

        Return: {"status": "complete|failed"}
)
```

---

## Testing

### Test Structure

```
test/
├── common.test.sh              # Shared utility tests
├── entry-point.test.sh         # Entry point logic tests
├── init-project.test.sh        # Project initialization tests
├── initialize-feature.test.sh  # Feature directory creation tests
├── parse-loop-args.test.sh     # Loop argument parsing tests
├── parse-tasks.test.sh         # Task parsing tests
├── update-context.test.sh      # Context update tests
├── update-state.test.sh        # State management tests
├── validate-artifact.test.sh   # Artifact validation tests
└── workflow-status.test.sh     # Status reporting tests
```

### Running Tests

```bash
# Run all tests
cd plugins/autopilot
for test in test/*.test.sh; do
    echo "Running $test..."
    bash "$test"
done

# Run individual test
bash test/entry-point.test.sh
```

### Test Framework Pattern

Each test file uses a simple bash test framework:

```bash
#!/usr/bin/env bash
set -e

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

setup() {
    TEST_TMP=$(mktemp -d)
    cd "$TEST_TMP"
}

teardown() {
    rm -rf "$TEST_TMP"
}

run_test() {
    local test_name="$1"
    local test_func="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    setup

    if $test_func; then
        echo "  PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL: $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    teardown
}

# Define tests
test_example() {
    local output
    output=$("$SCRIPT" "input")
    assert_contains "$output" "expected" "should contain expected"
}

# Run tests
run_test "example test" test_example

# Report
echo "Results: $TESTS_PASSED/$TESTS_RUN passed"
```

### Coverage Areas

| Area | Test File | Key Scenarios |
|------|-----------|---------------|
| Entry point | entry-point.test.sh | Action determination, state detection, JSON output |
| State updates | update-state.test.sh | Atomic updates, file locking, nested keys |
| Task parsing | parse-tasks.test.sh | T001 format, verify lines, status filtering |
| Validation | validate-artifact.test.sh | Spec, plan, tasks, state validation |
| Workflow status | workflow-status.test.sh | Phase names, progress calculation, artifacts |
| Initialization | init-project.test.sh | Directory creation, template copying |

### Integration Testing

Test the full workflow:

```bash
# Create test project
mkdir test-project && cd test-project
git init

# Initialize autopilot
/autopilot:init

# Create a simple plan
cat > my-feature.md << 'EOF'
# Add Logging

Add structured logging to the application.

## Requirements
- Use pino logger
- Log all HTTP requests
- Include request IDs
EOF

# Run autopilot (manual step-by-step)
/autopilot:_supervisor my-feature.md      # Phase 1
/autopilot:_supervisor --resume           # Phase 2
# ... continue through phases

# Or run autonomous loop
/autopilot:loop my-feature.md
```

---

## Appendix: Script Reference

### Core Scripts

| Script | Purpose | Key Options |
|--------|---------|-------------|
| `entry-point.sh` | Determine action from args/state | `<plan.md>`, `--resume` |
| `parse-loop-args.sh` | Parse /loop arguments | `<plan.md>`, `--interval`, `--resume` |
| `init-project.sh` | Initialize .autopilot/ | `--force` |
| `initialize-feature.sh` | Create feature directory | `--description`, `--number` |
| `update-state.sh` | Atomic state updates | `--set`, `--push`, `--get` |
| `update-context.sh` | Update context.md from plan | (no options) |
| `parse-tasks.sh` | Extract task info | `--file`, `--status` |
| `validate-artifact.sh` | Validate artifacts | `--type`, `--file`, `--strict` |
| `workflow-status.sh` | Get workflow status | `--feature-dir`, `--branch` |
| `check-prerequisites.sh` | Check phase prereqs | `--phase`, `--feature-dir` |

### Common Utilities (common.sh)

| Function | Purpose |
|----------|---------|
| `get_repo_root` | Find project root (.git or .autopilot) |
| `get_current_branch` | Get branch name or feature ID |
| `get_highest_feature_number` | Find next available feature number |
| `find_feature_dir` | Locate feature directory by branch |
| `validate_plan_path` | Security validation for file paths |
| `json_escape` | Escape strings for JSON |
| `json_output` | Build JSON from key-value pairs |
| `json_array` | Build JSON array |

---

## Appendix: State Schema

```typescript
interface WorkflowState {
  version: 1;
  feature: string;          // "NNN-feature-name"
  featureDir: string;       // "specs/NNN-feature-name"
  planFile: string;         // Absolute path to original plan
  currentPhase: number;     // 1-10
  status: "in_progress" | "completed" | "halted" | "checkpoint";
  iterations: {
    spike: number;
    specify: number;
    plan: number;
    tasks: number;
    analyze: number;
    implement: number;      // Capped at 100
    verify: number;         // Capped at 3
    review: number;
  };
  completedTasks: string[]; // ["T001", "T002", ...]
  timestamps: {
    started: string;        // ISO 8601
    lastUpdated: string;    // ISO 8601
    phaseStarted?: string;  // ISO 8601
    completed?: string;     // ISO 8601
  };
}
```
