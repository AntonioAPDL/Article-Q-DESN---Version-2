#!/usr/bin/env python3
"""Reconcile R97 host shards and gate the one-time Muscat test scoring stage."""

from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import socket
import sys
from types import SimpleNamespace
from typing import Any

import pandas as pd

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_r97_distributed_contract import (
    controller_lock_available,
    firewall,
    validate_firewall,
    verify_seal,
    write_sealed,
)
from pricefm_region_frozen_contract import file_record, validate_git_identity, verify_file_record


ARTIFACT_ROOT = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA_ROOT = ARTIFACT_ROOT / "application/data_local/pricefm"
TAG = "pricefm_stage_r97_global_region_frozen_campaign_20260908"
CAMPAIGN_ROOT = DATA_ROOT / "campaigns" / TAG
PREP_ROOT = DATA_ROOT / "authoritative" / f"{TAG}_prep"
OUTPUT_ROOT = DATA_ROOT / "authoritative" / f"{TAG}_distributed_closeout"
SCORE_TOKEN = "OPEN_PRICEFM_R97_TEST_ONCE_AFTER_37_REGION_RECONCILIATION"


def load_original_controller():
    path = SCRIPT_DIR / "319_orchestrate_pricefm_stage_r97_global_campaign.py"
    spec = importlib.util.spec_from_file_location("pricefm_r97_original_controller_finalizer", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


ORIGINAL = load_original_controller()


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    sub = value.add_subparsers(dest="command", required=True)
    reconcile = sub.add_parser("reconcile")
    reconcile.add_argument("--muscat-contract", type=Path, required=True)
    reconcile.add_argument("--jerez-contract", type=Path, required=True)
    reconcile.add_argument("--campaign-root", type=Path, default=CAMPAIGN_ROOT)
    reconcile.add_argument("--output-dir", type=Path, default=OUTPUT_ROOT)
    reconcile.add_argument("--force", action="store_true")
    score = sub.add_parser("score")
    score.add_argument("--reconciliation-terminal", type=Path, required=True)
    score.add_argument("--campaign-contract", type=Path, default=PREP_ROOT / "pricefm_stage_r97_campaign_contract.json")
    score.add_argument("--campaign-root", type=Path, default=CAMPAIGN_ROOT)
    score.add_argument("--prep-dir", type=Path, default=PREP_ROOT)
    score.add_argument("--code-root", type=Path, required=True)
    score.add_argument("--workers", type=int, default=20)
    score.add_argument("--cpu-list", default="")
    score.add_argument("--muscat-hostname-prefix", default="muscat")
    score.add_argument("--approval-token", default="")
    return value


def load_shard(path: Path, host: str) -> tuple[dict[str, Any], dict[str, Any]]:
    contract = json.loads(path.read_text())
    verify_seal(contract, "shard_contract_sha256", label=f"R97 {host} shard contract")
    validate_firewall(contract, label=f"R97 {host} shard contract")
    if contract.get("host") != host or contract.get("mode") != "freeze":
        raise RuntimeError(f"R97 {host} shard contract is not a frozen {host} contract")
    terminal_path = Path(contract["campaign_root"]) / "distributed" / host / "shard_terminal.json"
    terminal = json.loads(terminal_path.read_text())
    verify_seal(terminal, "shard_terminal_sha256", label=f"R97 {host} shard terminal")
    validate_firewall(terminal, label=f"R97 {host} shard terminal")
    if terminal.get("status") != "completed_validation_shard":
        raise RuntimeError(f"R97 {host} shard is not complete")
    if terminal.get("regions_assigned") != contract["regions"] or terminal.get("regions_completed") != contract["regions"]:
        raise RuntimeError(f"R97 {host} terminal differs from its region assignment")
    return contract, terminal


def validate_region_closeout(campaign_root: Path, region: str) -> list[dict[str, Any]]:
    root = campaign_root / "region_closeouts" / region
    summary_path = root / "summary.json"
    frozen_path = root / "pricefm_stage_r97_frozen_region_surface.json"
    summary = json.loads(summary_path.read_text())
    frozen = json.loads(frozen_path.read_text())
    if (
        summary.get("status") != "completed_region_validation_surface_frozen"
        or summary.get("region") != region
        or frozen.get("status") != "region_validation_surface_frozen"
        or frozen.get("region") != region
        or frozen.get("test_opened") is not False
        or frozen.get("test_access_authorized") is not False
        or frozen.get("per_fold_or_quantile_family_mixing") is not False
    ):
        raise RuntimeError(f"R97 region closeout is invalid: {region}")
    for name in ("selected_atom_manifest", "validation_metrics", "pipeline_contract"):
        verify_file_record(frozen[name], label=f"R97 {region} {name}")
    selected = pd.read_csv(frozen["selected_atom_manifest"]["path"])
    if len(selected) != 21 or sorted(selected.fold.astype(int).unique()) != [1, 2, 3]:
        raise RuntimeError(f"R97 region selected atom surface is incomplete: {region}")
    return [
        file_record(summary_path, f"{region}_validation_summary"),
        file_record(frozen_path, f"{region}_frozen_surface"),
        frozen["selected_atom_manifest"],
        frozen["validation_metrics"],
    ]


def reconcile(args: argparse.Namespace) -> dict[str, Any]:
    muscat, muscat_terminal = load_shard(args.muscat_contract, "muscat")
    jerez, jerez_terminal = load_shard(args.jerez_contract, "jerez")
    if muscat["checkpoint"]["sha256"] != jerez["checkpoint"]["sha256"]:
        raise RuntimeError("R97 host shards do not share one checkpoint")
    if muscat["assignment"]["sha256"] != jerez["assignment"]["sha256"]:
        raise RuntimeError("R97 host shards do not share one assignment")
    left, right = set(muscat["regions"]), set(jerez["regions"])
    regions = sorted(left | right)
    if left & right or len(regions) != 37:
        raise RuntimeError("R97 host assignments must be disjoint and cover exactly 37 regions")
    if muscat["campaign_root"] != jerez["campaign_root"] or Path(muscat["campaign_root"]).resolve() != args.campaign_root.resolve():
        raise RuntimeError("R97 host shards do not share the authoritative campaign root")
    evidence: list[dict[str, Any]] = []
    for region in regions:
        evidence.extend(validate_region_closeout(args.campaign_root.resolve(), region))
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    evidence_path = output / "pricefm_stage_r97_distributed_validation_evidence.csv"
    pd.DataFrame(evidence).drop_duplicates(["path", "sha256"]).to_csv(evidence_path, index=False)
    payload = {
        "schema_version": 1,
        "stage": "R97-distributed-continuation",
        "status": "completed_37_region_validation_reconciliation_test_still_sealed",
        "regions": regions,
        "region_count": 37,
        "muscat_contract": file_record(args.muscat_contract, "muscat_shard_contract"),
        "jerez_contract": file_record(args.jerez_contract, "jerez_shard_contract"),
        "muscat_terminal": file_record(Path(muscat["campaign_root"]) / "distributed/muscat/shard_terminal.json", "muscat_shard_terminal"),
        "jerez_terminal": file_record(Path(jerez["campaign_root"]) / "distributed/jerez/shard_terminal.json", "jerez_shard_terminal"),
        "validation_evidence": file_record(evidence_path, "37_region_validation_evidence"),
        "global_test_scoring_authorized": False,
        "global_test_scoring_invoked": False,
        "registry_mutated": False,
        "article_mutated": False,
        **firewall(),
    }
    return write_sealed(output / "pricefm_stage_r97_distributed_reconciliation_terminal.json", payload, "reconciliation_sha256")


def score(args: argparse.Namespace) -> dict[str, Any]:
    reconciliation = json.loads(args.reconciliation_terminal.read_text())
    verify_seal(reconciliation, "reconciliation_sha256", label="R97 distributed reconciliation")
    validate_firewall(reconciliation, label="R97 distributed reconciliation")
    if reconciliation.get("status") != "completed_37_region_validation_reconciliation_test_still_sealed":
        raise RuntimeError("R97 validation reconciliation is incomplete")
    if args.approval_token != SCORE_TOKEN:
        raise RuntimeError(f"one-time test scoring requires --approval-token {SCORE_TOKEN}")
    if not socket.gethostname().lower().startswith(args.muscat_hostname_prefix.lower()):
        raise RuntimeError("R97 global test scoring is restricted to Muscat")
    if not controller_lock_available(args.campaign_root):
        raise RuntimeError("the original R97 controller is active")
    muscat_contract = json.loads(Path(reconciliation["muscat_contract"]["path"]).read_text())
    expected_git = muscat_contract["code_git_identity"]
    validate_git_identity(args.code_root, expected_git, require_clean=True)
    cpus, _ = ORIGINAL.choose_cpus(args.workers, 20.0, args.cpu_list)
    campaign_args = SimpleNamespace(
        code_root=args.code_root.resolve(), prep_dir=args.prep_dir.resolve(),
        campaign_root=args.campaign_root.resolve(), workers=args.workers,
    )
    campaign = ORIGINAL.Campaign(campaign_args, cpus)
    closeout = campaign.score()
    result = {
        "schema_version": 1,
        "stage": "R97-distributed-continuation",
        "status": "completed_global_scoring_closeout",
        "regions_fitted": 37,
        "SE_2_reused": True,
        "cases": 114,
        "reconciliation": file_record(args.reconciliation_terminal, "validation_reconciliation"),
        "global_closeout": closeout,
        "model_refit_during_test_scoring": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    atomic_path = args.campaign_root / "distributed/global_scoring_terminal.json"
    write_sealed(atomic_path, result, "global_scoring_terminal_sha256")
    return result


def main() -> int:
    args = parser().parse_args()
    result = reconcile(args) if args.command == "reconcile" else score(args)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
