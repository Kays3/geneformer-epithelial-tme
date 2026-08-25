# Contributing to the Geneformer lung T-cell workflow

Thank you for helping improve this research workflow. Contributions are welcome for analysis code, validation checks, documentation, reproducibility tooling, and small review-ready outputs.

## Before you start

- Open an issue for a substantial change so the scientific question, expected inputs and outputs, and validation plan can be agreed before implementation.
- Do not commit patient-level data, controlled-access data, credentials, model weights, virtual environments, or large generated artifacts.
- Keep large inputs and outputs outside Git. Commit only the small manifests, checksums, schemas, configuration files, summary tables, and figures needed to review and reproduce the work.
- Preserve donor-disjoint train, evaluation, and test splits. Any change to cohort selection or split assignment must include an explicit donor-leakage check.

## Set up a development environment

For a clean, project-agnostic Geneformer installation, follow [`geneformer_uv_setup/README.md`](geneformer_uv_setup/README.md). The setup records the upstream Geneformer commit and uses a locked `uv` environment.

For migration or recovery of the active experiment, follow [`migration/README.md`](migration/README.md). Do not copy an existing `.venv` between machines.

Use a feature branch with a descriptive name, for example:

```text
docs/clarify-spatial-inputs
fix/donor-split-validation
feat/add-perturbation-summary
```

## Describe the workflow contract

For every new or changed script, notebook, or workflow component, document:

1. purpose and scientific question;
2. required inputs, including paths, formats, identifiers, units, and required columns or metadata;
3. outputs, including filenames, schemas, and where large artifacts are stored;
4. software and model versions, configuration, and random seeds;
5. validation checks and expected results; and
6. known limitations, failure modes, and recovery steps.

Prefer small, composable scripts with command-line arguments over machine-specific paths. Keep analysis logic separate from reporting and plotting when practical.

## Validate your change

Run the checks that apply to your contribution before opening a pull request:

```bash
# Catch Python syntax errors without requiring the full scientific environment.
python -m compileall \
  epithelial_tme_validation \
  geneformer_uv_setup \
  migration \
  tools

# In a bootstrapped Geneformer workspace, verify the environment.
uv run --frozen python scripts/smoke_test.py \
  --geneformer-root ../Geneformer

# Run focused tests when the change adds or modifies testable Python logic.
uv run --frozen pytest
```

For scientific changes, also confirm as applicable:

- input row, cell, donor, and feature counts;
- required columns and identifier conventions;
- absence of donor leakage across splits;
- deterministic behavior under the documented seed;
- expected output files and non-empty results;
- checksums or row counts for transferred critical artifacts;
- agreement with a small known-result or regression fixture; and
- clear reporting of caveats and incomplete validation.

Do not use the full held-out test set to tune model choices. If a result depends on a small number of donors, report that limitation explicitly.

## Notebooks and generated outputs

- Keep the source notebook and its executed, review-ready output synchronized when both are committed.
- Restart the kernel and run notebooks from top to bottom before submission.
- Avoid hidden state, absolute local paths, and credentials in notebook cells or outputs.
- Commit only compact, interpretable outputs. Large atlases, checkpoints, embeddings, and intermediate files belong in external storage.
- Update the relevant `README.md`, `METHODS.md`, `RESULTS.md`, manifest, or status report when behavior or results change.

## AI-assisted development

AI tools may be used for drafting code, tests, documentation, or refactoring, but the contributor remains responsible for every change. Review generated code line by line, verify commands in a safe environment, check scientific assumptions against primary sources, and never provide private data or credentials to an external AI service. State material AI assistance in the pull-request description when it affects implementation or interpretation.

## Pull-request checklist

In the pull-request description, include:

- a concise summary and motivation;
- the affected workflow paths;
- the input/output contract;
- commands used for validation and their results;
- any data, model, or environment assumptions;
- screenshots or compact result tables when they aid review;
- limitations and follow-up work; and
- confirmation that no secrets, controlled data, or large generated artifacts were added.

Keep pull requests focused. Separate environment upgrades, scientific-method changes, and documentation-only edits when that makes review safer.

## Reporting problems

When opening an issue, provide the smallest reproducible example you can, along with the operating system, Python version, relevant package or model versions, command used, expected behavior, actual behavior, and complete error message. Remove private paths, tokens, and controlled data before posting.
