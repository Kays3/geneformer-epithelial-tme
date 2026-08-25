#!/usr/bin/env python3
"""Starting point for a Geneformer analysis."""

from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = PROJECT_ROOT / "data"
RESULTS_DIR = PROJECT_ROOT / "results"


def main() -> None:
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Project: {PROJECT_ROOT}")
    print(f"Data: {DATA_DIR}")
    print(f"Results: {RESULTS_DIR}")
    print("Add a documented tokenization, embedding, fine-tuning, or perturbation workflow here.")


if __name__ == "__main__":
    main()
