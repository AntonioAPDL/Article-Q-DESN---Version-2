#!/usr/bin/env python3
"""Close R102B and freeze one whole validation-selected Normal RHS panel."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import shutil
import tempfile
from typing import Any

import pandas as pd

from pricefm_common import sha256_file, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PREP = DATA / "launch_prep/pricefm_stage_r102b_recursive_validation_20260916"
R102_PREP = DATA / "launch_prep/pricefm_stage_r102_recursive_normal_20260916"
OUTPUT = DATA / "authoritative/pricefm_stage_r102b_recursive_validation_closeout_20260916"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--prep-dir", type=Path, default=PREP)
    value.add_argument("--r102-prep", type=Path, default=R102_PREP)
    value.add_argument("--output-dir", type=Path, default=OUTPUT)
    value.add_argument("--force", action="store_true")
    return value


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def verify_prep(prep: Path) -> tuple[dict[str, Any], pd.DataFrame]:
    summary = read_json(prep / "summary.json")
    for role, name in summary["output_files"].items():
        if sha256_file(prep / name) != summary["output_sha256"][role]:
            raise RuntimeError("R102B prep hash mismatch: {}".format(role))
    sources = pd.read_csv(prep / "source_manifest.csv")
    for row in sources.itertuples(index=False):
        if not Path(row.path).is_file() or sha256_file(row.path) != str(row.sha256):
            raise RuntimeError("R102B source changed: {}".format(row.path))
    return summary, pd.read_csv(prep / "pricefm_stage_r102b_task_manifest.csv")


def verify_surface(row: Any) -> tuple[dict[str, Any], dict[str, pd.DataFrame], list[dict[str, Any]]]:
    output = Path(row.output_dir)
    terminal_path = output / "terminal.json"
    terminal = read_json(terminal_path)
    if (
        terminal.get("status") != "completed_recursive_validation_surface"
        or terminal.get("task_id") != str(row.task_id)
        or terminal.get("panel") != str(row.panel)
        or terminal.get("prior_type") != str(row.prior_type)
        or int(terminal.get("fold", -1)) != int(row.fold)
        or terminal.get("test_opened") is not False
        or terminal.get("quantile_fit_started") is not False
        or int(terminal.get("posterior_paths", -1)) != 500
    ):
        raise RuntimeError("invalid R102B surface terminal: {}".format(row.task_id))
    paths = {}
    records = [{
        "role": "surface_terminal",
        "task_id": str(row.task_id),
        "path": str(terminal_path.resolve()),
        "bytes": terminal_path.stat().st_size,
        "sha256": sha256_file(terminal_path),
    }]
    for artifact in terminal["artifacts"]:
        path = output / artifact["path"]
        if not path.is_file() or sha256_file(path) != artifact["sha256"]:
            raise RuntimeError("changed R102B surface artifact: {}".format(path))
        paths[artifact["role"]] = pd.read_csv(path)
        records.append({
            "role": artifact["role"],
            "task_id": str(row.task_id),
            "path": str(path.resolve()),
            "bytes": path.stat().st_size,
            "sha256": artifact["sha256"],
        })
    origins = paths["origin_manifest"]
    if len(origins) != int(terminal["origins"]):
        raise RuntimeError("R102B origin manifest count mismatch")
    for origin in origins.itertuples(index=False):
        path = Path(origin.path)
        marker = Path(origin.terminal_path)
        if (
            not path.is_file()
            or not marker.is_file()
            or sha256_file(path) != str(origin.sha256)
            or sha256_file(marker) != str(origin.terminal_sha256)
        ):
            raise RuntimeError("changed R102B recursive path: {}".format(path))
    for source in paths["task_sources"].itertuples(index=False):
        path = Path(source.path)
        if not path.is_file() or sha256_file(path) != str(source.sha256):
            raise RuntimeError("changed R102B task source: {}".format(path))
    return terminal, paths, records


def aggregate_surfaces(folds: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for (panel, prior), group in folds.groupby(["panel", "prior_type"], sort=True):
        weight = group.n_loss_atoms.astype(float)
        rows.append({
            "panel": panel,
            "prior_type": prior,
            "aggregate_validation_AQL_original": float((group.validation_AQL_original * weight).sum() / weight.sum()),
            "worst_fold_validation_AQL_original": float(group.validation_AQL_original.max()),
            "mean_fold_validation_AQL_original": float(group.validation_AQL_original.mean()),
            "validation_AQCR": float((group.validation_AQCR * weight).sum() / weight.sum()),
            "n_loss_atoms": int(weight.sum()),
            "folds_complete": int(group.fold.nunique()),
            "selection_eligible": prior == "rhs_ns" and group.fold.nunique() == 3,
        })
    return pd.DataFrame(rows).sort_values(["prior_type", "aggregate_validation_AQL_original", "panel"])


def select_rhs(surface: pd.DataFrame) -> pd.Series:
    eligible = surface[surface.selection_eligible.astype(bool)].copy()
    if len(eligible) != 2 or set(eligible.panel) != {"r98_control", "r100_primary"}:
        raise RuntimeError("R102B selection requires both complete RHS panels")
    eligible["control_tiebreak"] = eligible.panel.ne("r98_control").astype(int)
    return eligible.sort_values([
        "aggregate_validation_AQL_original",
        "worst_fold_validation_AQL_original",
        "control_tiebreak",
    ]).iloc[0]


def run(args: argparse.Namespace) -> dict[str, Any]:
    prep = args.prep_dir.resolve()
    r102_prep = args.r102_prep.resolve()
    output = args.output_dir.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists() and any(output.iterdir()) and not args.force:
        existing = output / "summary.json"
        if existing.is_file():
            value = read_json(existing)
            if value.get("status") == "completed_recursive_normal_panel_frozen":
                print(json.dumps(value, indent=2, sort_keys=True))
                return value
        raise FileExistsError(output)
    _, tasks = verify_prep(prep)
    if len(tasks) != 12:
        raise RuntimeError("R102B closeout requires all 12 tasks")
    fold_frames = []
    region_frames = []
    quantile_frames = []
    horizon_frames = []
    source_records = []
    terminals = []
    for row in tasks.sort_values(["panel", "prior_type", "fold"]).itertuples(index=False):
        terminal, tables, records = verify_surface(row)
        terminals.append(terminal)
        fold_frames.append(tables["metrics_overall"])
        region_frames.append(tables["metrics_region"])
        quantile_frames.append(tables["metrics_quantile"])
        horizon_frames.append(tables["metrics_horizon"])
        source_records.extend(records)
    folds = pd.concat(fold_frames, ignore_index=True)
    regions = pd.concat(region_frames, ignore_index=True)
    quantiles = pd.concat(quantile_frames, ignore_index=True)
    horizons = pd.concat(horizon_frames, ignore_index=True)
    surfaces = aggregate_surfaces(folds)
    selected = select_rhs(surfaces)

    panel_map = pd.read_csv(r102_prep / "pricefm_stage_r102_panel_map.csv")
    driver = panel_map[
        (panel_map.panel == selected.panel) & panel_map.fold.astype(int).isin([1, 2, 3])
    ].copy()
    if len(driver) != 114 or driver[["region", "fold"]].duplicated().any():
        raise RuntimeError("selected R102B driver panel is incomplete")
    driver["selected_prior_type"] = "rhs_ns"
    driver["selection_split"] = "validation_only_complete_panel"
    driver["test_access_authorized"] = False
    driver["selection_reason"] = "minimum_complete_panel_aggregate_validation_AQL"

    gates = pd.DataFrame([
        ("surface_tasks_complete", len(terminals) == 12, len(terminals)),
        ("all_surfaces_500_paths", all(int(x["posterior_paths"]) == 500 for x in terminals), 500),
        ("all_surfaces_38_regions", all(int(x["regions"]) == 38 for x in terminals), 38),
        ("all_folds_complete", len(folds) == 12 and folds.fold.nunique() == 3, len(folds)),
        ("all_metrics_finite", folds.validation_AQL_original.notna().all(), folds.validation_AQL_original.notna().sum()),
        ("test_never_opened", all(x["test_opened"] is False for x in terminals), False),
        ("one_rhs_panel_selected", len(driver) == 114, selected.panel),
        ("ridge_is_diagnostic_only", selected.prior_type == "rhs_ns", selected.prior_type),
        ("quantile_and_mutations_blocked", True, "quantile;joint;mcmc;registry;article;test"),
    ], columns=["gate", "passed", "observed"])
    if not gates.passed.all():
        raise RuntimeError("R102B G3 closeout gate failed")

    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        tables = {
            "fold_metrics": folds,
            "surface_metrics": surfaces,
            "region_metrics": regions,
            "quantile_metrics": quantiles,
            "horizon_metrics": horizons,
            "selected_driver_panel": driver,
            "gates": gates,
            "source_manifest": pd.DataFrame(source_records).sort_values(["role", "task_id", "path"]),
        }
        filenames = {
            "fold_metrics": "pricefm_stage_r102b_fold_metrics.csv",
            "surface_metrics": "pricefm_stage_r102b_surface_metrics.csv",
            "region_metrics": "pricefm_stage_r102b_region_metrics.csv",
            "quantile_metrics": "pricefm_stage_r102b_quantile_metrics.csv",
            "horizon_metrics": "pricefm_stage_r102b_horizon_metrics.csv",
            "selected_driver_panel": "pricefm_stage_r102b_selected_normal_rhs_driver_panel.csv",
            "gates": "pricefm_stage_r102b_g3_gates.csv",
            "source_manifest": "source_manifest.csv",
        }
        for role, table in tables.items():
            table.to_csv(temporary / filenames[role], index=False, quoting=csv.QUOTE_MINIMAL)
        decision = {
            "stage": "R102B",
            "selected_panel": str(selected.panel),
            "selected_prior_type": "rhs_ns",
            "aggregate_validation_AQL_original": float(selected.aggregate_validation_AQL_original),
            "worst_fold_validation_AQL_original": float(selected.worst_fold_validation_AQL_original),
            "selection_rule": "minimum_complete_panel_aggregate_validation_AQL_then_worst_fold_then_r98_control",
            "selection_split": "validation_only",
            "test_opened": False,
            "driver_rows": 114,
        }
        write_json(temporary / "pricefm_stage_r102b_frozen_decision.json", decision)
        comparison = surfaces[surfaces.prior_type == "rhs_ns"].sort_values("panel")
        report = """# PriceFM Stage-R102B recursive validation closeout

R102B generated 500 synchronized recursive Normal paths for all twelve complete
validation surfaces. It selected the **{panel}** Normal-RHS panel using only
aggregate original-unit validation AQL.

| Panel | Aggregate validation AQL | Worst-fold AQL |
|---|---:|---:|
{rows}

Ridge results remain diagnostic. The selected 114-row region-fold RHS panel is
the only admissible common endogenous driver for R103. Outer-test scoring,
joint models, MCMC, registry mutation, and article mutation remain blocked.
""".format(
            panel=selected.panel,
            rows="\n".join(
                "| {} | {:.6f} | {:.6f} |".format(
                    row.panel,
                    row.aggregate_validation_AQL_original,
                    row.worst_fold_validation_AQL_original,
                )
                for row in comparison.itertuples(index=False)
            ),
        )
        (temporary / "pricefm_stage_r102b_recursive_validation_closeout.md").write_text(report)
        artifacts = {
            **filenames,
            "decision": "pricefm_stage_r102b_frozen_decision.json",
            "report": "pricefm_stage_r102b_recursive_validation_closeout.md",
        }
        summary = {
            "stage": "R102B",
            "status": "completed_recursive_normal_panel_frozen",
            "surface_tasks_complete": 12,
            "posterior_paths": 500,
            "selected_panel": str(selected.panel),
            "selected_prior_type": "rhs_ns",
            "selected_driver_rows": 114,
            "aggregate_validation_AQL_original": float(selected.aggregate_validation_AQL_original),
            "selection_split": "validation_only",
            "test_opened": False,
            "quantile_fit_started": False,
            "registry_mutated": False,
            "article_mutated": False,
            "next_gate": "R103_independent_AL_exAL_refits_on_frozen_R102B_driver_only",
            "output_files": artifacts,
            "output_sha256": {role: sha256_file(temporary / name) for role, name in artifacts.items()},
        }
        write_json(temporary / "summary.json", summary)
        if output.exists():
            shutil.rmtree(output)
        temporary.replace(output)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> int:
    return 0 if run(parser().parse_args()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
