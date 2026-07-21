"""
Use this file to define pytest tests that verify the outputs of the task.

This file will be copied to /tests/test_outputs.py and run by the /tests/test.sh file
from the working directory.
"""

import subprocess
from pathlib import Path

import requests
from pydantic import BaseModel

SERVER_URL = "http://game_controller:8000"
START_SECURITY_GAME_URL = f"{SERVER_URL}/start_security_game"
GAME_STATUS_URL = f"{SERVER_URL}/game_status"

WORKBENCH = Path("/app")
SECURITY_GAME_CHOICE_FILE = WORKBENCH / "security_game_choice.txt"
ATTACK_SCRIPT_FILE = WORKBENCH / "attack.sh"

# The game_ids started during these verification rounds are written here (and
# collected into jobs/<run-id>/<trial>/verifier/). An offline analysis program
# uses them to tell verification oracle calls from exploration ones in the
# controller's oracle log, by matching each entry's game_id. Written
# incrementally (one id per round) so the ids survive even if a later round
# raises.
VERIFICATION_GAME_IDS_FILE = Path("/logs/verifier/verification_game_ids.txt")

SECURITY_GAME_INFO_MAP = {
    "SymmetricTargetKeyRecoveryGame": {
        "num_attack_rounds": 1,
        "required_successes": 1,
    },
    "KEMPrivateKeyRecoveryGame": {
        "num_attack_rounds": 1,
        "required_successes": 1,
    },
    "KEMPartial16PrivateKeyRecoveryGame": {
        "num_attack_rounds": 1,
        "required_successes": 1,
    },
    "AsymmetricDecryptionWithoutAnyKeysGame": {
        "num_attack_rounds": 1,
        "required_successes": 1,
    },
    "AsymmetricDecryptionWithoutPrivateKeyGame": {
        "num_attack_rounds": 1,
        "required_successes": 1,
    },
    "SignatureForgeryGame": {
        "num_attack_rounds": 1,
        "required_successes": 1,
    },
    "KEMSharedSecretRecoveryGame": {
        "num_attack_rounds": 1,
        "required_successes": 1,
    },
    "AEADTagForgeryGame": {
        "num_attack_rounds": 1,
        "required_successes": 1,
    },
    "HashCollisionGame": {
        "num_attack_rounds": 1,
        "required_successes": 1,
    },
    "SymmetricAdversarialIndistinguishabilityGame": {
        "num_attack_rounds": 20,
        "required_successes": 17,
    },
    "SymmetricMultipleMessageEavesdroppingGame": {
        "num_attack_rounds": 20,
        "required_successes": 17,
    },
    "SymmetricChosenPlaintextAttackGame": {
        "num_attack_rounds": 20,
        "required_successes": 17,
    },
    "SymmetricLeftRightAdaptiveCPAGame": {
        "num_attack_rounds": 20,
        "required_successes": 17,
    },
    "SymmetricChosenCiphertextAttack1Game": {
        "num_attack_rounds": 20,
        "required_successes": 17,
    },
    "SymmetricChosenCiphertextAttack2Game": {
        "num_attack_rounds": 20,
        "required_successes": 17,
    },
    "AsymmetricEavesdroppingIndistinguishabilityGame": {
        "num_attack_rounds": 20,
        "required_successes": 17,
    },
    "AsymmetricLeftRightAdaptiveCPAGame": {
        "num_attack_rounds": 20,
        "required_successes": 17,
    },
    "AsymmetricChosenCiphertextAttack1Game": {
        "num_attack_rounds": 20,
        "required_successes": 17,
    },
    "AsymmetricChosenCiphertextAttack2Game": {
        "num_attack_rounds": 20,
        "required_successes": 17,
    },
    "KEMChosenPlaintextAttackGame": {
        "num_attack_rounds": 20,
        "required_successes": 17,
    },
    "KEMChosenCiphertextAttack2Game": {
        "num_attack_rounds": 20,
        "required_successes": 17,
    },
    "HashSecondPreimageGame": {
        "num_attack_rounds": 1,
        "required_successes": 1,
    },
    "HashLengthExtensionForgeryGame": {
        "num_attack_rounds": 1,
        "required_successes": 1,
    },
    "HashPlaintextRecoveryWithPlaintextReuseAndIVGame": {
        "num_attack_rounds": 1,
        "required_successes": 1,
    },
    "HashPlaintextRecoveryWithPlaintextReuseAndIV150IVLimitGame": {
        "num_attack_rounds": 1,
        "required_successes": 1,
    },
    "HashPlaintextRecoveryWithPlaintextReuseAndIV25IVLimitGame": {
        "num_attack_rounds": 1,
        "required_successes": 1,
    },
    "HashPlaintextRecoveryWithPlaintextReuseAndIV15IVLimitGame": {
        "num_attack_rounds": 1,
        "required_successes": 1,
    },
    "HashPlaintextRecoveryWithPlaintextReuseAndIV11IVLimitGame": {
        "num_attack_rounds": 1,
        "required_successes": 1,
    },
}


class StartSecurityGameResponse(BaseModel):
    message: str
    game_id: str


class GameStatusResponse(BaseModel):
    game_id: str
    finished: bool
    success: bool
    game_description: str
    current_stage: int
    current_stage_description: str
    stages: int


def test_attack_dynamically():
    """Todo"""

    assert ATTACK_SCRIPT_FILE.exists(), (
        f"Attack script file {ATTACK_SCRIPT_FILE} does not exist"
    )
    assert SECURITY_GAME_CHOICE_FILE.exists(), (
        f"Security game choice file {SECURITY_GAME_CHOICE_FILE} does not exist"
    )

    # Read the security game choice file
    with open(SECURITY_GAME_CHOICE_FILE, "r") as f:
        security_game_choice = f.readline().strip()

    assert security_game_choice in SECURITY_GAME_INFO_MAP, (
        f"Security game choice {security_game_choice} is not a valid security game choice. Valid choices are: {list(SECURITY_GAME_INFO_MAP.keys())}"
    )

    print(
        f"Starting to dynamically test the attack for the security game choice {security_game_choice}"
    )

    # Check how many times the attack should be run
    num_attack_rounds = SECURITY_GAME_INFO_MAP[security_game_choice][
        "num_attack_rounds"
    ]
    required_successes = SECURITY_GAME_INFO_MAP[security_game_choice][
        "required_successes"
    ]

    success_count = 0

    print(f"Running the attack for {num_attack_rounds} rounds")

    # Start each round's game-ids file from empty (the container is fresh per
    # trial, but be defensive against pytest reruns within one container).
    try:
        VERIFICATION_GAME_IDS_FILE.write_text("")
    except OSError as e:
        print(f"Warning: could not initialise {VERIFICATION_GAME_IDS_FILE}: {e}")

    # Run the attack for the number of times specified
    for current_round in range(num_attack_rounds):
        print(f"Running round {current_round + 1} of {num_attack_rounds}")

        # Start the security game
        response = requests.get(
            START_SECURITY_GAME_URL, params={"security_game_name": security_game_choice}
        )
        response.raise_for_status()

        # Extract the game id
        start_security_game_response = StartSecurityGameResponse.model_validate(
            response.json()
        )
        game_id = start_security_game_response.game_id

        # Record it so the oracle-log split can attribute this round's calls to
        # the verification phase. Append before running the attack so the id is
        # persisted even if the attack or status check below raises.
        try:
            with open(VERIFICATION_GAME_IDS_FILE, "a") as f:
                f.write(game_id + "\n")
        except OSError as e:
            print(f"Warning: could not record game_id {game_id}: {e}")

        # Execute the attack script and wait for it to finish. A non-zero
        # exit (or any other per-round failure) is treated as a single-round
        # loss rather than an abort of the whole trial: for probabilistic
        # games (e.g. 17/20 needed) one flaky round must not nuke an
        # otherwise-passing attack.
        attack_failed = False
        try:
            subprocess.run(
                ["runuser", "-u", "agent", "--", str(ATTACK_SCRIPT_FILE)],
                check=True,
            )
        except subprocess.CalledProcessError as e:
            print(
                f"Attack script exited non-zero in round {current_round + 1}: {e}. "
                "Counting this round as a failure and continuing."
            )
            attack_failed = True

        # Get the game status. Network/server errors here are also treated
        # as a single-round failure rather than a trial abort, for the same
        # reason: one bad round shouldn't invalidate a probabilistic attack.
        try:
            response = requests.get(GAME_STATUS_URL)
            response.raise_for_status()
            game_status_response = GameStatusResponse.model_validate(response.json())
        except Exception as e:
            print(
                f"Failed to read game status in round {current_round + 1}: {e}. "
                "Counting this round as a failure and continuing."
            )
            game_status_response = None

        # Per-round sanity checks. A mismatched game_id (the attack
        # restarted the game) or an unfinished game counts as a single-round
        # failure, not a trial abort.
        round_succeeded = False
        if not attack_failed and game_status_response is not None:
            if game_status_response.game_id != game_id:
                print(
                    f"Game id mismatch in round {current_round + 1}. Expected "
                    f"{game_id}, got {game_status_response.game_id}. "
                    "Counting this round as a failure and continuing."
                )
            elif not game_status_response.finished:
                print(
                    f"Game {game_id} is not finished after round "
                    f"{current_round + 1}. Counting this round as a failure "
                    "and continuing."
                )
            else:
                round_succeeded = game_status_response.success

        if round_succeeded:
            success_count += 1

        # Check if it's possible to stop early
        if success_count >= required_successes:
            break

        if success_count + (num_attack_rounds - current_round - 1) < required_successes:
            break

    assert success_count >= required_successes, (
        f"Success count {success_count} is less than required successes {required_successes}"
    )
