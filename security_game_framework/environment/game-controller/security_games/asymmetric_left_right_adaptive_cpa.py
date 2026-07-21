from typing import Any
import secrets

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
Asymmetric Left-or-Right Adaptive IND-CPA Game:

Public-key variant of the left-or-right adaptive IND-CPA game. The adversary's
goal is to determine a hidden challenge bit b chosen once per session by the
challenger, using adaptive access to a "left-or-right" encryption oracle under
the challenger's public key. In the public-key setting the adversary can
already encrypt arbitrary plaintexts themselves on the public key, so the LR
oracle is what makes the game non-trivial: it is the only way to learn a
ciphertext whose choice of plaintext is controlled by the hidden bit b.

Rules:
1. At the start of the session, the challenger generates a random
   public/private keypair and samples a uniformly random challenge bit b in
   {0, 1}. The bit and the private key are kept hidden; the public key is
   revealed to the adversary (retrieved in stage 1, and also used internally
   by the LR oracle). All three are fixed for the entire session.
2. The adversary may adaptively make any number of queries to a left-or-right
   `encrypt` oracle. Each query provides two plaintexts, plaintext1 and
   plaintext2, of equal non-zero byte length. The oracle returns the
   encryption of plaintext1 if b == 0 or plaintext2 if b == 1, under the
   challenger's public key. The same challenge bit is reused across all
   oracle queries within a session.
3. At any point, the adversary must output a guess for b (i.e. 0 or 1).

The adversary wins if the submitted bit guess equals the bit b that the
challenger sampled. Note: for randomized public-key schemes this is the
standard IND-CPA game (equivalent by hybrid argument to the single-query
formulation); for deterministic public-key schemes the game is trivially
winnable (encrypt plaintext1 yourself on the public key and compare against
the LR-oracle reply), which means such schemes should not be used.

Session Lifecycle:
- This is a two-stage game:
  Stage 1 - Retrieve the challenger's public key.
  Stage 2 - Optionally query the left-or-right `encrypt` oracle as many
            times as desired, then submit your guess of the challenger's
            secret bit b (0 or 1). Submitting the guess completes the game
            session.
- During evaluation, this game will be played 20 times (independent sessions,
  each with a freshly sampled keypair and challenge bit). The adversary must
  win at least 17 out of 20 sessions to pass; note that a trivial random
  guess only wins ~50% of sessions in expectation, so a non-trivial
  distinguisher is required.
""".strip()


class AsymmetricLeftRightAdaptiveCPAGameState(SecurityGameState):
    def __init__(self):
        super().__init__()
        self.sampled_bit: int = secrets.randbelow(2)

    def required_state_variables(self) -> list[str]:
        return ["public_key", "private_key"]


class GetPublicKeyStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Retrieve the challenger's public key. No oracles are available during this stage. Use the "
            '`execute_current_stage` action with payload `{"stage_payload": {}}`; the response contains '
            "the public key as a hex-encoded string under the `public-key` field. You will need this "
            "public key to encrypt arbitrary plaintexts yourself (the public-key scheme's encrypt "
            "algorithm on this key is the equivalent of a CPA oracle) as well as to check your "
            "distinguisher against freshly sampled plaintexts.\n"
        )
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: AsymmetricLeftRightAdaptiveCPAGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        return {
            "public-key": game_state.public_key,
        }


class DistinguishStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Final stage of the game. The challenger has already sampled a hidden challenge bit b in "
            "{0, 1} (fixed for the entire session). You may adaptively query the left-or-right `encrypt` "
            "oracle any number of times: each query takes two plaintexts and returns the encryption of "
            "the left one if b == 0 or the right one if b == 1, under the challenger's public key (any "
            "public-key value the adversary supplies is ignored — the oracle always uses the public key "
            "from stage 1). When ready, submit your guess for b to end the session.\n"
            "\n"
            'Query the oracle using the `oracle_query` action with `oracle_type = "encrypt"` and '
            'arguments `{"plaintext1": "<hex_plaintext_1>", "plaintext2": "<hex_plaintext_2>"}`. Both '
            "plaintexts must be non-empty hex-encoded strings (with or without the `0x` prefix) and "
            "must have the same byte length. Each plaintext should also be of the length expected by "
            "the underlying public-key encryption scheme. Submitting `plaintext1 == plaintext2` is "
            "allowed but, for any randomized public-key scheme, leaves the ciphertext's distribution "
            "independent of the challenger's bit. Malformed oracle queries (missing plaintext, "
            "non-string value, empty plaintext, or plaintexts of unequal byte length) return an error "
            "but do not end the session, so you may retry.\n"
            "\n"
            "Submit your final guess using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"sampled_bit_guess": <0 or 1>}}`. Use 0 if you think the oracle was '
            "returning encryptions of the left plaintexts, or 1 for the right plaintexts. You win iff "
            "your guess equals the bit the challenger actually sampled. Submitting the guess completes "
            "the game session.\n"
        )
        self._allowed_oracles = ["encrypt"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def oracle_query(
        self,
        game_state: AsymmetricLeftRightAdaptiveCPAGameState,
        oracle_type: str,
        arguments: dict[str, str] | None = None,
    ) -> dict[str, str]:
        if oracle_type not in self.allowed_oracles():
            return {
                "error": f"Oracle type {oracle_type} is not allowed for this stage. Allowed oracles: {self.allowed_oracles()}"
            }

        arguments = arguments or {}
        normalized, error = self._normalize_adversary_hex_fields(
            {
                "plaintext1": arguments.get("plaintext1"),
                "plaintext2": arguments.get("plaintext2"),
            }
        )
        if error is not None:
            return {"error": error}
        message1 = normalized["plaintext1"]
        message2 = normalized["plaintext2"]

        if len(message1) == 0 or len(message2) == 0:
            return {"error": "`plaintext1` and `plaintext2` must be non-empty"}

        if len(message1) != len(message2):
            return {
                "error": "`plaintext1` and `plaintext2` must be of the same byte length"
            }

        chosen_message = message1 if game_state.sampled_bit == 0 else message2

        return self._oracle_query(
            "encrypt",
            {
                "plaintext": chosen_message,
                "public-key": game_state.public_key,
            },
        )

    def execute(
        self,
        game_state: AsymmetricLeftRightAdaptiveCPAGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        raw_guess = payload.get("sampled_bit_guess")
        if raw_guess is None:
            return self._abort(game_state, "`sampled_bit_guess` is required")

        try:
            bit_guess = int(raw_guess)
        except (TypeError, ValueError):
            return self._abort(
                game_state, "`sampled_bit_guess` must be the integer 0 or 1"
            )

        if bit_guess not in (0, 1):
            return self._abort(
                game_state, "`sampled_bit_guess` must be the integer 0 or 1"
            )

        game_state.success = bit_guess == game_state.sampled_bit
        game_state.finished = True

        return {"Game won": "Yes" if game_state.success else "No"}


class AsymmetricLeftRightAdaptiveCPAGame(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = AsymmetricLeftRightAdaptiveCPAGameState()
        self._stages = [GetPublicKeyStage(), DistinguishStage()]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> AsymmetricLeftRightAdaptiveCPAGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
