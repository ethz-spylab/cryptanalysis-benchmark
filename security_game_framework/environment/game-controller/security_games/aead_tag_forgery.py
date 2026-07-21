from typing import Any

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
AEAD Tag Forgery (ATF) Game:

The adversary's goal is to forge a valid ciphertext for an AEAD (Authenticated Encryption with Associated Data) scheme without having the corresponding plaintext, nonce, and associated data encrypted by the encryption oracle.

Rules:
1. The challenger generates a random secret key.
2. The adversary has access to an encryption oracle that can encrypt arbitrary messages with a given nonce and associated data.
3. The adversary is nonce-respecting: every call to the encryption oracle must use a fresh nonce that has not been used in any previous encryption query during this stage. The oracle rejects (and does not encrypt) any query whose nonce has already been used.
4. The adversary must submit a ciphertext along with a nonce and associated data such that the ciphertext decrypts successfully. The submitted (plaintext, nonce, associated data) triple must not have been previously queried to the encryption oracle. The forgery's nonce is allowed to repeat a nonce that was used in an encryption query (the nonce-respecting rule applies to encryption queries only).

The adversary wins if the submitted ciphertext decrypts to a valid plaintext and the corresponding (plaintext, nonce, associated data) triple was not queried to the encryption oracle.

Session Lifecycle:
- ATF is a single-stage game. The adversary must forge a valid ciphertext.
- Submitting your ciphertext, nonce, and associated data completes the game session.
- During evaluation, this game will only be played once. We therefore expect a 100% success rate.
""".strip()


class AEADTagForgeryGameState(SecurityGameState):
    def __init__(self):
        super().__init__()
        self.encryption_queries: set[tuple[str, str, str]] = set()
        self.used_nonces: set[str] = set()

    def required_state_variables(self) -> list[str]:
        return ["key"]


class TagForgeryStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Forge a valid ciphertext for some arbitrary plaintext. "
            "Find a ciphertext that decrypts successfully and then submit it along with its nonce and associated data using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"ciphertext": "<ciphertext>", "nonce": "<nonce>", "ad": "<associated_data>"}}`.\n'
            "All three fields must be hex-encoded strings (with or without the `0x` prefix). The following conditions immediately end the "
            "session as a loss: a missing `ciphertext`, `nonce`, or `ad` field, or any of these values not being a string.\n"
            "\n"
            "You have access to the following oracles during this stage (which you may call an arbitrary number of times):\n"
            "\n"
            "1. **Encryption oracle** - Given a plaintext, nonce, and associated data, returns the corresponding ciphertext.\n"
            "   Example:\n"
            '   python game_controller_client.py --action oracle_query --json \'{"oracle_type": "encrypt", "arguments": {"plaintext": "0xabc123...", "nonce": "0xdef456...", "ad": "0x789..."}}\'\n'
            "   Returns: ciphertext as a hex string.\n"
            "IMPORTANT: The encryption oracle is nonce-respecting. Every call must use a fresh nonce that has not been used in any previous encryption query during this stage; the oracle rejects (and does not encrypt) any query whose nonce was used before. "
            "The (plaintext, nonce, associated data) triple corresponding to the ciphertext you submit must not have been used in any calls to the encryption oracle during this stage; the forgery's nonce itself, however, may repeat a nonce that was used in an encryption query. "
            "The encryption oracle requires a `nonce` field on every call; omitted or non-string nonces are rejected. Missing `plaintext` or `ad` is treated as the empty hex string for the purposes of recording the queried triple."
        )
        self._allowed_oracles = ["encrypt"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def oracle_query(
        self,
        game_state: AEADTagForgeryGameState,
        oracle_type: str,
        arguments: dict[str, str] | None = None,
    ) -> dict[str, str]:
        """Records queried (plaintext, nonce, ad) triples and injects the secret key for encrypt oracle calls."""
        if arguments is None:
            arguments = {}

        if oracle_type not in self.allowed_oracles():
            return {
                "error": f"Oracle type {oracle_type} is not allowed for this stage. Allowed oracles: {self.allowed_oracles()}"
            }

        if oracle_type == "encrypt":
            # The nonce must be adversary-supplied: the AEAD CLI samples a
            # random nonce when `nonce:` is absent, which would yield a
            # usable ciphertext under a triple the freshness bookkeeping
            # never recorded. Reject missing/non-string nonces outright.
            if not isinstance(arguments.get("nonce"), str):
                return {
                    "error": "The encryption oracle requires a `nonce` field as a hex string."
                }
            # Missing or non-string `plaintext`/`ad` is recorded as the empty
            # hex string so that omitting a field cannot bypass the freshness
            # check (the underlying AEAD CLI defaults a missing `ad:` line to
            # empty AD, which would otherwise yield a usable ciphertext for a
            # triple that was never recorded).
            raw_fields = {
                name: arguments.get(name) for name in ("plaintext", "nonce", "ad")
            }
            present_fields = {
                name: v for name, v in raw_fields.items() if isinstance(v, str)
            }
            normalized_present, error = self._normalize_adversary_hex_fields(
                present_fields
            )
            if error is not None:
                return {"error": error}
            normalized_nonce = normalized_present.get("nonce", "")
            if normalized_nonce in game_state.used_nonces:
                return {
                    "error": (
                        "Nonce reuse is not allowed: the encryption oracle is "
                        "nonce-respecting, so each call must use a fresh nonce "
                        "that has not appeared in any previous encryption query "
                        "during this stage."
                    )
                }
            normalized_triple = (
                normalized_present.get("plaintext", ""),
                normalized_nonce,
                normalized_present.get("ad", ""),
            )
            game_state.encryption_queries.add(normalized_triple)
            game_state.used_nonces.add(normalized_nonce)
            arguments = {
                **arguments,
                **normalized_present,
                "key": game_state.key,
            }

        return self._oracle_query(oracle_type, arguments)

    def execute(
        self,
        game_state: AEADTagForgeryGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        normalized, error = self._normalize_adversary_hex_fields(
            {
                "ciphertext": payload.get("ciphertext"),
                "nonce": payload.get("nonce"),
                "ad": payload.get("ad"),
            }
        )
        if error is not None:
            return self._abort(game_state, error)

        ciphertext = normalized["ciphertext"]
        nonce = normalized["nonce"]
        ad = normalized["ad"]

        result = self._oracle_query(
            "decrypt",
            {
                "key": game_state.key,
                "nonce": nonce,
                "ciphertext": ciphertext,
                "ad": ad,
            },
        )
        message = result.get("plaintext")
        if message is None:
            return self._abort(
                game_state,
                result.get(
                    "error",
                    "Decryption oracle did not return a plaintext for the submitted ciphertext",
                ),
            )

        if (
            self._normalize_hex(message),
            nonce,
            ad,
        ) in game_state.encryption_queries:
            return self._abort(
                game_state,
                "The (plaintext, nonce, ad) triple corresponding to the submitted ciphertext was previously queried to the encrypt oracle",
            )

        game_state.success = True
        game_state.finished = True
        return {"Game won": "Yes"}


class AEADTagForgeryGame(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = AEADTagForgeryGameState()
        self._stages = [TagForgeryStage()]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> AEADTagForgeryGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
