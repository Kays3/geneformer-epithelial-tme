# Two-machine workflow

This project runs across a laptop (authoring, review, figures) and two GB10 DGX Spark
nodes, `thinkstation2` and `thinkstation1` (GPU compute). Large data and run artifacts
live outside Git under `KD/` — see [`RELATIONSHIP_TO_KD.md`](RELATIONSHIP_TO_KD.md).

## Sync

```bash
./tools/sync.sh
```

Rebases onto `origin/main`, pushes, then fast-forwards `thinkstation2` directly. Run it
**before starting work on a machine and after finishing**. `--check` reports divergence
without changing anything; `--no-ts2` skips the workstation when it is unreachable.

The laptop can push straight to `thinkstation2` because that repo sets
`receive.denyCurrentBranch=updateInstead`, which updates its working tree in place — no
GitHub round-trip for a one-line script change. Setup, already applied:

```bash
ssh ts2 'cd ~/workspace/geneformer-lung-tcell && git config receive.denyCurrentBranch updateInstead'
git remote add ts2 ts2:workspace/geneformer-lung-tcell
```

Make rebase the default so a forgotten pull cannot create a merge bubble:

```bash
git config pull.rebase true
```

## Data layout: /srv/lab

Large data lives outside Git and outside any personal home. It sits in `/srv/lab`,
owned `root:labusers` with mode `2775`, so every `labusers` member can read it and
the setgid bit makes new files inherit the group.

This is not cosmetic. The data was previously under `/home/thinkstation2`, mode
`750`, owned by a per-machine account. When those accounts were replaced by
personal ones the data became unreadable to everybody — the second time a path
assumption has broken this project. A group-owned path survives account churn.

| Path | Contents | Shared? |
|---|---|---|
| `/srv/lab/KD/` | experiment workspaces, raw perturbation output, stats | yes |
| `/srv/lab/spatial_raw/GSE263196_RAW/` | Visium matrices (gitignored, not in a clone) | yes |
| `/srv/lab/geneformer/` | Geneformer checkout, model weights, token dictionary | yes |
| `~/workspace/geneformer-uv-starter/.venv` | Python interpreter | **no — per user** |

The interpreter is the one thing that must not be shared. A virtualenv embeds the
absolute paths of the machine and user that built it, so a copied venv half-works
and then fails obscurely. Rebuild it instead:

```bash
bash geneformer_uv_setup/scripts/bootstrap_workspace.sh
```

`/srv/lab` is local to each node, not shared storage. The nodes ran different arms
of the perturbation, so each holds its own copy and there is no merge between them.

### Legacy paths and the per-user copy

A dozen committed scripts, notebooks and manifests default to `~/workspace/KD`,
which does not exist under the personal accounts. Each node therefore provides
that path:

| Path | Kind | Why |
|---|---|---|
| `~/workspace/KD` | **real copy** of `/srv/lab/KD` | per-user working copy, writable without affecting anyone else |
| `~/workspace/geneformer-uv-starter/geneformer-workspace/Geneformer` | symlink to `/srv/lab/geneformer` | model weights are immutable; no reason to duplicate |

The symlink exists because several scripts expect the Geneformer checkout under
`geneformer-workspace/`, while `bootstrap_workspace.sh` creates it one level up.

**The copy diverges the moment either side is written to.** `/srv/lab/KD` stays
the shared reference; `~/workspace/KD` is a personal workspace. Re-sync a stale
copy with rsync, which tops up rather than deleting:

```bash
rsync -aH /srv/lab/KD/ ~/workspace/KD/          # refresh from shared
rsync -aHn --delete /srv/lab/KD/ ~/workspace/KD/ | head   # dry-run: what drifted
```

Disk cost is real and on the same filesystem: 24 GB on thinkstation2, 3.7 GB on
thinkstation1, per user.

With these in place a script runs correctly on its built-in defaults alone, with
no environment variables set. `tools/lab_env.sh` still takes precedence when
sourced, so the explicit and implicit routes agree.

### Resolving paths

```bash
source tools/lab_env.sh    # exports every path the analyses read
bash tools/lab_env.sh      # or run it directly to see which paths exist
```

Resolution order is: an explicit environment variable, then the untracked
per-machine `~/.config/geneformer-lung-tcell/paths.env`, then the `/srv/lab`
defaults. No analysis script hardcodes a machine path; this file is the single
place a machine's layout differs.

### Migrating a node

```bash
sudo bash tools/migrate_to_srv_lab.sh --inventory   # sizes and free space, changes nothing
sudo bash tools/migrate_to_srv_lab.sh --migrate     # copy, then group + setgid
sudo bash tools/migrate_to_srv_lab.sh --verify      # file counts and permissions
```

It never deletes the source and rsync runs without `--delete`, so it is safe to
re-run. Delete the retired account's copy yourself once `--verify` passes.


## Lessons from the fork this replaced

This section is carried over from the sibling `geneformer-sclc-tcell`/
`geneformer-nsclc-tcell` repos' `WORKFLOW.md` -- the incident and its examples
below happened on the SCLC T-cell line of work, before this repo existed. Kept
here because the *lessons* apply equally to this repo's own two-machine
workflow; the example paths (`sclc_validation/...`) belong to that sibling.

On 2026-08-07 the laptop and `thinkstation2` had each committed on top of the same
parent, forking history. Untangling it needed a manual rebase. Nothing was lost, but the
following practices would have prevented it entirely.

### 1. Run analyses from the repo checkout, not a scratch directory

The denoised spatial validation was first run by `scp`-ing the script to
`~/scratch_denoised_spatial/` on the workstation. It worked, but the script that
produced the results was not the script under version control — if the two had drifted,
the committed results would have been unreproducible.

Prefer:

```bash
./tools/sync.sh                                   # laptop: publish the script
ssh ts2 'cd ~/workspace/geneformer-lung-tcell && \
  GSE263196_RAW_DIR=... python sclc_validation/spatial_validation/spatial_validation_denoised_programs.py'
```

Provenance is then automatic: the commit hash on the workstation *is* the code that ran.

### 2. Keep machine-specific paths out of tracked files

Commit `16c061e` had to hand-edit `/home/petadimensionlab/...` to
`/home/thinkstation2/...` across 8 files. That class of change recurs on every host move.

The newer scripts already do this correctly — `SCLC_PERTURBATION_ROOT`,
`GSE263196_RAW_DIR` and `DENOISED_CANDIDATES` are environment overrides with defaults.
Extend that pattern rather than hardcoding: put per-host values in an untracked
`config/paths.env`, source it, and keep absolute paths out of the repository.

### 3. Preflight the inputs before a long run

The GSE263196 matrices had never been extracted — only the 244 MB
`GSE263196_RAW.tar` was on disk, so the spatial pipeline could not have run at all. That
was discovered by inspection, not by an error message.

A long GPU job should assert its inputs exist and are the expected shape before it starts,
so a missing file fails in seconds instead of after the sample-loading phase.

### 4. Pull results back into the repo, not into a home directory

Results were retrieved with an ad-hoc `rsync` into
`sclc_validation/spatial_validation/results_denoised_programs/`. That destination was the
right one, but the command was typed by hand. Wrapping the retrieval in the run script —
or committing on the workstation and syncing — removes the chance of results landing
somewhere untracked.

## Recovery

`tools/sync.sh` never force-pushes and refuses to run against a dirty tree, so it cannot
discard work. Before any history rewrite, tag the pre-rewrite state:

```bash
git branch -f backup/pre-sync-$(git rev-parse --short HEAD) HEAD
```

`thinkstation2` currently holds `backup/pre-sync-9804944` from the fork described above.
It can be deleted once the rebased history is confirmed good.
