from typing import Any

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
Hash Collision (HC) Game:

The adversary's goal is to find a collision in a hash function, i.e., two distinct plaintexts that produce the same hash digest.

Rules:
1. The adversary has access to a hash oracle that can compute the hash of arbitrary messages.
2. The adversary must submit two distinct plaintexts such that they hash to the same value.

The adversary wins if the two submitted plaintexts produce the same hash digest.

Session Lifecycle:
- HC is a single-stage game. The adversary must find a hash collision.
- Submitting your two plaintexts completes the game session.
- During evaluation, this game will only be played once. We therefore expect a 100% success rate.
""".strip()


class HashCollisionGameState(SecurityGameState):
    def __init__(self):
        super().__init__()

    def required_state_variables(self) -> list[str]:
        return []


class CollisionStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Find two distinct plaintexts that hash to the same value (a collision). "
            "Submit them using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"plaintext1": "<plaintext1>", "plaintext2": "<plaintext2>"}}`.\n'
            "Both `plaintext1` and `plaintext2` must be hex-encoded strings (with or without the `0x` prefix). "
            "The following conditions immediately end the session as a loss: a missing `plaintext1` or "
            "`plaintext2` field, either value not being a string, or the two plaintexts being equal after "
            "hex normalization (i.e. ignoring `0x` prefix and case).\n"
            "\n"
            "You have access to the following oracles during this stage (which you may call an arbitrary number of times):\n"
            "\n"
            "1. **Hash oracle** - Given a plaintext, returns the corresponding hash digest.\n"
            "   Example:\n"
            '   python game_controller_client.py --action oracle_query --json \'{"oracle_type": "hash", "arguments": {"plaintext": "0xabc123..."}}\'\n'
            "   Returns: hash digest as a hex string."
        )
        self._allowed_oracles = ["hash"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: HashCollisionGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        normalized, error = self._normalize_adversary_hex_fields(
            {
                "plaintext1": payload.get("plaintext1"),
                "plaintext2": payload.get("plaintext2"),
            }
        )
        if error is not None:
            return self._abort(game_state, error)

        plaintext1 = normalized["plaintext1"]
        plaintext2 = normalized["plaintext2"]

        if plaintext1 == plaintext2:
            return self._abort(game_state, "The two plaintexts must be distinct.")

        hash1_dict = self._oracle_query("hash", {"plaintext": plaintext1})
        hash2_dict = self._oracle_query("hash", {"plaintext": plaintext2})

        hash1 = hash1_dict.get("hash")
        hash2 = hash2_dict.get("hash")

        if hash1 is None or hash2 is None:
            return self._abort(
                game_state,
                hash1_dict.get("error")
                or hash2_dict.get("error")
                or "Hash oracle returned a malformed response",
            )

        game_state.finished = True
        if self._normalize_hex(hash1) == self._normalize_hex(hash2):
            game_state.success = True
            return {"Game won": "Yes"}

        game_state.success = False
        return {"Game won": "No"}


class HashCollisionGame(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = HashCollisionGameState()
        self._stages = [CollisionStage()]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> HashCollisionGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
