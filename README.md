# Geneformer epithelial/TME workflow (integrative SCLC + NSCLC)

For moving the active Geneformer experiment, trained model, perturbation
outputs, and reporting environment to another machine, see the
[reproducible migration workspace](migration/README.md).

For creating a project-agnostic Geneformer environment with `uv` on a clean
machine, see the [general Geneformer + uv setup](geneformer_uv_setup/README.md).

This repo is the third in a family split out of an earlier combined repo. The
other two are T-cell-focused and single-cancer-type:
[`geneformer-sclc-tcell`](https://github.com/Kays3/geneformer-sclc-tcell) and
[`geneformer-nsclc-tcell`](https://github.com/Kays3/geneformer-nsclc-tcell).
This repo is **integrative** (both SCLC and NSCLC together) and focused on a
different cell population: **cancer/tumor cells** broadly (lung carcinomas are
epithelial-derived, so in practice this means malignant epithelial cells --
but the filters are driven by malignancy status, not an "epithelial" ontology
label, see `epithelial_tme_validation/data_harmonization/README.md`) and the
**tumor microenvironment (TME)** -- myeloid, mesenchymal/stromal, and broader
immune composition beyond just T cells.

## Prior art this builds on

A real, executed Geneformer V1 epithelial classifier already exists (not in
this repo's history -- migrated in as archived provenance, see
[`archive/prior_epithelial_v1_geneformer/README.md`](archive/prior_epithelial_v1_geneformer/README.md)):
a donor-disjoint LUAD-vs-SCLC epithelial classifier reaching **0.951 accuracy /
0.941 macro-F1** on the same HTAN SCLC atlas the sibling SCLC repo uses, plus a
genome-wide overexpression perturbation screen. Its 3-class (+normal) variant
has a documented donor-leakage bug -- read as a baseline to reproduce properly
with donor-disjoint splits and Geneformer V2, not as a validated result.

## Data

- **NSCLC**: the full integrated NSCLC atlas (892,296 cells) already includes
  malignant/epithelial cells and the whole TME (fibroblasts, endothelial cells,
  myeloid, etc.) -- no new download needed, just a different cell-type filter
  than the sibling T-cell repo used. See [`RELATIONSHIP_TO_KD.md`](RELATIONSHIP_TO_KD.md)
  for its real path (the sibling NSCLC repo's docs have a stale path for this
  same file).
- **SCLC**: the sibling SCLC repo's local atlas copy is T-cell-only. This repo
  downloaded the CELLxGENE-curated **"Epithelial cells"** (64,091 cells,
  LUAD/SCLC/normal) and **"SCLC epithelial cells"** (54,313 cells, SCLC-only)
  datasets from the same HTAN collection directly -- see
  [`epithelial_tme_validation/audit/`](epithelial_tme_validation/audit/README.md).
- **Unified cancer-cell dataset**: both sources combined into one
  donor-disjoint-ready corpus -- 181,398 cells x 25,544 genes, 279 donors
  (LUAD/LUSC/SCLC/normal) -- see
  [`epithelial_tme_validation/data_harmonization/README.md`](epithelial_tme_validation/data_harmonization/README.md).

## Structure

```text
archive/prior_epithelial_v1_geneformer/   migrated V1 prior art (see above)
epithelial_tme_validation/
  audit/                                  data audit + downloads (run)
  data_harmonization/                     unified cancer-cell dataset (run)
  classifier_workflow/                    Phase 2: integrative cancer-cell
                                           classifier + ISP screen (PLAN.md,
                                           not yet run)
  tme_composition/                        Phase 3: myeloid/mesenchymal/immune
                                           TME exploration (PLAN.md, not yet run)
tools/, migration/, geneformer_uv_setup/  shared infra, same conventions as
                                           the sibling repos
```

## Status

Data audit and harmonization are **run** -- see their `README.md`s for real
numbers. The classifier and TME phases are designed (`PLAN.md` in each
directory) but **not yet executed** -- this is real GPU work for follow-up
sessions, and a zero-shot-vs-fine-tuned-Geneformer decision needs to be made
explicitly before either runs (see `classifier_workflow/PLAN.md`).

Large atlases, tokenized datasets, embeddings, checkpoints, and model weights
remain outside Git.
