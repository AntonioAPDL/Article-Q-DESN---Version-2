#!/usr/bin/env python3
"""Run or plan the PriceFM bridge to Q-DESN model-selection artifacts.

This is an orchestration adapter. It keeps the PriceFM direct-horizon workflow
and the package-level ``exdqlm::qdesn_model_selection()`` surface aligned
without pretending the generic package selector can launch PriceFM folds yet.
By default it writes only a plan.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

from pricefm_common import parse_bool, repo_path, write_json


DEFAULT_GRID = (
    "application/config/"
    "pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml"
)
DEFAULT_BRIDGE_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_qdesn_model_selection_bridge_de_lu_folds23_20260606"
)
DEFAULT_REGISTRY_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_median_de_lu_folds23_followup_registry_20260605"
)
DEFAULT_PARITY_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_qdesn_model_selection_parity_de_lu_folds23_20260606"
)
DEFAULT_COMPARISON_TEMPLATE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_phase1_vs_desn_de_lu_fold{fold}_followup_20260605"
)
DEFAULT_METHODS = "qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked"


SCRIPT_DIR = Path(__file__).resolve().parent


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--grid-config", default=DEFAULT_GRID)
    p.add_argument("--bridge-dir", default=DEFAULT_BRIDGE_DIR)
    p.add_argument("--registry-dir", default=DEFAULT_REGISTRY_DIR)
    p.add_argument("--parity-dir", default=DEFAULT_PARITY_DIR)
    p.add_argument("--comparison-dir-template", default=DEFAULT_COMPARISON_TEMPLATE)
    p.add_argument("--plan-dir", default=None)
    p.add_argument("--regions", default="DE_LU")
    p.add_argument("--folds", default="2,3")
    p.add_argument("--priorities", default="0")
    p.add_argument("--stages", default=None)
    p.add_argument("--ids", default=None)
    p.add_argument("--quantile", default="0.50")
    p.add_argument("--selection-methods", default=DEFAULT_METHODS)
    p.add_argument("--selection-split", default="val")
    p.add_argument("--selection-unit", default="original")
    p.add_argument("--selection-metric", default="AQL")
    p.add_argument("--expected-horizons", default="1:96")
    p.add_argument("--experiment-jobs", type=int, default=1)
    p.add_argument("--cell-jobs", type=int, default=1)
    p.add_argument("--build-windows", type=parse_bool, default=False)
    p.add_argument("--resume", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    p.add_argument("--grid-dry-run", type=parse_bool, default=True)
    p.add_argument("--run-grid", type=parse_bool, default=False)
    p.add_argument("--select-existing", type=parse_bool, default=False)
    p.add_argument("--validate-parity", type=parse_bool, default=False)
    p.add_argument("--materialize-bridge", type=parse_bool, default=True)
    p.add_argument("--execute", type=parse_bool, default=False)
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def command_with_optional(cmd, pairs):
    out = list(cmd)
    for flag, value in pairs:
        if value is None or str(value).strip() == "":
            continue
        out.extend([flag, str(value)])
    return out


def build_runner_plan(args):
    py = sys.executable
    bridge_cmd = command_with_optional(
        [
            py,
            str(SCRIPT_DIR / "29_prepare_qdesn_model_selection_bridge.py"),
            "--grid-config",
            str(repo_path(args.grid_config)),
            "--output-dir",
            str(repo_path(args.bridge_dir)),
            "--quantile",
            str(args.quantile),
            "--selection-methods",
            str(args.selection_methods),
            "--write",
            str(bool(args.materialize_bridge)).lower(),
        ],
        [
            ("--regions", args.regions),
            ("--folds", args.folds),
            ("--priorities", args.priorities),
            ("--stages", args.stages),
            ("--ids", args.ids),
        ],
    )
    commands = [{
        "step": "materialize_bridge" if args.materialize_bridge else "plan_bridge",
        "enabled": True,
        "launches_model_fits": False,
        "command": bridge_cmd,
    }]

    grid_cmd = command_with_optional(
        [
            py,
            str(SCRIPT_DIR / "13_run_desn_experiment_grid.py"),
            "--grid-config",
            str(repo_path(args.grid_config)),
            "--experiment-jobs",
            str(int(args.experiment_jobs)),
            "--cell-jobs",
            str(int(args.cell_jobs)),
            "--build-windows",
            str(bool(args.build_windows)).lower(),
            "--resume",
            str(bool(args.resume)).lower(),
            "--force",
            str(bool(args.force)).lower(),
            "--dry-run",
            str(bool(args.grid_dry_run)).lower(),
        ],
        [
            ("--regions", args.regions),
            ("--folds", args.folds),
            ("--priorities", args.priorities),
            ("--stages", args.stages),
            ("--ids", args.ids),
        ],
    )
    commands.append({
        "step": "run_pricefm_grid",
        "enabled": bool(args.run_grid),
        "launches_model_fits": bool(args.run_grid and not args.grid_dry_run),
        "command": grid_cmd,
    })

    select_cmd = command_with_optional(
        [
            py,
            str(SCRIPT_DIR / "20_select_pricefm_desn_median_specs.py"),
            "--grid-config",
            str(repo_path(args.grid_config)),
            "--output-dir",
            str(repo_path(args.registry_dir)),
            "--selection-split",
            str(args.selection_split),
            "--selection-unit",
            str(args.selection_unit),
            "--selection-metric",
            str(args.selection_metric),
            "--selection-methods",
            str(args.selection_methods),
            "--require-complete",
            "true",
            "--expected-horizons",
            str(args.expected_horizons),
        ],
        [
            ("--regions", args.regions),
            ("--folds", args.folds),
            ("--priorities", args.priorities),
            ("--stages", args.stages),
            ("--ids", args.ids),
        ],
    )
    commands.append({
        "step": "select_existing_artifacts",
        "enabled": bool(args.select_existing),
        "launches_model_fits": False,
        "command": select_cmd,
    })

    parity_cmd = command_with_optional(
        [
            py,
            str(SCRIPT_DIR / "30_validate_qdesn_model_selection_parity.py"),
            "--bridge-dir",
            str(repo_path(args.bridge_dir)),
            "--registry-dir",
            str(repo_path(args.registry_dir)),
            "--comparison-dir-template",
            str(args.comparison_dir_template),
            "--output-dir",
            str(repo_path(args.parity_dir)),
            "--selection-methods",
            str(args.selection_methods),
            "--selection-split",
            str(args.selection_split),
            "--selection-unit",
            str(args.selection_unit),
            "--selection-metric",
            str(args.selection_metric),
            "--expected-horizons",
            str(args.expected_horizons),
        ],
        [
            ("--regions", args.regions),
            ("--folds", args.folds),
        ],
    )
    commands.append({
        "step": "validate_parity",
        "enabled": bool(args.validate_parity),
        "launches_model_fits": False,
        "command": parity_cmd,
    })

    plan_dir = repo_path(args.plan_dir) if args.plan_dir else repo_path(args.bridge_dir) / "runner_plan"
    enabled = [row for row in commands if row["enabled"]]
    return {
        "grid_config": config_path_value(args.grid_config),
        "bridge_dir": config_path_value(args.bridge_dir),
        "registry_dir": config_path_value(args.registry_dir),
        "parity_dir": config_path_value(args.parity_dir),
        "plan_dir": config_path_value(plan_dir),
        "regions": args.regions,
        "folds": args.folds,
        "priorities": args.priorities,
        "quantile": float(args.quantile),
        "selection_methods": args.selection_methods,
        "execute": bool(args.execute),
        "run_grid": bool(args.run_grid),
        "grid_dry_run": bool(args.grid_dry_run),
        "will_launch_model_fits": any(row["launches_model_fits"] for row in enabled),
        "commands": commands,
    }


def write_plan(plan):
    plan_dir = repo_path(plan["plan_dir"])
    plan_dir.mkdir(parents=True, exist_ok=True)
    write_json(plan_dir / "bridge_runner_plan.json", plan)
    with open(plan_dir / "bridge_runner_commands.txt", "w") as f:
        for row in plan["commands"]:
            prefix = "[enabled]" if row["enabled"] else "[disabled]"
            f.write("{} {}\n{}\n\n".format(prefix, row["step"], " ".join(row["command"])))
    return plan_dir


def run_enabled_commands(plan):
    rows = []
    plan_dir = repo_path(plan["plan_dir"])
    log_dir = plan_dir / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    for row in plan["commands"]:
        if not row["enabled"]:
            continue
        started = time.time()
        log_path = log_dir / "{}.log".format(row["step"])
        with open(log_path, "w") as log:
            log.write("$ {}\n\n".format(" ".join(row["command"])))
            log.flush()
            proc = subprocess.run(
                [str(x) for x in row["command"]],
                cwd=str(repo_path(".")),
                stdout=log,
                stderr=subprocess.STDOUT,
                check=False,
            )
        status = "completed" if proc.returncode == 0 else "failed"
        rows.append({
            "step": row["step"],
            "status": status,
            "return_code": int(proc.returncode),
            "elapsed_seconds": round(time.time() - started, 3),
            "log": config_path_value(log_path),
        })
        if proc.returncode != 0:
            break
    return rows


def main():
    args = parser().parse_args()
    plan = build_runner_plan(args)
    plan_dir = write_plan(plan)
    results = []
    if args.execute:
        results = run_enabled_commands(plan)
    summary = {
        "plan_dir": config_path_value(plan_dir),
        "execute": bool(args.execute),
        "will_launch_model_fits": bool(plan["will_launch_model_fits"]),
        "n_enabled_steps": sum(1 for row in plan["commands"] if row["enabled"]),
        "results": results,
    }
    write_json(plan_dir / "bridge_runner_summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    if any(row.get("status") == "failed" for row in results):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
