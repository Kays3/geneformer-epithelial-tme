#!/usr/bin/env python3
"""Download the SCLC epithelial-compartment CELLxGENE datasets this repo needs.

The sibling geneformer-sclc-tcell repo already downloaded this collection's
"T cells" dataset; it never downloaded the epithelial ones, because it never
needed them. Dataset IDs and URLs below are read directly from that repo's
committed inventory (sclc_validation/audit/results/cellxgene_collection_inventory.csv),
collection 62e8f058-9c37-48bc-9200-e767f318a8ec (Chan et al. 2021 HTAN SCLC atlas).

Runs on the compute host (large files). Resumable: uses curl -C - so a
partial/interrupted download picks back up rather than restarting.
"""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
from pathlib import Path

OUT_DIR = Path(os.environ.get(
    "EPITHELIAL_TME_ROOT",
    Path.home() / "workspace/KD/epithelial_tme",
)) / "data" / "sclc_cellxgene"

DATASETS = {
    "epithelial_cells": {
        "title": "Epithelial cells",
        "url": "https://datasets.cellxgene.cziscience.com/cfbc234a-7812-4b82-af81-ec6df4b65e04.h5ad",
        "dataset_id": "a6858c10-c52a-4a1d-bc12-a90dbd51ca66",
        "expected_bytes": 3835314338,
        "cell_count": 64091,
        "diseases": ["lung adenocarcinoma", "normal", "small cell lung carcinoma"],
    },
    "sclc_epithelial_cells": {
        "title": "SCLC epithelial cells",
        "url": "https://datasets.cellxgene.cziscience.com/0e55369f-8a0d-4897-b6fb-b09e817c72ba.h5ad",
        "dataset_id": "34deb33b-a50e-4993-a38b-1c0e5079c1c2",
        "expected_bytes": 8952427790,
        "cell_count": 54313,
        "diseases": ["small cell lung carcinoma"],
    },
}


def download(name: str, spec: dict) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    dest = OUT_DIR / f"{name}_{spec['dataset_id']}.h5ad"
    print(f"\n=== {spec['title']} -> {dest}")
    subprocess.run(
        ["curl", "-fL", "-C", "-", "--retry", "5", "--retry-delay", "10",
         "-o", str(dest), spec["url"]],
        check=True,
    )
    actual = dest.stat().st_size
    if actual != spec["expected_bytes"]:
        raise SystemExit(
            f"Size mismatch for {name}: expected {spec['expected_bytes']:,}, got {actual:,}"
        )
    print(f"OK: {actual:,} bytes")
    return dest


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(64 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    manifest = {}
    for name, spec in DATASETS.items():
        path = download(name, spec)
        manifest[name] = {**spec, "local_path": str(path), "sha256": sha256(path)}
        print(f"sha256: {manifest[name]['sha256']}")

    manifest_path = OUT_DIR / "download_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"\nWrote {manifest_path}")


if __name__ == "__main__":
    main()
