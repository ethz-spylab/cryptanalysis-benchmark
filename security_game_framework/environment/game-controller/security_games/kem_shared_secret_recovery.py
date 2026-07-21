from typing import Any

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
KEM Shared Secret Recovery Game:

The adversary's goal is to recover the shared secret produced by a KEM encapsulation, given the public key and the encapsulation (ciphertext).

Rules:
1. The challenger generates a random public/private key pair.
2. The challenger encapsulates using the public key, producing an encapsulation (ciphertext) and a shared secret.
3. The adversary receives the public key and the encapsulation.
4. The adversary can analyze the public key, encapsulation, and the code used to generate them.
5. The adversary must output a candidate shared secret.
6. The candidate shared secret is checked for equality to the true shared secret.

The adversary wins if the candidate shared secret is equal to the true shared secret.

Session Lifecycle:
- This is a two-stage game. In the first stage the adversary receives the public key and encapsulation, and in the second stage the shared secret should be recovered.
- Submitting your recovered shared secret completes the game session.
- During evaluation, this game will only be played once. We therefore expect a 100% success rate.
""".strip()


class KEMSharedSecretRecoveryGameState(SecurityGameState):
    def __init__(self):
        super().__init__()
        self.encapsulation = None
        self.shared_secret = None

    def required_state_variables(self) -> list[str]:
        return ["public_key", "private_key"]


class GetDataStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = 'Use the action `execute_current_stage` with payload `{"stage_payload": {}}` to receive the public key and encapsulation (ciphertext).'
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self, game_state: KEMSharedSecretRecoveryGameState, payload: dict[str, Any]
    ) -> dict[str, Any] | None:
        public_key = game_state.public_key

        result = self._oracle_query("encapsulate", {"public-key": public_key})
        if "encapsulation" not in result or "shared_secret_key" not in result:
            return self._abort(
                game_state,
                result.get(
                    "error", "Encapsulation oracle returned a malformed response"
                ),
            )
        encapsulation = result["encapsulation"]
        shared_secret = result["shared_secret_key"]

        game_state.encapsulation = encapsulation
        game_state.shared_secret = shared_secret

        return {
            "public_key": public_key,
            "encapsulation": encapsulation,
        }


class SharedSecretRecoveryStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Given the public key and encapsulation (ciphertext) from the previous stage, recover the shared secret. "
            "Submit the recovered shared secret using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"recovered_shared_secret": "<recovered_shared_secret>"}}`. '
            "The recovered shared secret must be a hex-encoded string (with or without the `0x` prefix). "
            "A missing or non-string `recovered_shared_secret` immediately ends the session as a loss.\n"
            "\n"
            "You have access to the following oracles during this stage:\n"
            "\n"
            "1. **Encapsulate oracle** - Given a public key, generates a shared secret and its encapsulation (ciphertext).\n"
            "   Example:\n"
            '   python game_controller_client.py --action oracle_query --json \'{"oracle_type": "encapsulate", "arguments": {"public-key": "0xabc123..."}}\'\n'
            "   Returns: shared_secret_key and encapsulation as hex strings.\n"
        )
        self._allowed_oracles = ["encapsulate"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self, game_state: KEMSharedSecretRecoveryGameState, payload: dict[str, Any]
    ) -> dict[str, Any] | None:
        normalized, error = self._normalize_adversary_hex_fields(
            {"recovered_shared_secret": payload.get("recovered_shared_secret")}
        )
        if error is not None:
            return self._abort(game_state, error)

        game_state.success = (
            self._normalize_hex(game_state.shared_secret)
            == normalized["recovered_shared_secret"]
        )
        game_state.finished = True

        return {"Game won": "Yes" if game_state.success else "No"}


class KEMSharedSecretRecoveryGame(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = KEMSharedSecretRecoveryGameState()
        self._stages = [GetDataStage(), SharedSecretRecoveryStage()]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> KEMSharedSecretRecoveryGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
