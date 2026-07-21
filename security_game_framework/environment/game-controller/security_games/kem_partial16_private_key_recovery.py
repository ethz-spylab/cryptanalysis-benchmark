from typing import Any

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
Partial Private Key Recovery (Partial-16 PKR) Game:

The adversary's goal is to recover the private key, ignoring the first 16 bytes,
using only the public key.

Rules:
1. The challenger generates a random public/private key pair.
2. The adversary can analyze the public key, as well as the code used to generate the public key.
3. The adversary must output a candidate private key.
4. The candidate private key is compared to the true private key, ignoring the first
   16 bytes. This accommodates KEM schemes where the private key includes a random
   nonce (e.g., the Fujisaki-Okamoto transform parameter 's') that is not
   cryptographically recoverable from the public key or oracle access.

The adversary wins if the candidate private key matches the true private key
from byte 17 onward.

Session Lifecycle:
- Partial-16 PKR is a two-stage game. In the first stage the adversary receives the public key and in the second stage the (partial) private key should be recovered.
- Submitting your recovered private key completes the game session
- During evaluation, this game will only be played once. We therefore expect a 100% success rate.
""".strip()


class KEMPartial16PrivateKeyRecoveryGameState(SecurityGameState):
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
        self,
        game_state: KEMPartial16PrivateKeyRecoveryGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        return {
            "public key": game_state.public_key,
        }


class Partial16KeyRecoveryStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Given the provided public key, recover the corresponding private key. "
            "The first 16 bytes of the private key (a KEM-specific nonce) are ignored during comparison, "
            "so you may set them to any value. Only the remaining part of the private key must match.\n"
            "\n"
            "Submit the recovered private key using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"recovered_private_key": "<recovered_private_key>"}}`. '
            "The recovered private key must be a hex-encoded string (with or without the `0x` prefix) "
            "of at least 16 bytes (32 hex characters) since the first 16 bytes are ignored. "
            "A missing or non-string `recovered_private_key`, or a recovered key shorter than 16 bytes, "
            "immediately ends the session as a loss.\n"
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
        self,
        game_state: KEMPartial16PrivateKeyRecoveryGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        normalized, error = self._normalize_adversary_hex_fields(
            {"recovered_private_key": payload.get("recovered_private_key")}
        )
        if error is not None:
            return self._abort(game_state, error)

        # The first 16 bytes (= 32 hex characters) of the private key are ignored
        # to accommodate KEM schemes where the private key includes a random nonce
        # (e.g., the Fujisaki-Okamoto transform parameter 's') that is not
        # cryptographically recoverable from the public key or oracle access.
        normalized_true = self._normalize_hex(game_state.private_key)
        normalized_recovered = normalized["recovered_private_key"]

        if len(normalized_recovered) < 32:
            return self._abort(
                game_state,
                "`recovered_private_key` must be at least 16 bytes (32 hex characters) long",
            )

        game_state.success = normalized_true[32:] == normalized_recovered[32:]
        game_state.finished = True

        return {"Game won": "Yes" if game_state.success else "No"}

    def oracle_query(
        self,
        game_state: KEMPartial16PrivateKeyRecoveryGameState,
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


class KEMPartial16PrivateKeyRecoveryGame(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = KEMPartial16PrivateKeyRecoveryGameState()
        self._stages = [GetPublicKeyStage(), Partial16KeyRecoveryStage()]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> KEMPartial16PrivateKeyRecoveryGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
