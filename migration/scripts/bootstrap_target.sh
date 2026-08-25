#!/usr/bin/env bash
set -euo pipefail

EXPECTED_COMMIT="f45a6c7"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 GENEFORMER_ROOT" >&2
  exit 2
fi

GF_ROOT="$(realpath "$1")"
if [[ ! -d "$GF_ROOT/.git" ]]; then
  echo "Not a Geneformer Git checkout: $GF_ROOT" >&2
  exit 1
fi

ACTUAL_COMMIT="$(git -C "$GF_ROOT" rev-parse --short=7 HEAD)"
if [[ "$ACTUAL_COMMIT" != "$EXPECTED_COMMIT" ]]; then
  echo "Geneformer commit mismatch: expected $EXPECTED_COMMIT, found $ACTUAL_COMMIT" >&2
  echo "Checkout the pinned commit before bootstrapping." >&2
  exit 1
fi

for file in pyproject.toml uv.lock .python-version; do
  [[ -f "$GF_ROOT/$file" ]] || { echo "Missing $GF_ROOT/$file" >&2; exit 1; }
done

if ! command -v uv >/dev/null 2>&1; then
  echo "uv is not installed or not on PATH." >&2
  exit 1
fi

cd "$GF_ROOT"
uv sync --frozen

.venv/bin/python - <<'PY'
import platform
import sys

sys.path.insert(0, ".")
import datasets
import geneformer
import torch
import transformers

print("platform:", platform.platform())
print("python:", sys.version.replace("\n", " "))
print("torch:", torch.__version__)
print("torch CUDA:", torch.version.cuda)
print("CUDA available:", torch.cuda.is_available())
print("GPU:", torch.cuda.get_device_name(0) if torch.cuda.is_available() else None)
print("transformers:", transformers.__version__)
print("datasets:", datasets.__version__)
print("Geneformer import: OK")
PY
