#!/usr/bin/env python3
"""Prepare the gated, training-only PriceFM Stage R121 campaign."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from typing import Any

import numpy as np
import pandas as pd

from pricefm_common import sha256_file, write_json
from pricefm_r121_engine import (
    R120_TAG, TAG, candidate_manifest, collapse_rhs, select_anchors,
    select_bridge_panel,
)


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    value.add_argument("--output-dir", type=Path)
    value.add_argument("--campaign-root", type=Path)
    value.add_argument("--workers", type=int, choices=(5, 10, 15), default=10)
    value.add_argument("--cpu-list", required=True)
    value.add_argument("--run-tag")
    value.add_argument("--screening-prep-dir", type=Path)
    value.add_argument("--screening-campaign-root", type=Path)
    value.add_argument("--screening-source-commit")
    value.add_argument("--force", action="store_true")
    return value


def _r120_paths(data: Path) -> tuple[Path, Path]:
    return data / "launch_prep" / R120_TAG, data / "campaigns" / R120_TAG


def _source_specs(r120_prep: Path, r120_campaign: Path) -> pd.DataFrame:
    paths = [
        r120_campaign / "stage_c/pricefm_stage_r120c_candidate_manifest.csv",
        r120_campaign / "stage_c/pricefm_stage_r120c_seed_manifest.csv",
        r120_prep / "pricefm_stage_r120b_candidate_manifest.csv",
    ]
    frames = [pd.read_csv(path) for path in paths if path.is_file()]
    if not frames:
        raise FileNotFoundError("R121 cannot locate the R120 candidate manifests")
    return pd.concat(frames, ignore_index=True).drop_duplicates("candidate_id", keep="first")


def _audit_r120(r120_prep: Path, r120_campaign: Path) -> dict[str, Any]:
    terminal_path = r120_campaign / "campaign_terminal.json"
    terminal = json.loads(terminal_path.read_text())
    required = {
        "terminal_status": terminal.get("status") == "completed_bg_pilot_not_promoted",
        "test_closed": terminal.get("test_opened") is False,
        "registry_closed": terminal.get("registry_mutated") is False,
        "article_closed": terminal.get("article_mutated") is False,
        "rhs_closeout": (r120_campaign / "stage_d/closeout/ranking.csv").is_file(),
        "source_manifest": (r120_prep / "source_manifest.csv").is_file(),
    }
    frozen_sources = pd.read_csv(r120_prep / "source_manifest.csv")
    source_hashes = all(Path(row.path).is_file() and sha256_file(Path(row.path)) == str(row.sha256)
                        for row in frozen_sources.itertuples(index=False))
    # R120 has an audited controller repair recorded separately. Its source hash
    # exception remains R120 provenance and is not inherited by R121.
    if not source_hashes and (r120_prep / "gate_repair_manifest.json").is_file():
        repair = json.loads((r120_prep / "gate_repair_manifest.json").read_text())
        source_hashes = repair.get("status") == "prepared_r120_quantile_gate_repair"
    required["r120_source_provenance"] = source_hashes
    if not all(required.values()):
        raise RuntimeError(f"R121 R120 terminal audit failed: {required}")
    return {
        "status": "completed_r121_r120_terminal_audit", "checks": required,
        "r120_terminal_path": str(terminal_path), "r120_terminal_sha256": sha256_file(terminal_path),
        "r120_three_fold_mean_AQL": terminal.get("three_fold_mean_AQL"), "test_opened": False,
    }


def _comparator_ledger(data: Path, r120_campaign: Path) -> pd.DataFrame:
    comparison = data / "figures/pricefm_stage_r111d_bg_recursive_authority_comparison_20260923/metrics.csv"
    metrics = pd.read_csv(comparison)
    rows = [{
        "source_path": str(comparison), "source_sha256": sha256_file(comparison),
        "method": str(row.method), "forecast_operator": "r111d_matched_recursive_authority_asset",
        "region": "BG", "fold": int(row.fold), "AQL": float(row.AQL),
        "coverage_10_90": float(row.coverage_10_90), "mean_width_10_90": float(row.mean_width_10_90),
        "origin_count": int(row.n_origins), "loss_atom_count": int(row.n_loss_atoms),
        "scale": "original", "quantiles": "0.10,0.25,0.45,0.50,0.55,0.75,0.90",
        "role": "external_benchmark" if row.method == "pricefm" else "matched_scientific_reference",
        "allowed_use": "reporting_and_frozen_outer_gate_context", "test_opened": False,
    } for row in metrics.itertuples(index=False) if int(row.fold) in (0, 1, 2, 3)]
    r120_metrics = pd.read_csv(r120_campaign / "stage_f/frozen_choice_metrics.csv")
    for row in r120_metrics.itertuples(index=False):
        rows.append({
            "source_path": str(r120_campaign / "stage_f/frozen_choice_metrics.csv"),
            "source_sha256": sha256_file(r120_campaign / "stage_f/frozen_choice_metrics.csv"),
            "method": "r120", "forecast_operator": str(row.operator), "region": "BG", "fold": int(row.fold),
            "AQL": float(row.AQL), "coverage_10_90": float(row.interval_80_coverage),
            "mean_width_10_90": float(row.interval_80_width), "origin_count": -1, "loss_atom_count": -1,
            "scale": "original", "quantiles": "0.10,0.25,0.45,0.50,0.55,0.75,0.90",
            "role": "same_operator_continuation_baseline", "allowed_use": "normal_and_fold1_gates",
            "test_opened": False,
        })
    return pd.DataFrame(rows)


def _screening_import(screening_prep: Path, screening_campaign: Path, candidates: pd.DataFrame,
                      code: Path, source_commit: str) -> tuple[dict[str, Any], pd.DataFrame, pd.DataFrame]:
    """Validate and freeze the reusable pre-AL R121 evidence surface."""
    required = [
        screening_prep / "summary.json", screening_prep / "source_manifest.csv",
        screening_prep / "candidate_manifest.csv", screening_campaign / "bridge/terminal.json",
        screening_campaign / "ridge/primary_progress.json", screening_campaign / "ridge/seed_progress.json",
        screening_campaign / "ridge/primary_ranking.csv", screening_campaign / "ridge/robust_ranking.csv",
        screening_campaign / "rhs/center/cell_metrics.csv", screening_campaign / "rhs/pilot/cell_metrics.csv",
        screening_campaign / "rhs/tau_activation.json", screening_campaign / "rhs/closeout/ranking.csv",
        screening_campaign / "rhs/closeout/normal_gates.csv",
    ]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise FileNotFoundError(f"R121 screening import is incomplete: {missing}")
    bridge = json.loads((screening_campaign / "bridge/terminal.json").read_text())
    primary = json.loads((screening_campaign / "ridge/primary_progress.json").read_text())
    seed = json.loads((screening_campaign / "ridge/seed_progress.json").read_text())
    tau = json.loads((screening_campaign / "rhs/tau_activation.json").read_text())
    old_candidates = pd.read_csv(screening_prep / "candidate_manifest.csv")
    same_candidates = sorted(old_candidates.semantic_sha256.astype(str)) == sorted(candidates.semantic_sha256.astype(str))
    frozen_sources = pd.read_csv(screening_prep / "source_manifest.csv")
    resolved_commit = subprocess.check_output(
        ["git", "-C", str(code), "rev-parse", f"{source_commit}^{{commit}}"], text=True).strip()
    reconstructed = []
    recorded_documents = []
    for row in frozen_sources.itertuples(index=False):
        raw_path = str(row.path)
        if "/application/" in raw_path:
            relative = "application/" + raw_path.split("/application/", 1)[1]
            content = subprocess.check_output(["git", "-C", str(code), "show", f"{resolved_commit}:{relative}"])
            reconstructed.append(hashlib.sha256(content).hexdigest() == str(row.sha256))
        elif "/local_trackers/" in raw_path:
            recorded_documents.append({"path": raw_path, "sha256": str(row.sha256)})
        else:
            raise RuntimeError(f"R121 cannot map frozen source path: {raw_path}")
    source_commit_valid = bool(reconstructed) and all(reconstructed)
    gates = pd.read_csv(screening_campaign / "rhs/closeout/normal_gates.csv")
    centers = pd.read_csv(screening_campaign / "rhs/center/cell_metrics.csv")
    selected = []
    for candidate_id in gates[gates.passed.astype(bool)].candidate_id.astype(str).drop_duplicates():
        center = centers[centers.candidate_id.astype(str).eq(candidate_id)]
        levels = np.unique(center.tau0.astype(float))
        if len(levels) != 1 or set(center.split.astype(int)) != {1, 2, 3}:
            continue
        rows = gates[gates.candidate_id.astype(str).eq(candidate_id) & gates.passed.astype(bool)]
        rows = rows[np.isclose(rows.tau0.astype(float), float(levels[0]), rtol=1e-10, atol=0)]
        if rows.empty:
            continue
        selected.append(rows.iloc[0])
        if len(selected) == 3:
            break
    shortlist = pd.DataFrame([row.to_dict() for row in selected])
    if len(shortlist) != 3 or shortlist.candidate_id.astype(str).duplicated().any():
        raise RuntimeError("R121 screening import cannot construct three unique center-tau candidates")
    parent_files: list[Path] = []
    parent_valid = True
    for row in shortlist.itertuples(index=False):
        for split in (1, 2, 3):
            fit = screening_campaign / f"rhs/center/fits/{row.candidate_id}_s{split}_t{float(row.tau0):.8e}"
            terminal = fit / "terminal.json"
            try:
                value = json.loads(terminal.read_text())
            except (OSError, json.JSONDecodeError):
                parent_valid = False
                continue
            parent_valid = parent_valid and value.get("status") == "completed_recursive_normal_fit" \
                and value.get("converged") is True and value.get("test_opened") is False
            parent_files.extend(path for path in fit.rglob("*") if path.is_file())
    checks = {
        "bridge_passed": bridge.get("passed") is True and bridge.get("test_opened") is False,
        "primary_complete": primary.get("complete") == primary.get("total") == 1200 and primary.get("failed") == 0,
        "seed_complete": seed.get("complete") == seed.get("total") == 400 and seed.get("failed") == 0,
        "tau_inactive": tau.get("active") is False and tau.get("test_opened") is False,
        "candidate_surface_identical": same_candidates,
        "source_commit_reconstructs_executable_manifest": source_commit_valid,
        "historical_plan_hash_recorded": len(recorded_documents) == 1 and bool(recorded_documents[0]["sha256"]),
        "three_unique_center_candidates": len(shortlist) == 3,
        "normal_parents_valid": parent_valid and len(parent_files) > 0,
    }
    if not all(checks.values()):
        raise RuntimeError(f"R121 screening import audit failed: {checks}")
    paths = sorted(set(required + parent_files), key=str)
    manifest = pd.DataFrame([{"path": str(path.resolve()), "sha256": sha256_file(path),
                              "bytes": path.stat().st_size} for path in paths])
    audit = {"status": "completed_r121b_screening_import_audit", "checks": checks,
             "source_prep": str(screening_prep.resolve()), "source_campaign": str(screening_campaign.resolve()),
             "source_commit": resolved_commit,
             "recorded_non_executable_sources": recorded_documents,
             "imported_candidate_count": 3, "imported_file_count": len(manifest),
             "imported_bytes": int(manifest.bytes.sum()), "test_opened": False}
    return audit, shortlist, manifest


def run(args: argparse.Namespace) -> dict[str, Any]:
    artifact = args.artifact_repo.resolve(); code = args.code_root.resolve()
    data = artifact / "application/data_local/pricefm"
    output = (args.output_dir or data / "launch_prep" / TAG).resolve()
    campaign = (args.campaign_root or data / "campaigns" / TAG).resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    r120_prep, r120_campaign = _r120_paths(data)
    audit = _audit_r120(r120_prep, r120_campaign)
    specs = _source_specs(r120_prep, r120_campaign)
    rhs = pd.read_csv(r120_campaign / "stage_d/closeout/ranking.csv")
    complete = collapse_rhs(rhs, specs)
    bridge = select_bridge_panel(complete)
    anchors = select_anchors(complete, bridge)
    candidates, design_summary = candidate_manifest(anchors, maximum=1200)
    bridge.to_csv(output / "bridge_panel.csv", index=False)
    anchors.to_csv(output / "anchor_manifest.csv", index=False)
    candidates.to_csv(output / "candidate_manifest.csv", index=False)
    ledger = _comparator_ledger(data, r120_campaign); ledger.to_csv(output / "comparator_ledger.csv", index=False)
    write_json(output / "r120_terminal_audit.json", audit)

    screening_audit = None
    continuation_values = (args.screening_prep_dir, args.screening_campaign_root, args.screening_source_commit)
    if any(value is not None for value in continuation_values) and not all(value is not None for value in continuation_values):
        raise ValueError("R121 continuation requires screening prep, campaign, and source commit")
    if args.screening_prep_dir is not None:
        screening_audit, shortlist, import_manifest = _screening_import(
            args.screening_prep_dir.resolve(), args.screening_campaign_root.resolve(), candidates,
            code, str(args.screening_source_commit))
        write_json(output / "screening_import_audit.json", screening_audit)
        shortlist.to_csv(output / "imported_normal_shortlist.csv", index=False)
        import_manifest.to_csv(output / "screening_import_manifest.csv", index=False)

    source_paths = [
        Path(__file__).resolve(), SCRIPT_DIR / "pricefm_r121_engine.py",
        SCRIPT_DIR / "418_run_pricefm_stage_r121_targeted_dense_refinement.py",
        SCRIPT_DIR / "419_closeout_pricefm_stage_r121_targeted_dense_refinement.py",
        SCRIPT_DIR / "420_fit_pricefm_stage_r121_quantile_atom.R",
        SCRIPT_DIR / "pricefm_r120_engine.py",
        SCRIPT_DIR / "336_fit_pricefm_stage_r102_recursive_normal.R",
        code / "application/R/pricefm_recursive_normal_fit.R",
        SCRIPT_DIR / "pricefm_stage_r67_cran111_adapter.R",
        code / "local_trackers/pricefm_stage_r121_targeted_dense_refinement_master_plan_20260927.md",
    ]
    missing = [str(path) for path in source_paths if not path.is_file()]
    if missing:
        raise FileNotFoundError(f"R121 source file(s) missing: {missing}")
    pd.DataFrame([{"path": str(path.resolve()), "sha256": sha256_file(path)} for path in source_paths]).to_csv(
        output / "source_manifest.csv", index=False)
    run_tag = str(args.run_tag or campaign.name)
    control = {
        "stage": "R121B" if screening_audit else "R121", "tag": run_tag,
        "status": "prepared_not_launched", "target_region": "BG",
        "workers": int(args.workers), "cpu_list": str(args.cpu_list), "campaign_root": str(campaign),
        "r120_prep": str(r120_prep), "r120_campaign": str(r120_campaign),
        "runtime_processed": str(r120_campaign / "processed"),
        "normal_runtime": str(data / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"),
        "cran_library": str(data / "runtime_libraries/exdqlm_cran_1p1p1"),
        "cran_manifest": str(data / "runtime_libraries/exdqlm_cran_1p1p1/pricefm_r67_cran111_install_manifest.json"),
        "rscript": "/data/jaguir26/local/opt/R/4.6.0/bin/Rscript",
        "quantiles": [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90],
        "quantile_order": [0.50, 0.45, 0.55, 0.25, 0.75, 0.10, 0.90],
        "posterior_paths": 500, "primary_candidates": len(candidates), "seed_top_k": 200,
        "rhs_top_k": 50, "al_shortlist_k": 3, "bridge_candidates": len(bridge),
        "minimum_free_gib": 200, "minimum_memory_gib": 200,
        "test_opened": False, "test_access_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "joint_model_authorized": False, "mcmc_authorized": False, "exal_authorized": False,
        "design_summary": design_summary,
    }
    if screening_audit:
        control.update({"screening_prep": screening_audit["source_prep"],
                        "screening_campaign": screening_audit["source_campaign"],
                        "screening_import_status": screening_audit["status"]})
    write_json(output / "launch_control.json", control)
    gates = {key: bool(value) for key, value in {
        "r120_terminal": audit["status"] == "completed_r121_r120_terminal_audit",
        "bridge_six": len(bridge) == 6 and not bridge.candidate_id.duplicated().any(),
        "anchors_bounded": 1 <= len(anchors) <= 12,
        "candidates_bounded": 100 <= len(candidates) <= 1200,
        "candidate_unique": not candidates.semantic_sha256.duplicated().any(),
        "training_only": not candidates.test_access_authorized.astype(bool).any(),
        "pure_readout": candidates.readout.eq("pure_all_layers").all(),
        "workers": int(args.workers) in (5, 10, 15),
        "screening_import": screening_audit is None or screening_audit["status"] == "completed_r121b_screening_import_audit",
    }.items()}
    write_json(output / "preparation_gates.json", {"status": "passed" if all(gates.values()) else "failed", "checks": gates})
    if not all(gates.values()):
        raise RuntimeError(f"R121 preparation gates failed: {gates}")
    output_names = [
        "bridge_panel.csv", "anchor_manifest.csv", "candidate_manifest.csv", "comparator_ledger.csv",
        "r120_terminal_audit.json", "source_manifest.csv", "launch_control.json", "preparation_gates.json"]
    if screening_audit:
        output_names.extend(["screening_import_audit.json", "imported_normal_shortlist.csv",
                             "screening_import_manifest.csv"])
    hashes = {name: sha256_file(output / name) for name in output_names}
    prepared_status = "prepared_r121b_repair_continuation" if screening_audit else "prepared_r121_gated_campaign"
    summary = {**control, "status": prepared_status, "output_sha256": hashes,
               "launch_authorized": True}
    write_json(output / "summary.json", summary)
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
