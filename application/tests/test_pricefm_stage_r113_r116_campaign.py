from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import threading
import time

import numpy as np
import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))


def load(relative: str, name: str):
    path = ROOT / relative
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PREP = load(
    "application/scripts/pricefm/388_prepare_pricefm_stage_r113_r116_campaign.py",
    "pricefm_r113_prep",
)
WORKER = load(
    "application/scripts/pricefm/391_run_pricefm_stage_r113_r116_campaign.py",
    "pricefm_r113_worker",
)
CONTROLLER = load(
    "application/scripts/pricefm/392_orchestrate_pricefm_stage_r113_r116_campaign.py",
    "pricefm_r113_controller",
)
RECOVERY = load(
    "application/scripts/pricefm/394_prepare_pricefm_stage_r113_r116_recovery.py",
    "pricefm_r113_recovery",
)
CALENDAR_RECOVERY = load(
    "application/scripts/pricefm/395_prepare_pricefm_stage_r113_r116_calendar_recovery.py",
    "pricefm_r113_calendar_recovery",
)
CONVERGENCE_RECOVERY = load(
    "application/scripts/pricefm/396_prepare_pricefm_stage_r113_r116_convergence_recovery.py",
    "pricefm_r113_convergence_recovery",
)
INDEX_RECOVERY = load(
    "application/scripts/pricefm/397_prepare_pricefm_stage_r113_r116_calendar_index_recovery.py",
    "pricefm_r113_calendar_index_recovery",
)
AUDIT = load(
    "application/scripts/pricefm/398_audit_pricefm_stage_r116_transfer_closeout.py",
    "pricefm_r116_transfer_closeout",
)


def write_quantile_family(
    campaign: Path, family: str, inner: int, *, eligible_taus: set[float], p: int = 2,
) -> Path:
    root = campaign / f"runs/r114_fit/family={family}/inner={inner}"
    root.mkdir(parents=True)
    for tau in WORKER.QUANTILES:
        atom = root / f"tau={str(tau).replace('.', 'p')}"
        atom.mkdir()
        np.arange(p, dtype="<f8").tofile(atom / "beta_mean.bin")
        np.eye(p, dtype="<f8").tofile(atom / "beta_cov.bin")
        (atom / "terminal.json").write_text(json.dumps({
            "stage": "R114", "status": "completed_r114_quantile_atom",
            "family": family, "tau": tau, "p": p,
            "numerically_eligible": tau in eligible_taus, "test_opened": False,
        }))
    (root / "terminal.json").write_text(json.dumps({
        "stage": "R114", "status": "completed_r114_quantile_family_fit",
        "family": family, "fit_axis": "inner_fold", "fit_axis_value": inner,
        "atoms_complete": 7, "atoms_eligible": len(eligible_taus),
        "all_atoms_eligible": len(eligible_taus) == 7, "test_opened": False,
    }))
    return root


def test_campaign_prep_is_training_only_bounded_and_reproducible(tmp_path: Path) -> None:
    result = PREP.prepare(ROOT, tmp_path / "campaign")
    assert result["stage"] == "R113_R116"
    assert result["status"] == "prepared_training_only_not_launched"
    assert result["nested_split_count"] == 3
    assert result["candidate_count"] == 240
    assert result["r114_fit_tasks"] == 6
    assert result["r114_fit_cells"] == 42
    assert result["r114_normal_driver_tasks"] == 9
    assert result["r115_ridge_fit_cells"] == 1440
    assert result["r115_rhs_maximum_fit_cells"] == 540
    assert result["posterior_paths"] == 500
    assert result["package_contract"] == "exact_CRAN_exdqlm_1.1.1_public_API_for_AL_exAL"
    assert result["normal_package_contract"].startswith("project_Normal_RHS_source_only")
    assert result["test_access_authorized"] is False
    assert result["registry_mutation_authorized"] is False
    assert result["article_mutation_authorized"] is False
    assert result["mcmc_authorized"] is False
    assert result["joint_model_authorized"] is False
    assert result["broad_all_region_authorized"] is False

    fits = pd.read_csv(tmp_path / "campaign/r114_fit_manifest.csv")
    normals = pd.read_csv(tmp_path / "campaign/r114_normal_driver_manifest.csv")
    assert len(fits) == 6
    assert fits.fit_cells.sum() == 42
    assert set(fits.family) == {"al", "exal"}
    assert len(normals) == 9
    assert set(normals.region) == {"BG", "GR", "RO"}
    for contract_path in fits.contract_path:
        contract = json.loads(Path(contract_path).read_text())
        assert contract["selection_split"] == "BG_fold1_training_nested_temporal_only"
        assert contract["test_access_authorized"] is False
        assert contract["runtime_library"].endswith("exdqlm_cran_1p1p1")

    sources = pd.read_csv(tmp_path / "campaign/source_manifest.csv")
    names = {Path(path).name for path in sources.path}
    assert {"X.bin", "y.bin", "X_train.csv", "rows_train.csv"}.issubset(names)
    assert any("processed_scoring/windows/fold_3/region=RO" in path for path in sources.path)
    CONTROLLER.verify_source_manifest(tmp_path / "campaign", result)


def test_source_manifest_tampering_is_rejected(tmp_path: Path) -> None:
    campaign = tmp_path / "campaign"
    result = PREP.prepare(ROOT, campaign)
    manifest = campaign / "source_manifest.csv"
    manifest.write_text(manifest.read_text() + "\n")
    with pytest.raises(RuntimeError, match="source manifest changed"):
        CONTROLLER.verify_source_manifest(campaign, result)


def test_r114_reader_accepts_exact_R_terminal_axis_contract(tmp_path: Path) -> None:
    campaign = tmp_path / "campaign"
    write_quantile_family(
        campaign, "al", 2, eligible_taus=set(WORKER.QUANTILES),
    )
    means, covariances = WORKER.read_fit(campaign, "al", 2)
    assert set(means) == set(WORKER.QUANTILES)
    assert all(value.shape == (2, 2) for value in covariances.values())


def test_r114_reader_rejects_contradictory_axis_metadata(tmp_path: Path) -> None:
    campaign = tmp_path / "campaign"
    root = write_quantile_family(
        campaign, "al", 2, eligible_taus=set(WORKER.QUANTILES),
    )
    terminal = json.loads((root / "terminal.json").read_text())
    terminal["inner_fold"] = 3
    (root / "terminal.json").write_text(json.dumps(terminal))
    with pytest.raises(RuntimeError, match="axis_contract_mismatch"):
        WORKER.read_fit(campaign, "al", 2)


def test_r114_family_gate_excludes_incomplete_exal_without_blocking_al(tmp_path: Path) -> None:
    campaign = tmp_path / "campaign"
    for inner in (1, 2, 3):
        write_quantile_family(
            campaign, "al", inner, eligible_taus=set(WORKER.QUANTILES),
        )
        write_quantile_family(
            campaign, "exal", inner, eligible_taus={0.5},
        )
    detail, eligible = CONTROLLER.r114_family_eligibility(
        campaign, WORKER, ["al", "exal"],
    )
    assert eligible == ["al"]
    assert detail.loc[detail.family.eq("al"), "eligible"].all()
    assert not detail.loc[detail.family.eq("exal"), "eligible"].any()
    summary = pd.read_csv(campaign / "r114_family_eligibility_summary.csv")
    assert summary.set_index("family").loc["exal", "decision"] == "exclude_before_validation_scoring"


def test_recovery_preserves_r114_files_and_freezes_new_lineage(tmp_path: Path) -> None:
    parent = tmp_path / "parent"
    parent.mkdir()
    evidence = tmp_path / "evidence.txt"
    evidence.write_text("frozen\n")
    source_manifest = pd.DataFrame([{
        "role": "source_or_frozen_evidence", "path": str(evidence),
        "bytes": evidence.stat().st_size, "sha256": RECOVERY.sha256_file(evidence),
    }])
    source_manifest.to_csv(parent / "source_manifest.csv", index=False)
    contract = {
        "stage": "R113_R116", "status": "prepared_training_only_not_launched",
        "region": "BG", "outer_selection_fold": 1, "inner_folds": [1, 2, 3],
        "families": ["al", "exal"], "quantiles": list(WORKER.QUANTILES),
        "posterior_paths": 500, "rank_policies": ["independent_stratified"],
        "readout_modes": ["state_lead_horizon", "state_horizon", "state_only"],
        "r115_ridge_candidates": 240, "r115_ridge_fit_cells": 1440,
        "r115_rhs_maximum_fit_cells": 540, "max_workers": 30,
        "selection_split": "BG_fold1_training_nested_temporal_only",
        "outer_validation_role": "transfer_diagnostic_only",
        "package_contract": "exact_CRAN_exdqlm_1.1.1_public_API_for_AL_exAL",
        "normal_package_contract": "project_Normal_RHS_source_only",
        "source_manifest_sha256": RECOVERY.sha256_file(parent / "source_manifest.csv"),
    }
    contract["campaign_contract_sha256"] = RECOVERY.canonical_hash(contract)
    (parent / "campaign_contract.json").write_text(json.dumps(contract))
    (parent / "splits").mkdir()
    (parent / "splits/marker.txt").write_text("split\n")
    pd.DataFrame({"candidate_id": [f"c{index:03d}" for index in range(240)]}).to_csv(
        parent / "r115_candidate_bank.csv", index=False,
    )
    pd.DataFrame({"inner_fold": [1, 2, 3]}).to_csv(
        parent / "nested_split_summary.csv", index=False,
    )
    for inner in (1, 2, 3):
        write_quantile_family(parent, "al", inner, eligible_taus=set(WORKER.QUANTILES))
        write_quantile_family(parent, "exal", inner, eligible_taus={0.5})
    for region in ("BG", "GR", "RO"):
        for inner in (1, 2, 3):
            root = parent / f"runs/r114_normal_driver/region={region}/inner={inner}"
            root.mkdir(parents=True)
            (root / "terminal.json").write_text(json.dumps({
                "status": "completed_r114_normal_driver", "test_opened": False,
            }))

    output = tmp_path / "recovery"
    result = RECOVERY.prepare_recovery(
        ROOT, parent, output, require_clean=False,
    )
    assert result["status"] == "prepared_recovery_not_launched"
    assert result["resume_mode"] == "reuse_completed_r114_fits"
    assert result["r114_score_families"] == ["al"]
    assert result["r116_families"] == ["al"]
    assert result["reused_r114_fit_cells"] == 51
    CONTROLLER.verify_reuse_manifest(output, result)
    source = parent / "runs/r114_fit/family=al/inner=1/tau=0p1/beta_mean.bin"
    reused = output / "runs/r114_fit/family=al/inner=1/tau=0p1/beta_mean.bin"
    assert source.stat().st_ino == reused.stat().st_ino
    assert not (output / "runs/r114_score").exists()


def write_normal_paths(
    campaign: Path, region: str, inner: int, origin_times: list[pd.Timestamp],
    *, aligned: bool,
) -> Path:
    root = campaign / f"runs/r114_normal_driver/region={region}/inner={inner}"
    root.mkdir(parents=True)
    rows = pd.DataFrame({
        "origin_id": np.repeat(np.arange(len(origin_times)), 96),
        "origin_market_time": np.repeat(origin_times, 96),
        "horizon": np.tile(np.arange(1, 97), len(origin_times)),
    })
    rows.to_csv(root / "evaluation_rows.csv", index=False)
    values = np.repeat(np.arange(len(origin_times) * 96)[:, None], 500, axis=1)
    values.astype("<f8").tofile(root / "prediction_paths_scaled.bin")
    terminal = {
        "status": "completed_r114_normal_driver", "test_opened": False,
        "calendar_alignment_mode": (
            "reference_region_shared_origin_times" if aligned else "region_local_nested_temporal"
        ),
        "reference_region": "BG" if aligned else region,
        "calendar_key": "origin_market_time_utc" if aligned else "region_local_origin_id",
    }
    (root / "terminal.json").write_text(json.dumps(terminal))
    if aligned:
        pd.DataFrame([{
            "split": "validation", "requested_origins": len(origin_times),
            "matched_origins": len(origin_times), "exact_match": True,
        }]).to_csv(root / "calendar_alignment_manifest.csv", index=False)
    return root


def test_normal_paths_align_by_UTC_calendar_not_local_origin_id(tmp_path: Path) -> None:
    times = [pd.Timestamp("2024-01-01", tz="UTC"), pd.Timestamp("2024-01-02", tz="UTC")]
    write_normal_paths(tmp_path, "GR", 1, times, aligned=True)
    cube, keys = WORKER.load_normal_paths(
        tmp_path, "GR", 1, require_reference_alignment=True,
    )
    aligned = WORKER.align_driver_paths(cube, keys, keys[::-1])
    assert aligned.shape == (500, 2, 96)
    assert aligned[0, 0, 0] == cube[0, 1, 0]
    assert aligned[0, 1, 0] == cube[0, 0, 0]
    with pytest.raises(RuntimeError, match="calendar differs from BG"):
        WORKER.align_driver_paths(cube, keys, keys + pd.Timedelta(days=1).value)


def test_normal_path_reader_rejects_incomplete_horizon_surface(tmp_path: Path) -> None:
    root = write_normal_paths(
        tmp_path, "RO", 2, [pd.Timestamp("2024-02-01", tz="UTC")], aligned=True,
    )
    rows = pd.read_csv(root / "evaluation_rows.csv")
    rows.loc[95, "horizon"] = 95
    rows.to_csv(root / "evaluation_rows.csv", index=False)
    with pytest.raises(RuntimeError, match="horizons 1--96 exactly once"):
        WORKER.load_normal_paths(tmp_path, "RO", 2, require_reference_alignment=True)


def test_shared_calendar_is_derived_from_completed_BG_fit(tmp_path: Path) -> None:
    parent = tmp_path / "parent"
    adapter = tmp_path / "adapter"
    adapter.mkdir()
    train_times = pd.date_range("2024-01-01", periods=4, freq="D", tz="UTC")
    validation_times = pd.date_range("2024-01-05", periods=2, freq="D", tz="UTC")
    all_times = train_times.append(validation_times)
    rows = pd.DataFrame({
        "origin_id": np.repeat(np.arange(len(all_times)), 96),
        "origin_market_time": np.repeat(all_times, 96),
        "response_market_time": np.repeat(all_times, 96),
        "horizon": np.tile(np.arange(1, 97), len(all_times)),
    })
    rows.to_csv(adapter / "rows_train.csv", index=False)
    old_contract = tmp_path / "old_contract.json"
    old_contract.write_text(json.dumps({"adapter_dir": str(adapter)}))
    (parent / "parent_metadata").mkdir(parents=True)
    pd.DataFrame([{
        "region": "BG", "inner_fold": 1, "contract_path": str(old_contract),
    }]).to_csv(parent / "parent_metadata/r114_normal_driver_manifest.csv", index=False)
    bg = parent / "runs/r114_normal_driver/region=BG/inner=1"
    bg.mkdir(parents=True)
    (bg / "terminal.json").write_text(json.dumps({
        "status": "completed_r114_normal_driver",
    }))
    rows[rows.origin_id.ge(4)].to_csv(bg / "evaluation_rows.csv", index=False)
    pd.DataFrame([{
        "n_train_origins": 4, "n_validation_origins": 2,
    }]).to_csv(bg / "embargo_summary.csv", index=False)
    calendar, source = CALENDAR_RECOVERY.build_shared_calendar(parent, 1)
    assert source == adapter / "rows_train.csv"
    assert calendar.split.value_counts().to_dict() == {"train": 4, "validation": 2}
    assert calendar.origin_market_time.iloc[4] == "2024-01-05T00:00:00Z"


def test_R_normal_driver_consumes_hashed_shared_calendar_with_embargo() -> None:
    text = (SCRIPTS / "390_run_pricefm_stage_r114_normal_driver.R").read_text()
    assert "reference_region_shared_origin_times" in text
    assert "shared_calendar_sha256" in text
    assert "response_time < validation_start" in text
    assert "validate_origin_surface" in text


def test_convergence_recovery_refits_only_failed_cell_and_accepts_reused_neighbors(
    tmp_path: Path,
) -> None:
    assert CONVERGENCE_RECOVERY.FAILED_REGION == "GR"
    assert CONVERGENCE_RECOVERY.FAILED_INNER_FOLD == 2
    assert CONVERGENCE_RECOVERY.EXTENDED_MAX_ITER == 3000
    times = [pd.Timestamp("2024-03-01", tz="UTC"), pd.Timestamp("2024-03-02", tz="UTC")]
    calendars = tmp_path / "shared_calendars"
    calendars.mkdir()
    for inner in (1, 2, 3):
        calendar = calendars / f"inner_fold_{inner}.csv"
        pd.DataFrame({
            "split": ["validation", "validation"],
            "origin_market_time": times,
            "calendar_order": [0, 1],
        }).to_csv(calendar, index=False)
        for region in ("GR", "RO"):
            root = write_normal_paths(tmp_path, region, inner, times, aligned=True)
            terminal = json.loads((root / "terminal.json").read_text())
            terminal["shared_calendar_sha256"] = CONTROLLER.sha256_file(calendar)
            (root / "terminal.json").write_text(json.dumps(terminal))
    pd.DataFrame([{
        "task_id": "only_failed_cell", "region": "GR", "inner_fold": 2,
        "contract_path": "unused", "output_dir": "unused",
    }]).to_csv(tmp_path / "r114_normal_driver_manifest.csv", index=False)
    CONTROLLER.verify_aligned_neighbor_drivers(tmp_path)


def test_candidate_calendar_maps_dates_to_local_positions_and_horizon_major_rows(
    tmp_path: Path,
) -> None:
    anchors = pd.date_range("2024-01-01", periods=6, freq="D", tz="UTC").astype(str)
    requested = WORKER.canonical_origin_keys([anchors[2], anchors[4]])
    positions = WORKER.local_origin_positions(anchors, requested, "unit candidate")
    assert positions.tolist() == [2, 4]
    design = WORKER.horizon_major_design_indices(positions, len(anchors))
    assert len(design) == 192
    assert design[:4].tolist() == [2, 4, 8, 10]
    assert design[-2:].tolist() == [95 * 6 + 2, 95 * 6 + 4]

    calendars = tmp_path / "shared_calendars"
    calendars.mkdir()
    pd.DataFrame({
        "split": ["validation", "train", "validation", "train"],
        "origin_market_time": [anchors[4], anchors[1], anchors[2], anchors[0]],
        "calendar_order": [1, 1, 0, 0],
    }).to_csv(calendars / "inner_fold_1.csv", index=False)
    observed = WORKER.shared_origin_calendar(tmp_path, 1, "validation")
    assert observed.tolist() == requested.tolist()


def test_calendar_index_recovery_invalidates_all_positional_R115_outputs() -> None:
    text = Path(INDEX_RECOVERY.__file__).read_text()
    assert '"reused_r115_ridge_candidates": 0' in text
    assert '"invalidated_positional_r115_candidates": 12' in text
    assert "runs/r115_ridge" not in INDEX_RECOVERY.REUSED_FLAT_FILES
    worker_text = (SCRIPTS / "391_run_pricefm_stage_r113_r116_campaign.py").read_text()
    assert "shared_BG_origin_times_to_local_candidate_indices" in worker_text
    assert "common_UTC_origin_intersection" in worker_text


def test_r116_exal_cannot_be_materialized_without_al(tmp_path: Path) -> None:
    with pytest.raises(RuntimeError, match="requires the matching AL initializer"):
        CONTROLLER.materialize_r116_family(tmp_path, ROOT, ["exal"])


def test_nested_splits_have_strict_response_time_embargo() -> None:
    rows = pd.DataFrame({
        "origin_id": np.repeat(np.arange(240), 96),
        "horizon": np.tile(np.arange(1, 97), 240),
    })
    base = pd.Timestamp("2020-01-01", tz="UTC")
    rows["origin_market_time"] = [
        base + pd.Timedelta(days=int(origin)) for origin in rows.origin_id
    ]
    rows["response_market_time"] = rows.origin_market_time + pd.to_timedelta(
        rows.horizon - 1, unit="h"
    )
    splits, summary = PREP.nested_temporal_splits(rows)
    assert len(splits) == 3
    assert summary.embargo_passed.all()
    for value in splits:
        assert len(value["train_index"])
        assert len(value["validation_index"]) == 36 * 96
        assert not set(value["train_index"]).intersection(value["validation_index"])


def test_driver_metrics_reward_sharp_calibrated_paths() -> None:
    rng = np.random.default_rng(116)
    truth = rng.normal(size=(3, 96))
    good = truth[:, None, :] + rng.normal(scale=0.2, size=(3, 500, 96))
    bad = truth[:, None, :] + 4 + rng.normal(scale=2, size=(3, 500, 96))
    good_metric, good_blocks = WORKER.driver_metrics(good, truth, "al", "good", 1)
    bad_metric, _ = WORKER.driver_metrics(bad, truth, "al", "bad", 1)
    assert good_metric["CRPS_scaled"] < bad_metric["CRPS_scaled"]
    assert good_metric["MAE_scaled"] < bad_metric["MAE_scaled"]
    assert len(good_blocks) == 4
    assert good_metric["test_opened"] is False


def test_scaled_ridge_prediction_is_finite_and_ordered() -> None:
    rng = np.random.default_rng(117)
    x = np.column_stack([np.ones(200), rng.normal(size=(200, 4))])
    y = x @ np.asarray([0.2, -0.4, 0.1, 0.3, -0.2]) + rng.normal(scale=0.5, size=200)
    fit = WORKER.fit_scaled_ridge(x[:150], y[:150])
    prediction = WORKER.ridge_quantiles(fit, x[150:])
    assert prediction.shape == (50, 7)
    assert np.isfinite(prediction).all()
    assert np.all(prediction[:, :-1] <= prediction[:, 1:])
    assert np.isfinite(WORKER.aql(y[150:], prediction))


def test_physical_cpu_pool_reserves_one_idle_core(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(CONTROLLER, "cpu_percent_snapshot", lambda interval: [0.0] * 4)
    monkeypatch.setattr(CONTROLLER.os, "cpu_count", lambda: 4)
    monkeypatch.setattr(Path, "read_text", lambda self: "0" if self.name == "physical_package_id" else str(int(str(self.parent.parent.name)[3:]) // 2))
    result = CONTROLLER.physical_cpu_pool(30)
    assert result["physical_core_count"] == 2
    assert result["selected_physical_core_count"] == 1
    assert result["reserve_physical_cores"] >= 1


def test_scheduler_never_runs_two_models_on_one_core(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    lock = threading.Lock()
    active: set[int] = set()
    collisions: list[int] = []

    def fake_run(task: dict, cpu: int) -> dict:
        with lock:
            if cpu in active:
                collisions.append(cpu)
            active.add(cpu)
        time.sleep(0.01)
        with lock:
            active.remove(cpu)
        return {
            "task_id": task["task_id"], "cpu": cpu, "returncode": 0,
            "elapsed_seconds": 0.01, "log_path": "unused",
        }

    monkeypatch.setattr(CONTROLLER, "run_one", fake_run)
    tasks = [{"task_id": f"task_{index}"} for index in range(7)]
    result = CONTROLLER.run_parallel(tasks, [2, 4, 6], tmp_path / "status.csv")
    assert len(result) == 7
    assert collisions == []


def test_r116_quantile_contract_uses_exact_cran_and_blocks_mutation(tmp_path: Path) -> None:
    split = tmp_path / "split.csv"
    split.write_text("split,design_index_zero_based\ntrain,0\n")
    contract = CONTROLLER.quantile_contract(
        tmp_path, ROOT, stage="R116", phase="training_only_likelihood_fit",
        task_id="r116_test", family="al", design_dir=tmp_path / "design",
        split_csv_path=split, output_dir=tmp_path / "output", tau0=1e-4,
        seed=116, selection_split="BG_fold1_training_nested_temporal_only",
        al_initializer_dir=None, axis_name="inner_fold", axis_value=1,
    )
    assert contract["runtime_library"].endswith("exdqlm_cran_1p1p1")
    assert contract["test_access_authorized"] is False
    assert contract["registry_mutation_authorized"] is False
    assert contract["article_mutation_authorized"] is False
    assert contract["mcmc_authorized"] is False
    assert contract["joint_model_authorized"] is False
    assert contract["task_contract_sha256"] == CONTROLLER.canonical_hash({
        key: value for key, value in contract.items() if key != "task_contract_sha256"
    })


def test_r116_family_selection_uses_all_three_training_pseudofolds(tmp_path: Path) -> None:
    for family, base in (("al", 1.0), ("exal", 0.8)):
        for inner in (1, 2, 3):
            root = tmp_path / f"runs/r116_family_score/family={family}/inner={inner}"
            root.mkdir(parents=True)
            pd.DataFrame([{
                "family": family, "inner_fold": inner, "eligible": True,
                "AQL_scaled": base + inner / 100, "late_AQL_scaled": base + inner / 50,
                "coverage_10_90": 0.8, "width_10_90_scaled": 1.0,
                "crossing_rate": 0.0, "reason": "complete", "test_opened": False,
            }]).to_csv(root / "metrics.csv", index=False)
    selected = CONTROLLER.select_r116_family(tmp_path)
    assert selected["family"] == "exal"
    assert selected["selection_frozen_before_outer_validation"] is True
    assert selected["test_opened"] is False


def test_r116_surface_score_rewards_exact_ordered_quantiles() -> None:
    truth = np.arange(12, dtype=float).reshape(3, 4)
    offsets = np.asarray([-2, -1, -0.2, 0, 0.2, 1, 2], dtype=float)
    prediction = truth[None, :, :] + offsets[:, None, None]
    metric = WORKER.score_surface(truth, prediction)
    assert metric["AQL"] > 0
    assert metric["AQCR"] == 0
    assert metric["coverage_10_90"] == 1
    assert metric["n_loss_atoms"] == 7 * truth.size


def test_r116_runner_supports_family_and_outer_contracts() -> None:
    runner = (ROOT / "application/scripts/pricefm/389_run_pricefm_stage_r114_quantile_fit.R").read_text()
    controller = (ROOT / "application/scripts/pricefm/392_orchestrate_pricefm_stage_r113_r116_campaign.py").read_text()
    assert '"training_only_likelihood_fit"' in runner
    assert '"outer_transfer_readout_fit"' in runner
    assert "completed_r116_quantile_family_fit" in runner
    assert "completed_r116_factorial_closeout" in controller


def synthetic_r116_metrics() -> tuple[pd.DataFrame, pd.DataFrame]:
    metrics = []
    horizons = []
    for fold in (1, 2, 3):
        for cell, aql, coverage, width in (
            ("A", 10.0 + fold, 0.70, 10.0),
            ("B", 10.0 + fold, 0.70, 10.0),
            ("C", 9.8 + fold, 0.66, 7.0),
            ("D", 9.8 + fold, 0.66, 7.0),
        ):
            metrics.append({
                "fold": fold, "cell": cell,
                "driver": "normal" if cell in {"A", "C"} else "selected",
                "readout": "current_lead" if cell in {"A", "B"} else "selected_no_bypass",
                "family": "al", "AQL": aql, "AQCR": 0.0,
                "coverage_10_90": coverage, "width_10_90": width,
                "n_loss_atoms": 100, "test_opened": False,
            })
            horizons.append({
                "fold": fold, "cell": cell, "horizon_block": "73-96",
                "driver": "normal" if cell in {"A", "C"} else "selected",
                "readout": "current_lead" if cell in {"A", "B"} else "selected_no_bypass",
                "family": "al", "AQL": aql, "AQCR": 0.0,
                "coverage_10_90": coverage, "width_10_90": width,
                "n_loss_atoms": 25, "test_opened": False,
            })
    return pd.DataFrame(metrics), pd.DataFrame(horizons)


def test_r116_closeout_loads_context_and_blocks_failed_harm_gates(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    campaign = tmp_path / "campaign"
    metrics, horizons = synthetic_r116_metrics()
    for fold in (1, 2, 3):
        root = campaign / f"runs/r116_outer_score/fold={fold}"
        root.mkdir(parents=True)
        metrics[metrics.fold.eq(fold)].to_csv(root / "metrics.csv", index=False)
        horizons[horizons.fold.eq(fold)].to_csv(root / "horizon_metrics.csv", index=False)
    (campaign / "r116_selected_family.json").write_text(json.dumps({"family": "al"}))
    (campaign / "r114_selected_driver.json").write_text(json.dumps({"family": "normal_rhs"}))
    references = tmp_path / "r111b"
    references.mkdir()
    pd.DataFrame([{
        "region": "BG", "fold": 1, "policy": "r111b_exposure_aligned_readout",
        "AQL": 5.0, "n_loss_atoms": 100,
    }]).to_csv(references / "pricefm_stage_r111b_bg_case_metrics.csv", index=False)
    pd.DataFrame([{
        "region": "BG", "fold": 1, "policy": "r97_direct_reference",
        "AQL": 4.0, "n_loss_atoms": 100,
    }]).to_csv(references / "pricefm_stage_r111b_bg_references.csv", index=False)
    monkeypatch.setattr(CONTROLLER, "R111B", references)

    result = CONTROLLER.closeout_r116(campaign)

    assert result["transfer_gates_passed"] == 3
    assert result["transfer_gates_total"] == 5
    assert result["all_transfer_gates_passed"] is False
    assert result["r117_preparation_authorized"] is False
    assert result["driver_contrast_identifiable"] is False
    assert result["mechanism_interpretation"] == "readout_only_driver_axis_degenerate"
    assert (campaign / "r116_contextual_references.csv").is_file()


def test_driver_axis_audit_requires_exact_duplicate_cells_for_normal_rhs(
    tmp_path: Path,
) -> None:
    campaign = tmp_path / "campaign"
    metrics, _ = synthetic_r116_metrics()
    (campaign / "r114_selected_driver.json").parent.mkdir(parents=True)
    (campaign / "r114_selected_driver.json").write_text(json.dumps({"family": "normal_rhs"}))
    for fold in (1, 2, 3):
        root = campaign / f"runs/r116_outer_score/fold={fold}"
        root.mkdir(parents=True)
        for cell, offset in (("A", 0.0), ("B", 0.0), ("C", 1.0), ("D", 1.0)):
            np.savez_compressed(
                root / f"cell_{cell}_validation_predictions.npz",
                prediction_scaled=np.arange(12, dtype=float).reshape(1, 3, 4) + offset,
            )
    frame, identifiable = AUDIT.driver_axis_audit(campaign, metrics, {})
    assert identifiable is False
    assert frame.exact_match.all()
    assert frame.maximum_metric_difference.eq(0).all()


def test_r103_equivalence_audit_distinguishes_fit_from_forecast_operator(
    tmp_path: Path,
) -> None:
    campaign = tmp_path / "campaign"
    r103 = tmp_path / "r103"
    for fold in (1, 2, 3):
        current_design = campaign / f"runs/r116_outer_design/fold={fold}/current_lead/design"
        reference_design = r103 / f"cases/region=BG/fold={fold}/design"
        current_design.mkdir(parents=True)
        reference_design.mkdir(parents=True)
        for name, values in (
            ("X.bin", np.arange(12, dtype="<f8")),
            ("y.bin", np.arange(4, dtype="<f8")),
        ):
            values.tofile(current_design / name)
            values.tofile(reference_design / name)
        for tau in AUDIT.QUANTILES:
            label = AUDIT.tau_label(tau)
            current_atom = campaign / (
                f"runs/r116_outer_fit/readout=current_lead/family=al/fold={fold}/tau={label}"
            )
            reference_atom = r103 / (
                f"cases/region=BG/fold={fold}/atoms/r103_bg_f{fold}_al_{label}"
            )
            current_atom.mkdir(parents=True)
            reference_atom.mkdir(parents=True)
            beta = np.asarray([1.0, 2.0, 3.0], dtype="<f8")
            beta.tofile(current_atom / "beta_mean.bin")
            (beta + 1e-8).tofile(reference_atom / "beta_mean.bin")
        current_score = campaign / f"runs/r116_outer_score/fold={fold}"
        reference_case = r103 / f"cases/region=BG/fold={fold}"
        current_score.mkdir(parents=True)
        prediction = np.arange(84, dtype=float).reshape(7, 3, 4)
        np.savez_compressed(
            current_score / "cell_A_validation_predictions.npz",
            prediction_scaled=prediction, anchors=np.arange(3),
            quantiles=np.asarray(AUDIT.QUANTILES),
        )
        np.savez_compressed(
            reference_case / "al_validation_quantiles.npz",
            prediction_scaled=prediction + 1e-4, anchors=np.arange(3),
            quantiles=np.asarray(AUDIT.QUANTILES),
        )
        pd.DataFrame([{
            "family": "al", "validation_AQL_original": 1.0,
            "n_loss_atoms": 84,
        }]).to_csv(reference_case / "family_validation_metrics.csv", index=False)

    result = AUDIT.r103_equivalence_audit(campaign, r103, {})

    assert result[result.component.str.startswith("design_")].exact_match.all()
    assert result[result.component.eq("beta_mean")].max_abs_difference.le(1e-5).all()
    assert result[result.component.eq("recursive_prediction_scaled")].max_abs_difference.le(2e-3).all()
