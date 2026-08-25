#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 SOURCE_GF TARGET_HOST TARGET_GF [--include-atlas]" >&2
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
  usage
  exit 2
fi

SOURCE_GF="$(realpath "$1")"
TARGET_HOST="$2"
TARGET_GF="$3"
INCLUDE_ATLAS=0
if [[ ${4:-} == "--include-atlas" ]]; then
  INCLUDE_ATLAS=1
elif [[ $# -eq 4 ]]; then
  usage
  exit 2
fi

ROOT_ASSETS=("Geneformer-V2-104M" "pyproject.toml" "uv.lock" ".python-version")
KD_ASSETS=(
  "tcell_luad_lusc_normal_10k_from_atlas"
  "tcell_luad_lusc_normal_luscmax7000_finetune"
  "tcell_luad_lusc_normal_luscmax7000_heldout_allgene_perturbation"
)

for asset in "${ROOT_ASSETS[@]}"; do
  [[ -e "$SOURCE_GF/$asset" ]] || { echo "Missing $SOURCE_GF/$asset" >&2; exit 1; }
done
for asset in "${KD_ASSETS[@]}"; do
  [[ -e "$SOURCE_GF/KD/$asset" ]] || { echo "Missing $SOURCE_GF/KD/$asset" >&2; exit 1; }
done
if [[ "$INCLUDE_ATLAS" == "1" && ! -f "$SOURCE_GF/KD/data/nsclc/nsclc_integrated.h5ad" ]]; then
  echo "Missing source atlas" >&2
  exit 1
fi

printf -v target_root_q '%q' "$TARGET_GF"
ssh "$TARGET_HOST" "mkdir -p $target_root_q/KD $target_root_q/KD/data/nsclc"

RSYNC_OPTIONS=(-aH --partial --info=progress2 --protect-args)

for asset in "${ROOT_ASSETS[@]}"; do
  rsync "${RSYNC_OPTIONS[@]}" "$SOURCE_GF/$asset" "$TARGET_HOST:$TARGET_GF/"
done
for asset in "${KD_ASSETS[@]}"; do
  rsync "${RSYNC_OPTIONS[@]}" "$SOURCE_GF/KD/$asset" "$TARGET_HOST:$TARGET_GF/KD/"
done
if [[ "$INCLUDE_ATLAS" == "1" ]]; then
  rsync "${RSYNC_OPTIONS[@]}" \
    "$SOURCE_GF/KD/data/nsclc/nsclc_integrated.h5ad" \
    "$TARGET_HOST:$TARGET_GF/KD/data/nsclc/"
fi

echo "Active experiment transfer complete. No destination files were deleted."
