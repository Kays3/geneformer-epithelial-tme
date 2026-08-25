#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 GENEFORMER_ROOT OUTPUT_DIR [--include-atlas]" >&2
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage
  exit 2
fi

GF_ROOT="$(realpath "$1")"
OUTPUT_DIR="$2"
INCLUDE_ATLAS=0
if [[ ${3:-} == "--include-atlas" ]]; then
  INCLUDE_ATLAS=1
elif [[ $# -eq 3 ]]; then
  usage
  exit 2
fi

ACTIVE_PATHS=(
  "Geneformer-V2-104M"
  "KD/tcell_luad_lusc_normal_10k_from_atlas"
  "KD/tcell_luad_lusc_normal_luscmax7000_finetune"
  "KD/tcell_luad_lusc_normal_luscmax7000_heldout_allgene_perturbation"
  "pyproject.toml"
  "uv.lock"
  ".python-version"
)
if [[ "$INCLUDE_ATLAS" == "1" ]]; then
  ACTIVE_PATHS+=("KD/data/nsclc/nsclc_integrated.h5ad")
fi

ABSOLUTE_PATHS=()
for relative_path in "${ACTIVE_PATHS[@]}"; do
  if [[ ! -e "$GF_ROOT/$relative_path" ]]; then
    echo "Missing required source asset: $GF_ROOT/$relative_path" >&2
    exit 1
  fi
  ABSOLUTE_PATHS+=("$GF_ROOT/$relative_path")
done

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(realpath "$OUTPUT_DIR")"

{
  date --iso-8601=seconds
  uname -a
  if [[ -f /etc/os-release ]]; then
    sed -n '1,20p' /etc/os-release
  fi
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
  fi
  if command -v nvcc >/dev/null 2>&1; then
    nvcc --version
  fi
} > "$OUTPUT_DIR/system.txt"

{
  git -C "$GF_ROOT" status -sb
  git -C "$GF_ROOT" remote -v
  git -C "$GF_ROOT" log -1 --oneline --decorate
} > "$OUTPUT_DIR/git-state.txt"

{
  for relative_path in "${ACTIVE_PATHS[@]}"; do
    du -sh "$GF_ROOT/$relative_path"
  done
  du -sch "${ABSOLUTE_PATHS[@]}" | tail -1
} > "$OUTPUT_DIR/sizes.txt"

PYTHON_BIN="$GF_ROOT/.venv/bin/python"
if [[ -x "$PYTHON_BIN" ]]; then
  "$PYTHON_BIN" - <<'PY' > "$OUTPUT_DIR/python-packages.txt"
import platform
import sys
from importlib.metadata import distributions

print("python", sys.version.replace("\n", " "))
print("platform", platform.platform())
for distribution in sorted(distributions(), key=lambda item: item.metadata["Name"].lower()):
    print(f"{distribution.metadata['Name']}=={distribution.version}")
PY
else
  echo "No executable environment at $PYTHON_BIN" > "$OUTPUT_DIR/python-packages.txt"
fi

(
  cd "$GF_ROOT"
  find "${ACTIVE_PATHS[@]}" -type f -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum
) > "$OUTPUT_DIR/files.sha256"

cat > "$OUTPUT_DIR/README.txt" <<EOF
Geneformer migration inventory
Generated: $(date --iso-8601=seconds)
Source root: $GF_ROOT
Atlas included: $INCLUDE_ATLAS
Verify with migration/scripts/verify_target.py and pass this files.sha256 as
the --manifest argument.
EOF

echo "Inventory written to $OUTPUT_DIR"
