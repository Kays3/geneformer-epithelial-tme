#!/usr/bin/env python3
"""Reusable Geneformer workflow for SCLC single-cell analyses."""

from __future__ import annotations

import argparse
import json
import os
import pickle
from pathlib import Path
from typing import Any


DEFAULT_ATTRS = {
    "cell_type": "cell_type",
    "cell_id": "cell_id",
    "disease": "disease",
    "donor_id": "individual",
    "sex": "sex",
    "age": "age",
}


def read_config(path: str | Path) -> dict[str, Any]:
    with open(path) as handle:
        config = json.load(handle)
    required = ["run_name", "input_h5ad", "model_directory", "cell_type", "tissue", "diseases"]
    missing = [key for key in required if key not in config]
    if missing:
        raise ValueError(f"Missing required config keys: {missing}")
    return config


def run_dir(config: dict[str, Any]) -> Path:
    return Path(config.get("output_root", "runs")) / config["run_name"]


def ensure_dirs(config: dict[str, Any]) -> dict[str, Path]:
    base = run_dir(config)
    paths = {
        "base": base,
        "input": base / "input_h5ad",
        "tokenized": base / "tokenized",
        "splits": base / "splits",
        "model": base / "model",
        "embeddings": base / "embeddings",
        "perturb": base / "perturb",
        "perturb_stats": base / "perturb_stats",
        "plots": base / "plots",
    }
    for path in paths.values():
        path.mkdir(parents=True, exist_ok=True)
    return paths


def summarize_obs(obs: pd.DataFrame, output_file: Path) -> pd.DataFrame:
    import pandas as pd

    summary = (
        obs.groupby("disease", observed=True)
        .agg(num_cell=("cell_id", "count"), num_donor=("donor_id", "nunique"))
        .reset_index()
        .sort_values("disease")
    )
    summary.to_csv(output_file, index=False)
    return summary


def prepare_h5ad(config: dict[str, Any]) -> Path:
    import numpy as np
    import scanpy as sc

    paths = ensure_dirs(config)
    adata = sc.read_h5ad(config["input_h5ad"])
    adata.obsm = {}
    adata.uns = {}

    keep_obs = ["donor_id", "cell_type", "disease", "sex", "development_stage", "tissue"]
    missing_obs = [col for col in keep_obs if col not in adata.obs.columns]
    if missing_obs:
        raise ValueError(f"Input AnnData is missing obs columns: {missing_obs}")
    adata.obs = adata.obs[keep_obs].copy()

    if "feature_name" in adata.var.columns:
        adata.var = adata.var[["feature_name"]].copy()
    else:
        adata.var["feature_name"] = adata.var_names.astype(str)
        adata.var = adata.var[["feature_name"]].copy()

    adata.var["ensembl_id"] = adata.var.index.astype(str)
    adata.obs["cell_id"] = adata.obs_names.astype(str)
    adata.obs["n_counts"] = np.asarray(adata.X.sum(axis=1)).ravel()
    adata.obs["filter_pass"] = 1
    adata.obs["age"] = (
        adata.obs["development_stage"].astype(str).str.extract(r"(\d+)").astype(float)
    )
    adata.obs["age"] = adata.obs["age"].fillna(adata.obs["age"].median())

    mask = (
        (adata.obs["tissue"] == config["tissue"])
        & (adata.obs["cell_type"] == config["cell_type"])
        & (adata.obs["disease"].isin(config["diseases"]))
    )
    adata = adata[mask].copy()
    if adata.n_obs == 0:
        raise ValueError("Filtering produced zero cells. Check tissue, cell_type, and diseases.")

    adata.obs = adata.obs[
        ["donor_id", "cell_id", "cell_type", "disease", "sex", "age", "tissue", "n_counts", "filter_pass"]
    ].copy()

    summarize_obs(adata.obs, paths["base"] / "cohort_summary.csv")
    output_file = paths["input"] / f"{config['run_name']}.h5ad"
    adata.write_h5ad(output_file)
    print(f"Wrote filtered AnnData: {output_file}")
    print(f"Cells: {adata.n_obs:,}; genes: {adata.n_vars:,}")
    return output_file


def tokenize(config: dict[str, Any]) -> Path:
    from geneformer import TranscriptomeTokenizer

    paths = ensure_dirs(config)
    input_file = paths["input"] / f"{config['run_name']}.h5ad"
    if not input_file.exists():
        input_file = prepare_h5ad(config)

    tokenizer_kwargs = {
        "custom_attr_name_dict": DEFAULT_ATTRS,
        "chunk_size": int(config.get("chunk_size", 512)),
        "nproc": int(config.get("tokenizer_nproc", 8)),
        "model_version": config.get("model_version", "V1"),
    }
    if config.get("model_input_size") is not None:
        tokenizer_kwargs["model_input_size"] = int(config["model_input_size"])
    tokenizer = TranscriptomeTokenizer(**tokenizer_kwargs)
    tokenizer.tokenize_data(
        data_directory=str(input_file.parent),
        output_directory=str(paths["tokenized"]),
        output_prefix=config["run_name"],
        file_format="h5ad",
    )
    dataset_file = paths["tokenized"] / f"{config['run_name']}.dataset"
    print(f"Wrote tokenized dataset: {dataset_file}")
    return dataset_file


def donor_table_from_h5ad(config: dict[str, Any]) -> pd.DataFrame:
    import scanpy as sc

    paths = ensure_dirs(config)
    input_file = paths["input"] / f"{config['run_name']}.h5ad"
    if not input_file.exists():
        input_file = prepare_h5ad(config)
    adata = sc.read_h5ad(input_file)
    return adata.obs[["donor_id", "disease"]].drop_duplicates().copy()


def build_splits(config: dict[str, Any]) -> dict[str, list[str]]:
    from sklearn.model_selection import train_test_split

    paths = ensure_dirs(config)
    donor_df = donor_table_from_h5ad(config)
    disease_counts = donor_df.groupby("donor_id")["disease"].nunique()
    ambiguous_ids = disease_counts[disease_counts > 1].index.tolist()
    if ambiguous_ids:
        ambiguous = donor_df[donor_df["donor_id"].isin(ambiguous_ids)].sort_values(["donor_id", "disease"])
        ambiguous.to_csv(paths["splits"] / "ambiguous_donors.csv", index=False)
        policy = config.get("ambiguous_donor_policy", "drop")
        if policy == "fail":
            raise ValueError(
                "Some donor IDs have multiple disease labels. See "
                f"{paths['splits'] / 'ambiguous_donors.csv'}"
            )
        if policy != "drop":
            raise ValueError("ambiguous_donor_policy must be 'drop' or 'fail'.")
        donor_df = donor_df[~donor_df["donor_id"].isin(ambiguous_ids)].copy()

    donor_df = donor_df.drop_duplicates("donor_id").sort_values("donor_id")
    donor_df.to_csv(paths["splits"] / "eligible_donors.csv", index=False)

    class_counts = donor_df["disease"].value_counts()
    if (class_counts < 3).any():
        raise ValueError(
            "Each disease class needs at least 3 unambiguous donors for train/eval/test splitting. "
            f"Counts: {class_counts.to_dict()}"
        )

    seed = int(config.get("split_seed", config.get("training_args", {}).get("seed", 42)))
    train_eval_df, test_df = train_test_split(
        donor_df,
        test_size=float(config.get("test_size", 0.20)),
        stratify=donor_df["disease"],
        random_state=seed,
    )
    train_df, eval_df = train_test_split(
        train_eval_df,
        test_size=float(config.get("eval_size", 0.20)),
        stratify=train_eval_df["disease"],
        random_state=seed,
    )

    splits = {
        "train": train_df["donor_id"].tolist(),
        "eval": eval_df["donor_id"].tolist(),
        "test": test_df["donor_id"].tolist(),
    }
    assert not (set(splits["train"]) & set(splits["eval"]))
    assert not (set(splits["train"]) & set(splits["test"]))
    assert not (set(splits["eval"]) & set(splits["test"]))

    for split_name, split_df in [("train", train_df), ("eval", eval_df), ("test", test_df)]:
        split_df.to_csv(paths["splits"] / f"{split_name}_donors.csv", index=False)
    with open(paths["splits"] / "splits.json", "w") as handle:
        json.dump(splits, handle, indent=2)

    print("Wrote donor-exclusive splits:")
    for key, values in splits.items():
        print(f"  {key}: {len(values)} donors")
    if ambiguous_ids:
        print(f"Dropped {len(ambiguous_ids)} ambiguous donor IDs; see ambiguous_donors.csv")
    return splits


def load_splits(config: dict[str, Any]) -> dict[str, list[str]]:
    split_file = ensure_dirs(config)["splits"] / "splits.json"
    if not split_file.exists():
        return build_splits(config)
    with open(split_file) as handle:
        return json.load(handle)


def classifier(config: dict[str, Any]):
    from geneformer import Classifier

    return Classifier(
        classifier="cell",
        cell_state_dict={"state_key": "disease", "states": "all"},
        filter_data=None,
        training_args=config.get("training_args", {}),
        max_ncells=config.get("max_ncells"),
        freeze_layers=int(config.get("freeze_layers", 3)),
        num_crossval_splits=1,
        forward_batch_size=int(config.get("classifier_forward_batch_size", 32)),
        nproc=int(config.get("classifier_nproc", 4)),
        model_version=config.get("model_version", "V1"),
    )


def prepare_classifier_data(config: dict[str, Any]) -> None:
    paths = ensure_dirs(config)
    dataset_file = paths["tokenized"] / f"{config['run_name']}.dataset"
    if not dataset_file.exists():
        dataset_file = tokenize(config)
    splits = load_splits(config)
    cc = classifier(config)
    cc.prepare_data(
        input_data_file=str(dataset_file),
        output_directory=str(paths["model"]),
        output_prefix=config["run_name"],
        split_id_dict={
            "attr_key": "individual",
            "train": splits["train"] + splits["eval"],
            "test": splits["test"],
        },
    )
    print(f"Wrote classifier-ready datasets: {paths['model']}")


def train(config: dict[str, Any]) -> Any:
    paths = ensure_dirs(config)
    prepare_classifier_data(config)
    splits = load_splits(config)
    os.environ["WANDB_DISABLED"] = "true"
    cc = classifier(config)
    metrics = cc.validate(
        model_directory=config["model_directory"],
        prepared_input_data_file=str(paths["model"] / f"{config['run_name']}_labeled_train.dataset"),
        id_class_dict_file=str(paths["model"] / f"{config['run_name']}_id_class_dict.pkl"),
        output_directory=str(paths["model"]),
        output_prefix=config["run_name"],
        split_id_dict={"attr_key": "individual", "train": splits["train"], "eval": splits["eval"]},
        n_hyperopt_trials=int(config.get("n_hyperopt_trials", 0)),
    )
    with open(paths["model"] / "validation_metrics.pkl", "wb") as handle:
        pickle.dump(metrics, handle)
    print(f"Wrote validation metrics: {paths['model'] / 'validation_metrics.pkl'}")
    return metrics


def latest_model_dir(config: dict[str, Any]) -> Path:
    if config.get("model_run_directory"):
        model_path = Path(config["model_run_directory"])
        if not model_path.exists():
            raise FileNotFoundError(f"Configured model_run_directory does not exist: {model_path}")
        return model_path

    paths = ensure_dirs(config)
    candidates = sorted(paths["model"].glob(f"*geneformer_cellClassifier_{config['run_name']}*/ksplit1"))
    if not candidates:
        raise FileNotFoundError(
            f"No fine-tuned ksplit1 model found under {paths['model']}. "
            "Run the train step first or set model_run_directory in the config."
        )
    return candidates[-1]


def evaluate(config: dict[str, Any]) -> Any:
    paths = ensure_dirs(config)
    cc = classifier(config)
    metrics = cc.evaluate_saved_model(
        model_directory=str(latest_model_dir(config)),
        id_class_dict_file=str(paths["model"] / f"{config['run_name']}_id_class_dict.pkl"),
        test_data_file=str(paths["model"] / f"{config['run_name']}_labeled_test.dataset"),
        output_directory=str(paths["model"]),
        output_prefix=config["run_name"],
    )
    with open(paths["model"] / "test_metrics.pkl", "wb") as handle:
        pickle.dump(metrics, handle)
    class_order = config.get("class_order", config["diseases"])
    cc.plot_conf_mat(
        conf_mat_dict={"Geneformer": metrics["conf_matrix"]},
        output_directory=str(paths["plots"]),
        output_prefix=f"{config['run_name']}_confusion",
        custom_class_order=class_order,
    )
    cc.plot_predictions(
        predictions_file=str(paths["model"] / f"{config['run_name']}_pred_dict.pkl"),
        id_class_dict_file=str(paths["model"] / f"{config['run_name']}_id_class_dict.pkl"),
        title="disease",
        output_directory=str(paths["plots"]),
        output_prefix=f"{config['run_name']}_predictions",
        custom_class_order=class_order,
    )
    print(f"Wrote test metrics and plots under: {paths['model']} and {paths['plots']}")
    return metrics


def extract_embeddings(config: dict[str, Any]) -> Any:
    from geneformer import EmbExtractor

    paths = ensure_dirs(config)
    embex = EmbExtractor(
        model_type="CellClassifier",
        num_classes=len(config["diseases"]),
        filter_data=None,
        max_ncells=config.get("embedding_max_ncells"),
        emb_layer=-1,
        emb_label=["disease", "individual"],
        labels_to_plot=["disease", "individual"],
        forward_batch_size=int(config.get("embedding_forward_batch_size", 256)),
        nproc=int(config.get("embedding_nproc", 4)),
        model_version=config.get("model_version", "V1"),
    )
    embs = embex.extract_embs(
        model_directory=str(latest_model_dir(config)),
        input_data_file=str(paths["tokenized"] / f"{config['run_name']}.dataset"),
        output_directory=str(paths["embeddings"]),
        output_prefix="finetuned_embs",
    )
    embex.plot_embs(
        embs=embs,
        plot_style="umap",
        output_directory=str(paths["plots"]),
        output_prefix=f"{config['run_name']}_umap",
        max_ncells_to_plot=5000,
    )
    embex.plot_embs(
        embs=embs,
        plot_style="heatmap",
        output_directory=str(paths["plots"]),
        output_prefix=f"{config['run_name']}_heatmap",
        max_ncells_to_plot=5000,
    )
    print(f"Wrote embeddings and plots under: {paths['embeddings']} and {paths['plots']}")
    return embs


def perturb(config: dict[str, Any]) -> None:
    from geneformer import EmbExtractor, InSilicoPerturber, InSilicoPerturberStats

    paths = ensure_dirs(config)
    perturb_cfg = config["perturbation"]
    cell_states_to_model = {
        "state_key": "disease",
        "start_state": perturb_cfg["start_state"],
        "goal_state": perturb_cfg["goal_state"],
        "alt_states": perturb_cfg.get("alt_states", []),
    }

    embex = EmbExtractor(
        model_type="CellClassifier",
        num_classes=len(config["diseases"]),
        filter_data=None,
        max_ncells=int(perturb_cfg.get("state_max_ncells", 5000)),
        emb_layer=-1,
        summary_stat="exact_mean",
        forward_batch_size=int(config.get("embedding_forward_batch_size", 256)),
        nproc=int(config.get("embedding_nproc", 4)),
        model_version=config.get("model_version", "V1"),
    )
    state_embs_dict = embex.get_state_embs(
        cell_states_to_model,
        model_directory=str(latest_model_dir(config)),
        input_data_file=str(paths["tokenized"] / f"{config['run_name']}.dataset"),
        output_directory=str(paths["embeddings"]),
        output_prefix="state_embs",
    )

    isp = InSilicoPerturber(
        perturb_type=perturb_cfg.get("perturb_type", "delete"),
        genes_to_perturb=perturb_cfg.get("genes_to_perturb", "all"),
        model_type="CellClassifier",
        num_classes=len(config["diseases"]),
        emb_mode="cell",
        cell_states_to_model=cell_states_to_model,
        state_embs_dict=state_embs_dict,
        max_ncells=int(perturb_cfg.get("max_ncells", 2000)),
        emb_layer=-1,
        forward_batch_size=int(config.get("perturb_forward_batch_size", 256)),
        nproc=int(config.get("perturb_nproc", 4)),
        model_version=config.get("model_version", "V1"),
    )
    isp.perturb_data(
        model_directory=str(latest_model_dir(config)),
        input_data_file=str(paths["tokenized"] / f"{config['run_name']}.dataset"),
        output_directory=str(paths["perturb"]),
        output_prefix=config["run_name"],
    )

    ispstats = InSilicoPerturberStats(
        mode="goal_state_shift",
        genes_perturbed=perturb_cfg.get("genes_to_perturb", "all"),
        combos=0,
        anchor_gene=None,
        cell_states_to_model=cell_states_to_model,
        model_version=config.get("model_version", "V1"),
    )
    ispstats.get_stats(
        input_data_directory=str(paths["perturb"]),
        null_dist_data_directory=None,
        output_directory=str(paths["perturb_stats"]),
        output_prefix=f"{config['run_name']}_perturbation_stats",
    )
    print(f"Wrote perturbation statistics: {paths['perturb_stats']}")


def plot_perturbation(config: dict[str, Any]) -> None:
    import matplotlib.pyplot as plt
    import numpy as np
    import pandas as pd
    import seaborn as sns

    paths = ensure_dirs(config)
    result_file = paths["perturb_stats"] / f"{config['run_name']}_perturbation_stats.csv"
    if not result_file.exists():
        raise FileNotFoundError(f"Missing perturbation stats file: {result_file}")
    results = pd.read_csv(result_file, index_col=0)
    filtered = results[results["N_Detections"] > int(config.get("min_detections", 100))].copy()
    filtered["minus_log10_fdr"] = -np.log10(filtered["Goal_end_FDR"].clip(lower=1e-300))

    sns.set_theme(style="white")
    plt.figure(figsize=(8, 6))
    sns.scatterplot(
        data=filtered,
        x="Shift_to_goal_end",
        y="minus_log10_fdr",
        size="N_Detections",
        sizes=(20, 200),
        alpha=0.7,
    )
    plt.axvline(0, color="red", linestyle=":")
    plt.axhline(-np.log10(float(config.get("fdr_cutoff", 0.05))), color="gray", linestyle="--")
    plt.title(
        f"{config['perturbation']['start_state']} to {config['perturbation']['goal_state']}",
        fontsize=12,
    )
    plt.xlabel(f"Shift toward {config['perturbation']['goal_state']}")
    plt.ylabel("-log10(FDR)")
    plt.tight_layout()
    plt.savefig(paths["plots"] / f"{config['run_name']}_perturbation_volcano.png", dpi=200)
    plt.close()

    top = filtered[
        filtered["Goal_end_FDR"] < float(config.get("fdr_cutoff", 0.05))
    ].copy()
    top = top.dropna(subset=["Gene_name"])
    top = top.reindex(top["Shift_to_goal_end"].abs().sort_values(ascending=False).index)
    top.head(int(config.get("top_n_genes", 30))).to_csv(paths["perturb_stats"] / "top_goal_shift_genes.csv")
    print(f"Wrote perturbation plots and top genes under: {paths['plots']} and {paths['perturb_stats']}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Streamlined Geneformer workflow for SCLC analyses.")
    parser.add_argument("--config", default="configs/sclc_tcell.json", help="Path to a JSON config file.")
    parser.add_argument(
        "--step",
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
        default="all",
    )
    args = parser.parse_args()
    config = read_config(args.config)

    if args.step in ["prepare", "all"]:
        prepare_h5ad(config)
    if args.step in ["tokenize", "all"]:
        tokenize(config)
    if args.step in ["split", "all"]:
        build_splits(config)
    if args.step in ["prepare-classifier", "all"]:
        prepare_classifier_data(config)
    if args.step in ["train", "all"]:
        train(config)
    if args.step in ["evaluate", "all"]:
        evaluate(config)
    if args.step in ["embeddings", "all"]:
        extract_embeddings(config)
    if args.step in ["perturb", "all"]:
        perturb(config)
    if args.step in ["plot-perturbation", "all"]:
        plot_perturbation(config)


if __name__ == "__main__":
    main()
