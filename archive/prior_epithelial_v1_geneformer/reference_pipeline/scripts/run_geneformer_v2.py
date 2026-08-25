#!/usr/bin/env python3
"""Simple Geneformer V2 runner for the SCLC workflow."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PIPELINE = REPO_ROOT / "scripts" / "sclc_geneformer_pipeline.py"


PRESETS = {
    "epithelial": REPO_ROOT / "configs" / "sclc_epithelial_transition.json",
    # The "tcell" preset (configs/sclc_tcell.json) was not migrated here -- that
    # line of work is superseded by geneformer-sclc-tcell/geneformer-nsclc-tcell,
    # which use donor-disjoint splits this V1 preset did not.
}


def write_v2_config(
    preset: str,
    model_dir: str,
    input_h5ad: str | None,
    output_root: str | None,
) -> Path:
    with open(PRESETS[preset]) as handle:
        config = json.load(handle)

    config["model_version"] = "V2"
    config["model_directory"] = model_dir
    config["run_name"] = f"{config['run_name']}_v2"
    if input_h5ad is not None:
        config["input_h5ad"] = input_h5ad
    if output_root is not None:
        config["output_root"] = output_root

    out_dir = REPO_ROOT / "runs" / "_generated_configs"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / f"{config['run_name']}.json"
    with open(out_file, "w") as handle:
        json.dump(config, handle, indent=2)
        handle.write("\n")
    return out_file


def run_step(config_file: Path, step: str) -> None:
    cmd = [
        sys.executable,
        str(PIPELINE),
        "--config",
        str(config_file),
        "--step",
        step,
    ]
    print("\nRunning:", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=REPO_ROOT, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run SCLC Geneformer analysis with Geneformer V2.")
    parser.add_argument(
        "--preset",
        choices=sorted(PRESETS),
        default="epithelial",
        help="Analysis preset to run.",
    )
    parser.add_argument(
        "--model-dir",
        default="../Geneformer-V2-104M",
        help="Path to the local Geneformer V2 model directory.",
    )
    parser.add_argument(
        "--input-h5ad",
        default=None,
        help="Optional path to the input .h5ad file.",
    )
    parser.add_argument(
        "--step",
        default="all",
        choices=[
            "prepare",
            "tokenize",
            "split",
            "prepare-classifier",
            "train",
            "evaluate",
            "embeddings",
            "perturb",
            "plot-perturbation",
            "all",
        ],
        help="Pipeline step to run.",
    )
    parser.add_argument(
        "--output-root",
        default=None,
        help="Optional output folder. Default is the pipeline's runs/ folder.",
    )
    args = parser.parse_args()

    config_file = write_v2_config(args.preset, args.model_dir, args.input_h5ad, args.output_root)
    print(f"Wrote V2 config: {config_file}")
    print(f"Preset: {args.preset}")
    if args.input_h5ad is not None:
        print(f"Input: {args.input_h5ad}")
    print(f"Model: {args.model_dir}")
    run_step(config_file, args.step)


if __name__ == "__main__":
    main()
