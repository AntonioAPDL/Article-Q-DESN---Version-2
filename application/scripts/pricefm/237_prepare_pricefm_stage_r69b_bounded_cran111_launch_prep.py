#!/usr/bin/env python3
"""Prepare the bounded PriceFM Stage-R69B CRAN 1.1.1 launch manifest."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from typing import Any

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R69A = DATA / "authoritative/pricefm_stage_r69a_spec_anchor_audit_20260831"
R67_RUNTIME = DATA / "runtime_libraries/exdqlm_cran_1p1p1/pricefm_r67_cran111_install_manifest.json"
TAG = "pricefm_stage_r69b_bounded_cran111_independent_vb_20260831"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r69b_bounded_cran111_launch_prep_20260831"
PYTHON = DATA / "venv/bin/python"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
METHOD_AL = "qdesn_al_rhs_ns_cran111_r69b"
METHOD_EXAL = "qdesn_exal_rhs_ns_cran111_r69b"
CRAN111_SHA256 = "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
RUNTIME_EXPORTS = {
    "exalStaticLDVB",
    "exal_make_vb_control",
    "exal_make_vb_sigmagam_control",
}
FORK_ONLY_EXPORTS = {
    "beta_prior",
    "exal_ldvb_fit",
    "normal_desn_fit",
    "qdesn_fit_vb",
}
SIGMAGAM_PROFILE = {
    "factorization": "structured",
    "structured_grid_size": 151,
    "structured_span_sd": 6.0,
    "freeze_warmup_iters": 10,
    "force_after_warmup": True,
    "postwarmup_damping": 0.2,
    "postwarmup_damping_iters": 30,
    "min_postwarmup_updates": 35,
}
BLOCKED_COLUMNS = (
    "launch_authorized",
    "launcher_invoked_by_prep",
    "test_access_authorized",
    "registry_mutation_authorized",
    "article_mutation_authorized",
    "joint_model_authorized",
    "mcmc_authorized",
)
BINARY_SUFFIXES = {".rds", ".rda", ".RData", ".rdata"}


def parser() -> argparse.ArgumentParser:
    root = Path(__file__).resolve().parents[3]
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, default=root)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--r69a-dir", type=Path, default=R69A)
    p.add_argument("--runtime-manifest", type=Path, default=R67_RUNTIME)
    p.add_argument("--python-bin", type=Path, default=PYTHON)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--tag", default=TAG)
    p.add_argument("--expected-targets", type=int, default=56)
    p.add_argument("--expected-quantiles", type=float, nargs="+", default=list(TAUS))
    p.add_argument("--recommended-workers", type=int, default=20)
    p.add_argument("--write-launch-yaml", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def git_head(path: Path) -> str | None:
    if not path.exists():
        return None
    try:
        return subprocess.check_output(
            ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
        ).strip()
    except Exception:
        return None


def prepare_dir(path: Path, force: bool) -> Path:
    path = path.resolve()
    if path.exists() and any(path.iterdir()):
        if not force:
            raise FileExistsError(path)
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)
    return path


def read_json(path: Path, label: str) -> dict[str, Any]:
    if not path.is_file():
        raise FileNotFoundError(f"Missing {label}: {path}")
    return json.loads(path.read_text())


def read_csv(path: Path, label: str) -> pd.DataFrame:
    if not path.is_file():
        raise FileNotFoundError(f"Missing {label}: {path}")
    return pd.read_csv(path, low_memory=False)


def load_yaml(path: Path) -> dict[str, Any]:
    payload = yaml.safe_load(path.read_text())
    if not isinstance(payload, dict):
        raise RuntimeError(f"YAML did not parse as a mapping: {path}")
    return payload


def boolish(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def text_value(value: Any) -> str:
    try:
        if pd.isna(value):
            return ""
    except (TypeError, ValueError):
        pass
    return str(value).strip()


def as_float(value: Any, default: float | None = None) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return default
    return number if pd.notna(number) else default


def as_int(value: Any, default: int | None = None) -> int | None:
    number = as_float(value)
    return default if number is None else int(number)


def parse_json_list(value: Any) -> list[Any]:
    if isinstance(value, list):
        return value
    text = text_value(value)
    if not text:
        return []
    parsed = json.loads(text)
    return parsed if isinstance(parsed, list) else [parsed]


def scalar_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def tau_key(value: Any) -> float:
    return round(float(value), 10)


def tau_slug(value: Any) -> str:
    return f"{float(value):.12g}".replace("-", "m").replace(".", "p")


def path_within(path: Path, root: Path) -> bool:
    path = path.resolve()
    root = root.resolve()
    return path == root or root in path.parents


def resolve(path: str | Path, artifact_repo: Path) -> Path:
    value = Path(path)
    return value.resolve() if value.is_absolute() else (artifact_repo / value).resolve()


def clean_slug(value: Any) -> str:
    return "".join(ch for ch in text_value(value).lower().replace("_", "") if ch.isalnum()) or "x"


def portable_data_config(source: Path, destination: Path, artifact_repo: Path) -> None:
    payload = load_yaml(source)
    block = payload.get("pricefm", {})
    block["allow_absolute_local_paths"] = True
    for key in ("raw_dir", "interim_dir", "processed_dir", "external_repo_dir", "log_dir"):
        value = block.get(key)
        if value and not Path(value).is_absolute():
            block[key] = str((artifact_repo / value).resolve())
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(yaml.safe_dump(payload, sort_keys=False))


def verify_runtime_manifest(path: Path) -> dict[str, Any]:
    manifest = read_json(path, "CRAN 1.1.1 runtime manifest")
    package = manifest.get("installed_package") or {}
    tarball = manifest.get("source_tarball") or {}
    exports = set(package.get("exports") or [])
    missing = sorted(RUNTIME_EXPORTS - exports)
    forbidden = sorted(FORK_ONLY_EXPORTS & exports)
    if manifest.get("status") != "installed_exact_cran_exdqlm_1.1.1":
        raise RuntimeError("R69B requires the exact CRAN exdqlm 1.1.1 runtime")
    if manifest.get("fork_source_used") is not False:
        raise RuntimeError("R69B must not use fork source for new fits")
    if package.get("version") != "1.1.1" or package.get("repository") != "CRAN":
        raise RuntimeError("R69B runtime package is not CRAN exdqlm 1.1.1")
    if tarball.get("sha256") != CRAN111_SHA256:
        raise RuntimeError("R69B runtime tarball SHA-256 changed")
    if missing or forbidden:
        raise RuntimeError(f"Unexpected exdqlm API; missing={missing}; fork_only={forbidden}")
    return manifest


def verify_r69a_inputs(args: argparse.Namespace) -> tuple[pd.DataFrame, pd.DataFrame, dict[str, Any]]:
    r69a = args.r69a_dir.resolve()
    anchors = read_csv(r69a / "pricefm_stage_r69a_spec_anchor_audit.csv", "R69A anchor audit")
    components = read_csv(
        r69a / "pricefm_stage_r69a_quantile_component_anchor_audit.csv",
        "R69A component audit",
    )
    gates = read_csv(r69a / "pricefm_stage_r69a_launch_readiness_gates.csv", "R69A gates")
    summary = read_json(r69a / "summary.json", "R69A summary")
    if summary.get("status") != "completed_read_only_spec_anchor_audit":
        raise RuntimeError(f"R69A is not launch-prep ready: {summary.get('status')}")
    if summary.get("targets") != args.expected_targets or len(anchors) != args.expected_targets:
        raise RuntimeError("R69A target count changed")
    if not gates.loc[gates["required"].map(boolish), "passed"].map(boolish).all():
        failed = gates.loc[gates["required"].map(boolish) & ~gates["passed"].map(boolish), "gate"].tolist()
        raise RuntimeError(f"R69A required gates failed: {failed}")
    if not anchors["anchor_launch_grade"].map(boolish).all():
        raise RuntimeError("R69B refuses non-launch-grade anchors")
    if anchors.duplicated(["region", "fold"]).any() or anchors.duplicated(["case_id"]).any():
        raise RuntimeError("R69A anchors must be unique by case and region/fold")
    expected_taus = sorted(tau_key(tau) for tau in args.expected_quantiles)
    for case_id, group in components.groupby("case_id"):
        observed = sorted(tau_key(value) for value in group["tau"].dropna())
        if observed != expected_taus:
            raise RuntimeError(f"R69A component quantiles changed for {case_id}: {observed}")
        file_columns = ["config_exists", "feature_manifest_exists", "metric_exists", "data_config_exists"]
        if not group[file_columns].apply(lambda col: col.map(boolish)).all().all():
            raise RuntimeError(f"R69A component files are incomplete for {case_id}")
    return anchors, components, summary


def selected_component(group: pd.DataFrame) -> pd.Series:
    tau50 = group[group["tau"].map(tau_key).eq(0.5)]
    if len(tau50) == 1:
        return tau50.iloc[0]
    return group.sort_values("tau").iloc[0]


def adapter_from_anchor(anchor: pd.Series, source_adapter: dict[str, Any]) -> dict[str, Any]:
    adapter = copy.deepcopy(source_adapter)
    units = [int(value) for value in parse_json_list(anchor["units_json"])]
    adapter.update({
        "feature_map": text_value(anchor["feature_map"]),
        "feature_dim": int(anchor["reservoir_feature_dim"]),
        "depth": int(anchor["depth_D"]),
        "units": units,
        "alpha": float(anchor["alpha"]),
        "rho": float(anchor["rho"]),
        "input_scale": float(anchor["input_scale"]),
        "projection_scale": float(anchor["projection_scale"]),
        "recurrent_sparsity": float(anchor["recurrent_sparsity"]),
        "reservoir_activation": text_value(anchor["reservoir_activation"]),
        "state_output": text_value(anchor["state_output"]),
    })
    graph_degree = as_int(anchor.get("graph_degree"))
    if graph_degree is None:
        adapter.pop("spatial", None)
    else:
        spatial = copy.deepcopy(adapter.get("spatial") or {})
        spatial["graph_degree"] = graph_degree
        adapter["spatial"] = spatial
    return adapter


def training_from_anchor(anchor: pd.Series, source_training: dict[str, Any]) -> dict[str, Any]:
    training = copy.deepcopy(source_training)
    training["train_origin_limit"] = int(anchor["train_origin_limit"])
    training["train_origin_selection"] = text_value(anchor["train_origin_selection"])
    training["selection_split"] = "val"
    training["selection_metric"] = "raw_original_seven_quantile_mean_AQL"
    training["test_metrics_role"] = "audit_only_after_frozen_validation_selection"
    return training


def qdesn_vb_from_source(source: dict[str, Any]) -> dict[str, Any]:
    qcfg = copy.deepcopy(source or {})
    max_iter = as_int(qcfg.get("max_iter"), 150) or 150
    n_samp_xi = as_int(qcfg.get("n_samp_xi"), 200) or 200
    n_samp = as_int(qcfg.get("n_samp"), 200) or 200
    qcfg.update({
        "likelihoods": ["al", "exal"],
        "public_api": "exalStaticLDVB",
        "beta_prior": "rhs_ns",
        "readout_modes": ["shared_static"],
        "max_iter": max(150, max_iter),
        "n_samp_xi": max(200, n_samp_xi),
        "n_samp": max(200, n_samp),
        "tol": as_float(qcfg.get("tol"), 1e-4),
        "verbose": False,
        "sigmagam": copy.deepcopy(SIGMAGAM_PROFILE),
        "exact_chunking_claimed": False,
        "fork_only_namespace_calls_authorized": False,
        "ignored_legacy_controls_under_cran111": sorted(
            set(qcfg.get("ignored_legacy_controls_under_cran111") or [])
            | {"chunking", "min_iter_elbo", "progress_every", "tol_par"}
        ),
    })
    return qcfg


def generated_config(
    args: argparse.Namespace,
    anchor: pd.Series,
    components: pd.DataFrame,
    runtime_manifest: dict[str, Any],
    config_path: Path,
    data_config: Path,
    adapter_dir: Path,
    model_dir: Path,
) -> dict[str, Any]:
    component = selected_component(components)
    source_config = resolve(component["config_path"], args.artifact_repo)
    source_payload = load_yaml(source_config)
    source_smoke = copy.deepcopy(source_payload["pricefm_desn_smoke"])
    runtime_library = Path(runtime_manifest["library"]).resolve()
    adapter_script = (args.code_root / "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R").resolve()
    smoke = copy.deepcopy(source_smoke)
    smoke["data_config"] = str(data_config.resolve())
    smoke["python_bin"] = str(args.python_bin.resolve())
    smoke["r_library"] = str(runtime_library)
    smoke["runtime_manifest"] = str(args.runtime_manifest.resolve())
    smoke["runtime_adapter_script"] = str(adapter_script)
    smoke["package_authority"] = "exact_CRAN_exdqlm_1.1.1_public_API"
    smoke["region"] = text_value(anchor["region"])
    smoke["fold"] = int(anchor["fold"])
    smoke["splits"] = ["train", "val"]
    smoke["quantiles"] = list(TAUS)
    smoke["feature_policy"] = text_value(anchor["feature_policy"])
    smoke["adapter"] = adapter_from_anchor(anchor, source_smoke.get("adapter") or {})
    smoke.setdefault("run", {})["output_dir"] = str(model_dir.resolve())
    smoke["adapter"]["output_dir"] = str(adapter_dir.resolve())
    smoke["rhs_ns"] = copy.deepcopy(source_smoke.get("rhs_ns") or {})
    smoke["rhs_ns"]["tau0"] = float(anchor["rhs_tau0"])
    smoke["qdesn_vb"] = qdesn_vb_from_source(source_smoke.get("qdesn_vb") or {})
    smoke["training"] = training_from_anchor(anchor, source_smoke.get("training") or {})
    smoke.setdefault("exact_equivalence", {})["enabled"] = False
    smoke["warm_start"] = {
        "enabled": True,
        "external_checkpoint_reuse_authorized": False,
        "within_case_al_to_exal_same_tau_authorized": True,
        "source": "none_until_future_r69c_or_r70_runner",
    }
    smoke["artifact_hygiene"] = {
        "enabled": True,
        "clean_model_patterns": sorted(BINARY_SUFFIXES),
        "preserve_patterns": [
            "metric_summary.csv",
            "metric_by_horizon.csv",
            "metric_by_horizon_group.csv",
            "model_method_summary.csv",
            "model_parameter_summary.csv",
            "model_trace_summary.csv",
            "model_predictions_scaled.csv",
            "predictions_with_naive_scaled.csv",
            "*.json",
            "*.log",
            "report.md",
        ],
    }
    source_rows = components.sort_values("tau")
    r69b = {
        "stage": "R69B",
        "tag": args.tag,
        "case_id": text_value(anchor["case_id"]),
        "selected_family_anchor": text_value(anchor["selected_family"]),
        "refit_priority": text_value(anchor["refit_priority"]),
        "operational_gap_class": text_value(anchor["operational_gap_class"]),
        "mechanism_queue": text_value(anchor["mechanism_queue"]),
        "source_r69a_anchor_sha256": sha256(args.r69a_dir / "pricefm_stage_r69a_spec_anchor_audit.csv"),
        "source_r69a_component_sha256": sha256(args.r69a_dir / "pricefm_stage_r69a_quantile_component_anchor_audit.csv"),
        "source_base_id": text_value(anchor["base_id"]),
        "source_panel_dir": text_value(anchor["panel_dir"]),
        "source_component_configs": source_rows["config_path"].astype(str).tolist(),
        "source_component_metrics": source_rows["metric_path"].astype(str).tolist(),
        "source_component_feature_manifests": source_rows["feature_manifest_path"].astype(str).tolist(),
        "method_ids": {"al": METHOD_AL, "exal": METHOD_EXAL},
        "selection_split": "val",
        "selection_metric": "raw_original_seven_quantile_mean_AQL",
        "test_metrics_role": "audit_only_after_frozen_validation_selection",
        "launch_authorized": False,
        "launcher_invoked_by_prep": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    return {"pricefm_desn_smoke": smoke, "pricefm_stage_r69b": r69b}


def case_row(
    anchor: pd.Series,
    config_path: Path,
    data_config: Path,
    adapter_dir: Path,
    model_dir: Path,
    runtime_manifest: dict[str, Any],
) -> dict[str, Any]:
    return {
        "case_id": text_value(anchor["case_id"]),
        "region": text_value(anchor["region"]),
        "fold": int(anchor["fold"]),
        "selected_family_anchor": text_value(anchor["selected_family"]),
        "refit_priority": text_value(anchor["refit_priority"]),
        "operational_gap_class": text_value(anchor["operational_gap_class"]),
        "mechanism_queue": text_value(anchor["mechanism_queue"]),
        "config": str(config_path.resolve()),
        "config_sha256": sha256(config_path),
        "data_config": str(data_config.resolve()),
        "data_config_sha256": sha256(data_config),
        "adapter_dir": str(adapter_dir.resolve()),
        "output_dir": str(model_dir.resolve()),
        "paper_quantiles": scalar_json(list(TAUS)),
        "expected_quantile_components": len(TAUS),
        "fit_family_surface": scalar_json(["al", "exal"]),
        "expected_al_method_id": METHOD_AL,
        "expected_exal_method_id": METHOD_EXAL,
        "package_authority": "exact_CRAN_exdqlm_1.1.1_public_API",
        "cran111_version": runtime_manifest["installed_package"]["version"],
        "cran111_repository": runtime_manifest["installed_package"]["repository"],
        "cran111_tarball_sha256": runtime_manifest["source_tarball"]["sha256"],
        "feature_policy": text_value(anchor["feature_policy"]),
        "input_scope": text_value(anchor["input_scope"]),
        "output_scope": text_value(anchor["output_scope"]),
        "spatial_information_set": text_value(anchor["spatial_information_set"]),
        "lead_covariate_status": text_value(anchor["lead_covariate_status"]),
        "depth_D": int(anchor["depth_D"]),
        "units_json": text_value(anchor["units_json"]),
        "n_per_layer": int(anchor["n_per_layer"]),
        "reservoir_feature_dim": int(anchor["reservoir_feature_dim"]),
        "alpha": float(anchor["alpha"]),
        "rho": float(anchor["rho"]),
        "input_scale": float(anchor["input_scale"]),
        "projection_scale": float(anchor["projection_scale"]),
        "recurrent_sparsity": float(anchor["recurrent_sparsity"]),
        "reservoir_activation": text_value(anchor["reservoir_activation"]),
        "state_output": text_value(anchor["state_output"]),
        "graph_degree": as_int(anchor.get("graph_degree"), ""),
        "rhs_tau0": float(anchor["rhs_tau0"]),
        "lag_window": int(anchor["lag_window"]),
        "lead_window": int(anchor["lead_window"]),
        "train_origin_limit": int(anchor["train_origin_limit"]),
        "train_origin_selection": text_value(anchor["train_origin_selection"]),
        "source_base_id": text_value(anchor["base_id"]),
        "source_panel_dir": text_value(anchor["panel_dir"]),
        "r69a_validation_AQL_recomputed": float(anchor["validation_AQL_recomputed"]),
        "qdesn_minus_operational_pricefm_AQL": float(anchor["qdesn_minus_operational_pricefm_AQL"]),
        "qdesn_minus_cached_pricefm_AQL": float(anchor["qdesn_minus_cached_pricefm_AQL"]),
        "selection_split": "val",
        "selection_is_validation_only": True,
        "selected_on_split": "val",
        "test_metrics_role": "audit_only_after_frozen_validation_selection",
        "launch_authorized": False,
        "launcher_invoked_by_prep": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
        "status": "prepared_not_launched",
    }


def component_rows(anchor: pd.Series, components: pd.DataFrame, config_path: Path, model_dir: Path) -> list[dict[str, Any]]:
    rows = []
    for component in components.sort_values("tau").itertuples(index=False):
        tau = tau_key(component.tau)
        rows.append({
            "case_id": text_value(anchor["case_id"]),
            "region": text_value(anchor["region"]),
            "fold": int(anchor["fold"]),
            "tau": tau,
            "component_dir": str((model_dir / "components" / f"tau={tau_slug(tau)}").resolve()),
            "case_config": str(config_path.resolve()),
            "source_config": text_value(component.config_path),
            "source_config_sha256": text_value(component.config_sha256),
            "source_feature_manifest": text_value(component.feature_manifest_path),
            "source_feature_manifest_sha256": text_value(component.feature_manifest_sha256),
            "source_metric": text_value(component.metric_path),
            "source_metric_sha256": text_value(component.metric_sha256),
            "historical_config_contains_test_split": boolish(component.historical_config_contains_test_split),
            "future_splits": scalar_json(["train", "val"]),
            "future_test_split_stripped": True,
            "expected_al_method_id": METHOD_AL,
            "expected_exal_method_id": METHOD_EXAL,
            "selection_role": "whole_seven_quantile_bundle_validation_selection_only",
            "test_access_authorized": False,
        })
    return rows


def build_launch_control(
    args: argparse.Namespace,
    case_manifest: Path,
    component_ledger: Path,
    runtime_manifest: dict[str, Any],
) -> dict[str, Any]:
    return {
        "pricefm_stage_r69b_launch_prep": {
            "tag": args.tag,
            "status": "prepared_not_launched",
            "case_manifest": str(case_manifest.resolve()),
            "component_ledger": str(component_ledger.resolve()),
            "run_root": str(args.run_dir.resolve()),
            "config_root": str((args.grid_dir / "configs/cases").resolve()),
            "runtime": {
                "package": "exdqlm",
                "version": "1.1.1",
                "repository": "CRAN",
                "library": runtime_manifest["library"],
                "source_tarball_sha256": runtime_manifest["source_tarball"]["sha256"],
                "public_api": "exalStaticLDVB",
                "adapter_script": str(
                    (args.code_root / "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R").resolve()
                ),
            },
            "fit_surface": {
                "cases": args.expected_targets,
                "quantiles": list(TAUS),
                "likelihoods": ["al", "exal"],
                "model_unit": "independent_region_fold_quantile_models",
                "selection_unit": "whole_seven_quantile_region_fold_bundle",
                "selection_split": "val",
                "test_metrics_role": "audit_only_after_frozen_validation_selection",
            },
            "recommended_launcher": {
                "stage": "future_stage_r70",
                "workers": int(args.recommended_workers),
                "one_core_per_model": True,
                "resume": True,
                "dry_run": False,
                "smoke_run": False,
                "force": False,
                "authorize_required": True,
                "prep_invokes_launcher": False,
            },
            "firewalls": {
                "splits": ["train", "val"],
                "test_access_authorized": False,
                "registry_mutation_authorized": False,
                "article_mutation_authorized": False,
                "joint_model_authorized": False,
                "mcmc_authorized": False,
            },
        }
    }


def readiness_gates(
    args: argparse.Namespace,
    cases: pd.DataFrame,
    components: pd.DataFrame,
    launch_yaml: Path | None,
    runtime_manifest: dict[str, Any],
) -> pd.DataFrame:
    expected_components = args.expected_targets * len(TAUS)
    blocked_false = True
    for column in BLOCKED_COLUMNS:
        if column in cases and cases[column].map(boolish).any():
            blocked_false = False
    case_configs = [Path(path) for path in cases["config"]]
    configs_train_val = []
    qdesn_public = []
    for path in case_configs:
        payload = load_yaml(path)
        smoke = payload["pricefm_desn_smoke"]
        configs_train_val.append([str(x) for x in smoke["splits"]] == ["train", "val"])
        qdesn_public.append(
            smoke.get("package_authority") == "exact_CRAN_exdqlm_1.1.1_public_API"
            and smoke.get("qdesn_vb", {}).get("public_api") == "exalStaticLDVB"
            and smoke.get("qdesn_vb", {}).get("fork_only_namespace_calls_authorized") is False
        )
    rows = [
        ("expected_case_count", len(cases) == args.expected_targets, len(cases)),
        ("unique_region_fold_cases", not cases.duplicated(["region", "fold"]).any(), len(cases)),
        ("expected_component_count", len(components) == expected_components, len(components)),
        ("seven_components_per_case", components.groupby("case_id").size().eq(len(TAUS)).all(), len(components)),
        ("paper_quantiles_exact", all(tuple(group["tau"].round(10)) == TAUS for _, group in components.groupby("case_id", sort=False)), scalar_json(list(TAUS))),
        ("train_validation_only_configs", all(configs_train_val), "train,val"),
        ("historical_test_split_stripped", components["future_test_split_stripped"].map(boolish).all(), "future configs only train,val"),
        ("case_specific_anchor_preserved", cases[["depth_D", "units_json", "rhs_tau0", "feature_policy", "lag_window", "state_output"]].notna().all().all(), "anchor fields non-missing"),
        ("cran111_runtime_chain_of_custody", runtime_manifest["source_tarball"]["sha256"] == CRAN111_SHA256, runtime_manifest["source_tarball"]["sha256"]),
        ("public_api_only", all(qdesn_public), "exalStaticLDVB"),
        ("al_exal_surface_planned", cases["fit_family_surface"].astype(str).eq(scalar_json(["al", "exal"])).all(), "al,exal"),
        ("validation_selection_only", cases["selection_is_validation_only"].map(boolish).all() and cases["selection_split"].astype(str).eq("val").all(), "val"),
        ("test_registry_article_joint_mcmc_blocked", blocked_false, "blocked"),
        ("prep_does_not_launch", not cases["launcher_invoked_by_prep"].map(boolish).any(), "not launched"),
        ("launch_control_yaml_written", launch_yaml is not None and launch_yaml.is_file(), str(launch_yaml or "")),
    ]
    return pd.DataFrame([{"gate": name, "passed": bool(passed), "observed": observed} for name, passed, observed in rows])


def source_manifest(
    args: argparse.Namespace,
    generated: list[Path],
    components: pd.DataFrame,
) -> pd.DataFrame:
    paths = [
        args.r69a_dir / "summary.json",
        args.r69a_dir / "pricefm_stage_r69a_launch_readiness_gates.csv",
        args.r69a_dir / "pricefm_stage_r69a_spec_anchor_audit.csv",
        args.r69a_dir / "pricefm_stage_r69a_quantile_component_anchor_audit.csv",
        args.runtime_manifest,
        Path(__file__).resolve(),
        args.code_root / "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R",
        args.code_root / "application/tests/test_pricefm_stage_r69b_bounded_cran111_launch_prep.py",
        args.code_root / "docs/implementation_notes/pricefm_stage_r69b_bounded_cran111_launch_prep_20260831.md",
        *generated,
    ]
    for column in ("config_path", "feature_manifest_path", "metric_path", "data_config_path"):
        if column in components:
            paths.extend(Path(text_value(path)) for path in components[column].dropna() if text_value(path))
    rows = []
    for path in dict.fromkeys(resolve(path, args.artifact_repo) for path in paths):
        if path.is_file():
            rows.append({"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size})
    return pd.DataFrame(rows).sort_values("path").reset_index(drop=True)


def report(summary: dict[str, Any]) -> str:
    return f"""# PriceFM Stage-R69B Bounded CRAN 1.1.1 Launch Prep

## Decision

Stage-R69B materialized launch-prep inputs for the 56 Stage-R68 target cases
whose case-specific anchors were verified by Stage-R69A. It did not launch,
fit models, open test metrics, mutate the registry, or update the article.

## Prepared Surface

| Quantity | Value |
|---|---:|
| Cases | {summary['planned_cases']} |
| Quantile components | {summary['planned_quantile_components']} |
| Likelihood families planned | 2 |
| Priority-0 near misses | {summary['priority_counts'].get('priority_0_near_miss', 0)} |
| Priority-1 moderate gaps | {summary['priority_counts'].get('priority_1_moderate_gap', 0)} |
| AL anchor cases | {summary['family_counts'].get('al', 0)} |
| exAL anchor cases | {summary['family_counts'].get('exal', 0)} |

## Firewalls

Every generated case config has `splits: [train, val]`. Historical test splits
from source configs are stripped in the generated configs. The launch-control
YAML records a future Stage-R70 launch contract but the prep stage does not
invoke a launcher. Registry, article, joint, and MCMC mutation remain blocked.

## Next Action

If the user explicitly authorizes the actual run, implement or invoke the
future Stage-R70 launcher against `case_manifest.csv`, with one worker per
case/model and CRAN `exdqlm` 1.1.1 public APIs only. Selection after completion
must remain validation-only before test metrics are audited.
"""


def run(args: argparse.Namespace) -> dict[str, Any]:
    args.code_root = args.code_root.resolve()
    args.artifact_repo = args.artifact_repo.resolve()
    args.r69a_dir = args.r69a_dir.resolve()
    args.runtime_manifest = args.runtime_manifest.resolve()
    args.python_bin = args.python_bin.resolve()
    args.grid_dir = prepare_dir(args.grid_dir, args.force)
    args.output_dir = prepare_dir(args.output_dir, args.force)
    args.run_dir = args.run_dir.resolve()
    args.run_dir.mkdir(parents=True, exist_ok=True)

    anchors, components, r69a_summary = verify_r69a_inputs(args)
    runtime_manifest = verify_runtime_manifest(args.runtime_manifest)

    config_dir = args.grid_dir / "configs/cases"
    data_dir = args.grid_dir / "configs/data"
    config_dir.mkdir(parents=True, exist_ok=True)
    data_dir.mkdir(parents=True, exist_ok=True)
    case_rows: list[dict[str, Any]] = []
    component_output_rows: list[dict[str, Any]] = []
    generated_paths: list[Path] = []

    for anchor in anchors.sort_values(["refit_priority", "region", "fold"]).itertuples(index=False):
        row = pd.Series(anchor._asdict())
        case_id = text_value(row["case_id"])
        case_components = components[components["case_id"].astype(str).eq(case_id)].copy()
        component = selected_component(case_components)
        source_data_config = resolve(component["data_config_path"], args.artifact_repo)
        data_config = data_dir / f"{case_id}.yaml"
        portable_data_config(source_data_config, data_config, args.artifact_repo)
        case_root = args.run_dir / case_id
        adapter_dir = case_root / "adapter"
        model_dir = case_root / "model"
        config_path = config_dir / f"{case_id}.yaml"
        payload = generated_config(
            args,
            row,
            case_components,
            runtime_manifest,
            config_path,
            data_config,
            adapter_dir,
            model_dir,
        )
        config_path.write_text(yaml.safe_dump(payload, sort_keys=False))
        generated_paths.extend([config_path, data_config])
        case_rows.append(case_row(row, config_path, data_config, adapter_dir, model_dir, runtime_manifest))
        component_output_rows.extend(component_rows(row, case_components, config_path, model_dir))

    cases = pd.DataFrame(case_rows).sort_values(["refit_priority", "region", "fold"]).reset_index(drop=True)
    component_ledger = pd.DataFrame(component_output_rows).sort_values(["case_id", "tau"]).reset_index(drop=True)
    case_manifest = args.grid_dir / "case_manifest.csv"
    component_manifest = args.grid_dir / "component_ledger.csv"
    cases.to_csv(case_manifest, index=False)
    component_ledger.to_csv(component_manifest, index=False)
    generated_paths.extend([case_manifest, component_manifest])

    launch_yaml = None
    if args.write_launch_yaml:
        launch_yaml = args.grid_dir / "pricefm_stage_r69b_launch_control.yaml"
        launch_yaml.write_text(yaml.safe_dump(
            build_launch_control(args, case_manifest, component_manifest, runtime_manifest),
            sort_keys=False,
        ))
        generated_paths.append(launch_yaml)

    gates = readiness_gates(args, cases, component_ledger, launch_yaml, runtime_manifest)
    if not gates["passed"].all():
        raise RuntimeError(f"R69B launch-prep gates failed: {gates.loc[~gates.passed].to_dict('records')}")
    gates.to_csv(args.output_dir / "pricefm_stage_r69b_launch_prep_gates.csv", index=False)

    source_manifest(args, generated_paths, components).to_csv(args.output_dir / "source_manifest.csv", index=False)
    priority_counts = cases["refit_priority"].value_counts().to_dict()
    family_counts = cases["selected_family_anchor"].value_counts().to_dict()
    summary = {
        "status": "prepared_bounded_cran111_independent_vb_launch_not_launched",
        "recommended_next_action": "implement_or_authorize_stage_r70_launcher_after_review",
        "tag": args.tag,
        "planned_cases": int(len(cases)),
        "planned_quantile_components": int(len(component_ledger)),
        "planned_atomic_fits": int(len(component_ledger) * 2),
        "priority_counts": {str(k): int(v) for k, v in priority_counts.items()},
        "family_counts": {str(k): int(v) for k, v in family_counts.items()},
        "case_manifest": str(case_manifest.resolve()),
        "component_ledger": str(component_manifest.resolve()),
        "launch_control_yaml": str(launch_yaml.resolve()) if launch_yaml else None,
        "r69a_source_status": r69a_summary.get("status"),
        "package_authority": "exact_CRAN_exdqlm_1.1.1_public_API",
        "cran111_runtime_manifest": str(args.runtime_manifest),
        "selection_split": "val",
        "future_configs_train_val_only": True,
        "historical_test_split_stripped": True,
        "launch_authorized": False,
        "launcher_invoked_by_prep": False,
        "fit_models": False,
        "test_opened": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
        "code_root_head": git_head(args.code_root),
        "artifact_repo_head": git_head(args.artifact_repo),
    }
    write_json(args.output_dir / "summary.json", summary)
    (args.output_dir / "pricefm_stage_r69b_launch_prep_report.md").write_text(report(summary))
    if (args.grid_dir / "launch_status.csv").exists() or (args.output_dir / "launch_status.csv").exists():
        raise RuntimeError("R69B prep must not create launch_status.csv")
    forbidden_roots = [args.output_dir, args.grid_dir]
    if any(path.is_file() and path.suffix in BINARY_SUFFIXES for root in forbidden_roots for path in root.rglob("*")):
        raise RuntimeError("R69B prep must not write model binary artifacts")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
