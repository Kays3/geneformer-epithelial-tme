# Streamlined Geneformer Workflow for SCLC

This project now has a repeatable runner for the analysis that was previously spread across exploratory notebooks.

## Presets

- `configs/sclc_tcell.json`: SCLC-focused lung T-cell disease model. Default perturbation asks which gene deletions shift SCLC T cells toward normal, with LUAD as the alternate disease state.
- `configs/sclc_epithelial_transition.json`: epithelial LUAD/SCLC model. Default perturbation asks which overexpressed genes shift LUAD epithelial cells toward SCLC.

## Run Order

Use one step at a time for long Geneformer jobs:

```bash
python scripts/sclc_geneformer_pipeline.py --config configs/sclc_tcell.json --step prepare
python scripts/sclc_geneformer_pipeline.py --config configs/sclc_tcell.json --step tokenize
python scripts/sclc_geneformer_pipeline.py --config configs/sclc_tcell.json --step split
python scripts/sclc_geneformer_pipeline.py --config configs/sclc_tcell.json --step prepare-classifier
python scripts/sclc_geneformer_pipeline.py --config configs/sclc_tcell.json --step train
python scripts/sclc_geneformer_pipeline.py --config configs/sclc_tcell.json --step evaluate
python scripts/sclc_geneformer_pipeline.py --config configs/sclc_tcell.json --step embeddings
python scripts/sclc_geneformer_pipeline.py --config configs/sclc_tcell.json --step perturb
python scripts/sclc_geneformer_pipeline.py --config configs/sclc_tcell.json --step plot-perturbation
```

Or run the full workflow:

```bash
python scripts/sclc_geneformer_pipeline.py --config configs/sclc_tcell.json --step all
```

## Outputs

Each preset writes into `runs/<run_name>/`:

- `cohort_summary.csv`: disease-level cell and donor counts.
- `input_h5ad/`: filtered AnnData object.
- `tokenized/`: Geneformer tokenized dataset.
- `splits/`: train/eval/test donor tables and donor overlap checks.
- `model/`: prepared datasets, fine-tuned model output, validation/test metrics.
- `embeddings/`: extracted cell and state embeddings.
- `perturb/`: raw in silico perturbation output.
- `perturb_stats/`: ranked perturbation statistics and top genes.
- `plots/`: confusion matrix, prediction plots, embeddings, perturbation plot.

## Donor Leakage Guardrail

The old notebooks used `drop_duplicates()` on `donor_id` and `disease`, which can let the same donor ID appear in more than one split when a donor has multiple disease labels.

The new runner:

1. builds one donor table before splitting;
2. writes multi-label donors to `splits/ambiguous_donors.csv`;
3. drops ambiguous donors by default;
4. asserts that train, eval, and test donor IDs have zero overlap.

Set `"ambiguous_donor_policy": "fail"` in a config if you prefer the run to stop whenever ambiguous donor IDs are detected.

## How This Maps to the Existing Notebooks

- `example_t.ipynb` and `example_t_commented.ipynb` map to `configs/sclc_tcell.json`.
- `example_epithelial.ipynb` maps to `configs/sclc_epithelial_transition.json`.

The notebooks remain useful for exploration and interpretation. The script is meant for reruns, strict splitting, cleaner output folders, and SCLC-centered perturbation.
