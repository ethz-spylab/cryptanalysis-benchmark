from typing import Any
import secrets

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
Symmetric Chosen-Ciphertext Attack 2 (IND-CCA2) Game:

The adversary's goal is to distinguish which of two adversary-chosen messages
was encrypted under a hidden secret key. The adversary has adaptive access
to both an `encrypt` oracle and a `decrypt` oracle under the hidden key,
both before and after seeing the challenge ciphertext — with the single
restriction that, once issued, the challenge ciphertext itself may never be
submitted to the `decrypt` oracle (otherwise the adversary could trivially
win). This is what distinguishes CCA2 from CCA1: in CCA1 the `decrypt`
oracle is revoked entirely after the challenge, whereas in CCA2 it stays
available except on the challenge ciphertext.

Rules:
1. The challenger generates a random secret key and a uniformly random
   challenge bit b in {0, 1}. Both are hidden from the adversary and fixed
   for the entire session.
2. Before submitting the challenge pair, the adversary may adaptively query
   an `encrypt` oracle (arbitrary plaintexts) and a `decrypt` oracle
   (arbitrary ciphertexts), both using the hidden challenge key. The
   oracles always use the challenger's key; any key the adversary supplies
   is ignored.
3. The adversary submits two messages, message1 and message2, of equal
   non-zero byte length.
4. The challenger encrypts message1 if b == 0 and message2 if b == 1 under
   the secret key, and returns the resulting challenge ciphertext c*.
5. After seeing c*, the adversary may continue to query both the `encrypt`
   and `decrypt` oracles; `decrypt` queries for c* itself are rejected but
   all other ciphertexts remain decryptable. The adversary must then
   output a guess for b (i.e. 0 or 1).

The adversary wins if the submitted bit guess equals the bit b that the
challenger sampled.

Session Lifecycle:
- This is a two-stage game:
  Stage 1 - Optionally query the `encrypt` and/or `decrypt` oracles, then
            submit the two candidate messages; the challenger encrypts one
            of them under the secret key and returns the resulting challenge
            ciphertext c*.
  Stage 2 - Optionally query the `encrypt` and/or `decrypt` oracles again
            (decrypt queries for c* are rejected), then submit your guess
            of the challenger's secret bit b (0 or 1).
- Submitting the guess in stage 2 completes the game session.
- During evaluation, this game will be played 20 times (independent sessions,
  each with a freshly sampled secret key and challenge bit). The adversary must
  win at least 17 out of 20 sessions to pass; note that a trivial random guess
  only wins ~50% of sessions in expectation, so a non-trivial distinguisher is
  required.
""".strip()


class SymmetricChosenCiphertextAttack2GameState(SecurityGameState):
    def __init__(self):
        super().__init__()
        self.sampled_bit: int = secrets.randbelow(2)
        self.ciphertext: str | None = None

    def required_state_variables(self) -> list[str]:
        return ["key"]


class MessageEncryptionStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Optionally query the `encrypt` and/or `decrypt` oracles (both always use the hidden challenge "
            "key; any key the adversary supplies is ignored), then submit two candidate messages. The game "
            "will use its hidden challenge bit b in {0, 1} (sampled once at the start of the session) to "
            "encrypt message1 (if b == 0) or message2 (if b == 1) under the hidden secret key, and return "
            "the resulting challenge ciphertext c*. After this stage the `encrypt` and `decrypt` oracles "
            "both remain available, but `decrypt` queries for c* itself will be rejected (this is the "
            "CCA2 restriction: without it, the adversary could trivially decrypt the challenge).\n"
            "\n"
            'Query the `encrypt` oracle using the `oracle_query` action with `oracle_type = "encrypt"` and '
            'arguments `{"plaintext": "<hex_plaintext>"}`. The encrypt response always contains '
            "`ciphertext`; for some ciphers (stream ciphers, AEAD schemes) it also contains additional "
            "fields such as `nonce` or `iv` that the underlying scheme generated for that call. Query the "
            '`decrypt` oracle using `oracle_type = "decrypt"` and arguments '
            '`{"ciphertext": "<hex_ciphertext>", ...}`; if the cipher needs auxiliary inputs (e.g. `nonce`, '
            "`iv`, `ad`) you must include them too — typically by echoing the same fields that the encrypt "
            "oracle returned alongside that ciphertext. Submit the two candidate messages using the "
            "`execute_current_stage` action and the payload "
            '`{"stage_payload": {"message1": "<hex_message_1>", "message2": "<hex_message_2>"}}`.\n'
            "Both candidate messages must be non-empty hex-encoded strings (with or without the `0x` prefix) "
            "and must have the same byte length. The following conditions immediately end the session as a "
            "loss: a missing message, a value that is not a string, an empty message, or messages of unequal "
            "byte length. Each message should also be of the length expected by the underlying encryption "
            "scheme. Submitting two equal messages is allowed but leaves the ciphertext independent of the "
            "challenger's bit, reducing the adversary to random guessing.\n"
        )
        self._allowed_oracles = ["encrypt", "decrypt"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def oracle_query(
        self,
        game_state: SymmetricChosenCiphertextAttack2GameState,
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
        game_state: SymmetricChosenCiphertextAttack2GameState,
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

        ciphertext = self._oracle_query(
            "encrypt",
            {
                "plaintext": chosen_message,
                "key": game_state.key,
            },
        )

        if "ciphertext" not in ciphertext:
            return self._abort(
                game_state,
                ciphertext.get(
                    "error", "Encryption oracle returned a malformed response"
                ),
            )

        game_state.ciphertext = self._normalize_hex(ciphertext["ciphertext"])

        return ciphertext


class DistinguishStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Optionally continue to query the `encrypt` and/or `decrypt` oracles (both still operate under "
            "the same hidden challenge key; any key the adversary supplies is ignored), then submit your "
            "guess for the challenger's secret bit b from the previous stage. The CCA2 restriction applies "
            "here: `decrypt` queries for the challenge ciphertext c* returned by the previous stage are "
            "rejected with an error (otherwise the adversary could trivially decrypt the challenge and "
            "win). All other ciphertexts may still be decrypted freely. Use 0 if you think message1 was "
            "encrypted, or 1 if you think message2 was encrypted. You win iff your guess equals the bit "
            "the challenger actually sampled.\n"
            "\n"
            'Query the `encrypt` oracle using the `oracle_query` action with `oracle_type = "encrypt"` '
            'and arguments `{"plaintext": "<hex_plaintext>"}`. The encrypt response always contains '
            "`ciphertext`; for some ciphers (stream ciphers, AEAD schemes) it also contains additional "
            "fields such as `nonce` or `iv` that the underlying scheme generated for that call. Query "
            'the `decrypt` oracle using `oracle_type = "decrypt"` and arguments '
            '`{"ciphertext": "<hex_ciphertext>", ...}`; if the cipher needs auxiliary inputs (e.g. '
            "`nonce`, `iv`, `ad`) you must include them too — typically by echoing the same fields that "
            "the encrypt oracle returned alongside that ciphertext. Passing the challenge ciphertext "
            "c* to decrypt here returns an error without ending the session, so you can retry. Submit "
            "the guess using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"sampled_bit_guess": <0 or 1>}}`. Submitting the guess completes the '
            "game session.\n"
        )
        self._allowed_oracles = ["encrypt", "decrypt"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def oracle_query(
        self,
        game_state: SymmetricChosenCiphertextAttack2GameState,
        oracle_type: str,
        arguments: dict[str, str] | None = None,
    ) -> dict[str, str]:
        if oracle_type not in self.allowed_oracles():
            return {
                "error": f"Oracle type {oracle_type} is not allowed for this stage. Allowed oracles: {self.allowed_oracles()}"
            }

        bound_arguments = dict(arguments or {})

        if oracle_type == "decrypt":
            ciphertext = bound_arguments.get("ciphertext")
            if isinstance(ciphertext, str):
                normalized, error = self._normalize_adversary_hex_fields(
                    {"ciphertext": ciphertext}
                )
                if error is not None:
                    return {"error": error}
                if normalized["ciphertext"] == game_state.ciphertext:
                    return {
                        "error": "You are not allowed to query the `decrypt` oracle with the challenge ciphertext."
                    }
                bound_arguments["ciphertext"] = normalized["ciphertext"]

        bound_arguments["key"] = game_state.key
        return self._oracle_query(oracle_type, bound_arguments)

    def execute(
        self,
        game_state: SymmetricChosenCiphertextAttack2GameState,
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


class SymmetricChosenCiphertextAttack2Game(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = SymmetricChosenCiphertextAttack2GameState()
        self._stages = [MessageEncryptionStage(), DistinguishStage()]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> SymmetricChosenCiphertextAttack2GameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
