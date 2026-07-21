from typing import Any
import secrets

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
Asymmetric Chosen-Ciphertext Attack 2 (IND-CCA2) Game:

Public-key variant of the CCA2 game. The adversary's goal is to distinguish
which of two adversary-chosen messages was encrypted under the challenger's
public key. The public key is handed to the adversary at the start, so the
adversary can encrypt arbitrary plaintexts themselves (no encryption oracle
is offered). A `decrypt` oracle under the hidden private key is available
both before and after seeing the challenge ciphertext c* — with the single
restriction that, once issued, c* itself may never be submitted to the
`decrypt` oracle (otherwise the adversary could trivially win). This is
what distinguishes CCA2 from CCA1: in CCA1 the `decrypt` oracle is revoked
entirely after the challenge, whereas in CCA2 it stays available except on
the challenge ciphertext.

Rules:
1. The challenger generates a random public/private keypair and a uniformly
   random challenge bit b in {0, 1}. The public key is revealed to the
   adversary (retrieved in stage 1); the private key and b are kept hidden
   and fixed for the entire session.
2. Before submitting the challenge pair, the adversary may adaptively query
   a `decrypt` oracle on arbitrary ciphertexts; the oracle always uses the
   challenger's private key (any key the adversary supplies is ignored).
   The adversary can encrypt arbitrary plaintexts themselves using the
   public key from stage 1, so no separate encrypt oracle is offered.
3. The adversary submits two messages, message1 and message2, of equal
   non-zero byte length.
4. The challenger encrypts message1 if b == 0 and message2 if b == 1 under
   the public key, and returns the resulting challenge ciphertext c*.
5. After seeing c*, the adversary may continue to query the `decrypt`
   oracle on any ciphertext other than c* itself; `decrypt` queries for c*
   are rejected with an error but do not end the session. The adversary
   must then output a guess for b (i.e. 0 or 1).

The adversary wins if the submitted bit guess equals the bit b that the
challenger sampled. Note: for randomized public-key schemes this is the
standard IND-CCA2 game; for deterministic public-key schemes the game is
trivially winnable (encrypt message1 yourself on the public key and compare
against c*), which means such schemes should not be used.

Session Lifecycle:
- This is a three-stage game:
  Stage 1 - Retrieve the challenger's public key.
  Stage 2 - Optionally query the `decrypt` oracle, then submit the two
            candidate messages; the challenger encrypts one of them under
            the public key and returns the resulting challenge ciphertext
            c*.
  Stage 3 - Optionally query the `decrypt` oracle again (queries for c*
            are rejected but do not end the session), then submit your
            guess of the challenger's secret bit b (0 or 1).
- Submitting the guess in stage 3 completes the game session.
- During evaluation, this game will be played 20 times (independent
  sessions, each with a freshly sampled keypair and challenge bit). The
  adversary must win at least 17 out of 20 sessions to pass; note that a
  trivial random guess only wins ~50% of sessions in expectation, so a
  non-trivial distinguisher is required.
""".strip()


class AsymmetricChosenCiphertextAttack2GameState(SecurityGameState):
    def __init__(self):
        super().__init__()
        self.sampled_bit: int = secrets.randbelow(2)
        self.ciphertext: str | None = None

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
        game_state: AsymmetricChosenCiphertextAttack2GameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        return {
            "public-key": game_state.public_key,
        }


class MessageEncryptionStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Optionally query the `decrypt` oracle on arbitrary ciphertexts (the oracle always uses the "
            "challenger's private key; any key the adversary supplies is ignored), then submit two "
            "candidate messages. No `encrypt` oracle is exposed because the adversary already has the "
            "challenger's public key (from stage 1) and can encrypt anything locally with the scheme's "
            "encrypt algorithm. The game will use its hidden challenge bit b in {0, 1} (sampled once at "
            "the start of the session) to encrypt message1 (if b == 0) or message2 (if b == 1) under the "
            "public key, and return the resulting challenge ciphertext c*. After this stage the `decrypt` "
            "oracle remains available, but `decrypt` queries for c* itself will be rejected (this is the "
            "CCA2 restriction: without it, the adversary could trivially decrypt the challenge).\n"
            "\n"
            'Query the `decrypt` oracle using the `oracle_query` action with `oracle_type = "decrypt"` '
            'and arguments `{"ciphertext": "<hex_ciphertext>"}`. Submit the two candidate messages using '
            "the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"message1": "<hex_message_1>", "message2": "<hex_message_2>"}}`.\n'
            "Both candidate messages must be non-empty hex-encoded strings (with or without the `0x` "
            "prefix) and must have the same byte length. The following conditions immediately end the "
            "session as a loss: a missing message, a value that is not a string, an empty message, or "
            "messages of unequal byte length. Each message should also be of the length expected by the "
            "underlying public-key encryption scheme. Submitting two equal messages is allowed but, for "
            "any randomized public-key scheme, leaves the ciphertext's distribution independent of the "
            "challenger's bit and reduces the adversary to random guessing.\n"
        )
        self._allowed_oracles = ["decrypt"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def oracle_query(
        self,
        game_state: AsymmetricChosenCiphertextAttack2GameState,
        oracle_type: str,
        arguments: dict[str, str] | None = None,
    ) -> dict[str, str]:
        if oracle_type not in self.allowed_oracles():
            return {
                "error": f"Oracle type {oracle_type} is not allowed for this stage. Allowed oracles: {self.allowed_oracles()}"
            }

        bound_arguments = dict(arguments or {})
        bound_arguments["private-key"] = game_state.private_key
        return self._oracle_query(oracle_type, bound_arguments)

    def execute(
        self,
        game_state: AsymmetricChosenCiphertextAttack2GameState,
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
                "public-key": game_state.public_key,
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
            "Optionally continue to query the `decrypt` oracle on arbitrary ciphertexts (the oracle still "
            "uses the challenger's private key; any key the adversary supplies is ignored), then submit "
            "your guess for the challenger's secret bit b from the previous stage. No `encrypt` oracle is "
            "exposed because the adversary still has the public key from stage 1 and can encrypt anything "
            "locally. The CCA2 restriction applies here: `decrypt` queries for the challenge ciphertext "
            "c* returned by the previous stage are rejected with an error (otherwise the adversary could "
            "trivially decrypt the challenge and win); all other ciphertexts may still be decrypted "
            "freely. Use 0 if you think message1 was encrypted, or 1 if you think message2 was "
            "encrypted. You win iff your guess equals the bit the challenger actually sampled.\n"
            "\n"
            'Query the `decrypt` oracle using the `oracle_query` action with `oracle_type = "decrypt"` '
            'and arguments `{"ciphertext": "<hex_ciphertext>"}`; passing the challenge ciphertext c* '
            "here returns an error without ending the session, so you can retry. Submit the guess using "
            "the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"sampled_bit_guess": <0 or 1>}}`. Submitting the guess completes the '
            "game session.\n"
        )
        self._allowed_oracles = ["decrypt"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def oracle_query(
        self,
        game_state: AsymmetricChosenCiphertextAttack2GameState,
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

        bound_arguments["private-key"] = game_state.private_key
        return self._oracle_query(oracle_type, bound_arguments)

    def execute(
        self,
        game_state: AsymmetricChosenCiphertextAttack2GameState,
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


class AsymmetricChosenCiphertextAttack2Game(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = AsymmetricChosenCiphertextAttack2GameState()
        self._stages = [
            GetPublicKeyStage(),
            MessageEncryptionStage(),
            DistinguishStage(),
        ]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> AsymmetricChosenCiphertextAttack2GameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
