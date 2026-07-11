"""Helpers for the full PriceFM DESN production run."""

from __future__ import annotations

import csv
import copy
import fnmatch
import json
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import yaml

from pricefm_common import load_config, pricefm_block, repo_path, write_json
from pricefm_desn_adapter import window_npz_path
from pricefm_graph import graph_active_regions_for_policy, graph_policy_requires_neighbor_windows


FULL_BLOCK = "pricefm_desn_full"
CELL_BLOCK = "pricefm_desn_smoke"
SUCCESS_CELL_STATUSES = {"completed", "skipped_complete", "planned"}

ADAPTER_FORWARD_KEYS = [
    "depth",
    "units",
    "alpha",
    "rho",
    "input_scale",
    "recurrent_sparsity",
    "recurrent_density",
    "bias_scale",
    "reservoir_activation",
    "state_output",
    "readout_interaction",
    "horizon_block_size",
    "readout_interaction_basis",
]


def load_full_config(path):
    cfg_path = repo_path(path)
    with open(cfg_path, "r") as f:
        payload = yaml.safe_load(f)
    if not isinstance(payload, dict) or FULL_BLOCK not in payload:
        raise ValueError("Config must contain top-level '{}'.".format(FULL_BLOCK))
    return payload[FULL_BLOCK]


def _as_list(value):
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return list(value)
    return [value]


def resolve_regions(full_cfg, data_cfg, override=None):
    spec = pricefm_block(data_cfg)
    value = override if override is not None else full_cfg["scope"].get("regions", "all")
    if value == "all":
        return list(spec["regions"])
    regions = [str(x) for x in _as_list(value)]
    unknown = sorted(set(regions) - set(spec["regions"]))
    if unknown:
        raise ValueError("Unknown PriceFM regions: {}".format(", ".join(unknown)))
    return regions


def resolve_folds(full_cfg, data_cfg, override=None):
    valid = [int(x["fold"]) for x in pricefm_block(data_cfg)["splits"]]
    value = override if override is not None else full_cfg["scope"].get("folds", valid)
    folds = [int(x) for x in _as_list(value)]
    unknown = sorted(set(folds) - set(valid))
    if unknown:
        raise ValueError("Unknown PriceFM folds: {}".format(", ".join(map(str, unknown))))
    return folds


def resolve_horizons(full_cfg, data_cfg):
    value = full_cfg["scope"].get("horizons", "all")
    lead_window = int(pricefm_block(data_cfg)["windows"]["lead_window"])
    if value == "all":
        return list(range(1, lead_window + 1))
    horizons = [int(x) for x in _as_list(value)]
    bad = [h for h in horizons if h < 1 or h > lead_window]
    if bad:
        raise ValueError("Invalid horizons for lead_window {}: {}".format(lead_window, bad))
    return horizons


def resolve_quantiles(full_cfg):
    qs = [float(x) for x in full_cfg["scope"].get("quantiles", [])]
    if not qs or qs != sorted(qs) or any(q <= 0.0 or q >= 1.0 for q in qs):
        raise ValueError("Quantiles must be an increasing list in (0, 1).")
    return qs


def cell_id(region, fold):
    return "region={}_fold={}".format(region, int(fold))


def cell_dir(run_dir, region, fold):
    return repo_path(run_dir) / "cells" / "region={}".format(region) / "fold={}".format(int(fold))


def cell_paths(full_cfg, region, fold):
    run_root = repo_path(full_cfg["run"]["output_dir"])
    root = cell_dir(run_root, region, fold)
    return {
        "root": root,
        "config": root / "config.yaml",
        "adapter": root / "adapter",
        "model": root / "model",
        "logs": run_root / "logs",
        "adapter_log": run_root / "logs" / "{}.adapter.log".format(cell_id(region, fold)),
        "model_log": run_root / "logs" / "{}.model.log".format(cell_id(region, fold)),
        "model_time": run_root / "logs" / "{}.time.log".format(cell_id(region, fold)),
        "summary_log": run_root / "logs" / "{}.summary.log".format(cell_id(region, fold)),
    }


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def make_cell_config(full_cfg, data_cfg, region, fold):
    paths = cell_paths(full_cfg, region, fold)
    horizons = resolve_horizons(full_cfg, data_cfg)
    quantiles = resolve_quantiles(full_cfg)
    adapter_cfg = {
        "name": "region={}_fold={}_h{}_{}".format(
            region, int(fold), len(horizons), full_cfg["adapter"]["feature_map"]
        ),
        "output_dir": config_path_value(paths["adapter"]),
        "feature_map": full_cfg["adapter"]["feature_map"],
        "feature_dim": int(full_cfg["adapter"]["feature_dim"]),
        "seed": int(full_cfg["adapter"]["seed"]),
        "include_intercept": bool(full_cfg["adapter"].get("include_intercept", True)),
        "row_chunk_size": int(full_cfg["adapter"].get("row_chunk_size", 2048)),
        "projection_scale": float(full_cfg["adapter"].get("projection_scale", 1.0)),
    }
    for key in ADAPTER_FORWARD_KEYS:
        if key in full_cfg["adapter"]:
            adapter_cfg[key] = copy.deepcopy(full_cfg["adapter"][key])
    if "spatial" in full_cfg["adapter"]:
        adapter_cfg["spatial"] = copy.deepcopy(full_cfg["adapter"]["spatial"])
    cell = {
        CELL_BLOCK: {
            "data_config": full_cfg["data_config"],
            "package_path": full_cfg["package_path"],
            "region": region,
            "fold": int(fold),
            "splits": list(full_cfg["scope"].get("splits", ["train", "val", "test"])),
            "horizons": horizons,
            "quantiles": quantiles,
            "feature_policy": full_cfg["scope"].get("feature_policy", "target_only"),
            "adapter": adapter_cfg,
            "run": {
                "output_dir": config_path_value(paths["model"]),
                "nd_predictive": int(full_cfg["run"].get("nd_predictive", 400)),
                "seed": int(full_cfg["run"].get("seed", 20260530)),
            },
            "rhs_ns": dict(full_cfg["rhs_ns"]),
            "normal": dict(full_cfg["normal"]),
            "qdesn_vb": dict(full_cfg["qdesn_vb"]),
            "exact_equivalence": dict(full_cfg["exact_equivalence"]),
        }
    }
    if "training" in full_cfg:
        cell[CELL_BLOCK]["training"] = dict(full_cfg["training"])
    if "warm_start" in full_cfg:
        cell[CELL_BLOCK]["warm_start"] = dict(full_cfg["warm_start"])
    if "artifact_hygiene" in full_cfg:
        cell[CELL_BLOCK]["artifact_hygiene"] = dict(full_cfg["artifact_hygiene"])
    return cell


def write_cell_config(full_cfg, data_cfg, region, fold):
    paths = cell_paths(full_cfg, region, fold)
    paths["root"].mkdir(parents=True, exist_ok=True)
    payload = make_cell_config(full_cfg, data_cfg, region, fold)
    with open(paths["config"], "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)
    return paths["config"]


def iter_cells(full_cfg, data_cfg, regions=None, folds=None):
    for region in resolve_regions(full_cfg, data_cfg, regions):
        for fold in resolve_folds(full_cfg, data_cfg, folds):
            yield region, fold


def missing_window_files(full_cfg, data_cfg, region, fold):
    missing = []
    feature_policy = str(full_cfg["scope"].get("feature_policy", "target_only"))
    spatial = full_cfg.get("adapter", {}).get("spatial", {})
    if graph_policy_requires_neighbor_windows(feature_policy):
        regions = graph_active_regions_for_policy(
            region,
            pricefm_block(data_cfg)["regions"],
            feature_policy,
            spatial=spatial,
        )
    else:
        regions = [region]
    for split in full_cfg["scope"].get("splits", ["train", "val", "test"]):
        for active_region in regions:
            path = window_npz_path(data_cfg, fold, active_region, split)
            if not path.exists():
                missing.append(str(path))
    return missing


def is_cell_complete(full_cfg, region, fold):
    paths = cell_paths(full_cfg, region, fold)
    required = [
        paths["model"] / "metric_summary.csv",
        paths["model"] / "model_method_summary.csv",
        paths["model"] / "predictions_with_naive_scaled.csv",
        paths["model"] / "report.md",
    ]
    return all(path.exists() and path.stat().st_size > 0 for path in required)


def is_adapter_ready_for_model(paths):
    """Return whether adapter outputs needed by the R model step are present."""
    required = [
        paths["adapter"] / "adapter_manifest.json",
        paths["adapter"] / "X_train.csv",
        paths["adapter"] / "X_val.csv",
        paths["adapter"] / "X_test.csv",
        paths["adapter"] / "y_train.csv",
        paths["adapter"] / "y_val.csv",
        paths["adapter"] / "y_test.csv",
        paths["adapter"] / "rows_train.csv",
        paths["adapter"] / "rows_val.csv",
        paths["adapter"] / "rows_test.csv",
    ]
    return all(path.exists() and path.stat().st_size > 0 for path in required)


def write_status_csv(path, rows):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "region", "fold", "status", "started_at", "ended_at", "elapsed_seconds",
        "message", "config", "adapter_dir", "model_dir", "adapter_log",
        "model_log", "time_log", "summary_log",
    ]
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row.get(k, "") for k in fields})


def cell_statuses_have_failures(rows):
    """Return TRUE when any cell has a non-success orchestration status."""
    return any(str(row.get("status", "")) not in SUCCESS_CELL_STATUSES for row in rows)


def _run_logged(cmd, log_path, cwd=None):
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with open(log_path, "w") as log:
        log.write("$ {}\n\n".format(" ".join(map(str, cmd))))
        log.flush()
        proc = subprocess.run(
            [str(x) for x in cmd],
            cwd=str(cwd) if cwd is not None else str(repo_path(".")),
            stdout=log,
            stderr=subprocess.STDOUT,
            check=False,
        )
    return proc.returncode


def cleanup_adapter_matrices(adapter_dir):
    adapter_dir = repo_path(adapter_dir)
    removed = []
    for pattern in ("X_*.csv",):
        for path in adapter_dir.glob(pattern):
            path.unlink()
            removed.append(str(path))
    return removed


def _matches_any(path, patterns):
    text = str(path)
    name = path.name
    return any(fnmatch.fnmatch(name, pattern) or fnmatch.fnmatch(text, pattern) for pattern in patterns)


def cleanup_success_artifacts(paths, hygiene=None):
    hygiene = dict(hygiene or {})
    if hygiene and not bool(hygiene.get("enabled", True)):
        return []
    preserve_patterns = list(hygiene.get("preserve_patterns", [
        "adapter_manifest.json",
        "feature_manifest.json",
        "rows_*.csv",
        "rows_all.csv",
        "y_*.csv",
        "metric_summary.csv",
        "model_method_summary.csv",
        "predictions_with_naive_scaled.csv",
        "report.md",
        "*.png",
        "*.pdf",
        "*.json",
        "*.log",
    ]))
    groups = [
        (
            paths["adapter"],
            list(hygiene.get("clean_adapter_patterns", ["X_*.csv"])),
        ),
        (
            paths["model"],
            list(hygiene.get("clean_model_patterns", ["*.rds", "*.rda", "*.RData"])),
        ),
    ]
    removed = []
    for root, patterns in groups:
        root = repo_path(root)
        if not root.exists():
            continue
        for pattern in patterns:
            for path in root.glob(pattern):
                if not path.is_file() or _matches_any(path, preserve_patterns):
                    continue
                path.unlink()
                removed.append(str(path))
    return removed


def run_cell(full_cfg, data_cfg, region, fold, force=False, resume=True, dry_run=False):
    paths = cell_paths(full_cfg, region, fold)
    started = time.time()
    started_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started))
    base = {
        "region": region,
        "fold": int(fold),
        "started_at": started_at,
        "config": str(paths["config"]),
        "adapter_dir": str(paths["adapter"]),
        "model_dir": str(paths["model"]),
        "adapter_log": str(paths["adapter_log"]),
        "model_log": str(paths["model_log"]),
        "time_log": str(paths["model_time"]),
        "summary_log": str(paths["summary_log"]),
    }

    if resume and not force and is_cell_complete(full_cfg, region, fold):
        return _finish_status(base, started, "skipped_complete", "cell already complete")

    missing = missing_window_files(full_cfg, data_cfg, region, fold)
    if missing:
        return _finish_status(base, started, "missing_windows", ";".join(missing))

    write_cell_config(full_cfg, data_cfg, region, fold)
    if dry_run:
        return _finish_status(base, started, "planned", "dry run")

    if force:
        if paths["adapter"].exists():
            shutil.rmtree(paths["adapter"])
        if paths["model"].exists():
            shutil.rmtree(paths["model"])

    paths["logs"].mkdir(parents=True, exist_ok=True)
    python_bin = repo_path(full_cfg.get("python_bin", sys.executable))
    rscript_bin = repo_path(full_cfg.get("rscript_bin", "Rscript"))
    cfg_path = paths["config"]

    if force or not is_adapter_ready_for_model(paths):
        adapter_cmd = [
            python_bin,
            repo_path("application/scripts/pricefm/07_build_desn_direct_horizon_adapter.py"),
            "--smoke-config", cfg_path,
            "--force", "true",
        ]
        code = _run_logged(adapter_cmd, paths["adapter_log"])
        if code != 0:
            return _finish_status(base, started, "adapter_failed", "return code {}".format(code))
    else:
        paths["adapter_log"].parent.mkdir(parents=True, exist_ok=True)
        paths["adapter_log"].write_text("Adapter already present; reused existing manifest.\n")

    model_cmd = [
        "/usr/bin/time", "-v", "-o", paths["model_time"],
        rscript_bin,
        repo_path("application/scripts/pricefm/08_run_desn_model_smoke.R"),
        "--smoke-config", cfg_path,
        "--force", "true",
    ]
    code = _run_logged(model_cmd, paths["model_log"])
    if code != 0:
        return _finish_status(base, started, "model_failed", "return code {}".format(code))

    summary_cmd = [
        python_bin,
        repo_path("application/scripts/pricefm/09_summarize_desn_model_smoke.py"),
        "--smoke-config", cfg_path,
    ]
    code = _run_logged(summary_cmd, paths["summary_log"])
    if code != 0:
        return _finish_status(base, started, "summary_failed", "return code {}".format(code))

    if not bool(full_cfg["adapter"].get("keep_matrices_after_success", False)):
        cleanup_success_artifacts(paths, full_cfg.get("artifact_hygiene"))

    return _finish_status(base, started, "completed", "ok")


def _finish_status(base, started, status, message):
    ended = time.time()
    out = dict(base)
    out.update({
        "status": status,
        "ended_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ended)),
        "elapsed_seconds": round(ended - started, 3),
        "message": message,
    })
    return out


def run_cells(full_cfg, data_cfg, regions=None, folds=None, jobs=1,
              force=False, resume=True, dry_run=False, max_cells=None):
    cells = list(iter_cells(full_cfg, data_cfg, regions=regions, folds=folds))
    if max_cells is not None:
        cells = cells[:int(max_cells)]
    results = []
    if int(jobs) <= 1 or dry_run:
        for region, fold in cells:
            results.append(run_cell(full_cfg, data_cfg, region, fold, force, resume, dry_run))
    else:
        with ThreadPoolExecutor(max_workers=int(jobs)) as ex:
            futs = [
                ex.submit(run_cell, full_cfg, data_cfg, region, fold, force, resume, dry_run)
                for region, fold in cells
            ]
            for fut in as_completed(futs):
                results.append(fut.result())
    results.sort(key=lambda x: (x["region"], int(x["fold"])))
    return results


def parse_time_log(path):
    path = repo_path(path)
    out = {"elapsed_wall": "", "max_rss_kb": ""}
    if not path.exists():
        return out
    text = path.read_text(errors="replace")
    for line in text.splitlines():
        if "Elapsed (wall clock) time" in line:
            if "):" in line:
                out["elapsed_wall"] = line.rsplit("):", 1)[1].strip()
            else:
                out["elapsed_wall"] = line.rsplit(":", 1)[-1].strip()
            break
    m = re.search(r"Maximum resident set size \(kbytes\):\s*(\d+)", text)
    if m:
        out["max_rss_kb"] = int(m.group(1))
    return out


def markdown_table(rows, columns):
    if not rows:
        return "_No rows._\n"
    lines = [
        "| " + " | ".join(columns) + " |",
        "| " + " | ".join(["---"] * len(columns)) + " |",
    ]
    for row in rows:
        vals = []
        for col in columns:
            val = row.get(col, "")
            if isinstance(val, float):
                vals.append("{:.6g}".format(val))
            else:
                vals.append(str(val))
        lines.append("| " + " | ".join(vals) + " |")
    return "\n".join(lines) + "\n"
