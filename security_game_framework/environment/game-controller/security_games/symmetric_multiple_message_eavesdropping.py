from typing import Any
import secrets

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
Symmetric Multiple-Message Eavesdropping (IND) Game:

The adversary's goal is to distinguish which of two adversary-chosen *lists* of
messages was encrypted under a hidden secret key. This is the multi-message
generalization of the standard single-message IND game: the adversary commits
to two message lists of equal length, and the challenger encrypts every message
in one of the two lists (chosen by a hidden bit b) under the same secret key.

Rules:
1. The challenger generates a random secret key.
2. The adversary submits two lists of messages, message_list1 and message_list2,
   containing the same number of messages.
3. The challenger secretly samples a uniformly random bit b in {0, 1}, encrypts
   every message in message_list1 if b == 0 (or every message in message_list2
   if b == 1) under the secret key, and returns the resulting list of challenge
   ciphertexts in order.
4. The adversary must then output a guess for b (i.e. 0 or 1, indicating which
   of the two lists was encrypted).

The adversary wins if the submitted bit guess equals the bit b that the
challenger actually sampled.

Session Lifecycle:
- This is a two-stage game:
  Stage 1 - Submit the two candidate message lists; the challenger encrypts one
            of them under the secret key and returns the ciphertexts.
  Stage 2 - Submit your guess of the challenger's secret bit b (0 or 1).
- Submitting the guess in stage 2 completes the game session.
- During evaluation, this game will be played 20 times (independent sessions,
  each with a freshly sampled secret key and challenge bit). The adversary must
  win at least 17 out of 20 sessions to pass; note that a trivial random guess
  only wins ~50% of sessions in expectation, so a non-trivial distinguisher is
  required.
""".strip()


class SymmetricMultipleMessageEavesdroppingGameState(SecurityGameState):
    def __init__(self):
        super().__init__()
        self.sampled_bit: int = secrets.randbelow(2)

    def required_state_variables(self) -> list[str]:
        return ["key"]


class MessageListEncryptionStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Submit two candidate lists of messages. The game will secretly sample a uniformly random bit b in "
            "{0, 1}, encrypt every message in message_list1 (if b == 0) or every message in message_list2 (if "
            "b == 1) under the hidden secret key, and return the list of resulting challenge ciphertexts in the "
            "same order. No oracles are available during this stage.\n"
            "\n"
            "Submit the two message lists using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"message_list1": ["<hex_msg_1_1>", "<hex_msg_1_2>", ...], '
            '"message_list2": ["<hex_msg_2_1>", "<hex_msg_2_2>", ...]}}`. The response is '
            '`{"ciphertexts": [{...}, {...}, ...]}` in input order; each entry is the full per-message '
            "encrypt response, which always contains `ciphertext` and for some ciphers (stream ciphers, "
            "AEAD schemes) also contains additional fields such as `nonce` or `iv` that the underlying "
            "scheme generated for that message.\n"
            "Each payload value must be a non-empty JSON list whose entries are hex-encoded strings (with or "
            "without the `0x` prefix). The following conditions immediately end the session as a loss: a "
            "missing list, a value that is not a list, a list that is empty, a list entry that is not a "
            "string, lists of unequal length, or any index i where message_list1[i] and message_list2[i] "
            "differ in byte length. Each message should also be of the length expected by the underlying "
            "encryption scheme. Submitting two identical lists is allowed but leaves the ciphertexts "
            "independent of the challenger's bit, reducing the adversary to random guessing.\n"
        )
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: SymmetricMultipleMessageEavesdroppingGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        normalized_list1, error = self._normalize_adversary_hex_list(
            "message_list1", payload.get("message_list1")
        )
        if error is not None:
            return self._abort(game_state, error)
        normalized_list2, error = self._normalize_adversary_hex_list(
            "message_list2", payload.get("message_list2")
        )
        if error is not None:
            return self._abort(game_state, error)

        if len(normalized_list1) == 0 or len(normalized_list2) == 0:
            return self._abort(
                game_state, "`message_list1` and `message_list2` must be non-empty"
            )

        if len(normalized_list1) != len(normalized_list2):
            return self._abort(
                game_state,
                "The two message lists must contain the same number of messages",
            )

        for i, (m1, m2) in enumerate(zip(normalized_list1, normalized_list2)):
            if len(m1) != len(m2):
                return self._abort(
                    game_state,
                    f"`message_list1[{i}]` and `message_list2[{i}]` must have the same byte length",
                )

        chosen_message_list = (
            normalized_list1 if game_state.sampled_bit == 0 else normalized_list2
        )

        ciphertext_dicts = self._batched_oracle_query(
            "encrypt",
            [
                {"key": game_state.key, "plaintext": message}
                for message in chosen_message_list
            ],
        )
        if any("ciphertext" not in d for d in ciphertext_dicts):
            first_error = next(
                (d["error"] for d in ciphertext_dicts if "error" in d),
                "Encryption oracle returned a malformed response",
            )
            return self._abort(game_state, first_error)

        # Surface every non-error field the encrypt oracle returned per message
        # (e.g. an `iv` from a stream cipher or a `nonce` from an AEAD scheme),
        # so the agent has the same context they would have seen across single
        # encrypt queries. For ciphers that return only `ciphertext`, each entry
        # collapses to `{"ciphertext": "0x..."}`.
        return {
            "ciphertexts": [
                {k: v for k, v in d.items() if k != "error"} for d in ciphertext_dicts
            ],
        }


class DistinguishStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Submit your guess for the challenger's secret bit b from the previous stage. Use 0 if you think "
            "message1 was encrypted, or 1 if you think message2 was encrypted. You win iff your guess equals "
            "the bit the challenger actually sampled.\n"
            "\n"
            "Submit the guess using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"sampled_bit_guess": <0 or 1>}}`.\n'
            "No oracles are available during this stage. Submitting the guess completes the game session.\n"
        )
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: SymmetricMultipleMessageEavesdroppingGameState,
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


class SymmetricMultipleMessageEavesdroppingGame(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = SymmetricMultipleMessageEavesdroppingGameState()
        self._stages = [MessageListEncryptionStage(), DistinguishStage()]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> SymmetricMultipleMessageEavesdroppingGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
