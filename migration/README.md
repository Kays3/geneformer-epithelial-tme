# Reproducible machine migration

This directory migrates the active integrative SCLC+NSCLC epithelial/TME
Geneformer experiment and its report repository to another Linux machine. It
deliberately rebuilds Python instead of copying the existing virtual
environment, whose compiled packages and absolute symlinks are tied to the
source machine.

This repo is new (scaffolded from the `geneformer-sclc-tcell`/`geneformer-nsclc-tcell`
siblings' migration mechanics); the scope/checklist below will fill in as real
runs happen. Treat the specifics as TODO until then, same convention as
`migration/scripts/verify_target.py`'s placeholder constants.

## Pinned source state

- Monitor repository: current `main` branch of
  `https://github.com/Kays3/geneformer-epithelial-tme.git`.
- Geneformer upstream: `https://huggingface.co/ctheodoris/Geneformer`, commit
  `f45a6c7` (same pin as the sibling repos; update here if a run uses a
  different upstream commit).
- Python: 3.12.
- Environment manager: `uv`, using the transferred `pyproject.toml` and
  `uv.lock`.

The target may use a different CPU architecture or NVIDIA GPU, but its driver
and selected PyTorch wheel must be compatible. Never copy `.venv/`.

## Migration scopes

The default active-experiment scope (paths per `tools/lab_env.sh`'s
`EPITHELIAL_TME_ROOT` / `NSCLC_ATLAS_H5AD`):

```text
Geneformer-V2-104M/
KD/epithelial_tme/                 # unified epithelial dataset, fine-tune runs, ISP outputs
pyproject.toml
uv.lock
.python-version
```

`NSCLC_ATLAS_H5AD` (the full NSCLC atlas this repo reads epithelial/tumor cells
from) lives outside `KD/epithelial_tme/` -- see `RELATIONSHIP_TO_KD.md` for its
real path and why the sibling `geneformer-nsclc-tcell` repo's docs disagree
with it.

The complete source workspace contains unrelated experiments (the T-cell lines
of work in `KD/tcell_luad_lusc_normal_*` and `KD/sclc_luad_normal_htan_*`) and
is intentionally outside this migration scope.

## 1. Configure the source

Copy the example without committing the resulting local file:

```bash
cd /home/thinkstation2/workspace/geneformer-epithelial-tme
cp migration/migration.env.example migration/migration.env
```

Edit `migration/migration.env` for the source and target machines. The file is
ignored by Git because it may contain a private SSH hostname.

## 2. Inventory and checksum the source

```bash
set -a
. migration/migration.env
set +a

migration/scripts/inventory_source.sh \
  "$SOURCE_GF" \
  "$MIGRATION_INVENTORY_DIR"
```

The inventory records system/GPU information, Git state, installed Python
packages, sizes, and SHA-256 hashes.

## 3. Prepare clean repositories on the target

```bash
mkdir -p /home/thinkstation2/workspace
cd /home/thinkstation2/workspace

git clone https://github.com/Kays3/geneformer-epithelial-tme.git

git clone https://huggingface.co/ctheodoris/Geneformer
cd Geneformer
git checkout f45a6c7
```

## 4. Transfer active assets

```bash
set -a
. migration/migration.env
set +a

migration/scripts/transfer_active_assets.sh \
  "$SOURCE_GF" \
  "$TARGET_HOST" \
  "$TARGET_GF"
```

The transfer uses `rsync --partial` and never uses `--delete`.

## 5. Rebuild the environment on the target

```bash
cd /home/thinkstation2/workspace/geneformer-epithelial-tme

migration/scripts/bootstrap_target.sh \
  /home/thinkstation2/workspace
```

## 6. Verify files, results, and runtime

```bash
cd /home/thinkstation2/workspace/geneformer-epithelial-tme

migration/scripts/verify_target.py \
  --geneformer-root /home/thinkstation2/workspace \
  --monitor-root /home/thinkstation2/workspace/geneformer-epithelial-tme \
  --runtime
```

`CRITICAL_HASHES`/`EXPECTED_STATS_ROWS` in `verify_target.py` are still empty
placeholders (no fine-tune run or ISP screen has happened yet in this repo) --
those checks currently no-op with a `SKIP` message rather than asserting
anything false. Populate them once a real run exists.

## 7. Cutover checklist

- Source monitor repository is clean and pushed.
- Source inventory and checksum manifest are retained outside the source disk.
- Target Geneformer import and CUDA smoke checks pass.
- GitHub and Hugging Face authentication are configured independently.
- Source data is retained until at least one independent target backup exists.

Do not transfer SSH keys, GitHub credentials, Hugging Face tokens, or other
secrets with the experiment directories.
