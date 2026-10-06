#!/usr/bin/env python3
"""Recover and audit the completed PriceFM R116 closeout without refitting."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from typing import Any

import numpy as np
import pandas as pd

from pricefm_common import sha256_file, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
DEFAULT_CAMPAIGN = DATA / "campaigns/pricefm_stage_r113_r116_calendar_index_recovery_20260923"
DEFAULT_R103 = DATA / "campaigns/pricefm_stage_r103_recursive_quantile_20260916"
DEFAULT_R111B = DATA / "campaigns/pricefm_stage_r111b_bg_exposure_readout_20260922"
DEFAULT_OUTPUT = DATA / "authoritative/pricefm_stage_r116_transfer_closeout_20260924"
QUANTILES = (0.1, 0.25, 0.45, 0.5, 0.55, 0.75, 0.9)


def canonical_hash(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(payload.encode()).hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def tau_label(tau: float) -> str:
    return str(float(tau)).replace(".", "p")


def source_record(path: Path, role: str) -> dict[str, Any]:
    path = path.resolve()
    if not path.is_file():
        raise FileNotFoundError(path)
    return {
        "role": role,
        "path": str(path),
        "bytes": int(path.stat().st_size),
        "sha256": sha256_file(path),
    }


def add_source(records: dict[str, dict[str, Any]], path: Path, role: str) -> None:
    record = source_record(path, role)
    existing = records.get(record["path"])
    if existing is None:
        records[record["path"]] = record
    elif role not in existing["role"].split("|"):
        existing["role"] += f"|{role}"


def verify_parent_provenance(
    campaign: Path, records: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    contract_path = campaign / "campaign_contract.json"
    manifest_path = campaign / "source_manifest.csv"
    contract = read_json(contract_path)
    expected_contract_hash = contract.get("campaign_contract_sha256")
    observed_contract_hash = canonical_hash({
        key: value for key, value in contract.items()
        if key != "campaign_contract_sha256"
    })
    if observed_contract_hash != expected_contract_hash:
        raise RuntimeError("parent campaign contract hash mismatch")
    observed_manifest_hash = sha256_file(manifest_path)
    if observed_manifest_hash != contract.get("source_manifest_sha256"):
        raise RuntimeError("parent source manifest hash mismatch")
    add_source(records, contract_path, "parent_campaign_contract")
    add_source(records, manifest_path, "parent_source_manifest")
    manifest = pd.read_csv(manifest_path)
    required = {"path", "bytes", "sha256"}
    if not required.issubset(manifest.columns):
        raise RuntimeError(f"parent source manifest lacks {sorted(required - set(manifest.columns))}")
    historical_code_root = Path(contract["code_root"]).resolve()
    historical_head = str(contract["head"])
    for row in manifest.itertuples(index=False):
        path = Path(row.path).resolve()
        current_matches = (
            path.is_file()
            and path.stat().st_size == int(row.bytes)
            and sha256_file(path) == str(row.sha256)
        )
        if current_matches:
            add_source(records, path, "parent_frozen_source")
            continue
        try:
            relative = path.relative_to(historical_code_root)
        except ValueError as exc:
            if not path.is_file():
                raise FileNotFoundError(f"parent frozen source is missing: {path}") from exc
            raise RuntimeError(f"parent frozen source changed: {path}") from exc
        try:
            payload = subprocess.check_output([
                "git", "-C", str(historical_code_root), "show",
                f"{historical_head}:{relative.as_posix()}",
            ])
        except subprocess.CalledProcessError as exc:
            raise RuntimeError(
                f"cannot resolve changed tracked source at frozen head: {path}"
            ) from exc
        observed_hash = hashlib.sha256(payload).hexdigest()
        if len(payload) != int(row.bytes) or observed_hash != str(row.sha256):
            raise RuntimeError(
                f"frozen Git blob does not match parent source manifest: {path}"
            )
        records[f"git:{historical_head}:{relative.as_posix()}"] = {
            "role": "parent_frozen_git_source",
            "path": f"git:{historical_head}:{relative.as_posix()}",
            "bytes": len(payload),
            "sha256": observed_hash,
        }
    return contract


def completed_terminal(path: Path, expected_status: str) -> bool:
    if not path.is_file():
        return False
    terminal = read_json(path)
    return terminal.get("status") == expected_status and terminal.get("test_opened") is not True


def manifest_completion(
    path: Path, expected_status: str, records: dict[str, dict[str, Any]],
) -> tuple[int, int]:
    add_source(records, path, "fit_manifest")
    manifest = pd.read_csv(path)
    completed = 0
    failed = 0
    for row in manifest.itertuples(index=False):
        terminal = Path(row.output_dir) / "terminal.json"
        add_source(records, terminal, "fit_terminal")
        if completed_terminal(terminal, expected_status):
            completed += int(getattr(row, "fit_cells", 1))
        else:
            failed += int(getattr(row, "fit_cells", 1))
    return completed, failed


def completion_audit(
    campaign: Path, contract: dict[str, Any], records: dict[str, dict[str, Any]],
) -> pd.DataFrame:
    normal_terminals = sorted(campaign.glob("runs/r114_normal_driver/region=*/inner=*/terminal.json"))
    quantile_terminals = sorted(campaign.glob("runs/r114_fit/family=*/inner=*/tau=*/terminal.json"))
    for path in normal_terminals + quantile_terminals:
        add_source(records, path, "r114_fit_terminal")
    normal_complete = sum(completed_terminal(path, "completed_r114_normal_driver") for path in normal_terminals)
    quantile_complete = sum(completed_terminal(path, "completed_r114_quantile_atom") for path in quantile_terminals)

    candidate_path = campaign / "r115_candidate_bank.csv"
    add_source(records, candidate_path, "r115_candidate_bank")
    candidate_count = len(pd.read_csv(candidate_path))
    ridge_terminals = sorted(campaign.glob("runs/r115_ridge/candidate=*/terminal.json"))
    for path in ridge_terminals:
        add_source(records, path, "r115_ridge_terminal")
    ridge_tasks_complete = sum(completed_terminal(path, "completed_r115_ridge_candidate") for path in ridge_terminals)
    ridge_cells_complete = ridge_tasks_complete * 6

    rhs_complete, rhs_failed = manifest_completion(
        campaign / "r115_rhs_manifest.csv", "completed_r115_rhs_cell", records,
    )
    family_complete, family_failed = manifest_completion(
        campaign / "r116_family_fit_manifest.csv", "completed_r116_quantile_family_fit", records,
    )
    outer_complete, outer_failed = manifest_completion(
        campaign / "r116_outer_fit_manifest.csv", "completed_r116_quantile_family_fit", records,
    )

    status_failures = 0
    for path in sorted(campaign.glob("*_status.csv")):
        add_source(records, path, "scheduler_status")
        frame = pd.read_csv(path)
        if "returncode" in frame.columns:
            status_failures += int(frame.returncode.fillna(1).ne(0).sum())

    expected = {
        "R114_foundation": 51,
        "R115_ridge": int(contract["r115_ridge_fit_cells"]),
        "R115_RHS": int(contract["r115_rhs_maximum_fit_cells"]),
        "R116_inner_family": int(contract["r116_family_maximum_fit_cells"]),
        "R116_outer_transfer": int(contract["r116_factorial_maximum_fit_cells"]),
    }
    completed = {
        "R114_foundation": normal_complete + quantile_complete,
        "R115_ridge": ridge_cells_complete,
        "R115_RHS": rhs_complete,
        "R116_inner_family": family_complete,
        "R116_outer_transfer": outer_complete,
    }
    explicit_failed = {
        "R114_foundation": max(0, expected["R114_foundation"] - completed["R114_foundation"]),
        "R115_ridge": max(0, expected["R115_ridge"] - completed["R115_ridge"]),
        "R115_RHS": rhs_failed,
        "R116_inner_family": family_failed,
        "R116_outer_transfer": outer_failed,
    }
    rows = []
    for component in expected:
        rows.append({
            "component": component,
            "expected_fit_cells": expected[component],
            "completed_fit_cells": completed[component],
            "remaining_fit_cells": expected[component] - completed[component],
            "failed_fit_cells": explicit_failed[component],
            "complete": completed[component] == expected[component] and explicit_failed[component] == 0,
        })
    frame = pd.DataFrame(rows)
    if candidate_count != int(contract["r115_ridge_candidates"]):
        raise RuntimeError("R115 candidate-bank count differs from the frozen contract")
    if status_failures:
        raise RuntimeError(f"scheduler status files contain {status_failures} nonzero return codes")
    if not frame.complete.all():
        raise RuntimeError("completed campaign has missing or failed fit cells")
    return frame


def weighted_pooled(metrics: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for cell, frame in metrics.groupby("cell", sort=True):
        weights = frame.n_loss_atoms.to_numpy(dtype=float)
        rows.append({
            "cell": cell,
            "AQL": float(np.average(frame.AQL, weights=weights)),
            "AQCR": float(np.average(frame.AQCR, weights=weights)),
            "coverage_10_90": float(np.average(frame.coverage_10_90, weights=weights)),
            "width_10_90": float(np.average(frame.width_10_90, weights=weights)),
            "n_loss_atoms": int(frame.n_loss_atoms.sum()),
        })
    return pd.DataFrame(rows)


def transfer_gates(metrics: pd.DataFrame, horizons: pd.DataFrame) -> pd.DataFrame:
    pooled = weighted_pooled(metrics).set_index("cell")
    a = float(pooled.loc["A", "AQL"])
    d = float(pooled.loc["D", "AQL"])
    fold_wins = sum(
        float(metrics.loc[(metrics.fold == fold) & (metrics.cell == "D"), "AQL"].iloc[0])
        < float(metrics.loc[(metrics.fold == fold) & (metrics.cell == "A"), "AQL"].iloc[0])
        for fold in (1, 2, 3)
    )
    late = horizons[horizons.horizon_block == "73-96"]
    late_a_rows = late[late.cell == "A"]
    late_d_rows = late[late.cell == "D"]
    late_a = float(np.average(late_a_rows.AQL, weights=late_a_rows.n_loss_atoms))
    late_d = float(np.average(late_d_rows.AQL, weights=late_d_rows.n_loss_atoms))
    coverage_a = float(pooled.loc["A", "coverage_10_90"])
    coverage_d = float(pooled.loc["D", "coverage_10_90"])
    width_a = float(pooled.loc["A", "width_10_90"])
    width_d = float(pooled.loc["D", "width_10_90"])
    return pd.DataFrame([
        {"gate": "pooled_D_beats_A", "passed": d < a, "value": d - a, "threshold": 0.0},
        {"gate": "D_beats_A_in_two_folds", "passed": fold_wins >= 2, "value": fold_wins, "threshold": 2},
        {"gate": "late_73_96_no_more_than_2pct_worse", "passed": late_d <= 1.02 * late_a, "value": late_d / late_a - 1, "threshold": 0.02},
        {"gate": "coverage_error_not_worse_by_2pp", "passed": abs(coverage_d - 0.8) <= abs(coverage_a - 0.8) + 0.02, "value": abs(coverage_d - 0.8) - abs(coverage_a - 0.8), "threshold": 0.02},
        {"gate": "interval_width_not_collapsed", "passed": width_d >= 0.8 * width_a, "value": width_d / width_a, "threshold": 0.8},
    ])


def verify_closeout_tables(
    campaign: Path, records: dict[str, dict[str, Any]],
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    metric_paths = [campaign / f"runs/r116_outer_score/fold={fold}/metrics.csv" for fold in (1, 2, 3)]
    horizon_paths = [campaign / f"runs/r116_outer_score/fold={fold}/horizon_metrics.csv" for fold in (1, 2, 3)]
    for path in metric_paths + horizon_paths:
        add_source(records, path, "r116_outer_score")
    metrics = pd.concat([pd.read_csv(path) for path in metric_paths], ignore_index=True)
    horizons = pd.concat([pd.read_csv(path) for path in horizon_paths], ignore_index=True)
    pooled = weighted_pooled(metrics)
    gates = transfer_gates(metrics, horizons)
    frozen_paths = [
        campaign / "r116_factorial_metrics.csv",
        campaign / "r116_factorial_horizon_metrics.csv",
        campaign / "r116_factorial_pooled_metrics.csv",
        campaign / "r116_transfer_gates.csv",
    ]
    for path in frozen_paths:
        add_source(records, path, "parent_closeout_partial")
    pd.testing.assert_frame_equal(
        metrics.reset_index(drop=True), pd.read_csv(frozen_paths[0]).reset_index(drop=True),
        check_dtype=False, rtol=1e-12, atol=1e-12,
    )
    pd.testing.assert_frame_equal(
        horizons.reset_index(drop=True), pd.read_csv(frozen_paths[1]).reset_index(drop=True),
        check_dtype=False, rtol=1e-12, atol=1e-12,
    )
    pd.testing.assert_frame_equal(
        pooled.sort_values("cell").reset_index(drop=True),
        pd.read_csv(frozen_paths[2]).sort_values("cell").reset_index(drop=True),
        check_dtype=False, rtol=1e-12, atol=1e-12,
    )
    pd.testing.assert_frame_equal(
        gates.reset_index(drop=True), pd.read_csv(frozen_paths[3]).reset_index(drop=True),
        check_dtype=False, rtol=1e-12, atol=1e-12,
    )
    return metrics, horizons, pooled, gates


def array_comparison(left: np.ndarray, right: np.ndarray) -> dict[str, Any]:
    shape_match = left.shape == right.shape
    if not shape_match:
        return {
            "shape_match": False, "exact_match": False,
            "max_abs_difference": np.nan, "correlation": np.nan,
        }
    delta = np.asarray(left, dtype=float) - np.asarray(right, dtype=float)
    left_flat = np.asarray(left, dtype=float).ravel()
    right_flat = np.asarray(right, dtype=float).ravel()
    correlation = 1.0 if np.array_equal(left_flat, right_flat) else float(np.corrcoef(left_flat, right_flat)[0, 1])
    return {
        "shape_match": True,
        "exact_match": bool(np.array_equal(left, right)),
        "max_abs_difference": float(np.max(np.abs(delta))) if delta.size else 0.0,
        "correlation": correlation,
    }


def driver_axis_audit(
    campaign: Path, metrics: pd.DataFrame, records: dict[str, dict[str, Any]],
) -> tuple[pd.DataFrame, bool]:
    selected_path = campaign / "r114_selected_driver.json"
    add_source(records, selected_path, "selection_record")
    selected_family = read_json(selected_path)["family"]
    rows = []
    for fold in (1, 2, 3):
        for left, right in (("A", "B"), ("C", "D")):
            left_path = campaign / f"runs/r116_outer_score/fold={fold}/cell_{left}_validation_predictions.npz"
            right_path = campaign / f"runs/r116_outer_score/fold={fold}/cell_{right}_validation_predictions.npz"
            add_source(records, left_path, "r116_prediction_surface")
            add_source(records, right_path, "r116_prediction_surface")
            with np.load(left_path) as lhs, np.load(right_path) as rhs:
                comparison = array_comparison(lhs["prediction_scaled"], rhs["prediction_scaled"])
            left_metric = metrics[(metrics.fold == fold) & (metrics.cell == left)].iloc[0]
            right_metric = metrics[(metrics.fold == fold) & (metrics.cell == right)].iloc[0]
            metric_delta = max(
                abs(float(left_metric[column]) - float(right_metric[column]))
                for column in ("AQL", "AQCR", "coverage_10_90", "width_10_90")
            )
            rows.append({
                "fold": fold, "left_cell": left, "right_cell": right,
                "selected_driver_family": selected_family,
                **comparison, "maximum_metric_difference": metric_delta,
            })
    frame = pd.DataFrame(rows)
    identifiable = selected_family != "normal_rhs"
    if not identifiable and not (
        frame.exact_match.all() and frame.maximum_metric_difference.le(1e-12).all()
    ):
        raise RuntimeError("Normal RHS selection should make the R116 driver axis degenerate")
    return frame, identifiable


def r103_equivalence_audit(
    campaign: Path, r103: Path, records: dict[str, dict[str, Any]],
) -> pd.DataFrame:
    rows: list[dict[str, Any]] = []
    for fold in (1, 2, 3):
        current_design = campaign / f"runs/r116_outer_design/fold={fold}/current_lead/design"
        reference_design = r103 / f"cases/region=BG/fold={fold}/design"
        for name in ("X.bin", "y.bin"):
            left_path = current_design / name
            right_path = reference_design / name
            add_source(records, left_path, "r116_current_design")
            add_source(records, right_path, "r103_reference_design")
            left = np.fromfile(left_path, dtype="<f8")
            right = np.fromfile(right_path, dtype="<f8")
            rows.append({
                "fold": fold, "component": f"design_{name}", "quantile": np.nan,
                **array_comparison(left, right),
            })
        for tau in QUANTILES:
            label = tau_label(tau)
            left_path = campaign / (
                f"runs/r116_outer_fit/readout=current_lead/family=al/fold={fold}/"
                f"tau={label}/beta_mean.bin"
            )
            right_path = r103 / (
                f"cases/region=BG/fold={fold}/atoms/r103_bg_f{fold}_al_{label}/beta_mean.bin"
            )
            add_source(records, left_path, "r116_current_beta_mean")
            add_source(records, right_path, "r103_reference_beta_mean")
            rows.append({
                "fold": fold, "component": "beta_mean", "quantile": tau,
                **array_comparison(
                    np.fromfile(left_path, dtype="<f8"),
                    np.fromfile(right_path, dtype="<f8"),
                ),
            })
        left_path = campaign / f"runs/r116_outer_score/fold={fold}/cell_A_validation_predictions.npz"
        right_path = r103 / f"cases/region=BG/fold={fold}/al_validation_quantiles.npz"
        metric_path = r103 / f"cases/region=BG/fold={fold}/family_validation_metrics.csv"
        add_source(records, left_path, "r116_current_prediction")
        add_source(records, right_path, "r103_reference_prediction")
        add_source(records, metric_path, "r103_reference_metric")
        with np.load(left_path) as lhs, np.load(right_path) as rhs:
            comparison = array_comparison(lhs["prediction_scaled"], rhs["prediction_scaled"])
            anchors_equal = np.array_equal(lhs["anchors"], rhs["anchors"])
            quantiles_equal = np.array_equal(lhs["quantiles"], rhs["quantiles"])
        rows.append({
            "fold": fold, "component": "recursive_prediction_scaled", "quantile": np.nan,
            **comparison, "anchors_equal": anchors_equal, "quantiles_equal": quantiles_equal,
        })
    frame = pd.DataFrame(rows)
    design = frame[frame.component.str.startswith("design_")]
    beta = frame[frame.component == "beta_mean"]
    prediction = frame[frame.component == "recursive_prediction_scaled"]
    if not design.exact_match.all():
        raise RuntimeError("R116 current design does not reproduce R103")
    if not beta.max_abs_difference.le(1e-5).all() or not beta.correlation.ge(0.999999999).all():
        raise RuntimeError("R116 current beta means do not reproduce R103")
    if not prediction.max_abs_difference.le(2e-3).all():
        raise RuntimeError("R116 current recursive predictions materially differ from R103")
    return frame


def pooled_reference_table(
    pooled: pd.DataFrame, r103: Path, r111b: Path,
    records: dict[str, dict[str, Any]],
) -> pd.DataFrame:
    rows: list[dict[str, Any]] = []
    for cell in ("A", "D"):
        value = pooled[pooled.cell == cell].iloc[0]
        rows.append({
            "reference": f"R116_cell_{cell}", "operator_class": "fully_recursive_normal_RHS_driver",
            "AQL": float(value.AQL), "coverage_10_90": float(value.coverage_10_90),
            "width_10_90": float(value.width_10_90), "n_loss_atoms": int(value.n_loss_atoms),
        })
    r103_frames = []
    for fold in (1, 2, 3):
        path = r103 / f"cases/region=BG/fold={fold}/family_validation_metrics.csv"
        add_source(records, path, "r103_reference_metric")
        frame = pd.read_csv(path)
        r103_frames.append(frame[frame.family == "al"])
    r103_al = pd.concat(r103_frames, ignore_index=True)
    rows.append({
        "reference": "R103_AL_recursive", "operator_class": "fully_recursive_normal_RHS_driver",
        "AQL": float(np.average(r103_al.validation_AQL_original, weights=r103_al.n_loss_atoms)),
        "coverage_10_90": np.nan, "width_10_90": np.nan,
        "n_loss_atoms": int(r103_al.n_loss_atoms.sum()),
    })
    case_path = r111b / "pricefm_stage_r111b_bg_case_metrics.csv"
    refs_path = r111b / "pricefm_stage_r111b_bg_references.csv"
    summary_path = r111b / "summary.json"
    for path in (case_path, refs_path, summary_path):
        add_source(records, path, "r111b_frozen_context")
    cases = pd.read_csv(case_path)
    references = pd.read_csv(refs_path)
    cases = cases.assign(reference="r111b_exposure_aligned_readout")
    references = references.assign(reference=references.policy)
    context = pd.concat([cases, references], ignore_index=True, sort=False)
    for reference, frame in context.groupby("reference", sort=True):
        weights = frame.n_loss_atoms.to_numpy(dtype=float)
        width_column = "mean_width_10_90" if "mean_width_10_90" in frame else None
        rows.append({
            "reference": reference,
            "operator_class": {
                "r97_direct_reference": "direct_frozen_authority",
                "r111b_exposure_aligned_readout": "exposure_aligned_readout",
                "r110_direct_target_rhs_neighbors": "direct_target_recursive_neighbors",
                "self_rhs_neighbors": "fully_recursive_self_RHS_driver",
                "oracle_all_active": "oracle_driver_diagnostic",
                "pricefm_quantile_paths_all_active": "PriceFM_quantile_driver_diagnostic",
            }.get(reference, "contextual_diagnostic"),
            "AQL": float(np.average(frame.AQL, weights=weights)),
            "coverage_10_90": float(np.average(frame.coverage_10_90, weights=weights)),
            "width_10_90": (
                float(np.average(frame[width_column], weights=weights))
                if width_column is not None else np.nan
            ),
            "n_loss_atoms": int(frame.n_loss_atoms.sum()),
        })
    result = pd.DataFrame(rows).sort_values("AQL").reset_index(drop=True)
    direct = float(result.loc[result.reference == "r97_direct_reference", "AQL"].iloc[0])
    result["relative_AQL_vs_R97"] = result.AQL / direct - 1.0
    return result


def git_metadata(code_root: Path) -> dict[str, str]:
    def run(*args: str) -> str:
        return subprocess.check_output(["git", "-C", str(code_root), *args], text=True).strip()
    dirty = run("status", "--porcelain", "--untracked-files=no")
    if dirty:
        raise RuntimeError("code root must be clean before materializing the recovered closeout")
    return {
        "branch": run("branch", "--show-current"),
        "head": run("rev-parse", "HEAD"),
        "upstream": run("rev-parse", "@{upstream}"),
    }


def write_markdown(path: Path, summary: dict[str, Any], references: pd.DataFrame) -> None:
    lines = [
        "# PriceFM Stage-R116 recovered closeout", "",
        "## Decision", "",
        f"- Status: `{summary['status']}`.",
        f"- Completed fit cells: `{summary['completed_fit_cells']}/{summary['expected_fit_cells']}`.",
        f"- Transfer gates: `{summary['transfer_gates_passed']}/{summary['transfer_gates_total']}` passed.",
        f"- R117 authorized: `{str(summary['r117_preparation_authorized']).lower()}`.",
        f"- Promotion authorized: `{str(summary['promotion_authorized']).lower()}`.", "",
        "## Diagnosis", "",
        "- The R116 current design is byte-identical to R103 in all three folds.",
        "- The 21 AL beta-mean comparisons and recursive predictions reproduce R103 within the prespecified numerical tolerances.",
        "- The selected driver was Normal RHS, so A=B and C=D. This campaign identifies a readout contrast, not a driver contrast.",
        "- Cell D has a small pooled AQL gain over Cell A, but worsens coverage and collapses interval width; it is not promotable.",
        "- The large gap from R97 is attributed to the fully recursive forecast operator and future-price driver exposure, not to a failed refit.", "",
        "## Pooled comparison", "",
        "| Reference | Operator | AQL | Coverage | Width | Relative AQL vs R97 |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for row in references.itertuples(index=False):
        coverage = "NA" if pd.isna(row.coverage_10_90) else f"{row.coverage_10_90:.4f}"
        width = "NA" if pd.isna(row.width_10_90) else f"{row.width_10_90:.3f}"
        lines.append(
            f"| {row.reference} | {row.operator_class} | {row.AQL:.6f} | {coverage} | {width} | {100 * row.relative_AQL_vs_R97:+.2f}% |"
        )
    lines.extend([
        "", "## Boundary", "",
        "No fit was launched or changed. The parent campaign, registry, article, MCMC, joint models, test data, and all-region work were untouched.",
    ])
    path.write_text("\n".join(lines) + "\n")


def output_manifest(root: Path) -> pd.DataFrame:
    rows = []
    for path in sorted(item for item in root.iterdir() if item.is_file() and item.name != "output_manifest.csv"):
        rows.append({
            "path": path.name, "bytes": path.stat().st_size, "sha256": sha256_file(path),
        })
    return pd.DataFrame(rows)


def compare_existing(expected: Path, observed: Path) -> None:
    expected_files = sorted(path.name for path in expected.iterdir() if path.is_file())
    observed_files = sorted(path.name for path in observed.iterdir() if path.is_file())
    if expected_files != observed_files:
        raise RuntimeError("recovered closeout file set is not reproducible")
    for name in expected_files:
        if sha256_file(expected / name) != sha256_file(observed / name):
            raise RuntimeError(f"recovered closeout is not reproducible: {name}")


def build_closeout(
    campaign: Path, r103: Path, r111b: Path, code_root: Path, output: Path,
    *, verify_existing: bool = False,
) -> dict[str, Any]:
    campaign = campaign.resolve()
    r103 = r103.resolve()
    r111b = r111b.resolve()
    code_root = code_root.resolve()
    output = output.resolve()
    metadata = git_metadata(code_root)
    records: dict[str, dict[str, Any]] = {}
    contract = verify_parent_provenance(campaign, records)
    for name in ("r114_selected_driver.json", "r115_selected_no_bypass.json", "r116_selected_family.json"):
        add_source(records, campaign / name, "selection_record")
    script_path = Path(__file__).resolve()
    controller_path = code_root / "application/scripts/pricefm/392_orchestrate_pricefm_stage_r113_r116_campaign.py"
    add_source(records, script_path, "closeout_audit_code")
    add_source(records, controller_path, "closeout_controller_code")

    completion = completion_audit(campaign, contract, records)
    metrics, horizons, pooled, gates = verify_closeout_tables(campaign, records)
    axis, driver_identifiable = driver_axis_audit(campaign, metrics, records)
    equivalence = r103_equivalence_audit(campaign, r103, records)
    references = pooled_reference_table(pooled, r103, r111b, records)

    expected_fit_cells = int(completion.expected_fit_cells.sum())
    completed_fit_cells = int(completion.completed_fit_cells.sum())
    gates_passed = int(gates.passed.sum())
    all_gates_passed = bool(gates.passed.all())
    cell_a = pooled[pooled.cell == "A"].iloc[0]
    cell_d = pooled[pooled.cell == "D"].iloc[0]
    r97_aql = float(references.loc[references.reference == "r97_direct_reference", "AQL"].iloc[0])
    fit_equivalent = bool(
        equivalence[equivalence.component.str.startswith("design_")].exact_match.all()
        and equivalence[equivalence.component == "beta_mean"].max_abs_difference.le(1e-5).all()
        and equivalence[equivalence.component == "recursive_prediction_scaled"].max_abs_difference.le(2e-3).all()
    )
    if not fit_equivalent:
        diagnosis = "fit_reproduction_failure"
    elif float(cell_a.AQL) > r97_aql:
        diagnosis = "forecast_operator_transfer_failure"
    else:
        diagnosis = "no_material_transfer_failure_detected"
    promotion = all_gates_passed and diagnosis == "no_material_transfer_failure_detected"

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        completion.to_csv(temporary / "completion_audit.csv", index=False)
        metrics.to_csv(temporary / "r116_recomputed_factorial_metrics.csv", index=False)
        horizons.to_csv(temporary / "r116_recomputed_horizon_metrics.csv", index=False)
        pooled.to_csv(temporary / "r116_recomputed_pooled_metrics.csv", index=False)
        gates.to_csv(temporary / "r116_recomputed_transfer_gates.csv", index=False)
        axis.to_csv(temporary / "driver_axis_audit.csv", index=False)
        equivalence.to_csv(temporary / "r103_r116_fit_equivalence_audit.csv", index=False)
        references.to_csv(temporary / "operator_reference_comparison.csv", index=False)
        source_manifest = pd.DataFrame(records.values()).sort_values("path").reset_index(drop=True)
        source_manifest.to_csv(temporary / "source_manifest.csv", index=False)
        summary = {
            "stage": "R116_recovered_closeout",
            "status": f"completed_not_promotable_{diagnosis}",
            "parent_campaign_tag": contract["tag"],
            "parent_campaign_head": contract["head"],
            "closeout_code_branch": metadata["branch"],
            "closeout_code_head": metadata["head"],
            "closeout_code_upstream": metadata["upstream"],
            "expected_fit_cells": expected_fit_cells,
            "completed_fit_cells": completed_fit_cells,
            "remaining_fit_cells": expected_fit_cells - completed_fit_cells,
            "failed_fit_cells": int(completion.failed_fit_cells.sum()),
            "fit_reproduces_R103": fit_equivalent,
            "selected_driver_family": read_json(campaign / "r114_selected_driver.json")["family"],
            "driver_contrast_identifiable": driver_identifiable,
            "mechanism_interpretation": (
                "driver_and_readout_factorial" if driver_identifiable
                else "readout_only_driver_axis_degenerate"
            ),
            "root_cause_classification": diagnosis,
            "cell_A_pooled_AQL": float(cell_a.AQL),
            "cell_D_pooled_AQL": float(cell_d.AQL),
            "cell_D_minus_A": float(cell_d.AQL - cell_a.AQL),
            "cell_D_relative_AQL_change": float(cell_d.AQL / cell_a.AQL - 1.0),
            "cell_D_minus_A_coverage": float(cell_d.coverage_10_90 - cell_a.coverage_10_90),
            "cell_D_width_ratio": float(cell_d.width_10_90 / cell_a.width_10_90),
            "R97_pooled_AQL": r97_aql,
            "cell_D_relative_AQL_vs_R97": float(cell_d.AQL / r97_aql - 1.0),
            "transfer_gates_passed": gates_passed,
            "transfer_gates_total": int(len(gates)),
            "all_transfer_gates_passed": all_gates_passed,
            "promotion_authorized": promotion,
            "r117_preparation_authorized": promotion,
            "test_opened": False,
            "registry_mutated": False,
            "article_mutated": False,
            "mcmc_fitted": False,
            "joint_model_fitted": False,
            "broad_all_region_launch_authorized": False,
            "source_manifest_sha256": sha256_file(temporary / "source_manifest.csv"),
        }
        write_json(temporary / "summary.json", summary)
        write_markdown(temporary / "closeout.md", summary, references)
        output_manifest(temporary).to_csv(temporary / "output_manifest.csv", index=False)
        if output.exists():
            if not verify_existing:
                raise FileExistsError(f"refusing to overwrite existing closeout: {output}")
            compare_existing(output, temporary)
            return summary
        temporary.rename(output)
        return summary
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--campaign-root", type=Path, default=DEFAULT_CAMPAIGN)
    parser.add_argument("--r103-root", type=Path, default=DEFAULT_R103)
    parser.add_argument("--r111b-root", type=Path, default=DEFAULT_R111B)
    parser.add_argument("--code-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--verify-existing", action="store_true")
    args = parser.parse_args()
    summary = build_closeout(
        args.campaign_root, args.r103_root, args.r111b_root,
        args.code_root, args.output_root, verify_existing=args.verify_existing,
    )
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
