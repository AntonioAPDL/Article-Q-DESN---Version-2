#!/usr/bin/env python3
"""Close out PriceFM R110 validation-only direct-driver results."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import yaml


TAG = "pricefm_stage_r110_direct_driver_20260921"
DEFAULT_ROOT = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/campaigns") / TAG
R109 = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r109_saved_driver_quality_20260921")
QUANTILES = np.asarray([0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90])
REGIONS = ("BG", "EE", "BE")


def sha256_file(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def weighted(frame: pd.DataFrame, value: str, weight: str = "n_points") -> float:
    return float(np.average(frame[value], weights=frame[weight]))


def score_paths(paths: np.ndarray, truth: np.ndarray, horizon: np.ndarray, scale: float) -> tuple[dict, pd.DataFrame]:
    q_scaled = np.quantile(paths, QUANTILES, axis=1).T
    error = truth[:, None] - q_scaled
    loss = np.maximum(QUANTILES[None, :] * error, (QUANTILES[None, :] - 1.0) * error)
    overall = {
        "AQL": float(loss.mean() * scale),
        "coverage_10_90": float(np.mean((truth >= q_scaled[:, 0]) & (truth <= q_scaled[:, -1]))),
        "mean_width_10_90": float(np.mean(q_scaled[:, -1] - q_scaled[:, 0]) * scale),
        "median_MAE": float(np.mean(np.abs(truth - q_scaled[:, 3])) * scale),
        "n_points": int(truth.size),
        "n_loss_atoms": int(loss.size),
        "posterior_paths": int(paths.shape[1]),
    }
    rows = []
    for value in sorted(set(horizon)):
        idx = horizon == value
        rows.append({
            "horizon": int(value), "AQL": float(loss[idx].mean() * scale),
            "coverage_10_90": float(np.mean((truth[idx] >= q_scaled[idx, 0]) & (truth[idx] <= q_scaled[idx, -1]))),
            "mean_width_10_90": float(np.mean(q_scaled[idx, -1] - q_scaled[idx, 0]) * scale),
            "n_origins": int(idx.sum()),
        })
    return overall, pd.DataFrame(rows)


def evaluate_gate(case: pd.DataFrame, horizon: pd.DataFrame, reference_case: pd.DataFrame, reference_horizon: pd.DataFrame) -> pd.DataFrame:
    rhs = reference_case[reference_case.driver_method.eq("normal_rhs_paths")]
    pricefm = reference_case[reference_case.driver_method.eq("cached_pricefm_quantiles")]
    candidate_aql = weighted(case, "AQL")
    rhs_aql = weighted(rhs.assign(n_points=rhs.n_points), "AQL")
    pricefm_aql = weighted(pricefm.assign(n_points=pricefm.n_points), "AQL")
    candidate_late = weighted(horizon[horizon.horizon.ge(73)].rename(columns={"n_origins": "n_points"}), "AQL")
    rhs_late_frame = reference_horizon[
        reference_horizon.driver_method.eq("normal_rhs_paths") & reference_horizon.horizon.ge(73)
    ].rename(columns={"n_origins": "n_points"})
    rhs_late = weighted(rhs_late_frame, "AQL")
    candidate_coverage = weighted(case, "coverage_10_90")
    rhs_coverage = weighted(rhs.assign(n_points=rhs.n_points), "coverage_10_90")
    region_candidate = case.groupby("region").apply(lambda x: weighted(x, "AQL"), include_groups=False)
    region_rhs = rhs.groupby("region").apply(lambda x: weighted(x.assign(n_points=x.n_points), "AQL"), include_groups=False)
    max_region_harm = float((region_candidate / region_rhs - 1.0).max())
    values = [
        ("complete_9_of_9", len(case) == 9 and case.posterior_paths.eq(500).all(), len(case)),
        ("pooled_aql_gain_at_least_30pct_vs_rhs", 1 - candidate_aql / rhs_aql >= 0.30, 1 - candidate_aql / rhs_aql),
        ("aql_at_most_25pct_above_pricefm", candidate_aql <= 1.25 * pricefm_aql, candidate_aql / pricefm_aql - 1),
        ("late_horizon_gain_at_least_30pct_vs_rhs", 1 - candidate_late / rhs_late >= 0.30, 1 - candidate_late / rhs_late),
        ("coverage_distance_harm_at_most_0p02", abs(candidate_coverage - 0.8) <= abs(rhs_coverage - 0.8) + 0.02, abs(candidate_coverage - 0.8) - abs(rhs_coverage - 0.8)),
        ("max_region_harm_at_most_10pct", max_region_harm <= 0.10, max_region_harm),
    ]
    return pd.DataFrame(values, columns=["gate", "passed", "observed"])


def closeout(root: Path) -> dict:
    root = root.resolve()
    contract = json.loads((root / "campaign_contract.json").read_text())
    data_config = Path(next(csv_path for csv_path in [root / "configs/BG/fold_1.yaml"] if csv_path.exists()))
    cfg = yaml.safe_load(data_config.read_text())["pricefm_desn_smoke"]
    processed = Path(yaml.safe_load(Path(cfg["data_config"]).read_text())["pricefm"]["processed_dir"])
    case_rows = []
    horizon_rows = []
    source_rows = []
    for region in REGIONS:
        for fold in (1, 2, 3):
            output = root / "runs/outer_validation" / region / f"fold={fold}"
            terminal = json.loads((output / "terminal.json").read_text())
            manifest = json.loads((output / "prediction_paths_manifest.json").read_text())
            if terminal.get("status") != "completed_r110_case" or terminal.get("test_opened") is not False:
                raise RuntimeError(f"invalid final terminal for {region} fold {fold}")
            if int(manifest["n_paths"]) != 500:
                raise RuntimeError("R110 requires 500 final paths")
            values = np.fromfile(output / "prediction_paths_scaled.bin", dtype="<f8")
            paths = values.reshape((int(manifest["n_rows"]), 500), order="F")
            predictions = pd.read_csv(output / "prediction_quantiles_scaled.csv")
            rows = pd.read_csv(output / "evaluation_rows.csv")
            if paths.shape[0] != len(predictions) or len(rows) != len(predictions) or not np.isfinite(paths).all():
                raise RuntimeError("invalid final prediction surface")
            scaler_path = processed / "scalers" / f"fold_{fold}" / "per_region_separate_xy_scalers.joblib"
            scaler = joblib.load(scaler_path)[region]["y_scaler"]
            scale = float(np.asarray(scaler.scale_).reshape(-1)[0])
            metric, hm = score_paths(paths, predictions.y_scaled.to_numpy(float), rows.horizon.to_numpy(int), scale)
            selection = pd.read_csv(root / "final_region_selection.csv")
            choice = selection[selection.region.eq(region)].iloc[0]
            case_rows.append({
                "region": region, "fold": fold, "readout": choice.readout,
                "prior_type": choice.prior_type, "tau0": choice.tau0,
                **metric, "selection_split": "fold1_training_inner_only",
                "evaluation_split": "outer_validation", "test_opened": False,
            })
            hm.insert(0, "fold", fold)
            hm.insert(0, "region", region)
            horizon_rows.append(hm)
            for path in output.iterdir():
                if path.is_file():
                    source_rows.append({"region": region, "fold": fold, "path": str(path), "bytes": path.stat().st_size, "sha256": sha256_file(path)})

    cases = pd.DataFrame(case_rows)
    horizons = pd.concat(horizon_rows, ignore_index=True)
    reference_cases = pd.read_csv(R109 / "pricefm_stage_r109_driver_case_metrics.csv")
    reference_horizons = pd.read_csv(R109 / "pricefm_stage_r109_driver_horizon_metrics.csv")
    reference_cases = reference_cases[reference_cases.region.isin(REGIONS)].copy()
    reference_horizons = reference_horizons[reference_horizons.region.isin(REGIONS)].copy()
    gates = evaluate_gate(cases, horizons, reference_cases, reference_horizons)
    passed = bool(gates.passed.all())
    cases.to_csv(root / "pricefm_stage_r110_driver_case_metrics.csv", index=False)
    horizons.to_csv(root / "pricefm_stage_r110_driver_horizon_metrics.csv", index=False)
    gates.to_csv(root / "pricefm_stage_r110_candidate_gates.csv", index=False)
    pd.DataFrame(source_rows).to_csv(root / "final_source_manifest.csv", index=False)

    rhs = reference_cases[reference_cases.driver_method.eq("normal_rhs_paths")].assign(n_points=lambda x: x.n_points)
    pricefm = reference_cases[reference_cases.driver_method.eq("cached_pricefm_quantiles")].assign(n_points=lambda x: x.n_points)
    report = [
        "# PriceFM Stage-R110 direct-driver closeout", "",
        "R110 is a validation-only driver experiment on BG, EE, and BE. It does not mutate the registry or article.", "",
        "## Pooled result", "",
        f"- R110 selected direct-driver AQL: `{weighted(cases, 'AQL'):.5f}`.",
        f"- R102B Normal-RHS driver AQL: `{weighted(rhs, 'AQL'):.5f}`.",
        f"- Cached PriceFM driver AQL: `{weighted(pricefm, 'AQL'):.5f}`.",
        f"- Direct-driver gate: `{'PASS' if passed else 'FAIL'}`.", "",
        "## Gate ledger", "",
        gates.to_markdown(index=False), "",
        "Passing authorizes only the separately controlled frozen-QDESN target-driver replay. Test, registry, article, joint-model, and MCMC work remain blocked.",
    ]
    (root / "pricefm_stage_r110_direct_driver_closeout.md").write_text("\n".join(report) + "\n")
    summary = {
        "stage": "R110", "status": "completed_direct_driver_closeout",
        "cases_complete": len(cases), "cases_expected": 9,
        "posterior_paths": 500, "all_gates_passed": passed,
        "downstream_replay_authorized": passed,
        "next_stage": "R110_target_driver_frozen_qdesn_replay" if passed else "stop_and_diagnose_direct_driver",
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
        "campaign_contract_sha256": contract["contract_sha256"],
    }
    write_json(root / "summary.json", summary)
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--campaign-root", type=Path, default=DEFAULT_ROOT)
    args = parser.parse_args()
    print(json.dumps(closeout(args.campaign_root), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
