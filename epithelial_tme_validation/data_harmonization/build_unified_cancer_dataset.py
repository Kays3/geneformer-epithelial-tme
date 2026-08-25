#!/usr/bin/env python3
"""Build one donor-disjoint, Geneformer-ready dataset unifying cancer (tumor)
cells across the NSCLC and SCLC atlases, plus matched normal epithelium.

Scope is CANCER CELLS, not "epithelial cells" narrowly -- lung carcinomas are
epithelial-derived, so the underlying populations are the same, but the
filters below are driven by malignancy status (cell_type_tumor's "Tumor
cells *" labels; the SCLC-collection's malignant "epithelial cell" bucket),
not by an epithelial-ontology label list. A cell bearing a non-epithelial
ontology term but a genuine malignant call would still be included if this
data had one; it doesn't (no such population exists in either atlas), so in
practice every included cancer cell also carries an epithelial identity --
that is a fact about lung cancer biology, not a scope restriction applied
here.

Four sources, three raw files:
  1. NSCLC atlas (NSCLC_ATLAS_H5AD) -- LUAD and LUSC cancer cells, plus
     normal epithelium, via cell_type_tumor.
  2. SCLC-collection "Epithelial cells" (LUAD/normal/SCLC diseases) --
     supplementary LUAD cancer cells (its malignant bucket only, see below)
     and supplementary normal epithelium.
  3. SCLC-collection "SCLC epithelial cells" (SCLC only) -- the SCLC cancer
     cell class, used whole; this file's own cell_type is uniformly
     "epithelial cell", i.e. entirely the malignant compartment already.

Raw counts note (verified by hand, not assumed): all three files store
normalized data in .X and integer raw counts in .raw.X. This script reads
.raw.X throughout -- Geneformer's tokenizer needs raw counts.

Donor-collision safety: every donor id is prefixed by source atlas
(nsclc:{id} / sclc_htan:{id}) before any downstream split logic can see it,
so a coincidental id collision between the two unrelated cohorts can never
silently merge two different real patients.

Runs on the compute host (large files, backed reads); needs no GPU.
"""
from __future__ import annotations

import os
from pathlib import Path

import anndata as ad
import numpy as np
import pandas as pd
import scipy.sparse as sp

NSCLC_ATLAS_H5AD = Path(os.environ.get(
    "NSCLC_ATLAS_H5AD",
    Path.home() / "workspace/geneformer-uv-starter/geneformer-workspace/analysis/data/nsclc/nsclc_integrated.h5ad",
))
EPITHELIAL_TME_ROOT = Path(os.environ.get(
    "EPITHELIAL_TME_ROOT",
    Path.home() / "workspace/KD/epithelial_tme",
))
SCLC_DATA_DIR = EPITHELIAL_TME_ROOT / "data" / "sclc_cellxgene"
SCLC_EPITHELIAL_ALL_DISEASE_H5AD = SCLC_DATA_DIR / "epithelial_cells_a6858c10-c52a-4a1d-bc12-a90dbd51ca66.h5ad"
SCLC_EPITHELIAL_SCLC_ONLY_H5AD = SCLC_DATA_DIR / "sclc_epithelial_cells_34deb33b-a50e-4993-a38b-1c0e5079c1c2.h5ad"
OUT_DIR = EPITHELIAL_TME_ROOT / "data_harmonization"

# NSCLC atlas: cell_type_tumor values that are genuinely malignant, per disease.
NSCLC_CANCER_LUAD = {
    "Tumor cells LUAD", "Tumor cells LUAD mitotic", "Tumor cells LUAD EMT",
    "Tumor cells LUAD MSLN", "Tumor cells LUAD NE",
}
NSCLC_CANCER_LUSC = {"Tumor cells LUSC", "Tumor cells LUSC mitotic"}
# "Tumor cells NSCLC mixed" (LUAD 470 / LUSC 1,701 cells) is deliberately
# excluded from both -- ambiguous cross-subtype identity, not a clean call
# for either class.
NSCLC_NORMAL_EPITHELIAL = {
    "Alveolar cell type 1", "Alveolar cell type 2", "transitional club/AT2",
    "Ciliated", "Club",
}

# SCLC-collection "Epithelial cells" file: cell_type=="epithelial cell" is
# the curator's malignant/dedifferentiated bucket (same convention the
# SCLC-only file uses for its entire, known-malignant population) -- the
# OTHER ontology labels present under disease==LUAD (ionocyte, pulmonary
# alveolar epithelial cell, basal cell, ciliated, goblet, club, tuft,
# neuroendocrine) are normal epithelium admixed in the tumor biopsy, not
# cancer cells, and are correctly excluded from the LUAD cancer class.
SCLC_COLLECTION_CANCER_CELL_TYPE = "epithelial cell"
# For the NORMAL class, by contrast, we want maximal genuine normal-tissue
# diversity, not just one label -- broaden to every real lung epithelial
# ontology term. "hepatocyte" is excluded explicitly: it appears at
# non-trivial counts (553 under LUAD, 85 under normal) and is almost
# certainly a contamination/mislabel artifact, not real lung tissue.
SCLC_COLLECTION_NORMAL_CELL_TYPES = {
    "epithelial cell", "pulmonary alveolar epithelial cell", "ionocyte",
    "goblet cell", "basal cell", "ciliated epithelial cell",
    "neuroendocrine cell", "club cell", "tuft cell",
}

DISEASE_LABEL = {
    "lung adenocarcinoma": "LUAD",
    "squamous cell lung carcinoma": "LUSC",
    "small cell lung carcinoma": "SCLC",
    "normal": "normal",
}


def raw_counts(sub: ad.AnnData) -> ad.AnnData:
    """Replace .X with .raw.X (raw integer counts), keeping .raw's var."""
    assert sub.raw is not None, "expected a .raw layer with raw counts"
    out = ad.AnnData(
        X=sub.raw.X.copy(),
        obs=sub.obs.copy(),
        var=sub.raw.var.copy(),
    )
    return out


def load_nsclc_cancer_and_normal() -> ad.AnnData:
    print(f"Loading NSCLC atlas: {NSCLC_ATLAS_H5AD}")
    a = ad.read_h5ad(NSCLC_ATLAS_H5AD, backed="r")

    luad_mask = a.obs["cell_type_tumor"].isin(NSCLC_CANCER_LUAD)
    lusc_mask = a.obs["cell_type_tumor"].isin(NSCLC_CANCER_LUSC)
    normal_mask = (a.obs["disease"] == "normal") & a.obs["cell_type_tumor"].isin(NSCLC_NORMAL_EPITHELIAL)
    keep = luad_mask | lusc_mask | normal_mask

    sub = a[keep].to_memory()
    sub = raw_counts(sub)
    sub.obs["disease_state"] = np.select(
        [luad_mask[keep], lusc_mask[keep]], ["LUAD", "LUSC"], default="normal",
    )
    sub.obs["harmonized_donor_id"] = "nsclc:" + sub.obs["donor_id"].astype(str)
    sub.obs["source_atlas"] = "nsclc_integrated"
    sub.obs["source_cell_type"] = sub.obs["cell_type_tumor"].astype(str)
    print(f"  kept {sub.n_obs} cells: "
          f"{(sub.obs['disease_state']=='LUAD').sum()} LUAD, "
          f"{(sub.obs['disease_state']=='LUSC').sum()} LUSC, "
          f"{(sub.obs['disease_state']=='normal').sum()} normal; "
          f"{sub.obs['harmonized_donor_id'].nunique()} donors")
    return sub


def load_sclc_collection_luad_and_normal() -> ad.AnnData:
    print(f"Loading SCLC-collection 'Epithelial cells': {SCLC_EPITHELIAL_ALL_DISEASE_H5AD}")
    a = ad.read_h5ad(SCLC_EPITHELIAL_ALL_DISEASE_H5AD, backed="r")

    luad_mask = (a.obs["disease"] == "lung adenocarcinoma") & (
        a.obs["cell_type"] == SCLC_COLLECTION_CANCER_CELL_TYPE
    )
    normal_mask = (a.obs["disease"] == "normal") & a.obs["cell_type"].isin(
        SCLC_COLLECTION_NORMAL_CELL_TYPES
    )
    keep = luad_mask | normal_mask

    sub = a[keep].to_memory()
    sub = raw_counts(sub)
    sub.obs["disease_state"] = np.where(luad_mask[keep], "LUAD", "normal")
    sub.obs["harmonized_donor_id"] = "sclc_htan:" + sub.obs["donor_id"].astype(str)
    sub.obs["source_atlas"] = "sclc_htan_epithelial_cells"
    sub.obs["source_cell_type"] = sub.obs["cell_type"].astype(str)
    print(f"  kept {sub.n_obs} cells: "
          f"{(sub.obs['disease_state']=='LUAD').sum()} LUAD (cancer-cell bucket only), "
          f"{(sub.obs['disease_state']=='normal').sum()} normal; "
          f"{sub.obs['harmonized_donor_id'].nunique()} donors")
    return sub


def load_sclc_cancer() -> ad.AnnData:
    print(f"Loading SCLC-collection 'SCLC epithelial cells': {SCLC_EPITHELIAL_SCLC_ONLY_H5AD}")
    a = ad.read_h5ad(SCLC_EPITHELIAL_SCLC_ONLY_H5AD, backed="r")
    assert (a.obs["cell_type"] == "epithelial cell").all(), (
        "expected this file's cell_type to be uniformly 'epithelial cell' "
        "(its entire malignant compartment) -- schema changed, re-check"
    )
    assert (a.obs["disease"] == "small cell lung carcinoma").all()

    sub = a.to_memory()
    sub = raw_counts(sub)
    sub.obs["disease_state"] = "SCLC"
    sub.obs["harmonized_donor_id"] = "sclc_htan:" + sub.obs["donor_id"].astype(str)
    sub.obs["source_atlas"] = "sclc_htan_sclc_epithelial_cells"
    sub.obs["source_cell_type"] = sub.obs["cell_type"].astype(str)
    print(f"  kept {sub.n_obs} cells (all SCLC cancer cells); "
          f"{sub.obs['harmonized_donor_id'].nunique()} donors")
    return sub


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    parts = [load_nsclc_cancer_and_normal(), load_sclc_collection_luad_and_normal(), load_sclc_cancer()]

    keep_cols = ["disease_state", "harmonized_donor_id", "source_atlas", "source_cell_type"]
    for p in parts:
        p.obs = p.obs[keep_cols].copy()

    print("\nConcatenating (outer join on genes -- unions the two gene panels, "
          "zero-fills the rest; a gene absent from one atlas's panel is simply "
          "never 'expressed' for that atlas's cells)...")
    combined = ad.concat(parts, join="outer", merge="same")
    combined.X = sp.csr_matrix(combined.X)
    combined.obs["n_counts"] = np.asarray(combined.X.sum(axis=1)).ravel()
    combined.obs_names_make_unique()

    print(f"\nCombined: {combined.n_obs} cells x {combined.n_vars} genes")
    print(combined.obs.groupby(["disease_state", "source_atlas"], observed=True).agg(
        n_cells=("harmonized_donor_id", "size"),
        n_donors=("harmonized_donor_id", "nunique"),
    ))
    donor_overlap = (
        combined.obs.groupby("harmonized_donor_id")["disease_state"].nunique()
    )
    cross_state_donors = donor_overlap[donor_overlap > 1]
    if len(cross_state_donors):
        print(f"\n{len(cross_state_donors)} donor(s) contribute cells to more than one "
              f"disease_state (expected for the small number of patients with both "
              f"tumor and matched-normal samples) -- classifier_workflow's split "
              f"must keep each such donor entirely on one side of train/eval/test.")

    out_path = OUT_DIR / "unified_cancer_luad_lusc_sclc_normal.h5ad"
    combined.write_h5ad(out_path)
    print(f"\nWrote {out_path}")

    summary = combined.obs.groupby(["disease_state", "source_atlas"], observed=True).size().reset_index(name="n_cells")
    summary_path = OUT_DIR / "unified_cancer_dataset_summary.csv"
    summary.to_csv(summary_path, index=False)
    print(f"Wrote {summary_path}")


if __name__ == "__main__":
    main()
