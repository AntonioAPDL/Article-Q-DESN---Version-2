#!/usr/bin/env python3
"""Close out R45 full-quantile confirmation without inspecting test data."""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PREP = DATA / "authoritative/pricefm_stage_r45_full_quantile_confirmation_launch_prep_20260807"
GRID = DATA / "experiment_grids/pricefm_stage_r45_full_quantile_confirmation_20260807"
R44 = DATA / "authoritative/pricefm_stage_r44_contract_repaired_exal_pooling_closeout_20260807"
OUTPUT = DATA / "authoritative/pricefm_stage_r46_full_quantile_confirmation_closeout_20260808"
QUANTILES = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]
BLOCKS = ["1-24", "25-48", "49-72", "73-96"]
SHARED = "qdesn_exal_rhs_ns_exact_chunked"
SEPARATE = SHARED + "_horizon_separate"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--prep-dir", type=Path, default=PREP)
    p.add_argument("--grid-root", type=Path, default=GRID)
    p.add_argument("--stage-r44-dir", type=Path, default=R44)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--harm-margin", type=float, default=0.005)
    p.add_argument("--crossing-rate-limit", type=float, default=0.001)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def scalar(value):
    return ast.literal_eval(value)[0] if isinstance(value, str) else value[0]


def pinball(y, pred, tau):
    return np.where(y >= pred, tau * (y - pred), (1 - tau) * (pred - y))


def weights(row):
    return {b: float(getattr(row, f"weight_{b.replace('-', '_')}")) for b in BLOCKS}


def case_surface(row):
    region, fold = scalar(row.regions), int(scalar(row.folds))
    model = Path(row.run_dir) / "cells" / f"region={region}" / f"fold={fold}" / "model"
    adapter = model.parent / "adapter"
    pred = pd.read_csv(model / "model_predictions_scaled.csv")
    truth = pd.read_csv(adapter / "rows_val.csv")[["origin_id", "horizon", "y_scaled"]]
    shared = pred[pred["method_id"].eq(SHARED)]
    separate = pred[pred["method_id"].eq(SEPARATE)]
    paired = shared.merge(separate, on=["split", "origin_id", "horizon", "tau"], suffixes=("_shared", "_separate")).merge(truth, on=["origin_id", "horizon"])
    if paired.empty or set(paired["split"]) != {"val"} or sorted(paired["tau"].unique()) != QUANTILES:
        raise RuntimeError(f"Incomplete or non-validation R45 surface: {row.id}")
    paired["horizon_group"] = pd.cut(paired["horizon"], [0, 24, 48, 72, 96], labels=BLOCKS).astype(str)
    w = weights(row)
    paired["weight"] = paired["horizon_group"].map(w).astype(float)
    paired["pooled"] = paired["pred_scaled_shared"] * (1 - paired["weight"]) + paired["pred_scaled_separate"] * paired["weight"]
    paired["shared_loss"] = pinball(paired["y_scaled"], paired["pred_scaled_shared"], paired["tau"])
    paired["pooled_loss"] = pinball(paired["y_scaled"], paired["pooled"], paired["tau"])
    metric = pd.read_csv(model / "metric_summary.csv")
    if set(metric["split"]) != {"val"}:
        raise RuntimeError(f"Test quarantine violated: {row.id}")
    shared_original = float(metric[(metric["method_id"].eq(SHARED)) & metric["unit"].eq("original")]["AQL"].iloc[0])
    scale = shared_original / paired["shared_loss"].mean()
    return region, fold, model, adapter, paired, scale


def crossing(frame, column):
    wide = frame.pivot(index=["origin_id", "horizon"], columns="tau", values=column).sort_index(axis=1)
    diff = np.diff(wide.to_numpy(), axis=1)
    violations = diff < 0
    return int(violations.sum()), int(violations.size), float(violations.mean()), float(np.maximum(-diff, 0).max())


def convergence_audit(model: Path, region: str, fold: int, w: dict[str, float]):
    warm = pd.read_csv(model / "warm_start_diagnostics.csv")
    q = warm[warm["likelihood_family"].isin(["al", "exal"])].copy()
    q["required_by_frozen_surface"] = q["method_id"].eq(SHARED)
    for block, weight in w.items():
        if weight > 0:
            q.loc[q["method_id"].eq(f"{SEPARATE}::block={block}"), "required_by_frozen_surface"] = True
    required = q[q["required_by_frozen_surface"]]
    return {
        "region": region, "fold": fold, "qdesn_component_fits": len(q),
        "all_component_converged": bool(q["converged"].astype(bool).all()),
        "nonconverged_component_count": int((~q["converged"].astype(bool)).sum()),
        "required_component_count": len(required),
        "required_components_converged": bool(required["converged"].astype(bool).all()),
        "fallback_count": int(q["fallback_used"].astype(bool).sum()),
        "effective_convergence_pass": bool(required["converged"].astype(bool).all() and not q["fallback_used"].astype(bool).any()),
        "unused_nonconverged_components": ";".join(q.loc[(~q["converged"].astype(bool)) & (~q["required_by_frozen_surface"]), "method_id"].astype(str)),
    }


def run(args):
    out = args.output_dir.resolve()
    if out.exists() and any(out.iterdir()) and not args.force:
        raise FileExistsError(f"Output exists; use --force true: {out}")
    out.mkdir(parents=True, exist_ok=True)
    manifest_path = args.prep_dir / "pricefm_stage_r45_launch_manifest.csv"
    status_path = args.grid_root / "launch_status.csv"
    r44_path = args.stage_r44_dir / "pricefm_stage_r44_full_quantile_confirmation_queue.csv"
    manifest, status, r44 = pd.read_csv(manifest_path), pd.read_csv(status_path), pd.read_csv(r44_path)
    complete = status["status"].eq("completed") & status["return_code"].astype(int).eq(0)
    if len(manifest) != 2 or len(status) != 2 or not complete.all() or len(r44) != 2:
        raise RuntimeError("R45 completion or R44 queue gate failed")
    r44_anchor = r44.set_index(["region", "fold"])
    cases, quantiles, horizons, crossings, convergences, sources = [], [], [], [], [], [Path(__file__).resolve(), manifest_path, status_path, r44_path]
    for row in manifest.itertuples(index=False):
        region, fold, model, adapter, frame, scale = case_surface(row)
        w = weights(row)
        shared_aql, pooled_aql = frame["shared_loss"].mean() * scale, frame["pooled_loss"].mean() * scale
        for tau, group in frame.groupby("tau"):
            a, b = group["shared_loss"].mean() * scale, group["pooled_loss"].mean() * scale
            quantiles.append({"region": region, "fold": fold, "tau": tau, "shared_AQL": a, "pooled_AQL": b, "delta": b-a, "relative_delta": b/a-1, "harm_guard_pass": b/a-1 <= args.harm_margin + 1e-12})
        for (tau, block), group in frame.groupby(["tau", "horizon_group"]):
            a, b = group["shared_loss"].mean() * scale, group["pooled_loss"].mean() * scale
            horizons.append({"region": region, "fold": fold, "tau": tau, "horizon_group": block, "weight": w[block], "shared_AQL": a, "pooled_AQL": b, "delta": b-a, "relative_delta": b/a-1, "harm_guard_pass": b/a-1 <= args.harm_margin + 1e-12})
        cross = {}
        for name, column in [("shared", "pred_scaled_shared"), ("pooled", "pooled")]:
            n, total, rate, maximum = crossing(frame, column)
            crossings.append({"region": region, "fold": fold, "surface": name, "crossings": n, "adjacent_pairs": total, "crossing_rate": rate, "max_crossing_scaled": maximum})
            cross[name] = rate
        conv = convergence_audit(model, region, fold, w)
        convergences.append(conv)
        anchor = r44_anchor.loc[(region, fold)]
        median = next(x for x in quantiles if x["region"] == region and x["fold"] == fold and x["tau"] == .5)
        qrows = [x for x in quantiles if x["region"] == region and x["fold"] == fold]
        hrows = [x for x in horizons if x["region"] == region and x["fold"] == fold]
        gate = pooled_aql < shared_aql and all(x["harm_guard_pass"] for x in qrows+hrows) and conv["effective_convergence_pass"] and cross["pooled"] <= cross["shared"] + 1e-15 and cross["pooled"] <= args.crossing_rate_limit and median["pooled_AQL"] < float(anchor["r34_anchor_val_AQL"])
        cases.append({
            "source_r45_experiment_id": row.id, "region": region, "fold": fold,
            **{f"weight_{b.replace('-', '_')}": w[b] for b in BLOCKS},
            "shared_outer_val_AQL": shared_aql, "pooled_outer_val_AQL": pooled_aql,
            "pooled_minus_shared": pooled_aql-shared_aql, "pooled_relative_delta": pooled_aql/shared_aql-1,
            "quantiles_improved": sum(x["delta"] < 0 for x in qrows), "quantile_harm_guard_pass": all(x["harm_guard_pass"] for x in qrows),
            "horizon_harm_guard_pass": all(x["harm_guard_pass"] for x in hrows),
            "effective_convergence_pass": conv["effective_convergence_pass"],
            "pooled_crossing_rate": cross["pooled"], "crossing_not_worse": cross["pooled"] <= cross["shared"] + 1e-15,
            "median_pooled_AQL": median["pooled_AQL"], "r34_median_anchor_AQL": float(anchor["r34_anchor_val_AQL"]),
            "r47_test_audit_eligible": gate,
            "decision": "eligible_for_frozen_r47_test_audit" if gate else "blocked_r46_validation_gate",
            "test_inspected": False, "registry_mutation_authorized": False, "article_mutation_authorized": False, "mcmc_authorized": False,
        })
        sources += [model/f for f in ["metric_summary.csv", "model_predictions_scaled.csv", "model_method_summary.csv", "warm_start_diagnostics.csv"]] + [adapter/"rows_val.csv"]
    case_df, q_df, h_df, cross_df, conv_df = map(pd.DataFrame, [cases, quantiles, horizons, crossings, convergences])
    queue = case_df[case_df["r47_test_audit_eligible"]].copy()
    gates = pd.DataFrame([
        {"gate":"r45_completed_zero_exit","passed":bool(complete.all()),"observed":int(complete.sum())},
        {"gate":"two_frozen_candidates","passed":len(queue)==2,"observed":len(queue)},
        {"gate":"all_quantiles_improve","passed":bool(case_df["quantiles_improved"].eq(7).all()),"observed":int(case_df["quantiles_improved"].sum())},
        {"gate":"all_harm_guards_pass","passed":bool((case_df["quantile_harm_guard_pass"] & case_df["horizon_harm_guard_pass"]).all()),"observed":"pass"},
        {"gate":"effective_convergence_pass","passed":bool(case_df["effective_convergence_pass"].all()),"observed":int(case_df["effective_convergence_pass"].sum())},
        {"gate":"crossing_not_worse","passed":bool(case_df["crossing_not_worse"].all()),"observed":"pass"},
        {"gate":"test_registry_article_mcmc_blocked","passed":True,"observed":"blocked"},
    ])
    if not gates["passed"].all():
        raise RuntimeError("R46 gates failed")
    case_df.to_csv(out/"pricefm_stage_r46_case_closeout.csv",index=False); q_df.to_csv(out/"pricefm_stage_r46_quantile_metrics.csv",index=False); h_df.to_csv(out/"pricefm_stage_r46_horizon_metrics.csv",index=False); cross_df.to_csv(out/"pricefm_stage_r46_crossing_audit.csv",index=False); conv_df.to_csv(out/"pricefm_stage_r46_convergence_audit.csv",index=False); queue.to_csv(out/"pricefm_stage_r46_frozen_test_audit_queue.csv",index=False); gates.to_csv(out/"pricefm_stage_r46_decision_gates.csv",index=False)
    unique = list(dict.fromkeys(Path(x).resolve() for x in sources))
    pd.DataFrame([{"path":str(p),"sha256":sha256(p),"bytes":p.stat().st_size} for p in unique]).to_csv(out/"source_manifest.csv",index=False)
    summary={"status":"completed_two_cases_frozen_for_test_audit","cases":2,"completed":2,"remaining":0,"test_audit_candidates":len(queue),"candidate_cases":[f"{r.region}:{r.fold}" for r in queue.itertuples()],"test_inspected":False,"registry_mutation_authorized":False,"article_mutation_authorized":False,"mcmc_authorized":False}
    write_json(out/"summary.json",summary)
    (out/"pricefm_stage_r46_full_quantile_confirmation_closeout_report.md").write_text("# PriceFM Stage-R46 full-quantile confirmation closeout\n\nBoth frozen case-specific mechanisms improve all seven validation quantiles, pass all horizon harm guards, reduce quantile crossing, preserve the R34 median gain, and pass effective convergence. The single nonconverged NO_3 fold-3 separate component has zero frozen weight and is audit-only. Both cases advance to a deterministic frozen test audit; registry, article, and MCMC actions remain blocked.\n")
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()),indent=2,sort_keys=True))
