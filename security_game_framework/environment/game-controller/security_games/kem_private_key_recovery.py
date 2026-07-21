from typing import Any

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
Private Key Recovery (PKR) Game:

The adversary's goal is to recover the private key using only the public key.

Rules:
1. The challenger generates a random public/private key pair.
2. The adversary can analyze the public key, as well as the code used to generate the public key.
3. The adversary must output a candidate private key.
4. The candidate private key is checked for equality to the true private key.

The adversary wins if the candidate private key is equal to the true private key.

Session Lifecycle:
- PKR is a two-stage game. In the first stage the adversary receives the public key and in the second stage the private key should be recovered.
- Submitting your recovered private key completes the game session
- During evaluation, this game will only be played once. We therefore expect a 100% success rate.
""".strip()


class KEMPrivateKeyRecoveryGameState(SecurityGameState):
    def required_state_variables(self) -> list[str]:
        return ["public_key", "private_key"]


class GetPublicKeyStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = 'Use the action `execute_current_stage` with payload `{"stage_payload": {}}` to receive the generated public key.'
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self, game_state: KEMPrivateKeyRecoveryGameState, payload: dict[str, Any]
    ) -> dict[str, Any] | None:
        return {
            "public key": game_state.public_key,
        }


class KeyRecoveryStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Given the provided public key, recover the corresponding private key. "
            "Finally, submit the recovered private key using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"recovered_private_key": "<recovered_private_key>"}}`. '
            "The recovered private key must be a hex-encoded string (with or without the `0x` prefix). "
            "A missing or non-string `recovered_private_key` immediately ends the session as a loss.\n"
            "\n"
            "You have access to the following oracles during this stage:\n"
            "\n"
            "1. **Encapsulate oracle** - Given a public key, generates a shared secret and its encapsulation (ciphertext).\n"
            "   Example:\n"
            '   python game_controller_client.py --action oracle_query --json \'{"oracle_type": "encapsulate", "arguments": {"public-key": "0xabc123..."}}\'\n'
            "   Returns: shared_secret_key and encapsulation as hex strings.\n"
            "\n"
            "2. **Decapsulate oracle** - Given an encapsulation (ciphertext), recovers the shared secret using the private key "
            "(the private key is automatically provided by the game; you do NOT need to supply it).\n"
            "   Example:\n"
            '   python game_controller_client.py --action oracle_query --json \'{"oracle_type": "decapsulate", "arguments": {"encapsulation": "0xdef456..."}}\'\n'
            "   Returns: shared_secret_key as a hex string.\n"
        )
        self._allowed_oracles = ["encapsulate", "decapsulate"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self, game_state: KEMPrivateKeyRecoveryGameState, payload: dict[str, Any]
    ) -> dict[str, Any] | None:
        normalized, error = self._normalize_adversary_hex_fields(
            {"recovered_private_key": payload.get("recovered_private_key")}
        )
        if error is not None:
            return self._abort(game_state, error)

        game_state.success = (
            self._normalize_hex(game_state.private_key)
            == normalized["recovered_private_key"]
        )
        game_state.finished = True

        return {"Game won": "Yes" if game_state.success else "No"}

    def oracle_query(
        self,
        game_state: KEMPrivateKeyRecoveryGameState,
        oracle_type: str,
        arguments: dict[str, str] | None = None,
    ) -> dict[str, str]:
        if arguments is None:
            arguments = {}

        if oracle_type not in self.allowed_oracles():
            return {
                "error": f"Oracle type {oracle_type} is not allowed for this stage. Allowed oracles: {self.allowed_oracles()}"
            }

        if oracle_type == "decapsulate":
            arguments["private-key"] = game_state.private_key

        return self._oracle_query(oracle_type, arguments)


class KEMPrivateKeyRecoveryGame(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = KEMPrivateKeyRecoveryGameState()
        self._stages = [GetPublicKeyStage(), KeyRecoveryStage()]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> KEMPrivateKeyRecoveryGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
