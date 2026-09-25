#!/usr/bin/env python3
"""Build the read-only R118 BG comparison without mutating any authority."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

import numpy as np
import pandas as pd


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_common import sha256_file, write_json


TAG = "pricefm_stage_r118_exact_cran_quantile_repair_20260925"
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--campaign-root", type=Path)
    return value


def pooled(frame: pd.DataFrame) -> pd.DataFrame:
    required = {"reference", "fold", "AQL", "n_loss_atoms"}
    if not required.issubset(frame):
        raise ValueError(f"comparison frame lacks {sorted(required - set(frame))}")
    rows = []
    for reference, group in frame.groupby("reference", sort=False):
        weights = group.n_loss_atoms.astype(float)
        rows.append({
            "reference": reference,
            "mean_fold_AQL": float(group.AQL.mean()),
            "pooled_AQL": float(np.average(group.AQL, weights=weights)),
            "n_loss_atoms": int(weights.sum()),
            "folds": int(group.fold.nunique()),
            "comparison_role": str(group.comparison_role.iloc[0]),
            "directly_comparable": bool(group.directly_comparable.astype(bool).all()),
        })
    return pd.DataFrame(rows).sort_values(
        ["directly_comparable", "pooled_AQL", "reference"],
        ascending=[False, True, True], kind="mergesort",
    ).reset_index(drop=True)


def r118_rows(campaign: Path) -> pd.DataFrame:
    terminal = json.loads((campaign / "campaign_terminal.json").read_text())
    if terminal.get("status") != "completed_pure_bg_not_promoted" or terminal.get("test_opened"):
        raise RuntimeError("R118 is not complete or violated its test firewall")
    selected = pd.read_csv(campaign / "closeout/fold1_frozen_choice_metrics.csv")
    if len(selected) != 3 or selected.fold.nunique() != 3:
        raise RuntimeError("R118 frozen family/operator metrics are incomplete")
    counts = {}
    for fold in (1, 2, 3):
        prediction = campaign / f"forecasts/family={terminal['selected_family']}/fold={fold}/predictions.npz"
        with np.load(prediction) as packet:
            truth = np.asarray(packet["truth"])
            quantiles = np.asarray(packet["quantiles"])
        if truth.ndim != 2 or quantiles.size != 7:
            raise RuntimeError(f"R118 prediction geometry changed: {prediction}")
        counts[fold] = int(truth.size * quantiles.size)
    return pd.DataFrame({
        "reference": "R118_pure_all_layers_recursive",
        "fold": selected.fold.astype(int),
        "AQL": selected.AQL.astype(float),
        "n_loss_atoms": selected.fold.map(counts).astype(int),
        "comparison_role": "candidate_outer_validation",
        "directly_comparable": True,
        "source_path": str(campaign / "closeout/fold1_frozen_choice_metrics.csv"),
    })


def strict_references(data: Path) -> pd.DataFrame:
    rows = []
    r111_path = data / "campaigns/pricefm_stage_r111b_bg_exposure_readout_20260922/pricefm_stage_r111b_bg_case_metrics.csv"
    r111 = pd.read_csv(r111_path)
    for value in r111.itertuples(index=False):
        rows.append({
            "reference": "R111B_exposure_aligned_readout", "fold": int(value.fold),
            "AQL": float(value.AQL), "n_loss_atoms": int(value.n_loss_atoms),
            "comparison_role": "aligned_outer_validation_reference",
            "directly_comparable": True, "source_path": str(r111_path),
        })
    r116_path = data / "authoritative/pricefm_stage_r116_transfer_closeout_20260924/r116_recomputed_factorial_metrics.csv"
    r116 = pd.read_csv(r116_path)
    for value in r116.loc[r116.cell.eq("D")].itertuples(index=False):
        rows.append({
            "reference": "R116_cell_D_normal_recursive", "fold": int(value.fold),
            "AQL": float(value.AQL), "n_loss_atoms": int(value.n_loss_atoms),
            "comparison_role": "aligned_outer_validation_reference",
            "directly_comparable": True, "source_path": str(r116_path),
        })
    r108_path = data / "authoritative/pricefm_stage_r108_recursive_driver_decomposition_20260920/pricefm_stage_r108_case_metrics.csv"
    r108 = pd.read_csv(r108_path)
    labels = {
        "r97_direct_reference": "R108_R97_direct_reference",
        "pricefm_quantile_paths_all_active": "R108_PriceFM_path_driver_diagnostic",
        "oracle_all_active": "R108_oracle_driver_diagnostic",
    }
    selected = r108.loc[r108.region.eq("BG") & r108.policy.isin(labels)]
    for value in selected.itertuples(index=False):
        rows.append({
            "reference": labels[str(value.policy)], "fold": int(value.fold),
            "AQL": float(value.AQL), "n_loss_atoms": int(value.n_loss_atoms),
            "comparison_role": (
                "aligned_outer_validation_reference"
                if value.policy == "r97_direct_reference" else "aligned_driver_diagnostic"
            ),
            "directly_comparable": True, "source_path": str(r108_path),
        })
    result = pd.DataFrame(rows)
    counts = result.groupby("reference").fold.nunique()
    if len(result) != 15 or not counts.eq(3).all():
        raise RuntimeError("strict R118 comparison references are incomplete")
    expected_atoms = {1: 81984, 2: 80640, 3: 82656}
    if any(int(row.n_loss_atoms) != expected_atoms[int(row.fold)] for row in result.itertuples()):
        raise RuntimeError("strict R118 comparison geometry changed")
    return result


def authority_context(data: Path) -> pd.DataFrame:
    path = data / "authoritative/pricefm_stage_r98_validity_first_authority_closeout_20260913/pricefm_stage_r98_authoritative_registry.csv"
    registry = pd.read_csv(path)
    bg = registry.loc[registry.region.eq("BG")].sort_values("fold")
    if len(bg) != 3:
        raise RuntimeError("R98 BG authority context is incomplete")
    columns = {
        "qdesn_AQL": ("R98_region_frozen_QDESN_final_test", "final_test_authority"),
        "current_authoritative_qdesn_AQL": ("pre_R98_QDESN_final_test", "historical_final_test"),
        "cached_pricefm_AQL": ("cached_PriceFM_final_test", "final_test_benchmark"),
        "selected_validation_AQL": ("R97_selected_outer_validation", "outer_validation_reference"),
    }
    rows = []
    for column, (reference, role) in columns.items():
        for value in bg.itertuples(index=False):
            rows.append({
                "reference": reference, "fold": int(value.fold),
                "AQL": float(getattr(value, column)), "comparison_role": role,
                "directly_comparable_to_R118": role == "outer_validation_reference",
                "source_path": str(path),
            })
    return pd.DataFrame(rows)


def run(args: argparse.Namespace) -> dict[str, Any]:
    artifact = args.artifact_repo.resolve()
    data = artifact / "application/data_local/pricefm"
    campaign = (args.campaign_root or data / "campaigns" / TAG).resolve()
    output = campaign / "comparison_closeout"
    candidate = r118_rows(campaign)
    strict = pd.concat([candidate, strict_references(data)], ignore_index=True)
    candidate_counts = candidate.set_index("fold").n_loss_atoms.to_dict()
    if any(int(row.n_loss_atoms) != int(candidate_counts[int(row.fold)]) for row in strict.itertuples()):
        raise RuntimeError("R118 and strict references do not share evaluation geometry")
    strict_pooled = pooled(strict)
    context = authority_context(data)
    output.mkdir(parents=True, exist_ok=True)
    strict.to_csv(output / "strict_outer_validation_fold_comparison.csv", index=False)
    strict_pooled.to_csv(output / "strict_outer_validation_pooled_comparison.csv", index=False)
    context.to_csv(output / "authority_and_pricefm_context.csv", index=False)
    candidate_row = strict_pooled.loc[
        strict_pooled.reference.eq("R118_pure_all_layers_recursive")
    ].iloc[0]
    direct_row = strict_pooled.loc[
        strict_pooled.reference.eq("R108_R97_direct_reference")
    ].iloc[0]
    summary = {
        "stage": "R118_comparison",
        "status": "completed_read_only_comparison_not_promoted",
        "r118_pooled_outer_validation_AQL": float(candidate_row.pooled_AQL),
        "aligned_direct_reference_pooled_AQL": float(direct_row.pooled_AQL),
        "delta_AQL_R118_minus_aligned_direct": float(candidate_row.pooled_AQL - direct_row.pooled_AQL),
        "strict_reference_count": int(strict.reference.nunique() - 1),
        "authority_context_is_directly_comparable": False,
        "promotion_authorized": False,
        "extended_variant_authorized": False,
        "next_gate": "scientific_review_of_R118_before_any_new_fit_or_promotion",
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
        "joint_model_fitted": False,
        "mcmc_fitted": False,
    }
    write_json(output / "summary.json", summary)
    (output / "README.md").write_text(
        "# PriceFM R118 read-only comparison\n\n"
        "The strict table compares R118 with BG outer-validation references sharing "
        "the same 122/120/123 origins and 96-by-7 loss geometry. The R98 QDESN "
        "authority and cached PriceFM values are final-test context, not a like-for-like "
        "promotion gate for this outer-validation pilot. No registry or article action "
        "is authorized.\n"
    )
    sources = sorted(set(strict.source_path) | set(context.source_path))
    generated = [
        output / "strict_outer_validation_fold_comparison.csv",
        output / "strict_outer_validation_pooled_comparison.csv",
        output / "authority_and_pricefm_context.csv",
        output / "summary.json", output / "README.md",
    ]
    write_json(output / "manifest.json", {
        "status": "hash_sealed_r118_read_only_comparison",
        "source_files": [{"path": path, "sha256": sha256_file(path)} for path in sources],
        "generated_files": [{"path": str(path), "sha256": sha256_file(path)} for path in generated],
        "test_opened": False,
    })
    return summary


def main() -> int:
    result = run(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
