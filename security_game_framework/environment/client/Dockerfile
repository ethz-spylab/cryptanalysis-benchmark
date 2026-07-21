FROM buildpack-deps:24.04
WORKDIR /app

# Install useful packages. tmux + asciinema are pre-installed so terminus-2's
# _attempt_tmux_installation short-circuits (it would otherwise call apt-get,
# which fails under the demoted agent UID). fakeroot is for the agent's
# `dpkg --extract` workflow when it needs system packages without root.
RUN apt update -y && apt install -y gcc curl ca-certificates bzip2 z3 tmux asciinema fakeroot && rm -rf /var/lib/apt/lists/*

# Install uv to /usr/local/bin (system path) so the demoted agent (UID 5000)
# can reach it. /root/.local/ is mode 700 on Ubuntu and inaccessible to
# non-root users — installing there breaks `uv run /app/game_controller_client.py`
# from the agent.
RUN curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

RUN uv init
RUN rm README.md main.py
RUN uv add fastapi[standard] pydantic pyyaml requests

# Activate the Python virtual environment
ENV VIRTUAL_ENV=/app/.venv
ENV PATH="/app/.venv/bin:$PATH"

# Install useful software
### SageMath
ENV CONDA_DIR=/opt/conda

RUN curl -L -o /tmp/miniforge.sh \
      "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh" \
    && bash /tmp/miniforge.sh -b -p "${CONDA_DIR}" \
    && rm -f /tmp/miniforge.sh \
    && "${CONDA_DIR}/bin/conda" clean -a -y

# Install Sage into its own env
RUN "${CONDA_DIR}/bin/conda" install -y -n base -c conda-forge mamba \
    && "${CONDA_DIR}/bin/mamba" create -y -n sage -c conda-forge sage \
    && "${CONDA_DIR}/bin/conda" clean -a -y

# Install a `sage` shim instead of a direct symlink. Conda-forge sage's
# `sage.features.pkg_systems` runs `sage -p` and `sage -pip --version` as
# subprocesses during `from sage.all import *`. Both invocations re-enter
# the heavyweight conda-forge `sage` wrapper, which itself does
# `from sage.all import *` — exponential fork-bomb (~6000 subprocesses,
# import never returns). The shim short-circuits those two cases and
# delegates everything else to the real binary.
RUN cat > /usr/local/bin/sage <<'SH' && chmod +x /usr/local/bin/sage
#!/bin/sh
case "$1" in
    -p)   exit 1 ;;
    -pip) shift; exec /opt/conda/envs/sage/bin/python -m pip "$@" ;;
    *)    exec /opt/conda/envs/sage/bin/sage "$@" ;;
esac
SH

# Sage's runtime needs Singular, gap, maxima, ecl, gp (PARI), etc. They
# live in the conda env's bin/ but the env is never activated. Append it
# to PATH (after system dirs so it can't shadow project tools). Without
# this, `from sage.all import *` raises FeatureNotPresentError on Singular.
ENV PATH="${PATH}:/opt/conda/envs/sage/bin"


COPY algorithm_src/ /app/algorithm_src
RUN bash /app/algorithm_src/build_cli.sh
RUN chmod +x /app/algorithm_src/cli

COPY client/game_controller_client.py /app/game_controller_client.py

# === Privilege drop setup ===
#
# The container's runtime USER stays root so Harbor's verifier `docker exec`
# inherits root naturally (no Harbor patch needed). Every other bash invocation
# — including the agent's commands and the oracle's solve.sh — is demoted to
# the unprivileged `agent` user by the wedge below in /etc/bash.bashrc.
#
# UID 5000 is deliberately chosen to NOT collide with typical host UIDs
# (1000-2000), so bind-mounted /logs/* don't appear agent-owned inside the
# container.

RUN useradd -m -u 5000 -s /bin/bash agent \
    && chown -R agent:agent /app /home/agent

# The wedge. Sourced by every interactive bash on Debian/Ubuntu (Harbor's
# `docker compose exec -it main bash -ic <cmd>` is interactive). The verifier
# carries RUN_AS_ROOT=1 in its env via task.toml's [verifier.env] block; the
# agent's exec calls do not. So the verifier stays root; the agent demotes
# itself before its command runs.
RUN cat >> /etc/bash.bashrc <<'WEDGE'

# --- cryptobench privilege-drop wedge ---
if [ "$(id -u)" = "0" ] && [ -z "$RUN_AS_ROOT" ]; then
    if [ -n "$BASH_EXECUTION_STRING" ]; then
        exec runuser -u agent -- bash -c "$BASH_EXECUTION_STRING"
    else
        exec runuser -u agent -- bash
    fi
fi
# --- end wedge ---
WEDGE
