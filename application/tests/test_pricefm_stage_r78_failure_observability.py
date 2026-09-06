from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "application/scripts/pricefm/259_run_pricefm_stage_r76_repaired_exal_component.R"
RTEST = ROOT / "application/tests/test_pricefm_stage_r78_failure_observability.R"


def test_runner_persists_field_level_failure_diagnostics():
    text = RUNNER.read_text()
    assert 'file.path(output, "failure_diagnostics.json")' in text
    assert 'stage = "fit_exception"' in text
    assert 'stage = "terminal_contract"' in text
    assert "failed_fields = contract$failed_fields" in text
    assert 'task_stage %in% c("R80D", "R82D")' in text
    assert 'scientific_repair_mode <- task_stage %in% c("R83", "R87")' in text
    assert "exdqlm.pricefm_failure_callback" in text


def test_named_contract_checks_execute_in_r():
    subprocess.run(["Rscript", str(RTEST)], check=True)


def test_runner_retains_firewalls_and_no_binary_writer():
    text = RUNNER.read_text()
    assert 'c("X_test.csv", "y_test.csv", "rows_test.csv")' in text
    assert "saveRDS(" not in text and "save(" not in text
