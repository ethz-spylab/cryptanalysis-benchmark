#!/usr/bin/env python3
"""
Reads task.toml and replaces placeholders in instruction.md with actual values.

This script expects to be run from a task directory containing both task.toml
and instruction.md files in the same directory as this script.
"""

import os
import re
import tomllib
from pathlib import Path

# Timeout overrides supplied via env vars by generate_harbor_tasks.sh. Each entry
# maps an env var to the (section, key) in task.toml it overwrites. An unset or
# empty env var means "leave the existing task.toml value untouched".
TIMEOUT_OVERRIDES = [
    ("OVERRIDE_VERIFIER_TIMEOUT_SEC", "verifier", "timeout_sec"),
    ("OVERRIDE_AGENT_TIMEOUT_SEC", "agent", "timeout_sec"),
    ("OVERRIDE_ENVIRONMENT_BUILD_TIMEOUT_SEC", "environment", "build_timeout_sec"),
]


def apply_timeout_overrides(task_toml_path):
    """Overwrite timeout values in task.toml from OVERRIDE_* env vars.

    Edits are section-aware and line-based: ``timeout_sec`` appears under both
    ``[verifier]`` and ``[agent]``, so a blind global replace would be wrong. We
    avoid a TOML writer dependency (tomllib is read-only) since these are simple
    scalar keys, and line-based editing preserves comments and formatting.
    """
    overrides = {
        (section, key): os.environ[env_var]
        for env_var, section, key in TIMEOUT_OVERRIDES
        if os.environ.get(env_var)
    }
    if not overrides:
        return

    with open(task_toml_path, "r") as f:
        lines = f.readlines()

    current_section = None
    for i, line in enumerate(lines):
        header = re.match(r"\s*\[([^\]]+)\]", line)
        if header:
            current_section = header.group(1)
            continue

        key_match = re.match(r"(\s*)([A-Za-z0-9_]+)(\s*=\s*).*", line)
        if not key_match:
            continue

        key = key_match.group(2)
        if (current_section, key) in overrides:
            value = overrides[(current_section, key)]
            lines[i] = f"{key_match.group(1)}{key}{key_match.group(3)}{value}\n"

    with open(task_toml_path, "w") as f:
        f.writelines(lines)


def main():
    # Get the directory where this script is located
    script_dir = Path(__file__).parent.resolve()

    # Define paths relative to the script location
    task_toml_path = script_dir / "task.toml"
    instruction_md_path = script_dir / "instruction.md"

    # Apply any timeout overrides to task.toml before reading it, so both the
    # task config and the instruction.md placeholders below reflect the override.
    apply_timeout_overrides(task_toml_path)

    # Read and parse task.toml
    with open(task_toml_path, "rb") as f:
        config = tomllib.load(f)

    # Extract values from the three sections
    verifier = config.get("verifier", {})
    agent = config.get("agent", {})
    environment = config.get("environment", {})

    # Build placeholder mapping
    placeholders = {
        "{{VERIFIER_TIMEOUT_SEC}}": str(verifier.get("timeout_sec", "N/A")),
        "{{AGENT_TIMEOUT_SEC}}": str(agent.get("timeout_sec", "N/A")),
        "{{ENVIRONMENT_BUILD_TIMEOUT_SEC}}": str(
            environment.get("build_timeout_sec", "N/A")
        ),
        "{{ENVIRONMENT_CPUS}}": str(environment.get("cpus", "N/A")),
        "{{ENVIRONMENT_MEMORY_MB}}": str(environment.get("memory_mb", "N/A")),
        "{{ENVIRONMENT_STORAGE_MB}}": str(environment.get("storage_mb", "N/A")),
    }

    # Read instruction.md
    with open(instruction_md_path, "r") as f:
        content = f.read()

    # Replace all placeholders
    for placeholder, value in placeholders.items():
        content = content.replace(placeholder, value)

    # Write back the modified content
    with open(instruction_md_path, "w") as f:
        f.write(content)

    print(f"Successfully processed {instruction_md_path}")
    print(f"Replaced placeholders with values from {task_toml_path}")


if __name__ == "__main__":
    main()
