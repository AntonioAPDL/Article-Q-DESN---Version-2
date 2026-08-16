#!/usr/bin/env python3
"""Prepare the PriceFM Stage-C expansion manifest.

Stage C starts from the post-seven-quantile Stage-B confirmation gate. This
script does not launch fits. It writes a reproducible candidate manifest for
the next median-screening batch plus a separate exception/rescue queue.

The manifest deliberately separates:

- completion folds for partially evaluated regions;
- diverse new-region folds;
- already evaluated exceptions such as FI fold 3.

This prevents median-only or seed-robust evidence from being treated as a
paper-quantile promotion decision.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess

import pandas as pd

from pricefm_common import load_config, pricefm_block, parse_bool, repo_path, write_json
from pricefm_graph import get_k_hop_regions


DEFAULT_CONFIRMED_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_b_confirmed_panel_20260618"
)
DEFAULT_PHASE1 = "application/data_local/pricefm/external/PriceFM/Result/phase1_pretraining.csv"
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_c_manifest_20260618"
)
DEFAULT_QUEUE2_REGIONS = "EE,LV,LT,DK_2,RO,HU,SE_4,DK_1,SK,SI,NL,BE"
DEFAULT_FOLDS = "1,2,3"

QUEUE_COMPLETION = "completion_folds"
QUEUE_NEW_REGION = "diverse_new_regions"
QUEUE_EXCEPTION = "exception_rescue"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--config", default="application/config/pricefm_data_pipeline.yaml")
    p.add_argument("--confirmed-dir", default=DEFAULT_CONFIRMED_DIR)
    p.add_argument("--phase1-reference-csv", default=DEFAULT_PHASE1)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--queue2-regions", default=DEFAULT_QUEUE2_REGIONS)
    p.add_argument("--folds", default=DEFAULT_FOLDS)
    p.add_argument("--grid-id", default="pricefm_stage_c_manifest_20260618")
    p.add_argument("--write", type=parse_bool, default=True)
    p.add_argument("--allow-retest", type=parse_bool, default=False)
    return p


def parse_csv(value, cast=str):
    if value is None or str(value).strip() in {"", "all"}:
        return []
    return [cast(x.strip()) for x in str(value).split(",") if x.strip()]


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def read_csv_required(path, context):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required CSV: {}".format(context, path))
    return pd.read_csv(path)


def require_columns(frame, columns, context):
    missing = set(columns) - set(frame.columns)
    if missing:
        raise ValueError("{} missing columns: {}".format(context, sorted(missing)))


def numeric(series):
    return pd.to_numeric(series, errors="coerce")


def git_head():
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=str(repo_path(".")),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            check=False,
        )
    except OSError:
        return ""
    if proc.returncode != 0:
        return ""
    return proc.stdout.strip()


def load_region_scores(config_path, phase1_reference_csv):
    cfg = load_config(config_path)
    spec = pricefm_block(cfg)
    audit_path = repo_path(Path(spec["interim_dir"]) / "audit_missingness_ranges.csv")
    audit = read_csv_required(audit_path, "PriceFM audit")
    phase1 = read_csv_required(phase1_reference_csv, "PriceFM Phase-I reference")
    phase1 = phase1.rename(columns={
        "target_country": "region",
        "AQL": "phase1_AQL",
        "MAE": "phase1_MAE",
        "RMSE": "phase1_RMSE",
    })
    price = audit[audit["feature"].astype(str).eq("price")].copy()
    if price.empty:
        raise ValueError("Audit file has no price rows.")
    price["spread_p99_p01"] = numeric(price["p99"]) - numeric(price["p01"])
    price["tail_range"] = numeric(price["max"]) - numeric(price["min"])
    cols = [
        "region", "min", "p01", "median", "p99", "max", "negative_rate",
        "zero_rate", "spread_p99_p01", "tail_range",
    ]
    merged = price[cols].merge(phase1, on="region", how="left", validate="one_to_one")
    missing = merged[merged["phase1_AQL"].isna()]
    if not missing.empty:
        raise ValueError(
            "Missing Phase-I reference metrics for regions: {}".format(
                sorted(missing["region"].astype(str).tolist())
            )
        )
    configured = [str(x) for x in spec["regions"]]
    merged = merged[merged["region"].astype(str).isin(set(configured))].copy()
    return merged.sort_values("region").reset_index(drop=True), configured


def graph_summary(region, all_regions):
    d1 = get_k_hop_regions(region, all_regions, 1)
    d2 = get_k_hop_regions(region, all_regions, 2)
    return {
        "degree1_n": int(len(d1)),
        "degree2_n": int(len(d2)),
        "degree1_regions": "|".join(d1),
        "degree2_regions": "|".join(d2),
    }


def score_index(scores):
    require_columns(scores, ["region"], "region scores")
    out = {}
    for _, row in scores.iterrows():
        region = str(row["region"])
        if region in out:
            raise ValueError("Duplicate region in score universe: {}".format(region))
        out[region] = row.to_dict()
    return out


def existing_region_caution(region, evaluated):
    sub = evaluated[evaluated["region"].astype(str).eq(str(region))].copy()
    if sub.empty:
        return ""
    if sub["promotion_label"].astype(str).eq("evaluated_loss").any():
        return "existing_fold_exception"
    rel = numeric(sub.get("rel_delta", pd.Series(dtype=float))).abs()
    if not rel.empty and rel.min() < 0.025:
        return "narrow_existing_win"
    worst_group = sub.get("worst_horizon_group")
    worst_delta = numeric(sub.get("worst_horizon_delta", pd.Series(dtype=float)))
    if worst_group is not None and (worst_group.astype(str).eq("1-24") & (worst_delta > 0.5)).any():
        return "short_horizon_fragile_existing_win"
    return "partial_region_completion"


def region_role(region, scores):
    score = scores.get(str(region), {})
    phase1 = float(score.get("phase1_AQL", float("nan")))
    negative = float(score.get("negative_rate", 0.0))
    spread = float(score.get("spread_p99_p01", 0.0))
    degree1 = int(score.get("degree1_n", 0) or 0)
    if phase1 >= 10.0:
        return "hard_phase1_region"
    if negative >= 0.035:
        return "negative_price_region"
    if spread >= 570.0:
        return "high_spread_region"
    if degree1 >= 6:
        return "high_graph_degree_region"
    return "diverse_stage_c_region"


def base_manifest_row(region, fold, queue, priority, scores, all_regions):
    region = str(region)
    fold = int(fold)
    score = scores[region]
    out = {
        "region": region,
        "fold": fold,
        "queue": queue,
        "stage_c_priority": int(priority),
        "recommended_next_gate": "median_screen",
        "selection_split": "val",
        "audit_split": "test",
        "selection_metric": "AQL",
        "selection_unit": "original",
        "target_quantile": 0.50,
        "paper_quantiles": "0.10,0.25,0.45,0.50,0.55,0.75,0.90",
        "candidate_strategy": "qdesn_al_exal_rhs_ns_exact_chunked_local_median",
        "allowed_final_methods": (
            "qdesn_exal_rhs_ns_exact_chunked,"
            "qdesn_al_rhs_ns_exact_chunked,"
            "normal_rhs_ns,normal_scaled_ridge"
        ),
        "input_scope": "local_target_only",
        "output_scope": "target_region_path",
        "feature_policy": "target_only",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "local_only_not_pricefm_graph",
        "shrink_intercept": False,
        "qdesn_likelihoods": "al,exal",
        "beta_prior": "rhs_ns",
        "exact_chunking": True,
        "cleanup_binary_artifacts": True,
        "preserve_pricefm_as_benchmark_only": True,
    }
    for key in [
        "phase1_AQL", "phase1_MAE", "phase1_RMSE", "median",
        "spread_p99_p01", "tail_range", "negative_rate", "zero_rate",
        "min", "p01", "p99", "max",
    ]:
        if key in score:
            out[key] = score[key]
    out.update(graph_summary(region, all_regions))
    return out


def build_completion_rows(scores, all_regions, evaluated, folds, allow_retest=False):
    require_columns(evaluated, ["region", "fold"], "evaluated Stage-B panel")
    evaluated = evaluated.copy()
    evaluated["region"] = evaluated["region"].astype(str)
    evaluated["fold"] = evaluated["fold"].astype(int)
    evaluated_pairs = set(zip(evaluated["region"], evaluated["fold"]))
    configured = set(scores)
    rows = []
    for region in sorted(evaluated["region"].unique()):
        if region not in configured:
            raise ValueError("evaluated region {} missing from score universe".format(region))
        have = sorted(evaluated.loc[evaluated["region"].eq(region), "fold"].astype(int).unique())
        if not have or len(have) >= len(folds):
            continue
        caution = existing_region_caution(region, evaluated)
        for fold in folds:
            pair = (region, int(fold))
            if pair in evaluated_pairs and not bool(allow_retest):
                continue
            row = base_manifest_row(region, fold, QUEUE_COMPLETION, 0, scores, all_regions)
            row["rationale"] = "complete_partial_stage_b_region"
            row["caution_label"] = caution
            row["evaluated_folds"] = "|".join(str(x) for x in have)
            rows.append(row)
    return rows


def build_new_region_rows(scores, all_regions, queue2_regions, folds, evaluated, allow_retest=False):
    evaluated_pairs = set(zip(evaluated["region"].astype(str), evaluated["fold"].astype(int)))
    evaluated_regions = set(evaluated["region"].astype(str))
    rows = []
    missing = [r for r in queue2_regions if r not in scores]
    if missing:
        raise ValueError("queue2 regions missing from score universe: {}".format(sorted(missing)))
    dup = sorted({r for r in queue2_regions if queue2_regions.count(r) > 1})
    if dup:
        raise ValueError("duplicate queue2 regions: {}".format(dup))
    for region in queue2_regions:
        if region in evaluated_regions and not bool(allow_retest):
            raise ValueError(
                "queue2 region {} already has evaluated Stage-B rows; use completion queue or allow-retest".format(
                    region
                )
            )
        role = region_role(region, scores)
        for fold in folds:
            pair = (region, int(fold))
            if pair in evaluated_pairs and not bool(allow_retest):
                continue
            row = base_manifest_row(region, fold, QUEUE_NEW_REGION, 1, scores, all_regions)
            row["rationale"] = role
            row["caution_label"] = "new_region_unverified"
            row["evaluated_folds"] = ""
            rows.append(row)
    return rows


def build_exception_rows(scores, all_regions, exceptions):
    if exceptions is None or exceptions.empty:
        return []
    require_columns(exceptions, ["region", "fold"], "Stage-B exceptions")
    rows = []
    for _, exc in exceptions.sort_values(["region", "fold"]).iterrows():
        region = str(exc["region"])
        fold = int(exc["fold"])
        if region not in scores:
            raise ValueError("exception region {} missing from score universe".format(region))
        row = base_manifest_row(region, fold, QUEUE_EXCEPTION, 0, scores, all_regions)
        row["recommended_next_gate"] = "short_horizon_rescue"
        row["candidate_strategy"] = "targeted_short_horizon_qdesn_rhs_ns_rescue"
        row["rationale"] = str(exc.get("exception_label", "stage_b_exception"))
        row["caution_label"] = str(exc.get("exception_label", "stage_b_exception"))
        row["evaluated_folds"] = str(fold)
        for key in [
            "best_method", "best_AQL", "pricefm_AQL", "delta", "rel_delta",
            "worst_horizon_group", "worst_horizon_delta",
        ]:
            if key in exc.index:
                row["exception_{}".format(key)] = exc[key]
        rows.append(row)
    return rows


def validate_manifest(manifest, all_regions, folds):
    require_columns(manifest, ["region", "fold", "queue", "recommended_next_gate"], "Stage-C manifest")
    if manifest.duplicated(["region", "fold"]).any():
        dup = manifest[manifest.duplicated(["region", "fold"], keep=False)]
        raise ValueError("Stage-C manifest has duplicate region/fold rows:\n{}".format(
            dup[["region", "fold", "queue"]].to_string(index=False)
        ))
    region_set = set(str(x) for x in all_regions)
    bad_regions = sorted(set(manifest["region"].astype(str)) - region_set)
    if bad_regions:
        raise ValueError("Stage-C manifest has unknown regions: {}".format(bad_regions))
    fold_set = set(int(x) for x in folds)
    bad_folds = sorted(set(manifest["fold"].astype(int)) - fold_set)
    if bad_folds:
        raise ValueError("Stage-C manifest has invalid folds: {}".format(bad_folds))
    required_text = [
        "rationale", "input_scope", "spatial_information_set",
        "candidate_strategy", "allowed_final_methods",
    ]
    for col in required_text:
        if col not in manifest.columns or manifest[col].astype(str).str.strip().eq("").any():
            raise ValueError("Stage-C manifest has empty required column: {}".format(col))


def build_manifest(scores_frame, all_regions, evaluated, exceptions, queue2_regions, folds, allow_retest=False):
    scores = score_index(scores_frame)
    folds = [int(x) for x in folds]
    evaluated = evaluated.copy()
    evaluated["region"] = evaluated["region"].astype(str)
    evaluated["fold"] = evaluated["fold"].astype(int)
    completion = build_completion_rows(scores, all_regions, evaluated, folds, allow_retest=allow_retest)
    new_regions = build_new_region_rows(
        scores,
        all_regions,
        [str(x) for x in queue2_regions],
        folds,
        evaluated,
        allow_retest=allow_retest,
    )
    manifest = pd.DataFrame(completion + new_regions)
    if manifest.empty:
        raise ValueError("Stage-C manifest is empty.")
    manifest = manifest.sort_values(["stage_c_priority", "queue", "region", "fold"]).reset_index(drop=True)
    validate_manifest(manifest, all_regions, folds)
    exception_rows = pd.DataFrame(build_exception_rows(scores, all_regions, exceptions))
    if not exception_rows.empty:
        exception_rows = exception_rows.sort_values(["region", "fold"]).reset_index(drop=True)
    return manifest, exception_rows


def queue_summary(manifest, exception_rows):
    rows = []
    for queue, sub in manifest.groupby("queue"):
        rows.append({
            "queue": queue,
            "n_rows": int(sub.shape[0]),
            "n_regions": int(sub["region"].nunique()),
            "n_region_folds": int(sub[["region", "fold"]].drop_duplicates().shape[0]),
            "n_unique_folds": int(sub["fold"].nunique()),
            "priority_min": int(sub["stage_c_priority"].min()),
            "priority_max": int(sub["stage_c_priority"].max()),
            "recommended_next_gate": "|".join(sorted(sub["recommended_next_gate"].astype(str).unique())),
        })
    if exception_rows is not None and not exception_rows.empty:
        rows.append({
            "queue": QUEUE_EXCEPTION,
            "n_rows": int(exception_rows.shape[0]),
            "n_regions": int(exception_rows["region"].nunique()),
            "n_region_folds": int(exception_rows[["region", "fold"]].drop_duplicates().shape[0]),
            "n_unique_folds": int(exception_rows["fold"].nunique()),
            "priority_min": int(exception_rows["stage_c_priority"].min()),
            "priority_max": int(exception_rows["stage_c_priority"].max()),
            "recommended_next_gate": "|".join(sorted(exception_rows["recommended_next_gate"].astype(str).unique())),
        })
    return pd.DataFrame(rows).sort_values(["priority_min", "queue"]).reset_index(drop=True)


def deferred_regions(scores_frame, evaluated, manifest, exceptions):
    evaluated_regions = set(evaluated["region"].astype(str))
    manifest_regions = set(manifest["region"].astype(str))
    exception_regions = set(exceptions["region"].astype(str)) if exceptions is not None and not exceptions.empty else set()
    rows = []
    for _, row in scores_frame.sort_values("region").iterrows():
        region = str(row["region"])
        if region in evaluated_regions or region in manifest_regions or region in exception_regions:
            continue
        out = row.to_dict()
        out["deferred_reason"] = "queue3_family_followup"
        rows.append(out)
    return pd.DataFrame(rows)


def markdown_value(value):
    if isinstance(value, float):
        if pd.isna(value):
            return ""
        return "{:.6g}".format(value)
    if pd.isna(value):
        return ""
    return str(value).replace("\n", " ").replace("|", "\\|")


def markdown_table(frame, columns=None):
    if frame is None or frame.empty:
        return "_No rows._"
    if columns is not None:
        frame = frame[[col for col in columns if col in frame.columns]].copy()
    cols = list(frame.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame.iterrows():
        lines.append("| " + " | ".join(markdown_value(row[col]) for col in cols) + " |")
    return "\n".join(lines)


def write_report(out_dir, args, manifest, exceptions, queue_counts, deferred):
    path = out_dir / "stage_c_manifest_report.md"
    with open(path, "w") as f:
        f.write("# PriceFM Stage-C Manifest\n\n")
        f.write("Grid id: `{}`\n\n".format(args.grid_id))
        f.write("This manifest is a launch-planning artifact. It does not fit models.\n\n")
        f.write("## Queues\n\n")
        f.write(markdown_table(queue_counts))
        f.write("\n\n## Candidate Manifest\n\n")
        f.write(markdown_table(
            manifest,
            [
                "region", "fold", "queue", "stage_c_priority", "rationale",
                "caution_label", "phase1_AQL", "negative_rate",
                "degree1_n", "degree2_n", "recommended_next_gate",
            ],
        ))
        f.write("\n\n## Exception Rescue Queue\n\n")
        f.write(markdown_table(
            exceptions,
            [
                "region", "fold", "queue", "rationale", "exception_best_method",
                "exception_best_AQL", "exception_pricefm_AQL", "exception_delta",
                "exception_worst_horizon_group", "exception_worst_horizon_delta",
                "recommended_next_gate",
            ],
        ))
        f.write("\n\n## Deferred Regions\n\n")
        f.write(markdown_table(
            deferred,
            ["region", "phase1_AQL", "negative_rate", "spread_p99_p01", "deferred_reason"],
        ))
        f.write("\n\n## Gate Discipline\n\n")
        f.write("- Median selection is candidate generation, not promotion.\n")
        f.write("- Seed robustness is required for fragile candidates.\n")
        f.write("- Seven paper quantiles and cached PriceFM comparison are required before `confirmed_win`.\n")
        f.write("- FI fold 3 remains an exception and is not included in the generic manifest.\n")
        f.write("- Binary R artifacts must be cleaned after successful metrics and figures.\n")
    return path


def prepare(args):
    confirmed_dir = repo_path(args.confirmed_dir)
    out_dir = repo_path(args.output_dir)
    folds = parse_csv(args.folds, int)
    queue2_regions = parse_csv(args.queue2_regions, str)
    if not folds:
        raise ValueError("folds must be nonempty.")
    if not queue2_regions:
        raise ValueError("queue2-regions must be nonempty.")

    scores, all_regions = load_region_scores(args.config, args.phase1_reference_csv)
    confirmed = read_csv_required(confirmed_dir / "confirmed_stage_b_panel.csv", "confirmed Stage-B panel")
    evaluated = read_csv_required(confirmed_dir / "evaluated_stage_b_panel.csv", "evaluated Stage-B panel")
    exceptions = read_csv_required(confirmed_dir / "stage_b_exceptions.csv", "Stage-B exceptions")
    require_columns(confirmed, ["region", "fold", "promotion_label"], "confirmed Stage-B panel")
    if not confirmed["promotion_label"].astype(str).eq("confirmed_win").all():
        raise ValueError("confirmed Stage-B panel contains non-confirmed rows.")

    manifest, exception_rows = build_manifest(
        scores,
        all_regions,
        evaluated,
        exceptions,
        queue2_regions,
        folds,
        allow_retest=bool(args.allow_retest),
    )
    deferred = deferred_regions(scores, evaluated, manifest, exception_rows)
    counts = queue_summary(manifest, exception_rows)

    if bool(args.write):
        out_dir.mkdir(parents=True, exist_ok=True)
        scores.to_csv(out_dir / "stage_c_region_score_universe.csv", index=False)
        manifest.to_csv(out_dir / "stage_c_candidate_manifest.csv", index=False)
        exception_rows.to_csv(out_dir / "stage_c_exception_rescue_queue.csv", index=False)
        counts.to_csv(out_dir / "stage_c_queue_summary.csv", index=False)
        deferred.to_csv(out_dir / "stage_c_deferred_regions.csv", index=False)
        report = write_report(out_dir, args, manifest, exception_rows, counts, deferred)
        write_json(out_dir / "summary.json", {
            "status": "completed",
            "grid_id": str(args.grid_id),
            "repo_head": git_head(),
            "confirmed_dir": config_path_value(confirmed_dir),
            "output_dir": config_path_value(out_dir),
            "queue2_regions": queue2_regions,
            "folds": folds,
            "allow_retest": bool(args.allow_retest),
            "n_candidate_rows": int(manifest.shape[0]),
            "n_candidate_regions": int(manifest["region"].nunique()),
            "n_exception_rows": int(exception_rows.shape[0]),
            "n_deferred_regions": int(deferred.shape[0]),
            "queue_counts": counts.to_dict("records"),
            "outputs": {
                "candidate_manifest": config_path_value(out_dir / "stage_c_candidate_manifest.csv"),
                "exception_rescue_queue": config_path_value(out_dir / "stage_c_exception_rescue_queue.csv"),
                "queue_summary": config_path_value(out_dir / "stage_c_queue_summary.csv"),
                "region_score_universe": config_path_value(out_dir / "stage_c_region_score_universe.csv"),
                "deferred_regions": config_path_value(out_dir / "stage_c_deferred_regions.csv"),
                "report": config_path_value(report),
            },
        })

    return {
        "status": "completed",
        "write": bool(args.write),
        "output_dir": config_path_value(out_dir),
        "n_candidate_rows": int(manifest.shape[0]),
        "n_candidate_regions": int(manifest["region"].nunique()),
        "n_exception_rows": int(exception_rows.shape[0]),
        "n_deferred_regions": int(deferred.shape[0]),
        "queue_counts": counts.to_dict("records"),
    }


def main():
    args = parser().parse_args()
    summary = prepare(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
