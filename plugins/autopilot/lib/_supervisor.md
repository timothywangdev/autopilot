---
description: Supervisor that orchestrates feature implementation by spawning worker agents for each phase. Executes ONE phase per invocation, persists state, exits cleanly.
argument-hint: "<plan-file.md> | --resume"
scripts:
  sh: scripts/bash/entry-point.sh "{ARGS}"
---

## User Input

```text
$ARGUMENTS
```

## Overview

This is the **supervisor** in the autopilot workflow. It:
1. Determines which phase to execute
2. Spawns **worker agents** to do the actual work
3. Persists state and exits cleanly

```bash
# Autonomous execution via loop
/loop 1m /autopilot:_supervisor plan.md

# Or manual step-by-step
/autopilot:_supervisor plan.md    # Phase 0-1
/autopilot:_supervisor --resume   # Phase 2
/autopilot:_supervisor --resume   # Phase 3
# ... continues until complete
```

**Key behavior:**
- Executes **ONE phase** per invocation
- Persists state to `.workflow-state.json`
- Exits cleanly after each phase
- Loop restarts and resumes from saved state
- Fast exit on `completed` or `halted` status

## Exit Signals

Output these exact strings for loop control:

| Signal | Meaning | Loop Action |
|--------|---------|-------------|
| `AUTOPILOT_COMPLETE` | All phases done | Stop loop |
| `AUTOPILOT_HALTED` | Unrecoverable error | Stop loop |
| `AUTOPILOT_CONTINUE` | Phase done, more work | Continue loop |

## Entry Point Logic

**CRITICAL**: Run the entry-point script FIRST to determine what to do.

```bash
plugins/autopilot/scripts/bash/entry-point.sh "$ARGUMENTS"
```

The script returns JSON with:
- `action`: "initialize" | "resume" | "complete" | "halted" | "error"
- `current_phase`: 0-10
- `feature_dir`: path to feature directory
- `plan_file`: path to plan file (for fresh start)
- `state_file`: path to state file (if resuming)
- `error`: error message if action is "error"

**Handle terminal states immediately:**
- If `action` is "complete": output `AUTOPILOT_COMPLETE` and exit
- If `action` is "halted": output `AUTOPILOT_HALTED` and exit
- If `action` is "error": output error message, `AUTOPILOT_HALTED`, and exit

After parsing JSON, you have these variables available for the entire phase:
- `CURRENT_PHASE` — which phase to execute (1-10)
- `FEATURE_DIR` — path to feature directory
- `STATE_FILE` — path to state file (use this, don't re-discover!)
- `PLAN_FILE` — input plan file

**IMPORTANT**: Save these variables after parsing entry-point output. Use them throughout the phase. Do NOT re-discover STATE_FILE with find commands.

## Phase Execution

Execute ONLY the phase indicated by `CURRENT_PHASE`, then exit.

### Phase 1: Initialize (includes pre-flight)

<execution>

**Step 1.0: Pre-flight validation**

```bash
echo "[1/10] Phase: INITIALIZE"

# Pre-flight checks
if [ ! -d ".autopilot" ]; then
    echo "FAIL: .autopilot directory not found"
    echo "Run: /autopilot:_init first"
    echo "AUTOPILOT_HALTED"
    exit 1
fi

for tmpl in spec-template.md plan-template.md tasks-template.md; do
    if [ ! -f ".autopilot/templates/$tmpl" ]; then
        echo "FAIL: $tmpl not found"
        echo "AUTOPILOT_HALTED"
        exit 1
    fi
done

if ! git diff --quiet 2>/dev/null; then
    echo "WARN: Uncommitted changes detected"
fi

echo "PASS: Pre-flight complete"
```

**Step 1.1: Validate and parse plan file**

```bash
# PLAN_FILE comes from entry point parsing
if [ -z "$PLAN_FILE" ]; then
    PLAN_FILE=$(echo "$ARGUMENTS" | grep -oE '[^ ]+\.md' | head -1)
fi

# Validate plan file path
if [ -z "$PLAN_FILE" ]; then
    echo "ERROR: No plan file specified"
    echo "AUTOPILOT_HALTED"
    exit 1
fi

# Security: reject shell metacharacters
if echo "$PLAN_FILE" | grep -qE '[$`|;&(){}]|\.\.'; then
    echo "ERROR: Invalid characters in plan file path"
    echo "AUTOPILOT_HALTED"
    exit 1
fi

# Validate extension
if ! echo "$PLAN_FILE" | grep -qE '\.md$'; then
    echo "ERROR: Plan file must be a .md file"
    echo "AUTOPILOT_HALTED"
    exit 1
fi

# Resolve and validate path (portable realpath)
if command -v realpath >/dev/null 2>&1; then
    PLAN_FILE_REAL=$(realpath "$PLAN_FILE" 2>/dev/null)
else
    # Fallback for macOS
    PLAN_FILE_REAL=$(cd "$(dirname "$PLAN_FILE")" 2>/dev/null && pwd)/$(basename "$PLAN_FILE")
fi

if [ -z "$PLAN_FILE_REAL" ] || [ ! -f "$PLAN_FILE_REAL" ]; then
    echo "ERROR: Plan file not found: $PLAN_FILE"
    echo "AUTOPILOT_HALTED"
    exit 1
fi

PROJECT_ROOT=$(pwd)
case "$PLAN_FILE_REAL" in
    "$PROJECT_ROOT"/*) ;;
    *)
        echo "ERROR: Plan file must be within project directory"
        echo "AUTOPILOT_HALTED"
        exit 1
        ;;
esac

PLAN_FILE="$PLAN_FILE_REAL"

# Extract feature name
FEATURE_NAME=$(grep -m1 '^#[^#]' "$PLAN_FILE" | sed 's/^#[[:space:]]*//' | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
if [ -z "$FEATURE_NAME" ]; then
    FEATURE_NAME=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
fi

# Find next feature number (find highest existing + 1, supports up to 9999)
HIGHEST_NUM=0
for dir in specs/[0-9]*-*; do
    [ -d "$dir" ] || continue
    NUM=$(basename "$dir" | grep -oE '^[0-9]+' | sed 's/^0*//')
    NUM=${NUM:-0}
    if [ "$NUM" -gt "$HIGHEST_NUM" ] && [ "$NUM" -le 9999 ]; then
        HIGHEST_NUM=$NUM
    fi
done
NEXT_NUM=$((HIGHEST_NUM + 1))
if [ "$NEXT_NUM" -gt 9999 ]; then
    echo "ERROR: Feature number limit (9999) exceeded"
    echo "AUTOPILOT_HALTED"
    exit 1
fi
# Use 4 digits if > 999, otherwise 3 digits
if [ "$NEXT_NUM" -gt 999 ]; then
    FEATURE_DIR=$(printf "specs/%04d-%s" "$NEXT_NUM" "$FEATURE_NAME")
else
    FEATURE_DIR=$(printf "specs/%03d-%s" "$NEXT_NUM" "$FEATURE_NAME")
fi

echo "FEATURE_NAME=$FEATURE_NAME"
echo "FEATURE_DIR=$FEATURE_DIR"

# Create feature directory and copy plan
mkdir -p "$FEATURE_DIR"
cp "$PLAN_FILE" "$FEATURE_DIR/original-plan.md"

echo "Created: $FEATURE_DIR"
```

**Step 1.2: Create state file**

Write this to `$FEATURE_DIR/.workflow-state.json`:

```json
{
  "version": 1,
  "feature": "{FEATURE_NAME}",
  "featureDir": "{FEATURE_DIR}",
  "planFile": "{PLAN_FILE}",
  "currentPhase": 2,
  "status": "in_progress",
  "iterations": {
    "spike": 0,
    "specify": 0,
    "plan": 0,
    "tasks": 0,
    "analyze": 0,
    "implement": 0,
    "verify": 0,
    "review": 0
  },
  "completedTasks": [],
  "timestamps": {
    "started": "{ISO timestamp}",
    "lastUpdated": "{ISO timestamp}"
  }
}
```

**Step 1.3: Exit for loop**

```bash
echo "Phase 1 complete. State saved."
echo "AUTOPILOT_CONTINUE"
exit 0
```

</execution>

### Phase 2: Spike (Assumption Validation)

<phase_rules>
- Validate risky assumptions BEFORE implementation
- CHECKPOINT on confidence < 85%
- HALT on blockers
</phase_rules>

<execution>

**Step 2.1: Update state**

```bash
echo "[2/10] Phase: SPIKE"

# Update state
SCRIPT_DIR="plugins/autopilot/scripts/bash"
"$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" \
    --set status=in_progress \
    --set "timestamps.phaseStarted=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

**Step 2.2: Run spike validation**

Use the Agent tool to run spike experiments:

```
Agent(
    description: "Spike: validate assumptions",
    subagent_type: "general-purpose",
    prompt: |
        Read the plan at $FEATURE_DIR/original-plan.md

        1. Identify risky assumptions (API availability, performance, dependencies)
        2. Create spike experiments to validate each
        3. Run experiments (use isolation: "worktree" for risky code)
        4. Write results to $FEATURE_DIR/spike-report.md
        5. Create $FEATURE_DIR/validated-plan.md with confidence levels

        Return: {"status": "PASS|CHECKPOINT|HALT", "confidence": 0-100}
)
```

**Step 2.3: Validate and decide**

```bash
# Check spike outputs exist
if [ ! -f "$FEATURE_DIR/spike-report.md" ]; then
    echo "WARN: spike-report.md not created, creating placeholder"
    printf '%s\n\n%s\n' "# Spike Report" "No risky assumptions identified." > "$FEATURE_DIR/spike-report.md"
fi

if [ ! -f "$FEATURE_DIR/validated-plan.md" ]; then
    echo "Using original plan as validated plan"
    cp "$FEATURE_DIR/original-plan.md" "$FEATURE_DIR/validated-plan.md"
fi

echo "PASS: Spike phase complete"
```

**Step 2.4: Update state and exit**

```bash
# Get current spike iteration count (default to 0)
SPIKE_COUNT=$(grep -o '"spike": [0-9]*' "$STATE_FILE" 2>/dev/null | grep -o '[0-9]*' || echo 0)
SPIKE_COUNT=${SPIKE_COUNT:-0}

"$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" \
    --set currentPhase=3 \
    --set "iterations.spike=$((SPIKE_COUNT + 1))"

echo "AUTOPILOT_CONTINUE"
exit 0
```

</execution>

### Phase 3: Specify

<execution>

**Step 3.1: Execute specify prompt**

```bash
echo "[3/10] Phase: SPECIFY"
```

Read the spec-kit specify prompt from `vendor/spec-kit/templates/commands/specify.md` and execute it with the validated plan as input. The prompt will:
1. Create a feature branch
2. Generate spec.md from the plan
3. Run specification quality validation

Use the Agent tool to execute the specify workflow:

```
Agent(
    description: "Generate spec from plan",
    subagent_type: "general-purpose",
    prompt: |
        Read and follow the instructions in: vendor/spec-kit/templates/commands/specify.md

        Input plan file: $FEATURE_DIR/validated-plan.md
        Output spec file: $FEATURE_DIR/spec.md

        The plan content is already in $FEATURE_DIR/validated-plan.md - use it as the feature description.
        Write the generated spec to $FEATURE_DIR/spec.md
)
```

**Step 3.2: Validate spec**

```bash
# Re-initialize paths (each bash block runs independently)
SCRIPT_DIR="plugins/autopilot/scripts/bash"
# STATE_FILE from entry-point output (do not re-discover)
STATE_FILE="$FEATURE_DIR/.workflow-state.json"
FEATURE_DIR=$(dirname "$STATE_FILE")

SPEC_FILE="$FEATURE_DIR/spec.md"

if [ ! -f "$SPEC_FILE" ]; then
    echo "FAIL: spec.md not created"
    echo "AUTOPILOT_HALTED"
    exit 1
fi

SPEC_SIZE=$(wc -c < "$SPEC_FILE" | tr -d ' ')
if [ "$SPEC_SIZE" -lt 2000 ]; then
    echo "FAIL: spec.md too small ($SPEC_SIZE bytes, need 2000+)"
    echo "AUTOPILOT_HALTED"
    exit 1
fi

if grep -qE '\[FEATURE NAME\]|\{\{FEATURE|\[Brief Title\]|\[DATE\]' "$SPEC_FILE"; then
    echo "FAIL: spec.md contains unfilled placeholders"
    echo "AUTOPILOT_HALTED"
    exit 1
fi

echo "PASS: spec.md validated ($SPEC_SIZE bytes)"
```

**Step 3.3: Update state and exit**

```bash
# Re-initialize paths
SCRIPT_DIR="plugins/autopilot/scripts/bash"
# STATE_FILE from entry-point output (do not re-discover)
STATE_FILE="$FEATURE_DIR/.workflow-state.json"

"$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" --set currentPhase=4

echo "AUTOPILOT_CONTINUE"
exit 0
```

</execution>

### Phase 4: Plan

<execution>

**Step 4.1: Execute plan prompt**

```bash
echo "[4/10] Phase: PLAN"
```

Read the spec-kit plan prompt and execute it:

```
Agent(
    description: "Generate plan from spec",
    subagent_type: "general-purpose",
    prompt: |
        Read and follow the instructions in: vendor/spec-kit/templates/commands/plan.md

        Input spec file: $FEATURE_DIR/spec.md
        Output plan file: $FEATURE_DIR/plan.md

        Generate a technical implementation plan based on the spec.
)
```

**Step 4.2: Validate plan**

```bash
# Re-initialize paths
SCRIPT_DIR="plugins/autopilot/scripts/bash"
# STATE_FILE from entry-point output (do not re-discover)
STATE_FILE="$FEATURE_DIR/.workflow-state.json"
FEATURE_DIR=$(dirname "$STATE_FILE")

PLAN_FILE="$FEATURE_DIR/plan.md"

if [ ! -f "$PLAN_FILE" ]; then
    echo "FAIL: plan.md not created"
    echo "AUTOPILOT_HALTED"
    exit 1
fi

PLAN_SIZE=$(wc -c < "$PLAN_FILE" | tr -d ' ')
if [ "$PLAN_SIZE" -lt 1000 ]; then
    echo "FAIL: plan.md too small ($PLAN_SIZE bytes, need 1000+)"
    echo "AUTOPILOT_HALTED"
    exit 1
fi

# Check for architecture section
if ! grep -qE '^##.*[Aa]rchitecture|^##.*[Dd]esign|^##.*[Tt]echnical' "$PLAN_FILE"; then
    echo "WARN: plan.md may be missing architecture section"
fi

echo "PASS: plan.md validated ($PLAN_SIZE bytes)"
```

**Step 4.3: Update context file**

After plan generation, update `.autopilot/context.md` with tech stack from the plan:

```bash
# Re-initialize paths
SCRIPT_DIR="plugins/autopilot/scripts/bash"

# Update context with tech stack from plan (writes to .autopilot/context.md)
"$SCRIPT_DIR/update-context.sh" || echo "WARN: context update skipped"
```

**Step 4.4: Update state and exit**

```bash
# Re-initialize paths
SCRIPT_DIR="plugins/autopilot/scripts/bash"
# STATE_FILE from entry-point output (do not re-discover)
STATE_FILE="$FEATURE_DIR/.workflow-state.json"

"$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" --set currentPhase=5

echo "AUTOPILOT_CONTINUE"
exit 0
```

</execution>

### Phase 5: Tasks

<execution>

**Step 5.1: Execute tasks prompt**

```bash
echo "[5/10] Phase: TASKS"
```

Read the spec-kit tasks prompt and execute it:

```
Agent(
    description: "Generate tasks from plan",
    subagent_type: "general-purpose",
    prompt: |
        Read and follow the instructions in: vendor/spec-kit/templates/commands/tasks.md

        Input plan file: $FEATURE_DIR/plan.md
        Input spec file: $FEATURE_DIR/spec.md
        Output tasks file: $FEATURE_DIR/tasks.md

        Generate actionable tasks with T001, T002, etc. format.
)
```

**Step 5.2: Validate tasks**

```bash
# Re-initialize paths
SCRIPT_DIR="plugins/autopilot/scripts/bash"
# STATE_FILE from entry-point output (do not re-discover)
STATE_FILE="$FEATURE_DIR/.workflow-state.json"
FEATURE_DIR=$(dirname "$STATE_FILE")

TASKS_FILE="$FEATURE_DIR/tasks.md"

if [ ! -f "$TASKS_FILE" ]; then
    echo "FAIL: tasks.md not created"
    echo "AUTOPILOT_HALTED"
    exit 1
fi

# Check for T001 format tasks
TASK_COUNT=$(grep -cE '^[[:space:]]*-[[:space:]]*\[[ Xx]\][[:space:]]*T[0-9]+:' "$TASKS_FILE" 2>/dev/null || echo 0)
TASK_COUNT=${TASK_COUNT:-0}
if [ "$TASK_COUNT" -lt 1 ]; then
    echo "FAIL: No tasks found in T001 format"
    echo "AUTOPILOT_HALTED"
    exit 1
fi

echo "PASS: tasks.md validated ($TASK_COUNT tasks)"
```

**Step 5.3: Update state and exit**

```bash
# Re-initialize paths
SCRIPT_DIR="plugins/autopilot/scripts/bash"
# STATE_FILE from entry-point output (do not re-discover)
STATE_FILE="$FEATURE_DIR/.workflow-state.json"

"$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" --set currentPhase=6

echo "AUTOPILOT_CONTINUE"
exit 0
```

</execution>

### Phase 6: Analyze

<execution>

**Step 6.1: Execute analyze prompt**

```bash
echo "[6/10] Phase: ANALYZE"
```

Read the spec-kit analyze prompt and execute it:

```
Agent(
    description: "Analyze artifacts for consistency",
    subagent_type: "general-purpose",
    prompt: |
        Read and follow the instructions in: vendor/spec-kit/templates/commands/analyze.md

        Feature directory: $FEATURE_DIR
        Files to analyze: spec.md, plan.md, tasks.md

        Check for inconsistencies, coverage gaps, and quality issues.
        Report findings but do not modify files (read-only analysis).
)
```

**Step 6.2: Check analysis results**

The analyze skill performs cross-artifact consistency checks. Review its output.

If critical issues found, the skill will indicate them. Otherwise proceed.

**Step 6.3: Update state and exit**

```bash
# Re-initialize paths
SCRIPT_DIR="plugins/autopilot/scripts/bash"
# STATE_FILE from entry-point output (do not re-discover)
STATE_FILE="$FEATURE_DIR/.workflow-state.json"

"$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" --set currentPhase=7

echo "AUTOPILOT_CONTINUE"
exit 0
```

</execution>

### Phase 7: Implement

<phase_rules>
- Execute tasks in dependency order
- Mark each task complete in tasks.md
- Track completed tasks in state
- Retry failed tasks up to 3 times per task
- Maximum 100 implement iterations total (safety limit)
</phase_rules>

<execution>

**Step 7.0: Check iteration limit**

```bash
echo "[7/10] Phase: IMPLEMENT"

# Re-initialize paths
SCRIPT_DIR="plugins/autopilot/scripts/bash"
STATE_FILE="$FEATURE_DIR/.workflow-state.json"
FEATURE_DIR=$(dirname "$STATE_FILE")

# SAFETY: Check max iterations to prevent infinite loops
MAX_IMPLEMENT_ITERATIONS=100
IMPLEMENT_COUNT=$(grep -o '"implement": [0-9]*' "$STATE_FILE" 2>/dev/null | grep -o '[0-9]*' || echo 0)
IMPLEMENT_COUNT=${IMPLEMENT_COUNT:-0}

if [ "$IMPLEMENT_COUNT" -ge "$MAX_IMPLEMENT_ITERATIONS" ]; then
    echo "ERROR: Maximum implement iterations ($MAX_IMPLEMENT_ITERATIONS) exceeded"
    echo "This usually indicates a task that cannot be completed."
    echo "Review the tasks.md and fix the issue manually."
    "$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" --set status=halted
    echo "AUTOPILOT_HALTED"
    exit 1
fi

# Increment implement counter
"$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" --set "iterations.implement=$((IMPLEMENT_COUNT + 1))"
```

**Step 7.1: Get incomplete tasks**

```bash
# Re-initialize paths
SCRIPT_DIR="plugins/autopilot/scripts/bash"
STATE_FILE="$FEATURE_DIR/.workflow-state.json"
FEATURE_DIR=$(dirname "$STATE_FILE")

TASKS_JSON=$("$SCRIPT_DIR/parse-tasks.sh" --file "$FEATURE_DIR/tasks.md" --status incomplete)

INCOMPLETE=$(echo "$TASKS_JSON" | grep -o '"incomplete": [0-9]*' | grep -o '[0-9]*' || echo 0)
INCOMPLETE=${INCOMPLETE:-0}

if [ "$INCOMPLETE" -eq 0 ]; then
    echo "All tasks complete!"
    "$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" --set currentPhase=8
    echo "AUTOPILOT_CONTINUE"
    exit 0
fi

echo "Tasks remaining: $INCOMPLETE"
```

**Step 7.2: Execute next task**

Use the Agent tool to implement ONE task:

```
Agent(
    description: "Implement task T00X",
    subagent_type: "general-purpose",
    prompt: |
        You are implementing a task for the autopilot workflow.

        FEATURE_DIR: $FEATURE_DIR
        TASKS_FILE: $FEATURE_DIR/tasks.md

        1. Read tasks.md and find the FIRST incomplete task ([ ])
        2. Implement the task following the spec and plan
        3. Run the task's verification command if specified
        4. Mark the task complete in tasks.md: change [ ] to [x]
        5. Return: {"taskId": "T001", "status": "complete|failed", "error": "..."}
)
```

**Step 7.3: Update state**

After task completion:
- Add task ID to `completedTasks[]` in state
- If more tasks remain, stay on phase 7
- If all tasks done, advance to phase 8

```bash
# Re-initialize paths
SCRIPT_DIR="plugins/autopilot/scripts/bash"
# STATE_FILE from entry-point output (do not re-discover)
STATE_FILE="$FEATURE_DIR/.workflow-state.json"
FEATURE_DIR=$(dirname "$STATE_FILE")

# Check if more tasks remain
TASKS_JSON=$("$SCRIPT_DIR/parse-tasks.sh" --file "$FEATURE_DIR/tasks.md" --status incomplete)
INCOMPLETE=$(echo "$TASKS_JSON" | grep -o '"incomplete": [0-9]*' | grep -o '[0-9]*' || echo 0)
INCOMPLETE=${INCOMPLETE:-0}

if [ "$INCOMPLETE" -eq 0 ]; then
    "$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" --set currentPhase=8
else
    # Stay on phase 7 for next iteration
    echo "Tasks remaining: $INCOMPLETE"
fi

echo "AUTOPILOT_CONTINUE"
exit 0
```

</execution>

### Phase 8: Verify

<phase_rules>
- Run all tests
- Check build succeeds
- Validate task verifications
- Retry up to 3 times on failure
</phase_rules>

<execution>

**Step 8.1: Run verification**

```bash
echo "[8/10] Phase: VERIFY"

# Re-initialize paths
SCRIPT_DIR="plugins/autopilot/scripts/bash"
# STATE_FILE from entry-point output (do not re-discover)
STATE_FILE="$FEATURE_DIR/.workflow-state.json"
FEATURE_DIR=$(dirname "$STATE_FILE")

# Run existing tests
if [ -f "package.json" ]; then
    if grep -q '"test"' package.json; then
        echo "Running: yarn test"
        if ! yarn test 2>&1; then
            echo "FAIL: Tests failed"

            # Check retry count (default to 0)
            VERIFY_RETRIES=$(grep -o '"verify": [0-9]*' "$STATE_FILE" 2>/dev/null | grep -o '[0-9]*' || echo 0)
            VERIFY_RETRIES=${VERIFY_RETRIES:-0}

            if [ "$VERIFY_RETRIES" -ge 3 ]; then
                echo "Max retries exceeded"
                "$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" --set status=halted
                echo "AUTOPILOT_HALTED"
                exit 1
            fi

            # Increment retry and go back to implement
            "$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" \
                --set currentPhase=7 \
                --set "iterations.verify=$((VERIFY_RETRIES + 1))"
            echo "Returning to implement phase to fix issues"
            echo "AUTOPILOT_CONTINUE"
            exit 0
        fi
    fi

    # Run build
    if grep -q '"build"' package.json; then
        echo "Running: yarn build"
        if ! yarn build 2>&1; then
            echo "FAIL: Build failed"
            "$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" --set currentPhase=7
            echo "AUTOPILOT_CONTINUE"
            exit 0
        fi
    fi
fi

echo "PASS: Verification complete"
```

**Step 8.2: Update state and exit**

```bash
# Re-initialize paths
SCRIPT_DIR="plugins/autopilot/scripts/bash"
# STATE_FILE from entry-point output (do not re-discover)
STATE_FILE="$FEATURE_DIR/.workflow-state.json"

"$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" --set currentPhase=9

echo "AUTOPILOT_CONTINUE"
exit 0
```

</execution>

### Phase 9: Review

<phase_rules>
- Self-review the implementation
- Check for code quality issues
- Create review-report.md
</phase_rules>

<execution>

**Step 9.1: Run code review**

```bash
echo "[9/10] Phase: REVIEW"
```

Use Agent tool for self-review:

```
Agent(
    description: "Code review",
    subagent_type: "general-purpose",
    prompt: |
        Review the implementation in $FEATURE_DIR.

        Check for:
        1. Code quality and best practices
        2. Security issues
        3. Missing error handling
        4. Test coverage gaps

        Write findings to $FEATURE_DIR/review-report.md

        Return: {"criticalIssues": 0, "warnings": 0, "status": "PASS|WARN|FAIL"}
)
```

**Step 9.2: Check review results**

```bash
# Re-initialize paths
SCRIPT_DIR="plugins/autopilot/scripts/bash"
# STATE_FILE from entry-point output (do not re-discover)
STATE_FILE="$FEATURE_DIR/.workflow-state.json"
FEATURE_DIR=$(dirname "$STATE_FILE")

if [ -f "$FEATURE_DIR/review-report.md" ]; then
    CRITICAL_COUNT=$(grep -ci "CRITICAL" "$FEATURE_DIR/review-report.md" 2>/dev/null || echo 0)
    CRITICAL_COUNT=${CRITICAL_COUNT:-0}
    if [ "$CRITICAL_COUNT" -gt 0 ]; then
        echo "WARN: $CRITICAL_COUNT critical issues found"
        # Go back to implement to fix
        "$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" --set currentPhase=7
        echo "AUTOPILOT_CONTINUE"
        exit 0
    fi
fi

echo "PASS: Review complete"
```

**Step 9.3: Update state and exit**

```bash
# Re-initialize paths
SCRIPT_DIR="plugins/autopilot/scripts/bash"
# STATE_FILE from entry-point output (do not re-discover)
STATE_FILE="$FEATURE_DIR/.workflow-state.json"

"$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" --set currentPhase=10

echo "AUTOPILOT_CONTINUE"
exit 0
```

</execution>

### Phase 10: Complete

<execution>

**Step 10.1: Final validation**

```bash
echo "[10/10] Phase: COMPLETE"

# Re-initialize paths
SCRIPT_DIR="plugins/autopilot/scripts/bash"
# STATE_FILE from entry-point output (do not re-discover)
STATE_FILE="$FEATURE_DIR/.workflow-state.json"
FEATURE_DIR=$(dirname "$STATE_FILE")

echo "=== FINAL VALIDATION ==="

ERRORS=0

# Check required files
for file in original-plan.md spec.md plan.md tasks.md; do
    if [ ! -f "$FEATURE_DIR/$file" ]; then
        echo "FAIL: Missing $file"
        ERRORS=$((ERRORS + 1))
    fi
done

# Check all tasks complete
INCOMPLETE=$(grep -cE '^[[:space:]]*-[[:space:]]*\[ \][[:space:]]*T[0-9]+:' "$FEATURE_DIR/tasks.md" 2>/dev/null || echo 0)
INCOMPLETE=${INCOMPLETE:-0}
if [ "$INCOMPLETE" -gt 0 ]; then
    echo "FAIL: $INCOMPLETE incomplete tasks"
    ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -gt 0 ]; then
    echo "Final validation failed with $ERRORS errors"
    "$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" --set currentPhase=7
    echo "AUTOPILOT_CONTINUE"
    exit 0
fi

echo "PASS: All validations passed"
```

**Step 10.2: Mark complete**

```bash
"$SCRIPT_DIR/update-state.sh" --state-file "$STATE_FILE" \
    --set status=completed \
    --set "timestamps.completed=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo ""
echo "=========================================="
echo "  WORKFLOW COMPLETE"
echo "=========================================="
echo "Feature: $FEATURE_DIR"
echo "Artifacts:"
ls -la "$FEATURE_DIR"/*.md 2>/dev/null
echo ""
echo "AUTOPILOT_COMPLETE"
exit 0
```

</execution>

## Phase Routing

Based on `CURRENT_PHASE` from entry point, execute the appropriate phase:

| Phase | Name | Description |
|-------|------|-------------|
| 1 | Initialize | Pre-flight checks + create feature directory |
| 2 | Spike | Validate risky assumptions |
| 3 | Specify | Generate spec.md |
| 4 | Plan | Generate plan.md |
| 5 | Tasks | Generate tasks.md |
| 6 | Analyze | Cross-artifact consistency |
| 7 | Implement | Execute tasks (loops here) |
| 8 | Verify | Run tests and build |
| 9 | Review | Self-review code |
| 10 | Complete | Final validation |

## Execution Rules

1. **One phase per invocation** — Execute only the current phase, then exit
2. **State is truth** — Always read phase from state file, not memory
3. **Use entry-point output** — Don't re-discover STATE_FILE or FEATURE_DIR
4. **Exit cleanly** — Output appropriate signal and exit 0 or 1
5. **Loop handles continuation** — Don't try to run multiple phases
6. **Max 8 parallel agents** — Never spawn more than 8 concurrent Agent() calls. Batch and wait if more are needed.

## Using with /loop

```bash
# Start autonomous execution
/loop 1m /autopilot:_supervisor my-feature-plan.md

# The loop will:
# 1. Call /autopilot:_supervisor every minute
# 2. Supervisor reads state, executes one phase, exits
# 3. Loop restarts, supervisor continues from next phase
# 4. When AUTOPILOT_COMPLETE is output, loop stops
```

## Bash Script Utilities

Scripts in `plugins/autopilot/scripts/bash/`:

| Script | Purpose |
|--------|---------|
| `common.sh` | Shared utilities (source first) |
| `initialize-feature.sh` | Create feature directory |
| `update-state.sh` | Atomic state operations |
| `validate-artifact.sh` | Validate artifacts |
| `check-prerequisites.sh` | Check phase prereqs |
| `parse-tasks.sh` | Extract task info |
| `workflow-status.sh` | Get workflow status |

## State Schema

```json
{
  "version": 1,
  "feature": "NNN-feature-name",
  "featureDir": "specs/NNN-feature-name",
  "planFile": "/absolute/path/to/plan.md",
  "currentPhase": 3,
  "status": "in_progress|completed|halted",
  "iterations": {
    "spike": 0,
    "verify": 0,
    "review": 0
  },
  "completedTasks": ["T001", "T002"],
  "timestamps": {
    "started": "ISO",
    "lastUpdated": "ISO",
    "completed": "ISO"
  }
}
```
