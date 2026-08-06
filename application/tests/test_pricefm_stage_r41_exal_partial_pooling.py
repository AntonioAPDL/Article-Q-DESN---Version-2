import importlib.util
import sys
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts/pricefm/167_prepare_pricefm_stage_r41_exal_partial_pooling.py"
if str(SCRIPT.parent) not in sys.path:
    sys.path.insert(0, str(SCRIPT.parent))


def module():
    spec = importlib.util.spec_from_file_location("r41", SCRIPT)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def test_capability_audit_detects_consumed_exal_pooling(tmp_path):
    mod = module()
    source = tmp_path / "runner.R"
    source.write_text('c("al", "exal")\nfit_qdesn_like("exal"\nfit_qdesn_horizon_separate("exal"\nfor (likelihood in qdesn_likelihoods)\npricefm_partial_pool_predictions(\ngamma_policy = if (identical(likelihood, "al")) "zero" else "source"\nnested_partial_pooling_metrics.csv')
    assert mod.capability_audit(source)["passed"].all()


def test_grid_keeps_only_targets_and_changes_likelihood():
    mod = module()
    source = {"pricefm_desn_experiment_grid": {
        "grid_id": "r39", "purpose": "old",
        "base": {}, "scope": {"regions": [], "folds": [], "splits": ["train", "val"]},
        "fixed": {"qdesn_likelihoods": ["al"]}, "launch": {},
        "experiments": [
            {"id": "r39_a", "regions": ["AA"], "folds": [1]},
            {"id": "r39_b", "regions": ["BB"], "folds": [2]},
        ],
    }}
    payload = mod.build_grid(source, {"r39_b"}, Path("out"), Path("grid"), Path("run"), list(range(16, 22)), True)
    grid = payload["pricefm_desn_experiment_grid"]
    assert grid["fixed"]["qdesn_likelihoods"] == ["exal"]
    assert [item["id"] for item in grid["experiments"]] == ["r41_b"]
    assert grid["scope"]["splits"] == ["train", "val"]


def test_launch_command_preserves_venv_path():
    source = SCRIPT.read_text()
    assert "args.python_bin.absolute()" in source
    assert "rows_test.csv" not in source
