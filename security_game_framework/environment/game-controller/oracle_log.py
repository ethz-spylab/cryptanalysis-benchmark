import contextvars
import json
import os
import threading
import time
import uuid
from pathlib import Path
from typing import Any

# The game controller streams every oracle call to an append-only JSONL file in
# a directory that is bind-mounted ONLY into this container (see the
# game_controller `volumes` in docker-compose.yaml). That directory is NOT
# mounted into `main`, so neither the agent (UID 5000) nor the verifier can
# reach it — there is no shared path and no network endpoint. Confidentiality of
# the ground-truth values in the log (secret keys, eval plaintexts, ...) thus
# comes from container isolation, which is why the log is stored un-redacted.
#
# The mount is a *host* directory (default <project>/logs/oracle_logs), so it
# survives `docker compose down --volumes` at teardown (that flag removes
# named/anonymous volumes, not bind mounts) and can be inspected offline.
#
# Logs are grouped per run: we write into a `<run-id>` subdirectory whose name
# matches Harbor's `jobs/<run-id>/` timestamp, derived from the verifier host
# path Harbor passes in (HARBOR_VERIFIER_HOST_PATH ==
# <project>/jobs/<run-id>/<trial>/verifier). All trials of a run share that
# subdirectory; each controller writes its own uniquely-named file (one file ==
# one trial, since every trial gets its own game_controller), so concurrent
# trials never collide.
#
# Every entry carries its `game_id`. An offline analysis program splits
# exploration vs verification calls by joining those ids against the per-trial
# verification_game_ids.txt that tests/test_attack.py records (and which Harbor
# collects into jobs/<run-id>/<trial>/verifier/).
#
# Every entry also carries a `source` ("agent" / "game"): whether the call was
# an explicit oracle query the adversary issued (`/oracle_query` -> agent) or an
# internal call the game made while running stage logic such as challenge
# generation or verification (`/execute_current_stage` -> game). This is set at
# the two public entry points in SecurityGame (see security_games/base.py) and
# read here when the entry is written. A ContextVar (rather than a plain global)
# keeps the tag correct even when FastAPI dispatches the synchronous endpoints
# across threadpool workers — each request gets its own copy of the context.


def _derive_run_id() -> str:
    """Return the run-id (matching Harbor's ``jobs/<run-id>/`` folder).

    ``HARBOR_VERIFIER_HOST_PATH`` looks like
    ``<project>/jobs/<run-id>/<trial>/verifier``; the run-id is the component
    right after the last ``jobs`` segment. Falls back to a timestamp when the
    hint is absent (e.g. an interactive ``harbor task start-env``).
    """
    hint = os.environ.get("HARBOR_VERIFIER_HOST_PATH", "")
    parts = [p for p in hint.replace("\\", "/").split("/") if p]
    if "jobs" in parts:
        last_jobs = len(parts) - 1 - parts[::-1].index("jobs")
        if last_jobs + 1 < len(parts):
            return parts[last_jobs + 1]
    return time.strftime("adhoc_%Y-%m-%d__%H-%M-%S")


LOG_ROOT = Path(os.environ.get("ORACLE_LOG_DIR", "/oracle_logs"))
LOG_DIR = LOG_ROOT / _derive_run_id()
LOG_FILE = LOG_DIR / f"oracle_log_{uuid.uuid4().hex}.jsonl"

_lock = threading.Lock()
_current_game_id: str | None = None
_current_game_name: str | None = None

# Who triggered the oracle call currently being served: "agent" (an explicit
# `/oracle_query`) or "game" (internal challenge/verification logic run inside
# `/execute_current_stage`). Defaults to "unknown" so a record written outside
# either entry point is still flagged rather than silently mis-attributed.
_source: contextvars.ContextVar[str] = contextvars.ContextVar(
    "oracle_call_source", default="unknown"
)


def set_source(source: str) -> None:
    """Tag who triggered the oracle calls in the current request context.

    Call this at a request entry point (see SecurityGame.oracle_query /
    execute_current_stage in security_games/base.py); every `record` made while
    serving that request then carries the given `source`.
    """
    _source.set(source)


def init() -> None:
    """Ensure the per-run log directory exists.

    Best-effort: if the mount is absent (e.g. an interactive ``harbor task
    start-env``) we must not crash the controller, so failures are swallowed.
    """
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
    except OSError as e:
        print(f"oracle_log.init: could not create {LOG_DIR}: {e}")


def set_current_game(game_id: str, game_name: str) -> None:
    global _current_game_id, _current_game_name
    with _lock:
        _current_game_id = game_id
        _current_game_name = game_name


def record(kind: str, oracle_type: str, arguments: Any, response: Any) -> None:
    with _lock:
        entry = {
            "timestamp": time.time(),
            "game_id": _current_game_id,
            "game_name": _current_game_name,
            "source": _source.get(),
            "kind": kind,
            "oracle_type": oracle_type,
            "arguments": arguments,
            "response": response,
        }
        line = json.dumps(entry, ensure_ascii=False) + "\n"
        try:
            with open(LOG_FILE, "a", encoding="utf-8") as f:
                f.write(line)
        except OSError as e:
            print(f"oracle_log.record: could not write {LOG_FILE}: {e}")
