#!/usr/bin/env python3
"""Materialize the train/validation-only Stage-R57 joint VB campaign."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
AUTHORITY = DATA / "authoritative/pricefm_stage_r57_joint_authority_freeze_20260824"
OUTPUT = DATA / "authoritative/pricefm_stage_r57_joint_vb_launch_prep_20260824"
GRID = DATA / "experiment_grids/pricefm_stage_r57_joint_vb_20260824"
RUNS = DATA / "runs/pricefm_stage_r57_joint_vb_20260824"
PYTHON = DATA / "venv/bin/python"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--authority-dir", type=Path, default=AUTHORITY)
    p.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[3])
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--python-bin", type=Path, default=PYTHON)
    p.add_argument("--max-iter", type=int, default=50)
    p.add_argument("--tol", type=float, default=1e-4)
    p.add_argument("--rhs-vb-inner", type=int, default=5)
    p.add_argument("--crossproduct-chunk-size", type=int, default=2048)
    p.add_argument("--default-workers", type=int, default=16)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def git_head(path: Path) -> str:
    return subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()


def prepare_dir(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(f"Output exists: {path}")
    path.mkdir(parents=True, exist_ok=True)


def absolute_artifact_path(artifact_repo: Path, value: str) -> str:
    path = Path(value)
    return str(path.resolve() if path.is_absolute() else (artifact_repo / path).resolve())


def portable_data_config(source: dict, artifact_repo: Path) -> dict:
    payload = copy.deepcopy(source)
    spec = payload["pricefm"]
    spec["allow_absolute_local_paths"] = True
    for key in ("raw_dir", "interim_dir", "processed_dir", "external_repo_dir", "log_dir"):
        if key in spec and str(spec[key]).strip():
            spec[key] = absolute_artifact_path(artifact_repo, str(spec[key]))
    return payload


def case_payload(row, args, grid: Path, runs: Path) -> tuple[dict, dict, dict]:
    case_id = str(row.case_id)
    case_dir = runs / case_id
    adapter_dir = case_dir / "adapter"
    model_dir = case_dir / "model"
    source_smoke_payload = yaml.safe_load(Path(row.source_config).read_text())
    smoke = copy.deepcopy(source_smoke_payload["pricefm_desn_smoke"])
    source_data = yaml.safe_load(Path(row.source_data_config).read_text())
    data_payload = portable_data_config(source_data, args.artifact_repo.resolve())
    data_path = grid / "configs/data" / f"{case_id}.yaml"
    smoke_path = grid / "configs/adapter" / f"{case_id}.yaml"
    runtime_path = grid / "configs/joint_vb" / f"{case_id}.yaml"
    data_path.parent.mkdir(parents=True, exist_ok=True)
    smoke_path.parent.mkdir(parents=True, exist_ok=True)
    runtime_path.parent.mkdir(parents=True, exist_ok=True)
    data_path.write_text(yaml.safe_dump(data_payload, sort_keys=False))

    smoke["data_config"] = str(data_path.resolve())
    smoke["splits"] = ["train", "val"]
    smoke["quantiles"] = list(TAUS)
    smoke["adapter"]["output_dir"] = str(adapter_dir.resolve())
    smoke["run"]["output_dir"] = str(model_dir.resolve())
    smoke["artifact_hygiene"] = {
        "enabled": True,
        "clean_adapter_patterns": ["X_*.csv", "y_*.csv", "rows_*.csv", "rows_all.csv"],
        "preserve_patterns": ["adapter_manifest.json", "feature_manifest.json", "feature_map_matrix.*", "feature_provenance.csv"],
    }
    smoke_path.write_text(yaml.safe_dump({"pricefm_desn_smoke": smoke}, sort_keys=False))

    method_id = "joint_qdesn_exal_rhs_ns_vb1" if row.likelihood_family == "exal" else "joint_qdesn_al_rhs_ns_vb"
    prior_sigma = smoke.get("qdesn_vb", {}).get("prior_sigma", {"a": 1.0, "b": 1.0})
    runtime = {
        "pricefm_stage_r57_joint_vb": {
            "stage": "R57",
            "case_id": case_id,
            "region": str(row.region),
            "fold": int(row.fold),
            "likelihood_family": str(row.likelihood_family),
            "method_id": method_id,
            "vb_method_id": str(row.vb_method_id),
            "source_method_id": str(row.source_method_id),
            "source_experiment_id": str(row.experiment_id),
            "source_config": str(Path(row.source_config).resolve()),
            "source_config_sha256": str(row.source_config_sha256),
            "smoke_config": str(smoke_path.resolve()),
            "adapter_dir": str(adapter_dir.resolve()),
            "output_dir": str(model_dir.resolve()),
            "source_root": str(args.source_root.resolve()),
            "python_bin": str(args.python_bin.resolve()),
            "adapter_builder": str((args.source_root / "application/scripts/pricefm/07_build_desn_direct_horizon_adapter.py").resolve()),
            "summarizer": str((args.source_root / "application/scripts/pricefm/09_summarize_desn_model_smoke.py").resolve()),
            "allowed_splits": ["train", "val"],
            "test_access_authorized": False,
            "quantiles": list(TAUS),
            "tau0": float(row.tau0),
            "a_sigma": float(prior_sigma.get("a", 1.0)),
            "b_sigma": float(prior_sigma.get("b", 1.0)),
            "max_iter": int(args.max_iter),
            "tol": float(args.tol),
            "rhs_vb_inner": int(args.rhs_vb_inner),
            "max_dense_dim": 2500,
            "crossproduct_chunk_size": int(args.crossproduct_chunk_size),
            "cleanup_adapter_after_success": True,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        }
    }
    runtime_path.write_text(yaml.safe_dump(runtime, sort_keys=False))
    launch_row = {
        "case_id": case_id,
        "region": str(row.region),
        "fold": int(row.fold),
        "likelihood_family": str(row.likelihood_family),
        "method_id": method_id,
        "source_experiment_id": str(row.experiment_id),
        "config": str(runtime_path.resolve()),
        "smoke_config": str(smoke_path.resolve()),
        "output_dir": str(model_dir.resolve()),
        "status": "prepared_not_launched",
    }
    source_row = {
        "case_id": case_id,
        "runtime_config": str(runtime_path.resolve()),
        "runtime_config_sha256": sha256(runtime_path),
        "adapter_config": str(smoke_path.resolve()),
        "adapter_config_sha256": sha256(smoke_path),
        "data_config": str(data_path.resolve()),
        "data_config_sha256": sha256(data_path),
        "source_config": str(Path(row.source_config).resolve()),
        "source_config_sha256": str(row.source_config_sha256),
    }
    return launch_row, source_row, runtime


def run(args: argparse.Namespace) -> dict:
    if args.max_iter < 5 or args.tol <= 0 or args.rhs_vb_inner < 1 or args.crossproduct_chunk_size < 1:
        raise ValueError("Invalid joint VB controls")
    output, grid, runs = args.output_dir.resolve(), args.grid_dir.resolve(), args.run_dir.resolve()
    prepare_dir(output, args.force)
    prepare_dir(grid, args.force)
    runs.mkdir(parents=True, exist_ok=True)
    authority_path = args.authority_dir / "pricefm_stage_r57_joint_case_authority.csv"
    authority = pd.read_csv(authority_path)
    required = {
        "case_id", "region", "fold", "likelihood_family", "vb_method_id", "source_method_id",
        "experiment_id", "source_config", "source_config_sha256", "source_data_config", "tau0",
        "selection_split", "selection_is_validation_only", "test_metrics_role",
    }
    missing = sorted(required - set(authority.columns))
    if missing:
        raise RuntimeError(f"R57 authority missing columns: {missing}")
    if len(authority) != 114 or authority.duplicated(["region", "fold"]).any():
        raise RuntimeError("R57 launch prep requires exactly 114 unique authority cells")
    if not (
        authority.selection_split.eq("val").all()
        and authority.selection_is_validation_only.astype(bool).all()
        and authority.test_metrics_role.eq("audit_only").all()
    ):
        raise RuntimeError("R57 authority no longer satisfies validation-only selection")
    forbidden = {"qdesn_AQL", "pricefm_AQL", "delta_AQL_qdesn_minus_pricefm"}
    if forbidden & set(authority.columns):
        raise RuntimeError("Test-audit columns leaked into the runnable R57 authority")

    launch_rows, source_rows = [], []
    for row in authority.sort_values(["region", "fold"]).itertuples(index=False):
        launch_row, source_row, runtime = case_payload(row, args, grid, runs)
        cfg = runtime["pricefm_stage_r57_joint_vb"]
        if cfg["allowed_splits"] != ["train", "val"] or cfg["test_access_authorized"]:
            raise RuntimeError(f"Split firewall failed for {row.case_id}")
        launch_rows.append(launch_row)
        source_rows.append(source_row)

    code_sources = [
        Path(__file__).resolve(),
        args.source_root / "application/R/pricefm_joint_quantile_inference.R",
        args.source_root / "application/scripts/pricefm/200_freeze_pricefm_stage_r57_joint_authority.py",
        args.source_root / "application/scripts/pricefm/202_run_pricefm_stage_r57_joint_vb_case.R",
        args.source_root / "application/scripts/pricefm/203_launch_pricefm_stage_r57_joint_vb.py",
        args.source_root / "application/scripts/pricefm/204_closeout_pricefm_stage_r57_joint_vb.py",
        args.source_root / "application/R/joint_qvp_qdesn.R",
        args.source_root / "application/R/joint_exqdesn_exact_structured_inference.R",
        args.source_root / "application/R/joint_exqdesn_inference_dispatch.R",
    ]
    for path in code_sources:
        path = path.resolve()
        if not path.is_file():
            raise FileNotFoundError(path)
        source_rows.append({
            "case_id": "ALL", "runtime_config": "", "runtime_config_sha256": "",
            "adapter_config": "", "adapter_config_sha256": "", "data_config": "",
            "data_config_sha256": "", "source_config": str(path),
            "source_config_sha256": sha256(path),
        })

    manifest = pd.DataFrame(launch_rows)
    manifest_path = grid / "launch_manifest.csv"
    manifest.to_csv(manifest_path, index=False)
    pd.DataFrame(source_rows).to_csv(output / "source_manifest.csv", index=False)
    launch_config = {
        "pricefm_stage_r57_joint_vb_launch": {
            "stage": "R57",
            "manifest": str(manifest_path),
            "runner": str((args.source_root / "application/scripts/pricefm/202_run_pricefm_stage_r57_joint_vb_case.R").resolve()),
            "launcher": str((args.source_root / "application/scripts/pricefm/203_launch_pricefm_stage_r57_joint_vb.py").resolve()),
            "default_workers": int(args.default_workers),
            "one_process_per_cpu": True,
            "numerical_threads_per_process": 1,
            "resume": True,
            "force": False,
            "selection_role": "validation_only",
            "test_role": "sealed_until_validation_freeze",
            "launch_authorized_now": True,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        }
    }
    launch_yaml = output / "pricefm_stage_r57_joint_vb_launch.yaml"
    launch_yaml.write_text(yaml.safe_dump(launch_config, sort_keys=False))
    gates = pd.DataFrame([
        {"gate": "authority_114", "passed": len(manifest) == 114, "observed": len(manifest)},
        {"gate": "unique_case_ids", "passed": manifest.case_id.nunique() == 114, "observed": manifest.case_id.nunique()},
        {"gate": "al_exal_counts", "passed": manifest.likelihood_family.value_counts().to_dict() == {"exal": 87, "al": 27}, "observed": json.dumps(manifest.likelihood_family.value_counts().to_dict(), sort_keys=True)},
        {"gate": "train_val_only", "passed": True, "observed": "all runtime configs"},
        {"gate": "one_process_per_cpu", "passed": True, "observed": 1},
        {"gate": "source_code_pinned", "passed": True, "observed": git_head(args.source_root)},
        {"gate": "registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    gates.to_csv(output / "pricefm_stage_r57_joint_vb_prelaunch_gates.csv", index=False)
    if not gates.passed.all():
        raise RuntimeError(f"R57 prelaunch gates failed: {gates.loc[~gates.passed].to_dict('records')}")
    summary = {
        "status": "prepared_launch_authorized_not_started",
        "cases": len(manifest),
        "al_cases": int(manifest.likelihood_family.eq("al").sum()),
        "exal_cases": int(manifest.likelihood_family.eq("exal").sum()),
        "quantiles": list(TAUS),
        "source_head": git_head(args.source_root),
        "max_iter": int(args.max_iter),
        "tol": float(args.tol),
        "default_workers": int(args.default_workers),
        "selection_role": "validation_only",
        "test_access_authorized": False,
        "launch_authorized": True,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r57_joint_vb_launch_prep_report.md").write_text(
        "# PriceFM Stage-R57 joint VB launch prep\n\n"
        "The campaign contains one case-specific joint seven-quantile model for each of the 114 "
        "region/fold cells. Each case inherits its authoritative DESN, local/graph information set, "
        "AL versus exAL family, and RHS-NS `tau0=0.001`.\n\n"
        "Fit workers can open only train and validation adapters. Test adapters are not materialized. "
        "Each worker uses one numerical thread on one assigned CPU. Successful jobs retain compact VB "
        "initialization, validation predictions, metrics, traces, and hashes, then remove rebuilt design CSVs.\n\n"
        "The full background launch is explicitly authorized by the current user request. Registry and "
        "article mutation remain blocked.\n"
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
