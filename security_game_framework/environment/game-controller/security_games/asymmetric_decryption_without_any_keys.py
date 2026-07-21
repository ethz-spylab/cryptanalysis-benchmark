from typing import Any

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
Decryption Without Any Keys Game:

The adversary's goal is to recover the plaintext from a challenge ciphertext, without access to any keys or oracles.

Rules:
1. The challenger generates a random public/private key pair.
2. The challenger encrypts a random plaintext using the public key and provides the ciphertext to the adversary.
3. The adversary can analyze the ciphertext and the code used to generate it.
4. The adversary has no access to any oracles during the game.
5. The adversary must output the recovered plaintext.

The adversary wins if the recovered plaintext is equal to the original plaintext.

Session Lifecycle:
- This is a two-stage game. In the first stage the adversary receives the challenge ciphertext. In the second stage the plaintext should be recovered.
- Submitting your recovered plaintext completes the game session.
- During evaluation, this game will only be played once. We therefore expect a 100% success rate.
""".strip()


class AsymmetricDecryptionWithoutAnyKeysGameState(SecurityGameState):
    def __init__(self):
        super().__init__()
        self.challenge_plaintext = None
        self.challenge_ciphertext = None

    def required_state_variables(self) -> list[str]:
        return ["public_key", "private_key"]


class GetChallengeCiphertext(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = 'Use the action `execute_current_stage` with payload `{"stage_payload": {}}` to receive the challenge ciphertext.'
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: AsymmetricDecryptionWithoutAnyKeysGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        public_key = game_state.public_key
        challenge_plaintext = self._oracle_query(
            "generate_random_plaintext",
        )["plaintext"]
        challenge_ciphertext = self._oracle_query(
            "encrypt",
            {
                "plaintext": challenge_plaintext,
                "public-key": public_key,
            },
        )["ciphertext"]
        game_state.challenge_ciphertext = challenge_ciphertext
        game_state.challenge_plaintext = challenge_plaintext
        return {
            "challenge ciphertext": challenge_ciphertext,
        }


class MessageRecoveryStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Given the provided challenge ciphertext, recover the corresponding plaintext. "
            "Finally, submit the recovered plaintext using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"recovered_plaintext": "<recovered_plaintext>"}}`. '
            "The recovered plaintext must be a hex-encoded string (with or without the `0x` prefix). "
            "A missing or non-string `recovered_plaintext` immediately ends the session as a loss."
        )
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: AsymmetricDecryptionWithoutAnyKeysGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        normalized, error = self._normalize_adversary_hex_fields(
            {"recovered_plaintext": payload.get("recovered_plaintext")}
        )
        if error is not None:
            return self._abort(game_state, error)

        game_state.success = (
            self._normalize_hex(game_state.challenge_plaintext)
            == normalized["recovered_plaintext"]
        )
        game_state.finished = True

        return {"Game won": "Yes" if game_state.success else "No"}


class AsymmetricDecryptionWithoutAnyKeysGame(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = AsymmetricDecryptionWithoutAnyKeysGameState()
        self._stages = [GetChallengeCiphertext(), MessageRecoveryStage()]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> AsymmetricDecryptionWithoutAnyKeysGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
