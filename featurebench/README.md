# Running FeatureBench with Autopilot

Evaluate the autopilot plugin against the [FeatureBench](https://github.com/LiberCoders/FeatureBench) benchmark for end-to-end feature development.

## Quick Start

### 1. Install FeatureBench

```bash
pip install featurebench
# or
uv add featurebench
```

### 2. Configure

```bash
cp config_example.toml config.toml
```

Edit `config.toml`:
```toml
[infer_config.autopilot]
ANTHROPIC_API_KEY = "sk-ant-..."
# Optional: lock versions
CLAUDE_CODE_VERSION = ""
```

### 3. Run Evaluation

```bash
# Lite split (30 tasks, ~$45-90)
fb infer --agent autopilot --model claude-opus-4-5 --split lite

# Full split (200 tasks, ~$300-600)
fb infer --agent autopilot --model claude-opus-4-5 --split full

# Evaluate results
fb eval -p runs/<timestamp>/output.jsonl --split lite
```

## Cost Estimates

| Split | Tasks | Est. Input Tokens | Est. Cost (Opus) |
|-------|-------|-------------------|------------------|
| Lite | 30 | ~900K | $45-90 |
| Full | 200 | ~6M | $300-600 |

*Based on ~30K tokens/task avg, multiple inference calls per task*

## Installing the Agent

### Option A: Symlink (Development)

```bash
# Clone this repo alongside FeatureBench
cd /path/to/FeatureBench/featurebench/infer/agents/
ln -s /path/to/autopilot/featurebench/autopilot_agent.py autopilot.py

# Register in __init__.py
echo 'from .autopilot import AutopilotAgent' >> __init__.py
```

### Option B: Copy

```bash
cp /path/to/autopilot/featurebench/autopilot_agent.py \
   /path/to/FeatureBench/featurebench/infer/agents/autopilot.py
```

## How It Works

The autopilot agent:

1. **Receives** FeatureBench problem statement (feature description)
2. **Writes** it to `plan.md` in the testbed
3. **Invokes** `/autopilot:full plan.md`
4. **Autopilot runs** the full workflow:
   - Spike (validate assumptions)
   - Specify (generate spec.md)
   - Plan (generate plan.md, research.md)
   - Tasks (generate tasks.md)
   - Analyze (cross-artifact consistency)
   - Implement (parallel team execution)
   - Verify (run tests, API checks)
   - Review (5 specialized reviewers)

## Comparing with Baseline Claude Code

```bash
# Run baseline Claude Code
fb infer --agent claude_code --model claude-opus-4-5 --split lite

# Run autopilot
fb infer --agent autopilot --model claude-opus-4-5 --split lite

# Compare results
fb eval -p runs/<claude_code_timestamp>/output.jsonl --split lite
fb eval -p runs/<autopilot_timestamp>/output.jsonl --split lite
```

## Expected Results

Current SOTA on FeatureBench:
- Claude Code (baseline): **11.0% resolved**
- Codex: **12.5% resolved**

Target for autopilot: **>15% resolved** (structured workflow advantage)

## Metrics Tracked

| Metric | Description |
|--------|-------------|
| Resolved Rate | % tasks fully passing all tests |
| Passed Rate | Avg % of tests passed per task |
| Time | Wall clock time per task |
| Tokens | Input + output tokens consumed |
| Steps | Tool calls to completion |
