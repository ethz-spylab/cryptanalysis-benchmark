FROM buildpack-deps:24.04
WORKDIR /game-controller

# Necessary for the 'source' command to work in the shell
SHELL ["/bin/bash", "-c"]

RUN apt update -y && apt install -y gcc curl && rm -rf /var/lib/apt/lists/*

# Install uv
RUN curl -fsSL https://astral.sh/uv/install.sh | sh

# Ensure the uv environment is in the PATH
ENV PATH="/root/.local/bin/:$PATH"

# Install dependencies
RUN uv init
RUN uv add fastapi[standard] pydantic pyyaml

# Copy the game controller code
COPY ./game-controller/game_controller_server.py /game-controller/game_controller_server.py
COPY ./game-controller/oracle_log.py /game-controller/oracle_log.py
COPY ./game-controller/security_games /game-controller/security_games
COPY ./possible_security_games.yml /game-controller/possible_security_games.yml

# Compile the CLI binary
RUN mkdir -p /crypto_oracle
COPY ./algorithm_src/ /crypto_oracle
# RUN gcc -O3 -o /crypto_oracle/cli /crypto_oracle/src/*.c
RUN ls -la /crypto_oracle
RUN bash /crypto_oracle/build_cli.sh
RUN chmod +x /crypto_oracle/cli
