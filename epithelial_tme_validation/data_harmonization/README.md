# Data harmonization: unified cancer-cell dataset (LUAD/LUSC/SCLC/normal)

**Status: run.** Builds one donor-disjoint-ready, Geneformer-input dataset
spanning both atlases, for `classifier_workflow/`'s integrative cancer-cell
classifier and its downstream ISP screen.

Scope is **cancer cells**, not "epithelial cells" narrowly -- see
[`build_unified_cancer_dataset.py`](build_unified_cancer_dataset.py)'s module
docstring for why that distinction matters for the filter logic (lung
carcinomas are epithelial-derived, so the underlying populations are the
same either way, but the *filter* is driven by malignancy status, not by an
epithelial-ontology label list -- an important difference for the
SCLC-collection's "Epithelial cells" file, see below).

## What ran

```bash
python3 epithelial_tme_validation/data_harmonization/build_unified_cancer_dataset.py
```

On `thinkstation2`, against three source files (see `RELATIONSHIP_TO_KD.md`
for exact paths): the NSCLC atlas (892,296 cells, full atlas) and the two
CELLxGENE datasets `epithelial_tme_validation/audit/` downloaded
("Epithelial cells", "SCLC epithelial cells"). Runtime: under a minute once
the files are on local disk.

## Result

**181,398 cells x 25,544 genes, 279 unique donors** (`harmonized_donor_id`,
prefixed by source atlas so a coincidental id collision between the two
unrelated cohorts can never silently merge two different patients):

| Disease state | Cells | Source(s) |
|---|---:|---|
| LUAD | 60,062 | 56,941 NSCLC atlas + 3,121 SCLC-collection (its malignant bucket only) |
| LUSC | 24,291 | NSCLC atlas only (SCLC collection has no LUSC) |
| SCLC | 54,313 | SCLC-collection "SCLC epithelial cells" (used whole) |
| Normal | 42,732 | 41,974 NSCLC atlas + 758 SCLC-collection |

Output: `$EPITHELIAL_TME_ROOT/data_harmonization/unified_cancer_luad_lusc_sclc_normal.h5ad`
(3.4 GB, outside Git) and
[`results/unified_cancer_dataset_summary.csv`](results/unified_cancer_dataset_summary.csv)
(committed, the small rollup table above).

**177 of the 279 donors contribute cells to more than one disease state** --
expected, since a substantial share of patients in these atlases have both a
tumor sample and a matched-normal/adjacent-normal sample. This is not a bug;
it is exactly the kind of split hazard the sibling repos already handle for
their much smaller instances of the same pattern (`geneformer-sclc-tcell`'s
three dual-tissue donors). Here it's the majority case, not the exception --
**`classifier_workflow/`'s donor-disjoint split must keep every one of these
177 donors entirely on one side of train/eval/test**, not just check for it
as an edge case.

## Design decisions and why

- **Raw counts**: all three source files store normalized data in `.X` and
  integer raw counts in `.raw.X` (verified directly, not assumed --
  `.X` row `[0.858, 0, 0, ...]` vs `.raw.X` same row `[1, 0, 0, ...]`).
  The script reads `.raw.X` throughout.
- **NSCLC atlas filter** (`cell_type_tumor` column): LUAD = `Tumor cells LUAD`
  + its `mitotic`/`EMT`/`MSLN`/`NE` variants; LUSC = `Tumor cells LUSC` + its
  `mitotic` variant; normal = `disease=="normal"` restricted to
  `Alveolar cell type 1/2`, `transitional club/AT2`, `Ciliated`, `Club`.
  `Tumor cells NSCLC mixed` (470 LUAD-labeled + 1,701 LUSC-labeled cells) is
  deliberately excluded from both -- ambiguous cross-subtype identity.
- **SCLC-collection "Epithelial cells" file, LUAD/normal subsets**: this
  file's `cell_type` column is **not** just `"epithelial cell"` for
  LUAD/normal -- real, specific epithelial subtypes appear too (ionocyte,
  ciliated, goblet, club, basal, alveolar, neuroendocrine, plus
  `hepatocyte` as an evident contamination artifact). For the **LUAD cancer
  class**, only `cell_type=="epithelial cell"` is used (the curator's
  malignant/dedifferentiated bucket -- the same convention the dedicated
  SCLC-only file uses for its entire known-malignant population); the other
  labels are normal epithelium admixed in the tumor biopsy, not cancer cells,
  and are correctly excluded. For the **normal class**, by contrast, all
  genuine lung-epithelial ontology terms are included except `hepatocyte` --
  normal tissue diversity is wanted there, malignancy isn't the question.
- **Gene panels differ** (NSCLC atlas 17,764 genes vs. both SCLC files'
  24,540 genes, all three Ensembl-ID indexed): combined via
  `anndata.concat(..., join="outer")`, unioning the gene sets rather than
  intersecting. A gene absent from one atlas's whole panel is simply never
  "expressed" for that atlas's cells -- harmless for Geneformer's per-cell
  tokenization, which only encodes genes actually detected in a given cell.
  Result: 25,544 genes (a bit more than either individual panel).

## What this does not do

- Does not balance classes or decide train/eval/test splits -- that is
  `classifier_workflow/`'s job, working from this dataset plus the 177-donor
  cross-state list above.
- Does not tokenize for Geneformer -- a separate step in `classifier_workflow/`.
- Does not touch TME/non-cancer compartments (myeloid, mesenchymal, broader
  immune) -- that is `tme_composition/`'s scope (Phase 3).
