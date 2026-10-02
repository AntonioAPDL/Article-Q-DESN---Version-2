#!/usr/bin/env python3
"""Freeze an explicit R122 dispatch-only continuation without refitting broad cells."""

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


def audit_broad_reuse(campaign: Path, manifest: pd.DataFrame) -> pd.DataFrame:
    if manifest.fit_id.duplicated().any():
        raise ValueError("R122 reuse contains duplicate fit IDs")
    inventory = []
    for row in manifest.itertuples(index=False):
        root = campaign / "ridge/fits" / str(row.fit_id)
        terminal = _json(root / "terminal.json")
        contract = _json(root / "contract.json")
        expected_spec = json.loads(str(row.spec_json))
        expected_spec["seed"] = int(row.reservoir_seed)
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
    inventory = audit_broad_reuse(campaign, manifest)
    output.mkdir(parents=True)
    replaced = {"summary.json", "source_manifest.csv", "launch_control.json",
                "runtime_environment.json", "preparation_gates.json"}
    for name in summary["output_sha256"]:
        if name not in replaced:
            destination = output / name; destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(original / name, destination)
    inventory.to_csv(output / "reused_output_inventory.csv", index=False)
    snapshot = output / "original_evidence"
    preserved = ["campaign_failure.json", "launch_preflight.json", "processed_audit.json",
                 "broad/progress.json", "seed3/progress.json", "seed3/manifest.csv"]
    preserved += [str(path.relative_to(campaign)) for path in (campaign / "broad/closeout").glob("*") if path.is_file()]
    preserved += [str(path.relative_to(campaign)) for path in (campaign / "logs/seed3_ridge").glob("*.log")]
    evidence = []
    for name in sorted(set(preserved)):
        path = campaign / name
        if path.is_file():
            destination = snapshot / name; destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
            evidence.append({"path": name, "sha256": sha256_file(path)})
    write_json(output / "reuse_audit.json", {
        "status": "R122_DISPATCH_ONLY_CONTINUATION_AUDITED", "original_code_head": old["code_head"],
        "continuation_code_head": head, "changed_files": sorted(changed), "changed_sources": changed_sources,
        "reused_broad_cells": len(manifest), "reused_output_files": len(inventory),
        "third_seed_planned": len(seed3), "seed3_manifest_sha256": sha256_file(campaign / "seed3/manifest.csv"),
        "original_prep": str(original), "original_summary_sha256": sha256_file(original / "summary.json"),
        "scientific_design_changed": False, "test_opened": False, "original_evidence": evidence,
    })
    (output / "source_changes.patch").write_text(_git(code, "diff", old["code_head"], head) + "\n")
    control = dict(old)
    control.update({"code_head": head, "code_branch": branch,
                    "data_config": str(output / "data_configs/data_L3120.yaml"),
                    "continuation": {"original_prep": str(original), "original_code_head": old["code_head"],
                        "reuse_stage": "broad_ridge", "reuse_inventory_sha256": sha256_file(output / "reused_output_inventory.csv")}})
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
            "reused_broad_cells": len(manifest), "third_seed_planned": len(seed3), "test_opened": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original-prep", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--campaign-root", type=Path, required=True)
    parser.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    args = parser.parse_args()
    with (args.campaign_root / "controller.lock").open("a+") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        print(json.dumps(prepare(args), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
