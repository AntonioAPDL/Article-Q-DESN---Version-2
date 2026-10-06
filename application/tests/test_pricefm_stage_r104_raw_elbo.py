from __future__ import annotations

import importlib.util
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/351_plot_pricefm_stage_r104_raw_elbo.py"


def load_script():
    spec = importlib.util.spec_from_file_location(SCRIPT.stem, SCRIPT)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


AUDIT = load_script()


def test_summarize_trace_reports_raw_terminal_behavior() -> None:
    elbo = np.asarray([-100.0, -20.0, -5.0, -1.0, -0.5, -0.25])
    trace = pd.DataFrame({
        "iter": np.arange(1, len(elbo) + 1),
        "elbo": elbo,
        "delta_elbo": np.r_[np.nan, np.diff(elbo)],
    })
    result = AUDIT.summarize_trace(trace)
    assert result["initial_elbo"] == -100.0
    assert result["final_elbo"] == -0.25
    assert result["maximum_elbo"] == -0.25
    assert result["final_minus_maximum"] == 0.0
    assert result["decrease_count"] == 0
    assert result["last_10_change"] == 99.75


def test_summarize_trace_detects_nonmonotone_terminal() -> None:
    elbo = np.asarray([-4.0, -2.0, -1.0, -1.5])
    trace = pd.DataFrame({
        "iter": np.arange(1, len(elbo) + 1),
        "elbo": elbo,
        "delta_elbo": np.r_[np.nan, np.diff(elbo)],
    })
    result = AUDIT.summarize_trace(trace)
    assert result["decrease_count"] == 1
    assert result["largest_decrease"] == -0.5
    assert result["final_minus_maximum"] == -0.5


def test_raw_elbo_script_is_read_only_and_keeps_launch_blocked() -> None:
    source = SCRIPT.read_text()
    assert "subprocess" not in source
    assert '"broad_relaunch_authorized": False' in source
    assert '"models_refitted": False' in source
    assert '"test_opened": False' in source
    assert '"pending_user_visual_review"' in source
