from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/387_close_pricefm_stage_r112b_normal_extension.py"
SPEC = importlib.util.spec_from_file_location("pricefm_r112b_closeout", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def build_fixture(root: Path) -> tuple[Path, Path, Path]:
    prep = root / "prep"
    r100 = root / "r100"
    campaign = root / "campaign"
    prep.mkdir()
    write_json(prep / "summary.json", {
        "stage": "R112A",
        "status": "completed_launch_prep_not_launched",
    })
    pending = []
    for host, count, start in (("jerez", 14, 18), ("muscat", 7, 32)):
        for index in range(start, start + count):
            pending.append({
                "region": f"R{index:02d}",
                "host": host,
                "test_access_authorized": False,
            })
    pd.DataFrame(pending).to_csv(
        prep / "pricefm_stage_r112a_normal_extension_launch_manifest.csv", index=False
    )

    r100.mkdir()
    write_json(r100 / "campaign_terminal.json", {
        "stage": "R100",
        "status": "completed_normal_winners_frozen",
        "regions_complete": 17,
        "regions_failed": [],
        "test_opened": False,
        "quantile_fit_started": False,
    })
    reused = []
    for index in range(1, 18):
        region = f"R{index:02d}"
        contract = r100 / f"contracts/{region}.json"
        write_json(contract, {
            "stage": "R100",
            "status": "provisional_normal_winner_frozen",
            "region": region,
            "eligible": True,
            "converged": True,
            "selection_uses_test": False,
            "test_scoring_authorized": False,
            "quantile_fit_authorized": False,
        })
        reused.append({
            "region": region,
            "contract": str(contract),
            "experiment_id": f"old_{region}",
            "validation_AQL": float(index),
            "tau0": 0.001,
        })
    pd.DataFrame(reused).to_csv(
        r100 / "pricefm_stage_r100_frozen_normal_winners.csv", index=False
    )

    for host in MODULE.HOSTS:
        host_root = campaign / f"hosts/{host}"
        rows = []
        for item in [row for row in pending if row["host"] == host]:
            region = item["region"]
            ranking = host_root / f"regions/{region}/rhs_closeout/ranking.csv"
            ranking.parent.mkdir(parents=True, exist_ok=True)
            ranking.write_text("rhs_rank,eligible,median_validation_AQL\n1,True,1.0\n")
            contract = ranking.parent / "contract.json"
            write_json(contract, {
                "stage": "R112B",
                "status": "provisional_normal_winner_frozen",
                "region": region,
                "host": host,
                "eligible": True,
                "converged": True,
                "selection_uses_outer_validation": False,
                "selection_uses_test": False,
                "test_scoring_authorized": False,
                "quantile_fit_authorized": False,
                "registry_mutation_authorized": False,
                "article_mutation_authorized": False,
                "ranking_path": str(ranking),
                "ranking_sha256": MODULE.sha256_file(ranking),
            })
            rows.append({
                "region": region,
                "host": host,
                "contract": str(contract),
                "contract_sha256": MODULE.sha256_file(contract),
                "experiment_id": f"new_{region}",
                "validation_AQL": float(int(region[1:])),
                "tau0": 0.002,
            })
        winners = host_root / f"pricefm_stage_r112b_{host}_normal_winners.csv"
        winners.parent.mkdir(parents=True, exist_ok=True)
        pd.DataFrame(rows).to_csv(winners, index=False)
        write_json(host_root / "host_terminal.json", {
            "stage": "R112B",
            "status": "completed_host_normal_winners_frozen",
            "host": host,
            "regions_expected": len(rows),
            "regions_complete": len(rows),
            "regions_failed": [],
            "winners_path": str(winners),
            "winners_sha256": MODULE.sha256_file(winners),
            "test_opened": False,
            "quantile_fit_started": False,
            "registry_mutated": False,
            "article_mutated": False,
        })
    return prep, r100, campaign


def test_complete_two_host_closeout_is_read_only_and_idempotent(tmp_path: Path) -> None:
    prep, r100, campaign = build_fixture(tmp_path)
    output = tmp_path / "output"
    args = MODULE.parser().parse_args([
        "--code-root", str(ROOT),
        "--prep-dir", str(prep),
        "--r100-root", str(r100),
        "--campaign-root", str(campaign),
        "--output-dir", str(output),
    ])
    summary = MODULE.run(args)
    assert summary["status"] == "completed_all_region_normal_winners_frozen"
    assert summary["regions"] == 38
    assert summary["r100_reused_winners"] == 17
    assert summary["r112b_new_winners"] == 21
    assert summary["selection_uses_outer_validation"] is False
    assert summary["selection_uses_test"] is False
    assert summary["model_fit_started_by_closeout"] is False
    assert summary["quantile_fit_started"] is False
    assert summary["joint_fit_started"] is False
    assert summary["mcmc_fit_started"] is False
    assert summary["registry_mutated"] is False
    assert summary["article_mutated"] is False
    winners = pd.read_csv(output / "pricefm_stage_r112b_all_region_normal_winners.csv")
    assert len(winners) == 38
    assert winners.region.is_unique
    assert winners.source_stage.value_counts().to_dict() == {"R112B": 21, "R100": 17}
    assert not winners.selection_uses_outer_validation.any()
    assert not winners.selection_uses_test.any()
    gates = pd.read_csv(output / "pricefm_stage_r112b_closeout_gates.csv")
    assert gates.passed.all()
    assert MODULE.run(args) == summary


def test_combine_winners_rejects_duplicate_region() -> None:
    columns = {
        "source_host": "host",
        "contract": "/tmp/contract",
        "contract_sha256": "a" * 64,
        "experiment_id": "id",
        "validation_AQL": 1.0,
        "tau0": 0.001,
        "selection_uses_outer_validation": False,
        "selection_uses_test": False,
    }
    r100 = pd.DataFrame([
        {"region": f"R{i:02d}", "source_stage": "R100", **columns}
        for i in range(17)
    ])
    r112b = pd.DataFrame([
        {"region": f"R{i:02d}", "source_stage": "R112B", **columns}
        for i in range(17, 38)
    ])
    r112b.loc[0, "region"] = "R00"
    try:
        MODULE.combine_winners(r100, r112b)
    except RuntimeError as error:
        assert "incomplete or contaminated" in str(error)
    else:
        raise AssertionError("duplicate region was accepted")


def test_source_has_no_fit_or_launch_path() -> None:
    text = SCRIPT.read_text()
    assert '"model_fit_started_by_closeout": False' in text
    assert '"quantile_fit_started": False' in text
    assert '"registry_mutated": False' in text
    assert '"article_mutated": False' in text
    assert "subprocess.run" not in text
    assert "Popen" not in text
    assert "ThreadPoolExecutor" not in text

