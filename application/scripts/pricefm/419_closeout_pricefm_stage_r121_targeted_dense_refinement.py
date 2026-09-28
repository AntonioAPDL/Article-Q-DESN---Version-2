#!/usr/bin/env python3
"""Close out a completed PriceFM R121 frozen outer evaluation."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
from typing import Any

import numpy as np
import pandas as pd

from pricefm_common import sha256_file, write_json
from pricefm_r121_engine import TAG


DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
QUANTILES = np.asarray((.10, .25, .45, .50, .55, .75, .90))


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--prep-dir", type=Path); value.add_argument("--campaign-root", type=Path)
    return value


def _pinball(truth: np.ndarray, prediction: np.ndarray) -> np.ndarray:
    # Return mean quantile/lead loss per origin. Predictions are q x origin x lead.
    error = truth[None, :, :] - prediction
    loss = np.maximum(QUANTILES[:, None, None] * error, (QUANTILES[:, None, None] - 1) * error)
    return loss.mean(axis=(0, 2))


def _circular_interval(difference: np.ndarray, seed: int = 2026092702, replicates: int = 2000) -> dict[str, float]:
    values = np.asarray(difference, dtype=float); n = len(values); block = max(2, round(n ** (1 / 3)))
    rng = np.random.default_rng(seed); means = np.empty(replicates)
    blocks = int(np.ceil(n / block))
    for replicate in range(replicates):
        starts = rng.integers(0, n, size=blocks)
        indices = np.concatenate([(start + np.arange(block)) % n for start in starts])[:n]
        means[replicate] = float(np.mean(values[indices]))
    return {"mean_difference": float(np.mean(values)), "lower_95": float(np.quantile(means, .025)),
            "upper_95": float(np.quantile(means, .975)), "replicates": replicates,
            "block_length": block, "seed": seed}


def run(args: argparse.Namespace) -> dict[str, Any]:
    artifact = args.artifact_repo.resolve(); data = artifact / "application/data_local/pricefm"
    prep = (args.prep_dir or data / "launch_prep" / TAG).resolve()
    campaign = (args.campaign_root or data / "campaigns" / TAG).resolve()
    frozen = json.loads((campaign / "frozen_choice.json").read_text())
    metrics = pd.read_csv(campaign / "outer/all_metrics.csv")
    primary = metrics[metrics.operator.eq("mean_feature")].sort_values("fold", kind="mergesort")
    if set(primary.fold.astype(int)) != {1, 2, 3}:
        raise RuntimeError("R121 closeout requires all three frozen outer folds")
    ledger = pd.read_csv(prep / "comparator_ledger.csv")
    comparisons, intervals = [], []
    reference_root = data / "authoritative/pricefm_stage_r108_recursive_driver_decomposition_20260920/cases/region=BG"
    for fold in (1, 2, 3):
        with np.load(campaign / f"outer/fold={fold}/predictions.npz") as current:
            anchors = np.asarray(current["anchors"], dtype=str); truth = np.asarray(current["truth"], dtype=float)
            candidate = np.transpose(np.asarray(current["mean_feature"], dtype=float), (2, 0, 1))
        with np.load(reference_root / f"fold={fold}/validation_predictions.npz") as reference:
            names = [str(value) for value in reference["policies"]]
            if not np.array_equal(anchors, np.asarray(reference["anchors"], dtype=str)):
                raise RuntimeError(f"R121 comparator row identity mismatch in Fold {fold}")
            if not np.allclose(truth, np.asarray(reference["truth_scaled"], dtype=float), rtol=0, atol=2e-6):
                raise RuntimeError(f"R121 comparator truth mismatch in Fold {fold}")
            surfaces = np.asarray(reference["predictions_scaled"], dtype=float)
            references = {"r97": surfaces[names.index("r97_direct_reference")],
                          "pricefm": surfaces[names.index("pricefm_quantile_paths_all_active")]}
        candidate_loss = _pinball(truth, candidate)
        for method, prediction in references.items():
            reference_loss = _pinball(truth, prediction)
            interval = _circular_interval(candidate_loss - reference_loss, seed=2026092702 + fold)
            intervals.append({"fold": fold, "comparator": method, **interval})
            scalar = ledger[(ledger.method.eq(method)) & (ledger.fold.eq(fold))]
            comparisons.append({"fold": fold, "comparator": method,
                "r121_AQL": float(primary[primary.fold.eq(fold)].iloc[0].AQL),
                "comparator_AQL": float(scalar.iloc[0].AQL),
                "difference": float(primary[primary.fold.eq(fold)].iloc[0].AQL - scalar.iloc[0].AQL),
                "row_identity_verified": True})
    comparison = pd.DataFrame(comparisons); uncertainty = pd.DataFrame(intervals)
    prospective = primary[primary.fold.isin((2, 3))]
    r120 = pd.read_csv(Path(json.loads((prep / "launch_control.json").read_text())["r120_campaign"]) / "stage_f/frozen_choice_metrics.csv")
    r120_prospective = float(r120[r120.fold.isin((2, 3))].AQL.mean())
    r121_value = float(prospective.AQL.mean())
    r97 = float(ledger[(ledger.method.eq("r97")) & (ledger.fold.isin((2, 3)))].AQL.mean())
    pricefm = float(ledger[(ledger.method.eq("pricefm")) & (ledger.fold.isin((2, 3)))].AQL.mean())
    if r121_value < min(r120_prospective, r97, pricefm): classification = "beats_r120_r97_and_pricefm"
    elif r121_value < r120_prospective and sum(r121_value < value for value in (r97, pricefm)) == 1: classification = "beats_r120_and_one_reference"
    elif r121_value < r120_prospective: classification = "beats_r120_only"
    elif abs(r121_value / r120_prospective - 1) <= .01: classification = "practically_equivalent_to_r120"
    else: classification = "worse_or_numerically_invalid"
    root = campaign / "closeout"; root.mkdir(parents=True, exist_ok=True)
    comparison.to_csv(root / "matched_comparisons.csv", index=False); uncertainty.to_csv(root / "paired_block_bootstrap.csv", index=False)
    primary.to_csv(root / "frozen_outer_metrics.csv", index=False)
    storage = {"campaign_bytes": sum(path.stat().st_size for path in campaign.rglob("*") if path.is_file()),
               "free_disk_gib": shutil.disk_usage(campaign).free / 2**30}
    source_hashes = {path.name: sha256_file(path) for path in (prep / "summary.json", prep / "source_manifest.csv",
        campaign / "frozen_choice.json", campaign / "outer/all_metrics.csv")}
    result = {"stage": "R121", "status": "completed_r121_not_promoted", "classification": classification,
        "frozen_choice": frozen, "fold23_mean_AQL": r121_value, "r120_fold23_mean_AQL": r120_prospective,
        "r97_fold23_mean_AQL": r97, "pricefm_fold23_mean_AQL": pricefm, "storage": storage,
        "source_hashes": source_hashes, "test_opened": False, "registry_mutated": False,
        "article_mutated": False, "joint_model_fitted": False, "mcmc_fitted": False, "exal_fitted": False}
    write_json(root / "summary.json", result); write_json(campaign / "campaign_terminal.json", result)
    return result


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True)); return 0


if __name__ == "__main__":
    raise SystemExit(main())
