#!/usr/bin/env python3
"""Close the complete R97 surface using one predeclared 114-case mean AQL."""

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

from pricefm_region_frozen_contract import (
    atomic_write_json,
    canonical_sha256,
    file_record,
    prepare_empty_directory,
    sha256_file,
    verify_file_record,
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--scoring-manifest", type=Path, required=True)
    value.add_argument("--campaign-contract", type=Path, required=True)
    value.add_argument("--authority-registry", type=Path, required=True)
    value.add_argument("--se2-comparison", type=Path, required=True)
    value.add_argument("--output-dir", type=Path, required=True)
    value.add_argument("--quarantine-root", type=Path, default=None)
    value.add_argument("--quarantine-existing", action="store_true")
    return value


def run(args: argparse.Namespace) -> dict[str, Any]:
    campaign = json.loads(args.campaign_contract.read_text())
    unhashed = {key: value for key, value in campaign.items() if key != "campaign_contract_sha256"}
    if canonical_sha256(unhashed) != campaign.get("campaign_contract_sha256"):
        raise RuntimeError("R97 campaign contract hash changed")
    final_decision = campaign["final_decision"]
    if (
        campaign.get("case_count") != 114
        or final_decision.get("per_case_dual_comparator_veto") is not False
        or final_decision.get("aggregation") != "unweighted_arithmetic_mean_over_exactly_114_region_fold_cases"
        or final_decision.get("promotion_gate") != "candidate_mean_AQL_strictly_below_current_R92_mean_AQL"
    ):
        raise RuntimeError("R97 campaign does not contain the corrected complete-surface decision rule")
    authority = pd.read_csv(args.authority_registry)
    if len(authority) != 114 or authority.duplicated(["region", "fold"]).any():
        raise RuntimeError("R97 authority is not the exact 114-case comparator surface")
    if sha256_file(args.authority_registry) != campaign["authority_registry"]["sha256"]:
        raise RuntimeError("R97 closeout authority differs from the frozen campaign authority")
    manifest = pd.read_csv(args.scoring_manifest)
    if len(manifest) != 111 or manifest.duplicated(["region", "fold"]).any():
        raise RuntimeError("R97 closeout requires exactly 111 newly scored cases")
    rows = []
    evidence = [
        file_record(args.scoring_manifest, "scoring_manifest"),
        file_record(args.campaign_contract, "campaign_contract"),
        file_record(args.authority_registry, "R92_authority"),
        file_record(args.se2_comparison, "frozen_R96_SE_2_surface"),
    ]
    for item in manifest.itertuples(index=False):
        task_path = Path(item.task_config)
        if sha256_file(task_path) != str(item.task_config_sha256):
            raise RuntimeError(f"R97 scoring task hash changed: {item.task_id}")
        terminal_path = Path(item.output_dir) / "terminal.json"
        terminal = json.loads(terminal_path.read_text())
        if (
            terminal.get("status") != "completed" or terminal.get("task_id") != item.task_id
            or terminal.get("model_fitted") is not False or terminal.get("selection_changed") is not False
            or terminal.get("test_opened") is not True
        ):
            raise RuntimeError(f"R97 scoring terminal is invalid: {item.task_id}")
        for record in terminal.get("artifacts") or []:
            verify_file_record(record, label="R97 scoring artifact")
        metric_path = Path(item.output_dir) / "test_metric.csv"
        metric = pd.read_csv(metric_path)
        if len(metric) != 1:
            raise RuntimeError(f"R97 scoring metric is invalid: {metric_path}")
        metric_row = metric.iloc[0]
        if str(metric_row.region) != str(item.region) or int(metric_row.fold) != int(item.fold):
            raise RuntimeError(f"R97 scoring metric identity differs from its task: {item.task_id}")
        rows.append(metric_row.to_dict())
        evidence.extend([
            file_record(task_path, "scoring_task"),
            file_record(terminal_path, "scoring_terminal"),
            file_record(metric_path, "scoring_metric"),
        ])
    candidate = pd.DataFrame(rows)
    se2 = pd.read_csv(args.se2_comparison)
    required_se2 = {
        "region", "fold", "candidate_test_AQL", "authoritative_qdesn_test_AQL",
        "cached_pricefm_test_AQL",
    }
    if not required_se2.issubset(se2.columns) or len(se2) != 3:
        raise RuntimeError("R97 SE_2 reuse surface is incomplete")
    se2_rows = pd.DataFrame({
        "region": se2.region.astype(str), "fold": se2.fold.astype(int),
        "selected_family": "exal", "AQL": se2.candidate_test_AQL.astype(float),
        "current_authoritative_qdesn_AQL": se2.authoritative_qdesn_test_AQL.astype(float),
        "cached_pricefm_AQL": se2.cached_pricefm_test_AQL.astype(float),
    })
    se2_rows["delta_AQL_candidate_minus_current"] = se2_rows.AQL - se2_rows.current_authoritative_qdesn_AQL
    se2_rows["delta_AQL_candidate_minus_pricefm"] = se2_rows.AQL - se2_rows.cached_pricefm_AQL
    complete = pd.concat([candidate, se2_rows], ignore_index=True, sort=False).sort_values(["region", "fold"])
    expected = set(zip(authority.region.astype(str), authority.fold.astype(int)))
    observed = set(zip(complete.region.astype(str), complete.fold.astype(int)))
    if len(complete) != 114 or observed != expected or complete.duplicated(["region", "fold"]).any():
        raise RuntimeError("R97 candidate surface does not align exactly with the 114-case authority")
    comparison = complete.merge(
        authority[["region", "fold", "qdesn_AQL", "pricefm_AQL"]],
        on=["region", "fold"], how="left", validate="one_to_one",
    )
    if not np.allclose(
        comparison.current_authoritative_qdesn_AQL.astype(float),
        comparison.qdesn_AQL.astype(float), rtol=0, atol=1e-12,
    ):
        raise RuntimeError("R97 per-case current-QDESN comparators differ from R92")
    if not np.allclose(
        comparison.cached_pricefm_AQL.astype(float),
        comparison.pricefm_AQL.astype(float), rtol=0, atol=1e-12,
    ):
        raise RuntimeError("R97 per-case cached-PriceFM comparators differ from R92")
    finite = complete[["AQL", "current_authoritative_qdesn_AQL", "cached_pricefm_AQL"]].apply(pd.to_numeric, errors="coerce")
    if not np.isfinite(finite.to_numpy()).all():
        raise RuntimeError("R97 complete surface contains non-finite AQL values")
    candidate_mean = float(finite.AQL.mean())
    authority_mean = float(finite.current_authoritative_qdesn_AQL.mean())
    pricefm_mean = float(finite.cached_pricefm_AQL.mean())
    frozen = campaign["frozen_comparator_values"]
    if not np.isclose(authority_mean, float(frozen["current_authoritative_qdesn_mean_AQL"]), rtol=0, atol=1e-12):
        raise RuntimeError("R97 current-authority mean differs from its predeclared value")
    if not np.isclose(pricefm_mean, float(frozen["cached_pricefm_mean_AQL"]), rtol=0, atol=1e-12):
        raise RuntimeError("R97 cached-PriceFM mean differs from its predeclared value")
    promoted = candidate_mean < authority_mean
    output, quarantined = prepare_empty_directory(
        args.output_dir,
        quarantine_root=args.quarantine_root or args.output_dir.parent / "quarantine",
        reason="replaced_r97_global_closeout", allow_quarantine=args.quarantine_existing,
    )
    surface_path = output / "pricefm_stage_r97_complete_surface.csv"
    complete.to_csv(surface_path, index=False)
    region_summary = complete.groupby("region", as_index=False).agg(
        candidate_mean_AQL=("AQL", "mean"),
        current_authoritative_mean_AQL=("current_authoritative_qdesn_AQL", "mean"),
        cached_pricefm_mean_AQL=("cached_pricefm_AQL", "mean"),
    )
    region_summary["candidate_minus_current"] = region_summary.candidate_mean_AQL - region_summary.current_authoritative_mean_AQL
    region_summary["candidate_minus_pricefm"] = region_summary.candidate_mean_AQL - region_summary.cached_pricefm_mean_AQL
    region_path = output / "pricefm_stage_r97_region_diagnostics.csv"
    region_summary.to_csv(region_path, index=False)
    decision = pd.DataFrame([
        {"surface": "R97_complete_region_specific_challenger", "cases": 114, "mean_AQL": candidate_mean},
        {"surface": "R92_current_authoritative_QDESN", "cases": 114, "mean_AQL": authority_mean},
        {"surface": "cached_PriceFM", "cases": 114, "mean_AQL": pricefm_mean},
    ])
    decision_path = output / "pricefm_stage_r97_global_mean_decision.csv"
    decision.to_csv(decision_path, index=False)
    summary = {
        "status": "completed_global_surface_closeout",
        "stage": "R97", "cases": 114, "regions": 38, "folds": 3,
        "aggregation": "unweighted_arithmetic_mean_over_exactly_114_region_fold_cases",
        "candidate_mean_AQL": candidate_mean,
        "current_authoritative_qdesn_mean_AQL": authority_mean,
        "cached_pricefm_mean_AQL": pricefm_mean,
        "candidate_minus_current_mean_AQL": candidate_mean - authority_mean,
        "candidate_minus_pricefm_mean_AQL": candidate_mean - pricefm_mean,
        "complete_surface_promotion_gate_passed": promoted,
        "per_case_dual_comparator_veto_used": False,
        "test_driven_case_mixing_used": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "quarantined_previous_output": str(quarantined) if quarantined else None,
        "outputs": {
            "complete_surface": str(surface_path), "region_diagnostics": str(region_path),
            "global_mean_decision": str(decision_path),
        },
    }
    atomic_write_json(output / "summary.json", summary)
    pd.DataFrame([*evidence, file_record(surface_path, "complete_surface"), file_record(region_path, "region_diagnostics"), file_record(decision_path, "global_mean_decision")]).to_csv(
        output / "source_manifest.csv", index=False,
    )
    (output / "pricefm_stage_r97_global_closeout.md").write_text(
        "# PriceFM Stage-R97 complete-surface closeout\n\n"
        f"The region-specific challenger mean AQL is `{candidate_mean:.9f}` over all 114 cases. "
        f"The frozen current Q-DESN mean is `{authority_mean:.9f}` and cached PriceFM is "
        f"`{pricefm_mean:.9f}`. The predeclared complete-surface promotion gate "
        f"{'passed' if promoted else 'did not pass'}. Individual cases were not used as vetoes "
        "or for test-driven replacement. Registry and article mutation remain blocked.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
