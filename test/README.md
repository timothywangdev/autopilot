# Autopilot Plugin Tests

Comprehensive test suite for the autopilot plugin using skill-creator evals.

## Quick Start

```bash
# Install skill-creator plugin (if not installed)
claude plugin install skill-creator

# Run all evals
/skill-creator eval autopilot

# Run specific command evals
/skill-creator eval autopilot:full
/skill-creator eval autopilot:init
/skill-creator eval autopilot:specify

# Run benchmarks
/skill-creator benchmark autopilot
```

## Test Structure

```
test/
├── README.md              # This file
├── fixtures/              # Test input files
│   ├── simple-plan.md     # Basic plan for happy path tests
│   ├── complex-plan.md    # Multi-requirement plan
│   └── risky-assumptions-plan.md  # Plan with assumptions needing spike
└── evals/
    └── autopilot-evals.yaml  # Comprehensive eval suite
```

## Eval Categories

### Critical Path Tests
- Full workflow execution
- Resume functionality
- State persistence

### Error Handling
- Missing files
- Empty inputs
- Invalid state

### Phase-Specific Tests
- Spike validation
- Specify generation
- Plan creation
- Task breakdown
- Analysis checks
- Verification
- Review

### Edge Cases
- Special characters
- Unicode content
- Long files

## Adding New Tests

### Inline Evals (in command frontmatter)

```yaml
---
description: My command description

evals:
  - prompt: "/autopilot:mycommand arg1"
    expect: |
      - Expected behavior 1
      - Expected behavior 2
---
```

### External Evals (in YAML file)

```yaml
evals:
  - name: "my test name"
    skill: "autopilot:mycommand"
    prompt: "/autopilot:mycommand"
    setup: |
      # Bash commands to set up test environment
      echo "setup" > test.txt
    expect:
      files_exist:
        - "output.md"
      output_contains:
        - "success"
```

## Benchmarks

Benchmarks track performance over time:

| Benchmark | Max Time | Max Tokens | Max Agents |
|-----------|----------|------------|------------|
| simple-feature-e2e | 5 min | 100k | 20 |
| complex-feature-e2e | 10 min | 500k | 50 |
| spike-with-invalid-assumptions | 3 min | - | - |

## Running Tests Locally

```bash
# Set up test directory
mkdir -p /tmp/autopilot-test
cd /tmp/autopilot-test
git init

# Run single eval
claude -p "/skill-creator eval autopilot:init"

# Run with verbose output
claude -p "/skill-creator eval autopilot --verbose"

# Run benchmarks
claude -p "/skill-creator benchmark autopilot"
```

## CI/CD Integration

```yaml
# .github/workflows/test-plugin.yml
name: Test Autopilot Plugin

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Claude Code
        run: npm install -g @anthropic/claude-code
      - name: Install plugins
        run: |
          claude plugin install skill-creator
          claude plugin install ./
      - name: Run evals
        run: claude -p "/skill-creator eval autopilot" --json > results.json
      - name: Check results
        run: jq '.pass_rate >= 0.95' results.json
```
