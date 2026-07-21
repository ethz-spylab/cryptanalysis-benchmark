from typing import Any
import secrets

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
KEM Key Indistinguishability under Chosen-Ciphertext Attack (IND-CCA2) Game:

The adversary's goal is to break the key-indistinguishability of a KEM in
the chosen-ciphertext setting: given the challenger's public key, a freshly
produced encapsulation (ciphertext), and a candidate shared secret, decide
whether the candidate is the actual shared secret produced by that
encapsulation or an independent uniformly random value of the same length.
Unlike the IND-CPA variant of this game, the adversary additionally has
access to a `decapsulate` oracle that returns `decapsulate(private_key, ·)`
on any ciphertext *other than* the challenge encapsulation itself — this
captures the standard IND-CCA2 attack model in which the adversary may
adaptively query a "decryption oracle" after seeing the challenge, with the
challenge ciphertext being the only forbidden input.

Rules:
1. The challenger generates a random KEM keypair and a uniformly random
   challenge bit b in {0, 1}. The keypair and b are kept fixed for the
   entire session; the private key and b are never revealed.
2. In stage 1 the challenger runs `encapsulate` under its public key to
   obtain a ciphertext (the "encapsulation") together with the
   corresponding real shared secret K_real. It then returns to the
   adversary:
       - public-key   : the challenger's public key,
       - encapsulation: the freshly produced KEM ciphertext,
       - shared-secret: a candidate shared secret defined as
             K_real                     if b == 0,
             a uniformly random value   if b == 1
         (in either case the same byte length as K_real).
3. In stage 2 the adversary may adaptively query a `decapsulate` oracle
   on any ciphertext, with one exception: the oracle refuses to decapsulate
   the challenge encapsulation itself (it returns an error in that case).
   *Any* modification of the challenge ciphertext, however slight, is
   permitted. The oracle always uses the challenger's hidden private key —
   the adversary need not (and cannot) supply a private key. After
   finishing its oracle queries the adversary outputs a guess for b and
   wins iff the guess equals b.

The adversary may also freely run the scheme's own encapsulate algorithm
on the public key locally. Note: any KEM with a non-trivial distinguisher
in this game is broken in the IND-CCA2 sense; for "plain" KEMs that are
CPA-secure but malleable, a single well-chosen decapsulation query
typically suffices to win — this is precisely why CCA-secure KEMs use
transforms like Fujisaki-Okamoto.

Session Lifecycle:
- This is a two-stage game:
  Stage 1 - Receive (public-key, encapsulation, shared-secret) from the
            challenger. No oracles are available in this stage.
  Stage 2 - Adaptively query the `decapsulate` oracle on any ciphertext
            other than the challenge encapsulation, then submit your guess
            of the challenger's secret bit b (0 or 1).
- Submitting the guess in stage 2 completes the game session.
- During evaluation, this game will be played 20 times (independent
  sessions, each with a freshly sampled keypair, encapsulation and
  challenge bit). The adversary must win at least 17 out of 20 sessions
  to pass; note that a trivial random guess only wins ~50% of sessions in
  expectation, so a non-trivial distinguisher is required.
""".strip()


class KEMChosenCiphertextAttack2GameState(SecurityGameState):
    def __init__(self):
        super().__init__()
        self.sampled_bit: int = secrets.randbelow(2)
        self.encapsulation: str | None = None

    def required_state_variables(self) -> list[str]:
        return ["public_key", "private_key"]


class GetChallengeDataStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Receive the challenge tuple from the challenger. No oracles are available during this "
            "stage (the `decapsulate` oracle becomes available in stage 2). Use the "
            "`execute_current_stage` action with payload "
            '`{"stage_payload": {}}`. The response contains three hex-encoded fields:\n'
            "  - `public-key`     : the challenger's public key,\n"
            "  - `encapsulation`  : a fresh KEM ciphertext produced by running `encapsulate` under "
            "that public key,\n"
            "  - `shared-secret`  : a candidate shared secret which is *either* the actual shared "
            "secret produced together with that encapsulation (if the challenger's secret bit b is 0) "
            "or an independent uniformly random hex string of the same length (if b is 1).\n"
            "Your task in stage 2 is to guess which of the two cases holds, with the help of a "
            "decapsulation oracle that will refuse only the challenge encapsulation itself. You may "
            "also locally run the KEM's encapsulate algorithm on the public key as many times as you "
            "wish to study its distribution.\n"
        )
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: KEMChosenCiphertextAttack2GameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        result = self._oracle_query(
            "encapsulate", {"public-key": game_state.public_key}
        )
        if "encapsulation" not in result or "shared_secret_key" not in result:
            return self._abort(
                game_state,
                result.get(
                    "error", "Encapsulation oracle returned a malformed response"
                ),
            )
        encapsulation = result["encapsulation"]
        shared_secret = self._normalize_hex(result["shared_secret_key"])

        if game_state.sampled_bit == 0:
            potential_shared_secret = "0x" + shared_secret
        else:
            # Create a random hex string of the same length (in nibbles) as the shared secret.
            random_nibbles = [secrets.randbelow(16) for _ in range(len(shared_secret))]
            potential_shared_secret = "0x" + "".join(
                format(nibble, "x") for nibble in random_nibbles
            )

        game_state.encapsulation = encapsulation

        return {
            "public-key": game_state.public_key,
            "encapsulation": encapsulation,
            "shared-secret": potential_shared_secret,
        }


class DistinguishStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Adaptively query the `decapsulate` oracle (using the `oracle_query` action with "
            '`{"oracle_type": "decapsulate", "arguments": {"encapsulation": "0x..."}}`) on any '
            "ciphertext you choose, then submit your guess for the challenger's secret bit b. The "
            "oracle returns `decapsulate(private_key, encapsulation)` as `shared_secret_key` using "
            "the challenger's hidden private key; you do not (and cannot) supply a private key — "
            "any `private-key` argument you pass is overridden server-side. The oracle refuses "
            "exactly one input: the challenge encapsulation itself (compared after stripping any "
            "`0x`/`0X` prefix and lowercasing). Any modification of the challenge encapsulation, "
            "however slight, is permitted.\n"
            "\n"
            "Once you have finished oracle queries, submit your guess using the "
            "`execute_current_stage` action and the payload "
            '`{"stage_payload": {"sampled_bit_guess": <0 or 1>}}`. Use 0 if you believe the '
            "`shared-secret` returned in stage 1 was the *real* shared secret produced by the KEM's "
            "encapsulate algorithm together with the returned `encapsulation`, or 1 if you believe "
            "it was an independent uniformly random value. Submitting the guess completes the game "
            "session; you win iff your guess equals the bit the challenger actually sampled.\n"
        )
        self._allowed_oracles = ["decapsulate"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def oracle_query(
        self,
        game_state: KEMChosenCiphertextAttack2GameState,
        oracle_type: str,
        arguments: dict[str, str] | None = None,
    ) -> dict[str, str]:
        if oracle_type not in self.allowed_oracles():
            return {
                "error": f"Oracle type {oracle_type} is not allowed for this stage. Allowed oracles: {self.allowed_oracles()}"
            }

        bound_arguments = dict(arguments or {})

        if oracle_type == "decapsulate":
            encapsulation = bound_arguments.get("encapsulation")
            if isinstance(encapsulation, str):
                normalized, error = self._normalize_adversary_hex_fields(
                    {"encapsulation": encapsulation}
                )
                if error is not None:
                    return {"error": error}
                if normalized["encapsulation"] == self._normalize_hex(
                    game_state.encapsulation
                ):
                    return {
                        "error": "You are not allowed to query the `decapsulate` oracle with the challenge encapsulation."
                    }
                bound_arguments["encapsulation"] = normalized["encapsulation"]

        bound_arguments["private-key"] = game_state.private_key
        return self._oracle_query(oracle_type, bound_arguments)

    def execute(
        self,
        game_state: KEMChosenCiphertextAttack2GameState,
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

        return {
            "Game won": "Yes" if game_state.success else "No",
        }


class KEMChosenCiphertextAttack2Game(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = KEMChosenCiphertextAttack2GameState()
        self._stages = [
            GetChallengeDataStage(),
            DistinguishStage(),
        ]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> KEMChosenCiphertextAttack2GameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
