#!/usr/bin/env python3
"""Validate a general Geneformer analysis environment."""

from __future__ import annotations

import argparse
import json
import platform
import subprocess
import sys
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path


PACKAGES = (
    "anndata",
    "datasets",
    "geneformer",
    "numpy",
    "pandas",
    "scanpy",
    "torch",
    "transformers",
)


def package_versions() -> dict[str, str]:
    result = {}
    for package in PACKAGES:
        try:
            result[package] = version(package)
        except PackageNotFoundError:
            result[package] = "not-installed-as-distribution"
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--geneformer-root", type=Path, required=True)
    parser.add_argument("--json", type=Path, help="Optional environment report output")
    args = parser.parse_args()

    geneformer_root = args.geneformer_root.resolve()
    if not (geneformer_root / ".git").is_dir():
        raise SystemExit(f"Not a Geneformer checkout: {geneformer_root}")
    sys.path.insert(0, str(geneformer_root))

    import anndata  # noqa: F401
    import datasets  # noqa: F401
    import geneformer  # noqa: F401
    import scanpy  # noqa: F401
    import torch
    import transformers  # noqa: F401

    commit = subprocess.run(
        ["git", "-C", str(geneformer_root), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    model_dirs = sorted(
        path.name
        for path in geneformer_root.glob("Geneformer-*")
        if path.is_dir() and (path / "config.json").is_file()
    )
    report = {
        "python": sys.version.replace("\n", " "),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "geneformer_root": str(geneformer_root),
        "geneformer_commit": commit,
        "model_directories": model_dirs,
        "packages": package_versions(),
        "torch_cuda_version": torch.version.cuda,
        "cuda_available": torch.cuda.is_available(),
        "gpu": torch.cuda.get_device_name(0) if torch.cuda.is_available() else None,
    }
    print(json.dumps(report, indent=2))
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2) + "\n")

    if not model_dirs:
        print("WARNING: no Geneformer model directory with config.json was found.")
    print("Geneformer environment smoke test passed")


if __name__ == "__main__":
    main()
