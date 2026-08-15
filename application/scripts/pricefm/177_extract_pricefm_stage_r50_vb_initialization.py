#!/usr/bin/env python3
"""Verify rebuilt R50 design hashes and recover prediction-equivalent VB starts."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

from pricefm_common import parse_bool, write_json

ARTIFACT = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT / "application/data_local/pricefm"
PREP = DATA / "authoritative/pricefm_stage_r50_mcmc_confirmation_launch_prep_20260809"
RUNS = DATA / "runs/pricefm_stage_r50_mcmc_confirmation_20260809"
R47_RUN = DATA / "runs/pricefm_stage_r47_frozen_test_audit_20260808/r47_no3_f3_nestedhorizonsep_81e260ce/cells/region=NO_3/fold=3"
TAUS = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]

SHARED = "qdesn_exal_rhs_ns_exact_chunked"
SEPARATE = SHARED + "_horizon_separate"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--prep-dir", type=Path, default=PREP)
    p.add_argument("--adapter-dir", type=Path, default=RUNS / "frozen_adapter")
    p.add_argument("--stage-r47-cell", type=Path, default=R47_RUN)
    p.add_argument("--tolerance", type=float, default=1e-8)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def parameter_row(params, component, tau):
    method = SHARED if component == "shared_static" else SEPARATE + "::block=1-24"
    row = params[(params.method_id == method) & np.isclose(params.tau, tau)]
    if len(row) != 1:
        raise RuntimeError(f"Expected one parameter row for {method} tau={tau}")
    return row.iloc[0]


def run(args):
    init_dir = args.prep_dir / "initialization"
    if init_dir.exists() and any(init_dir.iterdir()) and not args.force:
        raise FileExistsError(f"Output exists: {init_dir}")
    init_dir.mkdir(parents=True, exist_ok=True)
    old_manifest = json.loads((args.stage_r47_cell / "adapter/adapter_manifest.json").read_text())
    new_manifest = json.loads((args.adapter_dir / "adapter_manifest.json").read_text())
    hash_rows = []
    for split in ("train", "val", "test"):
        for field in ("X_sha256", "y_sha256", "rows_sha256"):
            old, new = old_manifest["splits"][split][field], new_manifest["splits"][split][field]
            hash_rows.append({"split": split, "field": field, "r47": old, "r50": new, "passed": old == new})
    old_map = old_manifest["feature_manifest"]["feature_map_matrix_sha256"]
    new_map = new_manifest["feature_manifest"]["feature_map_matrix_sha256"]
    hash_rows.append({"split": "all", "field": "feature_map_matrix_sha256", "r47": old_map, "r50": new_map, "passed": old_map == new_map})
    hashes = pd.DataFrame(hash_rows)
    hashes.to_csv(args.prep_dir / "pricefm_stage_r50_design_replay_audit.csv", index=False)
    if not hashes.passed.all():
        raise RuntimeError("R50 rebuilt design does not match R47")

    x_val = np.loadtxt(args.adapter_dir / "X_val.csv", delimiter=",")
    rows_val = pd.read_csv(args.adapter_dir / "rows_val.csv")
    pred = pd.read_csv(args.stage_r47_cell / "model/model_predictions_scaled.csv")
    params = pd.read_csv(args.stage_r47_cell / "model/model_parameter_summary.csv")
    records = []
    for component, method in (("shared_static", SHARED), ("horizon_1_24", SEPARATE)):
        idx = np.ones(len(rows_val), dtype=bool) if component == "shared_static" else rows_val.horizon.between(1, 24).to_numpy()
        X = x_val[idx]
        key = rows_val.loc[idx, ["origin_id", "horizon"]].copy()
        for tau in TAUS:
            target = pred[(pred.method_id == method) & (pred.split == "val") & np.isclose(pred.tau, tau)][["origin_id", "horizon", "pred_scaled"]]
            merged = key.merge(target, on=["origin_id", "horizon"], how="left", validate="one_to_one")
            if merged.pred_scaled.isna().any():
                raise RuntimeError(f"Missing R47 predictions for {component} tau={tau}")
            beta, _, rank, _ = np.linalg.lstsq(X, merged.pred_scaled.to_numpy(), rcond=None)
            replay = X @ beta
            max_diff = float(np.max(np.abs(replay - merged.pred_scaled.to_numpy())))
            if max_diff > args.tolerance:
                raise RuntimeError(f"VB replay failed for {component} tau={tau}: {max_diff}")
            beta_path = init_dir / f"{component}_tau{int(round(tau * 100)):02d}_beta.csv"
            np.savetxt(beta_path, beta, delimiter=",")
            prow = parameter_row(params, component, tau)
            records.append({
                "component": component, "tau": tau, "beta_path": str(beta_path),
                "n_features": len(beta), "design_rank": int(rank), "prediction_replay_max_abs_diff": max_diff,
                "sigma_init": float(prow.sigma), "gamma_init": float(prow.gamma),
                "parameter_identification": "prediction_equivalent_minimum_norm_start",
            })
    frame = pd.DataFrame(records)
    path = args.prep_dir / "pricefm_stage_r50_vb_initialization_manifest.csv"
    frame.to_csv(path, index=False)
    gates_path = args.prep_dir / "pricefm_stage_r50_prelaunch_gates.csv"
    gates = pd.read_csv(gates_path)
    gates.loc[gates.gate == "design_rebuild_pending", ["gate", "passed", "observed"]] = ["design_rebuild_exact", True, "10/10 hashes matched R47"]
    gates.loc[gates.gate == "vb_initialization_replay_pending", ["gate", "passed", "observed"]] = ["vb_initialization_replay", True, f"14/14 within {args.tolerance:g}"]
    gates.to_csv(gates_path, index=False)
    summary = {
        "status": "design_and_initialization_replay_passed", "design_hashes_passed": int(hashes.passed.sum()),
        "initializations": len(frame), "max_prediction_replay_abs_diff": float(frame.prediction_replay_max_abs_diff.max()),
        "launch_authorized": True,
    }
    write_json(args.prep_dir / "initialization_summary.json", summary)
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
