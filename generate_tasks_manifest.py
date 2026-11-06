#!/usr/bin/env python3
"""Generate tasks_manifest.csv at the repo root.

Surfaces one row per cryptanalysis task in algorithms/, parsing each task's
task.toml and environment/possible_security_games.yml. The CSV is the
tabular backing of the Croissant RecordSet ("tasks") in croissant.json.
"""

from __future__ import annotations

import csv
import hashlib
import json
import sys
import tomllib
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent
ALGORITHMS_DIR = REPO_ROOT / "algorithms"
MANIFEST_PATH = REPO_ROOT / "tasks_manifest.csv"
CROISSANT_PATH = REPO_ROOT / "croissant.json"
MANIFEST_DIST_ID = "tasks-manifest"

COLUMNS = [
    "task_name",
    "security_class",
    "scheme_type",
    "algorithm_source_url",
    "allowed_security_games",
    "has_solution",
    "agent_timeout_sec",
    "verifier_timeout_sec",
]

GAME_PREFIX_TO_SCHEME = [
    ("AEAD", "aead"),
    ("KEM", "kem"),
    ("Asymmetric", "asymmetric_pke"),
    ("Signature", "signature"),
    ("Hash", "hash"),
    ("Symmetric", "symmetric"),
]


def derive_scheme_type(games: list[str]) -> str:
    for prefix, scheme in GAME_PREFIX_TO_SCHEME:
        if any(g.startswith(prefix) for g in games):
            return scheme
    return "unknown"


SECURITY_CLASSES = {"T1", "T2", "Cbase", "C"}


def derive_security_class(task_name: str) -> str:
    head, _, _ = task_name.partition("_")
    return head if head in SECURITY_CLASSES else "unknown"


def load_task(task_dir: Path) -> dict[str, object]:
    with (task_dir / "task.toml").open("rb") as f:
        toml = tomllib.load(f)
    with (task_dir / "environment" / "possible_security_games.yml").open() as f:
        games_doc = yaml.safe_load(f) or {}
    games = games_doc.get("security_games", []) or []
    metadata = toml.get("metadata", {})
    return {
        "task_name": task_dir.name,
        "security_class": derive_security_class(task_dir.name),
        "scheme_type": derive_scheme_type(games),
        "algorithm_source_url": metadata.get("algorithm_source", ""),
        "allowed_security_games": ";".join(games),
        "has_solution": (task_dir / "solution" / "solve.sh").exists(),
        "agent_timeout_sec": int(toml.get("agent", {}).get("timeout_sec", 0)),
        "verifier_timeout_sec": int(toml.get("verifier", {}).get("timeout_sec", 0)),
    }


def update_croissant_sha256(manifest_sha256: str) -> bool:
    if not CROISSANT_PATH.exists():
        return False
    with CROISSANT_PATH.open() as f:
        spec = json.load(f)
    for entry in spec.get("distribution", []):
        if entry.get("@id") == MANIFEST_DIST_ID:
            if entry.get("sha256") == manifest_sha256:
                return False
            entry["sha256"] = manifest_sha256
            with CROISSANT_PATH.open("w") as f:
                json.dump(spec, f, indent=2)
                f.write("\n")
            return True
    return False


def main() -> int:
    rows: list[dict[str, object]] = []
    for task_dir in sorted(ALGORITHMS_DIR.iterdir()):
        if not task_dir.is_dir() or task_dir.name == "00_TEMPLATE":
            continue
        rows.append(load_task(task_dir))

    with MANIFEST_PATH.open("w", newline="") as f:
        # LF line endings: the csv default (CRLF) gets rewritten to LF by the
        # mixed-line-ending pre-commit hook, which would invalidate the sha256
        # recorded in croissant.json.
        writer = csv.DictWriter(f, fieldnames=COLUMNS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    manifest_sha256 = hashlib.sha256(MANIFEST_PATH.read_bytes()).hexdigest()
    print(f"Wrote {len(rows)} rows to {MANIFEST_PATH.relative_to(REPO_ROOT)}")
    print(f"sha256: {manifest_sha256}")
    if update_croissant_sha256(manifest_sha256):
        print(f"Updated sha256 in {CROISSANT_PATH.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
