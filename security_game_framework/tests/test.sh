#!/bin/bash

# Use this file to install test dependencies and run the tests.
# It will be copied to /tests/test.sh and run from the working directory.
#
# curl and uv are pre-installed in the Dockerfile (uv at /usr/local/bin),
# so no privileged bootstrap is needed here. The verifier inherits root
# from the container's USER directive (gated by the bashrc wedge that
# checks RUN_AS_ROOT in /etc/bash.bashrc).

# Check if we're in a valid working directory
if [ "$PWD" = "/" ]; then
    echo "Error: No working directory set. Please set a WORKDIR in your Dockerfile before running this script."
    exit 1
fi

# --- Harden the verifier output directory against forged rewards -------------
# Harbor grades a trial by reading /logs/verifier/reward.json (preferred) or, as
# a fallback, /logs/verifier/reward.txt. That directory is bind-mounted into the
# agent container, and harbor chmods it world-writable (0777) at container
# startup; the attack script later runs as the unprivileged `agent` user. Without
# the guards below, an attack could simply drop a /logs/verifier/reward.json
# containing {"reward": 1} and be graded as a pass regardless of the real game
# outcome: this script only ever writes reward.txt, so a planted reward.json wins
# the precedence and is never overwritten.
#
# This script runs as root (RUN_AS_ROOT=1) before pytest/the attack, so it can:
#   1. delete any reward file pre-planted during the agent phase, and
#   2. drop the directory back to 0755 so the `agent` user can no longer write
#      there for the rest of the grading phase (the verifier writes as root).
rm -f /logs/verifier/reward.json /logs/verifier/reward.txt
chmod 0755 /logs/verifier 2>/dev/null || true

echo "Running tests"
uvx \
  -p 3.13 \
  -w pytest==8.4.1 \
  -w pytest-json-ctrf==0.3.5 \
  -w requests \
  -w pydantic \
  pytest --ctrf /logs/verifier/ctrf.json /tests/test_attack.py -v -rA
PYTEST_EXIT=$?

# Write the authoritative reward as root. Remove any reward.json first: harbor
# prefers reward.json over reward.txt, and this script never legitimately
# produces one, so any reward.json here could only be a forged/leftover file.
rm -f /logs/verifier/reward.json
if [ $PYTEST_EXIT -eq 0 ]; then
  echo 1 > /logs/verifier/reward.txt
else
  echo 0 > /logs/verifier/reward.txt
fi
echo "Created reward file with value: $(cat /logs/verifier/reward.txt)"
