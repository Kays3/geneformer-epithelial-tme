# Plan — integrative cancer-cell classifier + ISP screen

**Status: planned, not run.** This documents the design so it can be reviewed
before any GPU time is spent. Nothing in this directory has been executed.

## Input

[`../data_harmonization/unified_cancer_luad_lusc_sclc_normal.h5ad`](../data_harmonization/README.md):
181,398 cells x 25,544 genes, four disease states (LUAD 60,062 / LUSC 24,291 /
SCLC 54,313 / normal 42,732), 279 unique donors (`harmonized_donor_id`,
source-atlas-prefixed).

## 1. Donor-disjoint split — the hard part here

**177 of the 279 donors contribute cells to more than one disease state**
(most commonly: a tumor sample and a matched-normal/adjacent-normal sample
from the same patient). This is the majority pattern here, not an edge case,
unlike every prior split in the sibling repos where at most a handful of
donors needed this handling.

Design: split on `harmonized_donor_id` as the unit (never on cells), so a
donor with e.g. both LUAD and normal cells lands entirely in one of
train/eval/test -- all their cells, across every disease state they
contributed to, move together. This means a train/eval/test split is not
independently balanceable per class in the usual way; the split algorithm
needs to account for each donor's full multi-class cell-count profile when
assigning donors to splits, not just count cells per class after the fact.
Verification: an explicit assertion, mirroring the pattern in every sibling
repo's `METHODS.md`, that no `harmonized_donor_id` appears in more than one
of train/eval/test.

## 2. Class balance

Current sizes are close enough that they may not need capping (60k/24k/54k/43k
-- roughly 2.5x between largest and smallest, much better than the earlier
T-cell work's need for aggressive oversampling/capping). Decide after seeing
what the donor-disjoint split actually yields per class in each split, not
before -- capping too early could waste real signal if the split turns out
naturally balanced once donor constraints are applied.

## 3. Tokenization

Geneformer V2 tokenizer (`GENEFORMER_TOKEN_DICT` per `tools/lab_env.sh`),
`custom_attr_name_dict` carrying at minimum `harmonized_donor_id`,
`disease_state`, `source_atlas`, `source_cell_type`, `split`. Raw counts are
already in `.X` post-harmonization (see `data_harmonization/README.md`'s raw
counts note) -- no further conversion needed.

## 4. Fine-tuning

Geneformer V2-104M `CellClassifier`, 4-class (LUAD/LUSC/SCLC/normal),
following the same training-args conventions the sibling repos already use
(donor-disjoint split assigned before any tokenization/oversampling step,
training-cells-only reference centroids for the later ISP screen). Track
`source_atlas` as a covariate to check for batch/technical confounding
between the two atlases -- report classifier performance broken down by
source_atlas as well as pooled, not pooled only, given the LUAD and normal
classes are themselves mixtures of both atlases.

## 5. Held-out evaluation

Standard pattern from `current_workflow/METHODS.md` /
`sclc_validation/perturbation_workflow/METHODS.md`: accuracy, macro-F1, and a
confusion matrix on the held-out test donors, reported both pooled and split
by `source_atlas` (per point 4).

## 6. ISP screen — open decision before this runs

**Zero-shot vs. fine-tuned Geneformer**, see the top-level session plan notes
for the full trade-off writeup. Every prior ISP screen in this family
(T-cell work in both siblings, the archived V1 epithelial classifier) used
the fine-tuned-model approach; this repo's cross-atlas design is a good
occasion to also run the zero-shot variant and compare, rather than
defaulting silently. **Decide and record the choice here before running
anything**, with the reasoning, not just the result.

Once decided: genome-wide or targeted-panel deletion/overexpression (design
mirrors the sibling repos' `perturbation_workflow/`), directional comparisons
among the four disease states (up to 12 directed pairs for 4 classes, likely
prioritized rather than all-12 -- e.g. LUAD<->LUSC<->SCLC<->normal along the
axes most clinically relevant first).

## What this does not do

- Does not run any of the above yet.
- Does not decide the zero-shot-vs-fine-tuned question (see point 6).
- Does not touch TME/non-cancer compartments -- see
  [`../tme_composition/PLAN.md`](../tme_composition/PLAN.md) (Phase 3).
