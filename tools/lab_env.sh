#!/usr/bin/env bash
# Resolve every machine-specific path the analyses need, in one place.
#
# Source it, do not execute it:
#
#   source tools/lab_env.sh
#   python epithelial_tme_validation/data_harmonization/build_unified_epithelial_dataset.py
#
# Resolution order, first hit wins per variable:
#   1. anything already exported in the environment  (explicit override)
#   2. ~/.config/geneformer-lung-tcell/paths.env     (per-machine, untracked)
#   3. the /srv/lab defaults below                   (post-migration layout)
#
# The scripts in this repository all read these variables and fall back to their
# own defaults, so sourcing this is optional but makes a machine's layout
# explicit in one auditable place instead of scattered across call sites. Paths
# are never hardcoded in tracked analysis code -- see WORKFLOW.md.

_LAB_ROOT="${LAB_ROOT:-/srv/lab}"
_USER_ENV="${LAB_ENV_FILE:-$HOME/.config/geneformer-lung-tcell/paths.env}"

# The variables this file is responsible for resolving.
_LAB_VARS=(NSCLC_ATLAS_H5AD EPITHELIAL_TME_ROOT GENEFORMER_TOKEN_DICT GENEFORMER_MODEL_DIR PYTHON_BIN)

# Remember which of them the caller set, BEFORE sourcing the per-machine file.
# The resolution order above promises that an explicit environment variable
# wins, but a paths.env written with a plain assignment (PYTHON_BIN=...) simply
# overwrites one -- silently, so an override appears to be ignored for no
# reason. Enforcing the order here makes the promise true no matter how any
# machine's paths.env is written, including the ones that already exist and the
# ones nobody is going to edit.
# One plain variable per saved value rather than an associative array:
# `declare -A` is bash 4+, and this file is SOURCED, so the sourcing shell's
# version governs and the shebang does not. macOS ships bash 3.2, where the
# associative form aborts the source part-way through -- the defaults below
# would never run and lab_env_check would never be defined. Indexed arrays and
# `printf -v` are bash 3.1+, so this works everywhere the file already worked.
for _lab_v in "${_LAB_VARS[@]}"; do
    [[ -n "${!_lab_v+set}" ]] && printf -v "_LAB_PRESET_$_lab_v" '%s' "${!_lab_v}"
done

# Per-machine overrides, if present.
# shellcheck disable=SC1090
[[ -r "$_USER_ENV" ]] && source "$_USER_ENV"

# Restore anything the caller set that the per-machine file overwrote.
for _lab_v in "${_LAB_VARS[@]}"; do
    _lab_p="_LAB_PRESET_$_lab_v"
    [[ -n "${!_lab_p+set}" ]] && printf -v "$_lab_v" '%s' "${!_lab_p}"
    unset "$_lab_p"
done
unset _lab_v _lab_p _LAB_VARS

# Defaults only fill variables the caller has not already set.
# Defaults only fill variables the caller has not already set.
# NSCLC_ATLAS_H5AD's real location (discovered during this repo's data audit)
# is NOT under $_LAB_ROOT/KD -- it lives in the geneformer-uv-starter analysis
# workspace instead. geneformer-nsclc-tcell's own docs still say
# ~/workspace/KD/data/nsclc/nsclc_integrated.h5ad, which does not resolve; that
# is a stale-documentation bug in that sibling repo, not fixed here.
: "${NSCLC_ATLAS_H5AD:=$HOME/workspace/geneformer-uv-starter/geneformer-workspace/analysis/data/nsclc/nsclc_integrated.h5ad}"
: "${EPITHELIAL_TME_ROOT:=$_LAB_ROOT/KD/epithelial_tme}"
: "${GENEFORMER_TOKEN_DICT:=$_LAB_ROOT/geneformer/geneformer/token_dictionary_gc104M.pkl}"
: "${GENEFORMER_MODEL_DIR:=$_LAB_ROOT/geneformer/Geneformer-V2-104M}"
# The interpreter is deliberately NOT under $_LAB_ROOT. A virtualenv embeds the
# absolute paths of the machine and user that built it, so it cannot be shared
# through a group-readable directory the way data can. Each user rebuilds their
# own with geneformer_uv_setup/scripts/bootstrap_workspace.sh.
: "${PYTHON_BIN:=$HOME/workspace/geneformer-uv-starter/.venv/bin/python}"

# LAB_ROOT is resolved at the top of this file, BEFORE the per-machine file is
# sourced, so the seven defaults above always use the caller's root. Republish
# that same value and export it, so a child process cannot resolve LAB_ROOT to
# a different root than the one these were built from. Without this, a script
# reading os.environ["LAB_ROOT"] can get a second root out of the same command:
# either from an `export LAB_ROOT=` in the per-machine file, which nothing here
# restores, or from a caller who set LAB_ROOT without exporting it -- line 19
# reads it either way, but a child never sees it. One command, one root.
LAB_ROOT="$_LAB_ROOT"

export LAB_ROOT NSCLC_ATLAS_H5AD EPITHELIAL_TME_ROOT \
       GENEFORMER_TOKEN_DICT GENEFORMER_MODEL_DIR PYTHON_BIN

lab_env__python_usable() {
    # A virtualenv directory can exist and still be useless: a rebuilt but
    # unpopulated .venv passes -e while containing no packages at all. Existence
    # is not usability, so run the interpreter instead of stat-ing its path.
    local py="$1"
    [[ -x "$py" ]] || return 1
    "$py" -c 'import numpy' >/dev/null 2>&1
}

lab_env_check() {
    # Report which resolved paths actually exist. Missing entries are printed
    # rather than exiting, because a machine legitimately holds only the assets
    # for the arm it ran.
    local name value missing=0 broken=0
    printf '\n\033[1mResolved lab paths\033[0m\n'
    for name in NSCLC_ATLAS_H5AD EPITHELIAL_TME_ROOT \
                GENEFORMER_TOKEN_DICT GENEFORMER_MODEL_DIR PYTHON_BIN; do
        value="${!name}"
        if [[ ! -e "$value" ]]; then
            printf '  \033[31mMISSING\033[0m %-24s %s\n' "$name" "$value"
            missing=$((missing + 1))
        elif [[ "$name" == "PYTHON_BIN" ]] && ! lab_env__python_usable "$value"; then
            # Reported separately from MISSING: the path is there, so the fault
            # is a broken or unpopulated environment, not a wrong pointer.
            printf '  \033[31mBROKEN \033[0m %-24s %s\n' "$name" "$value"
            printf '           %s\n' "exists but cannot run 'import numpy'; rebuild it with"
            printf '           %s\n' "geneformer_uv_setup/scripts/bootstrap_workspace.sh"
            broken=$((broken + 1))
        else
            printf '  \033[32mok     \033[0m %-24s %s\n' "$name" "$value"
        fi
    done
    # Counted separately: a missing path and a broken interpreter have
    # different causes and different fixes, so a single tally labelled
    # "missing" would misreport one of them.
    if [[ $missing -gt 0 ]]; then
        printf '\n  %d path(s) missing.\n' "$missing"
        printf '  If the migration has not run yet: sudo bash tools/migrate_to_srv_lab.sh --inventory\n'
        printf '  If this machine legitimately lacks them, set them in %s\n' "$_USER_ENV"
    fi
    if [[ $broken -gt 0 ]]; then
        printf '\n  %d interpreter(s) present but not usable.\n' "$broken"
        printf '  The path exists, so this is an unpopulated or broken environment,\n'
        printf '  not a wrong pointer. Rebuild it rather than repointing it.\n'
    fi
    return 0
}

# Allow `bash tools/lab_env.sh` as a quick check without sourcing.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    lab_env_check
fi
