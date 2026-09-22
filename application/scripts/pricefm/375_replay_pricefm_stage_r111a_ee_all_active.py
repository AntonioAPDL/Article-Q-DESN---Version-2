#!/usr/bin/env python3
"""Replay frozen EE Q-DESN readouts with R110 EE and R111A FI/LV drivers."""

from __future__ import annotations

import argparse
from concurrent.futures import ProcessPoolExecutor, as_completed
import csv
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from typing import Any, Mapping

import numpy as np
import pandas as pd


SCRIPTS = Path(__file__).resolve().parent
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from pricefm_common import sha256_file  # noqa: E402
from pricefm_recursive_normal import deterministic_seed  # noqa: E402
from pricefm_recursive_quantile import QUANTILES  # noqa: E402
from pricefm_recursive_quantile_marginal import stratified_uniforms  # noqa: E402


DATA_ROOT = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
TAG = "pricefm_stage_r111a_ee_neighbor_driver_20260921"
DEFAULT_ROOT = DATA_ROOT / "campaigns" / TAG
R110_ROOT = DATA_ROOT / "campaigns/pricefm_stage_r110_direct_driver_20260921"
R110B_ROOT = DATA_ROOT / "authoritative/pricefm_stage_r110_frozen_qdesn_replay_20260921"
R108_ROOT = DATA_ROOT / "authoritative/pricefm_stage_r108_recursive_driver_decomposition_20260920"
R103_TAG = "pricefm_stage_r103_recursive_quantile_20260916"
FOLDS = (1, 2, 3)
ACTIVE_REGIONS = ("EE", "FI", "LV")
POLICY = "r111a_all_active_direct_drivers"


def load_script(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load script: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


R110 = load_script(
    SCRIPTS / "370_audit_pricefm_stage_r110_frozen_qdesn_replay.py", "r111a_r110"
)
R108 = R110.R108
R104 = R110.R104
CASE_RUNNER = R110.CASE_RUNNER


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--campaign-root", type=Path, default=DEFAULT_ROOT)
    value.add_argument("--data-root", type=Path, default=DATA_ROOT)
    value.add_argument("--mode", choices=("all", "case", "finalize"), default="all")
    value.add_argument("--fold", type=int, choices=FOLDS)
    value.add_argument("--posterior-paths", type=int, default=500)
    value.add_argument("--workers", type=int, default=3)
    value.add_argument("--force", action="store_true")
    return value


def atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True, default=str) + "\n")
    temporary.replace(path)


def artifact(role: str, path: Path, **extra: Any) -> dict[str, Any]:
    value = Path(path).resolve()
    return {
        "role": role,
        "path": str(value),
        "bytes": value.stat().st_size,
        "sha256": sha256_file(value),
        **extra,
    }


def normalized_times(values: Any) -> np.ndarray:
    return pd.to_datetime(np.asarray(values), utc=True).astype(str).to_numpy()


def validate_campaign(root: Path) -> dict[str, Any]:
    contract_path = root / "campaign_contract.json"
    contract = json.loads(contract_path.read_text())
    if (
        contract.get("stage") != "R111A"
        or contract.get("fit_regions") != ["FI", "LV"]
        or contract.get("replay_active_regions") != list(ACTIVE_REGIONS)
        or contract.get("posterior_paths") != 500
        or contract.get("test_access_authorized") is not False
        or contract.get("broad_all_region_launch_authorized") is not False
    ):
        raise RuntimeError("invalid R111A campaign contract")
    return contract


def r103_context(data_root: Path, region: str, fold: int) -> tuple[Path, dict, dict, dict]:
    config_path = (
        data_root / "launch_prep" / R103_TAG / "cases"
        / f"r103_{region.lower()}_f{fold}.json"
    )
    config = json.loads(config_path.read_text())
    context, scaler = CASE_RUNNER.validation_context(config)
    return config_path, config, context, scaler


def read_r111a_paths(
    root: Path,
    region: str,
    fold: int,
    source_context: Mapping[str, Any],
    target_anchors: np.ndarray,
    n_paths: int,
) -> tuple[np.ndarray, list[dict[str, Any]]]:
    output = root / "runs/outer_validation" / region / f"fold={fold}"
    terminal = R110.verify_relative_terminal(output, "completed_r111a_direct_case")
    if (
        terminal.get("stage") != "R111A"
        or terminal.get("phase") != "outer_validation"
        or terminal.get("region") != region
        or int(terminal.get("outer_fold")) != fold
        or int(terminal.get("paths")) != n_paths
    ):
        raise RuntimeError(f"R111A {region} driver identity mismatch")
    rows_path = output / "evaluation_rows.csv"
    manifest_path = output / "prediction_paths_manifest.json"
    binary_path = output / "prediction_paths_scaled.bin"
    rows = pd.read_csv(rows_path)
    manifest = json.loads(manifest_path.read_text())
    n_origins = len(source_context["anchors"])
    n_rows = n_origins * 96
    if (
        set(rows.split.astype(str)) != {"val"}
        or len(rows) != n_rows
        or int(manifest.get("n_rows", -1)) != n_rows
        or int(manifest.get("n_paths", -1)) != n_paths
        or manifest.get("storage_order") != "R_column_major"
        or manifest.get("dtype") != "float64_little_endian"
    ):
        raise RuntimeError(f"R111A {region} path geometry changed")
    expected_origin = np.repeat(np.arange(n_origins), 96)
    expected_horizon = np.tile(np.arange(1, 97), n_origins)
    if (
        not np.array_equal(rows.origin_id.to_numpy(int), expected_origin)
        or not np.array_equal(rows.horizon.to_numpy(int), expected_horizon)
    ):
        raise RuntimeError(f"R111A {region} rows are not origin-major")
    stored_anchors = normalized_times(
        rows.groupby("origin_id", sort=True).origin_market_time.first()
    )
    source_anchors = normalized_times(source_context["anchors"])
    if not np.array_equal(stored_anchors, source_anchors) or not np.array_equal(
        stored_anchors, normalized_times(target_anchors)
    ):
        raise RuntimeError(f"R111A {region} and EE validation anchors disagree")
    truth = np.asarray(source_context["truth"], dtype=float)
    if not np.allclose(
        rows.y_scaled.to_numpy(float), truth.reshape(-1), rtol=0.0, atol=5e-7
    ):
        raise RuntimeError(f"R111A {region} response scale disagrees with its source window")
    flat = np.fromfile(binary_path, dtype="<f8")
    if flat.size != n_rows * n_paths:
        raise RuntimeError(f"R111A {region} path size changed")
    paths = flat.reshape((n_rows, n_paths), order="F").T.reshape(n_paths, n_origins, 96)
    if not np.isfinite(paths).all():
        raise RuntimeError(f"R111A {region} paths are nonfinite")
    return paths, [
        artifact("r111a_driver_terminal", output / "terminal.json", region=region, fold=fold),
        artifact("r111a_driver_rows", rows_path, region=region, fold=fold),
        artifact("r111a_driver_path_manifest", manifest_path, region=region, fold=fold),
        artifact("r111a_driver_paths", binary_path, region=region, fold=fold),
    ]


def case_dir(root: Path, fold: int) -> Path:
    return root / "replay/cases/region=EE" / f"fold={fold}"


def valid_case(path: Path) -> bool:
    try:
        terminal = R110.verify_relative_terminal(
            path, "completed_r111a_ee_all_active_replay_case"
        )
        return (
            terminal.get("model_fit_started") is False
            and terminal.get("posterior_paths") == 500
            and terminal.get("test_opened") is False
        )
    except (OSError, ValueError, KeyError, json.JSONDecodeError, RuntimeError):
        return False


def run_case(
    data_root_value: str,
    campaign_root_value: str,
    fold: int,
    n_paths: int,
    force: bool,
) -> dict[str, Any]:
    for name in (
        "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
        "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS",
    ):
        os.environ[name] = "1"
    data_root = Path(data_root_value).resolve()
    root = Path(campaign_root_value).resolve()
    destination = case_dir(root, fold)
    if valid_case(destination) and not force:
        return json.loads((destination / "terminal.json").read_text())
    validate_campaign(root)

    ee_config_path, ee_config, ee_context, ee_scaler = r103_context(data_root, "EE", fold)
    if list(ee_context["active_regions"]) != list(ACTIVE_REGIONS):
        raise RuntimeError("frozen EE readout does not use EE/FI/LV")
    if int(ee_config["posterior_paths"]) != n_paths:
        raise RuntimeError("R111A must preserve the frozen R103 path count")
    family = R108.selected_family(data_root, "EE")
    beta, evidence = R104.read_beta_draws(ee_config, family, n_paths)
    support, records = R108.training_support(ee_config)
    evidence.extend(records)
    evidence.extend([
        artifact("r103_ee_case_config", ee_config_path),
        artifact("r103_ee_scaler", ee_scaler["scaler_path"]),
        artifact("r111a_campaign_contract", root / "campaign_contract.json"),
        artifact("executed_source", Path(__file__)),
        artifact("executed_source", SCRIPTS / "364_audit_pricefm_stage_r108_recursive_driver_decomposition.py"),
        artifact("executed_source", SCRIPTS / "pricefm_recursive_quantile.py"),
        artifact("executed_source", SCRIPTS / "pricefm_recursive_driver_diagnostics.py"),
    ])

    target_paths, records = R110.read_r110_paths(
        R110_ROOT, "EE", fold, ee_context, n_paths
    )
    evidence.extend(records)
    neighbor_paths: dict[str, np.ndarray] = {}
    for region in ("FI", "LV"):
        config_path, _, context, scaler = r103_context(data_root, region, fold)
        paths, records = read_r111a_paths(
            root, region, fold, context, np.asarray(ee_context["anchors"]), n_paths
        )
        neighbor_paths[region] = paths
        evidence.extend(records)
        evidence.extend([
            artifact("r103_neighbor_case_config", config_path, region=region, fold=fold),
            artifact("r103_neighbor_scaler", scaler["scaler_path"], region=region, fold=fold),
        ])

    n_origins = len(ee_context["anchors"])
    prediction = np.empty((len(QUANTILES), n_origins, 96), dtype=float)
    diagnostic_rows: list[dict[str, Any]] = []
    origin_rows: list[dict[str, Any]] = []
    for origin_index in range(n_origins):
        uniforms = stratified_uniforms(
            n_paths,
            96,
            deterministic_seed(
                f"r111a_ee_f{fold}", family, origin_index, "paired_qdesn_uniforms"
            ),
        )
        result = R108.recursive_quantile_driver_forecast(
            ee_context,
            origin_index=origin_index,
            beta_draws=beta,
            seed=deterministic_seed(f"r111a_ee_f{fold}", origin_index),
            support=support,
            direct_design=None,
            uniforms=uniforms,
            external_panel={
                region: neighbor_paths[region][:, origin_index, :]
                for region in ("FI", "LV")
            },
            target_mode="external",
            target_external=target_paths[:, origin_index, :],
        )
        prediction[:, origin_index] = result["prediction"]
        for row in result["diagnostics"]:
            diagnostic_rows.append({
                "region": "EE", "fold": fold, "family": family,
                "policy": POLICY, "origin_index": origin_index, **row,
            })

    truth_original = R104.scaled_to_original(
        ee_context["truth"], ee_scaler["center"], ee_scaler["scale"]
    )
    prediction_original = R104.scaled_to_original(
        prediction, ee_scaler["center"], ee_scaler["scale"]
    )
    metric = pd.DataFrame([{
        "region": "EE", "fold": fold, "family": family, "policy": POLICY,
        **R104.score_surface(truth_original, prediction_original),
        "posterior_paths": n_paths,
        "selection_split": "fold1_training_inner_only_neighbor_driver_policy",
        "evaluation_split": "outer_validation_frozen_r103_ee_readout",
        "test_opened": False,
    }])
    horizons = R104.horizon_metrics(
        "EE", fold, family, POLICY, truth_original, prediction_original
    )
    for origin_index, anchor in enumerate(ee_context["anchors"]):
        origin_rows.append({
            "region": "EE", "fold": fold, "family": family, "policy": POLICY,
            "origin_index": origin_index, "anchor": str(anchor),
            **R104.score_surface(
                truth_original[origin_index : origin_index + 1],
                prediction_original[:, origin_index : origin_index + 1],
            ),
        })
    diagnostics = R108.aggregate_diagnostics(diagnostic_rows)

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=destination.name + ".tmp.", dir=destination.parent))
    try:
        metric.to_csv(temporary / "metrics.csv", index=False)
        horizons.to_csv(temporary / "horizon_metrics.csv", index=False)
        pd.DataFrame(origin_rows).to_csv(temporary / "origin_metrics.csv", index=False)
        diagnostics.to_csv(temporary / "driver_state_diagnostics.csv", index=False)
        pd.DataFrame(evidence).drop_duplicates(subset=["path", "sha256"]).sort_values(
            ["role", "path"]
        ).to_csv(temporary / "source_manifest.csv", index=False, quoting=csv.QUOTE_MINIMAL)
        np.savez_compressed(
            temporary / "validation_predictions.npz",
            prediction_scaled=prediction.astype(np.float32),
            truth_scaled=np.asarray(ee_context["truth"], dtype=np.float32),
            quantiles=np.asarray(QUANTILES, dtype=float),
            anchors=np.asarray(ee_context["anchors"], dtype=str),
            active_regions=np.asarray(ACTIVE_REGIONS, dtype=str),
        )
        records = []
        for path in sorted(temporary.iterdir()):
            if path.is_file() and path.name != "terminal.json":
                records.append({
                    "path": str((destination / path.name).resolve()),
                    "bytes": path.stat().st_size,
                    "sha256": sha256_file(path),
                })
        terminal = {
            "stage": "R111A",
            "status": "completed_r111a_ee_all_active_replay_case",
            "region": "EE",
            "fold": fold,
            "selected_family": family,
            "policy": POLICY,
            "active_regions": list(ACTIVE_REGIONS),
            "posterior_paths": n_paths,
            "n_origins": n_origins,
            "model_fit_started": False,
            "test_opened": False,
            "registry_mutated": False,
            "article_mutated": False,
            "artifacts": records,
        }
        atomic_json(temporary / "terminal.json", terminal)
        if destination.exists():
            shutil.rmtree(destination)
        temporary.rename(destination)
        return terminal
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def weighted(frame: pd.DataFrame, column: str = "AQL") -> float:
    return float(np.average(frame[column], weights=frame.n_loss_atoms))


def evaluate_gates(candidate: pd.DataFrame, horizons: pd.DataFrame, references: pd.DataFrame, reference_horizons: pd.DataFrame) -> pd.DataFrame:
    target = references[references.policy.eq("r110_direct_target_rhs_neighbors")]
    direct = references[references.policy.eq("r97_direct_reference")]
    candidate_aql = weighted(candidate)
    target_aql = weighted(target)
    direct_aql = weighted(direct)
    by_fold = candidate.set_index("fold").AQL / target.set_index("fold").AQL - 1.0
    late = horizons[horizons.horizon.ge(73)].copy()
    target_late = reference_horizons[
        reference_horizons.policy.eq("r110_direct_target_rhs_neighbors")
        & reference_horizons.horizon.ge(73)
    ].copy()
    late_aql = float(np.average(late.AQL, weights=late.n_origins))
    target_late_aql = float(np.average(target_late.AQL, weights=target_late.n_origins))
    values = [
        ("complete_3_of_3", len(candidate) == 3, len(candidate)),
        ("exactly_500_paths", bool(candidate.posterior_paths.eq(500).all()), int(candidate.posterior_paths.min())),
        ("pooled_gain_at_least_10pct_vs_r110_target_only", 1 - candidate_aql / target_aql >= 0.10, 1 - candidate_aql / target_aql),
        ("max_fold_harm_at_most_5pct_vs_r110_target_only", float(by_fold.max()) <= 0.05, float(by_fold.max())),
        ("pooled_aql_at_most_10pct_above_r97_direct", candidate_aql / direct_aql - 1 <= 0.10, candidate_aql / direct_aql - 1),
        ("late_horizon_gain_at_least_10pct_vs_r110_target_only", 1 - late_aql / target_late_aql >= 0.10, 1 - late_aql / target_late_aql),
        ("all_metrics_finite", bool(np.isfinite(candidate.select_dtypes(include=[np.number])).all().all()), float(np.isfinite(candidate.select_dtypes(include=[np.number])).all().all())),
    ]
    return pd.DataFrame(values, columns=["gate", "passed", "observed"])


def direct_driver_metrics(root: Path, data_root: Path) -> pd.DataFrame:
    rows = []
    selection = pd.read_csv(root / "final_region_selection.csv")
    for region in ("FI", "LV"):
        for fold in FOLDS:
            _, _, context, scaler = r103_context(data_root, region, fold)
            paths, _ = read_r111a_paths(
                root, region, fold, context, np.asarray(context["anchors"]), 500
            )
            output = root / "runs/outer_validation" / region / f"fold={fold}"
            prediction = pd.read_csv(output / "prediction_quantiles_scaled.csv")
            eval_rows = pd.read_csv(output / "evaluation_rows.csv")
            flat = paths.reshape(500, -1).T
            metric, _ = R110.load_script(
                SCRIPTS / "369_closeout_pricefm_stage_r110_direct_driver.py",
                f"r111a_direct_score_{region}_{fold}",
            ).score_paths(
                flat,
                prediction.y_scaled.to_numpy(float),
                eval_rows.horizon.to_numpy(int),
                scaler["scale"],
            )
            choice = selection[selection.region.eq(region)].iloc[0]
            rows.append({
                "region": region, "fold": fold, "readout": choice.readout,
                "prior_type": choice.prior_type, "tau0": choice.tau0,
                **metric, "test_opened": False,
            })
    return pd.DataFrame(rows)


def finalize(root: Path, data_root: Path) -> dict[str, Any]:
    contract = validate_campaign(root)
    cases = [case_dir(root, fold) for fold in FOLDS]
    if not all(valid_case(path) for path in cases):
        raise RuntimeError("R111A cannot close with incomplete EE replay cases")
    metrics = pd.concat([pd.read_csv(path / "metrics.csv") for path in cases], ignore_index=True)
    horizons = pd.concat([pd.read_csv(path / "horizon_metrics.csv") for path in cases], ignore_index=True)
    origins = pd.concat([pd.read_csv(path / "origin_metrics.csv") for path in cases], ignore_index=True)
    diagnostics = pd.concat([pd.read_csv(path / "driver_state_diagnostics.csv") for path in cases], ignore_index=True)
    r110b = pd.read_csv(R110B_ROOT / "pricefm_stage_r110_replay_case_metrics.csv")
    r108 = pd.read_csv(R108_ROOT / "pricefm_stage_r108_case_metrics.csv")
    references = pd.concat([
        r110b[r110b.region.eq("EE")],
        r108[r108.region.eq("EE") & r108.policy.isin((
            "r97_direct_reference", "self_rhs_neighbors", "oracle_all_active",
            "pricefm_quantile_paths_all_active",
        ))],
    ], ignore_index=True)
    r110b_h = pd.read_csv(R110B_ROOT / "pricefm_stage_r110_replay_horizon_metrics.csv")
    r108_h = pd.read_csv(R108_ROOT / "pricefm_stage_r108_horizon_metrics.csv")
    reference_horizons = pd.concat([
        r110b_h[r110b_h.region.eq("EE")],
        r108_h[r108_h.region.eq("EE") & r108_h.policy.isin((
            "r97_direct_reference", "self_rhs_neighbors", "oracle_all_active",
            "pricefm_quantile_paths_all_active",
        ))],
    ], ignore_index=True)
    gates = evaluate_gates(metrics, horizons, references, reference_horizons)
    passed = bool(gates.passed.all())
    direct = direct_driver_metrics(root, data_root)

    metrics.to_csv(root / "pricefm_stage_r111a_ee_replay_case_metrics.csv", index=False)
    horizons.to_csv(root / "pricefm_stage_r111a_ee_replay_horizon_metrics.csv", index=False)
    origins.to_csv(root / "pricefm_stage_r111a_ee_replay_origin_metrics.csv", index=False)
    diagnostics.to_csv(root / "pricefm_stage_r111a_ee_replay_state_diagnostics.csv", index=False)
    direct.to_csv(root / "pricefm_stage_r111a_neighbor_driver_metrics.csv", index=False)
    references.to_csv(root / "pricefm_stage_r111a_ee_references.csv", index=False)
    reference_horizons.to_csv(root / "pricefm_stage_r111a_ee_horizon_references.csv", index=False)
    gates.to_csv(root / "pricefm_stage_r111a_gates.csv", index=False)

    sources = []
    for path in cases:
        sources.append(artifact("r111a_replay_case_terminal", path / "terminal.json"))
        sources.extend(pd.read_csv(path / "source_manifest.csv").to_dict("records"))
    sources.extend([
        artifact("r111a_campaign_contract", root / "campaign_contract.json"),
        artifact("r110b_reference", R110B_ROOT / "pricefm_stage_r110_replay_case_metrics.csv"),
        artifact("r108_reference", R108_ROOT / "pricefm_stage_r108_case_metrics.csv"),
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
        "# PriceFM Stage-R111A EE neighbor-driver closeout", "",
        "R111A fits only FI and LV validation drivers, then replays the frozen R103 EE Q-DESN readout with the existing R110 EE target driver.",
        "No test data, registry, article, joint model, or MCMC fit is involved.", "",
        "## EE pooled AQL", "",
        *[f"- {policy}: `{value:.5f}`." for policy, value in by_policy.items()], "",
        f"- Mechanism gate: `{'PASS' if passed else 'FAIL'}`.", "",
        "## Gate ledger", "", gates.to_markdown(index=False), "",
        "A pass resolves only the EE neighbor-driver mechanism. Broad all-region launch and promotion remain blocked pending the separate BG readout question.",
    ]
    (root / "pricefm_stage_r111a_closeout.md").write_text("\n".join(report) + "\n")
    summary = {
        "stage": "R111A",
        "status": "completed_ee_neighbor_driver_closeout",
        "fit_regions": ["FI", "LV"],
        "direct_driver_cases_complete": len(direct),
        "direct_driver_cases_expected": 6,
        "replay_cases_complete": len(metrics),
        "replay_cases_expected": 3,
        "posterior_paths": 500,
        "all_gates_passed": passed,
        "ee_neighbor_mechanism_resolved": passed,
        "broad_all_region_launch_authorized": False,
        "next_stage": "R111B_BG_exposure_readout_design" if passed else "stop_and_diagnose_EE_neighbor_driver_transfer",
        "campaign_contract_sha256": contract["contract_sha256"],
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    atomic_json(root / "summary.json", summary)
    return summary


def run_all(args: argparse.Namespace) -> dict[str, Any]:
    tasks = list(FOLDS)
    failures = []
    with ProcessPoolExecutor(max_workers=min(args.workers, len(tasks))) as executor:
        futures = {
            executor.submit(
                run_case,
                str(args.data_root.resolve()),
                str(args.campaign_root.resolve()),
                fold,
                args.posterior_paths,
                args.force,
            ): fold
            for fold in tasks
        }
        for future in as_completed(futures):
            try:
                future.result()
            except Exception as error:
                failures.append(f"fold{futures[future]}: {error}")
    if failures:
        raise RuntimeError("R111A replay failures: " + "; ".join(failures))
    return finalize(args.campaign_root.resolve(), args.data_root.resolve())


def main() -> None:
    args = parser().parse_args()
    if args.posterior_paths != 500:
        raise RuntimeError("R111A requires exactly 500 posterior paths")
    if args.mode == "case":
        if args.fold is None:
            raise RuntimeError("case mode requires --fold")
        result = run_case(
            str(args.data_root.resolve()), str(args.campaign_root.resolve()),
            args.fold, args.posterior_paths, args.force,
        )
    elif args.mode == "finalize":
        result = finalize(args.campaign_root.resolve(), args.data_root.resolve())
    else:
        result = run_all(args)
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
