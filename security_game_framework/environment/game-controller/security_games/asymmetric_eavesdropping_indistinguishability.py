from typing import Any
import secrets

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
Asymmetric Eavesdropping Indistinguishability (IND) Game:

Public-key variant of the standard indistinguishability game. The adversary's
goal is to distinguish which of two adversary-chosen messages was encrypted
under the challenger's public key. The challenger's private key is never
revealed, but the public key is handed to the adversary at the start — so in
the public-key setting the adversary can freely encrypt arbitrary plaintexts
themselves (there is no separate encryption oracle; just run the scheme's
encrypt function on the public key you were given).

Rules:
1. The challenger generates a random public/private keypair. The public key
   is handed to the adversary at the start of the game; the private key is
   kept hidden.
2. The adversary submits two messages, message1 and message2, of equal
   non-zero byte length.
3. The challenger uses a uniformly random challenge bit b in {0, 1}, sampled
   once at the start of the session and kept hidden, to encrypt message1 if
   b == 0 or message2 if b == 1 under the public key, and returns the
   resulting challenge ciphertext.
4. The adversary must then output a guess for b (i.e. 0 or 1, indicating
   which of the two messages was encrypted).

The adversary wins if the submitted bit guess equals the bit b that the
challenger actually sampled. Note: for randomized public-key schemes this is
equivalent to IND-CPA because the adversary can encrypt anything they want
with the public key; for deterministic public-key schemes the game is
trivially winnable by the adversary (just encrypt message1 under the public
key and compare), which means such schemes should not be used.

Session Lifecycle:
- This is a three-stage game:
  Stage 1 - Retrieve the challenger's public key.
  Stage 2 - Submit the two candidate messages; the challenger encrypts one
            of them under the public key and returns the challenge ciphertext.
  Stage 3 - Submit your guess of the challenger's secret bit b (0 or 1).
- Submitting the guess in stage 3 completes the game session.
- During evaluation, this game will be played 20 times (independent sessions,
  each with a freshly sampled keypair and challenge bit). The adversary must
  win at least 17 out of 20 sessions to pass; note that a trivial random
  guess only wins ~50% of sessions in expectation, so a non-trivial
  distinguisher is required.
""".strip()


class AsymmetricEavesdroppingIndistinguishabilityGameState(SecurityGameState):
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
        game_state: AsymmetricEavesdroppingIndistinguishabilityGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        return {
            "public-key": game_state.public_key,
        }


class MessageEncryptionStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Submit two candidate messages. The game will use its hidden challenge bit b in {0, 1} "
            "(sampled once at the start of the session) to encrypt message1 (if b == 0) or message2 "
            "(if b == 1) under the challenger's public key, and return the resulting challenge "
            "ciphertext. No oracles are available during this stage — the adversary is expected to "
            "encrypt arbitrary plaintexts themselves using the public key obtained in the previous "
            "stage.\n"
            "\n"
            "Submit the two messages using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"message1": "<hex_message_1>", "message2": "<hex_message_2>"}}`.\n'
            "Both messages must be non-empty hex-encoded strings (with or without the `0x` prefix) and "
            "must have the same byte length. The following conditions immediately end the session as a "
            "loss: a missing message, a value that is not a string, an empty message, or messages of "
            "unequal byte length. Each message should also be of the length expected by the underlying "
            "public-key encryption scheme. Submitting two equal messages is allowed but, for any "
            "randomized public-key scheme, leaves the ciphertext's distribution independent of the "
            "challenger's bit and reduces the adversary to random guessing.\n"
        )
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: AsymmetricEavesdroppingIndistinguishabilityGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        normalized, error = self._normalize_adversary_hex_fields(
            {
                "message1": payload.get("message1"),
                "message2": payload.get("message2"),
            }
        )
        if error is not None:
            return self._abort(game_state, error)
        message1 = normalized["message1"]
        message2 = normalized["message2"]

        if len(message1) == 0 or len(message2) == 0:
            return self._abort(
                game_state, "`message1` and `message2` must be non-empty"
            )

        if len(message1) != len(message2):
            return self._abort(
                game_state, "The two messages must be of the same length"
            )

        chosen_message = message1 if game_state.sampled_bit == 0 else message2

        return self._oracle_query(
            "encrypt",
            {
                "plaintext": chosen_message,
                "public-key": game_state.public_key,
            },
        )


class DistinguishStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Submit your guess for the challenger's secret bit b from the previous stage. Use 0 if you "
            "think message1 was encrypted, or 1 if you think message2 was encrypted. You win iff your "
            "guess equals the bit the challenger actually sampled.\n"
            "\n"
            "Submit the guess using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"sampled_bit_guess": <0 or 1>}}`.\n'
            "No oracles are available during this stage (the public key from stage 1 is still usable "
            "locally to encrypt arbitrary plaintexts with the scheme's encrypt algorithm). Submitting "
            "the guess completes the game session.\n"
        )
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: AsymmetricEavesdroppingIndistinguishabilityGameState,
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


class AsymmetricEavesdroppingIndistinguishabilityGame(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = AsymmetricEavesdroppingIndistinguishabilityGameState()
        self._stages = [
            GetPublicKeyStage(),
            MessageEncryptionStage(),
            DistinguishStage(),
        ]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> AsymmetricEavesdroppingIndistinguishabilityGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
