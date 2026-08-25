# Relationship To KD

`KD` is the local data and generated-artifact workspace for this repository's
integrative SCLC+NSCLC epithelial/TME Geneformer workflow. This repository
contains version-controlled methods, validation, reporting, and migration
tools; it reads selected KD datasets, model checkpoints, statistics, and
perturbation outputs.

The large files this repo owns are intentionally outside Git in:

```text
/home/thinkstation2/workspace/KD/epithelial_tme/
```

This repo's atlas sources live in two places, one already on the compute host,
one not yet downloaded:

- The **NSCLC atlas** (full atlas, includes malignant/epithelial cells and the
  whole TME) is already present at
  `/home/kaisar/workspace/geneformer-uv-starter/geneformer-workspace/analysis/data/nsclc/nsclc_integrated.h5ad`
  -- **not** under `KD/`, and **not** at the path
  `geneformer-nsclc-tcell`'s own docs claim (`~/workspace/KD/data/nsclc/nsclc_integrated.h5ad`,
  which does not resolve on `thinkstation2` as of this repo's data audit). See
  `tools/lab_env.sh`'s `NSCLC_ATLAS_H5AD` default.
- The **SCLC epithelial compartment datasets** ("Epithelial cells," "SCLC
  epithelial cells," from CELLxGENE collection `62e8f058-9c37-48bc-9200-e767f318a8ec`)
  were downloaded into `KD/epithelial_tme/data/sclc_cellxgene/` by
  `epithelial_tme_validation/audit/` -- they were not already present locally
  (only the T-cell compartment had been downloaded, by the sibling SCLC repo).
- The **unified cancer-cell dataset** `data_harmonization/` builds from the
  two sources above lives at
  `KD/epithelial_tme/data_harmonization/unified_cancer_luad_lusc_sclc_normal.h5ad`
  (3.4 GB).

The other two repos in this line of work own their own `KD/` subtrees:

- [`geneformer-sclc-tcell`](https://github.com/Kays3/geneformer-sclc-tcell) --
  `KD/sclc_luad_normal_htan_*` (T-cell classifier + perturbation).
- [`geneformer-nsclc-tcell`](https://github.com/Kays3/geneformer-nsclc-tcell) --
  `KD/tcell_luad_lusc_normal_*` (T-cell classifier + perturbation).

Keep the KD directory layout stable unless all workflow scripts and path
configuration are updated together.
