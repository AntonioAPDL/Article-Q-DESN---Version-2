#!/usr/bin/env python3
"""Build one hash-sealed R102 causal Normal sufficient-statistic cell."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from pricefm_common import load_config
from pricefm_desn_adapter import load_window
from pricefm_graph import graph_adj_matrix
from pricefm_recursive_normal import causal_teacher_forced_statistics, write_statistics


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, required=True)
    p.add_argument("--design-id", required=True)
    p.add_argument("--force", action="store_true")
    return p


def _truthy(value: object) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes"}


def run(args: argparse.Namespace) -> dict:
    manifest = pd.read_csv(args.manifest)
    selected = manifest[manifest.design_id.astype(str).eq(str(args.design_id))]
    if len(selected) != 1:
        raise RuntimeError("design_id must identify exactly one R102 manifest row")
    row = selected.iloc[0]
    if str(row.selection_split) != "train_validation_only" or _truthy(row.test_access_authorized):
        raise RuntimeError("R102 design attempted to open a forbidden split")
    spec = json.loads(str(row.spec_json))
    active_regions = [str(x) for x in json.loads(str(row.active_regions))]
    data_config = load_config(str(row.data_config_path))
    windows = {
        region: load_window(data_config, int(row.fold), region, "train")
        for region in active_regions
    }
    result = causal_teacher_forced_statistics(
        windows,
        spec,
        input_regions=list(graph_adj_matrix()),
    )
    terminal = write_statistics(Path(row.statistics_dir), result, force=args.force)
    terminal.update({
        "stage": "R102",
        "design_id": str(row.design_id),
        "region": str(row.region),
        "fold": int(row.fold),
        "structure_sha256": str(row.structure_sha256),
    })
    # Re-write the enriched terminal only after the statistics packet exists.
    from pricefm_common import write_json
    write_json(Path(row.statistics_dir) / "terminal.json", terminal)
    return terminal


def main() -> int:
    args = parser().parse_args()
    print(json.dumps(run(args), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
