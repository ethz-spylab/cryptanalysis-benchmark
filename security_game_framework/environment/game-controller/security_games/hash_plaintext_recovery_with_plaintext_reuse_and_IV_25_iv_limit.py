from .hash_plaintext_recovery_with_plaintext_reuse_and_IV import (
    HashPlaintextRecoveryWithPlaintextReuseAndIVGame,
)


class HashPlaintextRecoveryWithPlaintextReuseAndIV25IVLimitGame(
    HashPlaintextRecoveryWithPlaintextReuseAndIVGame
):
    """HPR-RIV restricted to 25 hash oracle queries (IVs) during recovery.

    Everything else — state, stage logic, win condition, and the (budget-aware)
    game/stage descriptions — is inherited from the base game; only the budget
    differs.
    """

    IV_BUDGET = 25
