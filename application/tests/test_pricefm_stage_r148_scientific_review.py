"""Independent adversarial review of R148 provenance and completion contracts.

These tests reseal deliberately malformed records, so a passing checksum cannot
stand in for the scientific task grid or the paired evaluation identities.
"""
import copy
import importlib.util
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
ENTRY = ROOT / "application/scripts/pricefm/492_run_pricefm_stage_r148_ee_parallel_development.py"


@pytest.fixture
def review(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location("r148_independent_review", ENTRY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    config = module.read(module.CONFIG)
    monkeypatch.setattr(module, "PREP", tmp_path / "prep")
    monkeypatch.setattr(module, "OUT", tmp_path / "out")
    monkeypatch.setattr(module, "CONFIG", tmp_path / "config.json")
    module.write(module.CONFIG, config)
    identity = {"head": "review-head", "branch": config["required_branch"]}
    monkeypatch.setattr(module, "source_identity", lambda: identity)
    tasks = []
    for candidate in config["expected_selected_ids"]:
        for split in (1, 2, 3):
            tasks.append(dict(name=f"EE_cached_rhs_{candidate}_s{split}",
                kind="cached_rhs_rescore", region="EE", candidate_id=candidate,
                split=split, tau0=.001, paths=100, test_opened=False,
                posterior_moments_reused_without_update=True,
                spec=dict(readout="pure_all_layers", calendar="none"),
                parent_source=dict(head=config["cache_source_head"]),
                panels=dict(small=[0, 3, 7, 11], large=list(range(12)),
                            validation_origin_positions=list(range(500, 512)))))
    preparation = dict(source=identity, config_sha256=module.digest(module.CONFIG),
        task_count=18, tasks=tasks, new_model_fits=0, new_Ridge_geometries=0)
    return module, preparation


def reseal_preparation(module, preparation):
    module.write(module.PREP / "preparation.json", preparation)
    module.write(module.PREP / "prepared.json", dict(
        preparation_sha256=module.digest(module.PREP / "preparation.json"),
        source=preparation["source"], config_sha256=preparation["config_sha256"]))


def test_exact_manifest_is_readable(review):
    module, preparation = review
    reseal_preparation(module, preparation)
    assert len(module.read_preparation()["tasks"]) == 18


@pytest.mark.parametrize("change", [
    "truncated", "duplicate_name", "duplicate_pair", "wrong_region",
    "wrong_kind", "test_open", "new_paths", "parent_source", "updated_posterior",
])
def test_even_resealed_manifest_cannot_change_admitted_science(review, change):
    module, preparation = review
    tasks = preparation["tasks"]
    if change == "truncated":
        tasks.pop()
    elif change == "duplicate_name":
        tasks[-1]["name"] = tasks[0]["name"]
    elif change == "duplicate_pair":
        tasks[-1] = copy.deepcopy(tasks[0])
        tasks[-1]["name"] += "_pretend_unique"
    elif change == "wrong_region":
        tasks[0]["region"] = "HR"
    elif change == "wrong_kind":
        tasks[0]["kind"] = "normal_fit"
    elif change == "test_open":
        tasks[0]["test_opened"] = True
    elif change == "new_paths":
        tasks[0]["paths"] = 500
    elif change == "parent_source":
        tasks[0]["parent_source"]["head"] = "relabeled-old-fit"
    else:
        tasks[0]["posterior_moments_reused_without_update"] = False
    reseal_preparation(module, preparation)
    with pytest.raises(RuntimeError):
        module.read_preparation()


def valid_result(task):
    variants = ("deterministic16", "deterministic48", "stochastic16", "stochastic48")
    metric = dict(AQL=2., median_MAE=3., coverage_80=.8, width_80=4.)
    validation = task["panels"]["validation_origin_positions"]
    small = [validation[i] for i in task["panels"]["small"]]
    large = [validation[i] for i in task["panels"]["large"]]
    return dict(kind="cached_rhs_rescore", certified=True,
        candidate_id=task["candidate_id"], split=task["split"], tau0=task["tau0"],
        paths=100, test_opened=False, posterior_updated=False, new_model_fits=0,
        original_cached_moments_unchanged=True,
        numerical_threadpools=[dict(internal_api="openblas", num_threads=1)],
        metrics={key: dict(metric) for key in variants},
        clock_metrics={key: [dict(metric) for _ in range(4)] for key in variants},
        origin_identities=[dict(clock_offset_steps=offset,
            daily_origin_positions_small=list(small), daily_origin_positions_large=list(large),
            stable_rng_origin_keys=[i * 96 + offset for i in large],
            small_reused_from_large=True) for offset in (0, 24, 48, 72)])


def test_complete_result_retains_exact_paired_identity(review):
    module, preparation = review
    task = preparation["tasks"][0]
    module.validate_result(valid_result(task), task)


@pytest.mark.parametrize("change", ["other_origins", "duplicate_origins", "wrong_rng_key", "wrong_clock_average"])
def test_resealed_result_cannot_forge_paired_surface(review, change):
    module, preparation = review
    task = preparation["tasks"][0]
    result = valid_result(task)
    if change == "other_origins":
        for row in result["origin_identities"]:
            row["daily_origin_positions_small"] = [i + 1 for i in row["daily_origin_positions_small"]]
            row["daily_origin_positions_large"] = [i + 1 for i in row["daily_origin_positions_large"]]
    elif change == "duplicate_origins":
        for row in result["origin_identities"]:
            row["daily_origin_positions_small"] = [500] * 4
            row["daily_origin_positions_large"] = [500] * 12
    elif change == "wrong_rng_key":
        result["origin_identities"][2]["stable_rng_origin_keys"][0] += 1
    else:
        result["metrics"]["stochastic48"]["AQL"] = 1.
    with pytest.raises(RuntimeError):
        module.validate_result(result, task)


def test_source_mismatch_cannot_be_laundered_by_a_new_result_hash(review):
    module, preparation = review
    task = preparation["tasks"][0]
    reseal_preparation(module, preparation)
    task_path = module.OUT / "tasks" / (task["name"] + ".json")
    module.write(task_path, task)
    folder = module.OUT / "tasks_done" / task["name"]
    module.write(folder / "result.json", valid_result(task))
    module.write(folder / "completed_evidence.json", dict(
        artifacts={"result.json": module.digest(folder / "result.json")},
        metadata=dict(task_sha256=module.digest(task_path), source_head="another-head", certified=True)))
    with pytest.raises(RuntimeError, match="descriptor changed"):
        module.task_complete(task["name"])
