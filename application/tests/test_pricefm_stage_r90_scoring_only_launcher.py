import importlib.util
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/286_launch_pricefm_stage_r90_scoring_only_test_audit.py"


def load():
    spec = importlib.util.spec_from_file_location("pricefm_r90_launcher", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_cpu_parser_requires_unique_online_ids():
    module = load()
    assert module.parse_cpus("0,2-3") == [0, 2, 3]


def test_launcher_is_explicit_scoring_only_and_resumable():
    text = SCRIPT.read_text()
    assert "one_process_per_cpu" in text
    assert "skipped_completed" in text
    assert '("task_config_sha256", "task_config_sha256")' in text
    assert "R90 scoring launch requires explicit --authorize" in text
    assert '"model_refits": 0' in text
    assert '"registry_mutated": False' in text
    assert "259_run_pricefm" not in text
