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

## 6. ISP screen — zero-shot vs. fine-tuned: decided

**Decision: fine-tuned is primary; zero-shot is a secondary, orthogonal
validation check on top hits, not a competing primary method.**

**Why.** `InSilicoPerturber`'s goal-state-shift mode measures movement toward
class centroids -- that is only a meaningful signal if the embedding space
already organizes cells along those classes. A pretrained (zero-shot) model
has no guarantee of that; it was never asked to separate LUAD/LUSC/SCLC/
normal specifically. Fine-tuning creates that structure by construction,
which is exactly why every prior ISP screen in this project family (both
T-cell repos, the archived V1 epithelial classifier) used it, and why it
should again here. The usual worry about fine-tuned ISP -- that a shift
reflects something the classifier learned as a shortcut rather than real
biology -- is not a blind spot in this design: it is precisely what this
family's existing housekeeping-gene, donor-consistency, and
ambient-contamination review methodology (`geneformer-sclc-tcell`'s HK-gene
review, `primary_test_perturbation`'s donor-consistency checks) already
exists to catch, and that methodology carries over unchanged.

Zero-shot's genuine value is as an **independent cross-check**, the same role
`geneformer-sclc-tcell`'s spatial (Visium) validation plays for its ISP
hits: if a fine-tuned-model hit's shift direction is *also* detectable, even
weakly, in the pretrained embedding, that is evidence the classifier learned
something real rather than a classifier-specific artifact. It is not run as
a full parallel genome-wide screen -- only as a check on whatever the
fine-tuned screen's top hits turn out to be.

### Pilot test (designed, not run) to confirm this empirically before the full screen

Three small, cheap stages -- meant to catch a bad assumption before real GPU
time is spent on the full donor-disjoint fine-tune + genome-wide screen.

**Stage A -- zero-shot separability sanity check (cheapest, do first).**
Sample ~500 cells per disease state (2,000 total, simple per-class random
sample, not the full donor-disjoint machinery -- this is a diagnostic, not a
result), tokenize, extract CLS embeddings from the **pretrained** Geneformer
V2-104M with no fine-tuning. Fit a quick cross-validated linear probe
(logistic regression) on the frozen embeddings and report per-class
recall/macro-F1, plus silhouette score against `disease_state`. This answers
the single most decision-relevant empirical question directly: does the
pretrained embedding separate these four states *at all*? No fine-tuning, no
GPU training run -- one forward pass plus an `sklearn` fit.
- If separability is near chance: zero-shot has nothing to offer even as a
  validation signal -- drop it, go fine-tuned-only, note why in this file.
- If separability is real but weaker than what the fine-tuned classifier
  achieves (Stage B): confirms the "fine-tuned primary, zero-shot orthogonal
  check" design as planned.
- If zero-shot separability is surprisingly close to fine-tuned: worth
  reopening the primary-method question -- unexpected, but the test should
  be honest enough to catch it rather than assume the answer.

**Stage B -- same metric, folded into the real fine-tune (no separate
throwaway model).** Once section 4/5's actual fine-tuned classifier exists,
compute the identical silhouette-score/embedding-separability metric on its
held-out test embeddings and report it side-by-side with Stage A's number in
the held-out evaluation report (section 5). Deliberately not a separate pilot
fine-tune -- training a disposable model twice wastes real GPU time for no
extra information.

**Stage C -- small-panel ISP concordance test (the actual zero-shot-vs-
fine-tuned test for the ISP question specifically, not just classification).**
A tiny gene panel (~15-20 genes with strong prior expectation from the V1
work and this repo's own data -- e.g. `ASCL1`, `NEUROD1`, `DLL3`, `MYC`,
`POU2F3`, `B2M`, `CD274` -- not the full genome), ~200-500 cells per source
disease state (small, not the full held-out population). Run
`InSilicoPerturber` in **both** modes (pretrained/zero-shot and the Stage B
fine-tuned model) on this same small panel and cell subset, and compare
shift direction and relative magnitude per gene between the two. This is the
apples-to-apples check for the actual decision: do the two methods broadly
agree on direction for genes with strong priors? Reasonable agreement
supports using zero-shot as a lightweight cross-check on the full fine-tuned
screen's top hits later, the way this section already commits to; systematic
disagreement would be worth understanding before trusting either.

## What this does not do

- Does not run any of the above yet -- including the pilot (Stages A/B/C are
  designed here, not executed).
- Does not touch TME/non-cancer compartments -- see
  [`../tme_composition/PLAN.md`](../tme_composition/PLAN.md) (Phase 3).
