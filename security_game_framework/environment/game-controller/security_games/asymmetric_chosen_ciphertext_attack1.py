from typing import Any
import secrets

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
Asymmetric Chosen-Ciphertext Attack 1 (IND-CCA1, "lunchtime attack") Game:

Public-key variant of the CCA1 game. The adversary's goal is to distinguish
which of two adversary-chosen messages was encrypted under the challenger's
public key. The challenger's public key is handed to the adversary at the
start (so the adversary can encrypt arbitrary plaintexts themselves — there
is no separate encryption oracle), and a `decrypt` oracle under the hidden
private key is available *before* seeing the challenge ciphertext. After
the challenge ciphertext has been returned, the `decrypt` oracle is revoked
— this is what distinguishes CCA1 ("lunchtime attack") from CCA2.

Rules:
1. The challenger generates a random public/private keypair and a uniformly
   random challenge bit b in {0, 1}. The public key is revealed to the
   adversary (retrieved in stage 1); the private key and b are kept hidden
   and fixed for the entire session.
2. Before submitting the challenge pair, the adversary may adaptively query
   a `decrypt` oracle on arbitrary ciphertexts; the oracle always uses the
   challenger's private key (any key the adversary supplies is ignored).
   The adversary can encrypt arbitrary plaintexts themselves by running the
   scheme's encrypt algorithm on the public key obtained in stage 1, so no
   separate encrypt oracle is offered.
3. The adversary submits two messages, message1 and message2, of equal
   non-zero byte length.
4. The challenger encrypts message1 if b == 0 and message2 if b == 1 under
   the public key, and returns the resulting challenge ciphertext.
5. After seeing the challenge ciphertext, the `decrypt` oracle is no longer
   available. The adversary must then output a guess for b (i.e. 0 or 1);
   any further plaintext-encryption work in stage 3 has to be done locally
   with the public key.

The adversary wins if the submitted bit guess equals the bit b that the
challenger sampled. Note: for randomized public-key schemes this is the
standard IND-CCA1 game; for deterministic public-key schemes the game is
trivially winnable (encrypt message1 yourself on the public key and compare
against the challenge ciphertext), which means such schemes should not be
used.

Session Lifecycle:
- This is a three-stage game:
  Stage 1 - Retrieve the challenger's public key.
  Stage 2 - Optionally query the `decrypt` oracle, then submit the two
            candidate messages; the challenger encrypts one of them under
            the public key and returns the resulting challenge ciphertext.
  Stage 3 - No oracle access (CCA1 / lunchtime-attack restriction). Submit
            your guess of the challenger's secret bit b (0 or 1).
- Submitting the guess in stage 3 completes the game session.
- During evaluation, this game will be played 20 times (independent
  sessions, each with a freshly sampled keypair and challenge bit). The
  adversary must win at least 17 out of 20 sessions to pass; note that a
  trivial random guess only wins ~50% of sessions in expectation, so a
  non-trivial distinguisher is required.
""".strip()


class AsymmetricChosenCiphertextAttack1GameState(SecurityGameState):
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
        game_state: AsymmetricChosenCiphertextAttack1GameState,
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
            "public key, and return the resulting challenge ciphertext. After this stage the `decrypt` "
            "oracle is no longer available (this is the CCA1 / lunchtime-attack restriction).\n"
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
        game_state: AsymmetricChosenCiphertextAttack1GameState,
        oracle_type: str,
        arguments: dict[str, str] | None = None,
    ) -> dict[str, str]:
        if oracle_type not in self.allowed_oracles():
            return {
                "error": f"Oracle type {oracle_type} is not allowed for this stage. Allowed oracles: {self.allowed_oracles()}"
            }

        bound_arguments = dict(arguments or {})
        if oracle_type == "decrypt":
            bound_arguments["private-key"] = game_state.private_key
        elif oracle_type == "encrypt":
            bound_arguments["public-key"] = game_state.public_key
        return self._oracle_query(oracle_type, bound_arguments)

    def execute(
        self,
        game_state: AsymmetricChosenCiphertextAttack1GameState,
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
            "No oracle access is available during this stage — this is the CCA1 / lunchtime-attack "
            "restriction: once the challenge ciphertext has been seen, `decrypt` queries are forbidden "
            "(otherwise the adversary could trivially decrypt the challenge itself), and no encrypt "
            "oracle is needed because the adversary still has the public key from stage 1 and can "
            "encrypt arbitrary plaintexts locally. Submit your guess for the challenger's secret bit b "
            "from the previous stage. Use 0 if you think message1 was encrypted, or 1 if you think "
            "message2 was encrypted. You win iff your guess equals the bit the challenger actually "
            "sampled.\n"
            "\n"
            "Submit the guess using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"sampled_bit_guess": <0 or 1>}}`. Submitting the guess completes the '
            "game session.\n"
        )
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: AsymmetricChosenCiphertextAttack1GameState,
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


class AsymmetricChosenCiphertextAttack1Game(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = AsymmetricChosenCiphertextAttack1GameState()
        self._stages = [
            GetPublicKeyStage(),
            MessageEncryptionStage(),
            DistinguishStage(),
        ]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> AsymmetricChosenCiphertextAttack1GameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
