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

# Per-machine overrides, if present.
# shellcheck disable=SC1090
[[ -r "$_USER_ENV" ]] && source "$_USER_ENV"

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

export NSCLC_ATLAS_H5AD EPITHELIAL_TME_ROOT \
       GENEFORMER_TOKEN_DICT GENEFORMER_MODEL_DIR PYTHON_BIN

lab_env_check() {
    # Report which resolved paths actually exist. Missing entries are printed
    # rather than exiting, because a machine legitimately holds only the assets
    # for the arm it ran.
    local name value missing=0
    printf '\n\033[1mResolved lab paths\033[0m\n'
    for name in NSCLC_ATLAS_H5AD EPITHELIAL_TME_ROOT \
                GENEFORMER_TOKEN_DICT GENEFORMER_MODEL_DIR PYTHON_BIN; do
        value="${!name}"
        if [[ -e "$value" ]]; then
            printf '  \033[32mok     \033[0m %-24s %s\n' "$name" "$value"
        else
            printf '  \033[31mMISSING\033[0m %-24s %s\n' "$name" "$value"
            missing=$((missing + 1))
        fi
    done
    if [[ $missing -gt 0 ]]; then
        printf '\n  %d path(s) missing.\n' "$missing"
        printf '  If the migration has not run yet: sudo bash tools/migrate_to_srv_lab.sh --inventory\n'
        printf '  If this machine legitimately lacks them, set them in %s\n' "$_USER_ENV"
    fi
    return 0
}

# Allow `bash tools/lab_env.sh` as a quick check without sourcing.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    lab_env_check
fi
