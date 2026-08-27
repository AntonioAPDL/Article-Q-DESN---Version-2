#!/usr/bin/env python3
"""Prepare exact seven-quantile replays for Stage-R62 coverage gaps."""

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
R57 = DATA / "authoritative/pricefm_stage_r57_joint_authority_freeze_20260824/pricefm_stage_r57_joint_case_authority.csv"
GRID = DATA / "experiment_grids/pricefm_stage_r62_gap_completion_20260827"
RUNS = DATA / "runs/pricefm_stage_r62_gap_completion_20260827"
OUTPUT = DATA / "authoritative/pricefm_stage_r62_gap_completion_prep_20260827"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--r62-dir", type=Path, default=R62)
    p.add_argument("--r57-authority", type=Path, default=R57)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-gaps", type=int, default=6)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def git_head(path: Path) -> str:
    return subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()


def prepare(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(f"Output exists: {path}")
    path.mkdir(parents=True, exist_ok=True)


def tau_slug(tau: float) -> str:
    return ("{:.4g}".format(float(tau))).replace(".", "p")


def scientific_hash(smoke: dict) -> str:
    adapter = smoke["adapter"]
    payload = {
        "region": smoke["region"], "fold": int(smoke["fold"]),
        "feature_policy": smoke["feature_policy"], "data_config": smoke["data_config"],
        "horizons": smoke["horizons"], "quantiles": smoke["quantiles"],
        "adapter": {key: adapter.get(key) for key in (
            "feature_map", "feature_dim", "depth", "units", "alpha", "rho",
            "input_scale", "projection_scale", "recurrent_sparsity", "state_output",
            "seed", "spatial",
        )},
        "rhs_ns": smoke.get("rhs_ns"), "training": smoke.get("training"),
        "qdesn_vb": smoke.get("qdesn_vb"),
    }
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(raw.encode()).hexdigest()


def run(args: argparse.Namespace) -> dict:
    repo = args.artifact_repo.resolve()
    grid = args.grid_dir.resolve()
    runs = args.run_dir.resolve()
    output = args.output_dir.resolve()
    prepare(grid, args.force)
    prepare(output, args.force)
    runs.mkdir(parents=True, exist_ok=True)
    gaps = pd.read_csv(args.r62_dir / "pricefm_stage_r62_exact_coverage_gaps.csv")
    authority = pd.read_csv(args.r57_authority).set_index("case_id")
    if len(gaps) != args.expected_gaps or gaps.match_status.ne("exact_comparator_missing").any():
        raise RuntimeError(f"Expected exactly {args.expected_gaps} unresolved exact-comparator gaps")
    config_dir = grid / "configs/smoke"
    config_dir.mkdir(parents=True, exist_ok=True)
    manifest_rows = []
    source_rows = []
    for gap in gaps.sort_values(["region", "fold"]).itertuples(index=False):
        source = authority.loc[gap.case_id]
        source_path = Path(source.source_config).resolve()
        payload = yaml.safe_load(source_path.read_text())
        original = payload["pricefm_desn_smoke"]
        for tau in TAUS:
            smoke = copy.deepcopy(original)
            case_id = f"r62gap_{str(gap.region).lower()}_f{int(gap.fold)}_tau{tau_slug(tau)}"
            cell = runs / case_id / "cells" / f"region={gap.region}" / f"fold={int(gap.fold)}"
            smoke["splits"] = ["train", "val"]
            smoke["quantiles"] = [float(tau)]
            smoke["adapter"]["output_dir"] = str(cell / "adapter")
            smoke["run"]["output_dir"] = str(cell / "model")
            smoke.setdefault("qdesn_vb", {})["likelihoods"] = ["al", "exal"]
            smoke.setdefault("exact_equivalence", {})["quantile"] = float(tau)
            warm = smoke.setdefault("warm_start", {}).setdefault("qdesn", {})
            warm.setdefault("al", {})["tau_order"] = [float(tau)]
            smoke.setdefault("artifact_hygiene", {})["enabled"] = True
            config_path = config_dir / f"{case_id}.yaml"
            config_path.write_text(yaml.safe_dump({"pricefm_desn_smoke": smoke}, sort_keys=False))
            manifest_rows.append({
                "case_id": case_id, "source_case_id": gap.case_id,
                "region": gap.region, "fold": int(gap.fold), "tau": float(tau),
                "source_likelihood_family": source.likelihood_family,
                "source_config": str(source_path), "source_config_sha256": sha256(source_path),
                "config": str(config_path), "config_sha256": sha256(config_path),
                "scientific_spec_sha256": scientific_hash(smoke),
                "adapter_dir": str(cell / "adapter"), "output_dir": str(cell / "model"),
                "allowed_splits": json.dumps(["train", "val"]),
                "likelihoods": json.dumps(["al", "exal"]),
                "launch_authorized": False, "test_access_authorized": False,
                "registry_mutation_authorized": False, "article_mutation_authorized": False,
                "status": "prepared_exact_gap_completion_not_launched",
            })
            source_rows.append({"path": str(config_path), "sha256": sha256(config_path), "bytes": config_path.stat().st_size})
        source_rows.append({"path": str(source_path), "sha256": sha256(source_path), "bytes": source_path.stat().st_size})
    manifest = pd.DataFrame(manifest_rows)
    manifest_path = grid / "launch_manifest.csv"
    manifest.to_csv(manifest_path, index=False)
    gates = pd.DataFrame([
        {"gate": "exact_gap_count", "passed": gaps.shape[0] == args.expected_gaps, "observed": gaps.shape[0]},
        {"gate": "seven_quantiles_per_gap", "passed": manifest.groupby("source_case_id").size().eq(7).all(), "observed": manifest.shape[0]},
        {"gate": "paper_quantiles_exact", "passed": all(sorted(group.tau.tolist()) == list(TAUS) for _, group in manifest.groupby("source_case_id")), "observed": json.dumps(TAUS)},
        {"gate": "train_validation_only", "passed": manifest.allowed_splits.eq(json.dumps(["train", "val"])).all(), "observed": "train,val"},
        {"gate": "both_likelihoods", "passed": manifest.likelihoods.eq(json.dumps(["al", "exal"])).all(), "observed": "al,exal"},
        {"gate": "launch_and_test_blocked", "passed": (~manifest.launch_authorized & ~manifest.test_access_authorized).all(), "observed": "blocked"},
        {"gate": "no_registry_or_article_mutation", "passed": True, "observed": "blocked"},
    ])
    if not gates.passed.all():
        raise RuntimeError(f"R62 gap prep gates failed: {gates.loc[~gates.passed].to_dict('records')}")
    gates.to_csv(output / "pricefm_stage_r62_gap_completion_gates.csv", index=False)
    pd.DataFrame(source_rows + [
        {"path": str(Path(__file__).resolve()), "sha256": sha256(Path(__file__).resolve()), "bytes": Path(__file__).stat().st_size},
        {"path": str(args.r62_dir.resolve() / "pricefm_stage_r62_exact_coverage_gaps.csv"), "sha256": sha256(args.r62_dir.resolve() / "pricefm_stage_r62_exact_coverage_gaps.csv"), "bytes": (args.r62_dir.resolve() / "pricefm_stage_r62_exact_coverage_gaps.csv").stat().st_size},
    ]).drop_duplicates(["path", "sha256"]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "prepared_exact_gap_completion_not_launched",
        "artifact_repo_head": git_head(repo), "gap_cells": len(gaps),
        "quantile_jobs": len(manifest), "likelihoods_per_job": ["al", "exal"],
        "selection_role": "validation_only_seven_quantile_mean_AQL",
        "launch_authorized": False, "test_opened": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "recommended_action": "cpu_ownership_audit_then_explicit_authorized_background_launch",
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r62_gap_completion_prep_report.md").write_text(
        "# PriceFM Stage-R62 exact-gap completion prep\n\n"
        f"Prepared {len(manifest)} train/validation-only quantile jobs for {len(gaps)} exact coverage gaps. "
        "Every job preserves its region/fold source DESN and information-set contract and fits both AL and exAL. "
        "No job was launched and test, registry, and article access remain blocked.\n"
    )
    return summary


def main() -> int:
    args = parser().parse_args()
    print(json.dumps(run(args), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
