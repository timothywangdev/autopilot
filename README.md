# Autopilot

Fully autonomous feature implementation for Claude Code.

```
Plan → Specify → Tasks → Analyze → Implement → Review → Ship
```

## Installation

```bash
claude plugin install github:timothywangdev/autopilot
```

## Commands

| Command | Description |
| ------- | ----------- |
| `/autopilot.full <plan-file>` | End-to-end orchestrator (runs everything) |
| `/autopilot.specify` | Generate spec.md from feature description |
| `/autopilot.plan` | Generate plan.md, research.md, data-model.md |
| `/autopilot.tasks` | Generate tasks.md from plan |
| `/autopilot.analyze` | Cross-artifact consistency check |
| `/autopilot.clarify` | Ask clarifying questions, update spec |
| `/autopilot.implement` | Execute tasks with team spawning |
| `/autopilot.checklist` | Generate validation checklists |

## Usage

### Full Automation

```bash
# Create a plan file first (e.g., in plan mode or manually)
# Then run:
/autopilot.full my-feature-plan.md
```

Autopilot will:
1. Create spec from plan
2. Generate technical plan and artifacts
3. Break into tasks
4. Analyze for consistency (loop until clean)
5. Implement with parallel team spawning
6. Code review with 5 specialized reviewers
7. Auto-fix issues and re-review
8. Commit and push

### Resume

```bash
/autopilot.full --resume
```

Continues from `.workflow-state.json` after interruption.

## Configuration

State is persisted in:
```
specs/NNN-feature/.workflow-state.json
```

### Iteration Limits

| Loop | Default |
| ---- | ------- |
| analyze | 5 |
| clarify | 3 |
| implementTaskRetry | 3 |
| review | 5 |
| workflow | 3 |

## Design Principles

1. **Full automation** - No blocking prompts, HALT only on unrecoverable errors
2. **Team parallelism** - Spawn multiple agents in single message for speed
3. **Bounded iteration** - Hard limits prevent runaway loops
4. **State persistence** - Resume after `/clear` or interruption
5. **Audit trail** - Every decision logged, every iteration versioned

## License

MIT
