from typing import Any

from .base import SecurityGame, SecurityGameStage, SecurityGameState


def build_game_description(iv_budget: int | None = None) -> str:
    """Build the HPR-RIV game description.

    `iv_budget` is the maximum number of hash oracle queries the adversary may
    issue during the recovery stage (one IV consumed per query). `None` means
    the oracle may be queried an unlimited number of times; an integer caps it
    and the corresponding restriction is documented in the description.
    """
    access_word = "limited access" if iv_budget is not None else "access"

    if iv_budget is not None:
        budget_rule = (
            f"3. The number of hash oracle queries is restricted: the adversary "
            f"may\n"
            f"   issue at most {iv_budget} hash oracle queries during the recovery "
            f"stage.\n"
            f"   Each query consumes one IV (whether the adversary supplies it or "
            f"the\n"
            f"   oracle generates it). Once this budget is exhausted, further hash\n"
            f"   oracle queries return an error instead of a digest.\n"
        )
        submit_rule_number = 4
        attack_extra = (
            " The query restriction additionally tests whether the attack "
            "remains feasible within a bounded number of observations."
        )
    else:
        budget_rule = ""
        submit_rule_number = 3
        attack_extra = ""

    return f"""
Hash Plaintext Recovery with Plaintext Reuse and IV (HPR-RIV) Game:

The adversary's goal is to recover a secret plaintext that the challenger
keeps hidden, given only {access_word} to a hash oracle that *always* hashes
that same hidden plaintext (plaintext reuse) under an initialization vector
(IV).

Rules:
1. The challenger samples a uniformly random secret plaintext x and never
   reveals it.
2. The adversary has access to a hash oracle. Every call hashes the *same*
   hidden plaintext x; any `plaintext` the adversary supplies is ignored.
   The adversary may, however, choose the IV used for each call (or omit it,
   in which case the oracle generates one).
{budget_rule}{submit_rule_number}. The adversary must finally submit a single candidate plaintext.

The adversary wins iff the submitted candidate equals the hidden plaintext x
(compared after hex normalization, i.e. ignoring any `0x`/`0X` prefix and
case).

This game targets hash constructions that leak their (reused) input when the
adversary controls or observes the IV — a secure hash must not allow x to be
recovered from hash(x, IV) values.{attack_extra}

Session Lifecycle:
- HPR-RIV is a single-stage game (only the plaintext recovery stage).
- Submitting your candidate plaintext completes the game session.
- During evaluation, this game is played a single time per session — random
  guessing wins with negligible probability, so a successful run implies an
  actual plaintext-recovery attack rather than luck.
""".strip()


def build_stage_description(iv_budget: int | None = None) -> str:
    """Build the recovery stage description, optionally documenting an IV budget.

    See `build_game_description` for the meaning of `iv_budget`.
    """
    if iv_budget is not None:
        call_clause = ""
        budget_paragraph = (
            "\n"
            "\n"
            f"Query budget: you may issue at most {iv_budget} hash oracle queries "
            "during this stage. Each query consumes one IV, whether you supply the "
            "`iv` yourself or let the oracle generate one. Queries that fail (e.g. "
            "once the budget is exhausted, or if the underlying scheme does not echo "
            "an `iv`) do not consume budget. Once the budget is exhausted, any "
            "further hash oracle query returns an error instead of a digest, but you "
            "can still submit your candidate plaintext with `execute_current_stage`."
        )
    else:
        call_clause = " (which you may call an arbitrary number of times)"
        budget_paragraph = ""

    return (
        "Recover the hidden secret plaintext x that the challenger sampled. "
        "Submit your candidate using the `execute_current_stage` action and the payload "
        '`{"stage_payload": {"recovered_plaintext": "<recovered_plaintext>"}}`.\n'
        "`recovered_plaintext` must be a hex-encoded string (with or without the `0x` prefix). "
        "The following conditions immediately end the session as a loss: a missing "
        "`recovered_plaintext` field, the value not being a string, or the value not being "
        "valid hex.\n"
        "\n"
        "You win iff your candidate equals the hidden plaintext after hex normalization "
        "(ignoring any `0x`/`0X` prefix and case).\n"
        "\n"
        f"You have access to the following oracle during this stage{call_clause}:\n"
        "\n"
        "1. **Hash oracle** - Returns the hash digest of the hidden secret plaintext. "
        "Every call hashes the *same* hidden plaintext (plaintext reuse); any `plaintext` "
        "argument you supply is ignored. You may supply an `iv` argument to control the "
        "initialization vector used for that call; if you omit it, the oracle generates an "
        "IV automatically. The response contains the digest under the field `hash`, and "
        "(depending on the underlying scheme) may echo the `iv` that was used.\n"
        "   Example (adversary-chosen IV):\n"
        '   python game_controller_client.py --action oracle_query --json \'{"oracle_type": "hash", "arguments": {"iv": "0x0011223344556677"}}\'\n'
        "   Example (oracle-generated IV):\n"
        '   python game_controller_client.py --action oracle_query --json \'{"oracle_type": "hash", "arguments": {}}\'\n'
        "   Returns: the hash digest as a hex string under `hash`." + budget_paragraph
    )


class HashPlaintextRecoveryWithPlaintextReuseAndIVGameState(SecurityGameState):
    def __init__(self):
        super().__init__()
        # `_generate_random_plaintext` returns a list; this game uses a single
        # hidden plaintext that is reused for every hash oracle call.
        self.plaintext: str = self._generate_random_plaintext(1)[0]
        # Number of hash oracle queries that have consumed an IV (i.e. returned
        # a digest). Always tracked; only enforced when the stage has a budget.
        # Lives on the game state so it survives across oracle calls.
        self.hash_queries_used: int = 0

    def required_state_variables(self) -> list[str]:
        return []


class HashPlaintextRecoveryStage(SecurityGameStage):
    def __init__(self, iv_budget: int | None = None):
        super().__init__()
        # Maximum number of hash oracle queries allowed during this stage. `None`
        # means unlimited; an integer caps the number of IVs the adversary can
        # observe. This is the single knob the IV-limited variants override.
        self._iv_budget = iv_budget
        self._stage_description = build_stage_description(iv_budget)
        self._allowed_oracles = ["hash"]

    def stage_description(self) -> str:
        return self._stage_description

    def allowed_oracles(self) -> list[str]:
        return self._allowed_oracles

    def oracle_query(
        self,
        game_state: HashPlaintextRecoveryWithPlaintextReuseAndIVGameState,
        oracle_type: str,
        arguments: dict[str, str] | None = None,
    ) -> dict[str, str]:
        if oracle_type not in self.allowed_oracles():
            return {
                "error": f"Oracle type {oracle_type} is not allowed for this stage. Allowed oracles: {self.allowed_oracles()}"
            }

        # Enforce the IV-query budget (no-op when `self._iv_budget` is None).
        # Checked before spending the oracle call so an over-budget query never
        # leaks a fresh digest.
        if (
            self._iv_budget is not None
            and oracle_type == "hash"
            and game_state.hash_queries_used >= self._iv_budget
        ):
            return {
                "error": (
                    f"Hash oracle query budget exhausted: you may issue at most "
                    f"{self._iv_budget} hash oracle queries (one IV per query) "
                    "during this stage. Submit your candidate plaintext with "
                    "`execute_current_stage`."
                )
            }

        bound_arguments = dict(arguments or {})

        if oracle_type == "hash":
            # Plaintext reuse: every call hashes the same hidden plaintext.
            # Any adversary-supplied `plaintext` is overridden. The adversary
            # keeps control of `iv` (if absent, the CLI generates one).
            bound_arguments["plaintext"] = game_state.plaintext

        # `plaintext` here is stage-injected ground truth the adversary must
        # not see. It is logged verbatim like every other oracle call; the
        # oracle log is kept secret by file permissions (0600), not redaction.
        response = self._oracle_query(oracle_type, bound_arguments)

        # Pass CLI/parse failures through unchanged. Failed queries leak no new
        # IV/hash pair, so they don't count against the budget.
        if "error" in response:
            return response

        # The attack relies on the adversary observing the IV used for each
        # call (whether they supplied it or the oracle generated one). If the
        # algorithm's `hash` CLI does not echo `iv`, the game is unwinnable —
        # fail gracefully with a clear message instead of returning a digest
        # whose IV the adversary can never learn.
        if "iv" not in response:
            return {
                "error": (
                    "The hash oracle did not echo an `iv` field in its "
                    "response. This game requires the underlying algorithm's "
                    "`hash` command to return the IV it used; the configured "
                    "algorithm does not support this."
                )
            }

        # A digest was returned, so this query consumed an IV. Count it (only
        # matters when a budget is set).
        game_state.hash_queries_used += 1

        return response

    def execute(
        self,
        game_state: HashPlaintextRecoveryWithPlaintextReuseAndIVGameState,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        normalized, error = self._normalize_adversary_hex_fields(
            {"recovered_plaintext": payload.get("recovered_plaintext")}
        )
        if error is not None:
            return self._abort(game_state, error)

        recovered_plaintext = normalized["recovered_plaintext"]
        plaintext = self._normalize_hex(game_state.plaintext)

        game_state.finished = True
        if recovered_plaintext == plaintext:
            game_state.success = True
            return {"Game won": "Yes"}

        game_state.success = False
        return {"Game won": "No"}


class HashPlaintextRecoveryWithPlaintextReuseAndIVGame(SecurityGame):
    # Maximum number of hash oracle queries the adversary may issue during the
    # recovery stage. `None` = unlimited. IV-limited variants subclass this game
    # and set an integer here — that single value drives the stage enforcement
    # and both the game and stage descriptions.
    IV_BUDGET: int | None = None

    def __init__(self):
        super().__init__()
        self._game_description = build_game_description(self.IV_BUDGET)
        self._game_state = HashPlaintextRecoveryWithPlaintextReuseAndIVGameState()
        self._stages = [HashPlaintextRecoveryStage(iv_budget=self.IV_BUDGET)]

    def game_description(self) -> str:
        return self._game_description

    def game_state(self) -> HashPlaintextRecoveryWithPlaintextReuseAndIVGameState:
        return self._game_state

    def stages(self) -> list[SecurityGameStage]:
        return self._stages
