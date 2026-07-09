#!/usr/bin/env python3
"""Run generated PriceFM DESN experiment-grid configs in parallel."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import yaml

from pricefm_common import parse_bool, repo_path, write_json
from pricefm_graph import graph_active_regions_for_policy, graph_policy_requires_neighbor_windows


SCRIPT_DIR = Path(__file__).resolve().parent
GRID_PREP_PATH = SCRIPT_DIR / "12_prepare_desn_experiment_grid.py"


def load_grid_module():
    spec = importlib.util.spec_from_file_location("pricefm_grid_prepare", GRID_PREP_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def parse_csv(value, cast=str):
    if value is None or str(value).strip() == "":
        return None
    return [cast(x.strip()) for x in str(value).split(",") if x.strip()]


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--grid-config",
        default="application/config/pricefm_desn_experiment_grid_median_de_lu_refine_20260601.yaml",
    )
    p.add_argument("--priorities", default=None, help="Comma-separated priority filter.")
    p.add_argument("--stages", default=None, help="Comma-separated stage filter.")
    p.add_argument("--ids", default=None, help="Comma-separated experiment id filter.")
    p.add_argument("--experiment-jobs", type=int, default=2)
    p.add_argument("--cell-jobs", type=int, default=1)
    p.add_argument("--build-windows", type=parse_bool, default=False)
    p.add_argument("--resume", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    p.add_argument("--dry-run", type=parse_bool, default=True)
    p.add_argument("--regions", default=None, help="Optional comma-separated region override for every generated config.")
    p.add_argument("--folds", default=None, help="Optional comma-separated fold override for every generated config.")
    p.add_argument("--max-experiments", type=int, default=None)
    return p


def select_rows(rows, priorities=None, stages=None, ids=None, max_experiments=None):
    priorities = set(priorities or [])
    stages = set(stages or [])
    ids = set(ids or [])
    out = []
    for row in rows:
        if priorities and int(row["priority"]) not in priorities:
            continue
        if stages and str(row["stage"]) not in stages:
            continue
        if ids and str(row["id"]) not in ids:
            continue
        out.append(row)
    if max_experiments is not None:
        out = out[:int(max_experiments)]
    return out


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def run_logged(cmd, log_path, dry_run=False):
    log_path = repo_path(log_path)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.time()
    with open(log_path, "w") as log:
        log.write("$ {}\n\n".format(" ".join(map(str, cmd))))
        if dry_run:
            log.write("Dry run: command not executed.\n")
            return {
                "status": "planned",
                "return_code": 0,
                "elapsed_seconds": round(time.time() - started, 3),
            }
        log.flush()
        proc = subprocess.run(
            [str(x) for x in cmd],
            cwd=str(repo_path(".")),
            stdout=log,
            stderr=subprocess.STDOUT,
            check=False,
        )
    return {
        "status": "completed" if proc.returncode == 0 else "failed",
        "return_code": int(proc.returncode),
        "elapsed_seconds": round(time.time() - started, 3),
    }


def read_yaml(path):
    with open(repo_path(path), "r") as f:
        return yaml.safe_load(f)


def full_config_scope(full_config):
    payload = read_yaml(full_config)
    full = payload["pricefm_desn_full"]
    scope = full["scope"]
    regions = [str(x) for x in scope["regions"]]
    folds = [int(x) for x in scope["folds"]]
    return regions, folds


def ordered_unique(values):
    out = []
    seen = set()
    for value in values:
        text = str(value)
        if text in seen:
            continue
        seen.add(text)
        out.append(text)
    return out


def data_config_regions(data_config):
    payload = read_yaml(data_config)
    data = payload["pricefm"]
    return [str(x) for x in data["regions"]]


def full_config_window_regions(full_config, data_config):
    payload = read_yaml(full_config)
    full = payload["pricefm_desn_full"]
    target_regions = [str(x) for x in full["scope"]["regions"]]
    feature_policy = str(full["scope"].get("feature_policy", "target_only"))
    if not graph_policy_requires_neighbor_windows(feature_policy):
        return target_regions

    spatial = full.get("adapter", {}).get("spatial", {})
    if "graph_degree" not in spatial:
        raise ValueError("{} config is missing adapter.spatial.graph_degree: {}".format(feature_policy, full_config))
    input_regions = data_config_regions(data_config)
    graph_regions = []
    for region in target_regions:
        graph_regions.extend(graph_active_regions_for_policy(
            region,
            input_regions,
            feature_policy,
            spatial=spatial,
        ))
    return ordered_unique(graph_regions)


def data_window_scope(data_config):
    payload = read_yaml(data_config)
    data = payload["pricefm"]
    windows = data["windows"]
    return {
        "processed_dir": str(data.get("processed_dir", "")),
        "lag_window": int(windows["lag_window"]),
        "lead_window": int(windows["lead_window"]),
    }


def build_window_jobs(rows):
    jobs = []
    seen = set()
    for row in rows:
        _, folds = full_config_scope(row["full_config"])
        regions = full_config_window_regions(row["full_config"], row["data_config"])
        window = data_window_scope(row["data_config"])
        key = (
            tuple(regions),
            tuple(folds),
            window["processed_dir"],
            window["lag_window"],
            window["lead_window"],
        )
        if key in seen:
            continue
        seen.add(key)
        jobs.append({
            "data_config": row["data_config"],
            "regions": regions,
            "folds": folds,
            **window,
        })
    return jobs


def build_windows_for_rows(input_rows, log_dir, dry_run, resume, force):
    status_rows = []
    for i, job in enumerate(build_window_jobs(input_rows)):
        log_path = log_dir / "windows_{:03d}.log".format(i + 1)
        cmd = [
            sys.executable,
            repo_path("application/scripts/pricefm/05_build_windows.py"),
            "--config", repo_path(job["data_config"]),
            "--pilot-only", "true",
            "--regions", ",".join(job["regions"]),
            "--folds", ",".join(str(x) for x in job["folds"]),
            "--resume", str(bool(resume)).lower(),
            "--force", str(bool(force)).lower(),
        ]
        result = run_logged(cmd, log_path, dry_run=dry_run)
        status_rows.append({
            "id": "window_build_{:03d}".format(i + 1),
            "kind": "window_build",
            "config": job["data_config"],
            "log": config_path_value(log_path),
            **result,
        })
        if result["status"] == "failed":
            break
    return status_rows


def run_experiment(row, log_dir, dry_run, resume, force, cell_jobs, regions=None, folds=None):
    log_path = log_dir / "{}.log".format(row["id"])
    cmd = [
        sys.executable,
        repo_path("application/scripts/pricefm/10_run_desn_model_full.py"),
        "--config", repo_path(row["full_config"]),
        "--jobs", str(int(cell_jobs)),
        "--resume", str(bool(resume)).lower(),
        "--force", str(bool(force)).lower(),
        "--dry-run", str(bool(dry_run)).lower(),
    ]
    if regions:
        cmd.extend(["--regions", ",".join(str(x) for x in regions)])
    if folds:
        cmd.extend(["--folds", ",".join(str(int(x)) for x in folds)])
    result = run_logged(cmd, log_path, dry_run=False)
    if dry_run and result["status"] == "completed":
        result["status"] = "planned"
    return {
        "id": row["id"],
        "kind": "experiment",
        "priority": row["priority"],
        "stage": row["stage"],
        "config": row["full_config"],
        "run_dir": row["run_dir"],
        "log": config_path_value(log_path),
        **result,
    }


def write_status(path, rows):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "id", "kind", "priority", "stage", "status", "return_code",
        "elapsed_seconds", "config", "run_dir", "log",
    ]
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row.get(k, "") for k in fields})


def main():
    args = parser().parse_args()
    grid_mod = load_grid_module()
    grid = grid_mod.load_grid(args.grid_config)
    rows = grid_mod.prepare_grid(grid, grid["base"]["generated_root"], write=True)
    selected = select_rows(
        rows,
        priorities=parse_csv(args.priorities, int),
        stages=parse_csv(args.stages, str),
        ids=parse_csv(args.ids, str),
        max_experiments=args.max_experiments,
    )
    region_override = parse_csv(args.regions, str)
    fold_override = parse_csv(args.folds, int)
    generated_root = repo_path(grid["base"]["generated_root"])
    log_dir = generated_root / "launch_logs"
    status_rows = []

    if args.build_windows:
        window_rows = build_windows_for_rows(
            selected,
            log_dir,
            dry_run=bool(args.dry_run),
            resume=bool(args.resume),
            force=bool(args.force),
        )
        status_rows.extend(window_rows)
        if any(row["status"] == "failed" for row in window_rows):
            write_status(generated_root / "launch_status.csv", status_rows)
            raise SystemExit(1)

    if int(args.experiment_jobs) <= 1:
        for row in selected:
            status_rows.append(run_experiment(
                row, log_dir, bool(args.dry_run), bool(args.resume),
                bool(args.force), int(args.cell_jobs),
                regions=region_override,
                folds=fold_override,
            ))
    else:
        with ThreadPoolExecutor(max_workers=int(args.experiment_jobs)) as ex:
            futs = [
                ex.submit(
                    run_experiment, row, log_dir, bool(args.dry_run),
                    bool(args.resume), bool(args.force), int(args.cell_jobs),
                    region_override, fold_override,
                )
                for row in selected
            ]
            for fut in as_completed(futs):
                status_rows.append(fut.result())
        status_rows.sort(key=lambda x: (str(x.get("kind", "")), int(x.get("priority", 999)), str(x["id"])))

    status_path = generated_root / "launch_status.csv"
    write_status(status_path, status_rows)
    summary = {
        "grid_id": grid["grid_id"],
        "dry_run": bool(args.dry_run),
        "experiment_jobs": int(args.experiment_jobs),
        "cell_jobs": int(args.cell_jobs),
        "build_windows": bool(args.build_windows),
        "n_selected_experiments": len(selected),
        "region_override": region_override,
        "fold_override": fold_override,
        "status_csv": config_path_value(status_path),
        "selected_ids": [row["id"] for row in selected],
    }
    write_json(generated_root / "launch_summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
