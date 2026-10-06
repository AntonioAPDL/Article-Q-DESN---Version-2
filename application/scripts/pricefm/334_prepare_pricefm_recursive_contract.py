#!/usr/bin/env python3
"""Freeze the read-only R101 recursive PriceFM panel contract.

R101 consumes the completed R100 train/validation-only closeout and the R98
authority.  It writes immutable control/primary panel manifests and provenance
only.  It never opens outer-test metrics, fits a model, writes launch YAML, or
authorizes registry/article mutation.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
from typing import Any, Iterable

import pandas as pd

from pricefm_common import sha256_file, write_json
from pricefm_graph import graph_adj_matrix, graph_hash, graph_scope_manifest_for_policy
from pricefm_recursive_adapter import normalize_spec, spec_identities


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R98_DIR = DATA / "authoritative/pricefm_stage_r98_validity_first_authority_closeout_20260913"
R100_DIR = DATA / "campaigns/pricefm_stage_r100_targeted_normal_recovery_20260913"
R100_PREP = DATA / "launch_prep/pricefm_stage_r100_targeted_normal_recovery_20260913"
OUTPUT = DATA / "launch_prep/pricefm_stage_r101_recursive_contract_20260916"
QUANTILES = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]
FOLDS = [1, 2, 3]


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--r98-registry", type=Path, default=R98_DIR / "pricefm_stage_r98_authoritative_registry.csv")
    p.add_argument("--r100-campaign", type=Path, default=R100_DIR)
    p.add_argument("--r100-prep", type=Path, default=R100_PREP)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--write", action="store_true", help="materialize outputs after all gates pass")
    p.add_argument("--force", action="store_true")
    return p


def _json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def _bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes"}


def _path(value: Any) -> Path:
    path = Path(str(value))
    if not path.is_file():
        raise FileNotFoundError(path)
    return path


def _same(values: Iterable[Any], label: str) -> Any:
    values = list(values)
    if not values or any(value != values[0] for value in values[1:]):
        raise RuntimeError("{} must be identical across folds".format(label))
    return values[0]


def _feature_manifest_from_selected(selected: Path, artifact_repo: Path) -> Path:
    if selected.suffix.lower() == ".csv":
        frame = pd.read_csv(selected)
        if frame.empty or "feature_manifest_path" not in frame:
            raise RuntimeError("selected atom manifest lacks feature_manifest_path: {}".format(selected))
        return _path(frame.iloc[0].feature_manifest_path)
    surface = _json(selected)
    if str(surface.get("region")) != "SE_2":
        raise RuntimeError("JSON selected surface needs an explicit feature-manifest rule: {}".format(selected))
    return _path(
        artifact_repo
        / "application/data_local/pricefm/runs/pricefm_stage_r93_region_frozen_quantile_validation_20260906"
        / "r93_se2_region_frozen/adapter/feature_manifest.json"
    )


def _se2_fold_source(artifact_repo: Path, fold: int) -> dict[str, Path | str]:
    data = artifact_repo / "application/data_local/pricefm"
    if fold == 1:
        run = data / "runs/pricefm_stage_r93_region_frozen_quantile_validation_20260906/r93_se2_region_frozen/adapter"
        scaler = data / "processed_stage_r93_region_frozen_outer_20260906/scalers/fold_1/per_region_separate_xy_scalers.joblib"
    else:
        run = data / "runs/pricefm_stage_r95_region_frozen_allfold_validation_20260907/normal/cells/region=SE_2/fold={}/adapter".format(fold)
        scaler = data / "processed_stage_r95_region_frozen_allfold_20260907/scalers/fold_{}/per_region_separate_xy_scalers.joblib".format(fold)
    return {
        "feature_manifest_path": _path(run / "feature_manifest.json"),
        "scaler_path": _path(scaler),
        "validation_rows_path": _path(run / "rows_val.csv"),
        "source_case_config_path": "",
    }


def _fold_provenance_row(
    region: str,
    fold: int,
    selected: Path,
    source: dict[str, Any],
) -> dict[str, Any]:
    feature_path = _path(source["feature_manifest_path"])
    scaler_path = _path(source["scaler_path"])
    rows_path = _path(source["validation_rows_path"])
    config_value = source.get("source_case_config_path", "")
    config_path = _path(config_value) if str(config_value) else None
    feature = _json(feature_path)
    source_windows = (feature.get("feature_policy_manifest") or {}).get("source_windows") or []
    target_windows = [item for item in source_windows if str(item.get("region")) == region]
    if len(target_windows) != 1:
        raise RuntimeError("feature manifest must identify one target train window: {} fold {}".format(region, fold))
    window = target_windows[0]
    window_manifest_path = Path(str(window["manifest_path"]))
    window_manifest_available = window_manifest_path.is_file()
    window_manifest_current_sha256 = sha256_file(window_manifest_path) if window_manifest_available else ""
    window_manifest_hash_matches_frozen = (
        window_manifest_available and window_manifest_current_sha256 == str(window["manifest_sha256"])
    )
    if window_manifest_available:
        window_manifest = _json(window_manifest_path)
        expected_shape = {
            "X_lag_shape": list(window["lag_shape"]),
            "X_lead_shape": list(window["lead_shape"]),
            "Y_shape": list(window["response_shape"]),
        }
        if any(list(window_manifest.get(key) or []) != value for key, value in expected_shape.items()):
            raise RuntimeError("rebuilt target window shape differs from frozen feature provenance")
        if str(window_manifest.get("region")) != region or int(window_manifest.get("fold")) != int(fold):
            raise RuntimeError("rebuilt target window identity differs from frozen feature provenance")
        window_path = Path(str(window["window_path"]))
        if window_path.is_file() and sha256_file(window_path) != str(window["window_sha256"]):
            raise RuntimeError("rebuilt target window data hash differs from frozen feature provenance")
        lag_features = [str(x) for x in window_manifest.get("lag_features") or []]
        lead_features = [str(x) for x in window_manifest.get("lead_features") or []]
    else:
        # R97 compaction intentionally removed some rebuildable window files.
        # Their frozen paths/hashes/shapes remain in the feature manifest.
        window_manifest = {}
        lag_features = ["price", "load", "solar", "wind"]
        lead_features = ["load", "solar", "wind"]
        if list(window.get("lag_shape") or [])[-1:] != [4] or list(window.get("lead_shape") or [])[-1:] != [3]:
            raise RuntimeError("archived window dimensions do not match the frozen PriceFM input contract")
    if "price" not in lag_features or "price" in lead_features:
        raise RuntimeError("PriceFM endogenous/exogenous feature contract is unexpected")
    validation_rows = pd.read_csv(
        rows_path,
        usecols=["origin_id", "horizon", "origin_market_time", "response_market_time"],
    )
    return {
        "region": region,
        "fold": int(fold),
        "source_selected_atom_manifest": str(selected.resolve()),
        "source_selected_atom_manifest_sha256": sha256_file(selected),
        "feature_manifest_path": str(feature_path.resolve()),
        "feature_manifest_sha256": sha256_file(feature_path),
        "scaler_path": str(scaler_path.resolve()),
        "scaler_sha256": sha256_file(scaler_path),
        "validation_rows_path": str(rows_path.resolve()),
        "validation_rows_sha256": sha256_file(rows_path),
        "source_case_config_path": str(config_path.resolve()) if config_path else "",
        "source_case_config_sha256": sha256_file(config_path) if config_path else "",
        "target_train_window_manifest_path": str(window_manifest_path),
        "target_train_window_manifest_sha256": str(window["manifest_sha256"]),
        "target_train_window_manifest_current_sha256": window_manifest_current_sha256,
        "target_train_window_manifest_hash_matches_frozen": window_manifest_hash_matches_frozen,
        "target_train_window_manifest_available": window_manifest_available,
        "target_train_window_data_path": str(window["window_path"]),
        "target_train_window_data_sha256": str(window["window_sha256"]),
        "train_context_start": window_manifest.get("context_start"),
        "train_context_end": window_manifest.get("context_end"),
        "train_target_start": window_manifest.get("target_start"),
        "train_target_end": window_manifest.get("target_end"),
        "train_origin_count": int(window_manifest.get("n_origins", window["n_origins"])),
        "lag_window": int(window_manifest.get("lag_window", window["lag_shape"][1])),
        "forecast_horizon": int(window_manifest.get("lead_window", window["lead_shape"][1])),
        "validation_origin_count": int(validation_rows.origin_id.nunique()),
        "validation_origin_start": str(validation_rows.origin_market_time.min()),
        "validation_origin_end": str(validation_rows.origin_market_time.max()),
        "validation_response_end": str(validation_rows.response_market_time.max()),
        "validation_horizons": sorted(validation_rows.horizon.astype(int).unique().tolist()),
        "endogenous_lag_features": ["price"],
        "exogenous_lag_features": [name for name in lag_features if name != "price"],
        "admissible_lead_features": lead_features,
        "lead_covariate_status": "realized_ex_post",
        "recursive_price_source_after_origin": "generated_normal_model_path_only",
        "test_opened": False,
    }


def load_r98_specs(
    registry_path: Path, artifact_repo: Path
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    registry = pd.read_csv(registry_path, low_memory=False)
    expected_regions = list(graph_adj_matrix())
    if sorted(registry.region.astype(str).unique()) != sorted(expected_regions):
        raise RuntimeError("R98 registry must cover exactly the 38 PriceFM regions")
    rows: list[dict[str, Any]] = []
    sources: list[dict[str, Any]] = []
    fold_rows: list[dict[str, Any]] = []
    invariant_columns = [
        "lag_window", "depth", "units", "alpha", "rho", "input_scale",
        "feature_policy", "state_output", "rhs_tau0", "selected_atom_manifest_path",
        "selected_atom_manifest_sha256",
    ]
    for region in expected_regions:
        part = registry[registry.region.astype(str).eq(region)].sort_values("fold")
        if part.fold.astype(int).tolist() != FOLDS:
            raise RuntimeError("R98 region {} must have folds 1,2,3".format(region))
        for column in invariant_columns:
            _same(part[column].astype(str).tolist(), "{} {}".format(region, column))
        first = part.iloc[0]
        selected = _path(first.selected_atom_manifest_path)
        if sha256_file(selected) != str(first.selected_atom_manifest_sha256):
            raise RuntimeError("R98 selected atom hash mismatch: {}".format(selected))
        feature_path = _feature_manifest_from_selected(selected, artifact_repo)
        feature = _json(feature_path)
        policy = feature.get("feature_policy_manifest") or {}
        reservoir = feature.get("reservoir") or {}
        spec = normalize_spec({
            "region": region,
            "feature_policy": first.feature_policy,
            "lag_window": first.lag_window,
            "depth": first.depth,
            "units": first.units,
            "alpha": first.alpha,
            "rho": first.rho,
            "input_scale": first.input_scale,
            "state_output": first.state_output,
            "seed": feature.get("seed", reservoir.get("seed", 2026090601)),
            "spatial": policy.get("spatial") or {"graph_degree": 0 if first.feature_policy == "target_only" else 1},
            "tau0": first.rhs_tau0,
        })
        spec.update(spec_identities(spec))
        spec.update({
            "panel": "r98_control",
            "source_stage": "R98",
            "source_role": "frozen_authority_anchor",
            "source_selected_atom_manifest": str(selected.resolve()),
            "source_selected_atom_manifest_sha256": sha256_file(selected),
            "source_feature_manifest": str(feature_path.resolve()),
            "source_feature_manifest_sha256": sha256_file(feature_path),
            "source_readout_feature_count": int(len(feature.get("feature_names") or [])),
            "selection_split": "historical_validation_only",
            "test_used_for_selection": False,
        })
        rows.append(spec)
        sources.extend([
            {"role": "{}_r98_selected_atom".format(region), "path": str(selected.resolve()), "sha256": sha256_file(selected)},
            {"role": "{}_r98_feature_manifest".format(region), "path": str(feature_path.resolve()), "sha256": sha256_file(feature_path)},
        ])
        if selected.suffix.lower() == ".csv":
            atom_rows = pd.read_csv(selected)
            for fold in FOLDS:
                fold_atoms = atom_rows[atom_rows.fold.astype(int).eq(fold)]
                if sorted(fold_atoms.tau.astype(float).round(8).tolist()) != QUANTILES:
                    raise RuntimeError("R98 selected atom quantile coverage is incomplete: {} fold {}".format(region, fold))
                atom = fold_atoms.iloc[0]
                fold_rows.append(_fold_provenance_row(region, fold, selected, {
                    "feature_manifest_path": atom.feature_manifest_path,
                    "scaler_path": atom.scaler_path,
                    "validation_rows_path": atom.rows_val_path,
                    "source_case_config_path": atom.source_case_config_path,
                }))
        else:
            for fold in FOLDS:
                fold_rows.append(_fold_provenance_row(region, fold, selected, _se2_fold_source(artifact_repo, fold)))
    return rows, sources, fold_rows


def audit_r100_campaign(campaign: Path, verify_hashes: bool = True) -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    terminal_path = _path(campaign / "campaign_terminal.json")
    terminal = _json(terminal_path)
    expected = {
        "status": "completed_normal_winners_frozen",
        "regions_complete": 17,
        "test_opened": False,
        "quantile_fit_started": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    for key, value in expected.items():
        if terminal.get(key) != value:
            raise RuntimeError("R100 campaign terminal gate failed: {}".format(key))
    progress = _json(_path(campaign / "rhs_progress.json"))
    if (progress.get("complete"), progress.get("total"), progress.get("failed")) != (1530, 1530, 0):
        raise RuntimeError("R100 RHS progress is not a clean 1530/1530 closeout")
    winners = pd.read_csv(_path(campaign / "pricefm_stage_r100_frozen_normal_winners.csv"))
    if len(winners) != 17 or winners.region.astype(str).duplicated().any():
        raise RuntimeError("R100 must freeze exactly 17 unique region winners")

    audit_rows = []
    sources = [{"role": "r100_campaign_terminal", "path": str(terminal_path.resolve()), "sha256": sha256_file(terminal_path)}]
    for winner in winners.itertuples(index=False):
        region = str(winner.region)
        contract_path = _path(winner.contract)
        contract = _json(contract_path)
        if not contract.get("eligible") or not contract.get("converged") or contract.get("selection_uses_test"):
            raise RuntimeError("R100 winner is not validation-only eligible: {}".format(region))
        if any(contract.get(key) for key in ("test_access_authorized", "test_scoring_authorized", "quantile_fit_authorized", "registry_mutation_authorized", "article_mutation_authorized")):
            raise RuntimeError("R100 winner opens a forbidden surface: {}".format(region))
        ranking_path = _path(campaign / "regions" / region / "rhs_closeout/pricefm_stage_r100_rhs_ranking.csv")
        ranking = pd.read_csv(ranking_path)
        eligible = ranking[ranking.eligible.map(_bool)]
        if len(ranking) != 90 or eligible.empty:
            raise RuntimeError("R100 RHS ranking is incomplete: {}".format(region))
        if str(eligible.iloc[0].experiment_id) != str(contract["experiment_id"]):
            raise RuntimeError("R100 frozen winner does not match rank one: {}".format(region))
        compact_terminals = sorted((campaign / "regions" / region / "rhs_runs").glob("*/r100_compaction_terminal.json"))
        if len(compact_terminals) != 90:
            raise RuntimeError("R100 compact terminal count is not 90: {}".format(region))
        retained_count = 0
        retained_bytes = 0
        hash_failures = 0
        for compact_path in compact_terminals:
            compact = _json(compact_path)
            if compact.get("status") != "completed_compacted" or compact.get("test_opened"):
                raise RuntimeError("invalid R100 compaction terminal: {}".format(compact_path))
            if compact.get("binary_model_artifacts_retained"):
                raise RuntimeError("R100 compaction unexpectedly retained binary models")
            retained = compact.get("retained") or []
            if len(retained) != 6:
                raise RuntimeError("R100 compaction terminal must retain six audit files")
            for item in retained:
                path = _path(item["path"])
                retained_count += 1
                retained_bytes += int(item["bytes"])
                if path.stat().st_size != int(item["bytes"]):
                    hash_failures += 1
                elif verify_hashes and sha256_file(path) != str(item["sha256"]):
                    hash_failures += 1
        if hash_failures:
            raise RuntimeError("R100 retained artifact verification failed: {}".format(region))
        audit_rows.append({
            "region": region,
            "rhs_experiments": len(ranking),
            "eligible_rhs_experiments": len(eligible),
            "compaction_terminals": len(compact_terminals),
            "retained_files": retained_count,
            "retained_bytes": retained_bytes,
            "retained_hash_failures": hash_failures,
            "winner_experiment_id": contract["experiment_id"],
            "winner_validation_AQL": float(contract["median_validation_AQL"]),
            "test_opened": False,
            "status": "verified_complete",
        })
        sources.extend([
            {"role": "{}_r100_winner_contract".format(region), "path": str(contract_path.resolve()), "sha256": sha256_file(contract_path)},
            {"role": "{}_r100_rhs_ranking".format(region), "path": str(ranking_path.resolve()), "sha256": sha256_file(ranking_path)},
        ])
    return pd.DataFrame(audit_rows), sources


def load_r100_specs(campaign: Path, prep: Path) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]]]:
    winners_path = _path(campaign / "pricefm_stage_r100_frozen_normal_winners.csv")
    winners = pd.read_csv(winners_path)
    specs: dict[str, dict[str, Any]] = {}
    sources = [{"role": "r100_frozen_winners", "path": str(winners_path.resolve()), "sha256": sha256_file(winners_path)}]
    for winner in winners.itertuples(index=False):
        region = str(winner.region)
        contract_path = _path(winner.contract)
        contract = _json(contract_path)
        candidate_path = _path(
            prep / "regions" / region / "ridge_prep/pricefm_stage_r100_ridge_candidate_manifest.csv"
        )
        candidates = pd.read_csv(candidate_path)
        selected = candidates[candidates.candidate_id.astype(str).eq(str(contract["parent_ridge_candidate_id"]))]
        if len(selected) != 1:
            raise RuntimeError("R100 parent candidate is not unique: {}".format(region))
        row = selected.iloc[0].to_dict()
        row["tau0"] = contract["tau0"]
        spec = normalize_spec(row)
        spec.update(spec_identities(spec))
        spec.update({
            "panel": "r100_primary",
            "source_stage": "R100",
            "source_role": str(row["candidate_role"]),
            "source_experiment_id": str(contract["experiment_id"]),
            "source_parent_candidate_id": str(contract["parent_ridge_candidate_id"]),
            "source_winner_contract": str(contract_path.resolve()),
            "source_winner_contract_sha256": sha256_file(contract_path),
            "source_candidate_manifest": str(candidate_path.resolve()),
            "source_candidate_manifest_sha256": sha256_file(candidate_path),
            "selection_split": "fold1_train_internal_temporal_validation",
            "test_used_for_selection": False,
        })
        specs[region] = spec
        sources.append({"role": "{}_r100_candidate_manifest".format(region), "path": str(candidate_path.resolve()), "sha256": sha256_file(candidate_path)})
    return specs, sources


def _serialize(frame: pd.DataFrame) -> pd.DataFrame:
    output = frame.copy()
    for column in (
        "units", "spatial", "active_regions", "neighbor_regions",
        "endogenous_lag_features", "exogenous_lag_features",
        "admissible_lead_features", "validation_horizons",
    ):
        if column in output:
            output[column] = output[column].map(
                lambda value: json.dumps(value, sort_keys=True, separators=(",", ":"))
                if isinstance(value, (dict, list)) else value
            )
    return output


def _panel_row(spec: dict[str, Any], panel: str, graph_regions: list[str]) -> dict[str, Any]:
    row = dict(spec)
    row["panel"] = panel
    graph = graph_scope_manifest_for_policy(
        spec["region"], graph_regions, spec["feature_policy"], spatial=spec["spatial"]
    )
    row["active_regions"] = graph["active_regions"]
    row["neighbor_regions"] = graph["neighbor_regions"]
    row["graph_hash"] = graph["graph_hash"]
    row["recursive_training_contract"] = "causal_teacher_forcing_t_from_information_through_t_minus_1"
    row["recursive_forecast_contract"] = "synchronous_38_region_panel_generated_prices_only_after_origin"
    row["normal_driver_contract"] = "ridge_self_recursive;rhs_self_recursive"
    row["quantile_driver_contract"] = "common_normal_rhs_paths_no_quantile_feedback"
    row["warm_start_contract"] = "upstream_fits_initialize_optimization_only_and_never_redefine_priors"
    row["prior_contract"] = "tau0_and_all_fixed_hyperparameters_are_frozen_before_outer_test_access"
    row["posterior_paths"] = 500
    row["registry_mutation_authorized"] = False
    row["article_mutation_authorized"] = False
    row["test_scoring_authorized"] = False
    row["launch_authorized"] = False
    return row


def build_contract(args: argparse.Namespace) -> dict[str, Any]:
    artifact_repo = args.artifact_repo.resolve()
    r98_path = args.r98_registry.resolve()
    r100 = args.r100_campaign.resolve()
    prep = args.r100_prep.resolve()
    audit, audit_sources = audit_r100_campaign(r100, verify_hashes=True)
    r98_specs, r98_sources, fold_rows = load_r98_specs(r98_path, artifact_repo)
    r100_specs, r100_sources = load_r100_specs(r100, prep)
    regions = list(graph_adj_matrix())
    if set(r100_specs) != set(audit.region.astype(str)):
        raise RuntimeError("R100 specs and audited closeouts disagree")
    fold_provenance = pd.DataFrame(fold_rows).sort_values(["region", "fold"])
    if len(fold_provenance) != 114 or fold_provenance[["region", "fold"]].duplicated().any():
        raise RuntimeError("R101 fold provenance must contain 38 x 3 rows")

    control = [_panel_row(spec, "r98_control", regions) for spec in r98_specs]
    primary = []
    for r98_spec in r98_specs:
        selected = r100_specs.get(r98_spec["region"], r98_spec)
        primary.append(_panel_row(selected, "r100_primary" if selected is not r98_spec else "r98_primary", regions))
    control_map = {row["region"]: row for row in control}
    for row in primary:
        base = control_map[row["region"]]
        row["differs_from_r98_structure"] = row["structure_sha256"] != base["structure_sha256"]
        row["differs_from_r98_contract"] = row["contract_sha256"] != base["contract_sha256"]
    for row in control:
        row["differs_from_r98_structure"] = False
        row["differs_from_r98_contract"] = False

    combined = pd.DataFrame(control + primary)
    unique_structures = combined.sort_values(["structure_sha256", "panel"]).drop_duplicates("structure_sha256")
    unique_contracts = combined.sort_values(["contract_sha256", "panel"]).drop_duplicates("contract_sha256")
    primary_frame = pd.DataFrame(primary)
    if len(control) != 38 or len(primary) != 38:
        raise RuntimeError("both R101 panels must contain exactly 38 regions")
    if int(primary_frame.differs_from_r98_structure.sum()) != 10:
        raise RuntimeError("R101 expected exactly 10 R100 structural replacements")
    if int(primary_frame.differs_from_r98_contract.sum()) != 11:
        raise RuntimeError("R101 expected exactly 11 R100 full-contract replacements")
    if len(unique_structures) != 48 or len(unique_contracts) != 49:
        raise RuntimeError("R101 unique structure/full-contract counts disagree")
    if combined.test_used_for_selection.map(_bool).any():
        raise RuntimeError("R101 source selection touched test outcomes")

    gates = pd.DataFrame([
        ("r100_completed_cleanly", len(audit) == 17 and audit.retained_hash_failures.sum() == 0, len(audit)),
        ("r100_rhs_complete", int(audit.rhs_experiments.sum()) == 1530, int(audit.rhs_experiments.sum())),
        ("r100_retained_files_hash_valid", int(audit.retained_files.sum()) == 9180, int(audit.retained_files.sum())),
        ("control_panel_complete", len(control) == 38, len(control)),
        ("primary_panel_complete", len(primary) == 38, len(primary)),
        ("fold_provenance_complete", len(fold_provenance) == 114, len(fold_provenance)),
        ("unique_structures", len(unique_structures) == 48, len(unique_structures)),
        ("unique_full_contracts", len(unique_contracts) == 49, len(unique_contracts)),
        ("r100_structural_replacements", int(primary_frame.differs_from_r98_structure.sum()) == 10, int(primary_frame.differs_from_r98_structure.sum())),
        ("r100_full_contract_replacements", int(primary_frame.differs_from_r98_contract.sum()) == 11, int(primary_frame.differs_from_r98_contract.sum())),
        ("graph_hash_current", combined.graph_hash.eq(graph_hash()).all(), graph_hash()),
        ("selection_firewall", not combined.test_used_for_selection.map(_bool).any(), False),
        ("launch_registry_article_blocked", True, "blocked"),
    ], columns=["gate", "passed", "observed"])
    if not gates.passed.all():
        raise RuntimeError("R101 contract gate failed")

    fold_sources: list[dict[str, Any]] = []
    for row in fold_rows:
        prefix = "{}_fold{}".format(row["region"], row["fold"])
        for role, path_key, hash_key in (
            ("feature_manifest", "feature_manifest_path", "feature_manifest_sha256"),
            ("scaler", "scaler_path", "scaler_sha256"),
            ("validation_rows", "validation_rows_path", "validation_rows_sha256"),
            ("source_case_config", "source_case_config_path", "source_case_config_sha256"),
        ):
            if row.get(path_key):
                fold_sources.append({"role": "{}_{}".format(prefix, role), "path": row[path_key], "sha256": row[hash_key]})
        if row.get("target_train_window_manifest_available", False):
            fold_sources.append({
                "role": "{}_current_train_window_manifest".format(prefix),
                "path": row["target_train_window_manifest_path"],
                "sha256": row["target_train_window_manifest_current_sha256"],
            })
    script_path = Path(__file__).resolve()
    adapter_path = script_path.parent / "pricefm_recursive_adapter.py"
    engine_path = script_path.parents[2] / "R/pricefm_recursive_forecast.R"
    source_rows = r98_sources + r100_sources + audit_sources + fold_sources + [
        {"role": "r98_registry", "path": str(r98_path), "sha256": sha256_file(r98_path)},
        {"role": "r101_contract_compiler", "path": str(script_path), "sha256": sha256_file(script_path)},
        {"role": "r101_recursive_adapter", "path": str(adapter_path), "sha256": sha256_file(adapter_path)},
        {"role": "r101_recursive_engine", "path": str(engine_path), "sha256": sha256_file(engine_path)},
    ]
    source_frame = pd.DataFrame(source_rows).drop_duplicates(["path", "sha256"]).sort_values(["role", "path"])
    summary = {
        "stage": "R101",
        "status": "completed_recursive_contract_engine_ready",
        "r100_regions_audited": 17,
        "r100_rhs_experiments_verified": int(audit.rhs_experiments.sum()),
        "r100_retained_files_verified": int(audit.retained_files.sum()),
        "control_panel_regions": 38,
        "primary_panel_regions": 38,
        "region_fold_contracts": 114,
        "fold_window_manifests_available": int(fold_provenance.get("target_train_window_manifest_available", pd.Series(False, index=fold_provenance.index)).sum()),
        "fold_window_manifest_hashes_unchanged": int(fold_provenance.get("target_train_window_manifest_hash_matches_frozen", pd.Series(False, index=fold_provenance.index)).sum()),
        "fold_window_manifest_hashes_rebuilt_or_archived": int((~fold_provenance.get("target_train_window_manifest_hash_matches_frozen", pd.Series(False, index=fold_provenance.index))).sum()),
        "r100_structural_replacements": 10,
        "r100_full_contract_replacements": 11,
        "unique_structures": 48,
        "unique_full_contracts": 49,
        "folds": FOLDS,
        "quantiles": QUANTILES,
        "posterior_paths_default": 500,
        "graph_sha256": graph_hash(),
        "selection_uses_test": False,
        "launch_yaml_written": False,
        "model_fit_started": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "test_scoring_authorized": False,
        "next_gate": "R102_recursive_normal_refits_only_after_R101_tests_and_review",
    }
    return {
        "summary": summary,
        "control": pd.DataFrame(control),
        "primary": primary_frame,
        "fold_provenance": fold_provenance,
        "unique_structures": unique_structures,
        "unique_contracts": unique_contracts,
        "audit": audit,
        "gates": gates,
        "sources": source_frame,
    }


def materialize(bundle: dict[str, Any], output: Path, force: bool = False) -> dict[str, Any]:
    output = output.resolve()
    if output.exists() and any(output.iterdir()) and not force:
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    files = {
        "control_panel": "pricefm_stage_r101_r98_control_panel.csv",
        "primary_panel": "pricefm_stage_r101_r100_primary_panel.csv",
        "fold_provenance": "pricefm_stage_r101_region_fold_provenance.csv",
        "unique_structures": "pricefm_stage_r101_unique_structure_manifest.csv",
        "unique_contracts": "pricefm_stage_r101_unique_contract_manifest.csv",
        "r100_audit": "pricefm_stage_r101_r100_closeout_audit.csv",
        "gates": "pricefm_stage_r101_gates.csv",
        "sources": "source_manifest.csv",
    }
    for key, filename in files.items():
        frame_key = {"control_panel": "control", "primary_panel": "primary", "r100_audit": "audit"}.get(key, key)
        _serialize(bundle[frame_key]).to_csv(output / filename, index=False, quoting=csv.QUOTE_MINIMAL)
    summary = dict(bundle["summary"])
    summary["output_files"] = files
    summary["output_sha256"] = {key: sha256_file(output / filename) for key, filename in files.items()}
    write_json(output / "summary.json", summary)
    report = """# PriceFM Stage-R101 recursive contract closeout

R101 passed its read-only contract gate. The completed R100 evidence was
reverified without opening outer-test metrics: 1,530 RHS experiments, 9,180
retained audit files, 17 eligible validation-selected winners, and zero hash
failures.

The recursive comparison is pre-registered as two complete 38-region panels.
The control panel uses R98 everywhere. The primary panel uses the frozen R100
winner in the 17 targeted regions and R98 elsewhere. R100 changes 10 reservoir
structures and 11 complete structure-plus-`tau0` contracts; Austria is the
extra prior-only change. Across both panels there are 48 unique structures and
49 unique full contracts.

The forecast contract is causal and synchronous: every region at horizon `h`
is built from the same panel snapshot through `h-1`; all regional predictions
and draws are completed before any history is updated. Ridge and Normal RHS
self-recurse. Quantile models consume common Normal-RHS price paths and do not
feed their outputs back into the primary state path. The default is 500 paired
paths, with a later pre-test numerical stability check.

No launch YAML, fit, outer-test score, registry mutation, or article mutation
was produced. R102 remains blocked until the R101 source and focused tests are
reviewed.
"""
    (output / "pricefm_stage_r101_recursive_contract_closeout.md").write_text(report)
    summary["output_sha256"]["report"] = sha256_file(output / "pricefm_stage_r101_recursive_contract_closeout.md")
    write_json(output / "summary.json", summary)
    return summary


def run(args: argparse.Namespace) -> dict[str, Any]:
    bundle = build_contract(args)
    if args.write:
        return materialize(bundle, args.output_dir, force=args.force)
    return bundle["summary"]


def main() -> None:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
