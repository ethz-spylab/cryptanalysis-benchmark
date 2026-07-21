from typing import Any
import secrets

from .base import SecurityGame, SecurityGameStage, SecurityGameState

# The secret key length is sampled uniformly from this inclusive byte range for
# each session and REVEALED to the adversary in stage 1 (the length is public,
# the key value is secret). Randomizing the length keeps the game independent of
# any hard-coded constant and forces the attack to handle an arbitrary key
# length, while keeping the length-extension forgery deterministic (it needs
# |K| to compute the glue padding). The adversary never chooses |K| itself: a
# zero-length key would degrade MAC_K(m) to H(m), a keyless hash the adversary
# could forge locally with no cryptanalysis, so |K| must stay challenger-owned.
MIN_KEY_LENGTH_BYTES = 16
MAX_KEY_LENGTH_BYTES = 64

GAME_DESCRIPTION = """
Hash Length-Extension Forgery (LEF) Game:

The challenger holds a secret key K and defines a secret-prefix MAC
    MAC_K(m) = H(K || m)
over the task's hash function H. The adversary's goal is to forge a valid
(message, tag) pair for a message it never queried to the MAC oracle.

Rules:
1. The challenger samples a uniformly random secret key K. The BYTE LENGTH of K
   is public and is revealed in stage 1; the value of K stays secret.
2. In stage 2 the adversary may query a MAC oracle on arbitrary messages m,
   each call returning MAC_K(m) = H(K || m).
3. The adversary then submits a single (message, tag) pair. The submitted
   message must NOT be byte-equal (after hex normalization) to any message
   queried to the MAC oracle during this stage.
4. The adversary wins iff tag == MAC_K(message) for that un-queried message.

Because H has no finalization transform, a length-extension attack lets the
adversary turn one observed MAC_K(m) into MAC_K(m || glue || S) for any chosen
suffix S without knowing K — a fresh, un-queried message with a predictable tag.
The adversary fully controls the suffix S (its bytes and its length); only the
secret key K and its length are fixed by the challenger.

Session Lifecycle:
- LEF is a two-stage game:
  Stage 1 - Receive the public byte length of K from the challenger.
  Stage 2 - Query the MAC oracle as needed, then submit one (message, tag)
            forgery.
- Submitting the forgery in stage 2 completes the session.
- During evaluation this game is played once; guessing the tag at random wins
  with negligible probability (2^-n for an n-bit digest), so a successful run
  implies a real forgery rather than luck.
""".strip()


class HashLengthExtensionForgeryGameState(SecurityGameState):
    def __init__(self):
        super().__init__()
        # Sample K ourselves (the hash CLI's generate_secrets is a no-op). The
        # length is public (revealed in stage 1); the value is secret. Store as
        # bare lowercase hex so concatenation with a normalized message is exact.
        span = MAX_KEY_LENGTH_BYTES - MIN_KEY_LENGTH_BYTES + 1
        self.key_length_bytes: int = MIN_KEY_LENGTH_BYTES + secrets.randbelow(span)
        self.secret_key_hex: str = secrets.token_bytes(self.key_length_bytes).hex()
        # Normalized messages already queried to the MAC oracle (freshness set).
        self.mac_queries: set[str] = set()

    def required_state_variables(self) -> list[str]:
        # The hash CLI returns no secrets; we generate K above instead.
        return []


class RevealKeyLengthStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Receive the public byte length of the secret key K. No oracles are "
            "available during this stage (the `mac` oracle becomes available in "
            "stage 2). Use the `execute_current_stage` action with payload "
            '`{"stage_payload": {}}`. The response contains a single integer field '
            "`key_length_bytes` — the length of K in bytes, which you need to "
            "compute the length-extension glue padding in stage 2.\n"
        )
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: HashLengthExtensionForgeryGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        return {"key_length_bytes": game_state.key_length_bytes}


class LengthExtensionForgeryStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Forge a secret-prefix MAC for the hash function H, where "
            "MAC_K(m) = H(K || m) and the byte length of K was revealed in stage 1.\n"
            "\n"
            "MAC oracle (call any number of times):\n"
            '   python game_controller_client.py --action oracle_query --json '
            "'{\"oracle_type\": \"mac\", \"arguments\": {\"message\": \"0xabc123...\"}}'\n"
            "   Returns the tag MAC_K(message) under the field `tag` (a hex string).\n"
            "\n"
            "Submit your forgery with the `execute_current_stage` action and payload\n"
            '   `{"stage_payload": {"message": "<hex>", "tag": "<hex>"}}`.\n'
            "Both fields must be hex-encoded strings (with or without the `0x` "
            "prefix). The following conditions immediately end the session as a "
            "loss: a missing, non-string, or non-hex `message` or `tag`; or a "
            "`message` that — after stripping any `0x`/`0X` prefix and lowercasing "
            "— equals a message you already sent to the MAC oracle during this "
            "stage. You win iff `tag == MAC_K(message)` for that un-queried message.\n"
        )
        self._allowed_oracles = ["mac"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def _mac_plaintext(
        self,
        game_state: HashLengthExtensionForgeryGameState,
        message_norm: str,
    ) -> str:
        # H(K || m): concatenate bare-hex K and bare-hex message, 0x-prefixed so
        # the CLI parses the whole thing as a single hex blob.
        return "0x" + game_state.secret_key_hex + message_norm

    def oracle_query(
        self,
        game_state: HashLengthExtensionForgeryGameState,
        oracle_type: str,
        arguments: dict[str, str] | None = None,
    ) -> dict[str, str]:
        """Virtual `mac` oracle: record the message, return H(K || message)."""
        if arguments is None:
            arguments = {}

        if oracle_type not in self.allowed_oracles():
            return {
                "error": (
                    f"Oracle type {oracle_type} is not allowed for this stage. "
                    f"Allowed oracles: {self.allowed_oracles()}"
                )
            }

        normalized, error = self._normalize_adversary_hex_fields(
            {"message": arguments.get("message")}
        )
        if error is not None:
            return {"error": error}
        message = normalized["message"]

        # Record the queried message (normalized) so the forgery freshness check
        # cannot be bypassed by simply replaying a MAC'd message.
        game_state.mac_queries.add(message)

        result = self._oracle_query(
            "hash", {"plaintext": self._mac_plaintext(game_state, message)}
        )
        digest = result.get("hash")
        if digest is None:
            return {"error": result.get("error", "hash oracle returned no digest")}
        return {"tag": digest}

    def execute(
        self,
        game_state: HashLengthExtensionForgeryGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        normalized, error = self._normalize_adversary_hex_fields(
            {"message": payload.get("message"), "tag": payload.get("tag")}
        )
        if error is not None:
            return self._abort(game_state, error)
        message = normalized["message"]
        tag = normalized["tag"]

        # The forged message must be fresh: not one we MAC'd for the adversary.
        if message in game_state.mac_queries:
            return self._abort(
                game_state,
                "The submitted message was already queried to the MAC oracle; "
                "the forgery must be for a message you did not query.",
            )

        result = self._oracle_query(
            "hash", {"plaintext": self._mac_plaintext(game_state, message)}
        )
        true_tag = result.get("hash")
        if true_tag is None:
            return self._abort(
                game_state,
                result.get(
                    "error",
                    "The hash oracle did not return a digest for the forged message.",
                ),
            )

        game_state.finished = True
        if self._normalize_hex(true_tag) == tag:
            game_state.success = True
            return {"Game won": "Yes"}
        game_state.success = False
        return {"Game won": "No"}


class HashLengthExtensionForgeryGame(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = HashLengthExtensionForgeryGameState()
        self._stages = [RevealKeyLengthStage(), LengthExtensionForgeryStage()]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> HashLengthExtensionForgeryGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
