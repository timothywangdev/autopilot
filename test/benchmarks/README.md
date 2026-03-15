# Autopilot Benchmarks

End-to-end benchmarks aligned with [FeatureBench](https://arxiv.org/abs/2602.10975) methodology.

## Metrics

| Metric | Description | Target |
|--------|-------------|--------|
| **Resolved Rate** | % of tasks fully completed (all verification passes) | >80% |
| **Passed Rate** | Avg % of verification checks passed per task | >90% |
| **Token IO** | Total input/output tokens consumed | Track |
| **Steps** | Tool calls before completion | <500 |
| **Error Recovery** | % of failures recovered via retry | >70% |
| **Human Intervention** | % requiring manual input (should be 0%) | 0% |
| **Time to Complete** | Wall clock time | Track |

## Difficulty Levels

| Level | Description | Example |
|-------|-------------|---------|
| **L1** | Incremental - add feature to existing codebase | Add API endpoint |
| **L2** | From-scratch - build new module/component | New service |
| **L3** | Cross-cutting - multi-system changes | Auth + API + UI |

## Test Structure

```
test/benchmarks/
├── README.md
├── schema.json              # Benchmark result schema
├── tasks/
│   ├── l1-add-endpoint/     # L1 difficulty task
│   │   ├── task.md          # Feature description
│   │   ├── setup.sh         # Environment setup
│   │   ├── verify.sh        # Verification script
│   │   └── expected/        # Expected outputs
│   ├── l2-new-service/      # L2 difficulty task
│   └── l3-auth-flow/        # L3 difficulty task
└── results/
    └── benchmark-YYYYMMDD.json
```

## Running Benchmarks

```bash
./scripts/benchmark.sh                    # Run all benchmarks
./scripts/benchmark.sh l1-add-endpoint    # Run specific task
./scripts/benchmark.sh --report           # Generate report
```

## Verification Types

Each task specifies verification methods:

- `TEST` - Unit/integration tests pass
- `API` - Endpoint responds correctly
- `CLI` - Command produces expected output
- `DB` - Database state is correct
- `UI` - Browser automation checks (via agent-browser)

## Success Criteria

A task is **resolved** when:
1. All verification checks pass
2. No human intervention was required
3. Completed within step limit (500)
4. No pre-existing tests broken (regression)
