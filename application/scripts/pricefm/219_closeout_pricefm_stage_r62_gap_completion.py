#!/usr/bin/env python3
"""Close out Stage-R62 exact-gap completion into discoverable panel evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
MANIFEST = DATA / "experiment_grids/pricefm_stage_r62_gap_completion_20260827/launch_manifest.csv"
STATUS = DATA / "experiment_grids/pricefm_stage_r62_gap_completion_20260827/launch_status.csv"
OUTPUT = DATA / "authoritative/pricefm_stage_r62_gap_quantile_summary_20260827"
METHODS = ("qdesn_al_rhs_ns_exact_chunked", "qdesn_exal_rhs_ns_exact_chunked")


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=MANIFEST)
    p.add_argument("--launch-status", type=Path, default=STATUS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def run(args: argparse.Namespace) -> dict:
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    manifest = pd.read_csv(args.manifest)
    status = pd.read_csv(args.launch_status)
    completed = set(status.loc[status.status.isin(["completed", "skipped_complete"]), "case_id"].astype(str))
    panel_status = []
    metric_rows = []
    source_rows = []
    for row in manifest.sort_values(["region", "fold", "tau"]).itertuples(index=False):
        model = Path(row.output_dir)
        metric = model / "metric_summary.csv"
        is_complete = row.case_id in completed and metric.is_file()
        panel_status.append({
            "region": row.region, "fold": int(row.fold), "id": row.case_id,
            "tau": float(row.tau), "complete": is_complete,
            "model_dir": str(model), "adapter_dir": row.adapter_dir,
            "config_path": row.config,
        })
        if not is_complete:
            continue
        frame = pd.read_csv(metric)
        for method in METHODS:
            selected = frame[
                frame.method_id.astype(str).eq(method)
                & frame.split.astype(str).eq("val")
                & frame.unit.astype(str).eq("original")
            ]
            if len(selected) != 1:
                raise RuntimeError(f"Missing validation metric for {row.case_id} / {method}")
        source_rows.append({"path": str(metric), "sha256": sha256(metric), "bytes": metric.stat().st_size})
    panel = pd.DataFrame(panel_status)
    for (region, fold), group in manifest.groupby(["region", "fold"]):
        if len(group) != 7:
            continue
        for method in METHODS:
            values = []
            maes = []
            rmses = []
            aqcrs = []
            for row in group.itertuples(index=False):
                frame = pd.read_csv(Path(row.output_dir) / "metric_summary.csv")
                selected = frame[
                    frame.method_id.astype(str).eq(method)
                    & frame.split.astype(str).eq("val")
                    & frame.unit.astype(str).eq("original")
                ].iloc[0]
                values.append(float(selected.AQL)); maes.append(float(selected.MAE)); rmses.append(float(selected.RMSE)); aqcrs.append(float(selected.AQCR))
            metric_rows.append({
                "region": region, "fold": int(fold), "method_id": method,
                "split": "val", "unit": "original", "AQL": sum(values) / 7,
                "AQCR": sum(aqcrs) / 7, "MAE": sum(maes) / 7, "RMSE": sum(rmses) / 7,
            })
    panel.to_csv(output / "panel_status.csv", index=False)
    pd.DataFrame(metric_rows).to_csv(output / "panel_metric.csv", index=False)
    source_rows.extend([
        {"path": str(args.manifest.resolve()), "sha256": sha256(args.manifest), "bytes": args.manifest.stat().st_size},
        {"path": str(args.launch_status.resolve()), "sha256": sha256(args.launch_status), "bytes": args.launch_status.stat().st_size},
        {"path": str(Path(__file__).resolve()), "sha256": sha256(Path(__file__).resolve()), "bytes": Path(__file__).stat().st_size},
    ])
    pd.DataFrame(source_rows).drop_duplicates(["path", "sha256"]).to_csv(output / "source_manifest.csv", index=False)
    complete_count = int(panel.complete.sum())
    summary = {
        "status": "completed_exact_gap_quantile_summary" if complete_count == len(manifest) else "incomplete_exact_gap_quantile_summary",
        "expected_jobs": len(manifest), "complete_jobs": complete_count,
        "remaining_jobs": len(manifest) - complete_count, "failed_jobs": int((status.status == "failed").sum()),
        "panel_cells": int(panel[["region", "fold"]].drop_duplicates().shape[0]),
        "test_opened": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    write_json(output / "summary.json", summary)
    (output / "region_panel_quantile_summary_report.md").write_text(
        "# PriceFM Stage-R62 exact-gap quantile summary\n\n"
        f"Completed {complete_count}/{len(manifest)} train/validation-only quantile jobs across "
        f"{summary['panel_cells']} region/fold cells. Test remained sealed.\n"
    )
    if complete_count != len(manifest):
        raise RuntimeError(f"Gap completion is incomplete: {summary}")
    return summary


def main() -> int:
    args = parser().parse_args()
    print(json.dumps(run(args), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
