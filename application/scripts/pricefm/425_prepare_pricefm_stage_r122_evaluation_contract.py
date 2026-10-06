#!/usr/bin/env python3
"""Freeze the leakage-aware R122 development and retrospective scoring contract."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re

import pandas as pd
import yaml

from pricefm_common import sha256_file, write_json


DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
TAG = "pricefm_stage_r122_evaluation_contract_20260930"
R97_TAG = "pricefm_stage_r97_global_region_frozen_campaign_20260908"
IMPORTED_R97_MANIFEST = "imported_evidence/pricefm_stage_r97_global_region_frozen_campaign_20260908/source_manifest.csv"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--code-root", type=Path, default=Path(__file__).resolve().parents[3])
    value.add_argument("--output-dir", type=Path)
    value.add_argument("--historical-source-manifest", type=Path)
    return value


def run(args: argparse.Namespace) -> dict[str, object]:
    artifact, code = args.artifact_repo.resolve(), args.code_root.resolve()
    data = artifact / "application/data_local/pricefm"
    output = (args.output_dir or data / "launch_prep" / TAG).resolve()
    if output.exists() and any(output.iterdir()):
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    config_path = code / "application/config/pricefm_data_pipeline.yaml"
    config = yaml.safe_load(config_path.read_text())["pricefm"]
    windows = []
    for item in config["splits"]:
        for role in ("train", "val", "test"):
            windows.append({"fold": int(item["fold"]), "role": role,
                            "start": str(item[role][0]), "end": str(item[role][1])})
    pd.DataFrame(windows).to_csv(output / "official_windows.csv", index=False)

    native_r97_manifest = data / "campaigns" / R97_TAG / "global_scoring/closeout/source_manifest.csv"
    imported_r97_manifest = data / IMPORTED_R97_MANIFEST
    r97_manifest = (getattr(args, "historical_source_manifest", None) or
                    (native_r97_manifest if native_r97_manifest.is_file() else imported_r97_manifest)).resolve()
    opened: list[dict[str, object]] = []
    if r97_manifest.is_file():
        source = pd.read_csv(r97_manifest)
        pattern = re.compile(r"runs/region=([^/]+)/fold=(\d+)/score/test_metric\.csv$")
        for row in source.itertuples(index=False):
            path = str(row.path)
            match = pattern.search(path)
            if match:
                opened.append({"region": match.group(1), "fold": int(match.group(2)), "path": path,
                               "artifact_locally_present": Path(path).is_file(),
                               "sha256": str(getattr(row, "sha256", ""))})
    evidence = pd.DataFrame(opened).sort_values(["region", "fold"]) if opened else pd.DataFrame(columns=["region", "fold", "path", "artifact_locally_present", "sha256"])
    evidence.to_csv(output / "historical_test_opening_evidence.csv", index=False)
    complete_regions = int(evidence.groupby("region").fold.nunique().eq(3).sum()) if len(evidence) else 0
    bg_folds_opened = set(evidence[evidence.region.eq("BG")].fold.astype(int)) == {1, 2, 3} if len(evidence) else False
    historical_opened = bool(len(evidence) == 111 and complete_regions == 37 and bg_folds_opened and
                             evidence.sha256.astype(str).str.fullmatch(r"[0-9a-f]{64}").all())

    contract = {
        "stage": "R122", "tag": TAG, "target_region": "BG",
        "status": "R122_EVALUATION_CONTRACT_READY",
        "forecast_semantics": {
            "training": "teacher_forced_observed_target_lags",
            "between_daily_origins": "reset_from_observed_history",
            "within_origin": "recursive_96_quarter_hour_steps",
            "future_target_access_within_path": False,
            "exogenous_inputs": "frozen_application_convention",
        },
        "selection_protocol": {
            "broad_screen": "fold1_training_only_three_expanding_blocked_internal_splits",
            "stage0b_proxy_confirmation": "same_fold1_training_only_internal_splits",
            "shortlist_confirmation": "fold1_official_validation_only_after_internal_shortlist_freeze",
            "global_bg_specification_freeze": "before_any_official_test_score_is_opened_by_r122",
            "fold2_or_fold3_validation_for_specification_selection": False,
            "reason": "later-fold validation windows overlap earlier-fold official test windows",
            "test_selection_access": False,
        },
        "final_scoring_protocol": {
            "specification": "one_BG_specification_frozen_from_development_evidence",
            "refit": "per_fold_using_only_information_available_before_that_fold_test_start",
            "official_test_windows": "scoring_only_no_r122_selection_or_stopping",
            "aggregation": "freeze_before_scoring_then_report_all_folds_and_prespecified_mean",
        },
        "historical_test_status": "HISTORICALLY_OPENED_NOT_PRISTINE" if historical_opened else "UNRESOLVED",
        "historical_test_metric_count": int(len(evidence)),
        "historical_test_metric_expected_count": 111,
        "historical_complete_region_count": complete_regions,
        "historical_authority_scope": "37_regions_by_3_folds_SE_2_excluded",
        "historical_artifacts_locally_present_count": int(evidence.artifact_locally_present.sum()) if len(evidence) else 0,
        "fresh_holdout_available_in_current_snapshot": False,
        "claim_limit": "R122 can be a leakage-firewalled retrospective benchmark, but not a pristine never-observed confirmatory test",
        "prospective_confirmation": "requires a preregistered future period not present in the current snapshot",
        "test_access_authorized_during_selection": False,
        "article_mutation_authorized": False, "registry_mutation_authorized": False,
    }
    write_json(output / "evaluation_contract.json", contract)
    sources = [{"role": "authoritative_data_config", "path": str(config_path), "sha256": sha256_file(config_path)}]
    if r97_manifest.is_file():
        sources.append({"role": "historical_test_source_manifest", "path": str(r97_manifest), "sha256": sha256_file(r97_manifest)})
    pd.DataFrame(sources).to_csv(output / "source_manifest.csv", index=False)
    checks = {
        "three_folds": len(config["splits"]) == 3,
        "nine_official_windows": len(windows) == 9,
        "historical_test_opening_proven_111_hashed_metrics_and_BG_all_folds": historical_opened,
        "no_test_selection_access": contract["selection_protocol"]["test_selection_access"] is False,
        "later_validation_not_used_for_shared_spec": contract["selection_protocol"]["fold2_or_fold3_validation_for_specification_selection"] is False,
        "fresh_holdout_not_overclaimed": contract["fresh_holdout_available_in_current_snapshot"] is False,
    }
    summary = {"status": "R122_EVALUATION_CONTRACT_READY" if all(checks.values()) else "R122_EVALUATION_CONTRACT_UNRESOLVED",
               "checks": checks, "contract_sha256": sha256_file(output / "evaluation_contract.json"),
               "official_windows_sha256": sha256_file(output / "official_windows.csv"),
               "historical_evidence_sha256": sha256_file(output / "historical_test_opening_evidence.csv")}
    write_json(output / "summary.json", summary)
    if not all(checks.values()):
        raise RuntimeError(f"R122 evaluation contract unresolved: {checks}")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True)); return 0


if __name__ == "__main__":
    raise SystemExit(main())
