---
description: "[MAIN ENTRY POINT] Autonomous feature implementation from plan to production. Just run /autopilot:loop plan.md"
argument-hint: "<plan-file.md> [--interval 1m]"
scripts:
  sh: scripts/bash/parse-loop-args.sh "{ARGS}"
---

## User Input

```text
$ARGUMENTS
```

## Overview

This command starts the autopilot workflow in **autonomous loop mode**. It wraps the built-in `/loop` command to repeatedly invoke `/autopilot:_supervisor` until the workflow completes or halts.

## Usage

```bash
# Start autonomous execution (default: 1 minute interval)
/autopilot:loop my-feature-plan.md

# Custom interval
/autopilot:loop my-feature-plan.md --interval 30s

# Resume existing workflow
/autopilot:loop --resume
```

## Execution

1. **Run the parse script** to get structured arguments:
   ```bash
   plugins/autopilot/scripts/bash/parse-loop-args.sh "$ARGUMENTS"
   ```

2. **Parse the JSON output** which contains:
   - `plan_file`: The plan file path
   - `interval`: Loop interval (default: 1m)
   - `autopilot_cmd`: The command to pass to `/loop`
   - `error`: Error message if arguments invalid

3. **Handle errors**: If `error` is non-empty, display it and exit.

4. **Start the loop**:
   ```
   Skill(skill: "loop", args: "<interval> <autopilot_cmd>")
   ```

Example: For input `my-plan.md --interval 30s`, the script returns:
```json
{
  "plan_file": "my-plan.md",
  "interval": "30s",
  "autopilot_cmd": "/autopilot:_supervisor my-plan.md"
}
```
Then invoke: `Skill(skill: "loop", args: "30s /autopilot:_supervisor my-plan.md")`

## Monitoring Progress

While the loop is running, you can:

1. **Check status**: Run the workflow-status script
   ```bash
   plugins/autopilot/scripts/bash/workflow-status.sh
   ```

2. **View state file**: Read the .workflow-state.json
   ```bash
   cat specs/*/.workflow-state.json | head -20
   ```

3. **Cancel**: Run `/cancel-loop` to stop autonomous execution

## Exit Signals

The autopilot outputs these signals that the loop monitors:

| Signal | Meaning | Loop Action |
|--------|---------|-------------|
| `AUTOPILOT_COMPLETE` | All 10 phases done | Loop terminates |
| `AUTOPILOT_HALTED` | Unrecoverable error | Loop terminates |
| `AUTOPILOT_CONTINUE` | Phase done, more work | Loop continues |

## Example Session

```
> /autopilot:loop docs/plans/add-dark-mode.md

Starting autonomous autopilot...
Command: /autopilot:_supervisor docs/plans/add-dark-mode.md
Interval: 1m

Loop started. Autopilot will run every 1m until completion.

[1/10] Phase: INITIALIZE
FEATURE_DIR=specs/012-add-dark-mode
AUTOPILOT_CONTINUE

... (1 minute later) ...

[2/10] Phase: SPIKE
PASS: No risky assumptions found
AUTOPILOT_CONTINUE

... (continues through all phases) ...

[10/10] Phase: COMPLETE
==========================================
  WORKFLOW COMPLETE
==========================================
Feature: specs/012-add-dark-mode
AUTOPILOT_COMPLETE

Loop terminated: workflow complete.
```

## Troubleshooting

**Loop not starting?**
- Check that `/loop` skill is available
- Verify plan file exists and is valid .md

**Workflow stuck on a phase?**
- Check state file for retry counts
- Review phase-specific error messages
- May need manual intervention

**Want to restart from scratch?**
- Delete the feature directory: `rm -rf specs/NNN-feature`
- Run `/autopilot:loop plan.md` again
