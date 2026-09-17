#!/usr/bin/env python3
"""Prepare the validation-only PriceFM R102B recursive path campaign."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any

import pandas as pd

from pricefm_common import sha256_file, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R102_PREP = DATA / "launch_prep/pricefm_stage_r102_recursive_normal_20260916"
R102_CAMPAIGN = DATA / "campaigns/pricefm_stage_r102_recursive_normal_20260916"
OUTPUT = DATA / "launch_prep/pricefm_stage_r102b_recursive_validation_20260916"
CAMPAIGN = DATA / "campaigns/pricefm_stage_r102b_recursive_validation_20260916"
PANELS = ("r98_control", "r100_primary")
PRIORS = ("scaled_ridge", "rhs_ns")
FOLDS = (1, 2, 3)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--r102-prep", type=Path, default=R102_PREP)
    value.add_argument("--r102-campaign", type=Path, default=R102_CAMPAIGN)
    value.add_argument("--output-dir", type=Path, default=OUTPUT)
    value.add_argument("--campaign-root", type=Path, default=CAMPAIGN)
    value.add_argument("--workers", type=int, default=12)
    value.add_argument("--posterior-paths", type=int, default=500)
    value.add_argument("--base-seed", type=int, default=2026091602)
    value.add_argument("--write", action="store_true")
    value.add_argument("--force", action="store_true")
    return value


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def valid_fit(path: Path) -> bool:
    terminal_path = path / "terminal.json"
    if not terminal_path.is_file():
        return False
    try:
        terminal = read_json(terminal_path)
        return (
            terminal.get("status") == "completed_recursive_normal_fit"
            and terminal.get("converged") is True
            and terminal.get("test_opened") is False
            and all(
                (path / row["path"]).is_file()
                and sha256_file(path / row["path"]) == row["sha256"]
                for row in terminal.get("artifacts", [])
            )
        )
    except (OSError, KeyError, json.JSONDecodeError):
        return False


def verify_r102(prep: Path, campaign: Path) -> tuple[dict[str, Any], pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    summary = read_json(prep / "summary.json")
    for role, filename in summary["output_files"].items():
        if sha256_file(prep / filename) != summary["output_sha256"][role]:
            raise RuntimeError("R102 preparation hash mismatch: {}".format(role))
    if sha256_file(prep / "pricefm_stage_r102_launch_control.json") != summary["launch_control_sha256"]:
        raise RuntimeError("R102 launch-control hash mismatch")
    terminal = read_json(campaign / "campaign_terminal.json")
    if terminal != {
        "article_mutated": False,
        "design_cells_complete": 144,
        "fits_complete": 291,
        "next_gate": "R102B_synchronized_validation_paths_and_complete_panel_freeze",
        "quantile_fit_started": False,
        "registry_mutated": False,
        "rhs_complete": 147,
        "ridge_complete": 144,
        "stage": "R102A",
        "status": "completed_normal_refits_paths_pending",
        "test_opened": False,
    }:
        raise RuntimeError("R102A terminal does not authorize R102B")
    designs = pd.read_csv(prep / "pricefm_stage_r102_design_manifest.csv")
    fits = pd.read_csv(prep / "pricefm_stage_r102_fit_manifest.csv")
    panels = pd.read_csv(prep / "pricefm_stage_r102_panel_map.csv")
    if len(designs) != 144 or len(fits) != 291 or len(panels) != 228:
        raise RuntimeError("R102A manifests are incomplete")
    invalid = [path for path in fits.output_dir if not valid_fit(Path(path))]
    if invalid:
        raise RuntimeError("R102B found {} invalid R102A fits".format(len(invalid)))
    if set(panels.panel) != set(PANELS) or set(panels.fold.astype(int)) != set(FOLDS):
        raise RuntimeError("R102 panel map is incomplete")
    return terminal, designs, fits, panels


def build(args: argparse.Namespace) -> dict[str, Any]:
    if not 1 <= args.workers <= 12:
        raise ValueError("R102B uses between 1 and 12 one-core surface workers")
    if args.posterior_paths != 500:
        raise ValueError("R102B production requires exactly 500 paths")
    prep = args.r102_prep.resolve()
    r102_campaign = args.r102_campaign.resolve()
    terminal, designs, fits, panels = verify_r102(prep, r102_campaign)
    campaign = args.campaign_root.resolve()
    rows = []
    for panel in PANELS:
        for prior in PRIORS:
            for fold in FOLDS:
                subset = panels[(panels.panel == panel) & (panels.fold.astype(int) == fold)]
                if len(subset) != 38 or subset.region.astype(str).nunique() != 38:
                    raise RuntimeError("R102B task lacks a complete 38-region panel")
                rows.append({
                    "task_id": "r102b_{}_{}_f{}".format(panel, prior, fold),
                    "panel": panel,
                    "prior_type": prior,
                    "fold": fold,
                    "posterior_paths": args.posterior_paths,
                    "base_seed": args.base_seed,
                    "output_dir": str(campaign / "surfaces" / panel / prior / "fold_{}".format(fold)),
                    "selection_split": "validation_only",
                    "test_access_authorized": False,
                })
    tasks = pd.DataFrame(rows)
    if len(tasks) != 12 or tasks.task_id.duplicated().any():
        raise RuntimeError("R102B requires 12 unique complete-surface tasks")

    code_root = Path(__file__).resolve().parents[3]
    source_paths = [
        Path(__file__).resolve(),
        Path(__file__).resolve().parent / "pricefm_recursive_normal.py",
        Path(__file__).resolve().parent / "pricefm_recursive_adapter.py",
        Path(__file__).resolve().parent / "pricefm_desn_adapter.py",
        Path(__file__).resolve().parent / "340_run_pricefm_stage_r102b_recursive_validation.py",
        Path(__file__).resolve().parent / "341_closeout_pricefm_stage_r102b_recursive_validation.py",
        Path(__file__).resolve().parent / "342_orchestrate_pricefm_stage_r102b_recursive_validation.py",
        code_root / "application/R/pricefm_recursive_forecast.R",
        prep / "summary.json",
        prep / "pricefm_stage_r102_design_manifest.csv",
        prep / "pricefm_stage_r102_fit_manifest.csv",
        prep / "pricefm_stage_r102_panel_map.csv",
        r102_campaign / "campaign_terminal.json",
    ]
    sources = pd.DataFrame([
        {"path": str(path.resolve()), "bytes": path.stat().st_size, "sha256": sha256_file(path)}
        for path in source_paths
    ])
    gates = pd.DataFrame([
        ("r102a_complete", terminal["fits_complete"] == 291, terminal["fits_complete"]),
        ("all_r102a_fits_hash_valid", all(valid_fit(Path(path)) for path in fits.output_dir), len(fits)),
        ("complete_surface_tasks", len(tasks) == 12, len(tasks)),
        ("posterior_paths", args.posterior_paths == 500, args.posterior_paths),
        ("validation_only", tasks.selection_split.eq("validation_only").all(), "validation_only"),
        ("test_blocked", not tasks.test_access_authorized.astype(bool).any(), False),
        ("later_mutations_blocked", True, "test;quantile;joint;mcmc;registry;article"),
    ], columns=["gate", "passed", "observed"])
    if not gates.passed.all():
        raise RuntimeError("R102B preparation gate failed")
    return {
        "tasks": tasks,
        "sources": sources,
        "gates": gates,
        "campaign": campaign,
        "r102_prep": prep,
        "r102_campaign": r102_campaign,
        "workers": int(args.workers),
        "summary": {
            "stage": "R102B",
            "status": "prepared_not_launched",
            "surface_tasks": 12,
            "panels": list(PANELS),
            "prior_types": list(PRIORS),
            "folds": list(FOLDS),
            "regions_per_surface": 38,
            "posterior_paths": 500,
            "workers_requested": int(args.workers),
            "selection_rule": "minimum_complete_panel_aggregate_validation_AQL_then_worst_fold_then_r98_control",
            "selection_split": "validation_only",
            "test_opened": False,
            "quantile_fit_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "launch_authorized": False,
        },
    }


def materialize(bundle: dict[str, Any], output: Path, force: bool = False) -> dict[str, Any]:
    output = output.resolve()
    if output.exists() and any(output.iterdir()) and not force:
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    bundle["campaign"].mkdir(parents=True, exist_ok=True)
    files = {
        "tasks": "pricefm_stage_r102b_task_manifest.csv",
        "sources": "source_manifest.csv",
        "gates": "pricefm_stage_r102b_prep_gates.csv",
    }
    for role, name in files.items():
        bundle[role].to_csv(output / name, index=False, quoting=csv.QUOTE_MINIMAL)
    control = {
        "stage": "R102B",
        "campaign_root": str(bundle["campaign"]),
        "r102_prep": str(bundle["r102_prep"]),
        "r102_campaign": str(bundle["r102_campaign"]),
        "python": str(DATA / "venv/bin/python"),
        "workers": bundle["workers"],
        "approval_token": "RUN_PRICEFM_R102B_RECURSIVE_VALIDATION",
        "launch_authorized": False,
        "selection_split": "validation_only",
        "forbidden": ["test", "quantile_fit", "joint", "mcmc", "registry", "article"],
    }
    write_json(output / "pricefm_stage_r102b_launch_control.json", control)
    summary = dict(bundle["summary"])
    summary["output_files"] = files
    summary["output_sha256"] = {role: sha256_file(output / name) for role, name in files.items()}
    summary["launch_control_sha256"] = sha256_file(output / "pricefm_stage_r102b_launch_control.json")
    write_json(output / "summary.json", summary)
    report = """# PriceFM Stage-R102B recursive validation preparation

R102B contains twelve validation-only complete-surface tasks: two frozen
panels by two Normal priors by three folds. Each task generates 500
synchronized recursive paths for all 38 regions. Validation outcomes are used
only after path generation for original-unit scoring.

Selection compares the two complete RHS panels by aggregate validation AQL.
Worst-fold AQL and then the R98 control panel are deterministic tie breakers.
Ridge surfaces are diagnostics and cannot become the quantile-driver panel.
Outer test, quantile fitting, joint models, MCMC, registry mutation, and
article mutation remain blocked.
"""
    (output / "pricefm_stage_r102b_launch_prep.md").write_text(report)
    summary["report_sha256"] = sha256_file(output / "pricefm_stage_r102b_launch_prep.md")
    write_json(output / "summary.json", summary)
    return summary


def main() -> int:
    args = parser().parse_args()
    bundle = build(args)
    summary = materialize(bundle, args.output_dir, args.force) if args.write else bundle["summary"]
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
