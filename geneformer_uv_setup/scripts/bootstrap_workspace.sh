#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 WORKSPACE_ROOT ANALYSIS_NAME PROFILE [GENEFORMER_REF]" >&2
  echo "Profiles: default, cpu, cu130, postprocess" >&2
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
  usage
  exit 2
fi

WORKSPACE_ROOT="$1"
ANALYSIS_NAME="$2"
PROFILE="$3"
GENEFORMER_REF="${4:-main}"

case "$PROFILE" in
  default|cpu|cu130|postprocess) ;;
  *) usage; exit 2 ;;
esac

if [[ "$ANALYSIS_NAME" == */* || "$ANALYSIS_NAME" == "." || "$ANALYSIS_NAME" == ".." ]]; then
  echo "ANALYSIS_NAME must be one directory name without slashes." >&2
  exit 2
fi

for command in git git-lfs uv; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$SETUP_ROOT/templates"

mkdir -p "$WORKSPACE_ROOT"
WORKSPACE_ROOT="$(realpath "$WORKSPACE_ROOT")"
GENEFORMER_ROOT="$WORKSPACE_ROOT/Geneformer"
ANALYSIS_ROOT="$WORKSPACE_ROOT/$ANALYSIS_NAME"

git lfs install
if [[ ! -e "$GENEFORMER_ROOT" ]]; then
  git clone https://huggingface.co/ctheodoris/Geneformer "$GENEFORMER_ROOT"
  git -C "$GENEFORMER_ROOT" checkout "$GENEFORMER_REF"
elif [[ ! -d "$GENEFORMER_ROOT/.git" ]]; then
  echo "Existing path is not a Git checkout: $GENEFORMER_ROOT" >&2
  exit 1
else
  actual_ref="$(git -C "$GENEFORMER_ROOT" rev-parse HEAD)"
  requested_ref="$(git -C "$GENEFORMER_ROOT" rev-parse "$GENEFORMER_REF^{commit}")"
  if [[ "$actual_ref" != "$requested_ref" ]]; then
    echo "Existing Geneformer checkout does not match $GENEFORMER_REF." >&2
    echo "Use a separate workspace or resolve the checkout intentionally." >&2
    exit 1
  fi
fi

if ! git -C "$GENEFORMER_ROOT" diff --quiet \
  || ! git -C "$GENEFORMER_ROOT" diff --cached --quiet; then
  echo "Existing Geneformer checkout has tracked modifications." >&2
  echo "Use a clean checkout so the recorded commit fully describes the source." >&2
  exit 1
fi

if [[ -f "$GENEFORMER_ROOT/pyproject.toml" ]]; then
  project_name="$(
    awk '
      /^\[project\][[:space:]]*$/ { in_project=1; next }
      /^\[/ { in_project=0 }
      in_project && /^[[:space:]]*name[[:space:]]*=/ {
        line=$0
        sub(/^[^=]*=[[:space:]]*/, "", line)
        gsub(/["[:space:]]/, "", line)
        print line
        exit
      }
    ' "$GENEFORMER_ROOT/pyproject.toml"
  )"
  if [[ -n "$project_name" && "$project_name" != "geneformer" ]]; then
    echo "Geneformer metadata conflict: pyproject.toml names project '$project_name'." >&2
    echo "Use a clean upstream checkout whose package metadata names 'geneformer'." >&2
    exit 1
  fi
fi

if [[ -e "$ANALYSIS_ROOT" ]]; then
  echo "Refusing to overwrite existing analysis path: $ANALYSIS_ROOT" >&2
  exit 1
fi

mkdir -p "$ANALYSIS_ROOT/scripts" "$ANALYSIS_ROOT/notebooks" \
  "$ANALYSIS_ROOT/configs" "$ANALYSIS_ROOT/results"
cp "$TEMPLATE_DIR/.python-version" "$ANALYSIS_ROOT/.python-version"
cp "$TEMPLATE_DIR/.gitignore" "$ANALYSIS_ROOT/.gitignore"
cp "$TEMPLATE_DIR/README.md" "$ANALYSIS_ROOT/README.md"
cp "$TEMPLATE_DIR/pyproject.$PROFILE.toml" "$ANALYSIS_ROOT/pyproject.toml"
cp "$TEMPLATE_DIR/analysis.py" "$ANALYSIS_ROOT/scripts/analysis.py"
cp "$SETUP_ROOT/scripts/smoke_test.py" "$ANALYSIS_ROOT/scripts/smoke_test.py"
chmod +x "$ANALYSIS_ROOT/scripts/analysis.py" "$ANALYSIS_ROOT/scripts/smoke_test.py"

git -C "$GENEFORMER_ROOT" rev-parse HEAD > "$ANALYSIS_ROOT/.geneformer-commit"

cd "$ANALYSIS_ROOT"
uv lock
uv sync --locked
uv run --locked python scripts/smoke_test.py --geneformer-root "$GENEFORMER_ROOT"

echo "Created Geneformer analysis at $ANALYSIS_ROOT"
echo "Commit pyproject.toml, uv.lock, .python-version, and .geneformer-commit."
