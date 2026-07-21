#!/bin/bash

DEFAULT_SECURITY_GAME_FRAMEWORK_DIR="security_game_framework"

# When --download-sources is passed, each generated task's
# environment/algorithm_src/download_source.sh is run after the framework
# merge to refresh upstream archives from the network. Default behaviour
# leaves the vendored archives in place.
DOWNLOAD_SOURCES=0
# When --subset=VALUE is passed, the generated tasks_<DATE>/ folder is filtered
# to only contain tasks whose folder name matches the requested tier.
SUBSET=""
# When any of these timeout overrides are passed, the corresponding value in
# every generated task's task.toml (and the matching placeholder in
# instruction.md) is overwritten with the requested value. Empty = leave as-is.
VERIFIER_TIMEOUT_SEC=""
AGENT_TIMEOUT_SEC=""
ENVIRONMENT_BUILD_TIMEOUT_SEC=""
for arg in "$@"; do
    case "$arg" in
        --download-sources) DOWNLOAD_SOURCES=1 ;;
        --subset=*) SUBSET="${arg#--subset=}" ;;
        --verifier-timeout-sec=*) VERIFIER_TIMEOUT_SEC="${arg#--verifier-timeout-sec=}" ;;
        --agent-timeout-sec=*) AGENT_TIMEOUT_SEC="${arg#--agent-timeout-sec=}" ;;
        --environment-build-timeout-sec=*) ENVIRONMENT_BUILD_TIMEOUT_SEC="${arg#--environment-build-timeout-sec=}" ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [--download-sources] [--subset=T1|T2|benchmark|challenge|aimer] [--verifier-timeout-sec=VALUE] [--agent-timeout-sec=VALUE] [--environment-build-timeout-sec=VALUE]" >&2
            exit 2
            ;;
    esac
done

# Validate that any supplied timeout override is a positive number.
for pair in \
    "--verifier-timeout-sec:${VERIFIER_TIMEOUT_SEC}" \
    "--agent-timeout-sec:${AGENT_TIMEOUT_SEC}" \
    "--environment-build-timeout-sec:${ENVIRONMENT_BUILD_TIMEOUT_SEC}"; do
    flag="${pair%%:*}"
    value="${pair#*:}"
    [ -z "${value}" ] && continue
    if ! [[ "${value}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ "${value}" =~ ^0+(\.0+)?$ ]]; then
        echo "Invalid ${flag} value: ${value}" >&2
        echo "Must be a positive number" >&2
        exit 2
    fi
done

case "$SUBSET" in
    "" | T1 | T2 | benchmark | challenge | aimer) ;;
    *)
        echo "Invalid --subset value: $SUBSET" >&2
        echo "Must be one of: T1, T2, benchmark, challenge, aimer" >&2
        exit 2
        ;;
esac

# Family of a base algorithm folder, derived from its name prefix. The family
# also determines which variants the base can produce (by naming convention):
#   Cbase_* -> "frontier": full-strength modern primitive. Its generate_variants.sh
#              emits the simpler round-reduced tasks as T2_<name>_<r>_rounds and
#              a full round-reduced ladder (incl. the hardest) as C_<name>_<r>_rounds.
#   T1_*    -> "t1": its variants (if any) are also T1_*.
#   T2_*    -> "t2": its variants (if any) are also T2_*.
base_family() {
    case "$1" in
        Cbase_*) echo frontier ;;
        T1_*)    echo t1 ;;
        T2_*)    echo t2 ;;
        *)       echo other ;;
    esac
}

# Returns 0 if a base algorithm of the given family/name can contribute any task
# to the current subset. Bases that can't are skipped entirely (not copied, and
# their generate_variants.sh is never run) -- this is what makes
# --subset=challenge avoid expanding every T1_/T2_ variant generator.
#   - "frontier" bases are needed by T2/benchmark (they emit the T2_*_rounds
#     benchmark variants) and by challenge (full version + all variants).
#   - --subset=aimer is a bespoke tier that emits ONLY the T1_aimer base and its
#     IV-budget variants, so only the T1_aimer base is relevant there.
base_relevant() {
    local family="$1" name="$2"
    case "$SUBSET" in
        "")        return 0 ;;
        T1)        [[ "$family" == t1 ]] ;;
        T2)        [[ "$family" == t2 || "$family" == frontier ]] ;;
        benchmark) [[ "$family" == t1 || "$family" == t2 || "$family" == frontier ]] ;;
        challenge) [[ "$family" == frontier ]] ;;
        aimer)     [[ "$name" == T1_aimer ]] ;;
    esac
}

# The four bespoke T1_aimer IV-budget variant folders (T1_aimer_<budget>_ivs).
# The base T1_aimer folder is NOT one of them. These variants are only emitted
# under --subset=aimer (or no subset at all); T1/benchmark keep just the base.
is_aimer_variant() {
    case "$1" in
        T1_aimer_*_ivs) return 0 ;;
        *)              return 1 ;;
    esac
}

# Returns 0 if <base>/generate_variants.sh should be run under the current
# subset. Only T1_aimer is special-cased: its variant generator is skipped for
# every subset except --subset=aimer and no-subset, so T1/benchmark never even
# create the four IV-budget variants (they emit only the T1_O_aimer base).
expand_variants() {
    local name="$1"
    if [[ "$name" == T1_aimer ]]; then
        case "$SUBSET" in
            "" | aimer) return 0 ;;
            *)          return 1 ;;
        esac
    fi
    return 0
}

# Returns 0 if a specific member folder (a base or one of its variants) should
# be emitted as a task under the current subset. "family" is the family of the
# base that produced the member.
#   - Each frontier base emits three simpler round-reduced T2_<name>_<r>_rounds
#     variants (for T2/benchmark) plus four C_<name>_<r>_rounds variants (the
#     same three simpler rounds + the hardest round, for challenge).
#   - challenge emits the full-strength Cbase_* base AND its C_*_rounds
#     variants only (the T2_*_rounds are their duplicates and are left out).
#   - T1/T2/benchmark keep the historical name-prefix behaviour, so the
#     Cbase-derived T2_*_rounds land in the T2/benchmark sets while the Cbase
#     base and the C_*_rounds variants are dropped there. The one exception is
#     the T1_aimer IV-budget variants: T1/benchmark emit only the base and drop
#     those variants (they belong to the dedicated --subset=aimer tier).
#   - --subset=aimer emits ONLY the T1_aimer base and its IV-budget variants.
emit_member() {
    local family="$1" name="$2"
    case "$SUBSET" in
        "")        return 0 ;;
        T1)        [[ "$name" == T1_* ]] && ! is_aimer_variant "$name" ;;
        T2)        [[ "$name" == T2_* ]] ;;
        benchmark) { [[ "$name" == T1_* || "$name" == T2_* ]]; } && ! is_aimer_variant "$name" ;;
        challenge) [[ "$name" == Cbase_* || "$name" == C_* ]] ;;
        aimer)     [[ "$name" == T1_aimer ]] || is_aimer_variant "$name" ;;
    esac
}

# --------------------------------------------------------------------------
# Canonical task naming.
#
# The internal member folder names (produced by each base folder and its
# generate_variants.sh) still carry the tier prefix + encoded parameters that
# the subset logic above and various patch scripts rely on. We do NOT touch
# those. Instead, right before a member is emitted as a task, we translate its
# internal name into the uniform, human-facing task name:
#
#   <TIER>_O_<name>   original (unmodified) algorithm      (T1_O_/T2_O_/Cbase_O_)
#   T2_E_<name>       easy   difficulty variant
#   T2_M_<name>       medium difficulty variant
#   T2_H_<name>       hard   difficulty variant
#   C_E/M/H/XH_<name> challenge ladder (E/M/H mirror the reductions; XH = the
#                     extra hardest rung that has no easy/medium/hard analog)
#   T1_E/M/H/XH_<name> bespoke T1 ladder (currently only T1_aimer, banded by
#                     IV query budget rather than by round count)
#
# Most band variants are T2_* members; the round-reduced Cbase ladders emit
# T2_<name>_<r>_rounds (three E/M/H reductions) and C_<name>_<r>_rounds (the
# same three plus one extra-hard rung). T1_aimer is the one T1 exception.

# Map a Cbase round-reduced variant (base cipher + round count) to its band
# letter. The round triples/quads are fixed by each Cbase generate_variants.sh:
# the three lowest rounds are the E/M/H reductions, the extra (highest) C rung
# is XH. Returns UNKNOWN for anything unexpected so it surfaces loudly.
round_band() {
    case "${1}_${2}" in
        aes_4|chacha_2|katan_60|present_8|simon_10|skinny_10|speck_6)     echo E ;;
        aes_5|chacha_4|katan_85|present_10|simon_14|skinny_12|speck_8)    echo M ;;
        aes_6|chacha_6|katan_110|present_12|simon_18|skinny_14|speck_10)  echo H ;;
        aes_7|chacha_7|katan_124|present_29|simon_31|skinny_17|speck_19)  echo XH ;;
        *) echo UNKNOWN ;;
    esac
}

# Translate an internal member folder name to its uniform task name.
canonical_task_name() {
    local m="$1"

    # 1. Difficulty-band variants: always T2_<base>_variant_<...band...>.
    if [[ "$m" == T2_*_variant_* ]]; then
        local base="${m#T2_}"; base="${base%%_variant_*}"
        case "$m" in
            *easy*)   echo "T2_E_${base}" ;;
            *medium*) echo "T2_M_${base}" ;;
            *hard*)   echo "T2_H_${base}" ;;
            *)        echo "$m" ;;   # no band word -> leave untouched
        esac
        return
    fi

    # 2. Cbase round-reduced ladders: T2_<base>_<r>_rounds / C_<base>_<r>_rounds.
    if [[ "$m" =~ ^(T2|C)_(.+)_([0-9]+)_rounds$ ]]; then
        local tier="${BASH_REMATCH[1]}" base="${BASH_REMATCH[2]}" r="${BASH_REMATCH[3]}"
        echo "${tier}_$(round_band "$base" "$r")_${base}"
        return
    fi

    # 3. Bespoke T1_aimer query-budget variants: a four-rung ladder ordered by
    #    how tight the IV budget is (fewer IVs = harder), mirroring the
    #    E/M/H/XH bands used by the Cbase round-reduced ladders.
    case "$m" in
        T1_aimer_150_ivs) echo "T1_E_aimer";  return ;;
        T1_aimer_25_ivs)  echo "T1_M_aimer";  return ;;
        T1_aimer_15_ivs)  echo "T1_H_aimer";  return ;;
        T1_aimer_11_ivs)  echo "T1_XH_aimer"; return ;;
    esac

    # 4. Everything else is an original (unmodified) algorithm.
    case "$m" in
        Cbase_*) echo "Cbase_O_${m#Cbase_}" ;;
        T1_*)    echo "T1_O_${m#T1_}" ;;
        T2_*)    echo "T2_O_${m#T2_}" ;;
        *)       echo "$m" ;;
    esac
}
# --------------------------------------------------------------------------

# Regenerate the tasks manifest (backs the Croissant RecordSet in croissant.json).
echo "Regenerating tasks_manifest.csv"
python3 generate_tasks_manifest.py

# Generate date and time in the format YYYY-MM-DD_HH:MM:SS
DATE=$(date +%Y-%m-%d_%H-%M-%S)
TASKS_DIR="tasks_${DATE}"

# Create the tasks directory
echo "Creating directory: ${TASKS_DIR}"
mkdir -p "${TASKS_DIR}"

# Create a temporary directory for expanding algorithm variants
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "${TEMP_DIR}"' EXIT

# Lists the current variant folders in TEMP_DIR (basenames only, sorted).
list_temp() {
    find "${TEMP_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

# Counter for created folders
count=0

# Process each base algorithm (except 00_TEMPLATE). For every base we:
#   1. skip it entirely when its family can't contribute to the current subset
#      (so e.g. --subset=challenge never runs the T1_/T2_ variant generators),
#   2. expand it into TEMP_DIR via generate_variants.sh (variants are created
#      as siblings, so we diff the listing before/after to recover exactly which
#      folders this base produced -- its lineage),
#   3. emit the base and every variant that matches the subset as a task.
for algo_dir in algorithms/*/; do
    algo_name=$(basename "${algo_dir}")

    if [ "${algo_name}" == "00_TEMPLATE" ]; then
        continue
    fi

    family=$(base_family "${algo_name}")

    if ! base_relevant "${family}" "${algo_name}"; then
        continue
    fi

    # Expand this base into TEMP_DIR and recover the folders it produced.
    before=$(list_temp)
    cp -r "${algo_dir}" "${TEMP_DIR}/${algo_name}"
    if expand_variants "${algo_name}" && [ -f "${TEMP_DIR}/${algo_name}/generate_variants.sh" ]; then
        echo "Running generate_variants.sh for: ${algo_name}"
        bash "${TEMP_DIR}/${algo_name}/generate_variants.sh"
    fi
    after=$(list_temp)
    members=$(comm -13 <(printf '%s\n' "${before}") <(printf '%s\n' "${after}"))

    # Emit the base + each variant that matches the requested subset.
    while IFS= read -r member_name; do
        [ -z "${member_name}" ] && continue

        if ! emit_member "${family}" "${member_name}"; then
            continue
        fi

        # Translate the internal member name into the uniform task name used
        # for the emitted task folder (the subset logic above still keys off
        # the internal member_name, which is left untouched).
        task_name="$(canonical_task_name "${member_name}")"
        echo "Processing: ${member_name} -> ${task_name}"

        # Define the destination directory
        member_dir="${TEMP_DIR}/${member_name}"
        dest_dir="${TASKS_DIR}/${task_name}"

        # Copy the algorithm folder to the tasks directory
        cp -r "${member_dir}" "${dest_dir}"

        # Remove generate_variants.sh from the destination if present
        rm -f "${dest_dir}/generate_variants.sh"

        # Copy security_game_framework contents into the destination
        # Use -n flag to not overwrite existing files
        cp -rn ${DEFAULT_SECURITY_GAME_FRAMEWORK_DIR}/* "${dest_dir}/" 2>/dev/null || true

        # Run prepare_prompt.py to replace placeholders with actual values from
        # task.toml. Any timeout overrides are passed via OVERRIDE_* env vars; an
        # empty value means "leave the task.toml value untouched".
        OVERRIDE_VERIFIER_TIMEOUT_SEC="${VERIFIER_TIMEOUT_SEC}" \
        OVERRIDE_AGENT_TIMEOUT_SEC="${AGENT_TIMEOUT_SEC}" \
        OVERRIDE_ENVIRONMENT_BUILD_TIMEOUT_SEC="${ENVIRONMENT_BUILD_TIMEOUT_SEC}" \
        uv run "${dest_dir}/prepare_prompt.py"

        # If --download-sources was passed, refresh the vendored archives in the
        # generated task folder by running the algorithm's download_source.sh
        # (the in-repo vendored copies stay untouched).
        if [ "${DOWNLOAD_SOURCES}" = "1" ]; then
            ds="${dest_dir}/environment/algorithm_src/download_source.sh"
            if [ -f "${ds}" ]; then
                echo "  Refreshing upstream sources for: ${member_name}"
                bash "${ds}"
            fi
        fi

        ((count++))
    done <<< "${members}"
done

# Summary
echo ""
echo "======================================="
echo "Generation complete!"
echo "Total folders created: ${count}"
echo "Output directory: ${TASKS_DIR}"
echo "======================================="
