# Autopilot Plugin Development

## Overview

Autopilot is a Claude Code plugin for **fully autonomous feature implementation**. Given a plan file, it orchestrates a 10-phase workflow that takes a feature from specification to production-ready code, running without human intervention.

**Key capability**: Execute `/autopilot:loop plan.md` and watch as the plugin generates specs, creates tasks, implements code, runs tests, and completes the feature autonomously.

## Architecture

```
autopilot/
├── .claude-plugin/
│   └── plugin.json         # Plugin manifest (commands, metadata)
├── commands/
│   └── loop.md             # Public entry point (/autopilot:loop)
├── lib/
│   ├── _supervisor.md      # Phase orchestrator (spawns worker agents)
│   └── _init.md            # Project initialization (/autopilot:_init)
├── scripts/bash/           # All logic lives here (scripts, not prompts)
├── test/                   # Bash unit tests for each script
└── vendor/spec-kit/        # Git submodule (templates + prompts)
```

### Core Design Patterns

**Script Separation**
- Markdown files (`.md`) = prompts/instructions for Claude
- Bash scripts (`.sh`) = actual logic
- Commands reference scripts via `scripts:` frontmatter

**Supervisor/Worker Pattern**
- `/autopilot:loop` wraps `/loop` to repeatedly invoke `_supervisor`
- `_supervisor` executes ONE phase per invocation, persists state, exits
- Exit signals control loop: `AUTOPILOT_COMPLETE`, `AUTOPILOT_HALTED`, `AUTOPILOT_CONTINUE`

**State Machine**
- State persisted in `specs/NNN-feature/.workflow-state.json`
- 10 phases: Initialize → Spike → Specify → Plan → Tasks → Analyze → Implement → Verify → Review → Complete

## Commands

Registered in `.claude-plugin/plugin.json`:

| Command | File | Purpose |
|---------|------|---------|
| `/autopilot:loop` | `commands/loop.md` | Main entry point |
| `/autopilot:_supervisor` | `lib/_supervisor.md` | Phase orchestrator (internal) |
| `/autopilot:_init` | `lib/_init.md` | Project initialization |

## Development Commands

### Run All Tests
```bash
# From plugin root
for test in test/*.test.sh; do bash "$test"; done

# Run single test file
bash test/common.test.sh
bash test/entry-point.test.sh
bash test/update-state.test.sh
```

### Test Individual Scripts
```bash
# Test entry-point logic
bash scripts/bash/entry-point.sh "plan.md"
bash scripts/bash/entry-point.sh "--resume"

# Test state operations
bash scripts/bash/update-state.sh --state-file /tmp/test.json --set currentPhase=3
bash scripts/bash/workflow-status.sh

# Test task parsing
bash scripts/bash/parse-tasks.sh --file specs/001-test/tasks.md --status incomplete
```

### Update Submodule
```bash
git submodule update --remote vendor/spec-kit
```

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `common.sh` | Shared utilities (source first in other scripts) |
| `entry-point.sh` | Determine action and phase from state/arguments |
| `parse-loop-args.sh` | Parse `/autopilot:loop` arguments |
| `init-project.sh` | Initialize `.autopilot/` directory + CLAUDE.md |
| `initialize-feature.sh` | Create feature directory from plan |
| `update-context.sh` | Update `.autopilot/context.md` from plan.md |
| `update-state.sh` | Atomic state file updates |
| `parse-tasks.sh` | Extract task info from tasks.md |
| `workflow-status.sh` | Get current workflow status |
| `validate-artifact.sh` | Validate generated artifacts |
| `check-prerequisites.sh` | Check phase prerequisites |

## Code Style

### Bash Conventions

**Script Headers**
```bash
#!/usr/bin/env bash
# script-name.sh - Brief description
# Run: bash plugins/autopilot/scripts/bash/script-name.sh [args]

set -euo pipefail
```

**Sourcing Common Utilities**
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
```

**Output Conventions**
- Use `log_info`, `log_error`, `log_warning`, `log_success` (output to stderr)
- JSON output goes to stdout for machine parsing
- Use `json_output` and `json_array` helpers for structured output

**Path Handling**
- Always use `get_realpath` for portable path resolution (works on macOS)
- Validate paths with `validate_plan_path` (security: rejects metacharacters, symlinks, traversal)
- Use `get_repo_root` to find project root

**Feature Numbers**
- 3-digit padding for 001-999, 4-digit for 1000-9999
- Use `get_highest_feature_number` + increment

**JSON Escaping**
```bash
# Use json_escape for values
value=$(json_escape "$unsafe_string")
json_output "key" "$value"
```

### Test Conventions

Tests use a simple framework in each `.test.sh` file:

```bash
run_test "test description"
# ... test code ...
assert_equals "expected" "$actual"
assert_contains "$haystack" "needle"
assert_exit_code 0 "$exit_code"
assert_file_exists "$path"
```

Each test should:
- Use `setup_temp_dir` / `cleanup_temp_dir` for isolation
- Test both success and failure cases
- Trap cleanup on exit

## Key Files

| Path | Purpose |
|------|---------|
| `scripts/bash/common.sh` | Shared utilities, JSON helpers, validation |
| `lib/_supervisor.md` | Phase execution logic (the main orchestrator) |
| `commands/loop.md` | Entry point docs and argument parsing |
| `vendor/spec-kit/templates/` | Spec/plan/tasks templates |
| `vendor/spec-kit/templates/commands/*.md` | Agent prompts for each phase |

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
    "specify": 0,
    "plan": 0,
    "tasks": 0,
    "analyze": 0,
    "implement": 0,
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

## Constitution Model

Autopilot uses CLAUDE.md as the constitution (not `.specify/memory/constitution.md`):
- **CLAUDE.md** — Static principles, user-maintained
- **`.autopilot/context.md`** — Dynamic tech stack, auto-updated from plan.md
- **`.autopilot/templates/`** — Specification templates from spec-kit

## Workflow Phases

| Phase | Name | Description |
|-------|------|-------------|
| 1 | Initialize | Pre-flight checks + create feature directory |
| 2 | Spike | Validate risky assumptions |
| 3 | Specify | Generate spec.md from validated plan |
| 4 | Plan | Generate technical plan.md |
| 5 | Tasks | Generate tasks.md with T001 format |
| 6 | Analyze | Cross-artifact consistency checks |
| 7 | Implement | Execute tasks (loops until all complete) |
| 8 | Verify | Run tests and build |
| 9 | Review | Self-review code quality |
| 10 | Complete | Final validation |

## Exit Signals

| Signal | Meaning | Loop Action |
|--------|---------|-------------|
| `AUTOPILOT_COMPLETE` | All phases done | Stop loop |
| `AUTOPILOT_HALTED` | Unrecoverable error | Stop loop |
| `AUTOPILOT_CONTINUE` | Phase done, more work | Continue loop |

## Contributing

1. Keep markdown files as pure prompts (instructions for Claude)
2. Extract all bash logic to `scripts/bash/`
3. Use JSON output from scripts for structured data
4. Write tests for new scripts in `test/`
5. Follow spec-kit conventions for templates
6. Use `common.sh` utilities instead of reimplementing

## Testing the Plugin

```bash
# In a test project
/autopilot:_init                    # Initialize autopilot
/autopilot:loop my-feature-plan.md  # Run full workflow

# Manual step-by-step
/autopilot:_supervisor plan.md      # Phase 1
/autopilot:_supervisor --resume     # Phase 2
/autopilot:_supervisor --resume     # Phase 3...
```
