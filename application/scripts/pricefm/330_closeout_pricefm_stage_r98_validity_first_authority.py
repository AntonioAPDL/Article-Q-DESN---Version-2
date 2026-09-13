#!/usr/bin/env python3
"""Build the complete validity-first R98 PriceFM authority handoff package."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_r97_distributed_contract import verify_seal
from pricefm_region_frozen_contract import (
    PAPER_QUANTILES,
    atomic_write_json,
    file_record,
    prepare_empty_directory,
    sha256_file,
    verify_file_record,
)


REQUIRED_DESN = (
    "lag_window", "depth", "units", "alpha", "rho", "input_scale",
    "feature_policy", "state_output",
)
BLOCKED = (
    "model_refit_authorized", "selection_change_authorized",
    "registry_mutation_authorized", "article_mutation_authorized",
    "joint_model_authorized", "mcmc_authorized",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--scoring-authorization", type=Path, required=True)
    value.add_argument("--global-scoring-terminal", type=Path, required=True)
    value.add_argument("--r97-closeout-dir", type=Path, required=True)
    value.add_argument("--scoring-manifest", type=Path, required=True)
    value.add_argument("--r92-authority", type=Path, required=True)
    value.add_argument("--region-closeout-root", type=Path, required=True)
    value.add_argument("--se2-comparison", type=Path, required=True)
    value.add_argument("--se2-validation-surface", type=Path, required=True)
    value.add_argument("--output-dir", type=Path, required=True)
    value.add_argument("--quarantine-root", type=Path, default=None)
    value.add_argument("--quarantine-existing", action="store_true")
    return value


def validate_authorization(path: Path) -> dict[str, Any]:
    authorization = json.loads(path.read_text())
    verify_seal(authorization, "scoring_authorization_sha256", label="R98 scoring authorization")
    if (
        authorization.get("stage") != "R98"
        or authorization.get("status") != "authorized_once_for_frozen_R97_test_scoring"
        or authorization.get("test_access_authorized") is not True
        or authorization.get("test_opened") is not False
        or any(authorization.get(name) is not False for name in BLOCKED)
    ):
        raise RuntimeError("R98 scoring authorization is invalid")
    policy = authorization.get("authority_transition_policy") or {}
    if (
        policy.get("r98_authority_rule")
        != "replace_all_114_R92_rows_with_the_complete_R97_surface_regardless_of_test_performance"
        or policy.get("case_specific_R92_fallback_authorized") is not False
        or policy.get("performance_is_reported_not_used_to_choose_authority") is not True
    ):
        raise RuntimeError("R98 validity-first transition policy changed")
    for name in (
        "reconciliation_terminal", "campaign_contract", "r92_authority",
        "se2_comparison", "se2_validation_surface", "region_specifications",
        "authority_transition_policy_file",
    ):
        verify_file_record(authorization[name], label=f"R98 authorization {name}")
    for record in authorization.get("scoring_code") or []:
        verify_file_record(record, label="R98 authorized scoring code")
    return authorization


def load_complete_surface(root: Path, terminal: dict[str, Any]) -> tuple[pd.DataFrame, dict[str, Any], list[dict[str, Any]]]:
    summary_path = root / "summary.json"
    surface_path = root / "pricefm_stage_r97_complete_surface.csv"
    region_path = root / "pricefm_stage_r97_region_diagnostics.csv"
    decision_path = root / "pricefm_stage_r97_global_mean_decision.csv"
    source_path = root / "source_manifest.csv"
    summary = json.loads(summary_path.read_text())
    if (
        summary.get("status") != "completed_global_surface_closeout"
        or summary.get("stage") != "R97"
        or summary.get("cases") != 114
        or summary.get("regions") != 38
        or summary.get("folds") != 3
        or summary.get("per_case_dual_comparator_veto_used") is not False
        or summary.get("test_driven_case_mixing_used") is not False
    ):
        raise RuntimeError("R97 global closeout is incomplete or changed")
    closeout_record = terminal.get("global_closeout") or {}
    if not np.isclose(float(closeout_record.get("candidate_mean_AQL")), float(summary["candidate_mean_AQL"]), atol=1e-12, rtol=0):
        raise RuntimeError("R97 global terminal and closeout disagree")
    surface = pd.read_csv(surface_path)
    if (
        len(surface) != 114
        or surface.duplicated(["region", "fold"]).any()
        or surface.region.nunique() != 38
        or sorted(surface.fold.astype(int).unique()) != [1, 2, 3]
    ):
        raise RuntimeError("R97 closeout does not contain the exact 114-case surface")
    records = [file_record(path, role) for path, role in (
        (summary_path, "R97_global_summary"), (surface_path, "R97_complete_surface"),
        (region_path, "R97_region_diagnostics"), (decision_path, "R97_global_mean_decision"),
        (source_path, "R97_source_manifest"),
    )]
    return surface, summary, records


def specification_and_validation_rows(
    region_root: Path, se2_surface_path: Path,
) -> tuple[pd.DataFrame, pd.DataFrame, list[dict[str, Any]]]:
    specifications = []
    validations = []
    evidence = []
    for root in sorted(path for path in region_root.iterdir() if path.is_dir()):
        surface_path = root / "pricefm_stage_r97_frozen_region_surface.json"
        metrics_path = root / "pricefm_stage_r97_family_fold_validation_metrics.csv"
        if not surface_path.is_file():
            continue
        surface = json.loads(surface_path.read_text())
        region = str(surface["region"])
        family = str(surface["selected_family"])
        spec = surface["frozen_desn"]
        specifications.append({
            "region": region, "selected_family": family,
            "rhs_tau0": float(surface["rhs_tau0"]),
            **{name: spec[name] for name in REQUIRED_DESN},
            "selection_source_stage": "R97",
            "selected_atom_manifest_path": surface["selected_atom_manifest"]["path"],
            "selected_atom_manifest_sha256": surface["selected_atom_manifest"]["sha256"],
        })
        metrics = pd.read_csv(metrics_path)
        chosen = metrics[metrics.family.astype(str).eq(family)].copy()
        if len(chosen) != 3 or sorted(chosen.fold.astype(int)) != [1, 2, 3]:
            raise RuntimeError(f"R97 validation metrics are incomplete: {region}")
        for row in chosen.itertuples(index=False):
            validations.append({
                "region": region, "fold": int(row.fold),
                "selected_validation_AQL": float(row.AQL),
                "selected_validation_AQCR": float(row.AQCR),
                "selected_validation_MAE": float(row.MAE),
                "selected_validation_RMSE": float(row.RMSE),
            })
        evidence.extend([file_record(surface_path, f"{region}_frozen_surface"), file_record(metrics_path, f"{region}_validation_metrics")])
    if len(specifications) != 37:
        raise RuntimeError("R98 closeout requires exactly 37 R97 region specifications")

    se2_surface = json.loads(se2_surface_path.read_text())
    se2_spec = se2_surface["frozen_desn"]
    specifications.append({
        "region": "SE_2", "selected_family": "exal",
        "rhs_tau0": float(se2_surface["rhs_tau0"]),
        **{name: se2_spec[name] for name in REQUIRED_DESN},
        "selection_source_stage": "R95_R96_reuse",
        "selected_atom_manifest_path": str(se2_surface_path.resolve()),
        "selected_atom_manifest_sha256": sha256_file(se2_surface_path),
    })
    se2_metrics_path = se2_surface_path.parent / "pricefm_stage_r95_fold_family_validation_metrics.csv"
    se2_metrics = pd.read_csv(se2_metrics_path)
    selected = se2_metrics[se2_metrics.family.astype(str).eq("exal")]
    if len(selected) != 3 or sorted(selected.fold.astype(int)) != [1, 2, 3]:
        raise RuntimeError("R95 SE_2 validation metrics are incomplete")
    for row in selected.itertuples(index=False):
        validations.append({
            "region": "SE_2", "fold": int(row.fold),
            "selected_validation_AQL": float(row.AQL),
            "selected_validation_AQCR": float(row.AQCR),
            "selected_validation_MAE": float(row.MAE),
            "selected_validation_RMSE": float(row.RMSE),
        })
    evidence.extend([file_record(se2_surface_path, "SE_2_frozen_validation_surface"), file_record(se2_metrics_path, "SE_2_validation_metrics")])
    return pd.DataFrame(specifications), pd.DataFrame(validations), evidence


def scoring_evidence(manifest_path: Path, se2_path: Path) -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    manifest = pd.read_csv(manifest_path)
    if len(manifest) != 111 or manifest.duplicated(["region", "fold"]).any():
        raise RuntimeError("R98 scoring evidence requires exactly 111 newly scored cases")
    rows = []
    evidence = [file_record(manifest_path, "R97_scoring_manifest")]
    for row in manifest.itertuples(index=False):
        terminal_path = Path(row.output_dir) / "terminal.json"
        metric_path = Path(row.output_dir) / "test_metric.csv"
        terminal = json.loads(terminal_path.read_text())
        if (
            terminal.get("status") != "completed"
            or terminal.get("model_fitted") is not False
            or terminal.get("selection_changed") is not False
            or terminal.get("test_opened") is not True
        ):
            raise RuntimeError(f"R97 scoring terminal is invalid: {row.task_id}")
        rows.append({
            "region": str(row.region), "fold": int(row.fold),
            "test_evidence_path": str(metric_path.resolve()),
            "test_evidence_sha256": sha256_file(metric_path),
        })
        evidence.extend([file_record(terminal_path, "R97_scoring_terminal"), file_record(metric_path, "R97_scoring_metric")])
    se2_record = file_record(se2_path, "R96_SE_2_scoring_comparison")
    for fold in (1, 2, 3):
        rows.append({
            "region": "SE_2", "fold": fold,
            "test_evidence_path": se2_record["path"], "test_evidence_sha256": se2_record["sha256"],
        })
    evidence.append(se2_record)
    return pd.DataFrame(rows), evidence


def fill_se2_metrics(surface: pd.DataFrame, comparison: pd.DataFrame) -> pd.DataFrame:
    result = surface.copy()
    values = comparison.set_index(comparison.fold.astype(int))
    mapping = {
        "AQL": "candidate_test_AQL", "MAE": "candidate_test_MAE",
        "RMSE": "candidate_test_RMSE", "AQCR": "adjacent_crossing_rate",
    }
    for index in result.index[result.region.astype(str).eq("SE_2")]:
        fold = int(result.loc[index, "fold"])
        for target, source in mapping.items():
            result.loc[index, target] = float(values.loc[fold, source])
    return result


def write_table(path: Path, comparison: pd.DataFrame) -> None:
    rows = [
        r"\begingroup", r"\TableStyle", r"\begin{tabular}{@{}lrr@{}}", r"\toprule",
        "Surface & Cases & Mean AQL " + r"\\", r"\midrule",
    ]
    labels = {
        "R98_protocol_valid_QDESN": r"Q--DESN (R98 region-frozen)",
        "cached_PriceFM": "PriceFM (cached direct replay)",
        "R92_deprecated_historical_QDESN": r"Q--DESN (R92; historical sensitivity)",
    }
    for row in comparison.itertuples(index=False):
        rows.append(f"{labels[row.surface]} & {int(row.cases)} & {float(row.mean_AQL):.6f} " + r"\\")
    rows.extend([r"\bottomrule", r"\end{tabular}", r"\endgroup"])
    path.write_text("\n".join(rows) + "\n")


def write_region_figure(path_png: Path, path_pdf: Path, regions: pd.DataFrame) -> None:
    ordered = regions.sort_values("R98_mean_AQL", ascending=True).reset_index(drop=True)
    positions = np.arange(len(ordered))
    fig, ax = plt.subplots(figsize=(11.5, 7.2))
    ax.scatter(ordered.cached_PriceFM_mean_AQL, positions, s=28, color="#2a7f62", label="PriceFM")
    ax.scatter(ordered.R98_mean_AQL, positions, s=34, color="#2457a6", marker="s", label="R98 Q-DESN")
    ax.scatter(ordered.deprecated_R92_mean_AQL, positions, s=24, color="#8a8a8a", marker="x", label="R92 historical")
    ax.set_yticks(positions, ordered.region)
    ax.set_xlabel("Mean AQL across three folds (lower is better)")
    ax.set_ylabel("Region")
    ax.grid(axis="x", color="#dddddd", linewidth=0.7)
    ax.legend(frameon=False, ncol=3, loc="lower right")
    fig.tight_layout()
    fig.savefig(path_png, dpi=180)
    fig.savefig(path_pdf)
    plt.close(fig)


def run(args: argparse.Namespace) -> dict[str, Any]:
    authorization = validate_authorization(args.scoring_authorization)
    for argument, record_name in (
        (args.r92_authority, "r92_authority"),
        (args.se2_comparison, "se2_comparison"),
        (args.se2_validation_surface, "se2_validation_surface"),
    ):
        if argument.resolve() != Path(authorization[record_name]["path"]).resolve():
            raise RuntimeError(f"R98 closeout source differs from authorization: {record_name}")
    terminal = json.loads(args.global_scoring_terminal.read_text())
    verify_seal(terminal, "global_scoring_terminal_sha256", label="R97 global scoring terminal")
    if (
        terminal.get("status") != "completed_global_scoring_closeout"
        or terminal.get("cases") != 114
        or terminal.get("model_refit_during_test_scoring") is not False
        or terminal.get("selection_changed_during_test_scoring") is not False
    ):
        raise RuntimeError("R97 global scoring terminal is incomplete or unsafe")
    authorized_path = Path(terminal["scoring_authorization"]["path"])
    if authorized_path.resolve() != args.scoring_authorization.resolve():
        raise RuntimeError("R97 global scoring used a different R98 authorization")
    verify_file_record(terminal["scoring_authorization"], label="R97 terminal scoring authorization")

    surface, r97_summary, evidence = load_complete_surface(args.r97_closeout_dir, terminal)
    se2 = pd.read_csv(args.se2_comparison)
    surface = fill_se2_metrics(surface, se2)
    numeric = surface[["AQL", "AQCR", "MAE", "RMSE"]].apply(pd.to_numeric, errors="coerce")
    if not np.isfinite(numeric.to_numpy()).all():
        raise RuntimeError("R98 candidate surface has incomplete test metrics")
    authority = pd.read_csv(args.r92_authority)
    if len(authority) != 114 or authority.duplicated(["region", "fold"]).any():
        raise RuntimeError("R92 historical comparator is incomplete")
    specs, validation, spec_evidence = specification_and_validation_rows(
        args.region_closeout_root, args.se2_validation_surface,
    )
    score_evidence, scoring_records = scoring_evidence(args.scoring_manifest, args.se2_comparison)

    registry = surface.merge(specs, on=["region", "selected_family"], how="left", validate="many_to_one")
    registry = registry.merge(validation, on=["region", "fold"], how="left", validate="one_to_one")
    registry = registry.merge(score_evidence, on=["region", "fold"], how="left", validate="one_to_one")
    old_columns = [
        "region", "fold", "qdesn_method_id", "qdesn_AQL", "source_class",
        "experiment_id", "feature_policy",
    ]
    old = authority[old_columns].rename(columns={
        "qdesn_method_id": "deprecated_R92_method_id",
        "qdesn_AQL": "deprecated_R92_AQL",
        "source_class": "deprecated_R92_source_class",
        "experiment_id": "deprecated_R92_experiment_id",
        "feature_policy": "deprecated_R92_feature_policy",
    })
    registry = registry.merge(old, on=["region", "fold"], how="left", validate="one_to_one")
    registry["qdesn_method_id"] = registry.selected_family.map({
        "al": "qdesn_al_rhs_ns_r98_region_frozen",
        "exal": "qdesn_exal_rhs_ns_r98_region_frozen",
    })
    registry["qdesn_AQL"] = registry.AQL.astype(float)
    registry["qdesn_AQCR"] = registry.AQCR.astype(float)
    registry["qdesn_MAE"] = registry.MAE.astype(float)
    registry["qdesn_RMSE"] = registry.RMSE.astype(float)
    registry["pricefm_AQL"] = registry.cached_pricefm_AQL.astype(float)
    registry["delta_AQL_qdesn_minus_pricefm"] = registry.qdesn_AQL - registry.pricefm_AQL
    registry["delta_AQL_qdesn_minus_deprecated_R92"] = registry.qdesn_AQL - registry.deprecated_R92_AQL
    registry["decision_label"] = np.where(registry.qdesn_AQL < registry.pricefm_AQL, "qdesn_wins", "pricefm_wins")
    registry["authority_status"] = "R98_coordinator_ready_not_integrated"
    registry["authority_basis"] = "prospective_region_frozen_validation_only_protocol"
    registry["authority_transition_rule"] = "complete_114_case_replacement_regardless_of_performance"
    registry["selected_on_split"] = "fold1_train_internal_temporal_validation_and_fold1_outer_validation"
    registry["selection_is_validation_only"] = True
    registry["same_desn_tau0_all_folds_within_region"] = True
    registry["same_likelihood_family_all_folds_within_region"] = True
    registry["test_driven_case_mixing_used"] = False
    registry["R92_case_fallback_used"] = False
    registry["test_metrics_role"] = "audit_and_reporting_only"
    registry["r97_preregistered_performance_gate_passed"] = bool(r97_summary["complete_surface_promotion_gate_passed"])
    registry["registry_mutation_authorized"] = False
    registry["article_mutation_authorized"] = False
    registry["joint_model_authorized"] = False
    registry["mcmc_authorized"] = False
    if (
        len(registry) != 114 or registry.duplicated(["region", "fold"]).any()
        or registry.qdesn_method_id.isna().any()
        or registry.selected_validation_AQL.isna().any()
        or registry.test_evidence_sha256.isna().any()
    ):
        raise RuntimeError("R98 authority registry is incomplete")

    output, quarantined = prepare_empty_directory(
        args.output_dir,
        quarantine_root=args.quarantine_root or args.output_dir.parent / "quarantine",
        reason="replaced_R98_validity_first_closeout",
        allow_quarantine=args.quarantine_existing,
    )
    registry_path = output / "pricefm_stage_r98_authoritative_registry.csv"
    registry.to_csv(registry_path, index=False)
    global_comparison = pd.DataFrame([
        {"surface": "R98_protocol_valid_QDESN", "cases": 114, "mean_AQL": float(registry.qdesn_AQL.mean()), "authority_role": "replacement_candidate"},
        {"surface": "cached_PriceFM", "cases": 114, "mean_AQL": float(registry.pricefm_AQL.mean()), "authority_role": "external_comparator"},
        {"surface": "R92_deprecated_historical_QDESN", "cases": 114, "mean_AQL": float(registry.deprecated_R92_AQL.mean()), "authority_role": "historical_sensitivity_only"},
    ])
    global_path = output / "pricefm_stage_r98_global_comparison.csv"
    global_comparison.to_csv(global_path, index=False)
    region = registry.groupby("region", as_index=False).agg(
        R98_mean_AQL=("qdesn_AQL", "mean"),
        cached_PriceFM_mean_AQL=("pricefm_AQL", "mean"),
        deprecated_R92_mean_AQL=("deprecated_R92_AQL", "mean"),
    )
    region["R98_minus_PriceFM"] = region.R98_mean_AQL - region.cached_PriceFM_mean_AQL
    region["R98_minus_deprecated_R92"] = region.R98_mean_AQL - region.deprecated_R92_mean_AQL
    region_path = output / "pricefm_stage_r98_region_comparison.csv"
    region.to_csv(region_path, index=False)
    fold = registry.groupby("fold", as_index=False).agg(
        R98_mean_AQL=("qdesn_AQL", "mean"),
        cached_PriceFM_mean_AQL=("pricefm_AQL", "mean"),
        deprecated_R92_mean_AQL=("deprecated_R92_AQL", "mean"),
    )
    fold_path = output / "pricefm_stage_r98_fold_comparison.csv"
    fold.to_csv(fold_path, index=False)
    transition = registry[[
        "region", "fold", "qdesn_method_id", "qdesn_AQL",
        "deprecated_R92_method_id", "deprecated_R92_AQL",
        "delta_AQL_qdesn_minus_deprecated_R92", "authority_transition_rule",
        "R92_case_fallback_used", "test_evidence_path", "test_evidence_sha256",
    ]].copy()
    transition_path = output / "pricefm_stage_r98_authority_transition_ledger.csv"
    transition.to_csv(transition_path, index=False)

    table_path = output / "pricefm_stage_r98_global_aql_comparison.tex"
    figure_png = output / "pricefm_stage_r98_region_aql_comparison.png"
    figure_pdf = output / "pricefm_stage_r98_region_aql_comparison.pdf"
    write_table(table_path, global_comparison)
    write_region_figure(figure_png, figure_pdf, region)
    article_assets = [table_path, figure_png, figure_pdf, global_path, region_path, fold_path]
    asset_manifest = {
        "schema_version": 1, "stage": "R98",
        "status": "article_safe_assets_ready_for_coordinator_not_published",
        "article_mutation_authorized": False,
        "assets": [file_record(path, "coordinator_article_asset") for path in article_assets],
        "required_prose_disclosure": (
            "R98 is the prospective region-frozen validation-only Q-DESN surface; R92 is retained only "
            "as a deprecated historical sensitivity surface and was not used as a case-level fallback."
        ),
    }
    asset_manifest_path = output / "pricefm_stage_r98_article_asset_manifest.json"
    atomic_write_json(asset_manifest_path, asset_manifest)

    r98_mean = float(registry.qdesn_AQL.mean())
    r92_mean = float(registry.deprecated_R92_AQL.mean())
    pricefm_mean = float(registry.pricefm_AQL.mean())
    report_path = output / "pricefm_stage_r98_validity_first_closeout.md"
    report_path.write_text(
        "# PriceFM Stage-R98 validity-first closeout\n\n"
        f"R98 Q-DESN mean AQL is `{r98_mean:.9f}` over all 114 region-fold cases. "
        f"Cached PriceFM is `{pricefm_mean:.9f}` and deprecated R92 Q-DESN is `{r92_mean:.9f}`.\n\n"
        f"The original R97 performance gate {'passed' if r97_summary['complete_surface_promotion_gate_passed'] else 'did not pass'}. "
        "Independently of that result, all 114 R98 rows form the coordinator-ready authority replacement because "
        "they follow the prospective region-frozen, validation-only protocol. No R92 row was retained as a fallback.\n\n"
        "Registry and article publication remain blocked in this task lane. The integration coordinator must review "
        "this package, update authoritative main, compile the manuscript, and publish the article-only snapshot.\n"
    )
    all_evidence = [
        file_record(args.scoring_authorization, "R98_scoring_authorization"),
        file_record(args.global_scoring_terminal, "R97_global_scoring_terminal"),
        file_record(args.r92_authority, "R92_deprecated_authority"),
        *evidence, *spec_evidence, *scoring_records,
    ]
    source_path = output / "source_manifest.csv"
    pd.DataFrame(all_evidence).drop_duplicates(["path", "sha256"]).to_csv(source_path, index=False)
    outputs = [
        registry_path, global_path, region_path, fold_path, transition_path,
        table_path, figure_png, figure_pdf, asset_manifest_path, report_path, source_path,
    ]
    summary = {
        "schema_version": 1, "stage": "R98",
        "status": "completed_validity_first_authority_package_ready_for_coordinator",
        "cases": 114, "regions": 38, "folds": 3,
        "R98_mean_AQL": r98_mean, "cached_PriceFM_mean_AQL": pricefm_mean,
        "deprecated_R92_mean_AQL": r92_mean,
        "R98_minus_PriceFM_mean_AQL": r98_mean - pricefm_mean,
        "R98_minus_deprecated_R92_mean_AQL": r98_mean - r92_mean,
        "R97_preregistered_performance_gate_passed": bool(r97_summary["complete_surface_promotion_gate_passed"]),
        "R98_rows_selected_as_authority": 114,
        "R92_rows_retained_as_fallback": 0,
        "test_driven_case_mixing_used": False,
        "model_refits_during_scoring": 0, "selection_changes_after_test": 0,
        "registry_mutated": False, "article_mutated": False,
        "joint_model_authorized": False, "mcmc_authorized": False,
        "quarantined_previous_output": str(quarantined) if quarantined else None,
        "outputs": {path.stem: file_record(path, "R98_output") for path in outputs},
    }
    atomic_write_json(output / "summary.json", summary)
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
