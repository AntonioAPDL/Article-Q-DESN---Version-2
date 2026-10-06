from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/386_run_pricefm_stage_r112b_normal_extension.py"
SPEC = importlib.util.spec_from_file_location("pricefm_r112b", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


def test_runner_contract_is_host_scoped_and_one_cpu_per_worker(tmp_path: Path) -> None:
    assert MODULE.HOST_WORKER_CEILINGS == {"muscat": 25, "jerez": 50}
    assert MODULE.RUNNER.parse_cpus("0-2,7") == [0, 1, 2, 7]
    assert MODULE.host_root(tmp_path, "jerez") == tmp_path / "hosts/jerez"
    args = MODULE.parser().parse_args([
        "--code-root", str(ROOT),
        "--host", "muscat",
        "--workers", "2",
        "--cpu-list", "0,1",
        "--approval-token", MODULE.APPROVAL,
        "--preflight-only",
    ])
    assert args.host == "muscat"
    assert args.workers == 2
    assert args.preflight_only is True


def test_r112b_marker_requires_hash_validated_compacted_evidence(tmp_path: Path) -> None:
    retained = tmp_path / "metric_summary.csv"
    retained.write_text("method_id,split,unit,AQL\nnormal_rhs_ns,val,original,1.0\n")
    marker = tmp_path / "r112b_compaction_terminal.json"
    marker.write_text(json.dumps({
        "stage": "R112B",
        "status": "completed_compacted",
        "test_opened": False,
        "retained": [{
            "path": str(retained),
            "sha256": MODULE.sha256_file(retained),
        }],
    }))
    assert MODULE.valid_marker(marker)
    retained.write_text("changed\n")
    assert not MODULE.valid_marker(marker)


def test_run_queue_resumes_without_refitting_valid_cells(tmp_path: Path) -> None:
    run_dir = tmp_path / "run"
    run_dir.mkdir()
    retained = run_dir / "metric_summary.csv"
    retained.write_text("method_id,split,unit,AQL\nnormal_rhs_ns,val,original,1.0\n")
    (run_dir / "r112b_compaction_terminal.json").write_text(json.dumps({
        "stage": "R112B",
        "status": "completed_compacted",
        "test_opened": False,
        "retained": [{
            "path": str(retained),
            "sha256": MODULE.sha256_file(retained),
        }],
    }))
    manifest = pd.DataFrame([{
        "id": "already_done",
        "campaign_region": "AT",
        "folds": "[101, 102, 103]",
        "run_dir": str(run_dir),
        "full_config": str(tmp_path / "unused.yaml"),
    }])
    result = MODULE.run_queue(
        manifest,
        [0],
        ROOT,
        tmp_path / "campaign",
        "ridge",
        0.0,
        0.0,
    )
    assert result == {"complete": 1, "failed": 0, "total": 1}


def test_tau_scaling_matches_r100_and_source_is_fail_closed() -> None:
    assert MODULE.RUNNER.tau_reference(0.01, 100, 25) == 0.02
    text = SCRIPT.read_text()
    assert "selection_uses_test" in text
    assert "r112b_compaction_terminal.json" in text
    assert "one distinct CPU per worker" in text
    assert "clean synchronized PriceFM task branch" in text
    assert "completed_host_normal_winners_frozen" in text
    assert "quantile_fit_started" in text
    assert "registry_mutated" in text
    assert "article_mutated" in text

