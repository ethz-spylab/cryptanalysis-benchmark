from typing import Any

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
Signature Forgery (SF) Game:

The adversary's goal is to forge a valid signature for a message without having that message signed by the signature oracle.

Rules:
1. The challenger generates a random public/private key pair.
2. The challenger provides the public key to the adversary.
3. The adversary has access to a signature oracle that can sign arbitrary messages.
4. The adversary must submit a message along with a valid signature for that message.The submitted message must not have been previously queried to the signature oracle.

The adversary wins if the submitted signature is valid and the message was not queried to the signature oracle.

Session Lifecycle:
- SF is a two-stage game. In the first stage the adversary receives the public key. In the second stage the adversary must forge a signature.
- Submitting your message and the corresponding forged signature completes the game session.
- During evaluation, this game will only be played once. We therefore expect a 100% success rate.
""".strip()


class SignatureForgeryGameState(SecurityGameState):
    def __init__(self):
        super().__init__()
        self.signature_queries: set[str] = set()

    def required_state_variables(self) -> list[str]:
        return ["public_key", "private_key"]


class GetPublicKeyStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = 'Use the action `execute_current_stage` with payload `{"stage_payload": {}}` to receive a public key.'
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: SignatureForgeryGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        return {
            "public key": game_state.public_key,
        }


class SignatureForgeryStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Forge a signature for some arbitrary message."
            "Find a message for which you can forge a signature and then submit it along with its signature using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"message": "<message>", "signature": "<signature>"}}`.\n'
            "Both `message` and `signature` must be hex-encoded strings (with or without the `0x` prefix). The following conditions immediately end the session as a loss: "
            "a missing `message` or `signature` field, or either value not being a string.\n"
            "\n"
            "You have access to the following oracles during this stage (which you may call an arbitrary number of times):\n"
            "\n"
            "1. **Signature oracle** - Given a message, returns the corresponding signature.\n"
            "   Example:\n"
            '   python game_controller_client.py --action oracle_query --json \'{"oracle_type": "sign", "arguments": {"message": "0xabc123..."}}\'\n'
            "   Returns: signature as a hex string.\n"
            "IMPORTANT: The message you submit must not have been used in any calls to the signature oracle during this stage. "
            "A missing `message` in a sign-oracle call is treated as the empty hex string for the purposes of recording the queried message."
        )
        self._allowed_oracles = ["sign"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def oracle_query(
        self,
        game_state: SignatureForgeryGameState,
        oracle_type: str,
        arguments: dict[str, str] | None = None,
    ) -> dict[str, str]:
        """Records queried messages and injects the private key for sign oracle calls."""
        if arguments is None:
            arguments = {}

        if oracle_type not in self.allowed_oracles():
            return {
                "error": f"Oracle type {oracle_type} is not allowed for this stage. Allowed oracles: {self.allowed_oracles()}"
            }

        if oracle_type == "sign":
            # A missing or non-string `message` is recorded as the empty hex
            # string so that omitting the field cannot bypass the freshness
            # check (the underlying CLI defaults a missing `message:` line to
            # empty input, which would otherwise yield a usable signature for
            # a message that was never recorded).
            raw_message = arguments.get("message")
            if isinstance(raw_message, str):
                normalized, error = self._normalize_adversary_hex_fields(
                    {"message": raw_message}
                )
                if error is not None:
                    return {"error": error}
                game_state.signature_queries.add(normalized["message"])
                arguments = {**arguments, "message": normalized["message"]}
            else:
                game_state.signature_queries.add("")
            arguments = {**arguments, "private-key": game_state.private_key}

        return self._oracle_query(oracle_type, arguments)

    def execute(
        self,
        game_state: SignatureForgeryGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        normalized, error = self._normalize_adversary_hex_fields(
            {
                "message": payload.get("message"),
                "signature": payload.get("signature"),
            }
        )
        if error is not None:
            return self._abort(game_state, error)
        message = normalized["message"]
        signature = normalized["signature"]

        if message in game_state.signature_queries:
            return self._abort(
                game_state,
                "The submitted message was previously queried to the sign oracle",
            )

        verify_result = self._oracle_query(
            "verify",
            {
                "public-key": game_state.public_key,
                "message": message,
                "signature": signature,
            },
        )

        game_state.success = verify_result.get("valid") == "true"
        game_state.finished = True
        return {"Game won": "Yes" if game_state.success else "No"}


class SignatureForgeryGame(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = SignatureForgeryGameState()
        self._stages = [GetPublicKeyStage(), SignatureForgeryStage()]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> SignatureForgeryGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
