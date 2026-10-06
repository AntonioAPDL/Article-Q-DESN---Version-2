#!/usr/bin/env python3
"""Build the validation-only R110D BG/EE recursive failure atlas."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
from typing import Any

import numpy as np
import pandas as pd


DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
R103_TAG = "pricefm_stage_r103_recursive_quantile_20260916"
R108_TAG = "pricefm_stage_r108_recursive_driver_decomposition_20260920"
R110_TAG = "pricefm_stage_r110_direct_driver_20260921"
R110B_TAG = "pricefm_stage_r110_frozen_qdesn_replay_20260921"
R110C_TAG = "pricefm_stage_r110_driver_representation_20260921"
OUTPUT_TAG = "pricefm_stage_r110d_focus_failure_atlas_20260921"
REGIONS = ("BG", "EE", "BE")
FOLDS = (1, 2, 3)
HORIZON_BLOCKS = ((1, 24), (25, 48), (49, 72), (73, 96))
LADDER = (
    (0.00, "oracle_target_l0p00_rhs_neighbors"),
    (0.25, "oracle_target_l0p25_rhs_neighbors"),
    (0.50, "oracle_target_l0p50_rhs_neighbors"),
    (0.75, "oracle_target_l0p75_rhs_neighbors"),
    (1.00, "oracle_target_l1p00_rhs_neighbors"),
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--data-root", type=Path, default=DATA)
    value.add_argument(
        "--output-dir", type=Path, default=DATA / "authoritative" / OUTPUT_TAG
    )
    value.add_argument("--force", action="store_true")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True, default=str) + "\n")


def artifact(role: str, path: Path, **extra: Any) -> dict[str, Any]:
    path = path.resolve()
    return {
        "role": role,
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
        **extra,
    }


def require_summary(path: Path, stage: str, status: str) -> dict[str, Any]:
    value = json.loads(path.read_text())
    if (
        value.get("stage") != stage
        or value.get("status") != status
        or value.get("test_opened") is not False
        or value.get("registry_mutated") is not False
        or value.get("article_mutated") is not False
    ):
        raise RuntimeError(f"invalid {stage} summary: {path}")
    return value


def require_r108_output(summary: dict[str, Any], path: Path) -> None:
    matches = [row for row in summary.get("outputs", []) if row.get("path") == str(path)]
    if len(matches) != 1 or sha256_file(path) != matches[0].get("sha256"):
        raise RuntimeError(f"R108 output hash mismatch: {path}")


def weighted(frame: pd.DataFrame, column: str = "AQL") -> float:
    return float(np.average(frame[column], weights=frame["n_loss_atoms"]))


def one(frame: pd.DataFrame, **filters: Any) -> pd.Series:
    selected = frame
    for column, value in filters.items():
        selected = selected[selected[column].eq(value)]
    if len(selected) != 1:
        raise RuntimeError(f"expected one row for {filters}, found {len(selected)}")
    return selected.iloc[0]


def effective_oracle_lambda(aql: float, ladder_aql: list[float]) -> float:
    values = np.maximum.accumulate(np.asarray(ladder_aql, dtype=float))
    if not np.all(np.isfinite(values)) or len(values) != len(LADDER):
        raise ValueError("oracle ladder is invalid")
    lambdas = np.asarray([item[0] for item in LADDER], dtype=float)
    return float(np.interp(float(aql), values, lambdas, left=0.0, right=1.0))


def classify_region(
    region: str,
    active_count: int,
    replay_gap: float,
    neighbor_oracle_gain: float,
) -> tuple[str, str]:
    if replay_gap <= 0.10:
        return "control_hold", "freeze_completed_recursive_policy"
    if active_count == 1:
        return "target_driver_readout_exposure", "design_exposure_aligned_readout_screen"
    if neighbor_oracle_gain >= 0.10:
        return "neighbor_panel_and_target_driver", "complete_active_neighbor_drivers_then_replay"
    return "unresolved_recursive_transfer", "stop_for_additional_read_only_diagnosis"


def load_inputs(data_root: Path) -> tuple[dict[str, Any], dict[str, pd.DataFrame], list[dict[str, Any]]]:
    authoritative = data_root / "authoritative"
    roots = {
        "r108": authoritative / R108_TAG,
        "r110": data_root / "campaigns" / R110_TAG,
        "r110b": authoritative / R110B_TAG,
        "r110c": authoritative / R110C_TAG,
        "r103": data_root / "launch_prep" / R103_TAG,
    }
    summaries = {
        "r108": require_summary(
            roots["r108"] / "summary.json", "R108", "completed_recursive_driver_decomposition"
        ),
        "r110": require_summary(
            roots["r110"] / "summary.json", "R110", "completed_direct_driver_closeout"
        ),
        "r110b": require_summary(
            roots["r110b"] / "summary.json", "R110B", "completed_frozen_qdesn_replay_closeout"
        ),
        "r110c": require_summary(
            roots["r110c"] / "summary.json", "R110C", "completed_driver_representation_diagnosis"
        ),
    }
    if summaries["r110c"].get("selected_representation") != "raw_posterior_paths":
        raise RuntimeError("R110D requires the frozen raw-path R110C decision")
    source_manifest = roots["r110c"] / "source_manifest.csv"
    if sha256_file(source_manifest) != summaries["r110c"].get("source_manifest_sha256"):
        raise RuntimeError("R110C source-manifest hash mismatch")

    paths = {
        "r108_case": roots["r108"] / "pricefm_stage_r108_case_metrics.csv",
        "r108_horizon": roots["r108"] / "pricefm_stage_r108_horizon_metrics.csv",
        "r110_case": roots["r110"] / "pricefm_stage_r110_driver_case_metrics.csv",
        "r110_horizon": roots["r110"] / "pricefm_stage_r110_driver_horizon_metrics.csv",
        "r110b_case": roots["r110b"] / "pricefm_stage_r110_replay_case_metrics.csv",
        "r110b_horizon": roots["r110b"] / "pricefm_stage_r110_replay_horizon_metrics.csv",
        "r110c_selection": roots["r110c"] / "pricefm_stage_r110_representation_selection.csv",
    }
    require_r108_output(summaries["r108"], paths["r108_case"].resolve())
    require_r108_output(summaries["r108"], paths["r108_horizon"].resolve())
    frames = {name: pd.read_csv(path) for name, path in paths.items()}
    evidence = [artifact(f"{name}_input", path) for name, path in paths.items()]
    evidence.extend(artifact(f"{name}_summary", roots[name] / "summary.json") for name in summaries)
    evidence.append(artifact("r110c_source_manifest", source_manifest))
    return {"roots": roots, "summaries": summaries}, frames, evidence


def build_case_atlas(
    metadata: dict[str, Any], frames: dict[str, pd.DataFrame], evidence: list[dict[str, Any]]
) -> pd.DataFrame:
    rows: list[dict[str, Any]] = []
    roots = metadata["roots"]
    for region in REGIONS:
        for fold in FOLDS:
            config_path = roots["r103"] / "cases" / f"r103_{region.lower()}_f{fold}.json"
            config = json.loads(config_path.read_text())
            if config.get("region") != region or int(config.get("fold")) != fold:
                raise RuntimeError(f"R103 identity mismatch: {config_path}")
            evidence.append(artifact("r103_case_contract", config_path, region=region, fold=fold))
            active = [str(value) for value in config["active_regions"]]
            reference = one(frames["r108_case"], region=region, fold=fold, policy="r97_direct_reference")
            self_row = one(frames["r108_case"], region=region, fold=fold, policy="self_rhs_neighbors")
            exact_target = one(
                frames["r108_case"], region=region, fold=fold,
                policy="oracle_target_l0p00_rhs_neighbors",
            )
            exact_all = one(frames["r108_case"], region=region, fold=fold, policy="oracle_all_active")
            pf_target = one(
                frames["r108_case"], region=region, fold=fold,
                policy="pricefm_median_target_rhs_neighbors",
            )
            pf_all = one(
                frames["r108_case"], region=region, fold=fold,
                policy="pricefm_median_all_active",
            )
            pf_quantile = one(
                frames["r108_case"], region=region, fold=fold,
                policy="pricefm_quantile_paths_all_active",
            )
            driver = one(frames["r110_case"], region=region, fold=fold)
            replay = one(frames["r110b_case"], region=region, fold=fold)
            ladder = [
                float(one(frames["r108_case"], region=region, fold=fold, policy=policy).AQL)
                for _, policy in LADDER
            ]
            rows.append({
                "region": region,
                "fold": fold,
                "family": replay.family,
                "active_regions": "|".join(active),
                "active_region_count": len(active),
                "n_loss_atoms": int(replay.n_loss_atoms),
                "r97_direct_AQL": float(reference.AQL),
                "self_recursive_AQL": float(self_row.AQL),
                "exact_target_rhs_neighbors_AQL": float(exact_target.AQL),
                "exact_all_active_AQL": float(exact_all.AQL),
                "pricefm_median_target_rhs_neighbors_AQL": float(pf_target.AQL),
                "pricefm_median_all_active_AQL": float(pf_all.AQL),
                "pricefm_quantile_all_active_AQL": float(pf_quantile.AQL),
                "r110_direct_driver_AQL": float(driver.AQL),
                "r110_qdesn_replay_AQL": float(replay.AQL),
                "r110_replay_gap_vs_r97": float(replay.AQL / reference.AQL - 1.0),
                "r110_propagation_change_vs_driver": float(replay.AQL / driver.AQL - 1.0),
                "exact_neighbor_gain": float(1.0 - exact_all.AQL / exact_target.AQL),
                "pricefm_neighbor_gain": float(1.0 - pf_all.AQL / pf_target.AQL),
                "r110_effective_oracle_lambda": effective_oracle_lambda(float(replay.AQL), ladder),
                "test_opened": False,
            })
    frame = pd.DataFrame(rows)
    if len(frame) != 9 or frame.duplicated(["region", "fold"]).any():
        raise RuntimeError("R110D case atlas is incomplete")
    return frame


def build_region_summary(cases: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for region, frame in cases.groupby("region", sort=True):
        weights = frame.n_loss_atoms
        get = lambda column: float(np.average(frame[column], weights=weights))
        active_count = int(frame.active_region_count.iloc[0])
        replay_gap = get("r110_replay_gap_vs_r97")
        neighbor_gain = get("exact_neighbor_gain")
        mechanism, action = classify_region(region, active_count, replay_gap, neighbor_gain)
        rows.append({
            "region": region,
            "folds": int(frame.fold.nunique()),
            "active_regions": frame.active_regions.iloc[0],
            "active_region_count": active_count,
            "r97_direct_AQL": get("r97_direct_AQL"),
            "self_recursive_AQL": get("self_recursive_AQL"),
            "r110_direct_driver_AQL": get("r110_direct_driver_AQL"),
            "r110_qdesn_replay_AQL": get("r110_qdesn_replay_AQL"),
            "r110_replay_gap_vs_r97": replay_gap,
            "r110_propagation_change_vs_driver": get("r110_propagation_change_vs_driver"),
            "exact_neighbor_gain": neighbor_gain,
            "pricefm_neighbor_gain": get("pricefm_neighbor_gain"),
            "r110_effective_oracle_lambda": get("r110_effective_oracle_lambda"),
            "mechanism_queue": mechanism,
            "recommended_action": action,
        })
    return pd.DataFrame(rows).sort_values("region")


def block_mean(frame: pd.DataFrame, region: str, fold: int, start: int, stop: int, **filters: Any) -> float:
    selected = frame[frame.region.eq(region) & frame.fold.eq(fold)]
    for column, value in filters.items():
        selected = selected[selected[column].eq(value)]
    selected = selected[selected.horizon.between(start, stop)]
    if len(selected) != stop - start + 1:
        raise RuntimeError(f"incomplete horizon block: {region} fold {fold} {start}-{stop} {filters}")
    return float(selected.AQL.mean())


def build_horizon_atlas(frames: dict[str, pd.DataFrame]) -> pd.DataFrame:
    rows = []
    for region in REGIONS:
        for fold in FOLDS:
            for start, stop in HORIZON_BLOCKS:
                values = {
                    "r97_direct_AQL": block_mean(
                        frames["r108_horizon"], region, fold, start, stop,
                        policy="r97_direct_reference",
                    ),
                    "self_recursive_AQL": block_mean(
                        frames["r108_horizon"], region, fold, start, stop,
                        policy="self_rhs_neighbors",
                    ),
                    "exact_target_rhs_neighbors_AQL": block_mean(
                        frames["r108_horizon"], region, fold, start, stop,
                        policy="oracle_target_l0p00_rhs_neighbors",
                    ),
                    "exact_all_active_AQL": block_mean(
                        frames["r108_horizon"], region, fold, start, stop,
                        policy="oracle_all_active",
                    ),
                    "pricefm_quantile_all_active_AQL": block_mean(
                        frames["r108_horizon"], region, fold, start, stop,
                        policy="pricefm_quantile_paths_all_active",
                    ),
                    "r110_direct_driver_AQL": block_mean(
                        frames["r110_horizon"], region, fold, start, stop,
                    ),
                    "r110_qdesn_replay_AQL": block_mean(
                        frames["r110b_horizon"], region, fold, start, stop,
                    ),
                }
                rows.append({
                    "region": region,
                    "fold": fold,
                    "horizon_block": f"{start}-{stop}",
                    **values,
                    "replay_gap_vs_r97": values["r110_qdesn_replay_AQL"] / values["r97_direct_AQL"] - 1.0,
                    "neighbor_oracle_gain": 1.0 - values["exact_all_active_AQL"] / values["exact_target_rhs_neighbors_AQL"],
                    "propagation_change_vs_driver": values["r110_qdesn_replay_AQL"] / values["r110_direct_driver_AQL"] - 1.0,
                })
    return pd.DataFrame(rows)


def build_action_queue(region: pd.DataFrame) -> pd.DataFrame:
    by_region = region.set_index("region")
    return pd.DataFrame([
        {
            "priority": 0,
            "target": "EE",
            "action": "complete_active_neighbor_direct_drivers",
            "regions_to_fit": "FI|LV",
            "reuse": "EE_R110_target_driver_and_frozen_R103_EE_readout",
            "selection": "fold1_training_inner_only_one_policy_per_region",
            "evaluation": "outer_validation_then_frozen_EE_all_active_replay",
            "authorized": bool(by_region.loc["EE", "exact_neighbor_gain"] >= 0.10),
        },
        {
            "priority": 1,
            "target": "BG",
            "action": "design_exposure_aligned_readout_screen",
            "regions_to_fit": "BG",
            "reuse": "R110_target_paths_and_frozen_BG_reservoir_geometry",
            "selection": "training_only_cross_fitted_recursive_states",
            "evaluation": "outer_validation_after_readout_contract_tests",
            "authorized": False,
        },
        {
            "priority": 2,
            "target": "BE",
            "action": "freeze_control_no_new_fit",
            "regions_to_fit": "",
            "reuse": "completed_R110_raw_path_replay",
            "selection": "none",
            "evaluation": "hold",
            "authorized": False,
        },
    ])


def run(args: argparse.Namespace) -> dict[str, Any]:
    data_root = args.data_root.resolve()
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        summary_path = output / "summary.json"
        if summary_path.is_file():
            return json.loads(summary_path.read_text())
        raise FileExistsError(output)
    metadata, frames, evidence = load_inputs(data_root)
    cases = build_case_atlas(metadata, frames, evidence)
    region = build_region_summary(cases)
    horizon = build_horizon_atlas(frames)
    actions = build_action_queue(region)
    by_region = region.set_index("region")
    gates = pd.DataFrame([
        {"gate": "r110c_raw_paths_remain_selected", "passed": True, "observed": 1.0},
        {"gate": "be_control_within_10pct_of_r97", "passed": by_region.loc["BE", "r110_replay_gap_vs_r97"] <= 0.10, "observed": by_region.loc["BE", "r110_replay_gap_vs_r97"]},
        {"gate": "bg_is_target_only", "passed": int(by_region.loc["BG", "active_region_count"]) == 1, "observed": by_region.loc["BG", "active_region_count"]},
        {"gate": "bg_requires_exposure_readout_design", "passed": by_region.loc["BG", "r110_replay_gap_vs_r97"] > 0.10, "observed": by_region.loc["BG", "r110_replay_gap_vs_r97"]},
        {"gate": "ee_neighbor_oracle_gain_at_least_10pct", "passed": by_region.loc["EE", "exact_neighbor_gain"] >= 0.10, "observed": by_region.loc["EE", "exact_neighbor_gain"]},
        {"gate": "ee_neighbors_identified_as_fi_lv", "passed": by_region.loc["EE", "active_regions"] == "EE|FI|LV", "observed": float(by_region.loc["EE", "active_region_count"])},
    ])
    ee_authorized = bool(gates.passed.all()) and bool(actions.iloc[0].authorized)

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        cases.to_csv(temporary / "pricefm_stage_r110d_focus_case_atlas.csv", index=False)
        horizon.to_csv(temporary / "pricefm_stage_r110d_focus_horizon_atlas.csv", index=False)
        region.to_csv(temporary / "pricefm_stage_r110d_region_mechanism_summary.csv", index=False)
        actions.to_csv(temporary / "pricefm_stage_r110d_action_queue.csv", index=False)
        gates.to_csv(temporary / "pricefm_stage_r110d_gates.csv", index=False)
        evidence.append(artifact("executed_source", Path(__file__)))
        pd.DataFrame(evidence).drop_duplicates(["path", "sha256"]).sort_values(
            ["role", "path"]
        ).to_csv(temporary / "source_manifest.csv", index=False, quoting=csv.QUOTE_MINIMAL)
        report = [
            "# PriceFM Stage-R110D focus failure atlas",
            "",
            "This stage reads validation-only R108--R110C artifacts and performs no fitting.",
            "",
            "## Region mechanisms",
            "",
            region.to_markdown(index=False),
            "",
            "## Action queue",
            "",
            actions.to_markdown(index=False),
            "",
            "## Decision",
            "",
            f"- EE FI/LV direct-driver completion authorized: `{ee_authorized}`.",
            "- BG exposure-aligned readout work remains design/test only.",
            "- BE remains frozen as the control.",
            "- All-region fitting, test, registry, article, joint, and MCMC work remain blocked.",
        ]
        (temporary / "pricefm_stage_r110d_focus_failure_atlas.md").write_text("\n".join(report) + "\n")
        summary = {
            "stage": "R110D",
            "status": "completed_focus_failure_atlas",
            "cases_complete": 9,
            "regions": list(REGIONS),
            "ee_neighbor_driver_completion_authorized": ee_authorized,
            "bg_exposure_readout_launch_authorized": False,
            "broad_all_region_launch_authorized": False,
            "next_stage": "R111A_EE_FI_LV_direct_driver_completion" if ee_authorized else "stop_unresolved",
            "model_fit_started": False,
            "test_opened": False,
            "registry_mutated": False,
            "article_mutated": False,
        }
        write_json(temporary / "summary.json", summary)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
        return summary
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main() -> None:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
