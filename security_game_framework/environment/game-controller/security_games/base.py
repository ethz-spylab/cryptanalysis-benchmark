import re
import subprocess
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any

import oracle_log

# Argument keys are always programmer-defined identifiers (e.g. `plaintext`,
# `nonce`, `key`). Restricting them to this charset prevents argument injection
# into the line-based CLI stdin protocol, where a key containing `\n` or `: `
# could smuggle additional key/value lines past the game's own bookkeeping.
_SAFE_KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*$")

# Characters that can split or truncate a line in the C-side parser
# (`getline` splits on `\n`; `\r` is a defensive guard against future parser
# changes; embedded NULs would truncate strdup'd values mid-line).
_LINE_INJECTION_RE = re.compile(r"[\n\r\x00]")

# Maximum number of key:value entries the C-side stdin parser stores per block
# (`STDIN_KV_MAX_ENTRIES` in `cli_stdin.h`). We reject over-cap argument dicts
# here, before invoking the CLI, so an adversary cannot flood dummy fields to
# push a real field past the cap and have it dropped — which would make the CLI
# operate on different inputs than the game recorded. The CLI also hard-fails on
# overflow as defense in depth, but failing early gives a clearer error.
_STDIN_KV_MAX_ENTRIES = 16


# Static functions for generating random plaintexts
def generate_random_plaintext(num_plaintexts: int = 1) -> list[str]:
    """Generates a list of random plaintexts."""
    # Check if the binary exists
    assert Path("/crypto_oracle/cli").exists(), "'cli' binary does not exist"

    result = subprocess.run(
        [
            "/crypto_oracle/cli",
            "generate_random_plaintext",
            "--batch",
            f"--count={num_plaintexts}",
        ],
        capture_output=True,
        text=True,
        cwd="/crypto_oracle",
    )

    groups = result.stdout.strip().split("\n---\n")
    return [
        line.split(":", 1)[1].strip()
        for group in groups
        for line in group.strip().split("\n")
        if ":" in line
    ]


# Static functions for generating fresh secrets for the game
def generate_secrets() -> dict[str, str]:
    """Generates the secrets for the game."""

    # Check if the binary exists
    assert Path("/crypto_oracle/cli").exists(), "'cli' binary does not exist"

    result = subprocess.run(
        ["/crypto_oracle/cli", "generate_secrets"],
        capture_output=True,
        text=True,
        cwd="/crypto_oracle",
    ).stdout.strip()

    items = result.split("\n")
    return {
        item.split(":")[0].strip(): item.split(":")[1].strip()
        for item in items
        if ":" in item
    }


class SecurityGameState(ABC):
    def __init__(self):
        self.finished = False
        self.success = False

        secrets = self._generate_secrets()

        for variable_name in self.required_state_variables():
            assert variable_name in secrets, (
                f"The game {self.__class__.__name__} requires the variable {variable_name}!"
            )

        for key, value in secrets.items():
            setattr(self, key, value)

    @abstractmethod
    def required_state_variables(self) -> list[str]:
        raise NotImplementedError

    def _generate_secrets(self) -> dict[str, str]:
        return generate_secrets()

    def _generate_random_plaintext(self, num_plaintexts: int = 1) -> list[str]:
        return generate_random_plaintext(num_plaintexts)


class SecurityGameStage(ABC):
    _HEX_DIGITS = frozenset("0123456789abcdef")

    @staticmethod
    def _normalize_hex(value: str) -> str:
        """Normalizes a hex string to a canonical form (no 0x prefix, lowercase).

        Raises ValueError if the input is not well-formed hex: odd length, or
        contains any non-hex character after stripping a single optional 0x/0X
        prefix.

        This must be used whenever comparing or recording adversary-supplied hex
        values, because the C CLI silently strips the 0x/0X prefix and is
        case-insensitive. Without normalization an adversary can trivially bypass
        distinctness / freshness checks (e.g. "01" vs "0x01"). Strict validation
        is required because the C parser is also lenient about non-hex chars
        (e.g. "0x0x01" decodes to the same bytes as "0x0001"), so anything that
        bypasses validation here can smuggle past distinctness checks too.
        """
        v = value.strip()
        if v.startswith(("0x", "0X")):
            v = v[2:]
        v = v.lower()
        if len(v) % 2 != 0 or not all(c in SecurityGameStage._HEX_DIGITS for c in v):
            raise ValueError(f"Invalid hex string: {value!r}")
        return v

    @staticmethod
    def _normalize_adversary_hex_fields(
        raw_fields: dict[str, Any],
    ) -> tuple[dict[str, str] | None, str | None]:
        """Normalize a dict of adversary-supplied hex fields.

        Returns (normalized, None) on success, or (None, error_message) if any
        value is missing, not a string, or not valid hex. The error_message is
        a plain string; pass it to `_abort` (or wrap it as `{"error": msg}` if
        you only want to fail the current oracle call without ending the game).
        """
        normalized: dict[str, str] = {}
        for name, value in raw_fields.items():
            if value is None:
                return None, f"`{name}` is required"
            if not isinstance(value, str):
                return None, f"`{name}` must be a hex-encoded string"
            try:
                normalized[name] = SecurityGameStage._normalize_hex(value)
            except ValueError:
                return None, (
                    f"`{name}` is not a valid hex string (must contain only "
                    "hex digits, optionally prefixed by `0x`/`0X`, and have "
                    "even length)"
                )
        return normalized, None

    @staticmethod
    def _normalize_adversary_hex_list(
        name: str, values: Any
    ) -> tuple[list[str] | None, str | None]:
        """Normalize a list of adversary-supplied hex values.

        Returns (normalized, None) on success, or (None, error_message) on the
        first invalid entry. Error messages include the index of the bad entry.
        Use this for payload fields that are JSON lists of hex strings.
        """
        if values is None:
            return None, f"`{name}` is required"
        if not isinstance(values, list):
            return None, f"`{name}` must be a list of hex-encoded strings"
        normalized: list[str] = []
        for i, value in enumerate(values):
            if value is None:
                return None, f"`{name}[{i}]` is required"
            if not isinstance(value, str):
                return None, f"`{name}[{i}]` must be a hex-encoded string"
            try:
                normalized.append(SecurityGameStage._normalize_hex(value))
            except ValueError:
                return None, (
                    f"`{name}[{i}]` is not a valid hex string (must contain "
                    "only hex digits, optionally prefixed by `0x`/`0X`, and "
                    "have even length)"
                )
        return normalized, None

    @staticmethod
    def _abort(game_state: "SecurityGameState", error: str) -> dict[str, str]:
        """End the game as a loss and return a standard error response.

        Use this whenever a stage decides the adversary has lost (invalid
        input, oracle failure, distinctness violation, etc.). Sets
        `game_state.finished = True` and `game_state.success = False`, then
        returns `{"Game won": "No", "error": <error>}` which the caller
        should return directly from `execute`.
        """
        game_state.finished = True
        game_state.success = False
        return {"Game won": "No", "error": error}

    @abstractmethod
    def stage_description(self) -> str:
        raise NotImplementedError

    @abstractmethod
    def allowed_oracles(self) -> list[str]:
        raise NotImplementedError

    @abstractmethod
    def execute(
        self, game_state: SecurityGameState, payload: dict[str, Any]
    ) -> dict[str, Any] | None:
        raise NotImplementedError

    @staticmethod
    def _parse_output(output: str) -> dict[str, str]:
        """Parses 'name: value' output lines into a dictionary."""
        items = output.split("\n")
        return {
            item.split(":", 1)[0].strip(): item.split(":", 1)[1].strip()
            for item in items
            if ":" in item
        }

    @staticmethod
    def _cli_error_dict(
        returncode: int, stderr: str, parsed_keys: list[str] | None = None
    ) -> dict[str, str]:
        """Build a structured error response describing a failed CLI invocation."""
        message = stderr.strip() or "<no stderr>"
        if returncode != 0:
            return {"error": (f"Oracle CLI exited with code {returncode}: {message}")}
        if parsed_keys is not None and not parsed_keys:
            return {
                "error": (
                    f"Oracle CLI returned no parseable output (stderr: {message})"
                )
            }
        return {"error": f"Oracle CLI failure (stderr: {message})"}

    @staticmethod
    def _validate_arguments(arguments: dict[str, Any]) -> str | None:
        """Reject argument dicts that could inject lines into the CLI stdin.

        Validates both keys and values: keys must be identifier-shaped
        (``_SAFE_KEY_RE``) and values must be strings free of line-splitting
        characters (``_LINE_INJECTION_RE``). Returns an error message on the
        first violation, or ``None`` if all pairs are clean.

        Legitimate callers always satisfy these constraints, so this only
        fires on adversarial input — we surface it as an error (and log it)
        rather than silently sanitizing, so injection attempts show up in
        the JSONL trace.
        """
        for key, value in arguments.items():
            if not isinstance(key, str) or not _SAFE_KEY_RE.fullmatch(key):
                return (
                    f"Invalid argument key {key!r}: keys must match "
                    "[A-Za-z_][A-Za-z0-9_-]* (no whitespace, newlines, or "
                    "punctuation)."
                )
            if not isinstance(value, str):
                return f"Argument value for key {key!r} must be a string."
            if _LINE_INJECTION_RE.search(value):
                return (
                    f"Argument value for key {key!r} contains a forbidden "
                    "control character (newline, carriage return, or NUL)."
                )
        return None

    def _oracle_query(
        self,
        oracle_type: str,
        arguments: dict[str, str] = {},
    ) -> dict[str, str]:
        """Implements the actual oracle query logic.

        Returns a `{"error": "..."}` dict if the CLI exits non-zero or produces
        no parseable stdout. Callers should check for `"error" in result` (or
        for the absence of the keys they expect) before indexing the result.

        Every call (including stage-injected ground truth such as eval
        plaintexts) is written verbatim to the oracle log, which is protected by
        file permissions rather than redaction (see ``oracle_log``).
        """
        # Check if the binary exists
        assert Path("/crypto_oracle/cli").exists(), "'cli' binary does not exist"

        validation_error = self._validate_arguments(arguments)
        if validation_error is not None:
            response = {"error": validation_error}
            oracle_log.record("single", oracle_type, arguments, response)
            return response

        if len(arguments) > _STDIN_KV_MAX_ENTRIES:
            response = {
                "error": (
                    f"Too many oracle arguments: {len(arguments)} "
                    f"(max {_STDIN_KV_MAX_ENTRIES})."
                )
            }
            oracle_log.record("single", oracle_type, arguments, response)
            return response

        command = ["/crypto_oracle/cli", oracle_type]

        # Keys and values are validated above, so the format is injection-safe.
        stdin_data = (
            "\n".join(f"{k}: {v}" for k, v in arguments.items()) if arguments else None
        )

        result = subprocess.run(
            command,
            input=stdin_data,
            capture_output=True,
            text=True,
            cwd="/crypto_oracle",
        )
        print(f"Oracle query result: {result.stdout.strip()}")
        print(f"Oracle query error: {result.stderr.strip()}")

        if result.returncode != 0:
            response = self._cli_error_dict(result.returncode, result.stderr)
        else:
            parsed = self._parse_output(result.stdout.strip())
            if not parsed:
                response = self._cli_error_dict(
                    result.returncode, result.stderr, parsed_keys=[]
                )
            else:
                response = parsed
        oracle_log.record("single", oracle_type, arguments, response)
        return response

    def _batched_oracle_query(
        self,
        oracle_type: str,
        argument_dicts: list[dict[str, str]],
    ) -> list[dict[str, str]]:
        """Batches the oracle queries into a single subprocess call.

        On CLI failure (non-zero exit), returns a list of error dicts with the
        same length as the input list — one error per query — so callers can
        treat per-query failures uniformly. On success, any individual block
        that fails to parse is also returned as a `{"error": "..."}` dict.
        """
        # Check if the binary exists
        assert Path("/crypto_oracle/cli").exists(), "'cli' binary does not exist"

        for d in argument_dicts:
            validation_error = self._validate_arguments(d)
            if validation_error is not None:
                error = {"error": validation_error}
                parsed_groups = [error for _ in argument_dicts]
                oracle_log.record("batch", oracle_type, argument_dicts, parsed_groups)
                return parsed_groups
            if len(d) > _STDIN_KV_MAX_ENTRIES:
                error = {
                    "error": (
                        f"Too many oracle arguments: {len(d)} "
                        f"(max {_STDIN_KV_MAX_ENTRIES})."
                    )
                }
                parsed_groups = [error for _ in argument_dicts]
                oracle_log.record("batch", oracle_type, argument_dicts, parsed_groups)
                return parsed_groups

        # Keys and values are validated above, so the format is injection-safe.
        blocks = ["\n".join(f"{k}: {v}" for k, v in d.items()) for d in argument_dicts]
        stdin_data = "\n---\n".join(blocks)

        result = subprocess.run(
            ["/crypto_oracle/cli", oracle_type, "--batch"],
            input=stdin_data,
            capture_output=True,
            text=True,
            cwd="/crypto_oracle",
        )
        print(f"Oracle query result: {result.stdout.strip()}")
        print(f"Oracle query error: {result.stderr.strip()}")

        if result.returncode != 0:
            error = self._cli_error_dict(result.returncode, result.stderr)
            parsed_groups = [error for _ in argument_dicts]
        else:
            groups = result.stdout.strip().split("\n---\n")
            parsed_groups = []
            for group in groups:
                parsed = self._parse_output(group.strip())
                if not parsed:
                    parsed_groups.append(
                        self._cli_error_dict(
                            result.returncode, result.stderr, parsed_keys=[]
                        )
                    )
                else:
                    parsed_groups.append(parsed)
        oracle_log.record("batch", oracle_type, argument_dicts, parsed_groups)
        return parsed_groups

    def _generate_random_plaintext(self, num_plaintexts: int = 1) -> list[str]:
        return generate_random_plaintext(num_plaintexts)

    def oracle_query(
        self,
        game_state: SecurityGameState,
        oracle_type: str,
        arguments: dict[str, str] | None = None,
    ) -> dict[str, str]:
        if arguments is None:
            arguments = {}

        if oracle_type not in self.allowed_oracles():
            return {
                "error": f"Oracle type {oracle_type} is not allowed for this stage. Allowed oracles: {self.allowed_oracles()}"
            }

        return self._oracle_query(oracle_type, arguments)


class SecurityGame(ABC):
    def __init__(self):
        self.current_stage_index = 0

    @abstractmethod
    def game_description(self) -> str:
        raise NotImplementedError

    @abstractmethod
    def game_state(self) -> SecurityGameState:
        raise NotImplementedError

    @abstractmethod
    def stages(self) -> list[SecurityGameStage]:
        raise NotImplementedError

    def game_status(self) -> dict[str, Any]:
        return {
            "finished": self.finished(),
            "success": self.success(),
            "game_description": self.game_description(),
            "current_stage": self.current_stage_index,
            "current_stage_description": self.stages()[
                self.current_stage_index
            ].stage_description()
            if self.current_stage_index < len(self.stages())
            else "Game is finished. Start a new game to play again.",
            "stages": len(self.stages()),
        }

    def finished(self) -> bool:
        return self.game_state().finished

    def success(self) -> bool:
        return self.game_state().success

    def execute_current_stage(self, payload: dict[str, Any]) -> dict[str, Any] | None:
        # Any oracle calls a stage's `execute` makes (challenge generation,
        # verification, eval encryptions, ...) are the game's own, not the
        # adversary's — tag them so the offline analysis can tell them apart.
        oracle_log.set_source("game")

        if self.finished():
            return {"error": "Game is finished. Start a new game to play again."}

        assert self.current_stage_index < len(self.stages()), (
            f"Current stage index is out of bounds. Current stage index: {self.current_stage_index}, number of stages: {len(self.stages())}"
        )

        current_stage = self.stages()[self.current_stage_index]
        result = current_stage.execute(self.game_state(), payload)
        self.current_stage_index += 1
        return result

    def oracle_query(
        self,
        oracle_type: str,
        arguments: dict[str, str] | None = None,
    ) -> dict[str, str]:
        # This is the adversary's explicit oracle-query entry point; tag every
        # resulting oracle call as agent-initiated.
        oracle_log.set_source("agent")

        if self.finished():
            return {"error": "Game is finished. Start a new game to query the oracle."}

        if arguments is None:
            arguments = {}

        current_stage = self.stages()[self.current_stage_index]
        return current_stage.oracle_query(self.game_state(), oracle_type, arguments)
