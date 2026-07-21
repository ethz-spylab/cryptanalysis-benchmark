from typing import Any
import secrets
from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
Hash Second-Preimage (SP) Game:

The adversary's goal is to break the second-preimage resistance of a hash
function: given a target plaintext x sampled by the challenger, find any
*distinct* plaintext x' (x' != x) that produces the same hash digest, i.e.
hash(x') == hash(x).

Rules:
1. In stage 1 the challenger samples a uniformly random target plaintext x
   (a fixed-length random byte string) and reveals it to the adversary.
2. In stage 2 the adversary submits a single plaintext x'. The submission
   must be distinct from the challenge plaintext (compared after stripping
   any `0x`/`0X` prefix and lowercasing — see `_normalize_hex`); submitting
   the challenge itself counts as an immediate loss. The adversary may
   adaptively query a `hash` oracle on arbitrary messages while searching.
3. The adversary wins iff hash(x') == hash(x) and x' is distinct from x.

This is strictly easier to define and harder to win than a generic collision
(the target x is fixed and adversary-uncontrolled). For an n-bit hash the
generic attack costs ~2^n work, vs ~2^(n/2) for collisions, so any
non-trivial second-preimage attack against a hash with even moderate
output length is a strong attack.

Session Lifecycle:
- This is a two-stage game:
  Stage 1 - Receive the challenge plaintext x from the challenger.
  Stage 2 - Adaptively query the `hash` oracle, then submit a single
            second-preimage candidate x'.
- Submitting the candidate in stage 2 completes the game session.
- During evaluation, this game is played a single time per session — random
  guessing wins with negligible probability (2^-n for an n-bit digest), so
  a successful run implies an actual second-preimage attack rather than
  luck.
""".strip()


class HashSecondPreimageGameState(SecurityGameState):
    def __init__(self):
        super().__init__()
        # 64 nibbles = 256 bits.
        random_nibbles = [secrets.randbelow(16) for _ in range(64)]
        self.challenge_plaintext: str = "0x" + "".join(
            format(nibble, "x") for nibble in random_nibbles
        )

    def required_state_variables(self) -> list[str]:
        return []


class GetChallengePlaintextStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Receive the challenge plaintext x from the challenger. No oracles are available during "
            "this stage (the `hash` oracle becomes available in stage 2). Use the "
            '`execute_current_stage` action with payload `{"stage_payload": {}}`. The response '
            "contains a single hex-encoded field `challenge_plaintext` — the target plaintext x for "
            "which you must find a distinct second preimage in stage 2.\n"
        )
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: HashSecondPreimageGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        return {
            "challenge_plaintext": game_state.challenge_plaintext,
        }


class SubmitSecondPreimageStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Find a second preimage x' for the challenge plaintext x revealed in stage 1: any "
            "single hex-encoded plaintext that is *distinct* from x but produces the same hash "
            "digest. Submit it using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"plaintext": "<x_prime_hex>"}}` (note: a single field named '
            "`plaintext`, not `plaintext1`/`plaintext2`).\n"
            "\n"
            "Distinctness is checked after stripping any `0x`/`0X` prefix and lowercasing both "
            "strings (see `_normalize_hex`). Submitting a value that normalizes to the challenge "
            "is an immediate loss. You may also locally compute hashes with the algorithm of your "
            "choice; the oracle is provided for convenience.\n"
            "\n"
            "You may call the following oracle an arbitrary number of times during this stage:\n"
            "\n"
            "1. **Hash oracle** - Given a plaintext, returns the corresponding hash digest under "
            "the field `hash`.\n"
            "   Example:\n"
            '   python game_controller_client.py --action oracle_query --json \'{"oracle_type": "hash", "arguments": {"plaintext": "0xabc123..."}}\'\n'
        )
        self._allowed_oracles = ["hash"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: HashSecondPreimageGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        normalized, error = self._normalize_adversary_hex_fields(
            {"plaintext": payload.get("plaintext")}
        )
        if error is not None:
            return self._abort(game_state, error)
        plaintext = normalized["plaintext"]

        if plaintext == self._normalize_hex(game_state.challenge_plaintext):
            return self._abort(
                game_state,
                "The plaintext must be distinct from the challenge plaintext.",
            )

        hash1 = self._oracle_query("hash", {"plaintext": plaintext})
        hash2 = self._oracle_query(
            "hash", {"plaintext": game_state.challenge_plaintext}
        )

        digest1 = hash1.get("hash")
        digest2 = hash2.get("hash")
        if digest1 is None or digest2 is None:
            return self._abort(
                game_state,
                hash1.get("error")
                or hash2.get("error")
                or "The hash oracle did not return a digest for one of the plaintexts.",
            )

        game_state.finished = True
        if self._normalize_hex(digest1) == self._normalize_hex(digest2):
            game_state.success = True
            return {"Game won": "Yes"}
        game_state.success = False
        return {"Game won": "No"}


class HashSecondPreimageGame(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = HashSecondPreimageGameState()
        self._stages = [GetChallengePlaintextStage(), SubmitSecondPreimageStage()]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> HashSecondPreimageGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
