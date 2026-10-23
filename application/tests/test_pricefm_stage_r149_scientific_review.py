"""Independent adversarial review of R149 checkpoint and eligibility contracts."""
import copy
import datetime as dt
import importlib.util
from pathlib import Path

import numpy as np
import pytest


ROOT = Path(__file__).resolve().parents[2]
ENTRY = ROOT / "application/scripts/pricefm/494_run_pricefm_stage_r149_ee_origin_coverage.py"


@pytest.fixture
def review(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location("r149_independent_review", ENTRY)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    config = m.read(m.CONFIG)
    config["parent_preparation"] = str(tmp_path / "parent.json")
    monkeypatch.setattr(m, "CONFIG", tmp_path / "config.json")
    monkeypatch.setattr(m, "OUT", tmp_path / "campaign")
    monkeypatch.setattr(m, "PREP", tmp_path / "preparation")
    m.write(m.CONFIG, config)
    scaler = tmp_path / "scaler.json"
    m.write(scaler, dict(price_mean=10., price_scale=2.))
    originals, tasks = [], []
    for role, candidate in config["choices"].items():
        for split in (1, 2, 3):
            count = config["full_daily_counts"][str(split)]
            validation = list(range(split * 1000, split * 1000 + count + 1))
            anchor = dt.datetime(2023, split, 1, tzinfo=dt.timezone.utc)
            panels = dict(validation_origin_positions=validation,
                train_origin_positions=list(range(20)), small=[0, 3, 7, 11], large=list(range(12)),
                large_daily_anchors=[(anchor + dt.timedelta(days=i)).isoformat() for i in range(12)])
            old = dict(name=f"original_{role}_s{split}", candidate_id=candidate,
                spec=dict(readout="pure_all_layers", calendar="none"), specification_sha256="spec-hash",
                tau0=.0024929739307713865 if role == "C0" else .00025682335211342966,
                parent_task=f"original_R137_fit_{role}_s{split}", parent_fit=str(tmp_path / "retained_fit"),
                parent_source=dict(branch="original-R137", head="original-fit-head"),
                parent_seal_sha256="original-seal-hash", parent_input_sha256={},
                scaler_path=str(scaler), scaler_sha256=m.digest(scaler),
                bank=dict(path=str(tmp_path / "train_only.npz"), sha256="bank-hash"),
                forecast_seed=123, panels=panels)
            originals.append(old)
            for seed_index, seed in enumerate([123] + config["extra_MC_master_seeds"]):
                daily = validation[:-1] if seed_index == 0 else validation[:12]
                t = {k: copy.deepcopy(old[k]) for k in ("candidate_id", "spec", "specification_sha256",
                    "tau0", "parent_task", "parent_fit", "parent_source", "parent_seal_sha256",
                    "parent_input_sha256", "scaler_path", "scaler_sha256", "bank")}
                t.update(name=m.task_name(role, split, seed_index), role=role, split=split, region="EE",
                    seed_index=seed_index, forecast_seed=seed, paths=100,
                    kind="full_origin_replay" if seed_index == 0 else "mc_panel_replay",
                    clock_offsets_steps=[0, 24, 48, 72], daily_origin_positions=daily,
                    validation_origin_positions=validation, train_origin_positions=list(range(20)),
                    origin_timestamps={str(offset): [(anchor + dt.timedelta(days=i - validation[0],
                        minutes=15 * offset)).isoformat() for i in daily] for offset in (0, 24, 48, 72)},
                    original_panels=copy.deepcopy(panels), parent_r148_task=old["name"],
                    parent_r148_result=str(tmp_path / "R148_result.json"), parent_r148_result_sha256="old-result-hash",
                    kernel_sha256=config["parent_kernel_sha256"],
                    dependency_task=None if seed_index == 0 else m.task_name(role, split, 0),
                    posterior_updated=False, new_model_fits=0, test_opened=False)
                t["scientific_identity_sha256"] = m.fingerprint(m.scientific_identity(t))
                tasks.append(t)
    source_ledger = {"original_numeric_source.py": "original-source-hash"}
    m.write(config["parent_preparation"], dict(tasks=originals, source_sha256=source_ledger))
    prep = dict(task_count=18, tasks=tasks, new_model_fits=0, test_opened=False,
                posterior_updated=False, official_evaluation_authorized=False,
                source_sha256=source_ledger,
                input_sha256={str(scaler): m.digest(scaler),
                              str(tmp_path / "R148_result.json"): "old-result-hash"},
                parent_source=dict(head=config["parent_head"]))
    return m, prep


def prediction_arrays(m, task, descriptor=None):
    rows = m.expected_rows(task, descriptor)
    n = len(rows)
    arrays = {key: np.zeros(shape, dtype="<i8" if key in m.INT_ARRAYS else "<f8")
              for key, shape in m.array_shapes(n, reference=descriptor is None and task["seed_index"] == 0).items()}
    for key in ("truth_eur", "deterministic_eur", "stochastic_eur"):
        arrays[key].fill(10.)
    arrays["origin_positions"][:] = [row[0] for row in rows]
    arrays["clock_offsets"][:] = [row[1] for row in rows]
    arrays["stable_rng_origin_keys"][:] = [row[0] * 96 + row[1] for row in rows]
    stamps = [dt.datetime.fromisoformat(row[2]) for row in rows]
    arrays["origin_timestamps_ns"][:] = [round(v.timestamp() * 1e9) for v in stamps]
    arrays["weekday_UTC"][:] = [v.weekday() for v in stamps]
    arrays["month_UTC"][:] = [v.month for v in stamps]
    if descriptor is None and task["seed_index"] == 0:
        large = [task["validation_origin_positions"][i] for i in task["original_panels"]["large"]]
        arrays["R148_reference_origin_positions"][:] = large * 4
        arrays["R148_reference_clock_offsets"][:] = [offset for offset in (0, 24, 48, 72) for _ in large]
    return arrays


def chunk_fixture(m, task):
    descriptor = m.chunk_descriptors(task)[0]
    arrays = prediction_arrays(m, task, descriptor)
    source = dict(branch="new-R149", head="new-producer-head")
    metadata = dict(certified=True, descriptor=descriptor, context=m.checkpoint_context(task, source),
                    posterior_updated=False, new_model_fits=0)
    return descriptor, arrays, source, metadata


def test_full_common_cohort_counts_and_exact_single_coverage(review):
    m, prep = review
    m.validate_preparation(prep)
    full = [t for t in prep["tasks"] if t["seed_index"] == 0 and t["role"] == "C0"]
    assert [len(t["daily_origin_positions"]) for t in full] == [124, 134, 173]
    assert sum(len(t["daily_origin_positions"]) * 4 for t in full) == 1724
    for task in full:
        chunks = m.chunk_descriptors(task)
        actual = [(d["clock_offset_steps"], p) for d in chunks for p in d["origin_positions"]]
        expected = [(clock, p) for clock in (0, 24, 48, 72) for p in task["validation_origin_positions"][:-1]]
        assert actual == expected and len(actual) == len(set(actual))


@pytest.mark.parametrize("change", ["last_day", "duplicate_task", "original_scale", "new_seed", "new_calendar"])
def test_resealed_preparation_cannot_change_cohort_or_original_model(review, change):
    m, prep = review
    task = prep["tasks"][0]
    if change == "last_day":
        task["daily_origin_positions"][-1] = task["validation_origin_positions"][-1]
    elif change == "duplicate_task":
        prep["tasks"][-1] = copy.deepcopy(task)
    elif change == "original_scale":
        task["tau0"] /= 10
    elif change == "new_seed":
        task["forecast_seed"] += 1
    else:
        task["spec"]["calendar"] = "compact3"
    task["scientific_identity_sha256"] = m.fingerprint(m.scientific_identity(task))
    with pytest.raises(RuntimeError):
        m.validate_preparation(prep)


def test_valid_chunk_proves_context_and_recomputable_loss(review):
    m, prep = review
    task = prep["tasks"][0]
    descriptor, arrays, source, metadata = chunk_fixture(m, task)
    m.validate_chunk(task, descriptor, metadata, arrays, source=source)


@pytest.mark.parametrize("key", ["source", "bank", "scaler_sha256", "parent_seal_sha256", "forecast_seed", "paths", "kernel_sha256"])
def test_even_resealed_checkpoint_cannot_launder_context(review, key):
    m, prep = review
    task = prep["tasks"][0]
    descriptor, arrays, source, metadata = chunk_fixture(m, task)
    metadata["context"][key] = "wrong-context"
    with pytest.raises(RuntimeError):
        m.validate_chunk(task, descriptor, metadata, arrays, source=source)


@pytest.mark.parametrize("change", ["duplicate_origin", "rng", "timestamp", "units", "loss", "crossing", "nonfinite", "shape"])
def test_resealed_arrays_cannot_forge_origin_loss_or_units(review, change):
    m, prep = review
    task = prep["tasks"][0]
    descriptor, arrays, source, metadata = chunk_fixture(m, task)
    if change == "duplicate_origin":
        arrays["origin_positions"][1] = arrays["origin_positions"][0]
    elif change == "rng":
        arrays["stable_rng_origin_keys"][0] += 1
    elif change == "timestamp":
        arrays["origin_timestamps_ns"][0] += 1
    elif change == "units":
        arrays["stochastic_eur"][0, 0, 0] += 1
    elif change == "loss":
        arrays["stochastic_origin_AQL"][0] = .1
    elif change == "crossing":
        arrays["deterministic_standardized"][0, 0, 0] = 1
        arrays["deterministic_eur"][0, 0, 0] = 12
    elif change == "nonfinite":
        arrays["lag_features"][0, 0] = np.nan
    else:
        arrays["truth_eur"] = arrays["truth_eur"][:, :-1]
    with pytest.raises(RuntimeError):
        m.validate_chunk(task, descriptor, metadata, arrays, source=source)


@pytest.fixture
def sampling():
    path = ROOT / "application/scripts/pricefm/pricefm_r149_sampling_analysis.py"
    spec = importlib.util.spec_from_file_location("r149_independent_sampling_review", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_stratum_population_weights_preserve_unequal_population(sampling, monkeypatch):
    # Equal sampling quotas must not give the rare stratum half the target weight.
    rows = [dict(split=split, origin_key=i, weekday=int(i == 3), month=1,
                 control_loss=0., competitor_loss=10. if i == 3 else 0.)
            for split in (1, 2, 3) for i in range(4)]
    monkeypatch.setattr(sampling, "SAMPLE_SIZES", (2,))
    result = sampling.analyze_sampling(rows)
    weekday = next(v for v in result["samplers"] if v["method"] == "weekday_stratified")
    assert result["reference_macro_contrast"] == 2.5
    assert weekday["macro_estimates"] == [2.5] * sampling.REPLICATES


def test_sampling_macro_target_and_row_order_are_explicit(sampling, monkeypatch):
    rows = [dict(split=split, origin_key=i, weekday=i % 7, month=1,
                 control_loss=0., competitor_loss=float(delta))
            for split, count, delta in ((1, 4, 0), (2, 8, 1), (3, 12, 5))
            for i in range(count)]
    monkeypatch.setattr(sampling, "SAMPLE_SIZES", (4,))
    result = sampling.analyze_sampling(rows)
    assert result["reference_macro_contrast"] == 2.
    assert result["pooled_reference_contrast_diagnostic_only"] == pytest.approx(68 / 24)
    assert result == sampling.analyze_sampling(list(reversed(rows)))
    assert not result["automatic_panel_choice"] and not result["new_validation_claim"]


def test_insufficient_budget_cannot_silently_omit_nonempty_strata(sampling, monkeypatch):
    rows = [dict(split=split, origin_key=i, weekday=i % 7, month=i % 7 + 1,
                 control_loss=1., competitor_loss=2.)
            for split in (1, 2, 3) for i in range(8)]
    monkeypatch.setattr(sampling, "SAMPLE_SIZES", (4,))
    result = sampling.analyze_sampling(rows)
    assert all(v["status"] == "infeasible" for v in result["samplers"] if v["method"] != "uniform")


def test_census_sampling_has_no_origin_sampling_error(sampling, monkeypatch):
    rows = [dict(split=split, origin_key=i, weekday=i % 7, month=i % 6 + 1,
                 control_loss=float(i), competitor_loss=float(i * i))
            for split in (1, 2, 3) for i in range(8)]
    monkeypatch.setattr(sampling, "SAMPLE_SIZES", (8,))
    result = sampling.analyze_sampling(rows)
    for row in result["samplers"]:
        assert row["status"] == "complete"
        assert row["MAE"] == pytest.approx(0., abs=1e-12)
        assert row["macro_estimates"] == pytest.approx([result["reference_macro_contrast"]] * sampling.REPLICATES)


def test_completion_cache_cannot_hide_a_changed_runtime_descriptor(review, monkeypatch):
    m, prep = review
    task = prep["tasks"][0]
    m.write(task["parent_r148_result"], {})
    task["parent_r148_result_sha256"] = m.digest(task["parent_r148_result"])
    task["scientific_identity_sha256"] = m.fingerprint(m.scientific_identity(task))
    prep["source"] = dict(branch="review-R149", head="review-producer")
    monkeypatch.setattr(m, "read_preparation", lambda: prep)
    # This regression isolates the completion-cache boundary; numerical result
    # semantics and packet hashes have separate adversarial checks above.
    monkeypatch.setattr(m, "validate_result", lambda *a: None)
    descriptor_path = m.OUT / "tasks" / (task["name"] + ".json")
    m.write(descriptor_path, task)
    folder = m.OUT / "tasks_done" / task["name"]
    m.write(folder / "result.json", {})
    np.savez(folder / "predictions.npz")
    m.write(folder / "completed_evidence.json", dict(
        artifacts={name: m.digest(folder / name) for name in ("result.json", "predictions.npz")},
        metadata=dict(context=m.checkpoint_context(task, prep["source"]), certified=True,
                      source_head=prep["source"]["head"])))
    assert m.task_complete(task["name"])
    changed = copy.deepcopy(task)
    changed["forecast_seed"] += 1
    m.write(descriptor_path, changed)
    with pytest.raises(RuntimeError, match="task descriptor differs"):
        m.task_complete(task["name"])


@pytest.mark.parametrize("change", ["stochastic_bytes", "deterministic_reference", "deterministic_tolerance", "reference_coverage"])
def test_retained_original_replay_is_verified_from_arrays_not_flags(review, change):
    m, prep = review
    task = prep["tasks"][0]
    arrays = prediction_arrays(m, task)
    large_hash = m.byte_hash([0.] * (12 * 96 * 7))
    small_hash = m.byte_hash([0.] * (4 * 96 * 7))
    m.write(task["parent_r148_result"], dict(origin_identities=[dict(
        clock_offset_steps=offset, large_prediction_sha256=large_hash,
        small_prediction_sha256=small_hash, deterministic_small_prediction_sha256=small_hash)
        for offset in (0, 24, 48, 72)]))
    task["parent_r148_result_sha256"] = m.digest(task["parent_r148_result"])
    m.validate_replay_arrays(task, arrays)
    if change == "stochastic_bytes":
        arrays["stochastic_standardized"][0, 0, 0] = 1e-15
    elif change == "deterministic_reference":
        arrays["R148_deterministic_reference"][0, 0, 0] = 1e-15
    elif change == "deterministic_tolerance":
        arrays["deterministic_standardized"][0, 0, 0] = 1e-7
    else:
        arrays["R148_reference_clock_offsets"][0] = 24
    with pytest.raises(RuntimeError):
        m.validate_replay_arrays(task, arrays)


@pytest.mark.parametrize("key", ["deterministic_standardized", "truth_eur", "lag_features"])
def test_extra_seed_cannot_change_rows_reused_from_full_dependency(review, key):
    m, prep = review
    full_task, mc_task = prep["tasks"][:2]
    full, mc = prediction_arrays(m, full_task), prediction_arrays(m, mc_task)
    m.validate_MC_arrays(mc_task, mc, full)
    mc[key].flat[0] += 1e-15
    with pytest.raises(RuntimeError, match="full dependency"):
        m.validate_MC_arrays(mc_task, mc, full)


def test_MC_result_cannot_ignore_its_exact_dependency_seal(review):
    m, prep = review
    task = prep["tasks"][1]
    arrays = prediction_arrays(m, task)
    metrics = m.metrics_light(arrays)
    result = {key: task[key] for key in ("kind", "candidate_id", "role", "split", "tau0",
        "forecast_seed", "seed_index", "scientific_identity_sha256")}
    result.update(certified=True, posterior_updated=False, new_model_fits=0, test_opened=False,
        original_moments_unchanged=True,
        units="EUR/MWh", paths=100, equal_origin_weights=True, origin_clock_windows=48,
        daily_origin_count=12, automatic_future_stage_authorized=False,
        numerical_threadpools=[dict(num_threads=1)],
        MC_scope="nested48_conditional_MC_only_not_full_cohort_stability",
        dependency_task=task["dependency_task"], metrics=metrics,
        clock_metrics=[dict(clock_offset_steps=offset, metrics=metrics) for offset in (0, 24, 48, 72)])
    seal_path = m.OUT / "tasks_done" / task["dependency_task"] / "completed_evidence.json"
    m.write(seal_path, dict(original_full_task=True))
    result["dependency_seal_sha256"] = m.digest(seal_path)
    m.validate_result(task, result, arrays)
    result["dependency_seal_sha256"] = "incorrect-full-task-seal"
    with pytest.raises(RuntimeError, match="dependency"):
        m.validate_result(task, result, arrays)
