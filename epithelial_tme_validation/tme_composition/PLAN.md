# Plan — tumor microenvironment (TME) composition and perturbation

**Status: planned, not run.** Phase 3 of this repo -- comes after
`classifier_workflow/` (Phase 2) establishes a working cancer-cell classifier.
Nothing in this directory has been executed; no TME data has even been
downloaded yet (see "Data not yet acquired" below).

Seeded from a real, well-designed but never-executed experimental plan found
in `GENEFORMER_NSCLC_START/geneformer_sclc/exploration.txt` and
`dataset preparation.txt` (LLM-brainstormed planning notes, not migrated into
`archive/` since they were never run at all, not even partially -- unlike the
V1 epithelial classifier). Adapted here to the compartments and datasets this
repo's audit already identified.

## 1. Biological question

Can in silico deletion/overexpression of immune-checkpoint,
antigen-presentation, and myeloid-suppression genes shift tumor/TME cell
states toward a more immune-permissive or immune-resistant configuration --
and does this differ between SCLC (clinically immune-cold) and NSCLC?

## 2. Compartments and gene panels (from the original design notes)

Four compartments, each with its own candidate gene panel:

| Compartment | Genes |
|---|---|
| Tumor-intrinsic | `DLL3`, `ASCL1`, `NEUROD1`, `POU2F3`, `YAP1`, `MYC`, `MYCL`, `BCL2` |
| Antigen presentation / IFN response | `B2M`, `HLA-A`, `HLA-B`, `HLA-C`, `TAP1`, `TAP2`, `JAK1`, `JAK2`, `STAT1`, `IRF1` |
| Immune checkpoints | `CD274`, `PDCD1LG2`, `PDCD1`, `CTLA4`, `LAG3`, `HAVCR2`, `TIGIT`, `CD47`, `VSIR` |
| Myeloid/TME suppression | `LGALS9`, `TGFB1`, `IL10`, `CSF1R`, `SPP1`, `MRC1`, `ARG1`, `CXCL8`, `CCL2` |
| T-cell cytotoxic/exhaustion | `GZMB`, `PRF1`, `IFNG`, `TOX`, `CXCL13`, `ENTPD1`, `MKI67` |

The tumor-intrinsic and T-cell panels substantially overlap with work already
done elsewhere (the tumor panel with `classifier_workflow/`'s own classes;
the T-cell panel with `geneformer-sclc-tcell`'s `immune_axis_test/`, which
already found this exact 7-gene-style exhaustion program does **not** behave
as a single coherent axis -- read that work before assuming these T-cell
genes will behave simply here either). **The myeloid/TME-suppression arm is
the genuinely open territory** -- it was never run anywhere in this project
family.

## 3. Data not yet acquired

The original design's three compartments (tumor/myeloid/T-cell) map to
CELLxGENE datasets this repo's audit already catalogued but did **not**
download (out of scope for Phase 1/2's cancer-cell focus):

| CZI dataset | Cells | Diseases |
|---|---:|---|
| Myeloid cells | 14,072 | LUAD/SCLC/normal |
| Mesenchymal cells | 8,030 | LUAD/SCLC/normal (stromal/fibroblast proxy) |
| Immune cells | 73,047 | LUAD/SCLC/normal |

For NSCLC, the atlas already downloaded for `classifier_workflow/` (see
`RELATIONSHIP_TO_KD.md`) already contains matching TME populations directly
(`cell_type_predicted`: `Macrophage` 211,525, `Fibroblast` 19,756,
`Endothelial cell` 38,825, etc.) -- no new NSCLC-side download needed, same
situation as the cancer-cell work.

## 4. Experiment design (adapted from the original notes)

Three separate perturbation runs, not one all-cell run (per the original
design's own reasoning: cell-type-specific responses are the point, and
mixing compartments into one run would blur exactly the comparison that
matters):

- **Tumor-only**: perturb `DLL3, ASCL1, NEUROD1, MYC, B2M, CD274` (subset of
  the tumor-intrinsic + antigen-presentation panels). Endpoint: shift toward
  immune-visible/immune-hot embedding.
- **Myeloid-only**: perturb `CSF1R, SPP1, MRC1, LGALS9, TGFB1, IL10, CCL2,
  CXCL8`. Endpoint: loss of suppressive-macrophage embedding.
- **T-cell-only**: perturb `PDCD1, CTLA4, LAG3, HAVCR2, TIGIT, TOX, ENTPD1`.
  Endpoint: shift from exhausted toward cytotoxic. Cross-reference against
  `geneformer-sclc-tcell`'s `immune_axis_test/` findings before treating any
  single-gene shift here as confirmatory.

If no responder/non-responder or treatment metadata exists in the downloaded
compartment datasets (to be confirmed when they're pulled), use the
surrogate "immune-hot" / "immune-cold" scoring the original notes proposed:
immune-hot = `CD8A, CD8B, GZMB, PRF1, IFNG, CXCL9, CXCL10, HLA-A, HLA-B, B2M`;
immune-cold/suppressive = `MRC1, SPP1, TGFB1, IL10, VEGFA, CXCL8, LGALS9`.

## 5. Sequencing and open decisions

- Do not start until `classifier_workflow/` has a working, evaluated
  cancer-cell classifier -- this phase's tumor-compartment arm reuses that
  model rather than training a separate one.
- Same zero-shot-vs-fine-tuned decision noted in
  [`../classifier_workflow/PLAN.md`](../classifier_workflow/PLAN.md) applies
  here, and should be made once, consistently, for both phases.
- Data acquisition (downloading the three CZI compartment datasets above) is
  itself a discrete first step of this phase, done the same way
  `epithelial_tme_validation/audit/download_sclc_epithelial_datasets.py`
  did for the cancer-cell work -- not yet written.

## What this does not do

- Does not download any TME compartment data yet.
- Does not run any perturbation.
- Does not resolve the zero-shot-vs-fine-tuned question.
