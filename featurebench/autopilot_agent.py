"""
Autopilot agent for FeatureBench.

Wraps Claude Code with the autopilot plugin for structured feature development.
"""

import json
import shlex
from pathlib import Path
from typing import Dict, List, Optional

# Import from FeatureBench if available, otherwise stub
try:
    from featurebench.infer.agents.base import BaseAgent
    from featurebench.infer.container import DOCKER_HOST_GATEWAY
except ImportError:
    # Stub for standalone testing
    class BaseAgent:
        pass
    DOCKER_HOST_GATEWAY = "host.docker.internal"


class AutopilotAgent(BaseAgent):
    """
    Autopilot agent for FeatureBench.

    Uses the autopilot plugin's structured workflow:
    spike → specify → plan → tasks → analyze → implement → verify → review
    """

    # Allowed tools for autopilot (same as Claude Code + Skill)
    ALLOWED_TOOLS = [
        "Bash",
        "Edit",
        "Write",
        "Read",
        "Glob",
        "Grep",
        "LS",
        "WebFetch",
        "NotebookEdit",
        "NotebookRead",
        "TodoRead",
        "TodoWrite",
        "Agent",
        "Skill",  # Required for /autopilot:full
    ]

    @property
    def name(self) -> str:
        return "autopilot"

    @property
    def install_script(self) -> str:
        """Installation script for autopilot (Claude Code + plugin)."""
        claude_version = self._kwargs.get("claude_version") or self.env_vars.get("CLAUDE_CODE_VERSION") or "latest"

        return f"""#!/bin/bash
set -e

echo "Installing Autopilot agent (Claude Code + plugin)..."

# Update package manager
apt-get update
apt-get install -y curl ca-certificates tar xz-utils git

CACHE_ROOT="${{AGENT_DOWNLOAD_CACHE:-/download}}"
mkdir -p "$CACHE_ROOT" "$CACHE_ROOT/npm"

export npm_config_cache="$CACHE_ROOT/npm"
export NPM_CONFIG_CACHE="$CACHE_ROOT/npm"

NVM_DIR="/opt/featurebench/nvm"
mkdir -p "$NVM_DIR" "$NVM_DIR/.cache"

NODE_VERSION="22"

# Install NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | env NVM_DIR="$NVM_DIR" bash

export NVM_DIR
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Install Node
nvm install "$NODE_VERSION"
nvm use "$NODE_VERSION"

# Install Claude Code
npm install -g @anthropic-ai/claude-code@{claude_version}

# Verify installation
claude --version || echo "Claude Code installed"

# Install autopilot plugin
claude plugin install github:timothywangdev/autopilot || echo "Plugin install attempted"

echo "Autopilot installation complete"
"""

    def get_run_command(self, instruction: str) -> str:
        """
        Get command to run autopilot.

        Writes the problem statement to plan.md, then invokes /autopilot:full.
        """
        # Escape the instruction for shell
        escaped_instruction = instruction.rstrip().replace("'", "'\\''")
        allowed_tools = " ".join(self.ALLOWED_TOOLS)

        # The command:
        # 1. Write problem statement to plan.md
        # 2. Run /autopilot:full plan.md
        return (
            f"NVM_DIR=${{NVM_DIR:-/opt/featurebench/nvm}}; "
            f"[ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\" || true; "
            f"echo '{escaped_instruction}' > /testbed/plan.md; "
            f"cd /testbed && "
            f"claude --verbose "
            f"-p '/autopilot:full plan.md' --allowedTools {allowed_tools} "
            f"--dangerously-skip-permissions "
            f"--output-format stream-json | tee /agent-logs/autopilot_stream_output.jsonl"
        )

    def pre_run_hook(self, container, log_file) -> bool:
        """Create agent logs directory before running."""
        self.cm.exec_command(container, "mkdir -p /agent-logs", log_file=log_file)
        return True

    def post_run_hook(self, container, log_file) -> bool:
        """
        Save autopilot output and check for success.
        """
        log_dir = Path(log_file).parent

        # Copy stream output
        output_copied = self.cm.copy_from_container(
            container,
            "/agent-logs/autopilot_stream_output.jsonl",
            log_dir / "autopilot_stream_output.jsonl"
        )

        if not output_copied:
            self.logger.error("Failed to copy autopilot_stream_output.jsonl")
            return False

        # Also copy workflow state if available
        try:
            self.cm.copy_from_container(
                container,
                "/testbed/.workflow-state.json",
                log_dir / "workflow-state.json"
            )
        except Exception:
            pass

        # Check success from stream output
        output_file = log_dir / "autopilot_stream_output.jsonl"
        with open(output_file, "r", encoding="utf-8") as f:
            lines = f.readlines()

        if not lines:
            self.logger.error("Empty output file")
            return False

        last_line = lines[-1]
        try:
            result = json.loads(last_line)
        except json.JSONDecodeError:
            self.logger.error("Failed to parse last line as JSON")
            return False

        # Check for success
        is_success = (
            result.get("type") == "result" and
            result.get("subtype") == "success" and
            result.get("is_error") is False
        )

        if not is_success:
            self.logger.error(f"Autopilot did not complete successfully: {result}")
            return False

        return True

    def failure_hook(self, container, log_file) -> None:
        """Copy partial output on failure."""
        log_dir = Path(log_file).parent

        try:
            self.cm.copy_from_container(
                container,
                "/agent-logs/autopilot_stream_output.jsonl",
                log_dir / "autopilot_stream_output.jsonl",
            )
        except Exception:
            pass

        try:
            self.cm.copy_from_container(
                container,
                "/testbed/.workflow-state.json",
                log_dir / "workflow-state.json"
            )
        except Exception:
            pass

    def get_env_setup_script(self) -> str:
        """Get environment setup script."""
        lines = ["#!/bin/bash", ""]

        required_vars = {
            "ANTHROPIC_API_KEY": self.env_vars.get("ANTHROPIC_API_KEY", ""),
            "FORCE_AUTO_BACKGROUND_TASKS": "1",
            "ENABLE_BACKGROUND_TASKS": "1",
            "DISABLE_TELEMETRY": "1",
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
        }

        # Add model if specified
        model = self._kwargs.get("model")
        if model:
            if "/" in model:
                model = model.split("/")[-1]
            required_vars["ANTHROPIC_MODEL"] = model
            required_vars["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = model
            required_vars["ANTHROPIC_DEFAULT_SONNET_MODEL"] = model
            required_vars["ANTHROPIC_DEFAULT_OPUS_MODEL"] = model

        # Add any additional env vars
        for key, value in self.env_vars.items():
            if key not in required_vars and value:
                required_vars[key] = value

        for key, value in required_vars.items():
            if value:
                value_str = str(value)
                if 'localhost' in value_str or '127.0.0.1' in value_str:
                    value_str = value_str.replace('localhost', DOCKER_HOST_GATEWAY)
                    value_str = value_str.replace('127.0.0.1', DOCKER_HOST_GATEWAY)
                escaped_value = value_str.replace("'", "'\\''")
                lines.append(f"export {key}='{escaped_value}'")

        # Add NVM setup
        lines.extend([
            "",
            "# Load NVM",
            'export NVM_DIR="/opt/featurebench/nvm"',
            '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'
        ])

        return "\n".join(lines)


# Registry entry for FeatureBench
AGENT_REGISTRY = {
    "autopilot": AutopilotAgent
}
