#!/usr/bin/env python3
"""Replay and close out the bounded R111B BG exposure-aligned readout."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import os
from pathlib import Path
import shutil
import tempfile
from typing import Any

import numpy as np
import pandas as pd


HERE = Path(__file__).resolve().parent
if str(HERE) not in os.sys.path:
    os.sys.path.insert(0, str(HERE))

from pricefm_common import sha256_file, write_json  # noqa: E402
from pricefm_recursive_normal import deterministic_seed  # noqa: E402
from pricefm_recursive_quantile import QUANTILES, draw_beta_posterior  # noqa: E402
from pricefm_recursive_quantile_marginal import stratified_uniforms  # noqa: E402


DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
TAG = "pricefm_stage_r111b_bg_exposure_readout_20260922"
DEFAULT_ROOT = DATA / "campaigns" / TAG
R103 = DATA / "launch_prep/pricefm_stage_r103_recursive_quantile_20260916"
R108 = DATA / "authoritative/pricefm_stage_r108_recursive_driver_decomposition_20260920"
R110 = DATA / "campaigns/pricefm_stage_r110_direct_driver_20260921"
R110B = DATA / "authoritative/pricefm_stage_r110_frozen_qdesn_replay_20260921"
POLICY = "r111b_exposure_aligned_readout"
FOLDS = (1, 2, 3)


def load_script(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


R103_RUNNER = load_script(HERE / "345_run_pricefm_stage_r103_quantile_case.py", "r111b_r103")
R104 = load_script(HERE / "350_audit_pricefm_stage_r104_forecast_operator.py", "r111b_r104")
R108_MODULE = load_script(HERE / "364_audit_pricefm_stage_r108_recursive_driver_decomposition.py", "r111b_r108")
R110_MODULE = load_script(HERE / "370_audit_pricefm_stage_r110_frozen_qdesn_replay.py", "r111b_r110")


def artifact(role: str, path: Path, **extra: Any) -> dict[str, Any]:
    path = path.resolve()
    return {
        "role": role, "path": str(path), "bytes": path.stat().st_size,
        "sha256": sha256_file(path), **extra,
    }


def validate_campaign(root: Path) -> dict[str, Any]:
    contract = json.loads((root / "campaign_contract.json").read_text())
    if (
        contract.get("stage") != "R111B"
        or contract.get("selected_family") != "al"
        or contract.get("posterior_paths") != 500
        or contract.get("test_access_authorized") is not False
        or contract.get("broad_all_region_launch_authorized") is not False
    ):
        raise RuntimeError("invalid R111B campaign contract")
    return contract


def selected_arm(root: Path) -> str:
    value = json.loads((root / "selected_exposure_arm.json").read_text())
    arm = str(value.get("selected_arm"))
    if (
        value.get("selection_split") != "fold1_training_crossfit_only"
        or value.get("test_opened") is not False
        or arm not in {"teacher_recent", "recursive_mean", "mixed_equal"}
    ):
        raise RuntimeError("invalid R111B selected exposure arm")
    return arm


def final_beta(root: Path, fold: int, n_paths: int) -> tuple[dict[float, np.ndarray], list[dict[str, Any]]]:
    result: dict[float, np.ndarray] = {}
    evidence = []
    for tau in QUANTILES:
        label = str(tau).replace(".", "p")
        output = root / "runs/final" / f"fold={fold}" / f"tau={label}"
        terminal_path = output / "terminal.json"
        terminal = json.loads(terminal_path.read_text())
        if (
            terminal.get("status") != "completed_r111b_al_readout"
            or terminal.get("phase") != "final_al_readout"
            or terminal.get("family") != "al"
            or abs(float(terminal.get("tau")) - float(tau)) > 1e-12
            or terminal.get("converged") is not True
            or terminal.get("test_opened") is not False
            or terminal.get("prior_center_from_initializer") is not False
        ):
            raise RuntimeError(f"invalid R111B final readout: fold {fold}, tau {tau}")
        for row in terminal["artifacts"]:
            path = output / row["path"]
            if not path.is_file() or sha256_file(path) != row["sha256"]:
                raise RuntimeError(f"changed R111B final artifact: {path}")
        p = int(terminal["p"])
        mean = np.fromfile(output / "beta_mean.bin", dtype="<f8")
        covariance = np.fromfile(output / "beta_cov.bin", dtype="<f8").reshape(p, p)
        result[float(tau)] = draw_beta_posterior(
            mean, covariance, n_paths,
            deterministic_seed("r111b", "BG", fold, tau, "beta"),
        )
        evidence.extend([
            artifact("r111b_final_terminal", terminal_path, fold=fold, tau=float(tau)),
            artifact("r111b_final_beta_mean", output / "beta_mean.bin", fold=fold, tau=float(tau)),
            artifact("r111b_final_beta_cov", output / "beta_cov.bin", fold=fold, tau=float(tau)),
        ])
    return result, evidence


def case_dir(root: Path, fold: int) -> Path:
    return root / "replay" / f"fold={fold}"


def valid_case(path: Path) -> bool:
    terminal_path = path / "terminal.json"
    if not terminal_path.is_file():
        return False
    try:
        value = json.loads(terminal_path.read_text())
        return (
            value.get("status") == "completed_r111b_bg_replay_case"
            and value.get("posterior_paths") == 500
            and value.get("test_opened") is False
            and value.get("executed_source_sha256") == sha256_file(Path(__file__))
            and all(
                Path(row["path"]).is_file()
                and sha256_file(Path(row["path"])) == row["sha256"]
                for row in value["artifacts"]
            )
        )
    except (OSError, KeyError, json.JSONDecodeError):
        return False


def run_case(root: Path, fold: int, force: bool = False) -> dict[str, Any]:
    for name in (
        "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
        "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS",
    ):
        os.environ[name] = "1"
    validate_campaign(root)
    arm = selected_arm(root)
    destination = case_dir(root, fold)
    if valid_case(destination) and not force:
        return json.loads((destination / "terminal.json").read_text())
    config_path = R103 / "cases" / f"r103_bg_f{fold}.json"
    config = json.loads(config_path.read_text())
    context, scaler = R103_RUNNER.validation_context(config)
    if list(context["active_regions"]) != ["BG"]:
        raise RuntimeError("R111B BG replay is no longer target-only")
    beta, evidence = final_beta(root, fold, 500)
    support, records = R108_MODULE.training_support(config)
    evidence.extend(records)
    target_paths, records = R110_MODULE.read_r110_paths(R110, "BG", fold, context, 500)
    evidence.extend(records)
    evidence.extend([
        artifact("r103_bg_case_config", config_path, fold=fold),
        artifact("r103_bg_scaler", scaler["scaler_path"], fold=fold),
        artifact("r111b_campaign_contract", root / "campaign_contract.json"),
        artifact("r111b_selected_arm", root / "selected_exposure_arm.json"),
        artifact("executed_source", Path(__file__)),
        artifact("executed_source", HERE / "pricefm_recursive_driver_diagnostics.py"),
        artifact("executed_source", HERE / "pricefm_recursive_quantile.py"),
    ])
    n_origins = len(context["anchors"])
    prediction = np.empty((len(QUANTILES), n_origins, 96), dtype=float)
    diagnostics = []
    origin_rows = []
    for origin_index in range(n_origins):
        uniforms = stratified_uniforms(
            500, 96,
            deterministic_seed("r111b", "BG", fold, origin_index, "uniforms"),
        )
        result = R108_MODULE.recursive_quantile_driver_forecast(
            context, external_panel={}, origin_index=origin_index,
            beta_draws=beta,
            seed=deterministic_seed("r111b", "BG", fold, origin_index),
            target_mode="external", target_external=target_paths[:, origin_index, :],
            support=support, direct_design=None, uniforms=uniforms,
        )
        prediction[:, origin_index] = result["prediction"]
        diagnostics.extend({
            "region": "BG", "fold": fold, "family": "al", "policy": POLICY,
            "arm": arm, "origin_index": origin_index, **row,
        } for row in result["diagnostics"])

    truth_original = R104.scaled_to_original(context["truth"], scaler["center"], scaler["scale"])
    prediction_original = R104.scaled_to_original(prediction, scaler["center"], scaler["scale"])
    metric = pd.DataFrame([{
        "region": "BG", "fold": fold, "family": "al", "policy": POLICY,
        "arm": arm, **R104.score_surface(truth_original, prediction_original),
        "posterior_paths": 500,
        "selection_split": "fold1_training_crossfit_only",
        "evaluation_split": "outer_validation_frozen_R110_driver",
        "test_opened": False,
    }])
    horizons = R104.horizon_metrics("BG", fold, "al", POLICY, truth_original, prediction_original)
    horizons["arm"] = arm
    for origin_index, anchor in enumerate(context["anchors"]):
        origin_rows.append({
            "region": "BG", "fold": fold, "family": "al", "policy": POLICY,
            "arm": arm, "origin_index": origin_index, "anchor": str(anchor),
            **R104.score_surface(
                truth_original[origin_index : origin_index + 1],
                prediction_original[:, origin_index : origin_index + 1],
            ),
        })
    state = R108_MODULE.aggregate_diagnostics(diagnostics)

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=destination.name + ".tmp.", dir=destination.parent))
    try:
        metric.to_csv(temporary / "metrics.csv", index=False)
        horizons.to_csv(temporary / "horizon_metrics.csv", index=False)
        pd.DataFrame(origin_rows).to_csv(temporary / "origin_metrics.csv", index=False)
        state.to_csv(temporary / "driver_state_diagnostics.csv", index=False)
        pd.DataFrame(evidence).drop_duplicates(subset=["path", "sha256"]).sort_values(
            ["role", "path"]
        ).to_csv(temporary / "source_manifest.csv", index=False, quoting=csv.QUOTE_MINIMAL)
        np.savez_compressed(
            temporary / "validation_predictions.npz",
            prediction_scaled=prediction.astype(np.float32),
            truth_scaled=np.asarray(context["truth"], dtype=np.float32),
            quantiles=np.asarray(QUANTILES), anchors=np.asarray(context["anchors"], dtype=str),
        )
        artifacts = [
            {"path": str((destination / path.name).resolve()), "bytes": path.stat().st_size,
             "sha256": sha256_file(path)}
            for path in sorted(temporary.iterdir()) if path.is_file()
        ]
        terminal = {
            "stage": "R111B", "status": "completed_r111b_bg_replay_case",
            "region": "BG", "fold": fold, "selected_family": "al", "selected_arm": arm,
            "policy": POLICY, "posterior_paths": 500, "n_origins": n_origins,
            "executed_source_sha256": sha256_file(Path(__file__)),
            "test_opened": False, "registry_mutated": False, "article_mutated": False,
            "artifacts": artifacts,
        }
        write_json(temporary / "terminal.json", terminal)
        if destination.exists():
            shutil.rmtree(destination)
        temporary.rename(destination)
        return terminal
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def weighted(frame: pd.DataFrame) -> float:
    return float(np.average(frame.AQL, weights=frame.n_loss_atoms))


def evaluate_gates(metrics: pd.DataFrame, references: pd.DataFrame) -> pd.DataFrame:
    candidate = weighted(metrics)
    r110_rows = references[references.policy.eq("r110_direct_target_rhs_neighbors")]
    r97_rows = references[references.policy.eq("r97_direct_reference")]
    if set(metrics.fold) != set(FOLDS) or set(r110_rows.fold) != set(FOLDS) or set(r97_rows.fold) != set(FOLDS):
        raise RuntimeError("R111B gate inputs do not cover all three folds")
    r110 = weighted(r110_rows)
    r97 = weighted(r97_rows)
    fold_reference = r110_rows.set_index("fold").AQL
    fold_change = metrics.set_index("fold").AQL / fold_reference - 1.0
    values = [
        ("complete_3_of_3", len(metrics) == 3, len(metrics)),
        ("exactly_500_paths", bool(metrics.posterior_paths.eq(500).all()), int(metrics.posterior_paths.min())),
        ("pooled_gain_at_least_10pct_vs_r110", 1 - candidate / r110 >= 0.10, 1 - candidate / r110),
        ("max_fold_harm_at_most_5pct_vs_r110", float(fold_change.max()) <= 0.05, float(fold_change.max())),
        ("pooled_aql_at_most_10pct_above_r97", candidate / r97 - 1 <= 0.10, candidate / r97 - 1),
        ("raw_crossing_rate_at_most_1pct", float(metrics.AQCR.max()) <= 0.01, float(metrics.AQCR.max())),
        ("all_metrics_finite", bool(np.isfinite(metrics.select_dtypes(include=[np.number])).all().all()), 1.0),
    ]
    return pd.DataFrame(values, columns=["gate", "passed", "observed"])


def finalize(root: Path) -> dict[str, Any]:
    contract = validate_campaign(root)
    cases = [case_dir(root, fold) for fold in FOLDS]
    if not all(valid_case(path) for path in cases):
        raise RuntimeError("R111B cannot close with incomplete BG replay cases")
    metrics = pd.concat([pd.read_csv(path / "metrics.csv") for path in cases], ignore_index=True)
    horizons = pd.concat([pd.read_csv(path / "horizon_metrics.csv") for path in cases], ignore_index=True)
    origins = pd.concat([pd.read_csv(path / "origin_metrics.csv") for path in cases], ignore_index=True)
    diagnostics = pd.concat([pd.read_csv(path / "driver_state_diagnostics.csv") for path in cases], ignore_index=True)
    r110b = pd.read_csv(R110B / "pricefm_stage_r110_replay_case_metrics.csv")
    r108 = pd.read_csv(R108 / "pricefm_stage_r108_case_metrics.csv")
    references = pd.concat([
        r110b[r110b.region.eq("BG")],
        r108[r108.region.eq("BG") & r108.policy.isin((
            "r97_direct_reference", "self_rhs_neighbors", "oracle_all_active",
            "pricefm_quantile_paths_all_active",
        ))],
    ], ignore_index=True)
    gates = evaluate_gates(metrics, references)
    passed = bool(gates.passed.all())
    metrics.to_csv(root / "pricefm_stage_r111b_bg_case_metrics.csv", index=False)
    horizons.to_csv(root / "pricefm_stage_r111b_bg_horizon_metrics.csv", index=False)
    origins.to_csv(root / "pricefm_stage_r111b_bg_origin_metrics.csv", index=False)
    diagnostics.to_csv(root / "pricefm_stage_r111b_bg_state_diagnostics.csv", index=False)
    references.to_csv(root / "pricefm_stage_r111b_bg_references.csv", index=False)
    gates.to_csv(root / "pricefm_stage_r111b_gates.csv", index=False)
    sources = []
    for path in cases:
        sources.append(artifact("r111b_replay_terminal", path / "terminal.json"))
        sources.extend(pd.read_csv(path / "source_manifest.csv").to_dict("records"))
    sources.extend([
        artifact("r111b_campaign_contract", root / "campaign_contract.json"),
        artifact("r111b_selected_arm", root / "selected_exposure_arm.json"),
        artifact("r110b_reference", R110B / "pricefm_stage_r110_replay_case_metrics.csv"),
        artifact("r108_reference", R108 / "pricefm_stage_r108_case_metrics.csv"),
        artifact("executed_source", Path(__file__)),
    ])
    pd.DataFrame(sources).drop_duplicates(subset=["path", "sha256"]).sort_values(
        ["role", "path"]
    ).to_csv(root / "final_source_manifest.csv", index=False, quoting=csv.QUOTE_MINIMAL)
    by_policy = pd.concat([
        references[["policy", "AQL", "n_loss_atoms"]],
        metrics[["policy", "AQL", "n_loss_atoms"]],
    ]).groupby("policy", sort=True).apply(weighted, include_groups=False)
    report = [
        "# PriceFM Stage-R111B BG exposure-aligned readout closeout", "",
        "R111B changes only the BG AL-RHS readout training exposure. The DESN, tau0,",
        "Normal-RHS driver policy, outer-validation paths, and seven-quantile grid are frozen.",
        "No test, registry, article, joint-model, or MCMC work is involved.", "",
        "## Pooled BG AQL", "",
        *[f"- {policy}: `{value:.5f}`." for policy, value in by_policy.items()], "",
        f"- Selected exposure arm: `{selected_arm(root)}`.",
        f"- Mechanism gate: `{'PASS' if passed else 'FAIL'}`.", "",
        "## Gate ledger", "", gates.to_markdown(index=False), "",
        "A pass permits design of a prospective all-region validation campaign; it does not authorize that launch or promotion.",
    ]
    (root / "pricefm_stage_r111b_closeout.md").write_text("\n".join(report) + "\n")
    summary = {
        "stage": "R111B", "status": "completed_bg_exposure_readout_closeout",
        "selected_arm": selected_arm(root), "selected_family": "al",
        "cases_complete": len(metrics), "cases_expected": 3, "posterior_paths": 500,
        "all_gates_passed": passed, "bg_exposure_mechanism_resolved": passed,
        "broad_all_region_launch_authorized": False,
        "next_stage": "R112_prospective_all_region_design" if passed else "stop_recursive_redesign_retain_R97",
        "campaign_contract_sha256": contract["contract_sha256"],
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
    }
    write_json(root / "summary.json", summary)
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--campaign-root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--mode", choices=("case", "finalize"), required=True)
    parser.add_argument("--fold", type=int, choices=FOLDS)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    root = args.campaign_root.resolve()
    if args.mode == "case":
        if args.fold is None:
            raise RuntimeError("case mode requires --fold")
        result = run_case(root, args.fold, args.force)
    else:
        result = finalize(root)
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
