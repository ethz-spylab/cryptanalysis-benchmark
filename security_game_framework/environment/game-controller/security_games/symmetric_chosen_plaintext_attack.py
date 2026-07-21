from typing import Any
import secrets

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
Symmetric Chosen-Plaintext Attack (IND-CPA) Game:

The adversary's goal is to distinguish which of two adversary-chosen messages
was encrypted under a hidden secret key, with adaptive oracle access to
encryption under that same hidden key both before and after seeing the
challenge ciphertext.

Rules:
1. The challenger generates a random secret key and keeps it hidden.
2. Throughout the game, the adversary may adaptively query an `encrypt` oracle
   that encrypts adversary-chosen plaintexts under the hidden secret key. The
   oracle always uses the challenger's key; any key the adversary supplies is
   ignored.
3. The adversary submits two messages, message1 and message2.
4. The challenger secretly samples a uniformly random bit b in {0, 1}, encrypts
   message1 if b == 0 and message2 if b == 1 under the secret key, and returns
   the resulting challenge ciphertext.
5. The adversary may continue to query the `encrypt` oracle after seeing the
   challenge ciphertext, and must then output a guess for b (i.e. 0 or 1).

The adversary wins if the submitted bit guess equals the bit b that the
challenger actually sampled.

Session Lifecycle:
- This is a two-stage game:
  Stage 1 - Optionally query the `encrypt` oracle, then submit the two
            candidate messages; the challenger encrypts one of them under the
            secret key and returns the resulting challenge ciphertext.
  Stage 2 - Optionally query the `encrypt` oracle again, then submit your
            guess of the challenger's secret bit b (0 or 1).
- Submitting the guess in stage 2 completes the game session.
- During evaluation, this game will be played 20 times (independent sessions,
  each with a freshly sampled secret key and challenge bit). The adversary must
  win at least 17 out of 20 sessions to pass; note that a trivial random guess
  only wins ~50% of sessions in expectation, so a non-trivial distinguisher is
  required.
""".strip()


class SymmetricChosenPlaintextAttackGameState(SecurityGameState):
    def __init__(self):
        super().__init__()
        self.sampled_bit: int = secrets.randbelow(2)

    def required_state_variables(self) -> list[str]:
        return ["key"]


class MessageEncryptionStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Optionally query the `encrypt` oracle with adversary-chosen plaintexts (the oracle always "
            "encrypts under the hidden challenge key; any key the adversary supplies is ignored), then submit "
            "two candidate messages. The game will secretly sample a uniformly random bit b in {0, 1}, "
            "encrypt message1 (if b == 0) or message2 (if b == 1) under the hidden secret key, and return the "
            "resulting challenge ciphertext.\n"
            "\n"
            'Query the oracle using the `oracle_query` action with `oracle_type = "encrypt"` and arguments '
            '`{"plaintext": "<hex_plaintext>"}`. The encrypt response always contains `ciphertext`; for '
            "some ciphers (stream ciphers, AEAD schemes) it also contains additional fields such as "
            "`nonce` or `iv` that the underlying scheme generated for that call. Submit the two candidate "
            "messages using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"message1": "<hex_message_1>", "message2": "<hex_message_2>"}}`.\n'
            "Both candidate messages must be non-empty hex-encoded strings (with or without the `0x` prefix) "
            "and must have the same byte length. The following conditions immediately end the session as a "
            "loss: a missing message, a value that is not a string, an empty message, or messages of unequal "
            "byte length. Each message should also be of the length expected by the underlying encryption "
            "scheme. Submitting two equal messages is allowed but leaves the ciphertext independent of the "
            "challenger's bit, reducing the adversary to random guessing.\n"
        )
        self._allowed_oracles = ["encrypt"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def oracle_query(
        self,
        game_state: SymmetricChosenPlaintextAttackGameState,
        oracle_type: str,
        arguments: dict[str, str] | None = None,
    ) -> dict[str, str]:
        if oracle_type not in self.allowed_oracles():
            return {
                "error": f"Oracle type {oracle_type} is not allowed for this stage. Allowed oracles: {self.allowed_oracles()}"
            }

        bound_arguments = dict(arguments or {})
        bound_arguments["key"] = game_state.key
        return self._oracle_query(oracle_type, bound_arguments)

    def execute(
        self,
        game_state: SymmetricChosenPlaintextAttackGameState,
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
                "key": game_state.key,
            },
        )


class DistinguishStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Optionally continue to query the `encrypt` oracle with adversary-chosen plaintexts (the oracle "
            "still encrypts under the same hidden challenge key; any key the adversary supplies is ignored), "
            "then submit your guess for the challenger's secret bit b from the previous stage. Use 0 if you "
            "think message1 was encrypted, or 1 if you think message2 was encrypted. You win iff your guess "
            "equals the bit the challenger actually sampled.\n"
            "\n"
            'Query the oracle using the `oracle_query` action with `oracle_type = "encrypt"` and arguments '
            '`{"plaintext": "<hex_plaintext>"}`. The encrypt response always contains `ciphertext`; for '
            "some ciphers (stream ciphers, AEAD schemes) it also contains additional fields such as "
            "`nonce` or `iv` that the underlying scheme generated for that call. Submit the guess using "
            "the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"sampled_bit_guess": <0 or 1>}}`.\n'
            "Submitting the guess completes the game session.\n"
        )
        self._allowed_oracles = ["encrypt"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def oracle_query(
        self,
        game_state: SymmetricChosenPlaintextAttackGameState,
        oracle_type: str,
        arguments: dict[str, str] | None = None,
    ) -> dict[str, str]:
        if oracle_type not in self.allowed_oracles():
            return {
                "error": f"Oracle type {oracle_type} is not allowed for this stage. Allowed oracles: {self.allowed_oracles()}"
            }

        bound_arguments = dict(arguments or {})
        bound_arguments["key"] = game_state.key
        return self._oracle_query(oracle_type, bound_arguments)

    def execute(
        self,
        game_state: SymmetricChosenPlaintextAttackGameState,
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


class SymmetricChosenPlaintextAttackGame(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = SymmetricChosenPlaintextAttackGameState()
        self._stages = [MessageEncryptionStage(), DistinguishStage()]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> SymmetricChosenPlaintextAttackGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
