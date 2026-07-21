# CryptanalysisBench

This is a benchmark to test LLM agents' capability to find and exploit weaknesses in *real-world* cryptographic algorithms.

## Setup
Install uv.
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Install harbor. (Currently, we only support version 0.13.1.)

```bash
uv tool install harbor==0.13.1
```

Install all required packages.

```bash
uv sync
```

## Generating harbor tasks.
Harbor tasks can be compiled using the following command:
```bash
./generate_harbor_tasks.sh
```

### Build options

`generate_harbor_tasks.sh` accepts the following optional flags:

- `--download-sources` — re-fetch each algorithm's upstream archive at build time (via the algorithm's `download_source.sh`) instead of using the in-repo vendored copy. Use this when you want to refresh the sources from upstream. **NOTE: (time-costly!)**
- `--subset=VALUE` — only emit the tasks belonging to the requested tier in the generated `tasks_<DATE>/` folder. Supported values:
  - `T1` — efficiently-breakable legacy schemes (folders starting with `T1_`).
  - `T2` — schemes with only slow attacks or no known attacks (`T2_*` tasks); this includes both the standalone `T2_O_*` algorithms and the **three simpler** round-reduced variants (emitted as `T2_E_<name>`, `T2_M_<name>`, `T2_H_<name>`)
  - `benchmark` — the union of `T1` and `T2`; the regular evaluation set.
  - `challenge` — the full frontier set: every full-strength `Cbase_O_*` task **plus its `C_*` subvariants**. Each `Cbase_*` cipher emits a four-rung challenge ladder **plus** the hardest reduction, emitted as `C_E_<name>`, `C_M_<name>`, `C_H_<name>`, `C_XH_<name>` (e.g. `C_E_aes`, `C_M_aes`, `C_H_aes`, `C_XH_aes`).
  - `aimer` — a bespoke single-algorithm tier that emits **only** the `T1_aimer` base and its four IV-budget variants (`T1_O_aimer`, `T1_E_aimer`, `T1_M_aimer`, `T1_H_aimer`, `T1_XH_aimer`). The IV-budget variants are deliberately kept out of the `T1`/`benchmark` sets, which emit just the unmodified `T1_O_aimer` base; conversely `--subset=aimer` runs no other algorithm's variant generator.
- `--verifier-timeout-sec=VALUE` — overwrite `verifier.timeout_sec` in **every** generated task's `task.toml` with `VALUE`.
- `--agent-timeout-sec=VALUE` — overwrite `agent.timeout_sec` in **every** generated task's `task.toml` with `VALUE`.
- `--environment-build-timeout-sec=VALUE` — overwrite `environment.build_timeout_sec` in **every** generated task's `task.toml` with `VALUE`.

The three timeout flags apply uniformly to all emitted tasks **and their generated variants** (e.g. `T2_E_aes`), regardless of each task's original value. `VALUE` must be a positive number (e.g. `1800` or `1800.0`). When a timeout flag is omitted, that task's existing value is left untouched.

When `--subset` is omitted, all tasks are emitted: the full-strength `Cbase_O_*` frontier tasks, every `T1_*`/`T2_*` task (including the `T1_aimer` IV-budget ladder), and both round-reduced ladders each `Cbase_*` cipher produces — its three `T2_{E,M,H}_<name>` variants and its four `C_{E,M,H,XH}_<name>` variants.

### Generated task names

Every emitted task uses a uniform name that encodes its tier and difficulty:

```
<TIER>_O_<name>    original, unmodified algorithm   (T1_O_/T2_O_/Cbase_O_)
<TIER>_E_<name>    easy   difficulty variant
<TIER>_M_<name>    medium difficulty variant
<TIER>_H_<name>    hard   difficulty variant
<TIER>_XH_<name>   extra-hard variant (the hardest challenge rung; occurs rarely)
```

For example `Cbase_aes` is emitted as `Cbase_O_aes`, and its round-reduced variants become `T2_E_aes` / `T2_M_aes` / `T2_H_aes` (plus `C_E_aes` … `C_XH_aes` in the challenge set).

```bash
./generate_harbor_tasks.sh --subset=benchmark               # standard evaluation set (T1 + T2)
./generate_harbor_tasks.sh --subset=challenge               # full-strength Cbase_* tasks + their C_*_rounds ladders
./generate_harbor_tasks.sh --subset=aimer                   # only T1_aimer + its IV-budget ladder
./generate_harbor_tasks.sh --download-sources --subset=T1   # refresh sources, T1 only

# Overwrite the verifier/agent/build timeouts (seconds) for every generated task
./generate_harbor_tasks.sh --verifier-timeout-sec=3600 --agent-timeout-sec=3600 --environment-build-timeout-sec=1200
```
### Result replication
For the main runs of our benchmark, we used the following compilation command:
```bash
# Compile all harbor tasks with 2h agent runtime and 2h verification runtime limit.
./generate_harbor_tasks.sh --subset=benchmark --agent-timeout-sec=7200 --verifier-timeout-sec=7200
```

## Run the evaluation
*Note: Make sure to export the necessary API keys before evaluation.*

```bash
harbor run -p tasks_2026-XX-XX_XX-XX-XX -n X -a terminus-2 -m XXX
```
This is also the command that was used to for all runs in our benchmark.

See the [harbor documentation](https://harborframework.com/docs) for more information of how to use harbor.

## View agent traces
Run
```bash
harbor view jobs --port XXXX
```
then open:
```bash
http://127.0.0.1:XXXX
```

## Adding cryptographic algorithms
1. Create a copy of the folder `algorithms/00_TEMPLATE`
2. Create all files and tasks specified the TODO files.
3. (Optional) If necessary, you can additionally overwrite any file in the default task in `security_game_framework`, by adding a copy of the file at the correct location in your newly create folder. The script `./generate_harbor_tasks` basically just merges your newly created folder with the folder `security_game_framework`.

## Adding security games
1. Create a new file in `security_game_framework/environment/game-controller/security_games/`

2. Create a new class inheriting from `SecurityGame` (see the `base.py` file). If necessary, also create custom security game states and security game stages by inheriting from `SecurityGameState` and `SecurityGameStage`.

3. Register the game's class name in the framework-wide allowlist `security_game_framework/environment/game-controller/possible_security_games.yml` (the global list of implemented games).

4. Add an entry for the game to the `SECURITY_GAME_INFO_MAP` in `security_game_framework/tests/test_attack.py`, specifying the `num_attack_rounds` / `required_successes` thresholds that define a pass. Use `{1, 1}` for single-shot games; for games where random guessing has a non-trivial success probability (e.g. a 1-bit indistinguishability game), pick a larger round count and a threshold that rules out random (e.g. 17/20).

5. Add your new security game to the `possible_security_games.yml` file of each algorithm that should support it.

## Benchmark description

This benchmark evaluates LLM agents' ability to discover and exploit vulnerabilities in real-world cryptographic algorithms through formal security games. The framework provides a standardized environment where agents interact with a FastAPI server to conduct cryptanalytic attacks.

### Task Structure

Each benchmark task challenges the agent to:
1. **Explore** the cryptographic algorithm implementation and available security games
2. **Develop** a cryptanalytic attack against a chosen security game
3. **Automate** the attack in a script that reliably wins the security game

The agent succeeds when it creates an attack script that wins a sufficient fraction of games automatically.

### Security Games

Security games are formal cryptographic challenges that test specific security properties. For example:

- **Target Key Recovery (TKR)**: Recover the secret encryption key through oracle queries. Success requires extracting the exact key that can decrypt test ciphertexts correctly 100% of the time.

- **IND-CPA (Indistinguishability under Chosen Plaintext Attack)**: Distinguish between encryptions of two chosen plaintexts. Success requires guessing correctly significantly more than 50% of the time.

### Framework Architecture

The evaluation environment consists of:

- **Game Controller**: A FastAPI server that manages security game sessions, enforces rules, and provides oracle access
- **Client CLI**: A Python tool (`game_controller_client.py`) for interacting with the game controller
- **Algorithm Implementation**: Source code of the cryptographic algorithm (typically in C) that implements encryption/decryption oracles
- **Attack Development**: Agents develop attacks using any combination of scripting languages, with performance-critical code typically written in C

### Agent Workflow

The typical evaluation workflow:
1. **Manual Exploration**: Agent uses the `start_security_game` API to explore game mechanics interactively and analyze the algorithm implementation
2. **Attack Development**: Agent writes and tests a cryptanalytic attack script (`attack.sh`)
3. **Game Selection**: Agent selects a winnable security game and saves its name to `security_game_choice.txt`
4. **Automated Evaluation**: The framework automatically runs the attack script against fresh game instances to validate success

### API Interface

Agents interact with the framework through these main actions:
- `list_security_games` - List available security games for the algorithm
- `start_security_game` - Start an interactive game session for exploration
- `game_description` - Get detailed game information (stages, oracles, success criteria)
- `game_status` - Check current game session status
- `oracle_query` - Query encryption/decryption oracles
- `execute_current_stage` - Submit results and advance to the next stage

### Key Design Principles

- **Real Cryptographic Algorithms**: Tasks use actual historical cryptographic algorithms with known vulnerabilities, not artificial CTF challenges
- **Oracle-Based Access**: Agents never directly call cryptographic primitives; all access goes through the game controller to enforce security game rules
- **Performance Requirements**: Efficient attacks are crucial - games have time limits and query budgets
- **Multiple Game Types**: Different security games test different aspects of cryptographic security, allowing agents to choose the most exploitable weakness

## Dataset metadata (Croissant)

This benchmark ships a [Croissant](https://docs.mlcommons.org/croissant/) machine-readable metadata file at [`croissant.json`](croissant.json). It includes both the standard core fields and the [Responsible AI](https://docs.mlcommons.org/croissant/docs/croissant-rai-spec.html) fields (limitations, biases, use cases, social impact, provenance).

The Croissant file's `tasks` RecordSet is backed by [`tasks_manifest.csv`](tasks_manifest.csv), one row per cryptanalysis task (security class, scheme type, upstream algorithm source URL, allowed security games, presence of a reference solution, timeouts). The manifest is regenerated by `generate_tasks_manifest.py` and is also rebuilt at the top of `generate_harbor_tasks.sh`.

To validate locally:
```bash
uv add mlcroissant
python -c "import mlcroissant; mlcroissant.Dataset(jsonld='croissant.json')"
```
You can also paste `croissant.json` into the [online Croissant validator](https://huggingface.co/spaces/JoaquinVanschoren/croissant-checker) and the [RAI checker](https://huggingface.co/spaces/JoaquinVanschoren/croissant-rai-checker).
