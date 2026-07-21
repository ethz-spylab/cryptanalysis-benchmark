from typing import Any
import secrets

from .base import SecurityGame, SecurityGameStage, SecurityGameState

GAME_DESCRIPTION = """
KEM Key Indistinguishability under Chosen-Plaintext Attack (IND-CPA) Game:

The adversary's goal is to break the key-indistinguishability of a KEM:
given the challenger's public key, a freshly produced encapsulation
(ciphertext), and a candidate shared secret, decide whether the candidate
is the actual shared secret produced by that encapsulation or an
independent uniformly random value of the same length. No oracles are
exposed in either stage — for a KEM, "chosen-plaintext attack" simply
means the adversary holds the public key and can therefore run the KEM's
own encapsulate algorithm on it locally as many times as it likes, but
does not get any decapsulation oracle.

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
3. In stage 2 the adversary outputs a guess for b and wins iff the guess
   equals b.

The adversary may freely run the scheme's own encapsulate algorithm on
the public key locally to study its distribution; no separate oracles
are offered. Note: for a secure KEM (e.g. IND-CPA-secure under standard
assumptions) no efficient adversary should win significantly more often
than 50%; a KEM for which a non-trivial distinguisher exists is broken
in the IND-CPA sense.

Session Lifecycle:
- This is a two-stage game:
  Stage 1 - Receive (public-key, encapsulation, shared-secret) from the
            challenger.
  Stage 2 - Submit your guess of the challenger's secret bit b (0 or 1).
- Submitting the guess in stage 2 completes the game session.
- During evaluation, this game will be played 20 times (independent
  sessions, each with a freshly sampled keypair, encapsulation and
  challenge bit). The adversary must win at least 17 out of 20 sessions
  to pass; note that a trivial random guess only wins ~50% of sessions in
  expectation, so a non-trivial distinguisher is required.
""".strip()


class KEMChosenPlaintextAttackGameState(SecurityGameState):
    def __init__(self):
        super().__init__()
        self.sampled_bit: int = secrets.randbelow(2)

    def required_state_variables(self) -> list[str]:
        return ["public_key", "private_key"]


class GetChallengeDataStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Receive the challenge tuple from the challenger. No oracles are available during this "
            "stage. Use the `execute_current_stage` action with payload "
            '`{"stage_payload": {}}`. The response contains three hex-encoded fields:\n'
            "  - `public-key`     : the challenger's public key,\n"
            "  - `encapsulation`  : a fresh KEM ciphertext produced by running `encapsulate` under "
            "that public key,\n"
            "  - `shared-secret`  : a candidate shared secret which is *either* the actual shared "
            "secret produced together with that encapsulation (if the challenger's secret bit b is 0) "
            "or an independent uniformly random hex string of the same length (if b is 1).\n"
            "Your task in stage 2 is to guess which of the two cases holds. You may locally run the "
            "KEM's encapsulate algorithm on the public key as many times as you wish to study its "
            "distribution, but doing so only yields fresh independent (ciphertext, shared_secret) "
            "pairs — it does not let you decapsulate the challenger's `encapsulation`, and there is "
            "no decapsulation oracle in either stage.\n"
        )
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: KEMChosenPlaintextAttackGameState,
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

        return {
            "public-key": game_state.public_key,
            "encapsulation": encapsulation,
            "shared-secret": potential_shared_secret,
        }


class DistinguishStage(SecurityGameStage):
    def __init__(self):
        super().__init__()
        self._stage_description = (
            "Submit your guess for the challenger's secret bit b. No oracles are available during "
            "this stage (and none were available in stage 1 either — this is a chosen-plaintext, "
            "i.e. no-decapsulation-oracle, game). Use 0 if you think the `shared-secret` field "
            "returned in stage 1 was the *real* shared secret produced by the KEM's encapsulate "
            "algorithm together with the returned `encapsulation`, or 1 if you think it was an "
            "independent uniformly random value. You win iff your guess equals the bit the "
            "challenger actually sampled.\n"
            "\n"
            "Submit the guess using the `execute_current_stage` action and the payload "
            '`{"stage_payload": {"sampled_bit_guess": <0 or 1>}}`. Submitting the guess completes '
            "the game session.\n"
        )
        self._allowed_oracles = []

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def execute(
        self,
        game_state: KEMChosenPlaintextAttackGameState,
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


class KEMChosenPlaintextAttackGame(SecurityGame):
    def __init__(self):
        super().__init__()
        self._game_description = GAME_DESCRIPTION
        self._game_state = KEMChosenPlaintextAttackGameState()
        self._stages = [
            GetChallengeDataStage(),
            DistinguishStage(),
        ]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> KEMChosenPlaintextAttackGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
