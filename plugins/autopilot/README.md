# Autopilot

Fully autonomous feature implementation for Claude Code. Give it a plan, and it builds the feature end-to-end: specification, design, implementation, testing, and review.

## How It Works

Autopilot takes your feature idea through a structured 10-phase workflow:

```
Initialize -> Spike -> Specify -> Plan -> Tasks -> Analyze -> Implement -> Verify -> Review -> Complete
```

Each phase runs automatically. You can walk away while Autopilot:
- Validates risky assumptions with spike experiments
- Generates detailed specifications and implementation plans
- Breaks work into atomic tasks
- Implements each task with test coverage
- Runs verification and self-review
- Handles failures with automatic retries

## Installation

```bash
claude plugin install github:timothywangdev/autopilot
```

## Quick Start

```bash
# 1. Initialize autopilot in your project
/autopilot:init

# 2. Write CLAUDE.md with your project principles (if not already present)

# 3. Create a plan file describing your feature (e.g., add-dark-mode.md):
#    - What the feature does
#    - Why it's needed
#    - Any constraints or requirements

# 4. Run autopilot
/autopilot:loop add-dark-mode.md
```

Autopilot takes over from here. It will run continuously until the feature is complete or it hits a blocker.

## Commands

| Command | Description |
|---------|-------------|
| `/autopilot:loop <plan.md>` | Start autonomous implementation from a plan file |
| `/autopilot:loop --resume` | Resume a halted or interrupted workflow |
| `/autopilot:init` | Initialize autopilot in current project |

### Command Options

```bash
# Start with default 1-minute interval
/autopilot:loop my-feature.md

# Custom interval between phases
/autopilot:loop my-feature.md --interval 30s

# Resume existing workflow
/autopilot:loop --resume
```

## Writing a Good Plan File

Your plan file is the input to autopilot. A good plan includes:

```markdown
# Add Dark Mode Support

## Problem
Users need a dark theme option for comfortable viewing in low-light conditions.

## Requirements
- Toggle between light/dark themes
- Persist preference in localStorage
- System preference detection (prefers-color-scheme)
- Smooth transition animation

## Constraints
- Must work with existing Tailwind setup
- No additional dependencies
- Accessibility: maintain contrast ratios

## Out of Scope
- Per-component theme customization
- Theme scheduling
```

The more context you provide, the better the output.

## Phases Explained

| Phase | What Happens |
|-------|--------------|
| **1. Initialize** | Pre-flight checks, creates feature directory in `specs/NNN-feature/` |
| **2. Spike** | Validates risky assumptions (API availability, performance, dependencies) |
| **3. Specify** | Generates detailed `spec.md` with acceptance criteria |
| **4. Plan** | Creates technical `plan.md` with architecture decisions |
| **5. Tasks** | Breaks plan into atomic `tasks.md` with T001, T002... format |
| **6. Analyze** | Cross-checks spec, plan, and tasks for consistency |
| **7. Implement** | Executes tasks one by one, marks complete in tasks.md |
| **8. Verify** | Runs tests and build, retries on failure |
| **9. Review** | Self-reviews code for quality, security, coverage |
| **10. Complete** | Final validation, marks workflow complete |

## Project Structure

After running `/autopilot:init`:

```
your-project/
├── CLAUDE.md                    # Your project principles (you maintain this)
├── .autopilot/
│   ├── context.md               # Tech stack context (auto-updated)
│   └── templates/
│       ├── spec-template.md
│       ├── plan-template.md
│       ├── tasks-template.md
│       └── checklist-template.md
└── specs/                       # Feature directories (created per feature)
    └── 001-add-dark-mode/
        ├── .workflow-state.json # Progress tracking
        ├── original-plan.md     # Your input plan
        ├── spec.md              # Generated specification
        ├── plan.md              # Technical plan
        └── tasks.md             # Task breakdown
```

### Key Files

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project constitution - principles, commands, code style. You write and maintain this. |
| `.autopilot/context.md` | Active tech stack. Autopilot updates this from each feature's plan. |
| `specs/NNN-feature/.workflow-state.json` | Tracks current phase, completed tasks, retry counts. |

## Monitoring Progress

While autopilot runs:

```bash
# Check workflow status
plugins/autopilot/scripts/bash/workflow-status.sh

# View state directly
cat specs/*/.workflow-state.json

# Stop the loop
/cancel-loop
```

### Exit Signals

Autopilot outputs these signals that control the loop:

| Signal | Meaning | What Happens |
|--------|---------|--------------|
| `AUTOPILOT_CONTINUE` | Phase complete, more work to do | Loop continues |
| `AUTOPILOT_COMPLETE` | All phases done | Loop terminates successfully |
| `AUTOPILOT_HALTED` | Unrecoverable error | Loop terminates, needs manual intervention |

## Configuration

### CLAUDE.md (Required)

Your project's constitution. Autopilot reads this to understand your conventions:

```markdown
# Project Guidelines

## Principles
- Test-driven development
- No comments in code, self-documenting names
- Prefer composition over inheritance

## Commands
yarn build    # Type-check
yarn test     # Run tests
yarn lint     # Lint code

## Code Style
TypeScript strict mode, ESM modules, no default exports
```

### Customizing Templates

Edit templates in `.autopilot/templates/` to match your team's conventions:
- `spec-template.md` - Specification structure
- `plan-template.md` - Technical plan format
- `tasks-template.md` - Task breakdown format

## Troubleshooting

### "Autopilot not initialized"

Run `/autopilot:init` first to set up the `.autopilot/` directory and templates.

### Workflow stuck on a phase

1. Check the state file: `cat specs/NNN-feature/.workflow-state.json`
2. Look at `iterations` counts - high numbers indicate repeated failures
3. Check generated artifacts for errors
4. May need manual intervention to fix the issue, then `/autopilot:loop --resume`

### Tests failing repeatedly

The verify phase retries up to 3 times. If still failing:
1. Check `specs/NNN-feature/tasks.md` for incomplete tasks
2. Review test output for the actual error
3. Fix manually and resume

### Want to start over

```bash
# Delete the feature directory
rm -rf specs/NNN-feature

# Start fresh
/autopilot:loop my-plan.md
```

### Maximum iterations exceeded

The implement phase has a 100-iteration safety limit. If hit:
1. The workflow halts to prevent infinite loops
2. Review `tasks.md` for a task that can't be completed
3. Fix the blocker manually
4. Resume with `/autopilot:loop --resume`

## Example Session

```
> /autopilot:loop docs/plans/add-user-auth.md

Starting autonomous autopilot...
Command: /autopilot:_supervisor docs/plans/add-user-auth.md
Interval: 1m

[1/10] Phase: INITIALIZE
FEATURE_DIR=specs/012-add-user-auth
AUTOPILOT_CONTINUE

[2/10] Phase: SPIKE
PASS: OAuth provider reachable, no blockers
AUTOPILOT_CONTINUE

[3/10] Phase: SPECIFY
Generated spec.md (4532 bytes)
AUTOPILOT_CONTINUE

...

[7/10] Phase: IMPLEMENT
Implementing T003: Add login form component
Task T003 complete
Tasks remaining: 5
AUTOPILOT_CONTINUE

...

[10/10] Phase: COMPLETE
==========================================
  WORKFLOW COMPLETE
==========================================
Feature: specs/012-add-user-auth
AUTOPILOT_COMPLETE
```

## How It Works (Architecture)

Autopilot uses a **supervisor/worker pattern**:

```
/loop (built-in interval timer)
  └── /autopilot:_supervisor (called every interval)
        ├── Reads .workflow-state.json
        ├── Executes ONE phase
        ├── Spawns worker agents for heavy lifting
        ├── Updates state
        └── Exits with signal (CONTINUE/COMPLETE/HALTED)
```

Key design decisions:
- **One phase per invocation** - Clean separation, easy to debug
- **State is truth** - Always resumes from state file, survives interruptions
- **Bounded iteration** - Hard limits prevent runaway loops
- **Bash for logic, Markdown for prompts** - Clean separation of concerns

## Updating Spec-kit Templates

Autopilot uses [spec-kit](https://github.com/github/spec-kit) templates. To update:

```bash
cd plugins/autopilot
git submodule update --remote vendor/spec-kit
```

## License

MIT
