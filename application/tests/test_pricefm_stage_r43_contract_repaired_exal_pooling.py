import importlib.util
import sys
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts/pricefm/169_prepare_pricefm_stage_r43_contract_repaired_exal_pooling.py"
if str(SCRIPT.parent) not in sys.path:
    sys.path.insert(0, str(SCRIPT.parent))


def module():
    spec = importlib.util.spec_from_file_location("r43", SCRIPT)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def source_grid():
    return {"pricefm_desn_experiment_grid": {
        "grid_id": "r41",
        "purpose": "old",
        "base": {},
        "scope": {"regions": [], "folds": [], "splits": ["train", "val"], "quantiles": [0.5]},
        "fixed": {
            "qdesn_likelihoods": ["exal"],
            "normal": {"enabled": False},
            "warm_start": {"enabled": False},
            "exact_equivalence": {"enabled": False},
            "artifact_hygiene": {"preserve_patterns": []},
        },
        "launch": {},
        "experiments": [{
            "id": "r41_a", "regions": ["AA"], "folds": [2],
            "source_r34_experiment_id": "r33_a", "readout_interaction": "none",
            "training": {"horizon_weighting": {"max_expansion_factor": 8}},
        }],
    }}


def test_grid_restores_selected_contract_and_enables_consumed_chain():
    mod = module()
    selected = {"r33_a": {
        "adapter": {"spatial": {"graph_degree": 1, "neighbor_regions": ["BB"], "max_neighbor_regions": 1}},
        "training": {"train_origin_limit": 3000, "horizon_weighting": {"max_expansion_factor": 6}},
    }}
    payload = mod.build_grid(
        source_grid(), {"r41_a"}, selected, Path("out"), Path("grid"), Path("runs"), list(range(6)), True,
    )
    grid = payload["pricefm_desn_experiment_grid"]
    assert grid["fixed"]["qdesn_likelihoods"] == ["al", "exal"]
    assert grid["fixed"]["normal"]["enabled"] is True
    assert grid["fixed"]["warm_start"]["enabled"] is True
    assert grid["fixed"]["warm_start"]["fallback_to_cold"] is False
    assert grid["fixed"]["warm_start"]["qdesn"]["exal"]["source"] == "al_same_tau"
    assert "nested_warm_start_diagnostics.csv" in grid["fixed"]["artifact_hygiene"]["preserve_patterns"]
    experiment = grid["experiments"][0]
    assert experiment["id"] == "r43_a"
    assert experiment["spatial"] == selected["r33_a"]["adapter"]["spatial"]
    assert experiment["training"] == selected["r33_a"]["training"]
    assert experiment["readout_interaction"] == "none"


def test_capability_audit_passes_real_runner():
    mod = module()
    runner = Path(__file__).parents[1] / "scripts/pricefm/08_run_desn_model_smoke.R"
    assert mod.capability_audit(runner)["passed"].all()


def test_prep_never_invokes_launcher_or_reads_test_rows():
    source = SCRIPT.read_text()
    assert "subprocess" not in source
    assert "rows_test.csv" not in source
    assert '"test_inspected": False' in source
    assert '"--authorize-launch", type=parse_bool, default=False' in source
