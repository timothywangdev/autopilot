# Autopilot

Fully autonomous feature implementation for Claude Code. Built on [spec-kit](https://github.com/github/spec-kit).

```
Plan → Spike → Specify → Plan → Tasks → Analyze → Implement → Verify → Review → Ship
```

## Installation

```bash
claude plugin install github:timothywangdev/autopilot
```

## Quick Start

```bash
# 1. Initialize autopilot in your project
/autopilot:init

# 2. Edit CLAUDE.md to define your project principles

# 3. Create a plan file describing your feature, then run:
/autopilot:loop my-feature-plan.md
```

That's it. Autopilot handles everything else autonomously.

## Commands

| Command | Description |
| ------- | ----------- |
| `/autopilot:loop <plan-file>` | **Main entry point** - autonomous feature implementation |
| `/autopilot:init` | Initialize autopilot in current project |

## How It Works

Autopilot uses a **supervisor/worker pattern**:

```
┌─────────────────────────────────────────────────────┐
│  /loop (interval timer)                             │
│  ┌───────────────────────────────────────────────┐  │
│  │  /autopilot:_supervisor                       │  │
│  │                                               │  │
│  │  1. Read .workflow-state.json                 │  │
│  │  2. If completed → exit (AUTOPILOT_COMPLETE)  │  │
│  │  3. Spawn worker agent for current phase      │  │
│  │  4. Update state, increment phase             │  │
│  │  5. Exit (AUTOPILOT_CONTINUE)                 │  │
│  │                                               │  │
│  │  ┌─────────────┐  ┌─────────────┐             │  │
│  │  │ Worker Agent│  │ Worker Agent│  ...        │  │
│  │  │ (specify)   │  │ (implement) │             │  │
│  │  └─────────────┘  └─────────────┘             │  │
│  └───────────────────────────────────────────────┘  │
│                         ↓                           │
│  Loop waits for interval, then invokes again...     │
└─────────────────────────────────────────────────────┘
```

The supervisor spawns worker agents for each phase (specify, plan, tasks, implement, etc.).

## Phases

| Phase | Name | Description |
|-------|------|-------------|
| 1 | Initialize | Pre-flight + create feature directory |
| 2 | Spike | Validate risky assumptions |
| 3 | Specify | Generate spec.md |
| 4 | Plan | Generate plan.md |
| 5 | Tasks | Generate tasks.md |
| 6 | Analyze | Cross-artifact consistency |
| 7 | Implement | Execute tasks (loops here) |
| 8 | Verify | Run tests and build |
| 9 | Review | Self-review code |
| 10 | Complete | Final validation |

## State Persistence

State is persisted in:
```
specs/NNN-feature/.workflow-state.json
```

Resume after interruption:
```bash
/autopilot:loop --resume
```

## Project Structure

After `/autopilot:init`:
```
CLAUDE.md                    # Constitution (principles, static)
.specify/
├── context.md               # Active context (tech stack, auto-updated)
├── memory/
│   └── constitution.md      # Symlink → ../../CLAUDE.md (spec-kit compat)
└── templates/               # Spec-kit templates

specs/
└── NNN-feature-name/        # Feature directories
    ├── .workflow-state.json
    ├── original-plan.md
    ├── spec.md
    ├── plan.md
    └── tasks.md
```

**Key insight:** CLAUDE.md is your constitution (static principles). `.specify/context.md` is auto-updated with tech stack from each feature's plan.md.

## Design Principles

1. **Single command** - Just `/autopilot:loop` to start
2. **Loop pattern** - Execute one phase per invocation, persist, exit
3. **State is truth** - Always resume from state file
4. **Bounded iteration** - Hard limits prevent runaway loops
5. **Clean separation** - Bash logic in scripts, prompts in markdown

## Architecture

```
autopilot/
├── commands/loop.md           # Public entry point
├── lib/
│   ├── _supervisor.md         # Supervisor (spawns workers)
│   └── _init.md               # Initialize project
├── scripts/bash/              # All bash logic here
│   ├── entry-point.sh
│   ├── parse-loop-args.sh
│   ├── init-project.sh
│   └── ...
└── vendor/spec-kit/           # Git submodule
    └── templates/             # Spec-kit templates
```

## Updating Spec-kit

```bash
cd plugins/autopilot
git submodule update --remote vendor/spec-kit
```

## License

MIT
