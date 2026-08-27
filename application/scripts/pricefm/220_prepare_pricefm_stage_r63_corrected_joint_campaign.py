#!/usr/bin/env python3
"""Prepare the bounded validation-only Stage-R63 corrected joint campaign."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R62 = DATA / "authoritative/pricefm_stage_r62_matched_seven_quantile_authority_20260827"
R57_GRID = DATA / "experiment_grids/pricefm_stage_r57_joint_vb_20260824"
GRID = DATA / "experiment_grids/pricefm_stage_r63_corrected_joint_campaign_20260827"
RUNS = DATA / "runs/pricefm_stage_r63_corrected_joint_campaign_20260827"
OUTPUT = DATA / "authoritative/pricefm_stage_r63_corrected_joint_campaign_prep_20260827"
PYTHON = DATA / "venv/bin/python"
METHODS = {"al": "qdesn_al_rhs_ns_exact_chunked", "exal": "qdesn_exal_rhs_ns_exact_chunked"}
SEVERE_ARMS = ("joint_safe_tau_start", "training_only_independent_quantiles", "innovation_tau0_strong_0p0005")


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[3])
    p.add_argument("--r62-dir", type=Path, default=R62)
    p.add_argument("--r57-grid-dir", type=Path, default=R57_GRID)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--python-bin", type=Path, default=PYTHON)
    p.add_argument("--max-iter", type=int, default=150)
    p.add_argument("--tol", type=float, default=1e-4)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            h.update(block)
    return h.hexdigest()


def prepare(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(path)
    path.mkdir(parents=True, exist_ok=True)


def arm_spec(arm_id: str, family: str) -> dict:
    safe = {"anchor_tau0": 0.001, "innovation_tau0": 0.001, "anchor_init_tau": 1.0,
            "innovation_init_tau": 0.05, "freeze_iters": 5, "vb_inner": 5}
    specs = {
        "corrected_family_replay": ("corrected_seven_quantile_likelihood_family", "controlled_cold", safe, 1),
        "joint_safe_tau_start": ("parameterization_aware_rhs_initialization", "controlled_cold", safe, 2),
        "training_only_independent_quantiles": ("bad_joint_coefficient_basin", "training_only_independent_quantiles", safe, 3),
        "innovation_tau0_strong_0p0005": ("stronger_cross_quantile_shrinkage", "controlled_cold", {**safe, "innovation_tau0": 0.0005}, 4),
    }
    question, initialization, rhs, rank = specs[arm_id]
    return {"arm_id": arm_id, "question": question, "likelihood_family": family,
            "initialization_mode": initialization, "rhs_control": rhs, "complexity_rank": rank}


def selected_arms(queues: pd.DataFrame, corrections: pd.DataFrame) -> pd.DataFrame:
    corrected = corrections.merge(queues, on=["case_id", "region", "fold"], validate="one_to_one")
    corrected = corrected[~corrected.mechanism_queue.eq("existing_joint_validation_win")]
    rows = [{"case_id": row.case_id, "arm_id": "corrected_family_replay",
             "target_family": row.corrected_seven_quantile_family, "target_reason": "losing_family_correction"}
            for row in corrected.itertuples(index=False)]
    severe = queues[
        queues.mechanism_queue.eq("severe_loss_gt_5pct")
        & queues.joint_likelihood_family.eq(queues.independent_selected_family)
    ]
    for row in severe.itertuples(index=False):
        for arm_id in SEVERE_ARMS:
            rows.append({"case_id": row.case_id, "arm_id": arm_id,
                         "target_family": row.independent_selected_family,
                         "target_reason": "severe_same_family_mechanism"})
    return pd.DataFrame(rows)


def spec_hash(smoke: dict, runtime: dict) -> str:
    adapter = copy.deepcopy(smoke["adapter"]); adapter.pop("output_dir", None)
    payload = {"region": smoke["region"], "fold": int(smoke["fold"]), "adapter": adapter,
               "feature_policy": smoke["feature_policy"], "quantiles": runtime["quantiles"],
               "likelihood_family": runtime["likelihood_family"], "rhs_control": runtime["rhs_control"],
               "initialization": runtime["initialization"]}
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def run(args: argparse.Namespace) -> dict:
    if args.max_iter < 50 or args.tol <= 0:
        raise ValueError("Invalid fit controls")
    source_root = args.source_root.resolve(); grid = args.grid_dir.resolve(); runs = args.run_dir.resolve(); output = args.output_dir.resolve()
    prepare(grid, args.force); prepare(output, args.force); runs.mkdir(parents=True, exist_ok=True)
    queues = pd.read_csv(args.r62_dir / "pricefm_stage_r62_mechanism_queues.csv")
    corrections = pd.read_csv(args.r62_dir / "pricefm_stage_r62_family_corrections.csv")
    summary = json.loads((args.r62_dir / "summary.json").read_text())
    if summary.get("status") != "completed_full_matched_seven_quantile_authority" or summary.get("matched_cells") != 114:
        raise RuntimeError("R62 full authority is not frozen")
    if summary.get("test_opened", True) or summary.get("provenance_conflict_cells") != 0:
        raise RuntimeError("R62 firewall or provenance gate failed")
    targets = selected_arms(queues, corrections)
    if len(targets) != 38 or targets.case_id.nunique() != 30:
        raise RuntimeError(f"Unexpected bounded target surface: {len(targets)} arms / {targets.case_id.nunique()} cells")
    old_manifest = pd.read_csv(args.r57_grid_dir / "launch_manifest.csv").set_index("case_id")
    queue_by_case = queues.set_index("case_id")
    launch_rows, source_rows = [], []
    for target in targets.sort_values(["case_id", "arm_id"]).itertuples(index=False):
        source = old_manifest.loc[target.case_id]
        old_runtime_path = Path(source.config); old_smoke_path = Path(source.smoke_config)
        old_runtime = yaml.safe_load(old_runtime_path.read_text())["pricefm_stage_r57_joint_vb"]
        smoke = copy.deepcopy(yaml.safe_load(old_smoke_path.read_text())["pricefm_desn_smoke"])
        arm = arm_spec(target.arm_id, target.target_family)
        arm_case = f"{target.case_id}__r63__{target.arm_id}"
        adapter_dir = runs / arm_case / "adapter"; model_dir = runs / arm_case / "model"
        smoke_path = grid / "configs/adapter" / f"{arm_case}.yaml"
        runtime_path = grid / "configs/joint_vb" / f"{arm_case}.yaml"
        smoke_path.parent.mkdir(parents=True, exist_ok=True); runtime_path.parent.mkdir(parents=True, exist_ok=True)
        smoke["splits"] = ["train", "val"]
        smoke["adapter"]["output_dir"] = str(adapter_dir); smoke["run"]["output_dir"] = str(model_dir)
        smoke_path.write_text(yaml.safe_dump({"pricefm_desn_smoke": smoke}, sort_keys=False))
        runtime = {
            "stage": "R63", "case_id": arm_case, "source_case_id": target.case_id,
            "arm_id": arm["arm_id"], "region": str(queue_by_case.loc[target.case_id].region),
            "fold": int(queue_by_case.loc[target.case_id].fold), "likelihood_family": arm["likelihood_family"],
            "method_id": f"joint_qdesn_{arm['likelihood_family']}_rhs_ns_vb_r63_{arm['arm_id']}",
            "vb_method_id": "AL_joint_cavi" if arm["likelihood_family"] == "al" else "VB1_structured_v",
            "source_method_id": METHODS[arm["likelihood_family"]],
            "source_experiment_id": old_runtime["source_experiment_id"],
            "source_config": old_runtime["source_config"], "source_config_sha256": old_runtime["source_config_sha256"],
            "smoke_config": str(smoke_path), "adapter_dir": str(adapter_dir), "output_dir": str(model_dir),
            "source_root": str(source_root), "python_bin": str(args.python_bin.absolute()),
            "adapter_builder": str(source_root / "application/scripts/pricefm/07_build_desn_direct_horizon_adapter.py"),
            "summarizer": str(source_root / "application/scripts/pricefm/09_summarize_desn_model_smoke.py"),
            "allowed_splits": ["train", "val"], "test_access_authorized": False,
            "quantiles": list(map(float, old_runtime["quantiles"])), "rhs_control": arm["rhs_control"],
            "initialization": {"mode": arm["initialization_mode"]}, "inherit_al_bootstrap_rhs": True,
            "a_sigma": float(old_runtime["a_sigma"]), "b_sigma": float(old_runtime["b_sigma"]),
            "max_iter": int(args.max_iter), "tol": float(args.tol),
            "max_dense_dim": int(old_runtime["max_dense_dim"]),
            "registry_mutation_authorized": False, "article_mutation_authorized": False,
        }
        runtime_path.write_text(yaml.safe_dump({"pricefm_stage_r61_joint_mechanism": runtime}, sort_keys=False))
        q = queue_by_case.loc[target.case_id]
        launch_rows.append({
            "case_id": arm_case, "source_case_id": target.case_id, "region": q.region, "fold": int(q.fold),
            "arm_id": arm["arm_id"], "question": arm["question"], "target_reason": target.target_reason,
            "likelihood_family": arm["likelihood_family"], "method_id": runtime["method_id"],
            "initialization_mode": arm["initialization_mode"], "adapter_variant": "authority",
            "complexity_rank": arm["complexity_rank"], "config": str(runtime_path), "smoke_config": str(smoke_path),
            "output_dir": str(model_dir), "scientific_spec_sha256": spec_hash(smoke, runtime),
            "independent_validation_AQL": float(q.independent_seven_quantile_validation_AQL),
            "old_joint_validation_AQL": float(q.joint_contract_validation_AQL),
            "launch_authorized": False, "test_access_authorized": False,
            "registry_mutation_authorized": False, "article_mutation_authorized": False,
            "status": "prepared_validation_only_not_launched",
        })
        for label, path in (("runtime_config", runtime_path), ("adapter_config", smoke_path)):
            source_rows.append({"case_id": arm_case, "label": label, "path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size})
    manifest = pd.DataFrame(launch_rows)
    manifest.to_csv(grid / "launch_manifest.csv", index=False)
    targets.to_csv(output / "pricefm_stage_r63_target_arm_ledger.csv", index=False)
    queues[~queues.case_id.isin(targets.case_id)].to_csv(output / "pricefm_stage_r63_hold_rows.csv", index=False)
    gates = pd.DataFrame([
        {"gate": "r62_full_surface", "passed": True, "observed": 114},
        {"gate": "bounded_38_arms_30_cells", "passed": len(manifest) == 38 and manifest.source_case_id.nunique() == 30, "observed": len(manifest)},
        {"gate": "current_joint_wins_excluded", "passed": not set(queues.loc[queues.mechanism_queue.eq("existing_joint_validation_win"), "case_id"]) & set(manifest.source_case_id), "observed": 12},
        {"gate": "all_losing_family_corrections_covered", "passed": (manifest.target_reason == "losing_family_correction").sum() == 26, "observed": int((manifest.target_reason == "losing_family_correction").sum())},
        {"gate": "same_family_severe_three_arms", "passed": (manifest.target_reason == "severe_same_family_mechanism").sum() == 12, "observed": int((manifest.target_reason == "severe_same_family_mechanism").sum())},
        {"gate": "validation_only", "passed": not manifest.test_access_authorized.any(), "observed": "train,val"},
        {"gate": "launch_registry_article_blocked", "passed": not manifest.launch_authorized.any(), "observed": "blocked"},
    ])
    if not gates.passed.all(): raise RuntimeError(gates.loc[~gates.passed].to_dict("records"))
    gates.to_csv(output / "pricefm_stage_r63_prelaunch_gates.csv", index=False)
    source_rows.extend({"case_id": "ALL", "label": "r62_evidence", "path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size}
                       for path in (args.r62_dir / "summary.json", args.r62_dir / "pricefm_stage_r62_mechanism_queues.csv", args.r62_dir / "pricefm_stage_r62_family_corrections.csv"))
    pd.DataFrame(source_rows).to_csv(output / "source_manifest.csv", index=False)
    result = {"status": "prepared_r63_not_launched", "target_cells": 30, "prepared_arms": 38,
              "family_replay_arms": 26, "severe_mechanism_arms": 12, "test_opened": False,
              "launch_authorized": False, "registry_mutation_authorized": False,
              "article_mutation_authorized": False, "source_head": subprocess.check_output(["git", "-C", str(source_root), "rev-parse", "HEAD"], text=True).strip()}
    write_json(output / "summary.json", result)
    return result


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
