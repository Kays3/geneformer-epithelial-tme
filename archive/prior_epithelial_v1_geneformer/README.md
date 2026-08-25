# Prior art: V1 Geneformer epithelial classifier (archived provenance)

This directory preserves real, executed work found in
`GENEFORMER_NSCLC_START/geneformer_sclc/HOANG_GENEFORMER_REPORT/` (a personal
scratch workspace, never in git) at the time this repo was created. It is
**not a validated result to build on unquestioned** -- read it as the baseline
this repo's own work supersedes, with its own caveats intact.

## What was actually run

Same source cohort as the sibling `geneformer-sclc-tcell` repo's atlas: the
Chan et al. 2021 HTAN SCLC atlas (CELLxGENE collection
`62e8f058-9c37-48bc-9200-e767f318a8ec`), 147,137 cells total, filtered here to
lung epithelial cells.

- **2-class (LUAD vs SCLC), 31,258 cells** (5,270 LUAD/16 donors, 25,988
  SCLC/9 donors): Geneformer **V1**, `CellClassifier`, 1 epoch, lr 1e-4, batch
  12, `freeze_layers=3`. **Validation accuracy 0.951, macro-F1 0.941** -- a
  much stronger disease-lineage signal than the T-cell work's classifier
  (0.661 accuracy / 0.499 macro-F1 in the same project, since superseded by
  `geneformer-sclc-tcell`/`geneformer-nsclc-tcell`'s properly donor-disjoint
  T-cell classifiers).
- **3-class (+normal), 32,109 cells**: 0.850 accuracy / 0.747 macro-F1.
  **This run has a documented donor-leakage bug** -- donors repeat across
  train/eval/test splits, so this number is not a clean held-out estimate.
  Do not cite it as validated; it is exactly the kind of split hygiene issue
  `sclc_geneformer_pipeline.py` (below) was written to fix, and that this
  repo's own `classifier_workflow/` must enforce from the start (see the
  donor-disjoint requirement in the root `CONTRIBUTING.md`).
- A genome-wide **in silico overexpression** screen (LUAD → SCLC goal-state
  shift, all genes, max 2,500 cells): 15,531 genes tested, 1,059 passed FDR <
  0.05 and > 100 detections. Top hits recorded in
  `reports/geneformer_epithelial_report_for_clinicians.txt` (positive shift:
  `SFTPC`, `TPT1`, `SLPI`, `PTMA`, `ACTB`; negative: `B2M`, `S100A9`, `FTH1`,
  `RALGAPA2`, `ITGB8`) -- explicitly flagged in that report as needing
  biological/housekeeping-gene filtering before trusting individual hits, the
  same caution the sibling repos' HK-gene review work applies.

## Contents

- `notebooks/` -- `example_epithelial.ipynb` (2-class, executed, real outputs)
  and `example_epithelial_commented_full.ipynb` (same analysis, narrated).
  `Integrated_Geneformer_Report_Notebook.ipynb` synthesizes this with the
  (separately superseded) T-cell analysis.
- `reports/` -- the clinician-facing writeup, the integrated
  epithelial+T-cell comparison (`integrated_geneformer_Tcell_epithelial_report.txt`,
  `Aplan_...txt` — a near-duplicate citing "Chan et al 2021" explicitly), a
  typeset LaTeX source (`geneformer_overleaf_report.tex`) and its two rendered
  PDFs.
- `figures/` -- the epithelial-analysis figures extracted from the notebooks
  (`epithelial_umap.pdf`, `epithelial_confusion_matrix.pdf`,
  `epithelial_perturbation_volcano.pdf`, `epithelial_perturbation_list.pdf`,
  plus the commented notebook's inline figures). T-cell-side figures from the
  same source directory were not migrated (superseded).
- `reference_pipeline/` -- `scripts/sclc_geneformer_pipeline.py` (536 lines): a
  solid, donor-leakage-aware **reimplementation** of the notebook workflow,
  written to fix exactly the 3-class leakage bug above, plus
  `scripts/run_geneformer_v2.py` (a thin preset runner) and
  `configs/sclc_epithelial_transition.json`. **This pipeline was never
  executed.** Its config's paths do not resolve as committed here:
  `input_h5ad` points at `../sclc_raw/5b7cbce2-....h5ad` (the actual file was
  one level up, in a differently-named `rawdata/` folder) and
  `model_directory` points at a V1 model this repo won't use (this repo
  targets Geneformer V2, per the config's own `model_version` field, which
  `run_geneformer_v2.py` already overrides at runtime). Treat this as a
  well-designed starting point for `classifier_workflow/`'s actual scripts,
  not as runnable code -- paths need fixing, and it should be adapted for the
  integrative (NSCLC + SCLC) scope this repo actually targets, not SCLC-only.

## What was not migrated

- `example_t.ipynb` / `example_t_commented.ipynb` and
  `geneformer_tcell_report_for_clinicians.txt` -- the T-cell side of the same
  project, already superseded by `geneformer-sclc-tcell`/`geneformer-nsclc-tcell`'s
  properly donor-disjoint T-cell work.
- `configs/sclc_tcell.json` -- the T-cell preset config, same reason.
- `dgx_spark_geneformer_analysis/` -- an unexecuted V2 packaging attempt (empty
  data/model placeholders, no real run). Its shape (`run_v2_epithelial.sh`
  launcher pattern) is worth knowing about but there was nothing to migrate.

The source files remain, untouched, in
`GENEFORMER_NSCLC_START/geneformer_sclc/HOANG_GENEFORMER_REPORT/` on the
laptop -- this is a copy, not a move.
