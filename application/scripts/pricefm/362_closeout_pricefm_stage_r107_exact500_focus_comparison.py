#!/usr/bin/env python3
"""Compare focused R106 exact-500 forecasts with frozen R104 forecasts."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import shutil
import tempfile
from typing import Any, Iterable

import numpy as np
import pandas as pd

from pricefm_common import sha256_file, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
CAMPAIGN = DATA / "campaigns/pricefm_stage_r106_exact500_recursive_quantile_20260918"
R104 = DATA / "authoritative/pricefm_stage_r104_forecast_operator_diagnosis_20260918"
OUTPUT = DATA / "authoritative/pricefm_stage_r107_exact500_focus_comparison_20260918"
FOCUS_CASES = (
    ("r106_bg_f1", "BG", 1, "al", "quantile_curve_self"),
    ("r106_be_f1", "BE", 1, "exal", "quantile_curve_self_rhs_neighbors"),
    ("r106_be_f1", "BE", 1, "exal", "quantile_curve_self_ridge_neighbors"),
    ("r106_be_f2", "BE", 2, "exal", "quantile_curve_self_rhs_neighbors"),
    ("r106_be_f2", "BE", 2, "exal", "quantile_curve_self_ridge_neighbors"),
    ("r106_be_f3", "BE", 3, "exal", "quantile_curve_self_rhs_neighbors"),
    ("r106_be_f3", "BE", 3, "exal", "quantile_curve_self_ridge_neighbors"),
)
FOCUS_CASE_IDS = tuple(dict.fromkeys(value[0] for value in FOCUS_CASES))
METRIC_COLUMNS = (
    "AQL",
    "AQCR",
    "coverage_10_90",
    "mean_width_10_90",
    "mean_width_25_75",
    "median_MAE",
    "median_RMSE",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--campaign-root", type=Path, default=CAMPAIGN)
    value.add_argument("--r104-root", type=Path, default=R104)
    value.add_argument("--output-dir", type=Path, default=OUTPUT)
    value.add_argument("--force", action="store_true")
    return value


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def artifact_record(role: str, path: Path, **identity: Any) -> dict[str, Any]:
    return {
        "role": role,
        **identity,
        "path": str(path.resolve()),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def case_dir(campaign: Path, region: str, fold: int) -> Path:
    return campaign / "cases" / f"region={region}" / f"fold={fold}"


def verify_case(campaign: Path, case_id: str, region: str, fold: int) -> dict[str, Any]:
    path = case_dir(campaign, region, fold)
    terminal_path = path / "terminal.json"
    if not terminal_path.is_file():
        raise RuntimeError(f"R107 focus case is incomplete: {case_id}")
    terminal = read_json(terminal_path)
    if (
        terminal.get("status") != "completed_recursive_quantile_case"
        or terminal.get("case_id") != case_id
        or terminal.get("test_opened") is not False
        or int(terminal.get("atoms_complete", -1)) != 14
        or terminal.get("all_atoms_exact_500") is not True
        or int(terminal.get("posterior_paths", -1)) != 500
    ):
        raise RuntimeError(f"R107 focus case terminal is invalid: {case_id}")
    for record in terminal["artifacts"]:
        artifact = Path(record["path"])
        if not artifact.is_file() or sha256_file(artifact) != record["sha256"]:
            raise RuntimeError(f"R107 focus artifact changed: {artifact}")
    metrics = pd.read_csv(path / "family_validation_metrics.csv")
    if metrics.test_opened.astype(bool).any() or not metrics.all_atoms_exact_500.astype(bool).all():
        raise RuntimeError(f"R107 focus metrics violate the firewall: {case_id}")
    return terminal


def load_exact500_metrics(campaign: Path) -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    frames = []
    evidence = []
    unique_cases = {(row[0], row[1], row[2]) for row in FOCUS_CASES}
    for case_id, region, fold in sorted(unique_cases):
        verify_case(campaign, case_id, region, fold)
        path = case_dir(campaign, region, fold)
        metrics_path = path / "family_validation_metrics.csv"
        horizon_path = path / "family_policy_horizon_metrics.csv"
        frames.append(pd.read_csv(metrics_path))
        evidence.extend([
            artifact_record("r106_case_terminal", path / "terminal.json", case_id=case_id),
            artifact_record("r106_case_metrics", metrics_path, case_id=case_id),
            artifact_record("r106_case_horizon_metrics", horizon_path, case_id=case_id),
        ])
    return pd.concat(frames, ignore_index=True), evidence


def _r104_metrics(root: Path) -> pd.DataFrame:
    path = root / "pricefm_stage_r104_operator_metrics.csv"
    metrics = pd.read_csv(path)
    if metrics.test_opened.astype(bool).any():
        raise RuntimeError("R104 comparator opened test data")
    return metrics


def matched_comparison(exact: pd.DataFrame, early: pd.DataFrame) -> pd.DataFrame:
    keys = ["region", "fold", "family", "policy"]
    wanted = pd.DataFrame(
        [{"region": r, "fold": f, "family": family, "policy": policy}
         for _, r, f, family, policy in FOCUS_CASES]
    )
    exact_columns = {
        "validation_AQL_original": "exact500_AQL",
        "validation_AQCR": "exact500_AQCR",
        "coverage_10_90": "exact500_coverage_10_90",
        "mean_width_10_90": "exact500_mean_width_10_90",
        "mean_width_25_75": "exact500_mean_width_25_75",
        "median_MAE": "exact500_median_MAE",
        "median_RMSE": "exact500_median_RMSE",
    }
    early_columns = {column: f"early_{column}" for column in METRIC_COLUMNS}
    current = wanted.merge(exact[keys + list(exact_columns)], on=keys, how="left").rename(
        columns=exact_columns
    )
    reference = early[keys + list(early_columns)].rename(columns=early_columns)
    result = current.merge(reference, on=keys, how="left", validate="one_to_one")
    if len(result) != len(FOCUS_CASES) or result.isna().any().any():
        raise RuntimeError("R107 matched metric surface is incomplete")
    result["AQL_delta"] = result.exact500_AQL - result.early_AQL
    result["AQL_relative_change"] = result.AQL_delta / result.early_AQL.abs().clip(lower=1e-12)
    result["coverage_delta"] = (
        result.exact500_coverage_10_90 - result.early_coverage_10_90
    )
    result["width_10_90_relative_change"] = (
        result.exact500_mean_width_10_90 - result.early_mean_width_10_90
    ) / result.early_mean_width_10_90.abs().clip(lower=1e-12)
    result["AQCR_delta"] = result.exact500_AQCR - result.early_AQCR
    result["coverage_distance_change"] = (
        (result.exact500_coverage_10_90 - 0.8).abs()
        - (result.early_coverage_10_90 - 0.8).abs()
    )
    result["crossing_harm"] = result.exact500_AQCR > np.maximum(
        result.early_AQCR + 0.005, 0.01
    )
    result["practically_equivalent"] = (
        result.AQL_relative_change.abs().le(0.01)
        & result.coverage_delta.abs().le(0.02)
        & result.width_10_90_relative_change.abs().le(0.05)
    )
    result["materially_better"] = (
        result.AQL_relative_change.le(-0.02)
        & result.coverage_distance_change.le(0.02)
        & ~result.crossing_harm
    )
    result["materially_worse"] = (
        result.AQL_relative_change.ge(0.02)
        | result.coverage_distance_change.gt(0.02)
        | result.crossing_harm
    )
    return result.sort_values(keys).reset_index(drop=True)


def decision_from_comparison(comparison: pd.DataFrame) -> dict[str, Any]:
    total = len(comparison)
    equivalent = int(comparison.practically_equivalent.sum())
    better = int(comparison.materially_better.sum())
    worse = int(comparison.materially_worse.sum())
    if total != len(FOCUS_CASES):
        raise RuntimeError("R107 decision surface has the wrong size")
    if equivalent == total:
        action = "stop_broad_exact500_no_practical_change"
        broad_resume = False
    elif better >= 5 and worse == 0:
        action = "resume_broad_exact500_after_resource_review"
        broad_resume = True
    else:
        action = "hold_broad_exact500_mixed_forecast_effect"
        broad_resume = False
    return {
        "matched_rows": total,
        "practically_equivalent_rows": equivalent,
        "materially_better_rows": better,
        "materially_worse_rows": worse,
        "recommended_action": action,
        "broad_resume_supported": broad_resume,
    }


def trace_stability(campaign: Path) -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    rows = []
    evidence = []
    unique_cases = {(row[0], row[1], row[2]) for row in FOCUS_CASES}
    for case_id, region, fold in sorted(unique_cases):
        atoms = case_dir(campaign, region, fold) / "atoms"
        terminals = sorted(atoms.glob("*/terminal.json"))
        if len(terminals) != 14:
            raise RuntimeError(f"R107 expected 14 exact-500 atoms: {case_id}")
        for terminal_path in terminals:
            terminal = read_json(terminal_path)
            trace_path = terminal_path.parent / "vb_trace.csv"
            trace = pd.read_csv(trace_path)
            if (
                terminal.get("iterations") != 500
                or terminal.get("numerical_gate_passed") is not True
                or terminal.get("formal_converged") is not True
                or len(trace) != 500
                or set((200, 500)) - set(trace.iter.astype(int))
            ):
                raise RuntimeError(f"R107 exact-500 trace is invalid: {terminal_path}")
            at_200 = trace.loc[trace.iter.astype(int).eq(200)].iloc[0]
            at_500 = trace.loc[trace.iter.astype(int).eq(500)].iloc[0]
            def change(column: str) -> float:
                if column not in trace or not np.isfinite(float(at_200[column])):
                    return np.nan
                return float(at_500[column] - at_200[column])
            elbo_change = change("elbo")
            rows.append({
                "case_id": case_id,
                "region": region,
                "fold": fold,
                "atom_id": terminal["atom_id"],
                "family": terminal["family"],
                "tau": float(terminal["tau"]),
                "elbo_200": float(at_200.elbo),
                "elbo_500": float(at_500.elbo),
                "elbo_change_200_to_500": elbo_change,
                "absolute_relative_elbo_change": abs(elbo_change) / max(abs(float(at_500.elbo)), 1.0),
                "sigma_change_200_to_500": change("sigma"),
                "gamma_change_200_to_500": change("gamma"),
                "final_delta_state": float(at_500.delta_state),
                "formal_converged": True,
                "numerical_gate_passed": True,
                "iterations": 500,
                "test_opened": False,
            })
            evidence.extend([
                artifact_record("r106_atom_terminal", terminal_path, atom_id=terminal["atom_id"]),
                artifact_record("r106_atom_trace", trace_path, atom_id=terminal["atom_id"]),
            ])
    result = pd.DataFrame(rows).sort_values(["region", "fold", "family", "tau"])
    if len(result) != 56:
        raise RuntimeError("R107 focus trace packet must contain 56 atoms")
    return result, evidence


def horizon_comparison(campaign: Path, r104_root: Path) -> pd.DataFrame:
    exact_frames = []
    for case_id, region, fold in sorted({(x[0], x[1], x[2]) for x in FOCUS_CASES}):
        del case_id
        exact_frames.append(pd.read_csv(
            case_dir(campaign, region, fold) / "family_policy_horizon_metrics.csv"
        ))
    exact = pd.concat(exact_frames, ignore_index=True)
    early = pd.read_csv(r104_root / "pricefm_stage_r104_operator_horizon_metrics.csv")
    wanted = pd.DataFrame([
        {"region": r, "fold": f, "family": family, "policy": policy, "horizon": h}
        for _, r, f, family, policy in FOCUS_CASES for h in range(1, 97)
    ])
    keys = ["region", "fold", "family", "policy", "horizon"]
    current = wanted.merge(exact, on=keys, how="left").rename(columns={
        "validation_AQL_original": "exact500_AQL",
        "coverage_10_90": "exact500_coverage_10_90",
        "width_10_90": "exact500_width_10_90",
    })
    reference = early[keys + ["AQL", "coverage_10_90", "width_10_90"]].rename(columns={
        "AQL": "early_AQL",
        "coverage_10_90": "early_coverage_10_90",
        "width_10_90": "early_width_10_90",
    })
    result = current.merge(reference, on=keys, how="left", validate="one_to_one")
    if len(result) != len(FOCUS_CASES) * 96 or result[[
        "exact500_AQL", "early_AQL", "exact500_coverage_10_90",
        "early_coverage_10_90", "exact500_width_10_90", "early_width_10_90",
    ]].isna().any().any():
        raise RuntimeError("R107 horizon comparison is incomplete")
    result["AQL_delta"] = result.exact500_AQL - result.early_AQL
    return result.sort_values(keys).reset_index(drop=True)


def _prediction_paths(
    campaign: Path, r104_root: Path, region: str, fold: int, family: str, policy: str
) -> tuple[Path, Path]:
    exact = case_dir(campaign, region, fold) / f"{family}_{policy}_validation_quantiles.npz"
    early = r104_root / "predictions" / region / f"fold_{fold}" / f"{family}_{policy}.npz"
    return exact, early


def write_forecast_pdf(
    path: Path, campaign: Path, r104_root: Path, horizons: pd.DataFrame
) -> list[dict[str, Any]]:
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages

    evidence = []
    with PdfPages(path) as pdf:
        for _, region, fold, family, policy in FOCUS_CASES:
            exact_path, early_path = _prediction_paths(
                campaign, r104_root, region, fold, family, policy
            )
            with np.load(exact_path, allow_pickle=False) as archive:
                exact_prediction = np.asarray(archive["prediction_original"], dtype=float)
                exact_truth = np.asarray(archive["truth_original"], dtype=float)
            with np.load(early_path, allow_pickle=False) as archive:
                early_prediction = np.asarray(archive["prediction"], dtype=float)
                early_truth = np.asarray(archive["truth"], dtype=float)
            if (
                exact_prediction.shape != early_prediction.shape
                or exact_truth.shape != early_truth.shape
                or not np.allclose(exact_truth, early_truth, atol=1e-5, rtol=1e-6)
            ):
                raise RuntimeError(f"R107 prediction geometry changed: {region} fold {fold}")
            evidence.extend([
                artifact_record("r106_prediction", exact_path, region=region, fold=fold, family=family, policy=policy),
                artifact_record("r104_prediction", early_path, region=region, fold=fold, family=family, policy=policy),
            ])
            index = int(np.argmax(np.ptp(exact_truth, axis=1)))
            x = np.arange(1, 97)
            subset = horizons[
                horizons.region.eq(region)
                & horizons.fold.astype(int).eq(fold)
                & horizons.family.eq(family)
                & horizons.policy.eq(policy)
            ].sort_values("horizon")
            fig, axes = plt.subplots(2, 2, figsize=(13, 8.5))
            for axis, prediction, title, color in (
                (axes[0, 0], early_prediction, "R104 earlier fit", "#3b6ea8"),
                (axes[0, 1], exact_prediction, "R106 exact 500", "#c44e52"),
            ):
                axis.fill_between(x, prediction[0, index], prediction[-1, index], color=color, alpha=0.18)
                axis.fill_between(x, prediction[1, index], prediction[5, index], color=color, alpha=0.30)
                axis.plot(x, prediction[3, index], color=color, linewidth=1.8, label="Median")
                axis.plot(x, exact_truth[index], color="#202428", linewidth=1.2, label="Observed")
                axis.set_title(title, loc="left")
                axis.set_ylabel("Price")
                axis.grid(alpha=0.2)
            axes[1, 0].plot(x, subset.early_AQL, color="#3b6ea8", label="R104")
            axes[1, 0].plot(x, subset.exact500_AQL, color="#c44e52", label="R106 exact 500")
            axes[1, 0].set_title("Validation AQL by horizon", loc="left")
            axes[1, 0].set_ylabel("AQL")
            axes[1, 0].grid(alpha=0.2)
            axes[1, 1].plot(x, subset.early_width_10_90, color="#3b6ea8", label="R104 width")
            axes[1, 1].plot(x, subset.exact500_width_10_90, color="#c44e52", label="R106 width")
            axes[1, 1].set_title("Mean 10-90% width by horizon", loc="left")
            axes[1, 1].set_ylabel("Width")
            axes[1, 1].grid(alpha=0.2)
            for axis in axes.ravel():
                axis.set_xlabel("Forecast horizon (hours)")
                axis.legend(frameon=False, fontsize=8)
            fig.suptitle(f"{region}, Fold {fold}, {family.upper()}, {policy}", fontsize=13)
            fig.tight_layout(rect=(0, 0, 1, 0.96))
            pdf.savefig(fig)
            plt.close(fig)
    return evidence


def write_trace_pdf(path: Path, campaign: Path, stability: pd.DataFrame) -> None:
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages

    with PdfPages(path) as pdf:
        for (region, fold, family), group in stability.groupby(
            ["region", "fold", "family"], sort=True
        ):
            fig, axes = plt.subplots(2, 1, figsize=(11, 8))
            for row in group.sort_values("tau").itertuples(index=False):
                trace_path = (
                    case_dir(campaign, region, int(fold))
                    / "atoms" / row.atom_id / "vb_trace.csv"
                )
                trace = pd.read_csv(trace_path)
                axes[0].plot(trace.iter, trace.elbo, label=f"q={row.tau:g}")
                axes[1].plot(trace.iter, np.maximum(np.abs(trace.delta_state), 1e-14))
            axes[0].axvline(200, color="#555555", linestyle="--", linewidth=1)
            axes[0].set_title("Raw total ELBO")
            axes[0].set_ylabel("ELBO")
            axes[1].axvline(200, color="#555555", linestyle="--", linewidth=1)
            axes[1].set_title("Absolute state change")
            axes[1].set_yscale("log")
            axes[1].set_ylabel("Change")
            for axis in axes:
                axis.set_xlabel("Iteration")
                axis.grid(alpha=0.2)
            axes[0].legend(frameon=False, ncol=4, fontsize=8)
            fig.suptitle(f"{region}, Fold {fold}, {family.upper()}: exact-500 diagnostics")
            fig.tight_layout(rect=(0, 0, 1, 0.96))
            pdf.savefig(fig)
            plt.close(fig)


def write_report(
    path: Path, comparison: pd.DataFrame, stability: pd.DataFrame,
    decision: dict[str, Any], gates: pd.DataFrame,
) -> None:
    summary = comparison[[
        "region", "fold", "family", "policy", "early_AQL", "exact500_AQL",
        "AQL_relative_change", "early_coverage_10_90", "exact500_coverage_10_90",
        "early_mean_width_10_90", "exact500_mean_width_10_90",
        "practically_equivalent", "materially_better", "materially_worse",
    ]]
    lines = [
        "# PriceFM Stage-R107 exact-500 focus comparison",
        "",
        "R107 is a validation-only production-data checkpoint. It compares four fully "
        "completed R106 cases with seven matching R104 family/operator rows. It does "
        "not open test data or authorize registry, article, joint, or MCMC work.",
        "",
        "## Decision",
        "",
        f"Recommended action: `{decision['recommended_action']}`.",
        "",
        "## Matched forecast metrics",
        "",
        summary.to_markdown(index=False, floatfmt=".5f"),
        "",
        "## Iteration stability",
        "",
        f"All {len(stability)} focus atoms contain exactly 500 finite iterations. "
        f"The maximum absolute relative ELBO change from iteration 200 to 500 is "
        f"{stability.absolute_relative_elbo_change.max():.3e}.",
        "",
        "## Gates",
        "",
        gates.to_markdown(index=False),
        "",
        "## Interpretation",
        "",
        "If every matched row is practically equivalent, the broad exact-500 campaign "
        "is computationally redundant. If at least five of seven rows improve AQL by "
        "at least two percent without coverage or crossing harm, a broad resume may be "
        "considered after a resource review. Mixed evidence remains blocked for focused "
        "forecast-mechanism diagnosis.",
        "",
    ]
    path.write_text("\n".join(lines))


def _records(paths: Iterable[dict[str, Any]]) -> pd.DataFrame:
    value = pd.DataFrame(paths).drop_duplicates(subset=["path", "sha256"])
    return value.sort_values(["role", "path"]).reset_index(drop=True)


def run(args: argparse.Namespace) -> dict[str, Any]:
    campaign = args.campaign_root.resolve()
    r104_root = args.r104_root.resolve()
    output = args.output_dir.resolve()
    exact, evidence = load_exact500_metrics(campaign)
    early = _r104_metrics(r104_root)
    comparison = matched_comparison(exact, early)
    stability, trace_evidence = trace_stability(campaign)
    evidence.extend(trace_evidence)
    horizons = horizon_comparison(campaign, r104_root)
    decision = decision_from_comparison(comparison)
    gates = pd.DataFrame([
        ("four_focus_cases_complete", True, 4),
        ("matched_forecast_rows_complete", len(comparison) == 7, len(comparison)),
        ("focus_atoms_complete", len(stability) == 56, len(stability)),
        ("all_atoms_exact_500", stability.iterations.eq(500).all(), int(stability.iterations.eq(500).sum())),
        ("all_atoms_formally_converged", stability.formal_converged.all(), int(stability.formal_converged.sum())),
        ("all_atoms_numerically_eligible", stability.numerical_gate_passed.all(), int(stability.numerical_gate_passed.sum())),
        ("test_never_opened", True, False),
        ("joint_mcmc_registry_article_blocked", True, "joint;mcmc;registry;article;test"),
    ], columns=["gate", "passed", "observed"])
    if not gates.passed.all():
        raise RuntimeError("R107 focus comparison gate failed")
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        comparison.to_csv(
            temporary / "pricefm_stage_r107_matched_forecast_comparison.csv",
            index=False, quoting=csv.QUOTE_MINIMAL,
        )
        horizons.to_csv(
            temporary / "pricefm_stage_r107_horizon_comparison.csv",
            index=False, quoting=csv.QUOTE_MINIMAL,
        )
        stability.to_csv(
            temporary / "pricefm_stage_r107_iteration_stability.csv",
            index=False, quoting=csv.QUOTE_MINIMAL,
        )
        gates.to_csv(temporary / "pricefm_stage_r107_gates.csv", index=False)
        evidence.extend(write_forecast_pdf(
            temporary / "pricefm_stage_r107_forecast_comparison.pdf",
            campaign, r104_root, horizons,
        ))
        write_trace_pdf(
            temporary / "pricefm_stage_r107_raw_elbo_diagnostics.pdf",
            campaign,
            stability,
        )
        evidence.extend([
            artifact_record("r104_metrics", r104_root / "pricefm_stage_r104_operator_metrics.csv"),
            artifact_record("r104_horizon_metrics", r104_root / "pricefm_stage_r104_operator_horizon_metrics.csv"),
        ])
        _records(evidence).to_csv(temporary / "source_manifest.csv", index=False)
        write_report(
            temporary / "pricefm_stage_r107_exact500_focus_comparison.md",
            comparison, stability, decision, gates,
        )
        output_names = (
            "pricefm_stage_r107_matched_forecast_comparison.csv",
            "pricefm_stage_r107_horizon_comparison.csv",
            "pricefm_stage_r107_iteration_stability.csv",
            "pricefm_stage_r107_gates.csv",
            "pricefm_stage_r107_forecast_comparison.pdf",
            "pricefm_stage_r107_raw_elbo_diagnostics.pdf",
            "pricefm_stage_r107_exact500_focus_comparison.md",
            "source_manifest.csv",
        )
        summary = {
            "stage": "R107",
            "status": "completed_validation_only_exact500_focus_comparison",
            "focus_cases": list(FOCUS_CASE_IDS),
            **decision,
            "atoms_exact_500": int(stability.iterations.eq(500).sum()),
            "maximum_absolute_relative_elbo_change_200_to_500": float(
                stability.absolute_relative_elbo_change.max()
            ),
            "test_opened": False,
            "registry_mutated": False,
            "article_mutated": False,
            "joint_model_fitted": False,
            "mcmc_fitted": False,
            "outputs": {
                name: {
                    "path": str((output / name).resolve()),
                    "sha256": sha256_file(temporary / name),
                    "bytes": (temporary / name).stat().st_size,
                }
                for name in output_names
            },
            "next_gate": "manual_R107_forecast_review_before_any_broad_resume_or_model_change",
        }
        write_json(temporary / "summary.json", summary)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> int:
    run(parser().parse_args())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
