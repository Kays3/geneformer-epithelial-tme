# Geneformer analysis

This project uses an adjacent `../Geneformer` checkout as an editable `uv`
dependency. The exact upstream revision is recorded in `.geneformer-commit`.

## Quick start

```bash
uv sync --frozen
uv run --frozen python scripts/smoke_test.py --geneformer-root ../Geneformer
uv run --frozen jupyter lab
```

Place code in `scripts/`, notebooks in `notebooks/`, configuration in
`configs/`, and small reviewed tables or figures in `results/`. Private or
large inputs and outputs are ignored by default.
