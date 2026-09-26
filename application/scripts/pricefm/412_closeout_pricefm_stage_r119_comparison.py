#!/usr/bin/env python3
"""Build the read-only R119 comparison on the aligned BG validation surface."""

from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import sys
from typing import Any

import numpy as np
import pandas as pd


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_common import sha256_file, write_json  # noqa: E402


TAG = "pricefm_stage_r119_bg_extended_all_layer_exact_cran_20260925"
R118_TAG = "pricefm_stage_r118_exact_cran_quantile_repair_20260925"
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")


def load_r118_comparison() -> Any:
    path = SCRIPT_DIR / "408_closeout_pricefm_stage_r118_comparison.py"
    spec = importlib.util.spec_from_file_location("pricefm_r118_comparison_for_r119", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--campaign-root", type=Path)
    return value


def r119_rows(campaign: Path) -> pd.DataFrame:
    terminal = json.loads((campaign / "campaign_terminal.json").read_text())
    if terminal.get("status") != "completed_extended_bg_not_promoted" or terminal.get("test_opened"):
        raise RuntimeError("R119 is incomplete or violated its test firewall")
    selected = pd.read_csv(campaign / "closeout/fold1_frozen_choice_metrics.csv")
    if len(selected) != 3 or selected.fold.nunique() != 3:
        raise RuntimeError("R119 frozen operator metrics are incomplete")
    counts: dict[int, int] = {}
    for fold in (1, 2, 3):
        prediction = campaign / f"forecasts/family=al/fold={fold}/predictions.npz"
        with np.load(prediction) as packet:
            truth = np.asarray(packet["truth"])
            quantiles = np.asarray(packet["quantiles"])
        if truth.ndim != 2 or quantiles.size != 7:
            raise RuntimeError(f"R119 prediction geometry changed: {prediction}")
        counts[fold] = int(truth.size * quantiles.size)
    return pd.DataFrame({
        "reference": "R119_extended_all_layers_recursive",
        "fold": selected.fold.astype(int), "AQL": selected.AQL.astype(float),
        "n_loss_atoms": selected.fold.map(counts).astype(int),
        "comparison_role": "candidate_outer_validation",
        "directly_comparable": True,
        "source_path": str(campaign / "closeout/fold1_frozen_choice_metrics.csv"),
    })


def run(args: argparse.Namespace) -> dict[str, Any]:
    artifact = args.artifact_repo.resolve()
    data = artifact / "application/data_local/pricefm"
    campaign = (args.campaign_root or data / "campaigns" / TAG).resolve()
    output = campaign / "comparison_closeout"
    r118_module = load_r118_comparison()
    candidate = r119_rows(campaign)
    r118 = r118_module.r118_rows(data / "campaigns" / R118_TAG)
    strict = pd.concat(
        [candidate, r118, r118_module.strict_references(data)], ignore_index=True,
    )
    candidate_counts = candidate.set_index("fold").n_loss_atoms.to_dict()
    if any(
        int(row.n_loss_atoms) != int(candidate_counts[int(row.fold)])
        for row in strict.itertuples()
    ):
        raise RuntimeError("R119 and strict references do not share evaluation geometry")
    pooled = r118_module.pooled(strict)
    context = r118_module.authority_context(data)
    output.mkdir(parents=True, exist_ok=True)
    strict.to_csv(output / "strict_outer_validation_fold_comparison.csv", index=False)
    pooled.to_csv(output / "strict_outer_validation_pooled_comparison.csv", index=False)
    context.to_csv(output / "authority_and_pricefm_context.csv", index=False)
    candidate_row = pooled.loc[
        pooled.reference.eq("R119_extended_all_layers_recursive")
    ].iloc[0]
    direct_row = pooled.loc[pooled.reference.eq("R108_R97_direct_reference")].iloc[0]
    exposure_row = pooled.loc[
        pooled.reference.eq("R111B_exposure_aligned_readout")
    ].iloc[0]
    summary = {
        "stage": "R119_comparison",
        "status": "completed_read_only_comparison_not_promoted",
        "r119_pooled_outer_validation_AQL": float(candidate_row.pooled_AQL),
        "aligned_direct_reference_pooled_AQL": float(direct_row.pooled_AQL),
        "r111b_exposure_reference_pooled_AQL": float(exposure_row.pooled_AQL),
        "delta_AQL_R119_minus_aligned_direct": float(candidate_row.pooled_AQL - direct_row.pooled_AQL),
        "delta_AQL_R119_minus_R111B": float(candidate_row.pooled_AQL - exposure_row.pooled_AQL),
        "strict_reference_count": int(strict.reference.nunique() - 1),
        "mechanism_development_surface_already_observed": True,
        "promotion_authorized": False,
        "next_gate": "scientific_review_before_any_clean_confirmation_or_broadening",
        "test_opened": False, "registry_mutated": False,
        "article_mutated": False, "joint_model_fitted": False,
        "mcmc_fitted": False,
    }
    write_json(output / "summary.json", summary)
    (output / "README.md").write_text(
        "# PriceFM R119 read-only comparison\n\n"
        "R119 tests the extended all-layer BG readout on the same outer-validation "
        "geometry as R118 and the aligned R108/R111B/R116 references. This BG "
        "surface informed the mechanism design, so the result is diagnostic and "
        "cannot authorize registry or article promotion. Final-test authority and "
        "cached PriceFM scores remain context only.\n"
    )
    sources = sorted(set(strict.source_path) | set(context.source_path))
    generated = [
        output / "strict_outer_validation_fold_comparison.csv",
        output / "strict_outer_validation_pooled_comparison.csv",
        output / "authority_and_pricefm_context.csv", output / "summary.json",
        output / "README.md",
    ]
    write_json(output / "manifest.json", {
        "status": "hash_sealed_r119_read_only_comparison",
        "source_files": [{"path": path, "sha256": sha256_file(path)} for path in sources],
        "generated_files": [
            {"path": str(path), "sha256": sha256_file(path)} for path in generated
        ],
        "test_opened": False,
    })
    return summary


def main() -> int:
    result = run(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
