# General Geneformer + uv setup

This directory creates a clean, reusable Geneformer analysis environment on a
new machine. It is independent of the NSCLC experiment and is intended as the
starting point for tokenization, embeddings, fine-tuning, classification, or
in silico perturbation projects.

The layout keeps upstream Geneformer code separate from each analysis:

```text
workspace/
├── Geneformer/              # upstream source and pretrained models
└── my-geneformer-analysis/  # scripts, notebooks, data, results, uv.lock
```

Geneformer is installed into the analysis environment as an editable relative
path dependency. This lets the analysis record an exact Geneformer commit
without copying the upstream repository into every project.

## Official references

- [Geneformer repository and model files](https://huggingface.co/ctheodoris/Geneformer)
- [Geneformer getting-started documentation](https://geneformer.readthedocs.io/en/latest/getstarted.html)
- [uv installation](https://docs.astral.sh/uv/getting-started/installation/)
- [uv project workflow](https://docs.astral.sh/uv/guides/projects/)
- [uv locking and syncing](https://docs.astral.sh/uv/concepts/projects/sync/)

The official Geneformer installation requires Git LFS, clones the Hugging Face
repository, and installs its Python package. The helpers here express the same
workflow as a reproducible `uv` project.

## 1. System prerequisites

Install:

- Git and Git LFS;
- a supported NVIDIA driver when GPU acceleration is required;
- common build tools and system libraries required by scientific Python; and
- `uv`.

On Ubuntu/Debian, a typical starting point is:

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential git git-lfs libhdf5-dev pkg-config

git lfs install
```

Install `uv` using an official method. For example:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv --version
```

Review installation scripts before executing them and use an OS package or
managed installation method when required by local policy.

## 2. Choose a PyTorch profile

The bootstrap accepts one of three profiles:

| Profile | Use when | PyTorch source |
|---|---|---|
| `default` | Let normal PyPI/platform resolution choose | PyPI |
| `cpu` | No supported NVIDIA GPU is available | Official PyTorch CPU index |
| `cu130` | NVIDIA driver supports CUDA 13.0 wheels | Official PyTorch CUDA 13.0 index |

The `cu130` profile is validated on the current NVIDIA GB10 machine. It is not
automatically correct for every NVIDIA system. Confirm driver and wheel
compatibility before selecting it.

## 3. Create a workspace and analysis project

From this repository:

```bash
geneformer_uv_setup/scripts/bootstrap_workspace.sh \
  /path/to/workspace \
  my-geneformer-analysis \
  default
```

For the known CUDA 13.0 profile and a pinned upstream commit:

```bash
geneformer_uv_setup/scripts/bootstrap_workspace.sh \
  /path/to/workspace \
  my-geneformer-analysis \
  cu130 \
  f45a6c7
```

The script:

1. verifies `git`, `git-lfs`, and `uv`;
2. clones Geneformer with Git LFS if it is absent;
3. optionally checks out the requested Geneformer ref on a fresh clone;
4. refuses to overwrite an existing analysis directory;
5. copies the selected project template;
6. records the exact Geneformer commit;
7. creates `uv.lock` and `.venv`;
8. installs Geneformer editable through `../Geneformer`; and
9. runs the environment smoke test.

If an existing Geneformer checkout is present at a different commit, the
bootstrap exits instead of changing it. Use a separate workspace or resolve
the checkout intentionally. It also rejects tracked source modifications and a
local `pyproject.toml` whose package name is not `geneformer`; either condition
would prevent the recorded upstream commit from fully describing the installed
code. A fresh upstream clone is the safest resolution.

## 4. Work in the environment

```bash
cd /path/to/workspace/my-geneformer-analysis

uv run python scripts/smoke_test.py --geneformer-root ../Geneformer
uv run jupyter lab
uv run python scripts/analysis.py
```

`uv run` checks that the environment matches the project. Direct activation is
also possible:

```bash
uv sync --locked
. .venv/bin/activate
python scripts/analysis.py
```

Commit these files in the analysis repository:

```text
pyproject.toml
uv.lock
.python-version
.geneformer-commit
scripts/
notebooks/
configs/
README.md
```

Do not commit `.venv/`, private datasets, credentials, or large generated model
checkpoints unless an appropriate artifact system is used.

## 5. Reproduce on another machine

Clone the analysis repository beside a Geneformer checkout at the commit in
`.geneformer-commit`, then run:

```bash
uv sync --frozen
uv run --frozen python scripts/smoke_test.py --geneformer-root ../Geneformer
```

`uv.lock` records exact resolved packages. The Geneformer commit file records
the external source revision that the relative dependency must use.

## 6. Add or update dependencies

Use `uv`, then commit both project files:

```bash
uv add package-name
git add pyproject.toml uv.lock
```

Inspect planned updates before accepting them:

```bash
uv lock --check
uv tree
```

Avoid editing `uv.lock` manually. Create a new branch when upgrading
Geneformer, PyTorch, Transformers, CUDA profiles, or core single-cell packages,
then rerun the smoke and a small scientific regression test.

## 7. Prepare data for Geneformer

Before a full analysis, explicitly document:

- raw-count source and whether counts are stored in `X` or a layer;
- human Ensembl gene identifiers and identifier version handling;
- cell and donor identifiers;
- required phenotype or classification labels;
- donor-disjoint train/evaluation/test splitting when supervised learning is
  used;
- the chosen Geneformer model version and vocabulary; and
- filtering, normalization, tokenization, and random-seed settings.

Keep source data outside Git. Store only small manifests, checksums, schemas,
and configuration files needed to locate and validate it.

## 8. Minimum validation before a real run

- `scripts/smoke_test.py` passes.
- CUDA availability and GPU name match expectations, or CPU use is intentional.
- The selected model contains its configuration and weight files.
- A tiny tokenization example completes.
- A tiny embedding or forward-pass example completes.
- Donor leakage checks pass before fine-tuning.
- A restart/checkpoint test succeeds before launching a long perturbation.
- Environment report and data/model checksums are saved with the analysis.

Geneformer’s official documentation notes that GPUs are needed for efficient
use and that fine-tuning hyperparameters should be tuned for each downstream
task; there is no universally appropriate fine-tuning configuration.
