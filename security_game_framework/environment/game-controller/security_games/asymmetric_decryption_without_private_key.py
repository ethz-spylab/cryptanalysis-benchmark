from typing import Any

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
Plaintext Recovery (PR) Game:

The adversary's goal is to recover the plaintexts from ciphertexts encrypted with a public key, without access to the private key.

Rules:
1. The challenger generates a random public/private key pair.
2. The challenger encrypts 10 random plaintexts with the public key and provides them to the adversary along with the public key.
3. The adversary can analyze the public key, the ciphertexts, and the code used to generate them.
4. The adversary has access to an encrypt oracle during the recovery stage.
5. The adversary must output the recovered plaintexts.

The adversary wins if all recovered plaintexts match the original plaintexts.

Session Lifecycle:
- PR is a two-stage game. In the first stage the adversary receives the public key and 10 ciphertexts. In the second stage the plaintexts should be recovered.
- Submitting your recovered plaintexts completes the game session.
- During evaluation, this game will only be played once. We therefore expect a 100% success rate.
""".strip()


class AsymmetricDecryptionWithoutPrivateKeyGameState(SecurityGameState):
    def __init__(self):
        super().__init__()
        self.plaintexts = []
        self.ciphertexts = []

    def required_state_variables(self) -> list[str]:
        return ["public_key", "private_key"]


class GetDataStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = 'Use the action `execute_current_stage` with payload `{"stage_payload": {}}` to receive a public key and 10 ciphertexts encrypted with the public key.'
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: AsymmetricDecryptionWithoutPrivateKeyGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        # Create 10 random plaintexts
        plaintexts = self._generate_random_plaintext(10)
        ciphertext_dicts = self._batched_oracle_query(
            "encrypt",
            [
                {"plaintext": plaintext, "public-key": game_state.public_key}
                for plaintext in plaintexts
            ],
        )
        if any("ciphertext" not in d for d in ciphertext_dicts):
            first_error = next(
                (d["error"] for d in ciphertext_dicts if "error" in d),
                "Encryption oracle returned a malformed response",
            )
            return self._abort(game_state, first_error)

        ciphertexts = [d["ciphertext"] for d in ciphertext_dicts]
        game_state.plaintexts = plaintexts
        game_state.ciphertexts = ciphertexts
        return {
            "public key": game_state.public_key,
            "ciphertexts": ciphertexts,
        }


class PlaintextRecoveryStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Recover the plaintexts corresponding to the ciphertexts received in the previous stage. "
            "Submit all recovered plaintexts using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"recovered_plaintexts": ["<plaintext_1>", "<plaintext_2>", ...]}}`. '
            "Each entry must be a hex-encoded string (with or without the `0x` prefix). "
            "The following conditions immediately end the session as a loss: a missing "
            "`recovered_plaintexts` field, a value that is not a list, a list whose length differs "
            "from the number of challenge ciphertexts, or any list entry that is not a string.\n"
            "\n"
            "You have access to the following oracles during this stage:\n"
            "\n"
            "1. **Encrypt oracle** - Given a plaintext and a public key, returns the corresponding ciphertext.\n"
            "   Example:\n"
            '   python game_controller_client.py --action oracle_query --json \'{"oracle_type": "encrypt", "arguments": {"plaintext": "0xabc123...", "public-key": "0xdef456..."}}\'\n'
            "   Returns: ciphertext as a hex string.\n"
        )
        self._allowed_oracles = ["encrypt"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: AsymmetricDecryptionWithoutPrivateKeyGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        normalized_recovered, error = self._normalize_adversary_hex_list(
            "recovered_plaintexts", payload.get("recovered_plaintexts")
        )
        if error is not None:
            return self._abort(game_state, error)

        if len(normalized_recovered) != len(game_state.plaintexts):
            return self._abort(
                game_state,
                (
                    f"Expected {len(game_state.plaintexts)} recovered plaintexts, "
                    f"got {len(normalized_recovered)}"
                ),
            )

        game_state.success = all(
            recovered == self._normalize_hex(original)
            for recovered, original in zip(normalized_recovered, game_state.plaintexts)
        )
        game_state.finished = True

        return {"Game won": "Yes" if game_state.success else "No"}


class AsymmetricDecryptionWithoutPrivateKeyGame(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = AsymmetricDecryptionWithoutPrivateKeyGameState()
        self._stages = [GetDataStage(), PlaintextRecoveryStage()]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> AsymmetricDecryptionWithoutPrivateKeyGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
