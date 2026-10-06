#!/usr/bin/env python3
"""Prepare the bounded R122 Stage-0B complete AL proxy confirmation."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import platform
import sys

import pandas as pd

from pricefm_common import sha256_file, write_json


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
TAG = "pricefm_stage_r122_stage0b_complete_proxy_confirmation_20260930"
R121B_TAG = "pricefm_stage_r121b_bg_targeted_dense_refinement_repair_20260928"
AUDIT_TAG = "pricefm_stage_r122_stage0a_predictive_stability_audit_20260930"
EVALUATION_TAG = "pricefm_stage_r122_evaluation_contract_20260930"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    value.add_argument("--output-dir", type=Path)
    value.add_argument("--campaign-root", type=Path)
    return value


def build_ladder_manifest(r121b: Path, shortlist: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for candidate in shortlist.itertuples(index=False):
        for split in (1, 2, 3):
            root = r121b / f"al_internal/{candidate.candidate_id}/split={split}"
            source_contract = root / "quantiles/contracts/tau=0.50.json"
            if not source_contract.is_file() or not (root / "design/terminal.json").is_file():
                raise FileNotFoundError(f"missing R121B frozen ladder source: {candidate.candidate_id} split {split}")
            source = json.loads(source_contract.read_text())
            rows.append({"candidate_id": str(candidate.candidate_id), "split": split,
                         "tau0": float(candidate.tau0), "design_dir": str((root / "design").resolve()),
                         "normal_parent_dir": str(Path(source["parent_dir"]).resolve()),
                         "source_median_contract": str(source_contract.resolve()),
                         "posterior_target_design_sha256": sha256_file(root / "design/terminal.json")})
    result = pd.DataFrame(rows).sort_values(["candidate_id", "split"]).reset_index(drop=True)
    if len(result) != 9 or result.candidate_id.nunique() != 3:
        raise RuntimeError("R122 Stage-0B requires exactly three candidates by three splits")
    return result


def run(args: argparse.Namespace) -> dict[str, object]:
    artifact, code = args.artifact_repo.resolve(), args.code_root.resolve()
    data = artifact / "application/data_local/pricefm"
    output = (args.output_dir or data / "launch_prep" / TAG).resolve()
    campaign = (args.campaign_root or data / "campaigns" / TAG).resolve()
    if output.exists() and any(output.iterdir()):
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    r121b = data / "campaigns" / R121B_TAG
    r121b_prep = data / "launch_prep" / R121B_TAG
    audit = json.loads((data / "campaigns" / AUDIT_TAG / "terminal.json").read_text())
    evaluation = json.loads((data / "launch_prep" / EVALUATION_TAG / "summary.json").read_text())
    source_terminal = json.loads((r121b / "campaign_terminal.json").read_text())
    if audit.get("status") != "R122_STAGE0A_PREDICTIVE_STABILITY_PASS" or audit.get("frozen_final_cap") != 1000:
        raise RuntimeError("R122 Stage-0A fitted-function stability has not passed")
    if evaluation.get("status") != "R122_EVALUATION_CONTRACT_READY":
        raise RuntimeError("R122 evaluation contract is not ready")
    if source_terminal.get("test_opened") is not False:
        raise RuntimeError("R121B source violated the test firewall")

    shortlist_path = r121b / "imported_screening/unique_normal_shortlist.csv"
    shortlist = pd.read_csv(shortlist_path)
    ladders = build_ladder_manifest(r121b, shortlist)
    ladders.to_csv(output / "ladder_manifest.csv", index=False)
    shortlist.to_csv(output / "normal_shortlist.csv", index=False)
    r121b_control = json.loads((r121b_prep / "launch_control.json").read_text())
    control = {
        "stage": "R122_stage0B", "tag": TAG, "status": "prepared_not_launched",
        "campaign_root": str(campaign), "r121b_campaign": str(r121b),
        "r121b_prep": str(r121b_prep), "evaluation_contract": str(data / "launch_prep" / EVALUATION_TAG / "evaluation_contract.json"),
        "stage0a_audit": str(data / "campaigns" / AUDIT_TAG / "terminal.json"),
        "rscript": r121b_control["rscript"], "cran_library": r121b_control["cran_library"],
        "cran_manifest": r121b_control["cran_manifest"], "runtime_processed": r121b_control["runtime_processed"],
        "python_executable": str(Path(sys.executable).absolute()), "python_prefix": str(Path(sys.prefix).absolute()),
        "python_version": platform.python_version(),
        "workers": 9, "final_max_iter": 1000, "diagnostic_companion_max_iter": 750,
        "final_fit_count": 63, "maximum_conditional_companion_count": 63,
        "minimum_memory_gib": 200, "minimum_free_gib": 180,
        "test_access_authorized": False, "article_mutation_authorized": False,
        "registry_mutation_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False, "exal_authorized": False,
    }
    write_json(output / "launch_control.json", control)
    sources = [Path(__file__).resolve(), SCRIPT_DIR / "427_run_pricefm_stage_r122_stage0b.py",
               SCRIPT_DIR / "424_audit_pricefm_stage_r122_calibration_geometry.py",
               SCRIPT_DIR / "420_fit_pricefm_stage_r121_quantile_atom.R",
               SCRIPT_DIR / "pricefm_r122_engine.py", SCRIPT_DIR / "pricefm_r120_engine.py",
               SCRIPT_DIR / "418_run_pricefm_stage_r121_targeted_dense_refinement.py",
               Path(control["evaluation_contract"]), Path(control["stage0a_audit"]),
               shortlist_path, r121b / "campaign_terminal.json"]
    for row in ladders.itertuples(index=False):
        sources.extend([Path(row.design_dir) / "terminal.json", Path(row.normal_parent_dir) / "terminal.json",
                        Path(row.source_median_contract)])
    source_frame = pd.DataFrame([{"path": str(path.resolve()), "sha256": sha256_file(path)} for path in sources]).drop_duplicates("path")
    source_frame.to_csv(output / "source_manifest.csv", index=False)
    checks = {
        "stage0a_predictive_stability_pass": audit["passed"] is True,
        "evaluation_contract_ready": evaluation["status"] == "R122_EVALUATION_CONTRACT_READY",
        "three_candidates_nine_ladders": len(ladders) == 9 and ladders.candidate_id.nunique() == 3,
        "source_test_firewall": source_terminal["test_opened"] is False,
        "one_common_final_cap": control["final_max_iter"] == 1000,
        "all_sources_present": all(Path(path).is_file() for path in source_frame.path),
    }
    write_json(output / "preparation_gates.json", {"status": "passed" if all(checks.values()) else "failed", "checks": checks})
    if not all(checks.values()):
        raise RuntimeError(f"R122 Stage-0B preparation failed: {checks}")
    summary = {**control, "status": "prepared_r122_stage0b_complete_proxy_confirmation",
               "source_manifest_sha256": sha256_file(output / "source_manifest.csv"),
               "ladder_manifest_sha256": sha256_file(output / "ladder_manifest.csv")}
    write_json(output / "summary.json", summary)
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True)); return 0


if __name__ == "__main__":
    raise SystemExit(main())
