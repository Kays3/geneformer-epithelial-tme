# Resolved environments

The exact dependency resolution that produced a working Geneformer environment,
captured so it can be reproduced rather than re-resolved. `bootstrap_workspace.sh`
prints an instruction to commit these four files; this is where they live.

| File | Why it matters |
|---|---|
| `uv.lock` | the full transitive resolution, every package and hash |
| `pyproject.toml` | the profile as it was actually used, including the transformers pin |
| `.python-version` | interpreter series |
| `.geneformer-commit` | the upstream Geneformer commit the editable install points at |

## cu130

Resolved on `thinkstation2` (NVIDIA GB10, aarch64, CUDA 13.0), Python 3.12,
against Geneformer `f45a6c7`. Verified by loading the fine-tuned 3-class
classifier from `/srv/lab` and running a forward pass on the GPU.

```text
torch 2.13.0+cu130   transformers 4.46.0   datasets 5.0.1
anndata 0.13.2       scanpy 1.12.3         numpy 2.5.2      pandas 3.0.5
```

Recreate with:

```bash
bash geneformer_uv_setup/scripts/bootstrap_workspace.sh \
  ~/workspace/geneformer-uv-starter sclc_analysis cu130 f45a6c7
```

Needs `python3-dev` for the `tdigest` C extension; without it the build fails on
a missing `Python.h`. The post-hoc analyses do not need any of this — use the
`postprocess` profile, which installs from wheels alone.
