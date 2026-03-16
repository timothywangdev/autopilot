# Autopilot Plugin Development

## Overview

Autopilot is a Claude Code plugin for fully autonomous feature implementation. It uses spec-kit as a submodule for templates and prompts.

## Architecture

```
autopilot/
├── commands/loop.md           # Public entry point (/autopilot:loop)
├── lib/
│   ├── _supervisor.md         # Supervisor (spawns worker agents)
│   └── _init.md               # Project initialization (internal)
├── scripts/bash/              # All bash logic
└── vendor/spec-kit/           # Git submodule (templates + prompts)
```

## Key Patterns

### Script Separation
- **Markdown files** = prompts/instructions for Claude
- **Bash scripts** = actual logic in `scripts/bash/`
- Commands reference scripts via `scripts:` frontmatter

### Supervisor/Worker Pattern
- `/autopilot:loop` invokes `/loop` which repeatedly calls `/autopilot:_supervisor`
- `_supervisor` spawns worker agents for each phase (specify, plan, implement, etc.)
- Each invocation executes ONE phase, persists state, exits
- Exit signals: `AUTOPILOT_COMPLETE`, `AUTOPILOT_HALTED`, `AUTOPILOT_CONTINUE`

### State Machine
- State persisted in `specs/NNN-feature/.workflow-state.json`
- 11 phases (0-10): pre-flight → initialize → spike → specify → plan → tasks → analyze → implement → verify → review → complete

## Commands

Only three commands are registered in plugin.json:
- `./commands/loop.md` — public entry point
- `./lib/_supervisor.md` — supervisor (spawns workers)
- `./lib/_init.md` — internal initialization

## Spec-kit Integration

Templates and prompts come from `vendor/spec-kit/`:
- `templates/spec-template.md`
- `templates/plan-template.md`
- `templates/tasks-template.md`
- `templates/commands/*.md` — prompt templates read by Agent tool

Note: We don't use `constitution-template.md` — CLAUDE.md is the constitution.

Update submodule: `git submodule update --remote vendor/spec-kit`

## Constitution Model

Autopilot uses CLAUDE.md as the constitution (not `.specify/memory/constitution.md`):
- **CLAUDE.md** — Static principles, user-maintained (constitution)
- **`.specify/context.md`** — Dynamic tech stack, auto-updated from plan.md
- **`.specify/memory/constitution.md`** — Symlink to CLAUDE.md (spec-kit compatibility)

## Scripts

| Script | Purpose |
|--------|---------|
| `entry-point.sh` | Determine action and phase from state |
| `parse-loop-args.sh` | Parse /autopilot:loop arguments |
| `init-project.sh` | Initialize .specify/ directory + CLAUDE.md |
| `update-context.sh` | Update .specify/context.md from plan.md |
| `update-state.sh` | Atomic state file updates |
| `parse-tasks.sh` | Extract task info from tasks.md |
| `workflow-status.sh` | Get current workflow status |
| `validate-artifact.sh` | Validate generated artifacts |
| `check-prerequisites.sh` | Check phase prerequisites |

## Testing

Test the plugin by running in a test project:
```bash
/autopilot:init
/autopilot:loop test-plan.md
```

## Contributing

1. Keep markdown files as pure prompts
2. Extract bash logic to `scripts/bash/`
3. Use JSON output from scripts for structured data
4. Follow spec-kit conventions for templates
