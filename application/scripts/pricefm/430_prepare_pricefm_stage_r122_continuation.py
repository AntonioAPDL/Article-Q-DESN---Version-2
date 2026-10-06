#!/usr/bin/env python3
"""Freeze a target-preserving R122 continuation with audited completed-fit reuse."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

for _name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
              "BLIS_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS"):
    os.environ[_name] = "1"

import numpy as np
import pandas as pd
import yaml

from pricefm_common import sha256_file, write_json
from pricefm_r122_runtime import normalize_spec


SCRIPT_DIR = Path(__file__).resolve().parent
RUNNER = SCRIPT_DIR / "429_run_pricefm_stage_r122_long_memory.py"
TEST = "application/tests/test_pricefm_stage_r122_continuation.py"
ALLOWED_CHANGES = {
    "application/scripts/pricefm/429_run_pricefm_stage_r122_long_memory.py",
    "application/scripts/pricefm/430_prepare_pricefm_stage_r122_continuation.py", TEST,
}


def _json(path: Path) -> dict:
    return json.loads(path.read_text())


def _git(code: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(code), *args], text=True).strip()


def _runner():
    spec = importlib.util.spec_from_file_location("pricefm_r122_continuation_runner", RUNNER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def audit_broad_reuse(campaign: Path, manifest: pd.DataFrame,
                      input_hashes: dict[str, str] | None = None) -> pd.DataFrame:
    if manifest.fit_id.duplicated().any():
        raise ValueError("R122 reuse contains duplicate fit IDs")
    inventory = []
    for row in manifest.itertuples(index=False):
        root = campaign / "ridge/fits" / str(row.fit_id)
        terminal = _json(root / "terminal.json")
        contract = _json(root / "contract.json")
        if input_hashes is not None:
            if not contract.get("source_manifest"):
                raise RuntimeError(f"R122 reused fit lacks input provenance: {row.fit_id}")
            for source in contract["source_manifest"]:
                for kind in ("window", "manifest"):
                    path = str(source[f"{kind}_path"]); expected = str(source[f"{kind}_sha256"])
                    if path in input_hashes and input_hashes[path] != expected:
                        raise RuntimeError(f"R122 fits used different versions of an input: {path}")
                    input_hashes[path] = expected
        expected_spec = json.loads(str(row.spec_json))
        expected_spec["seed"] = int(row.reservoir_seed)
        expected_spec = normalize_spec(expected_spec)
        if (terminal.get("status") != "completed_r122_ridge_cell"
                or terminal.get("test_opened") is not False
                or contract.get("test_opened") is not False
                or terminal.get("fit_sha256") != str(row.fit_sha256)
                or terminal.get("fit_id") != str(row.fit_id)
                or terminal.get("candidate_id") != str(row.candidate_id)
                or terminal.get("reservoir_seed") != int(row.reservoir_seed)
                or terminal.get("role") != str(row.role)
                or contract.get("fit_sha256") != str(row.fit_sha256)
                or contract.get("candidate_id") != str(row.candidate_id)
                or contract.get("reservoir_seed") != int(row.reservoir_seed)
                or contract.get("role") != str(row.role)
                or contract.get("spec") != expected_spec):
            raise RuntimeError(f"R122 reused terminal/contract differs: {row.fit_id}")
        metrics = pd.read_csv(root / "validation_metrics.csv")
        required = ["AQL", "late_AQL", "median_MAE", "interval_80_width", "interval_80_coverage"]
        if (len(metrics) != 3 or set(metrics.split.astype(int)) != {1, 2, 3}
                or not np.isfinite(metrics[required].to_numpy(dtype=float)).all()
                or not np.isclose(float(terminal["mean_AQL"]), float(metrics.AQL.mean()), rtol=1e-12)):
            raise RuntimeError(f"R122 reused metrics differ: {row.fit_id}")
        for name in ("terminal.json", "contract.json", "validation_metrics.csv", "training_statistics.npz"):
            path = root / name
            inventory.append({"fit_id": str(row.fit_id), "path": str(path.relative_to(campaign)),
                              "bytes": path.stat().st_size, "sha256": sha256_file(path)})
    return pd.DataFrame(inventory)


def _trace_converged(trace: pd.DataFrame, contract: dict) -> bool:
    if len(trace) < int(contract["min_iter"]) or not np.isfinite(trace.to_numpy(dtype=float)).all():
        return False
    if float(trace.beta_max_abs_delta.iloc[-1]) <= float(contract["tol"]):
        return True
    tail = trace.tail(int(contract["stability_window"]))
    return len(tail) == int(contract["stability_window"]) and all(
        float(tail[column].max()) <= float(contract[threshold])
        for column, threshold in (
            ("fitted_rmse_delta", "predictive_tol"),
            ("beta_relative_l2_delta", "relative_beta_tol"),
            ("sigma_relative_delta", "sigma_relative_tol"),
            ("prior_rms_log_precision_delta", "prior_rms_log_precision_tol"),
        )
    )


def audit_rhs_cap_calibration(campaign: Path, maximum: int, evidence: Path | None) -> dict | None:
    if maximum == 500:
        if evidence is not None:
            raise ValueError("R122 cap evidence requires an explicit calibrated budget")
        return None
    if maximum != 2000 or evidence is None:
        raise ValueError("R122 extended RHS cap requires bounded score-blind calibration evidence")
    packet = _json(evidence)
    failed = set(_json(campaign / "rhs/center/fit_progress.json")["failed_task_ids"])
    entries = packet.get("diagnostics", [])
    if (not failed or len(entries) != len(failed)
            or {item["fit_id"] for item in entries} != failed
            or packet.get("validation_scores_opened") is not False
            or packet.get("official_test_opened") is not False):
        raise RuntimeError("R122 RHS calibration must cover every current failure without scores")
    checked = []
    for entry in entries:
        paths = {name: Path(entry[name]).resolve() for name in ("diagnostic", "trace", "contract")}
        for name, path in paths.items():
            if (not path.is_relative_to((campaign / "continuations").resolve())
                    or sha256_file(path) != entry[f"{name}_sha256"]):
                raise RuntimeError("R122 RHS calibration evidence hash/path differs")
        diagnostic = _json(paths["diagnostic"]); contract = _json(paths["contract"])
        trace = pd.read_csv(paths["trace"])
        if (diagnostic.get("fit_id") != entry["fit_id"] or contract["fit_id"] != entry["fit_id"]
                or contract["prior_type"] != "rhs_ns" or contract["max_iter"] != 500
                or contract["selection_split"] != "train_validation_only"
                or contract["test_access_authorized"] is not False
                or diagnostic.get("posterior_target_sha256") != contract["posterior_target_sha256"]
                or diagnostic.get("tau0") != contract["tau0"]
                or diagnostic.get("prior_hypers", {}).get("tau0") != contract["tau0"]
                or diagnostic.get("diagnostic_only") is not True
                or diagnostic.get("finite") is not True
                or diagnostic.get("diagnostic_converged") is not True
                or diagnostic.get("official_test_opened") is not False
                or diagnostic.get("validation_scores_opened") is not False
                or diagnostic.get("campaign_iteration_budget_changed") is not False
                or diagnostic.get("starting_values") != "unchanged_scaled_ridge_initialization_only"
                or len(trace) != int(diagnostic["diagnostic_iterations"])
                or not 500 < len(trace) <= maximum
                or trace.iter.astype(int).tolist() != list(range(1, len(trace) + 1))
                or _trace_converged(trace[trace.iter <= 500], contract)
                or not _trace_converged(trace, contract)):
            raise RuntimeError(f"R122 RHS score-blind cap calibration failed: {entry['fit_id']}")
        checked.append({**entry, "converged_iteration": len(trace),
                        "posterior_target_sha256": contract["posterior_target_sha256"]})
    return {"status": "R122_RHS_SCORE_BLIND_CAP_CALIBRATED", "previous_max_iter": 500,
            "max_iter": maximum, "early_stopping_unchanged": True,
            "priors_and_tolerances_unchanged": True, "diagnostics": checked,
            "validation_scores_opened": False, "official_test_opened": False}


def audit_rhs_reuse(campaign: Path) -> pd.DataFrame:
    inventory = []; columns = ["fit_id", "path", "bytes", "sha256"]
    manifest = campaign / "rhs/center/manifest.csv"
    if not manifest.is_file():
        return pd.DataFrame(columns=columns)
    for row in pd.read_csv(manifest).itertuples(index=False):
        root = Path(row.output_dir).resolve()
        if root != (campaign / "rhs/center/fits" / str(row.fit_id)).resolve():
            raise RuntimeError("R122 reused RHS output path differs")
        if not (root / "terminal.json").is_file():
            continue
        terminal = _json(root / "terminal.json"); contract = _json(Path(row.contract_path))
        if (terminal.get("status") != "completed_recursive_normal_fit"
                or terminal.get("converged") is not True or terminal.get("test_opened") is not False
                or terminal.get("fit_id") != str(row.fit_id) or terminal.get("prior_type") != "rhs_ns"
                or terminal.get("posterior_target_sha256") != contract["posterior_target_sha256"]
                or terminal.get("convergence_controls", {}).get("max_iter") != contract["max_iter"]):
            raise RuntimeError(f"R122 reused RHS target/convergence differs: {row.fit_id}")
        names = {item["path"] for item in terminal["artifacts"]}
        if not {"fit.rds", "beta_mean.bin", "beta_cov.bin", "convergence_trace.csv", "fit_summary.json"}.issubset(names):
            raise RuntimeError(f"R122 reused RHS artifacts incomplete: {row.fit_id}")
        for item in terminal["artifacts"]:
            path = (root / item["path"]).resolve()
            if (not path.is_relative_to(root) or path.stat().st_size != int(item["bytes"])
                    or sha256_file(path) != item["sha256"]):
                raise RuntimeError(f"R122 reused RHS artifact changed: {row.fit_id}")
        paths = [root / name for name in names] + [root / "terminal.json", Path(row.contract_path)]
        stats = Path(contract["stats_dir"])
        paths += [stats / name for name in ("terminal.json", "statistics.json", "XtX.bin", "Xty.bin")]
        if (root / "validation_score.json").is_file():
            if _json(root / "validation_score.json").get("test_opened") is not False:
                raise RuntimeError("R122 reused RHS score opened test data")
            paths.append(root / "validation_score.json")
        for path in paths:
            inventory.append({"fit_id": str(row.fit_id), "path": str(path.relative_to(campaign)),
                              "bytes": path.stat().st_size, "sha256": sha256_file(path)})
    return pd.DataFrame(inventory, columns=columns)


def prepare(args: argparse.Namespace) -> dict:
    original = args.original_prep.resolve(); output = args.output_dir.resolve()
    campaign = args.campaign_root.resolve(); code = args.code_root.resolve()
    if output.exists():
        raise FileExistsError("R122 continuation output must be new; never overwrite provenance")
    if _git(code, "status", "--short"):
        raise RuntimeError("R122 continuation requires a clean committed worktree")
    branch = _git(code, "branch", "--show-current")
    if not branch.startswith("work/pricefm-r122-"):
        raise RuntimeError("R122 continuation requires the dedicated scientific branch")
    summary = _json(original / "summary.json"); old = _json(original / "launch_control.json")
    if summary.get("status") != "R122_LONG_MEMORY_LAUNCH_READY" or Path(old["campaign_root"]).resolve() != campaign:
        raise RuntimeError("R122 continuation does not match the original authorized campaign")
    for name, expected in summary["output_sha256"].items():
        if sha256_file(original / name) != expected:
            raise RuntimeError(f"R122 original preparation changed: {name}")
    head = _git(code, "rev-parse", "HEAD")
    changed = set(_git(code, "diff", "--name-only", old["code_head"], head).splitlines())
    if not changed or not changed.issubset(ALLOWED_CHANGES):
        raise RuntimeError(f"R122 correction contains unapproved source changes: {sorted(changed)}")
    if subprocess.run(["git", "-C", str(code), "merge-base", "--is-ancestor", old["code_head"], head]).returncode:
        raise RuntimeError("R122 correction does not descend from executed source HEAD")
    environment = _json(original / "runtime_environment.json")
    current_environment = {
        "python_executable": str(Path(sys.executable).absolute()), "python_version": platform.python_version(),
        "python_prefix": sys.prefix, "pandas_version": pd.__version__, "pyyaml_version": yaml.__version__,
    }
    if any(environment.get(key) != value for key, value in current_environment.items()):
        raise RuntimeError("R122 continuation environment differs from the original")
    sources = pd.read_csv(original / "source_manifest.csv")
    changed_sources = []
    for row in sources.itertuples(index=False):
        path = Path(row.path)
        if sha256_file(path) == str(row.sha256):
            continue
        relative = str(path.relative_to(code))
        if relative not in ALLOWED_CHANGES:
            raise RuntimeError(f"R122 statistical source changed: {path}")
        executed = subprocess.check_output(["git", "-C", str(code), "show", f"{old['code_head']}:{relative}"])
        if hashlib.sha256(executed).hexdigest() != str(row.sha256):
            raise RuntimeError(f"R122 frozen source does not match the executed commit: {path}")
        changed_sources.append({"path": relative, "original_sha256": str(row.sha256),
                                "current_sha256": sha256_file(path)})
    run = _runner()
    calibration = audit_rhs_cap_calibration(
        campaign, int(getattr(args, "rhs_max_iter", 500)), getattr(args, "rhs_cap_evidence", None),
    )
    rhs_inventory = audit_rhs_reuse(campaign)
    manifest = run._execution(original)
    if len(manifest) != 6400 or manifest.role.value_counts().to_dict() != {"search": 6398, "external_control": 2}:
        raise RuntimeError("R122 continuation requires the exact completed broad manifest")
    if not (campaign / "seed3/manifest.csv").is_file():
        raise RuntimeError("R122 continuation requires the frozen third-seed manifest")
    broad = pd.read_csv(campaign / "broad/closeout/structural_ranking.csv")
    if len(broad) != 3199:
        raise RuntimeError("R122 broad closeout is incomplete")
    seed3 = run._third_seed_manifest(original, campaign, broad)
    lookup = run._ridge_worker_manifest(original, campaign)
    candidates = pd.concat([run._candidate_manifest(original), pd.read_csv(original / "control_manifest.csv")])
    for fit_id in seed3.fit_id.astype(str):
        run._ridge_row(original, campaign, fit_id, lookup, candidates)
    input_hashes: dict[str, str] = {}
    completed_seed3 = seed3[[run._ridge_valid(run._fit_root(campaign, str(row.fit_id)), str(row.fit_sha256))
                           for row in seed3.itertuples(index=False)]]
    reused = pd.concat([manifest, completed_seed3], ignore_index=True)
    inventory = audit_broad_reuse(campaign, reused, input_hashes)
    inputs = []
    for name, expected in sorted(input_hashes.items()):
        path = Path(name).resolve()
        if (not path.is_relative_to((campaign / "processed/windows").resolve())
                or "train_L3120_H96_contained_half_open" not in path.name or sha256_file(path) != expected):
            raise RuntimeError(f"R122 executed training input changed: {path}")
        inputs.append({"path": str(path.relative_to(campaign)), "bytes": path.stat().st_size, "sha256": expected})
    output.mkdir(parents=True)
    replaced = {"summary.json", "source_manifest.csv", "launch_control.json",
                "runtime_environment.json", "preparation_gates.json"}
    for name in summary["output_sha256"]:
        if name not in replaced:
            destination = output / name; destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(original / name, destination)
    inventory.to_csv(output / "reused_output_inventory.csv", index=False)
    rhs_inventory.to_csv(output / "reused_rhs_inventory.csv", index=False)
    pd.DataFrame(inputs).to_csv(output / "reused_input_inventory.csv", index=False)
    if calibration is not None:
        write_json(output / "rhs_cap_calibration.json", calibration)
    snapshot = output / "original_evidence"
    preserved = ["campaign_failure.json", "launch_preflight.json", "processed_audit.json",
                 "broad/progress.json", "seed3/progress.json", "seed3/manifest.csv"]
    preserved += [str(path.relative_to(campaign)) for path in (campaign / "broad/closeout").glob("*") if path.is_file()]
    preserved += [str(path.relative_to(campaign)) for path in (campaign / "logs/seed3_ridge").glob("*.log")]
    preserved += [str(path.relative_to(campaign)) for path in (campaign / "seed3/closeout").glob("*") if path.is_file()]
    preserved += [str(path.relative_to(campaign)) for path in (campaign / "rhs/center").rglob("*")
                  if path.is_file() and path.suffix.lower() not in (".rds", ".rda", ".rdata", ".bin")]
    preserved += [str(path.relative_to(campaign)) for path in (campaign / "logs/rhs_center_fit").glob("*.log")]
    if calibration is not None:
        preserved += [str(Path(entry[name]).relative_to(campaign))
                      for entry in calibration["diagnostics"] for name in ("diagnostic", "trace", "contract")]
    evidence = []
    for name in sorted(set(preserved)):
        path = campaign / name
        if path.is_file():
            destination = snapshot / name; destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
            evidence.append({"path": name, "sha256": sha256_file(path)})
    write_json(output / "reuse_audit.json", {
        "status": "R122_TARGET_PRESERVING_CONTINUATION_AUDITED", "original_code_head": old["code_head"],
        "continuation_code_head": head, "changed_files": sorted(changed), "changed_sources": changed_sources,
        "reused_broad_cells": len(manifest), "reused_output_files": len(inventory),
        "reused_third_seed_cells": len(completed_seed3),
        "reused_rhs_fits": rhs_inventory.fit_id.nunique(),
        "optimization_budget_changed": calibration is not None,
        "reused_input_files": len(inputs),
        "third_seed_planned": len(seed3), "seed3_manifest_sha256": sha256_file(campaign / "seed3/manifest.csv"),
        "original_prep": str(original), "original_summary_sha256": sha256_file(original / "summary.json"),
        "scientific_design_changed": False, "test_opened": False, "original_evidence": evidence,
    })
    (output / "source_changes.patch").write_text(_git(code, "diff", old["code_head"], head) + "\n")
    control = dict(old)
    if calibration is not None:
        control.update({"rhs_max_iter": calibration["max_iter"],
                        "rhs_cap_calibration_sha256": sha256_file(output / "rhs_cap_calibration.json")})
    control.update({"code_head": head, "code_branch": branch,
                    "rhs_contract_namespace": output.name,
                    "data_config": str(output / "data_configs/data_L3120.yaml"),
                    "continuation": {"original_prep": str(original), "original_code_head": old["code_head"],
                        "reuse_stage": "broad_and_completed_third_seed_ridge", "reuse_inventory_sha256": sha256_file(output / "reused_output_inventory.csv"),
                        "input_inventory_sha256": sha256_file(output / "reused_input_inventory.csv"),
                        "seed3_manifest_sha256": sha256_file(campaign / "seed3/manifest.csv")}})
    write_json(output / "launch_control.json", control)
    write_json(output / "runtime_environment.json", {
        **current_environment, "git_head": head, "git_branch": branch, "git_worktree_clean": True,
    })
    updated_sources = []
    for row in sources.itertuples(index=False):
        path = Path(row.path)
        if path.is_relative_to(original):
            path = output / path.relative_to(original)
        updated_sources.append({"path": str(path), "sha256": sha256_file(path)})
    for path in (Path(__file__).resolve(), code / TEST):
        updated_sources.append({"path": str(path), "sha256": sha256_file(path)})
    pd.DataFrame(updated_sources).to_csv(output / "source_manifest.csv", index=False)
    write_json(output / "preparation_gates.json", {"status": "passed", "checks": {
        "original_preparation_unchanged": True, "statistical_sources_unchanged": True,
        "completed_broad_outputs_audited": True, "seed3_worker_rows_resolved": True,
        "environment_unchanged": True, "dedicated_clean_branch": True, "test_firewall": True,
    }})
    files = [path for path in output.rglob("*") if path.is_file()]
    result = {**control, "status": "R122_LONG_MEMORY_LAUNCH_READY", "launch_authorized": True,
              "output_sha256": {str(path.relative_to(output)): sha256_file(path) for path in files}}
    write_json(output / "summary.json", result)
    return {"status": result["status"], "output_dir": str(output), "code_head": head,
            "reused_broad_cells": len(manifest), "reused_third_seed_cells": len(completed_seed3),
            "third_seed_planned": len(seed3), "reused_rhs_fits": rhs_inventory.fit_id.nunique(),
            "rhs_max_iter": control["rhs_max_iter"], "test_opened": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original-prep", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--campaign-root", type=Path, required=True)
    parser.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    parser.add_argument("--rhs-max-iter", type=int, choices=(500, 2000), default=500)
    parser.add_argument("--rhs-cap-evidence", type=Path)
    args = parser.parse_args()
    with (args.campaign_root / "controller.lock").open("a+") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        print(json.dumps(prepare(args), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
