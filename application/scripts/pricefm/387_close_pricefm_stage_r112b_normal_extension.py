#!/usr/bin/env python3
"""Close the two-host R112B Normal extension without fitting models."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from typing import Any

import pandas as pd


STAGE = "R112B"
TAG = "pricefm_stage_r112b_normal_extension_closeout_20260922"
DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
PREP = DATA / "launch_prep/pricefm_stage_r112a_normal_extension_prep_20260922"
R100 = DATA / "campaigns/pricefm_stage_r100_targeted_normal_recovery_20260913"
CAMPAIGN = DATA / "campaigns/pricefm_stage_r112b_normal_extension_20260922"
OUTPUT = DATA / "authoritative" / TAG
HOSTS = ("jerez", "muscat")
EXPECTED_HOST_REGIONS = {"jerez": 14, "muscat": 7}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, default=Path.cwd())
    p.add_argument("--prep-dir", type=Path, default=PREP)
    p.add_argument("--r100-root", type=Path, default=R100)
    p.add_argument("--campaign-root", type=Path, default=CAMPAIGN)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--force", action="store_true")
    return p


def artifact(role: str, path: Path, **extra: Any) -> dict[str, Any]:
    path = path.resolve()
    if not path.is_file():
        raise FileNotFoundError(path)
    return {
        "role": role,
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
        **extra,
    }


def validate_r100(root: Path) -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    terminal_path = root / "campaign_terminal.json"
    winners_path = root / "pricefm_stage_r100_frozen_normal_winners.csv"
    terminal = json.loads(terminal_path.read_text())
    winners = pd.read_csv(winners_path)
    if (
        terminal.get("stage") != "R100"
        or terminal.get("status") != "completed_normal_winners_frozen"
        or terminal.get("regions_complete") != 17
        or terminal.get("regions_failed") != []
        or terminal.get("test_opened") is not False
        or terminal.get("quantile_fit_started") is not False
        or len(winners) != 17
        or winners.region.nunique() != 17
    ):
        raise RuntimeError("R112B closeout found an invalid R100 winner package")
    rows = []
    evidence = [
        artifact("r100_campaign_terminal", terminal_path),
        artifact("r100_frozen_winners", winners_path),
    ]
    for winner in winners.itertuples(index=False):
        contract_path = Path(winner.contract)
        contract = json.loads(contract_path.read_text())
        if (
            contract.get("stage") != "R100"
            or contract.get("status") != "provisional_normal_winner_frozen"
            or contract.get("region") != winner.region
            or contract.get("eligible") is not True
            or contract.get("converged") is not True
            or contract.get("selection_uses_test") is not False
            or contract.get("test_scoring_authorized") is not False
            or contract.get("quantile_fit_authorized") is not False
        ):
            raise RuntimeError(f"invalid frozen R100 contract: {winner.region}")
        rows.append({
            "region": str(winner.region),
            "source_stage": "R100",
            "source_host": "historical_reuse",
            "contract": str(contract_path.resolve()),
            "contract_sha256": sha256_file(contract_path),
            "experiment_id": str(winner.experiment_id),
            "validation_AQL": float(winner.validation_AQL),
            "tau0": float(winner.tau0),
            "selection_uses_outer_validation": False,
            "selection_uses_test": False,
        })
        evidence.append(artifact("r100_winner_contract", contract_path, region=winner.region))
    return pd.DataFrame(rows), evidence


def validate_r112b_hosts(
    campaign_root: Path,
    expected_regions: pd.DataFrame,
) -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    frames = []
    evidence: list[dict[str, Any]] = []
    for host in HOSTS:
        root = campaign_root / "hosts" / host
        terminal_path = root / "host_terminal.json"
        terminal = json.loads(terminal_path.read_text())
        expected = EXPECTED_HOST_REGIONS[host]
        if (
            terminal.get("stage") != STAGE
            or terminal.get("status") != "completed_host_normal_winners_frozen"
            or terminal.get("host") != host
            or terminal.get("regions_expected") != expected
            or terminal.get("regions_complete") != expected
            or terminal.get("regions_failed") != []
            or terminal.get("test_opened") is not False
            or terminal.get("quantile_fit_started") is not False
            or terminal.get("registry_mutated") is not False
            or terminal.get("article_mutated") is not False
        ):
            raise RuntimeError(f"R112B {host} terminal is incomplete or invalid")
        winners_path = Path(terminal["winners_path"])
        if (
            not winners_path.is_file()
            or sha256_file(winners_path) != terminal.get("winners_sha256")
        ):
            raise RuntimeError(f"R112B {host} winner ledger changed")
        winners = pd.read_csv(winners_path)
        host_expected = set(
            expected_regions.loc[expected_regions.host.eq(host), "region"].astype(str)
        )
        if (
            len(winners) != expected
            or winners.region.nunique() != expected
            or set(winners.region.astype(str)) != host_expected
            or set(winners.host.astype(str)) != {host}
        ):
            raise RuntimeError(f"R112B {host} winner set differs from R112A ownership")
        normalized = []
        for winner in winners.itertuples(index=False):
            contract_path = Path(winner.contract)
            if (
                not contract_path.is_file()
                or sha256_file(contract_path) != winner.contract_sha256
            ):
                raise RuntimeError(f"R112B winner contract changed: {winner.region}")
            contract = json.loads(contract_path.read_text())
            if (
                contract.get("stage") != STAGE
                or contract.get("status") != "provisional_normal_winner_frozen"
                or contract.get("region") != winner.region
                or contract.get("host") != host
                or contract.get("eligible") is not True
                or contract.get("converged") is not True
                or contract.get("selection_uses_outer_validation") is not False
                or contract.get("selection_uses_test") is not False
                or contract.get("test_scoring_authorized") is not False
                or contract.get("quantile_fit_authorized") is not False
                or contract.get("registry_mutation_authorized") is not False
                or contract.get("article_mutation_authorized") is not False
            ):
                raise RuntimeError(f"invalid R112B winner contract: {winner.region}")
            ranking_path = Path(contract["ranking_path"])
            if (
                not ranking_path.is_file()
                or sha256_file(ranking_path) != contract.get("ranking_sha256")
            ):
                raise RuntimeError(f"R112B ranking changed: {winner.region}")
            normalized.append({
                "region": str(winner.region),
                "source_stage": STAGE,
                "source_host": host,
                "contract": str(contract_path.resolve()),
                "contract_sha256": sha256_file(contract_path),
                "experiment_id": str(winner.experiment_id),
                "validation_AQL": float(winner.validation_AQL),
                "tau0": float(winner.tau0),
                "selection_uses_outer_validation": False,
                "selection_uses_test": False,
            })
            evidence.extend([
                artifact("r112b_winner_contract", contract_path, region=winner.region, host=host),
                artifact("r112b_winner_ranking", ranking_path, region=winner.region, host=host),
            ])
        frames.append(pd.DataFrame(normalized))
        evidence.extend([
            artifact("r112b_host_terminal", terminal_path, host=host),
            artifact("r112b_host_winners", winners_path, host=host),
        ])
    return pd.concat(frames, ignore_index=True), evidence


def combine_winners(r100: pd.DataFrame, r112b: pd.DataFrame) -> pd.DataFrame:
    combined = pd.concat([r100, r112b], ignore_index=True).sort_values("region")
    if (
        len(combined) != 38
        or combined.region.nunique() != 38
        or combined.contract_sha256.str.len().ne(64).any()
        or combined.selection_uses_outer_validation.any()
        or combined.selection_uses_test.any()
        or set(combined.source_stage.value_counts().to_dict().items())
        != {("R100", 17), ("R112B", 21)}
    ):
        raise RuntimeError("R112B all-region Normal union is incomplete or contaminated")
    combined.insert(0, "normal_winner_rank_by_validation_AQL", combined.validation_AQL.rank(method="first").astype(int))
    return combined


def report_text(combined: pd.DataFrame) -> str:
    summary = combined.groupby(["source_stage", "source_host"], as_index=False).agg(
        regions=("region", "nunique"),
        median_inner_validation_AQL=("validation_AQL", "median"),
        min_inner_validation_AQL=("validation_AQL", "min"),
        max_inner_validation_AQL=("validation_AQL", "max"),
    )
    return "\n".join([
        "# PriceFM Stage-R112B all-region Normal closeout",
        "",
        "This read-only closeout combines 17 frozen R100 winners with 21 R112B",
        "winners. It fits nothing and opens no outer validation or test data.",
        "",
        "## Completeness",
        "",
        "The union contains exactly one training-selected Normal RHS specification",
        "for each of the 38 PriceFM regions. All contracts, rankings, host terminals,",
        "and source files are hash-verified.",
        "",
        summary.to_markdown(index=False),
        "",
        "## Decision",
        "",
        "R112C may prepare the training-only AL versus structured/M0 exAL family",
        "selection. Outer-fold scoring, joint/MCMC work, registry mutation, and article",
        "updates remain blocked.",
    ]) + "\n"


def run(args: argparse.Namespace) -> dict[str, Any]:
    output = args.output_dir.resolve()
    summary_path = output / "summary.json"
    if summary_path.is_file() and not args.force:
        summary = json.loads(summary_path.read_text())
        if summary.get("status") == "completed_all_region_normal_winners_frozen":
            for row in summary.get("outputs", []):
                path = Path(row["path"])
                if not path.is_file() or sha256_file(path) != row["sha256"]:
                    raise RuntimeError(f"R112B closeout output changed: {path}")
            return summary
    if output.exists() and any(output.iterdir()) and not args.force:
        raise RuntimeError(f"R112B closeout exists but is not reusable: {output}")

    prep_summary_path = args.prep_dir / "summary.json"
    prep_summary = json.loads(prep_summary_path.read_text())
    launch_path = args.prep_dir / "pricefm_stage_r112a_normal_extension_launch_manifest.csv"
    launch = pd.read_csv(launch_path)
    if (
        prep_summary.get("stage") != "R112A"
        or prep_summary.get("status") != "completed_launch_prep_not_launched"
        or len(launch) != 21
        or launch.region.nunique() != 21
        or launch.test_access_authorized.any()
    ):
        raise RuntimeError("R112B closeout found an invalid R112A package")
    r100, evidence = validate_r100(args.r100_root)
    r112b, host_evidence = validate_r112b_hosts(args.campaign_root, launch)
    evidence.extend(host_evidence)
    combined = combine_winners(r100, r112b)
    evidence.extend([
        artifact("r112a_summary", prep_summary_path),
        artifact("r112a_launch_manifest", launch_path),
        artifact("executed_source", Path(__file__)),
    ])

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        winner_path = temporary / "pricefm_stage_r112b_all_region_normal_winners.csv"
        gate_path = temporary / "pricefm_stage_r112b_closeout_gates.csv"
        source_path = temporary / "source_manifest.csv"
        report_path = temporary / "pricefm_stage_r112b_normal_extension_closeout.md"
        combined.to_csv(winner_path, index=False)
        gates = pd.DataFrame([
            ("r100_winners", len(r100) == 17, len(r100)),
            ("r112b_winners", len(r112b) == 21, len(r112b)),
            ("all_regions", len(combined) == 38, len(combined)),
            ("one_winner_per_region", combined.region.is_unique, combined.region.nunique()),
            ("outer_validation_selection_blocked", not combined.selection_uses_outer_validation.any(), False),
            ("test_selection_blocked", not combined.selection_uses_test.any(), False),
            ("quantile_not_started", True, "blocked_until_R112C"),
            ("registry_article_blocked", True, "blocked"),
        ], columns=["gate", "passed", "observed"])
        if not gates.passed.all():
            raise RuntimeError("R112B closeout gates failed")
        gates.to_csv(gate_path, index=False)
        pd.DataFrame(evidence).drop_duplicates(["path", "sha256"]).sort_values(["role", "path"]).to_csv(source_path, index=False)
        report_path.write_text(report_text(combined))
        outputs = [
            {
                "path": str((output / path.name).resolve()),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
            for path in sorted(temporary.iterdir())
        ]
        head = subprocess.check_output(
            ["git", "-C", str(args.code_root.resolve()), "rev-parse", "HEAD"], text=True
        ).strip()
        summary = {
            "stage": STAGE,
            "status": "completed_all_region_normal_winners_frozen",
            "tag": TAG,
            "head": head,
            "regions": 38,
            "r100_reused_winners": 17,
            "r112b_new_winners": 21,
            "selection_uses_outer_validation": False,
            "selection_uses_test": False,
            "model_fit_started_by_closeout": False,
            "quantile_fit_started": False,
            "joint_fit_started": False,
            "mcmc_fit_started": False,
            "registry_mutated": False,
            "article_mutated": False,
            "next_stage": "R112C_training_only_AL_exAL_family_selection_prep",
            "outputs": outputs,
        }
        (temporary / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
        return summary
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main() -> None:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
