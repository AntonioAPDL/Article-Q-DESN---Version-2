#!/usr/bin/env python3
"""Launch only the R82-gated 14-atom R83 structured-init retry."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
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
GRID = DATA / "experiment_grids/pricefm_stage_r83_structured_init_failed_atom_retry_20260904"
GATE = DATA / "authoritative/pricefm_stage_r82_structured_init_repair_gate_20260904/summary.json"


def parser():
    p = BASE.parser()
    p.set_defaults(
        manifest=GRID / "retry_manifest.csv",
        gate_summary=GATE,
        expected_tasks=14,
        workers=14,
    )
    return p


def preflight(manifest: pd.DataFrame, args: Any, cpus: list[int]) -> dict[str, Any]:
    gate = json.loads(args.gate_summary.read_text())
    if gate.get("r83_retry_authorized") is not True or gate.get("r83_retry_atoms") != 14:
        raise RuntimeError("R82 gate does not authorize R83")
    if len(manifest) != 14 or manifest.case_id.nunique() != 11 or manifest.task_id.duplicated().any():
        raise RuntimeError("R83 retry identity contract failed")
    if not manifest.likelihood_family.eq("exal").all() or not manifest.sigmagam_freeze_warmup_iters.eq(0).all():
        raise RuntimeError("R83 must be exAL-only with immediate structured updates")
    if args.workers < 1 or len(cpus) < args.workers:
        raise RuntimeError("R83 requires one unique logical CPU per worker")
    for row in manifest.itertuples(index=False):
        task_path = Path(row.task_config)
        if BASE.sha256(task_path) != row.task_config_sha256:
            raise RuntimeError(f"Changed R83 task: {task_path}")
        task = json.loads(task_path.read_text())
        if (
            task.get("stage") != "R83"
            or task.get("diagnostic_mode") is not False
            or task.get("selection_split") != "val"
            or task.get("sigmagam_freeze_warmup_iters") != 0
        ):
            raise RuntimeError("R83 task firewall mismatch")
        for name in BASE.BLOCKED:
            if task.get(name) is True:
                raise RuntimeError(f"R83 task authorizes forbidden action: {name}")
        for name, expected in (
            ("runtime_manifest", task["runtime_manifest_sha256"]),
            ("source_case_config", task["source_case_config_sha256"]),
            ("al_beta_path", task["al_beta_sha256"]),
            ("al_parameter_path", task["al_parameter_sha256"]),
            ("al_source_terminal", task["al_source_terminal_sha256"]),
            ("source_r76_task", task["source_r76_task_sha256"]),
            ("repair_gate", task["repair_gate_sha256"]),
        ):
            if BASE.sha256(Path(task[name])) != expected:
                raise RuntimeError(f"Changed R83 source: {task[name]}")
        adapter = Path(task["adapter_dir"])
        if any((adapter / name).exists() for name in ("X_test.csv", "y_test.csv", "rows_test.csv")):
            raise RuntimeError("R83 adapter contains test data")
    free = BASE.shutil.disk_usage(BASE.DATA).free / 1024**3
    memory = BASE.available_memory_gib()
    if free < args.minimum_free_gib or memory < args.minimum_available_memory_gib:
        raise RuntimeError("R83 resource gate failed")
    return {
        "tasks": 14,
        "cases": 11,
        "workers": args.workers,
        "cpu_ids": cpus[:args.workers],
        "one_process_per_cpu": True,
        "threads_per_process": 1,
        "repair_gate_passed": True,
        "test_opened": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }


def main() -> int:
    BASE.preflight = preflight
    result = BASE.run(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result.get("status") in {"preflight_passed_not_launched", "completed"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
