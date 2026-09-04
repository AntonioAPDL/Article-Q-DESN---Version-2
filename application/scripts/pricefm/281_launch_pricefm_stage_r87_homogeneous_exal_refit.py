#!/usr/bin/env python3
"""Launch or resume the R85-authorized 280-atom homogeneous exAL refit."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
from typing import Any

import pandas as pd


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "r76_atomic_launcher", HERE / "260_launch_pricefm_stage_r76_repaired_exal_surface.py"
)
BASE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = BASE
SPEC.loader.exec_module(BASE)
DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
GRID = DATA / "experiment_grids/pricefm_stage_r87_homogeneous_exal_refit_20260904"
GATE = DATA / "authoritative/pricefm_stage_r85_surface_wide_numerical_audit_20260904/summary.json"


def parser():
    p = BASE.parser()
    p.set_defaults(
        manifest=GRID / "task_manifest.csv", gate_summary=GATE,
        expected_tasks=280, workers=32,
    )
    return p


def preflight(manifest: pd.DataFrame, args: Any, cpus: list[int]) -> dict[str, Any]:
    gate = json.loads(args.gate_summary.read_text())
    if (
        gate.get("r86_launch_prep_authorized") is not True
        or gate.get("legacy_r76_atoms_requiring_refit") != 280
        or gate.get("test_opened") is not False
    ):
        raise RuntimeError("R85 does not authorize R87")
    if (
        len(manifest) != 280 or manifest.task_id.duplicated().any()
        or manifest.case_id.nunique() != 42 or not manifest.stage.eq("R87").all()
    ):
        raise RuntimeError("R87 task identity contract failed")
    if args.workers < 1 or len(cpus) < args.workers:
        raise RuntimeError("R87 requires one unique logical CPU per worker")
    if args.cpu_list:
        usage = BASE.cpu_snapshot()
        busy = {cpu: usage[cpu] for cpu in cpus[:args.workers]
                if usage[cpu] > args.maximum_cpu_snapshot_percent}
        if busy:
            raise RuntimeError(f"R87 selected CPUs exceed the usage gate: {busy}")
    for row in manifest.itertuples(index=False):
        task_path = Path(row.task_config)
        if BASE.sha256(task_path) != str(row.task_config_sha256):
            raise RuntimeError(f"Changed R87 task: {row.task_id}")
        task = json.loads(task_path.read_text())
        if (
            task.get("stage") != "R87" or task.get("diagnostic_mode") is not False
            or task.get("selection_split") != "val"
            or task.get("sigmagam_freeze_warmup_iters") != 0
        ):
            raise RuntimeError(f"R87 task firewall mismatch: {row.task_id}")
        for name in BASE.BLOCKED:
            if task.get(name) is True:
                raise RuntimeError(f"R87 task authorizes forbidden action: {name}")
        for name, expected in (
            ("runtime_manifest", task["runtime_manifest_sha256"]),
            ("source_case_config", task["source_case_config_sha256"]),
            ("al_beta_path", task["al_beta_sha256"]),
            ("al_parameter_path", task["al_parameter_sha256"]),
            ("al_source_terminal", task["al_source_terminal_sha256"]),
            ("source_r76_task", task["source_r76_task_sha256"]),
            ("repair_gate", task["repair_gate_sha256"]),
            ("runner_script", task["runner_script_sha256"]),
        ):
            if BASE.sha256(Path(task[name])) != expected:
                raise RuntimeError(f"Changed R87 source: {task[name]}")
        adapter = Path(task["adapter_dir"])
        if any((adapter / name).exists() for name in ("X_test.csv", "y_test.csv", "rows_test.csv")):
            raise RuntimeError("R87 adapter contains test data")
    free = BASE.shutil.disk_usage(BASE.DATA).free / 1024**3
    memory = BASE.available_memory_gib()
    if free < args.minimum_free_gib or memory < args.minimum_available_memory_gib:
        raise RuntimeError("R87 resource gate failed")
    code_commit = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=args.code_root.resolve(), text=True,
        capture_output=True, check=True,
    ).stdout.strip()
    return {
        "tasks": 280, "cases": 42, "workers": args.workers,
        "cpu_ids": cpus[:args.workers], "one_process_per_cpu": True,
        "threads_per_process": 1, "homogeneous_repair_gate_passed": True,
        "free_disk_gib": round(free, 3), "available_memory_gib": round(memory, 3),
        "test_opened": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "code_commit": code_commit,
        "runner_sha256": str(manifest.runner_script_sha256.iloc[0]),
    }


def main() -> int:
    BASE.preflight = preflight
    result = BASE.run(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result.get("status") in {"preflight_passed_not_launched", "completed"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
