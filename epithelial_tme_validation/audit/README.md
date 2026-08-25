# Data audit: cancer-cell + normal-epithelium source availability

**Status: run.** Confirms and acquires the source data
`data_harmonization/` needs.

## What ran

- **NSCLC atlas**: already present on `thinkstation2`, confirmed via direct
  read (892,296 cells, 17,764 genes) at
  `~/workspace/geneformer-uv-starter/geneformer-workspace/analysis/data/nsclc/nsclc_integrated.h5ad`
  -- **not** the path `geneformer-nsclc-tcell`'s own docs claim
  (`~/workspace/KD/data/nsclc/nsclc_integrated.h5ad`, which does not resolve).
  See `RELATIONSHIP_TO_KD.md`.
- **SCLC epithelial-compartment datasets**: not previously downloaded (the
  sibling `geneformer-sclc-tcell` repo only ever needed the "T cells"
  compartment from this same CELLxGENE collection). Downloaded fresh:

```bash
python3 epithelial_tme_validation/audit/download_sclc_epithelial_datasets.py
```

| Dataset | Cells | Diseases | Size | SHA-256 verified |
|---|---:|---|---:|---|
| Epithelial cells | 64,091 | LUAD/SCLC/normal | 3.83 GB | yes |
| SCLC epithelial cells | 54,313 | SCLC only | 8.95 GB | yes |

Both downloaded to `$EPITHELIAL_TME_ROOT/data/sclc_cellxgene/`, from CELLxGENE
collection `62e8f058-9c37-48bc-9200-e767f318a8ec` (Chan et al. 2021 HTAN SCLC
atlas -- the same collection `geneformer-sclc-tcell` uses, dataset IDs and
URLs read directly from that repo's committed
`sclc_validation/audit/results/cellxgene_collection_inventory.csv`). A
per-file manifest with checksums is written alongside the downloads
(`download_manifest.json`, outside Git -- large-file convention).

Not downloaded (out of scope for the cancer-cell focus; would matter for
`tme_composition/`'s Phase 3): "Myeloid cells", "Mesenchymal cells",
"Immune cells" from the same collection.

## Feeds into

[`../data_harmonization/`](../data_harmonization/README.md), which reads
these two files plus the NSCLC atlas directly.
