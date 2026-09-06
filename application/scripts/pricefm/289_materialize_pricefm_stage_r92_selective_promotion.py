#!/usr/bin/env python3
"""Materialize the frozen PriceFM R91 case replacements as the R92 authority."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import pandas as pd
import yaml


REPO_ROOT = Path(__file__).resolve().parents[3]
ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA_ROOT = ARTIFACT_REPO / "application/data_local/pricefm"
HISTORICAL = DATA_ROOT / "authoritative/pricefm_full_surface_decision_closeout_20260704"
R88 = DATA_ROOT / "authoritative/pricefm_stage_r88_repaired_exal_surface_closeout_20260905"
R89 = DATA_ROOT / "authoritative/pricefm_stage_r89_validation_family_selection_20260905"
R90_PREP = DATA_ROOT / "authoritative/pricefm_stage_r90_scoring_only_test_prep_20260905"
R90_GRID = DATA_ROOT / "experiment_grids/pricefm_stage_r90_scoring_only_test_audit_20260905"
R91 = DATA_ROOT / "authoritative/pricefm_stage_r91_test_audit_and_promotion_20260905"
R69B_CASE_MANIFEST = (
    DATA_ROOT
    / "experiment_grids/pricefm_stage_r69b_bounded_cran111_independent_vb_20260831/case_manifest.csv"
)
DEFAULT_OUTPUT = (
    REPO_ROOT
    / "application/data_local/pricefm/authoritative/pricefm_stage_r92_selective_promotion_20260905"
)
PRODUCTION_OUTPUT_ROOT = REPO_ROOT / "application/data_local/pricefm/authoritative"

TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
HORIZON_GROUPS = ("1-24", "25-48", "49-72", "73-96")
EXPECTED_PROMOTIONS = {
    ("AT", 1): "exal",
    ("BE", 2): "exal",
    ("DK_1", 3): "exal",
    ("DK_2", 2): "exal",
    ("DK_2", 3): "exal",
    ("ES", 1): "al",
    ("FR", 3): "exal",
    ("HU", 1): "exal",
    ("IT_CNOR", 1): "exal",
    ("IT_NORD", 3): "exal",
    ("LV", 3): "exal",
    ("SE_3", 1): "exal",
}

FROZEN_HASHES = {
    HISTORICAL / "pricefm_full_surface_decision_registry.csv":
        "d45c43b6d2dd3b163ca1d3cd0b140ce0e582797aaea0a3db012a7d74293e4802",
    HISTORICAL / "pricefm_full_surface_horizon_diagnostics.csv":
        "2455116d61d62607819f3013e484a7c0fa1b0fc47a2052e6b29d17ba786a81eb",
    R88 / "source_manifest.csv":
        "9d4ed86f90d281353f9e9dfa33143140d3ffc7ac26090977db819fffda5dd60e",
    R89 / "source_manifest.csv":
        "445c32bbebebdc9998baf41f4183158e2aa5ca843b64a1cef28f7e99eec6e936",
    R90_PREP / "source_manifest.csv":
        "e221a80c28e1c46f35d5c3574ca585ed098deb9074f9b9948dd5e00684e94fe5",
    R91 / "source_manifest.csv":
        "a4bf9a752f5d37aefb95455d9da80a78736f59d758df995a04da66fb6f909bd5",
    R91 / "pricefm_stage_r91_promotion_queue.csv":
        "3a5f4899ed1e01421af2376f723d6b95d44220d604304e64844cbb232ee7ef3d",
    R69B_CASE_MANIFEST:
        "f9c058c7e601d688b14c1a6396ebe9342a37142f0cd39c95f8a0b9fda2ae5f08",
    R89 / "pricefm_stage_r89_selected_atom_manifest.csv":
        "9e6092c19194fb039eaff4268a20094cc75af218bb7ec9905c21e897b03007e3",
    R89 / "pricefm_stage_r89_family_selection.csv":
        "eade594432cda676a7cbdc8c0e19d068345223d5d10d11f8a7cc0b38d8bb6867",
    R90_GRID / "task_manifest.csv":
        "a130a43e1a5e8834fafa7d7214d16ae8650377ef7b72dbc8a818ff35c2e09aa9",
    R90_GRID / "launch_status.csv":
        "8b08a234b373bf6f694bf386e0696b70c5b0a6dd82af2bf1d35928685b9f5c35",
    R91 / "pricefm_stage_r91_case_decisions.csv":
        "92cb87da0803369f0c8491ab6c466e2f2614b19e995b4f615938e634902a1356",
    R91 / "pricefm_stage_r91_candidate_quantile_metrics.csv":
        "141ddc74259fef4402f373ccd85925cfac0d1fbbeb73c8965b3675cf522cd41f",
    R91 / "pricefm_stage_r91_candidate_horizon_metrics.csv":
        "41fa4f4e6aac28a11d8f95f09d05c4e9d8eaf0bfa5b8e4fa11233df13e943fdd",
}

HORIZON_REFERENCE_HASHES = {
    DATA_ROOT / "authoritative/pricefm_phase1_cached_vs_stage_b_combined_promotion_rescue_20260617/panel_horizon_group.csv":
        "f48aab15aa4d8e151cfd31b5de341850eb9f7023cd5418243a0650010d54e9bb",
    DATA_ROOT / "authoritative/pricefm_coverage_quantiles_stage_r3q_decision_closeout_20260703/coverage_quantile_horizon_diagnostics.csv":
        "965a786dbe59afbbafb8bfb31691470638c83ad798f9ca131d9bbfc8c439134e",
}

METRIC_SOURCE_HASHES = {
    "authoritative/pricefm_coverage_quantiles_priority0_comparison_fixed_20260702/panel_metric.csv": "a244155e4a72910c2a2d41503a76ff7d1cf0ffb60746ec6b79508321e63d184b",
    "authoritative/pricefm_phase1_cached_vs_stage_b_combined_promotion_rescue_20260617/panel_metric.csv": "76d6cd6ff853742ad73e96677347cc659a76c5659cebfa61008f46280a0ccb45",
    "authoritative/pricefm_phase1_cached_vs_stage_g_seedrob_promoted_quantiles_20260622/panel_metric.csv": "4ac97b9918055005ebfb6dcb64655a2428e16b14a5223f8f32e195535d52d777",
    "authoritative/pricefm_phase1_cached_vs_stage_h_priority0_promoted_quantiles_20260623/panel_metric.csv": "eb53b6cac694ee06286c16e9ba8f8781362ff5b7525c71c7f9a7d0d5fd55b724",
    "authoritative/pricefm_phase1_cached_vs_stage_i_unresolved_promoted_quantiles_20260623/panel_metric.csv": "682470916554bfc21f4bc785b270a67af8abeae18ca8831367ff167be24d588c",
    "authoritative/pricefm_phase1_vs_desn_region_panel_from_local_ar_20260613/panel_metric.csv": "a8cfa1e0d0b86a7452e7a08a68865a5ace5352c2640afdbbcf3fdff8e0fe010b",
    "authoritative/pricefm_phase1_vs_desn_region_panel_graph_local_20260614/panel_metric.csv": "d5d704cd1228147825aaebae6145ff7df4a6b87eee89c04f2d9a1e8dbc78bafc",
    "authoritative/pricefm_phase1_vs_stage_c_completion_paper_quantiles_20260618/panel_metric.csv": "9b8a2252a50aeaf0f7516f0c9fff712f969add621abb51e5dc5dbff7cbc29b9e",
    "authoritative/pricefm_phase1_vs_stage_c_priority1_green_paper_quantiles_20260618/panel_metric.csv": "ad5945f43ee2b3c562669623fff189294954ad2a393736d904157eed0abdc79f",
    "authoritative/pricefm_phase1_vs_stage_d_graph_median_rescue_promoted_quantiles_20260619/panel_metric.csv": "9d9a50febff2f4233055c25e664c701ccc1282101764324486a73a0afc86a921",
    "authoritative/pricefm_phase1_vs_stage_e_full_panel_missing_paper_quantiles_20260619/panel_metric.csv": "62f428e8d1ab34a751b9d1020d87d3914e666a843f52475b566c20f885a7cc73",
    "authoritative/pricefm_phase1_vs_stage_f_graph_median_rescue_promoted_quantiles_20260621/panel_metric.csv": "c90d2cec4c4b64ef4a3d5d167a3bd2a24ce5fd3ee824bff09cc01770dedc2c48",
    "authoritative/pricefm_stage_r3_itcnor_quantile_promotion_comparison_20260703/panel_metric.csv": "727d397a8403a6a7bc41c8110fddf08b3ce0be9b9fb9485b8f199126defdbe24",
}

EXPECTED_AGGREGATES = {
    "AQL": 6.823677420470439,
    "AQCR_percent": 2.579293032015585,
    "MAE": 16.721997707630997,
    "RMSE": 25.449231419703835,
    "pricefm_AQL": 7.038685346534470,
    "mean_delta": -0.21500792606402971,
    "median_delta": -0.0828163895796008,
}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    p.add_argument("--authorize-registry-promotion", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_hash(path: Path, expected: str) -> None:
    if not path.is_file():
        raise FileNotFoundError(path)
    observed = sha256(path)
    if observed != expected:
        raise RuntimeError(f"Frozen hash mismatch for {path}: {observed} != {expected}")


def resolve_recorded_path(value: str) -> Path:
    path = Path(value)
    if path.exists():
        return path
    text = path.as_posix()
    for marker in ("/application/", "/docs/", "/scripts/"):
        if marker in text:
            candidate = REPO_ROOT / marker.strip("/") / text.split(marker, 1)[1]
            if candidate.exists():
                return candidate
    return path


def verify_source_manifest(path: Path) -> None:
    frame = pd.read_csv(path)
    required = {"path", "sha256"}
    if not required.issubset(frame.columns):
        raise RuntimeError(f"Malformed source manifest: {path}")
    for row in frame.itertuples(index=False):
        source = resolve_recorded_path(str(row.path))
        require_hash(source, str(row.sha256))
        if "bytes" in frame.columns and int(row.bytes) != source.stat().st_size:
            raise RuntimeError(f"Frozen byte count mismatch for {source}")


def artifact_relative(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPO_ROOT.resolve()))
    except ValueError:
        pass
    try:
        return str(path.resolve().relative_to(ARTIFACT_REPO.resolve()))
    except ValueError:
        return str(path.resolve())


def manifest_source_root(path: Path) -> str:
    resolved = path.resolve()
    try:
        resolved.relative_to(REPO_ROOT.resolve())
        return "article_repository"
    except ValueError:
        pass
    try:
        resolved.relative_to(ARTIFACT_REPO.resolve())
        return "protected_pricefm_evidence_repository"
    except ValueError:
        return "absolute_path"


def validate_output_location(path: Path, allow_test_output: bool) -> None:
    if allow_test_output:
        return
    try:
        relative = path.relative_to(PRODUCTION_OUTPUT_ROOT.resolve())
    except ValueError as exc:
        raise PermissionError(
            f"R92 output must be inside the ignored authoritative data root: {PRODUCTION_OUTPUT_ROOT}"
        ) from exc
    if not relative.parts:
        raise PermissionError("R92 output must be a new child directory of the authoritative data root")
    ignored = subprocess.run(
        ["git", "check-ignore", "--quiet", str(path)],
        cwd=REPO_ROOT,
        check=False,
    )
    if ignored.returncode != 0:
        raise PermissionError(f"R92 output is not ignored by Git: {path}")


def require_unique_keys(frame: pd.DataFrame, keys: list[str], label: str) -> None:
    if frame.duplicated(keys).any():
        duplicate = frame.loc[frame.duplicated(keys, keep=False), keys].head().to_dict("records")
        raise RuntimeError(f"Duplicate {label} keys: {duplicate}")


def bool_value(value: Any) -> bool:
    if isinstance(value, (bool, np.bool_)):
        return bool(value)
    return str(value).strip().lower() in {"true", "1", "yes"}


def target_scale(path: Path, region: str) -> float:
    scalers = joblib.load(path)
    scale = float(np.asarray(scalers[region]["y_scaler"].scale_).reshape(-1)[0])
    if not np.isfinite(scale) or scale <= 0:
        raise RuntimeError(f"Invalid target scale for {region}: {path}")
    return scale


def horizon_group(values: pd.Series) -> pd.Series:
    lower = ((values.astype(int) - 1) // 24) * 24 + 1
    return lower.astype(str) + "-" + (lower + 23).astype(str)


def load_metric_sources() -> pd.DataFrame:
    frames: list[pd.DataFrame] = []
    for relative, expected in METRIC_SOURCE_HASHES.items():
        path = DATA_ROOT / relative
        require_hash(path, expected)
        frame = pd.read_csv(path)
        needed = ["region", "fold", "method_id", "split", "unit", "AQL", "AQCR", "MAE", "RMSE"]
        if not set(needed).issubset(frame.columns):
            raise RuntimeError(f"Incomplete historical metric source: {path}")
        frame = frame[needed].copy()
        frame["metric_source_path"] = artifact_relative(path)
        frame["metric_source_sha256"] = expected
        frames.append(frame)
    return pd.concat(frames, ignore_index=True)


def find_historical_metric(
    metrics: pd.DataFrame, region: str, fold: int, method: str, expected_aql: float,
) -> pd.Series:
    found = metrics[
        metrics.region.astype(str).eq(str(region))
        & metrics.fold.astype(int).eq(int(fold))
        & metrics.method_id.astype(str).eq(str(method))
        & metrics.split.astype(str).eq("test")
        & metrics.unit.astype(str).eq("original")
        & np.isclose(pd.to_numeric(metrics.AQL), float(expected_aql), atol=1e-8, rtol=0.0)
    ].copy()
    if found.empty:
        raise RuntimeError(f"No historical metric match for {region}/{fold}/{method}")
    numeric = found[["AQL", "AQCR", "MAE", "RMSE"]].astype(float)
    if not np.allclose(numeric, numeric.iloc[0].to_numpy(), atol=1e-10, rtol=0.0):
        raise RuntimeError(f"Inconsistent duplicate historical metrics for {region}/{fold}/{method}")
    return found.sort_values("metric_source_path").iloc[0]


def verify_selected_atoms(selected: pd.DataFrame) -> None:
    if len(selected) != 392 or selected.case_id.nunique() != 56:
        raise RuntimeError("R89 selected-atom surface is not 56 cases by seven levels")
    require_unique_keys(selected, ["case_id", "tau"], "R89 selected atom")
    for case_id, frame in selected.groupby("case_id"):
        if tuple(sorted(frame.tau.astype(float))) != TAUS:
            raise RuntimeError(f"R89 selected atoms do not contain seven expected levels for {case_id}")
    for row in selected.itertuples(index=False):
        for path_name, hash_name in (
            ("beta_path", "beta_sha256"),
            ("validation_prediction_path", "validation_prediction_sha256"),
            ("terminal_path", "terminal_sha256"),
            ("feature_manifest_path", "feature_manifest_sha256"),
            ("x_val_path", "x_val_sha256"),
            ("rows_val_path", "rows_val_sha256"),
            ("source_case_config", "source_case_config_sha256"),
            ("scaler_path", "scaler_sha256"),
        ):
            require_hash(Path(getattr(row, path_name)), str(getattr(row, hash_name)))


def verify_r90_terminal(manifest_row: Any) -> dict[str, Any]:
    score_dir = Path(manifest_row.output_dir)
    adapter_dir = Path(manifest_row.adapter_dir)
    terminal_path = score_dir / "terminal.json"
    terminal = json.loads(terminal_path.read_text())
    required_state = (
        terminal.get("status") == "completed"
        and terminal.get("model_fitted") is False
        and terminal.get("selection_changed") is False
        and terminal.get("validation_replay_passed") is True
    )
    if not required_state:
        raise RuntimeError(f"R90 scoring-only state changed: {terminal_path}")
    for name, expected in (terminal.get("retained_artifact_sha256") or {}).items():
        parent = adapter_dir if name in {"adapter_manifest.json", "feature_manifest.json", "rows_test.csv"} else score_dir
        require_hash(parent / name, str(expected))
    return terminal


def reconstruct_candidate(
    queue_row: Any, manifest_row: Any, selected: pd.DataFrame, case_manifest: pd.DataFrame,
) -> tuple[dict[str, Any], pd.DataFrame, pd.DataFrame]:
    terminal = verify_r90_terminal(manifest_row)
    score_dir = Path(manifest_row.output_dir)
    adapter_dir = Path(manifest_row.adapter_dir)
    atoms = selected[selected.case_id.astype(str).eq(str(queue_row.case_id))].sort_values("tau")
    if len(atoms) != 7 or tuple(atoms.tau.astype(float)) != TAUS:
        raise RuntimeError(f"Incomplete selected atoms for {queue_row.case_id}")
    if atoms.selected_family.nunique() != 1 or str(atoms.selected_family.iloc[0]) != str(queue_row.selected_family):
        raise RuntimeError(f"Selected family mismatch for {queue_row.case_id}")
    if not np.allclose(
        atoms.selected_validation_AQL.astype(float), float(queue_row.selected_validation_AQL),
        atol=1e-12, rtol=0.0,
    ):
        raise RuntimeError(f"Selected validation AQL mismatch for {queue_row.case_id}")
    if atoms.scaler_path.nunique() != 1 or atoms.source_case_config.nunique() != 1:
        raise RuntimeError(f"Mixed R89 provenance for {queue_row.case_id}")

    config_path = Path(atoms.source_case_config.iloc[0])
    config = yaml.safe_load(config_path.read_text())["pricefm_desn_smoke"]
    if str(config["region"]) != str(queue_row.region) or int(config["fold"]) != int(queue_row.fold):
        raise RuntimeError(f"R69B case identity mismatch for {queue_row.case_id}")
    bridge = case_manifest[case_manifest.case_id.astype(str).eq(str(queue_row.case_id))]
    if len(bridge) != 1:
        raise RuntimeError(f"Missing R69B case-manifest row for {queue_row.case_id}")
    bridge = bridge.iloc[0]
    if Path(str(bridge.config)) != config_path or str(bridge.config_sha256) != str(atoms.source_case_config_sha256.iloc[0]):
        raise RuntimeError(f"R69B configuration bridge changed for {queue_row.case_id}")
    feature_manifest_path = Path(atoms.feature_manifest_path.iloc[0])
    feature = json.loads(feature_manifest_path.read_text())
    adapter = config["adapter"]
    reservoir = feature["reservoir"]
    expected_scope = str(bridge.input_scope)
    if str(bridge.feature_policy) == "graph_khop":
        expected_scope += f"_degree{int(bridge.graph_degree)}"
    bridge_checks = {
        "feature_policy": str(bridge.feature_policy) == str(config["feature_policy"]) == str(feature["feature_policy"]),
        "feature_input_scope": str(feature["feature_policy_manifest"]["input_scope"]) == str(bridge.input_scope),
        "feature_spatial_set": str(feature["feature_policy_manifest"]["spatial_information_set"]) == str(bridge.spatial_information_set),
        "feature_map": str(feature["feature_map"]) == str(adapter["feature_map"]),
        "feature_dim": int(feature["feature_dim"]) == int(bridge.reservoir_feature_dim) == int(adapter["feature_dim"]),
        "seed": int(feature["seed"]) == int(adapter["seed"]),
        "depth": int(reservoir["depth"]) == int(bridge.depth_D) == int(adapter["depth"]),
        "units": list(map(int, reservoir["units"])) == list(map(int, adapter["units"])) == list(map(int, json.loads(str(bridge.units_json)))),
        "alpha": np.allclose(reservoir["alpha"], [float(bridge.alpha)] * int(bridge.depth_D), atol=0.0, rtol=0.0),
        "rho": np.allclose(reservoir["rho"], [float(bridge.rho)] * int(bridge.depth_D), atol=0.0, rtol=0.0),
        "input_scale": np.allclose(reservoir["input_scale"], [float(bridge.input_scale)] * int(bridge.depth_D), atol=0.0, rtol=0.0),
        "projection_scale": float(feature["projection_scale"]) == float(bridge.projection_scale) == float(adapter["projection_scale"]),
        "sparsity": np.allclose(reservoir["recurrent_sparsity"], [float(bridge.recurrent_sparsity)] * int(bridge.depth_D), atol=0.0, rtol=0.0),
        "activation": str(reservoir["reservoir_activation"]) == str(bridge.reservoir_activation) == str(adapter["reservoir_activation"]),
        "state_output": str(reservoir["state_output"]) == str(bridge.state_output) == str(adapter["state_output"]),
    }
    if not all(bridge_checks.values()):
        failed = [name for name, passed in bridge_checks.items() if not passed]
        raise RuntimeError(f"R69B feature specification mismatch for {queue_row.case_id}: {failed}")

    scaler_path = Path(atoms.scaler_path.iloc[0])
    scale = target_scale(scaler_path, str(queue_row.region))
    truth = pd.read_csv(adapter_dir / "rows_test.csv")
    predictions = pd.read_csv(score_dir / "test_predictions_scaled.csv")
    require_unique_keys(truth, ["origin_id", "horizon"], f"R90 truth {queue_row.case_id}")
    require_unique_keys(predictions, ["origin_id", "horizon", "tau"], f"R90 prediction {queue_row.case_id}")
    if set(predictions.tau.astype(float)) != set(TAUS):
        raise RuntimeError(f"Unexpected quantile levels for {queue_row.case_id}")
    if set(predictions.horizon.astype(int)) != set(range(1, 97)):
        raise RuntimeError(f"Unexpected horizons for {queue_row.case_id}")
    merged = predictions.merge(
        truth[["origin_id", "horizon", "y_scaled"]],
        on=["origin_id", "horizon"], how="left", validate="many_to_one",
    )
    if merged.y_scaled.isna().any() or not np.isfinite(merged[["y_scaled", "pred_scaled"]]).all().all():
        raise RuntimeError(f"Invalid scoring rows for {queue_row.case_id}")
    residual = merged.y_scaled - merged.pred_scaled
    merged["loss"] = np.maximum(merged.tau * residual, (merged.tau - 1.0) * residual) * scale
    merged["horizon_group"] = horizon_group(merged.horizon)
    wide = merged.pivot(index=["origin_id", "horizon"], columns="tau", values="pred_scaled").loc[:, list(TAUS)]
    crossing = wide.to_numpy()[:, :-1] > wide.to_numpy()[:, 1:]
    median = merged[np.isclose(merged.tau.astype(float), 0.50)].copy()
    median_error = (median.y_scaled - median.pred_scaled).to_numpy() * scale
    case = {
        "case_id": str(queue_row.case_id),
        "region": str(queue_row.region),
        "fold": int(queue_row.fold),
        "selected_family": str(queue_row.selected_family),
        "selected_validation_AQL": float(queue_row.selected_validation_AQL),
        "candidate_test_AQL": float(merged.loss.mean()),
        "candidate_test_AQCR": float(crossing.mean()),
        "candidate_test_AQCR_percent": 100.0 * float(crossing.mean()),
        "candidate_test_MAE": float(np.mean(np.abs(median_error))),
        "candidate_test_RMSE": float(np.sqrt(np.mean(median_error ** 2))),
        "test_rows": int(len(truth)),
        "row_any_crossing_rate": float(crossing.any(axis=1).mean()),
        "feature_policy": str(config["feature_policy"]),
        "input_scope": expected_scope,
        "spatial_information_set": str(bridge.spatial_information_set),
        "source_case_config": artifact_relative(config_path),
        "source_case_config_sha256": str(atoms.source_case_config_sha256.iloc[0]),
        "scaler_path": artifact_relative(scaler_path),
        "scaler_sha256": str(atoms.scaler_sha256.iloc[0]),
        "r90_terminal_path": artifact_relative(score_dir / "terminal.json"),
        "r90_terminal_sha256": sha256(score_dir / "terminal.json"),
        "r90_model_fitted": bool(terminal["model_fitted"]),
        "r90_selection_changed": bool(terminal["selection_changed"]),
    }
    checks = {
        "candidate_test_AQL": float(queue_row.candidate_test_AQL),
        "candidate_test_AQCR": float(queue_row.adjacent_crossing_rate),
        "row_any_crossing_rate": float(queue_row.row_any_crossing_rate),
    }
    for name, expected in checks.items():
        if not np.isclose(case[name], expected, atol=1e-10, rtol=0.0):
            raise RuntimeError(f"R91 {name} mismatch for {queue_row.case_id}: {case[name]} != {expected}")
    if int(queue_row.test_rows) != len(truth):
        raise RuntimeError(f"R91 test-row mismatch for {queue_row.case_id}")

    quantiles = merged.groupby("tau", as_index=False).loss.mean().rename(columns={"loss": "candidate_test_AQL"})
    horizons = merged.groupby(["tau", "horizon_group"], as_index=False).loss.mean().rename(
        columns={"loss": "candidate_test_AQL"}
    )
    return case, quantiles, horizons


def decision_from_delta(delta: float, relative: float) -> tuple[str, str]:
    if delta <= 0.0:
        return "qdesn_wins", "promote_qdesn"
    if relative <= 0.05:
        return "qdesn_close", "retain_qdesn_close"
    return "pricefm_wins", "retain_pricefm"


def method_summary(registry: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for method, column in (("qdesn_selected", "qdesn_AQL"), ("pricefm_phase1_pretraining", "pricefm_AQL")):
        values = pd.to_numeric(registry[column])
        rows.append({
            "method_id": method,
            "n": len(values),
            "mean_AQL": float(values.mean()),
            "median_AQL": float(values.median()),
            "min_AQL": float(values.min()),
            "max_AQL": float(values.max()),
        })
    return pd.DataFrame(rows)


def load_horizon_pricefm_reference(registry_row: pd.Series) -> pd.DataFrame:
    root = ARTIFACT_REPO / str(registry_row.comparison_metric_root)
    if str(registry_row.source_class) == "provenance_bridge_30":
        path = root / "panel_horizon_group.csv"
        expected = HORIZON_REFERENCE_HASHES[path]
        require_hash(path, expected)
        frame = pd.read_csv(path)
        selected = frame[
            frame.region.astype(str).eq(str(registry_row.region))
            & frame.fold.astype(int).eq(int(registry_row.fold))
            & frame.split.astype(str).eq("test")
            & frame.unit.astype(str).eq("original")
        ]
        qdesn = selected[selected.method_id.astype(str).eq(str(registry_row.qdesn_method_id))][
            ["horizon_group", "AQL"]
        ].rename(columns={"AQL": "historical_qdesn_horizon_AQL"})
        pricefm = selected[selected.method_id.astype(str).eq("pricefm_phase1_pretraining")][
            ["horizon_group", "AQL"]
        ].rename(columns={"AQL": "pricefm_horizon_AQL"})
        out = qdesn.merge(pricefm, on="horizon_group", validate="one_to_one")
        out["historical_delta"] = out.historical_qdesn_horizon_AQL - out.pricefm_horizon_AQL
        return out[["horizon_group", "pricefm_horizon_AQL", "historical_delta"]]
    if str(registry_row.source_class) == "current_r3q":
        path = root / "coverage_quantile_horizon_diagnostics.csv"
        expected = HORIZON_REFERENCE_HASHES[path]
        require_hash(path, expected)
        frame = pd.read_csv(path)
        out = frame[
            frame.region.astype(str).eq(str(registry_row.region))
            & frame.fold.astype(int).eq(int(registry_row.fold))
        ][["horizon_group", "pricefm_horizon_AQL", "horizon_delta_AQL_qdesn_minus_pricefm"]].rename(
            columns={"horizon_delta_AQL_qdesn_minus_pricefm": "historical_delta"}
        )
        return out
    raise RuntimeError(f"No authorized horizon reference for {registry_row.region}/{registry_row.fold}")


def write_csv(frame: pd.DataFrame, path: Path) -> None:
    frame.to_csv(path, index=False, lineterminator="\n")


def run(args: argparse.Namespace) -> dict[str, Any]:
    if not args.authorize_registry_promotion:
        raise PermissionError("R92 requires --authorize-registry-promotion")
    final_output = args.output_dir.resolve()
    if final_output.exists():
        raise FileExistsError(f"R92 output must be a new directory: {final_output}")
    validate_output_location(final_output, bool(getattr(args, "allow_test_output", False)))

    for path, expected in FROZEN_HASHES.items():
        require_hash(path, expected)
    for manifest in (R88 / "source_manifest.csv", R89 / "source_manifest.csv", R90_PREP / "source_manifest.csv", R91 / "source_manifest.csv"):
        verify_source_manifest(manifest)
    for path, expected in HORIZON_REFERENCE_HASHES.items():
        require_hash(path, expected)

    historical = pd.read_csv(HISTORICAL / "pricefm_full_surface_decision_registry.csv").sort_values(["region", "fold"]).reset_index(drop=True)
    horizons_old = pd.read_csv(HISTORICAL / "pricefm_full_surface_horizon_diagnostics.csv").sort_values(["region", "fold", "horizon_group"]).reset_index(drop=True)
    queue = pd.read_csv(R91 / "pricefm_stage_r91_promotion_queue.csv").sort_values(["region", "fold"]).reset_index(drop=True)
    decisions = pd.read_csv(R91 / "pricefm_stage_r91_case_decisions.csv")
    r91_quantiles = pd.read_csv(R91 / "pricefm_stage_r91_candidate_quantile_metrics.csv")
    r91_horizons = pd.read_csv(R91 / "pricefm_stage_r91_candidate_horizon_metrics.csv")
    selected = pd.read_csv(R89 / "pricefm_stage_r89_selected_atom_manifest.csv")
    case_manifest = pd.read_csv(R69B_CASE_MANIFEST)
    task_manifest = pd.read_csv(R90_GRID / "task_manifest.csv")
    metrics = load_metric_sources()

    require_unique_keys(historical, ["region", "fold"], "historical registry")
    require_unique_keys(horizons_old, ["region", "fold", "horizon_group"], "historical horizon")
    require_unique_keys(queue, ["region", "fold"], "R91 promotion")
    if len(historical) != 114 or len(horizons_old) != 288 or historical[["region", "fold"]].drop_duplicates().shape[0] != 114:
        raise RuntimeError("Historical PriceFM authority has changed dimensions")
    observed_promotions = {(str(r.region), int(r.fold)): str(r.selected_family) for r in queue.itertuples(index=False)}
    if observed_promotions != EXPECTED_PROMOTIONS:
        raise RuntimeError(f"Frozen promotion set changed: {observed_promotions}")
    required_true = [
        "validation_replay_pass", "all_quantile_metrics_finite", "all_horizon_metrics_finite",
        "full_quantile_confirmation_pass", "full_horizon_confirmation_pass",
        "beats_authoritative_qdesn", "beats_cached_pricefm", "complete_finite_surface", "promotion_eligible",
    ]
    if any(not queue[name].map(bool_value).all() for name in required_true):
        raise RuntimeError("One or more R91 promotion gates are no longer true")
    if len(decisions) != 56 or decisions.promotion_eligible.map(bool_value).sum() != 12:
        raise RuntimeError("R91 decision surface no longer contains exactly 12 of 56 promotions")
    if set(decisions.decision.astype(str)) != {
        "promote_candidate_for_integration_review", "retain_current_authoritative_qdesn"
    }:
        raise RuntimeError("Unexpected R91 decision label")
    if not queue.decision.astype(str).eq("promote_candidate_for_integration_review").all():
        raise RuntimeError("R91 queue contains a non-promotion decision")
    if not np.isclose(decisions.candidate_test_AQL.mean(), 6.7042093434, atol=5e-11, rtol=0.0):
        raise RuntimeError("The full 56-case R91 candidate mean changed")
    reference_check = decisions.merge(
        historical[["region", "fold", "qdesn_AQL", "pricefm_AQL"]],
        on=["region", "fold"], how="left", validate="one_to_one",
    )
    if len(reference_check) != 56 or reference_check[["qdesn_AQL", "pricefm_AQL"]].isna().any().any():
        raise RuntimeError("R91 comparator cases do not map to the historical registry")
    if not np.allclose(
        reference_check.authoritative_qdesn_test_AQL, reference_check.qdesn_AQL,
        atol=1e-12, rtol=0.0,
    ) or not np.allclose(
        reference_check.cached_pricefm_test_AQL, reference_check.pricefm_AQL,
        atol=1e-12, rtol=0.0,
    ):
        raise RuntimeError("One or more R91 comparator values changed from the historical registry")

    verify_selected_atoms(selected)
    task_lookup = task_manifest.set_index("case_id", drop=False)
    if len(task_manifest) != 56 or task_lookup.index.nunique() != 56:
        raise RuntimeError("R90 task manifest is not a unique 56-case surface")
    for row in task_manifest.itertuples(index=False):
        verify_r90_terminal(row)

    candidate_rows: list[dict[str, Any]] = []
    recomputed_quantiles: list[pd.DataFrame] = []
    recomputed_horizons: dict[tuple[str, int], pd.DataFrame] = {}
    for queue_row in queue.itertuples(index=False):
        task = task_lookup.loc[str(queue_row.case_id)]
        case, qmetrics, hmetrics = reconstruct_candidate(queue_row, task, selected, case_manifest)
        candidate_rows.append(case)
        qmetrics.insert(0, "case_id", str(queue_row.case_id))
        recomputed_quantiles.append(qmetrics)
        recomputed_horizons[(str(queue_row.region), int(queue_row.fold))] = hmetrics

    promoted = pd.DataFrame(candidate_rows).sort_values(["region", "fold"]).reset_index(drop=True)
    qcheck = pd.concat(recomputed_quantiles, ignore_index=True).sort_values(["case_id", "tau"]).reset_index(drop=True)
    qref = r91_quantiles[r91_quantiles.case_id.isin(queue.case_id)].sort_values(["case_id", "tau"]).reset_index(drop=True)
    if (
        len(qcheck) != 84
        or len(qref) != 84
        or not qcheck[["case_id", "tau"]].equals(qref[["case_id", "tau"]])
        or not np.allclose(qcheck.candidate_test_AQL, qref.candidate_test_AQL, atol=1e-10, rtol=0.0)
    ):
        raise RuntimeError("Reconstructed R90 quantile metrics disagree with R91")

    registry = historical.copy(deep=True)
    ledger_rows: list[dict[str, Any]] = []
    old_metric_rows: dict[tuple[str, int], pd.Series] = {}
    full_qdesn_metrics: list[dict[str, float]] = []
    full_pricefm_metrics: list[dict[str, float]] = []
    for old in historical.itertuples(index=False):
        qmetric = find_historical_metric(metrics, old.region, int(old.fold), old.qdesn_method_id, float(old.qdesn_AQL))
        pmetric = find_historical_metric(metrics, old.region, int(old.fold), old.pricefm_method_id, float(old.pricefm_AQL))
        old_metric_rows[(str(old.region), int(old.fold))] = qmetric
        full_qdesn_metrics.append({name: float(qmetric[name]) for name in ("AQL", "AQCR", "MAE", "RMSE")})
        full_pricefm_metrics.append({name: float(pmetric[name]) for name in ("AQL", "AQCR", "MAE", "RMSE")})

    queue_hash = FROZEN_HASHES[R91 / "pricefm_stage_r91_promotion_queue.csv"]
    queue_relative = artifact_relative(R91 / "pricefm_stage_r91_promotion_queue.csv")
    hist_relative = artifact_relative(HISTORICAL / "pricefm_full_surface_decision_registry.csv")
    hist_hash = FROZEN_HASHES[HISTORICAL / "pricefm_full_surface_decision_registry.csv"]
    promoted_lookup = promoted.set_index(["region", "fold"])
    historical_qdesn_frame = pd.DataFrame(full_qdesn_metrics)
    historical_pricefm_frame = pd.DataFrame(full_pricefm_metrics)
    historical_direct_metrics = {
        "qdesn": {
            "AQL": float(historical_qdesn_frame.AQL.mean()),
            "AQCR_percent": 100.0 * float(historical_qdesn_frame.AQCR.mean()),
            "MAE": float(historical_qdesn_frame.MAE.mean()),
            "RMSE": float(historical_qdesn_frame.RMSE.mean()),
        },
        "pricefm": {
            "AQL": float(historical_pricefm_frame.AQL.mean()),
            "AQCR_percent": 100.0 * float(historical_pricefm_frame.AQCR.mean()),
            "MAE": float(historical_pricefm_frame.MAE.mean()),
            "RMSE": float(historical_pricefm_frame.RMSE.mean()),
        },
    }
    for key, new in promoted_lookup.iterrows():
        region, fold = str(key[0]), int(key[1])
        mask = registry.region.astype(str).eq(region) & registry.fold.astype(int).eq(fold)
        if mask.sum() != 1:
            raise RuntimeError(f"Missing registry key for promotion {region}/{fold}")
        idx = registry.index[mask][0]
        old = registry.loc[idx].copy()
        if str(old.decision_label) != "qdesn_wins" or not float(new.candidate_test_AQL) < float(old.qdesn_AQL) or not float(new.candidate_test_AQL) < float(old.pricefm_AQL):
            raise RuntimeError(f"Promotion is not a strict dual improvement: {region}/{fold}")
        if str(new.feature_policy) != str(old.feature_policy):
            raise RuntimeError(f"Feature policy changed for {region}/{fold}")
        if str(new.input_scope) != str(old.input_scope) or str(new.spatial_information_set) != str(old.spatial_information_set):
            raise RuntimeError(f"Information set changed for {region}/{fold}")
        method = "qdesn_exal_rhs_ns_exact_chunked" if str(new.selected_family) == "exal" else "qdesn_al_rhs_ns_exact_chunked"
        delta = float(new.candidate_test_AQL) - float(old.pricefm_AQL)
        relative = delta / max(abs(float(old.pricefm_AQL)), 1e-12)
        decision, recommendation = decision_from_delta(delta, relative)
        registry.loc[idx, "qdesn_method_id"] = method
        registry.loc[idx, "selected_method_id"] = method
        registry.loc[idx, "qdesn_AQL"] = float(new.candidate_test_AQL)
        registry.loc[idx, "delta_AQL_qdesn_minus_pricefm"] = delta
        registry.loc[idx, "delta_rel_qdesn_minus_pricefm"] = relative
        registry.loc[idx, "decision_label"] = decision
        registry.loc[idx, "article_recommendation"] = recommendation
        registry.loc[idx, "selected_on_split"] = "val"
        registry.loc[idx, "selection_metric"] = "AQL"
        registry.loc[idx, "selection_metric_value"] = float(new.selected_validation_AQL)
        registry.loc[idx, "selection_is_validation_only"] = True
        registry.loc[idx, "test_metrics_role"] = "audit_only"
        registry.loc[idx, "evidence_path"] = queue_relative
        registry.loc[idx, "evidence_sha256"] = queue_hash
        registry.loc[idx, "comparison_metric_root"] = artifact_relative(Path(task_lookup.loc[str(new.case_id)].output_dir))
        registry.loc[idx, "registry_source_path"] = hist_relative
        registry.loc[idx, "registry_source_sha256"] = hist_hash
        registry.loc[idx, "qdesn_beats_pricefm"] = True
        for flag, baseline in (("qdesn_beats_normal", "normal_AQL"), ("qdesn_beats_naive", "naive_AQL")):
            if pd.notna(old[baseline]):
                baseline_value = float(old[baseline])
                if not np.isfinite(baseline_value):
                    raise RuntimeError(f"Nonfinite optional baseline for {region}/{fold}: {baseline}")
                registry.loc[idx, flag] = float(new.candidate_test_AQL) < baseline_value

        old_metric = old_metric_rows[(region, fold)]
        full_position = historical.index[
            historical.region.astype(str).eq(region) & historical.fold.astype(int).eq(fold)
        ][0]
        full_qdesn_metrics[full_position] = {
            "AQL": float(new.candidate_test_AQL),
            "AQCR": float(new.candidate_test_AQCR),
            "MAE": float(new.candidate_test_MAE),
            "RMSE": float(new.candidate_test_RMSE),
        }
        ledger_rows.append({
            "region": region,
            "fold": fold,
            "selected_family": str(new.selected_family),
            "old_qdesn_method_id": str(old.qdesn_method_id),
            "promoted_qdesn_method_id": method,
            "likelihood_family_changed": str(old.qdesn_method_id) != method,
            "selected_validation_AQL": float(new.selected_validation_AQL),
            "old_qdesn_AQL": float(old_metric.AQL),
            "promoted_qdesn_AQL": float(new.candidate_test_AQL),
            "AQL_gain": float(old_metric.AQL) - float(new.candidate_test_AQL),
            "old_qdesn_AQCR_percent": 100.0 * float(old_metric.AQCR),
            "promoted_qdesn_AQCR_percent": float(new.candidate_test_AQCR_percent),
            "old_qdesn_MAE": float(old_metric.MAE),
            "promoted_qdesn_MAE": float(new.candidate_test_MAE),
            "old_qdesn_RMSE": float(old_metric.RMSE),
            "promoted_qdesn_RMSE": float(new.candidate_test_RMSE),
            "pricefm_AQL": float(old.pricefm_AQL),
            "feature_policy": str(old.feature_policy),
            "input_scope": str(old.input_scope),
            "spatial_information_set": str(old.spatial_information_set),
            "experiment_id": str(old.experiment_id),
            "source_case_config": str(new.source_case_config),
            "source_case_config_sha256": str(new.source_case_config_sha256),
            "r91_decision_path": queue_relative,
            "r91_decision_sha256": queue_hash,
        })

    registry = registry.sort_values(["region", "fold"]).reset_index(drop=True)
    require_unique_keys(registry, ["region", "fold"], "R92 registry")
    nonpromotion = historical.merge(queue[["region", "fold"]], on=["region", "fold"], how="left", indicator=True)
    unchanged_keys = nonpromotion[nonpromotion._merge.eq("left_only")][["region", "fold"]]
    old_unchanged = historical.merge(unchanged_keys, on=["region", "fold"], how="inner").sort_values(["region", "fold"]).reset_index(drop=True)
    new_unchanged = registry.merge(unchanged_keys, on=["region", "fold"], how="inner").sort_values(["region", "fold"]).reset_index(drop=True)
    if not old_unchanged.equals(new_unchanged) or len(new_unchanged) != 102:
        raise RuntimeError("One or more non-promoted registry rows changed")
    counts = registry.decision_label.value_counts().to_dict()
    if counts != {"qdesn_wins": 66, "pricefm_wins": 36, "qdesn_close": 12}:
        raise RuntimeError(f"R92 decision counts changed: {counts}")

    horizon_keys = set(map(tuple, horizons_old[["region", "fold"]].drop_duplicates().itertuples(index=False, name=None)))
    matched = [key for key in EXPECTED_PROMOTIONS if key in horizon_keys]
    if set(matched) != {("ES", 1), ("FR", 3), ("IT_CNOR", 1), ("IT_NORD", 3), ("SE_3", 1)}:
        raise RuntimeError(f"Unexpected promoted horizon-authority cases: {matched}")
    horizons = horizons_old.copy(deep=True)
    replaced_horizon_rows: list[dict[str, Any]] = []
    for region, fold in matched:
        old = historical[historical.region.astype(str).eq(region) & historical.fold.astype(int).eq(fold)].iloc[0]
        refs = load_horizon_pricefm_reference(old)
        candidate = recomputed_horizons[(region, fold)].groupby("horizon_group", as_index=False).candidate_test_AQL.mean()
        r91_candidate = r91_horizons[
            r91_horizons.region.astype(str).eq(region) & r91_horizons.fold.astype(int).eq(fold)
        ].groupby("horizon_group", as_index=False).candidate_test_AQL.mean()
        check = candidate.merge(r91_candidate, on="horizon_group", suffixes=("_recomputed", "_r91"), validate="one_to_one")
        if len(check) != 4 or not np.allclose(check.candidate_test_AQL_recomputed, check.candidate_test_AQL_r91, atol=1e-10, rtol=0.0):
            raise RuntimeError(f"R91 horizon reconstruction mismatch for {region}/{fold}")
        update = candidate.merge(refs, on="horizon_group", validate="one_to_one")
        if len(update) != 4 or set(update.horizon_group) != set(HORIZON_GROUPS):
            raise RuntimeError(f"Incomplete matched PriceFM horizon reference for {region}/{fold}")
        for row in update.itertuples(index=False):
            mask = (
                horizons.region.astype(str).eq(region)
                & horizons.fold.astype(int).eq(fold)
                & horizons.horizon_group.astype(str).eq(str(row.horizon_group))
            )
            if mask.sum() != 1:
                raise RuntimeError(f"Missing historical horizon row for {region}/{fold}/{row.horizon_group}")
            old_delta = float(horizons.loc[mask, "horizon_delta_AQL_qdesn_minus_pricefm"].iloc[0])
            if not np.isclose(old_delta, float(row.historical_delta), atol=1e-10, rtol=0.0):
                raise RuntimeError(f"Historical horizon source mismatch for {region}/{fold}/{row.horizon_group}")
            new_delta = float(row.candidate_test_AQL) - float(row.pricefm_horizon_AQL)
            horizons.loc[mask, "horizon_delta_AQL_qdesn_minus_pricefm"] = new_delta
            replaced_horizon_rows.append({
                "region": region, "fold": fold, "horizon_group": str(row.horizon_group),
                "old_delta_AQL_qdesn_minus_pricefm": old_delta,
                "promoted_qdesn_horizon_AQL": float(row.candidate_test_AQL),
                "pricefm_horizon_AQL": float(row.pricefm_horizon_AQL),
                "new_delta_AQL_qdesn_minus_pricefm": new_delta,
            })
    old_horizon_unchanged = horizons_old.merge(pd.DataFrame(replaced_horizon_rows)[["region", "fold", "horizon_group"]], on=["region", "fold", "horizon_group"], how="left", indicator=True)
    unchanged_horizon_keys = old_horizon_unchanged[old_horizon_unchanged._merge.eq("left_only")][["region", "fold", "horizon_group"]]
    before = horizons_old.merge(unchanged_horizon_keys, on=["region", "fold", "horizon_group"]).sort_values(["region", "fold", "horizon_group"]).reset_index(drop=True)
    after = horizons.merge(unchanged_horizon_keys, on=["region", "fold", "horizon_group"]).sort_values(["region", "fold", "horizon_group"]).reset_index(drop=True)
    if len(replaced_horizon_rows) != 20 or len(before) != 268 or not before.equals(after):
        raise RuntimeError("R92 horizon replacement boundary changed")
    horizon_summary = (
        horizons.groupby("horizon_group", as_index=False, sort=False)
        .agg(
            n=("region", "size"),
            qdesn_wins=("horizon_delta_AQL_qdesn_minus_pricefm", lambda x: int((x < 0).sum())),
            mean_delta_AQL=("horizon_delta_AQL_qdesn_minus_pricefm", "mean"),
            median_delta_AQL=("horizon_delta_AQL_qdesn_minus_pricefm", "median"),
        )
    )
    horizon_summary["_order"] = horizon_summary.horizon_group.map({x: i for i, x in enumerate(HORIZON_GROUPS)})
    horizon_summary = horizon_summary.sort_values("_order").drop(columns="_order").reset_index(drop=True)

    qmetric_frame = pd.DataFrame(full_qdesn_metrics)
    pmetric_frame = pd.DataFrame(full_pricefm_metrics)
    if not np.isfinite(qmetric_frame[["AQL", "AQCR", "MAE", "RMSE"]].to_numpy()).all():
        raise RuntimeError("Reconstructed Q-DESN metric surface contains a nonfinite value")
    if not np.isfinite(pmetric_frame[["AQL", "AQCR", "MAE", "RMSE"]].to_numpy()).all():
        raise RuntimeError("Reconstructed PriceFM metric surface contains a nonfinite value")
    aggregate = {
        "AQL": float(qmetric_frame.AQL.mean()),
        "AQCR_percent": 100.0 * float(qmetric_frame.AQCR.mean()),
        "MAE": float(qmetric_frame.MAE.mean()),
        "RMSE": float(qmetric_frame.RMSE.mean()),
        "pricefm_AQL": float(pmetric_frame.AQL.mean()),
        "pricefm_AQCR_percent": 100.0 * float(pmetric_frame.AQCR.mean()),
        "pricefm_MAE": float(pmetric_frame.MAE.mean()),
        "pricefm_RMSE": float(pmetric_frame.RMSE.mean()),
        "mean_delta": float(registry.delta_AQL_qdesn_minus_pricefm.mean()),
        "median_delta": float(registry.delta_AQL_qdesn_minus_pricefm.median()),
    }
    for name, expected in EXPECTED_AGGREGATES.items():
        if not np.isclose(aggregate[name], expected, atol=1e-10, rtol=0.0):
            raise RuntimeError(f"R92 aggregate {name} mismatch: {aggregate[name]} != {expected}")
    if not np.isclose(aggregate["pricefm_AQCR_percent"], 0.0, atol=1e-12):
        raise RuntimeError("PriceFM crossing metric changed")
    if not np.isclose(aggregate["pricefm_MAE"], 17.27366671978033, atol=1e-10, rtol=0.0):
        raise RuntimeError("PriceFM MAE changed")
    if not np.isclose(aggregate["pricefm_RMSE"], 26.335538393719123, atol=1e-10, rtol=0.0):
        raise RuntimeError("PriceFM RMSE changed")
    expected_horizon = {
        "1-24": (72, 22, 0.41515480326196835, 0.35114961628922914),
        "25-48": (72, 45, -0.6835525620342087, -0.3818499460674425),
        "49-72": (72, 34, -0.1983022078010112, 0.0320375982491145),
        "73-96": (72, 42, -0.15547452528154534, -0.11356532006296315),
    }
    for row in horizon_summary.itertuples(index=False):
        expected = expected_horizon[str(row.horizon_group)]
        observed = (int(row.n), int(row.qdesn_wins), float(row.mean_delta_AQL), float(row.median_delta_AQL))
        if observed[:2] != expected[:2] or not np.allclose(observed[2:], expected[2:], atol=1e-10, rtol=0.0):
            raise RuntimeError(f"R92 horizon summary mismatch for {row.horizon_group}: {observed}")

    ledger = pd.DataFrame(ledger_rows).sort_values("AQL_gain", ascending=False).reset_index(drop=True)
    promoted = promoted.sort_values(["region", "fold"]).reset_index(drop=True)
    methods = method_summary(registry)
    source_rows = []
    for label, path, expected in (
        [("historical_registry", HISTORICAL / "pricefm_full_surface_decision_registry.csv", FROZEN_HASHES[HISTORICAL / "pricefm_full_surface_decision_registry.csv"]),
         ("historical_horizons", HISTORICAL / "pricefm_full_surface_horizon_diagnostics.csv", FROZEN_HASHES[HISTORICAL / "pricefm_full_surface_horizon_diagnostics.csv"]),
         ("r88_source_manifest", R88 / "source_manifest.csv", FROZEN_HASHES[R88 / "source_manifest.csv"]),
         ("r89_source_manifest", R89 / "source_manifest.csv", FROZEN_HASHES[R89 / "source_manifest.csv"]),
         ("r90_source_manifest", R90_PREP / "source_manifest.csv", FROZEN_HASHES[R90_PREP / "source_manifest.csv"]),
         ("r91_source_manifest", R91 / "source_manifest.csv", FROZEN_HASHES[R91 / "source_manifest.csv"]),
         ("r91_promotion_queue", R91 / "pricefm_stage_r91_promotion_queue.csv", queue_hash),
         ("r69b_case_manifest", R69B_CASE_MANIFEST, FROZEN_HASHES[R69B_CASE_MANIFEST]),
         ("r89_selected_atoms", R89 / "pricefm_stage_r89_selected_atom_manifest.csv", FROZEN_HASHES[R89 / "pricefm_stage_r89_selected_atom_manifest.csv"]),
         ("r89_family_selection", R89 / "pricefm_stage_r89_family_selection.csv", FROZEN_HASHES[R89 / "pricefm_stage_r89_family_selection.csv"]),
         ("r90_task_manifest", R90_GRID / "task_manifest.csv", FROZEN_HASHES[R90_GRID / "task_manifest.csv"]),
         ("r90_launch_status", R90_GRID / "launch_status.csv", FROZEN_HASHES[R90_GRID / "launch_status.csv"]),
         ("r91_case_decisions", R91 / "pricefm_stage_r91_case_decisions.csv", FROZEN_HASHES[R91 / "pricefm_stage_r91_case_decisions.csv"]),
         ("r91_quantile_metrics", R91 / "pricefm_stage_r91_candidate_quantile_metrics.csv", FROZEN_HASHES[R91 / "pricefm_stage_r91_candidate_quantile_metrics.csv"]),
         ("r91_horizon_metrics", R91 / "pricefm_stage_r91_candidate_horizon_metrics.csv", FROZEN_HASHES[R91 / "pricefm_stage_r91_candidate_horizon_metrics.csv"]),
         ("r92_materializer", Path(__file__).resolve(), sha256(Path(__file__).resolve()))]
        + [(f"horizon_reference_{i + 1}", path, expected) for i, (path, expected) in enumerate(HORIZON_REFERENCE_HASHES.items())]
        + [(f"historical_metric_{i + 1}", DATA_ROOT / relative, expected) for i, (relative, expected) in enumerate(METRIC_SOURCE_HASHES.items())]
    ):
        source_rows.append({
            "label": label,
            "source_root": manifest_source_root(path),
            "path": artifact_relative(path),
            "sha256": expected,
            "bytes": path.stat().st_size,
        })
    for row in promoted.itertuples(index=False):
        task = task_lookup.loc[str(row.case_id)]
        paths = {
            "r90_terminal": Path(task.output_dir) / "terminal.json",
            "r90_predictions": Path(task.output_dir) / "test_predictions_scaled.csv",
            "r90_truth": Path(task.adapter_dir) / "rows_test.csv",
            "r69b_case_config": ARTIFACT_REPO / str(row.source_case_config),
            "r69b_feature_manifest": Path(task.adapter_dir) / "feature_manifest.json",
            "target_scaler": ARTIFACT_REPO / str(row.scaler_path),
        }
        for label, path in paths.items():
            source_rows.append({
                "label": f"{label}_{row.region}_f{int(row.fold)}",
                "source_root": manifest_source_root(path),
                "path": artifact_relative(path),
                "sha256": sha256(path),
                "bytes": path.stat().st_size,
            })
    sources = (
        pd.DataFrame(source_rows)
        .sort_values(["path", "label"])
        .drop_duplicates("path", keep="first")
        .reset_index(drop=True)
    )

    final_output.parent.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix=f".{final_output.name}.tmp-", dir=final_output.parent))
    report_path = output / "pricefm_stage_r92_selective_promotion_report.md"
    report_path.write_text(
        "# PriceFM Stage R92 selective promotion\n\n"
        "The frozen R91 test audit yielded 12 strict case-specific improvements over both the preceding "
        "Q-DESN specification and the matched released PriceFM predictions. R92 replaces those 12 rows "
        "and preserves the other 102 rows. Eleven replacements use exAL and one uses AL; only IT_NORD "
        "fold 3 changes likelihood family.\n\n"
        f"The resulting 114-case mean AQL is {aggregate['AQL']:.15f}. Decision counts remain "
        "66 Q-DESN wins, 12 near ties, and 36 PriceFM wins. The complete 56-case candidate surface "
        f"had mean AQL {decisions.candidate_test_AQL.mean():.10f}, compared with "
        f"{decisions.authoritative_qdesn_test_AQL.mean():.10f} for the preceding Q-DESN specifications. "
        "The final registry therefore retains only the 12 dual-reference improvements. No model was fit, "
        "and each validation-selected AL or exAL family remained fixed during test scoring.\n"
    )
    output_files = {
        "decision_registry": output / "pricefm_full_surface_decision_registry.csv",
        "method_summary": output / "pricefm_full_surface_method_summary.csv",
        "horizon_diagnostics": output / "pricefm_full_surface_horizon_diagnostics.csv",
        "horizon_summary": output / "pricefm_full_surface_horizon_summary.csv",
        "promoted_case_metrics": output / "pricefm_stage_r92_promoted_case_metrics.csv",
        "promotion_ledger": output / "pricefm_stage_r92_promotion_ledger.csv",
        "source_manifest": output / "source_manifest.csv",
        "report": report_path,
    }
    write_csv(registry, output_files["decision_registry"])
    write_csv(methods, output_files["method_summary"])
    write_csv(horizons, output_files["horizon_diagnostics"])
    write_csv(horizon_summary, output_files["horizon_summary"])
    write_csv(promoted, output_files["promoted_case_metrics"])
    write_csv(ledger, output_files["promotion_ledger"])
    write_csv(sources, output_files["source_manifest"])

    summary = {
        "stage": "pricefm_stage_r92_selective_promotion",
        "status": "completed",
        "comparison_status_completed": True,
        "expected_quantiles": list(TAUS),
        "row_alignment_complete": True,
        "fits_models": False,
        "launches_models": False,
        "mutates_manuscript": False,
        "authorization_flag_present": True,
        "n_region_folds": 114,
        "n_regions": int(registry.region.nunique()),
        "n_folds": int(registry.fold.nunique()),
        "cases": int(len(decisions)),
        "promoted_rows": 12,
        "unchanged_rows": 102,
        "promoted_exal_rows": 11,
        "promoted_al_rows": 1,
        "likelihood_family_changes": int(ledger.likelihood_family_changed.sum()),
        "decision_counts": {name: int(counts[name]) for name in ("qdesn_wins", "qdesn_close", "pricefm_wins")},
        "qdesn_win_rate": 66 / 114,
        "source_class_counts": {str(k): int(v) for k, v in registry.source_class.value_counts().sort_index().items()},
        "mean_qdesn_AQL": aggregate["AQL"],
        "mean_pricefm_AQL": aggregate["pricefm_AQL"],
        "mean_delta_AQL_qdesn_minus_pricefm": aggregate["mean_delta"],
        "median_delta_AQL_qdesn_minus_pricefm": aggregate["median_delta"],
        "direct_comparison_metrics": {
            "qdesn": {"AQL": aggregate["AQL"], "AQCR_percent": aggregate["AQCR_percent"], "MAE": aggregate["MAE"], "RMSE": aggregate["RMSE"]},
            "pricefm": {"AQL": aggregate["pricefm_AQL"], "AQCR_percent": aggregate["pricefm_AQCR_percent"], "MAE": aggregate["pricefm_MAE"], "RMSE": aggregate["pricefm_RMSE"]},
        },
        "historical_direct_comparison_metrics": historical_direct_metrics,
        "n_horizon_diagnostic_region_folds": 72,
        "horizon_rows": 288,
        "replaced_horizon_rows": 20,
        "replaced_horizon_cases": 5,
        "full_56_candidate_mean_AQL": float(decisions.candidate_test_AQL.mean()),
        "full_56_authoritative_mean_AQL": float(decisions.authoritative_qdesn_test_AQL.mean()),
        "full_56_pricefm_mean_AQL": float(decisions.cached_pricefm_test_AQL.mean()),
        "full_candidate_surface_promoted": False,
        "models_fitted": False,
        "selection_changed_after_test": False,
        "validation_selected_family_changed_during_test_scoring": False,
        "outputs": {
            name: artifact_relative(final_output / path.name)
            for name, path in output_files.items()
        },
        "output_sha256": {name: sha256(path) for name, path in output_files.items()},
    }
    summary_path = output / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    for name, path in output_files.items():
        if sha256(path) != summary["output_sha256"][name]:
            raise RuntimeError(f"R92 output changed before publication: {path}")
    output.rename(final_output)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> int:
    run(parser().parse_args())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
