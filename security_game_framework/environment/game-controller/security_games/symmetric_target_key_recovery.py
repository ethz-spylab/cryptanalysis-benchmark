from typing import Any

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
Target Key Recovery (TKR) Game:

The adversary's goal is to recover the secret key used by the encryption oracle.

Rules:
1. The challenger generates a random secret key
2. The adversary can make chosen-plaintext queries to the encryption oracle
3. The adversary must output a candidate key
4. The candidate key is used to decrypt hidden test ciphertexts

The adversary wins if the candidate key correctly decrypts all hidden test ciphertexts.

Session Lifecycle:
- TKR is a single-stage game (only key recovery stage)
- Submitting your recovered key completes the game session
- During evaluation, this game will only be played once. We therefore expect a 100% success rate.
""".strip()


class SymmetricTargetKeyRecoveryGameState(SecurityGameState):
    def __init__(self):
        super().__init__()
        self.eval_plaintexts: list[str] | None = None

    def required_state_variables(self) -> list[str]:
        return ["key"]


class KeyRecoveryStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Perform as many encryption oracle queries as you want. Use the output to recover the secret key. "
            "Finally, submit the recovered key using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"recovered_key": "<recovered_key>"}}`.\n'
            "The recovered key must be a hex-encoded string (with or without the `0x` prefix). "
            "A missing or non-string `recovered_key` immediately ends the session as a loss.\n"
            "\n"
            "You have access to the following oracles during this stage:\n"
            "\n"
            "1. **Encrypt oracle** - Given a plaintext, encrypts it using the secret key "
            "(the secret key is automatically provided by the game; you do NOT need to supply it).\n"
            "   Example:\n"
            '   python game_controller_client.py --action oracle_query --json \'{"oracle_type": "encrypt", "arguments": {"plaintext": "0x0000000000000000"}}\'\n'
            '   Returns: JSON containing at least `ciphertext` as a hex string, e.g. {"ciphertext": "0x..."}.\n'
            "   For some ciphers (stream ciphers, AEAD schemes) the response also contains additional "
            "fields such as `nonce` or `iv` that the underlying scheme generated for that call; the "
            "verifier captures those fields automatically when checking your recovered key, so you do "
            "not need to supply them yourself.\n"
        )
        self._allowed_oracles = ["encrypt"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def oracle_query(
        self,
        game_state: SymmetricTargetKeyRecoveryGameState,
        oracle_type: str,
        arguments: dict[str, str] | None = None,
    ) -> dict[str, str]:
        if arguments is None:
            arguments = {}

        if oracle_type not in self.allowed_oracles():
            return {
                "error": f"Oracle type {oracle_type} is not allowed for this stage. Allowed oracles: {self.allowed_oracles()}"
            }

        if oracle_type == "encrypt":
            arguments["key"] = game_state.key

        return self._oracle_query(oracle_type, arguments)

    def execute(
        self, game_state: SymmetricTargetKeyRecoveryGameState, payload: dict[str, Any]
    ) -> dict[str, Any] | None:
        normalized, error = self._normalize_adversary_hex_fields(
            {"recovered_key": payload.get("recovered_key")}
        )
        if error is not None:
            return self._abort(game_state, error)
        recovered_key = normalized["recovered_key"]

        if game_state.eval_plaintexts is None:
            game_state.eval_plaintexts = self._generate_random_plaintext(1000)

        eval_ciphertext_dicts = self._batched_oracle_query(
            "encrypt",
            [
                {"key": game_state.key, "plaintext": plaintext}
                for plaintext in game_state.eval_plaintexts
            ],
        )
        eval_ciphertexts = [d.get("ciphertext") for d in eval_ciphertext_dicts]
        if any(ct is None for ct in eval_ciphertexts):
            return self._abort(
                game_state,
                "Encryption oracle returned a malformed response while building the evaluation set",
            )

        assert len(eval_ciphertexts) == len(game_state.eval_plaintexts), (
            "Number of eval ciphertexts does not match number of eval plaintexts"
        )
        assert len(eval_ciphertexts) == 1000, "Number of eval ciphertexts is not 1000"

        print(f"Real key: {game_state.key}")
        print(f"Recovered key: {recovered_key}")

        # Pass through any extra fields the encrypt oracle returned alongside
        # `ciphertext` (e.g. an `iv` from a stream cipher or a `nonce` from an
        # AEAD scheme), so the corresponding decrypt call has the same context.
        # For ciphers that return only `ciphertext`, this loop is a no-op.
        decrypt_arguments = []
        for d in eval_ciphertext_dicts:
            args: dict[str, str] = {"key": recovered_key}
            for k, v in d.items():
                if k != "error":
                    args[k] = v
            decrypt_arguments.append(args)

        recovered_plaintext_dicts = self._batched_oracle_query(
            "decrypt", decrypt_arguments
        )
        recovered_plaintexts = [d.get("plaintext") for d in recovered_plaintext_dicts]

        num_correct = sum(
            recovered_plaintext is not None
            and self._normalize_hex(eval_plaintext)
            == self._normalize_hex(recovered_plaintext)
            for eval_plaintext, recovered_plaintext in zip(
                game_state.eval_plaintexts, recovered_plaintexts
            )
        )

        print(f"First 10 eval plaintexts: {game_state.eval_plaintexts[:10]}")
        print(f"First 10 recovered plaintexts: {recovered_plaintexts[:10]}")

        success = num_correct == len(game_state.eval_plaintexts)
        game_state.success = success
        game_state.finished = True

        return {
            "Game won": "Yes" if success else "No",
            "Number of correctly decrypted ciphertexts": f"{num_correct} of {len(eval_ciphertexts)}",
        }


class SymmetricTargetKeyRecoveryGame(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = SymmetricTargetKeyRecoveryGameState()
        self._stages = [KeyRecoveryStage()]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> SymmetricTargetKeyRecoveryGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
