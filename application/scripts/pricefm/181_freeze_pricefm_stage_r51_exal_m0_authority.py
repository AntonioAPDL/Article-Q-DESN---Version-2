#!/usr/bin/env python3
"""Freeze the authoritative PriceFM exAL surface for collapsed-M0 replay."""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import subprocess
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
ARTICLE_REPO = Path(__file__).resolve().parents[3]
EXDQLM_REPO = Path("/data/jaguir26/local/src/exdqlm__wt__independent_exal_m0_relaunch_v1_1p0p0")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
REGISTRY = DATA / "authoritative/pricefm_full_surface_decision_closeout_20260704/pricefm_full_surface_decision_registry.csv"
ATLAS = DATA / "authoritative/pricefm_stage_r8_specification_atlas_20260706/pricefm_stage_r8_specification_atlas.csv"
MANIFEST_ROOT = DATA / "experiment_grids"
OUTPUT = DATA / "authoritative/pricefm_stage_r51_exal_m0_authority_freeze_20260811"
EXAL_METHOD = "qdesn_exal_rhs_ns_exact_chunked"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
EXPECTED_EXDQLM_HEAD = "10ca8e356ff445f600c4eee15f36db8a69330016"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--article-repo", type=Path, default=ARTICLE_REPO)
    p.add_argument("--exdqlm-repo", type=Path, default=EXDQLM_REPO)
    p.add_argument("--registry", type=Path, default=REGISTRY)
    p.add_argument("--atlas", type=Path, default=ATLAS)
    p.add_argument("--manifest-root", type=Path, default=MANIFEST_ROOT)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-targets", type=int, default=87)
    p.add_argument("--expected-al-exclusions", type=int, default=27)
    p.add_argument("--expected-complete-lineages", type=int, default=81)
    p.add_argument("--expected-exdqlm-head", default=EXPECTED_EXDQLM_HEAD)
    p.add_argument("--lineage-tolerance", type=float, default=1e-8)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            h.update(block)
    return h.hexdigest()


def git_head(path: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
    ).strip()


def parse_list(value) -> list:
    if isinstance(value, list):
        return value
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return []
    text = str(value).strip()
    if not text:
        return []
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        parsed = ast.literal_eval(text)
    return parsed if isinstance(parsed, list) else [parsed]


def read_metric(path: Path, method: str = EXAL_METHOD) -> dict[tuple[str, float | None], float]:
    frame = pd.read_csv(path)
    required = {"method_id", "split", "unit", "AQL"}
    if not required.issubset(frame.columns):
        raise RuntimeError(f"Metric summary lacks {sorted(required)}: {path}")
    frame = frame[
        frame.method_id.eq(method)
        & frame.split.isin(["val", "test"])
        & frame.unit.eq("original")
    ].copy()
    if frame.empty:
        return {}
    tau_values = frame["tau"] if "tau" in frame.columns else pd.Series([None] * len(frame))
    return {
        (str(row.split), None if tau is None else float(tau)): float(row.AQL)
        for row, tau in zip(frame.itertuples(index=False), tau_values)
    }


def selected_specs(registry: pd.DataFrame, atlas: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    eligible = registry[registry.qdesn_method_id.eq(EXAL_METHOD)].copy()
    excluded = registry[~registry.qdesn_method_id.eq(EXAL_METHOD)].copy()
    matched = atlas.merge(
        eligible[["region", "fold", "experiment_id", "qdesn_method_id"]],
        left_on=["region", "fold", "experiment_id", "method_id"],
        right_on=["region", "fold", "experiment_id", "qdesn_method_id"],
        how="inner",
    )
    matched = matched.drop_duplicates(["region", "fold", "experiment_id", "method_id"])
    if len(matched) != len(eligible):
        keys = eligible[["region", "fold", "experiment_id"]].merge(
            matched[["region", "fold", "experiment_id"]],
            on=["region", "fold", "experiment_id"], how="left", indicator=True,
        )
        missing = keys[keys._merge.eq("left_only")]
        raise RuntimeError(f"Atlas did not uniquely recover all exAL targets: {missing.to_dict('records')}")
    return matched, excluded


def source_paths(artifact_repo: Path, row) -> dict[str, Path]:
    run = artifact_repo / str(row.run_dir)
    cell = run / "cells" / f"region={row.region}" / f"fold={int(row.fold)}"
    return {
        "source_config": cell / "config.yaml",
        "source_adapter_manifest": cell / "adapter/adapter_manifest.json",
        "source_metric_summary": cell / "model/metric_summary.csv",
        "source_parameter_summary": cell / "model/model_parameter_summary.csv",
        "source_experiment_manifest": artifact_repo / str(row.manifest_path),
    }


def target_key(region, fold, experiment_id) -> tuple[str, int, str]:
    return str(region), int(fold), str(experiment_id)


def collect_lineage_candidates(
    manifest_root: Path,
    artifact_repo: Path,
    target_keys: set[tuple[str, int, str]],
) -> pd.DataFrame:
    records: list[dict] = []
    for manifest_path in sorted(manifest_root.rglob("manifest.csv")):
        manifest = pd.read_csv(manifest_path)
        if "median_registry" not in manifest.columns:
            continue
        for row_index, row in manifest.iterrows():
            raw = row.get("median_registry")
            if raw is None or (isinstance(raw, float) and pd.isna(raw)) or not str(raw).strip():
                continue
            try:
                contract = json.loads(str(raw))
            except json.JSONDecodeError:
                continue
            key = target_key(
                contract.get("region", ""),
                contract.get("fold", -1),
                contract.get("median_experiment_id", ""),
            )
            if key not in target_keys:
                continue
            quantiles = [float(x) for x in parse_list(row.get("quantiles"))]
            if len(quantiles) != 1 or not any(abs(quantiles[0] - tau) < 1e-12 for tau in TAUS):
                continue
            run_dir = artifact_repo / str(row.get("run_dir", ""))
            cell = run_dir / "cells" / f"region={key[0]}" / f"fold={key[1]}"
            metric_path = cell / "model/metric_summary.csv"
            if not metric_path.exists():
                continue
            metrics = read_metric(metric_path)
            tau = quantiles[0]
            val = metrics.get(("val", tau), metrics.get(("val", None)))
            test = metrics.get(("test", tau), metrics.get(("test", None)))
            if val is None or test is None:
                continue
            records.append({
                "region": key[0], "fold": key[1], "experiment_id": key[2],
                "lineage_grid": manifest_path.parent.name,
                "lineage_manifest": str(manifest_path.resolve()),
                "lineage_manifest_row": int(row_index),
                "child_experiment_id": str(row.get("id", row.get("experiment_id", ""))),
                "tau": tau, "val_AQL": val, "test_AQL": test,
                "child_metric_summary": str(metric_path.resolve()),
                "child_metric_sha256": sha256(metric_path),
                "child_full_config": str((artifact_repo / str(row.get("full_config", ""))).resolve()),
                "child_data_config": str((artifact_repo / str(row.get("data_config", ""))).resolve()),
            })
    return pd.DataFrame(records)


def choose_lineages(targets: pd.DataFrame, candidates: pd.DataFrame, tolerance: float):
    selected_rows: list[pd.DataFrame] = []
    target_rows: list[dict] = []
    for target in targets.itertuples(index=False):
        key = target_key(target.region, target.fold, target.experiment_id)
        subset = candidates[
            candidates.region.eq(key[0])
            & candidates.fold.eq(key[1])
            & candidates.experiment_id.eq(key[2])
        ] if not candidates.empty else candidates
        choices = []
        for grid, group in subset.groupby("lineage_grid", sort=True):
            group = group.sort_values(["tau", "child_experiment_id"]).drop_duplicates("tau")
            taus = tuple(round(float(x), 12) for x in group.tau)
            complete = taus == tuple(round(x, 12) for x in TAUS)
            if complete:
                mean_test = float(group.test_AQL.mean())
                choices.append((abs(mean_test - float(target.qdesn_AQL)), str(grid), group, mean_test, float(group.val_AQL.mean())))
        choices.sort(key=lambda item: (item[0], item[1]))
        if choices:
            delta, grid, group, mean_test, mean_val = choices[0]
            group = group.copy()
            group["selected_lineage"] = True
            group["aggregate_test_AQL"] = mean_test
            group["aggregate_val_AQL"] = mean_val
            group["aggregate_test_delta_vs_authority"] = delta
            selected_rows.append(group)
            status = "complete_exact" if delta <= tolerance else "complete_metric_drift"
            n_taus = len(group)
        else:
            grid, mean_test, mean_val, delta, status, n_taus = "", float("nan"), float("nan"), float("nan"), "legacy_lineage_gap", 0
        target_rows.append({
            "region": key[0], "fold": key[1], "experiment_id": key[2],
            "lineage_status": status, "lineage_grid": grid,
            "lineage_quantiles": n_taus, "lineage_val_AQL": mean_val,
            "lineage_test_AQL": mean_test, "lineage_test_delta_vs_authority": delta,
        })
    selected = pd.concat(selected_rows, ignore_index=True) if selected_rows else pd.DataFrame()
    return pd.DataFrame(target_rows), selected


def prepare_output(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(f"Output exists: {path}")
    path.mkdir(parents=True, exist_ok=True)


def run(args) -> dict:
    out = args.output_dir.resolve()
    prepare_output(out, args.force)
    engine_head = git_head(args.exdqlm_repo)
    if engine_head != args.expected_exdqlm_head:
        raise RuntimeError(f"Collapsed-M0 engine drifted: {engine_head} != {args.expected_exdqlm_head}")

    registry = pd.read_csv(args.registry)
    atlas = pd.read_csv(args.atlas, low_memory=False)
    matched, excluded = selected_specs(registry, atlas)
    if len(matched) != args.expected_targets or len(excluded) != args.expected_al_exclusions:
        raise RuntimeError(
            f"Authority counts changed: exAL={len(matched)}, exclusions={len(excluded)}"
        )

    spec_records = []
    source_records = []
    for row in matched.itertuples(index=False):
        paths = source_paths(args.artifact_repo, row)
        for label, path in paths.items():
            if not path.exists():
                raise FileNotFoundError(path)
            source_records.append({
                "region": row.region, "fold": int(row.fold), "label": label,
                "path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size,
            })
        payload = json.loads(json.dumps(__import__("yaml").safe_load(paths["source_config"].read_text())))
        cfg = payload["pricefm_desn_smoke"]
        adapter = cfg["adapter"]
        if str(cfg["region"]) != str(row.region) or int(cfg["fold"]) != int(row.fold):
            raise RuntimeError(f"Source config region/fold mismatch: {paths['source_config']}")
        if EXAL_METHOD.split("_")[1] not in [str(x).lower() for x in cfg["qdesn_vb"]["likelihoods"]]:
            raise RuntimeError(f"Source config does not fit exAL: {paths['source_config']}")
        spec_records.append({
            "region": row.region, "fold": int(row.fold), "experiment_id": row.experiment_id,
            "method_id": EXAL_METHOD, "source_class": row.source_class,
            "feature_policy": cfg.get("feature_policy", "target_only"),
            "lag_window": int(row.lag_window), "feature_map": adapter["feature_map"],
            "feature_dim": int(adapter["feature_dim"]), "depth": int(adapter["depth"]),
            "units": json.dumps(adapter["units"]), "alpha": float(adapter["alpha"]),
            "rho": float(adapter["rho"]), "input_scale": float(adapter["input_scale"]),
            "projection_scale": float(adapter["projection_scale"]),
            "recurrent_sparsity": float(adapter["recurrent_sparsity"]),
            "state_output": adapter["state_output"], "tau0": float(cfg["rhs_ns"]["tau0"]),
            "seed": int(adapter["seed"]), "quantiles": json.dumps(TAUS),
            "source_config": str(paths["source_config"].resolve()),
            "source_adapter_manifest": str(paths["source_adapter_manifest"].resolve()),
            "source_metric_summary": str(paths["source_metric_summary"].resolve()),
            "source_parameter_summary": str(paths["source_parameter_summary"].resolve()),
            "source_experiment_manifest": str(paths["source_experiment_manifest"].resolve()),
            "spec_signature": str(row.spec_signature),
        })

    specs = pd.DataFrame(spec_records).sort_values(["region", "fold"]).reset_index(drop=True)
    keys = {target_key(x.region, x.fold, x.experiment_id) for x in matched.itertuples(index=False)}
    candidates = collect_lineage_candidates(args.manifest_root, args.artifact_repo, keys)
    authority_targets = registry[registry.qdesn_method_id.eq(EXAL_METHOD)].copy()
    lineage_status, selected_lineage = choose_lineages(
        authority_targets, candidates, args.lineage_tolerance
    )
    complete = int(lineage_status.lineage_status.str.startswith("complete").sum())
    if complete != args.expected_complete_lineages:
        raise RuntimeError(f"Seven-quantile lineage count changed: {complete}")

    target_columns = [
        "region", "fold", "source_class", "experiment_id", "qdesn_method_id",
        "qdesn_AQL", "pricefm_AQL", "decision_label", "feature_policy",
        "selected_on_split", "selection_metric", "selection_metric_value",
        "selection_is_validation_only", "test_metrics_role", "evidence_path", "evidence_sha256",
    ]
    targets = authority_targets[target_columns].drop_duplicates(["region", "fold"]).merge(
        specs, on=["region", "fold", "source_class", "experiment_id", "feature_policy"], how="left"
    ).merge(lineage_status, on=["region", "fold", "experiment_id"], how="left")
    targets["m0_eligible"] = True
    targets["selection_unit"] = "region_fold_seven_quantile_bundle"
    targets["selection_role"] = "validation_only"
    targets["test_role"] = "frozen_audit_after_selection"
    targets["registry_mutation_authorized"] = False
    targets["article_mutation_authorized"] = False

    excluded_out = excluded.copy()
    excluded_out["m0_eligible"] = False
    excluded_out["exclusion_reason"] = "collapsed_m0_is_exal_only"
    gaps = targets[targets.lineage_status.eq("legacy_lineage_gap")].copy()

    targets.to_csv(out / "pricefm_stage_r51_exal_target_ledger.csv", index=False)
    excluded_out.to_csv(out / "pricefm_stage_r51_al_exclusion_ledger.csv", index=False)
    specs.to_csv(out / "pricefm_stage_r51_case_specification_freeze.csv", index=False)
    selected_lineage.to_csv(out / "pricefm_stage_r51_selected_quantile_lineage.csv", index=False)
    gaps.to_csv(out / "pricefm_stage_r51_lineage_gaps.csv", index=False)

    global_sources = [
        ("authority_registry", args.registry), ("stage_r8_atlas", args.atlas),
        ("r51_script", Path(__file__).resolve()),
        ("m0_engine", args.exdqlm_repo / "R/exal_mcmc_collapsed_scale_shape.R"),
        ("m0_dispatch", args.exdqlm_repo / "R/exal_mcmc_fit.R"),
    ]
    for label, path in global_sources:
        source_records.append({
            "region": "ALL", "fold": 0, "label": label, "path": str(path.resolve()),
            "sha256": sha256(path), "bytes": path.stat().st_size,
        })
    pd.DataFrame(source_records).to_csv(out / "source_manifest.csv", index=False)

    gates = pd.DataFrame([
        {"gate": "authoritative_surface_114", "passed": len(registry) == 114, "observed": len(registry)},
        {"gate": "selected_exal_87", "passed": len(targets) == args.expected_targets, "observed": len(targets)},
        {"gate": "excluded_al_27", "passed": len(excluded_out) == args.expected_al_exclusions, "observed": len(excluded_out)},
        {"gate": "exact_source_specs", "passed": len(specs) == args.expected_targets, "observed": len(specs)},
        {"gate": "complete_lineages_81", "passed": complete == args.expected_complete_lineages, "observed": complete},
        {"gate": "m0_engine_pinned", "passed": engine_head == args.expected_exdqlm_head, "observed": engine_head},
        {"gate": "selection_validation_only", "passed": targets.selection_is_validation_only.astype(str).str.lower().eq("true").all(), "observed": "all"},
        {"gate": "registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    gates.to_csv(out / "pricefm_stage_r51_freeze_gates.csv", index=False)
    if not gates.passed.all():
        raise RuntimeError("Stage-R51 authority freeze gates failed")

    summary = {
        "status": "completed_authority_freeze",
        "article_head": git_head(args.article_repo), "exdqlm_head": engine_head,
        "surface_rows": len(registry), "exal_targets": len(targets),
        "al_exclusions": len(excluded_out), "complete_quantile_lineages": complete,
        "lineage_gaps": len(gaps), "quantiles": list(TAUS),
        "launch_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    write_json(out / "summary.json", summary)
    (out / "pricefm_stage_r51_exal_m0_authority_freeze_report.md").write_text(
        "# PriceFM Stage-R51 exAL collapsed-M0 authority freeze\n\n"
        "R51 freezes the 87 exAL region/fold specifications currently selected on the "
        "114-row PriceFM surface. The 27 AL rows are explicitly excluded because M0 is exAL-only.\n\n"
        f"Complete seven-quantile child lineage is available for {complete} cases; {len(gaps)} "
        "legacy bridge cases require deterministic VB replay before promotion. Every case retains "
        "its own frozen reservoir and information-set specification.\n\n"
        "R51 does not launch, fit, mutate the registry, or edit the article.\n"
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
