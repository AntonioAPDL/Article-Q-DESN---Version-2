#!/usr/bin/env python3
"""Focused tests for the R111D BG comparison book."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/393_plot_pricefm_r111b_bg_recursive_comparison.py"
SPEC = importlib.util.spec_from_file_location("pricefm_r111d", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


def synthetic_cases() -> list[dict[str, object]]:
    cases = []
    for fold, origins in ((1, 4), (2, 5), (3, 6)):
        horizon = np.arange(96, dtype=float)[None, :]
        origin = np.arange(origins, dtype=float)[:, None]
        truth = 50.0 + fold + 0.04 * horizon + 0.2 * origin
        predictions = {}
        for method, bias, width in (
            ("r111b", 0.3, 8.0),
            ("r97", 0.1, 9.0),
            ("pricefm", 0.5, 7.0),
        ):
            median = truth + bias + 0.01 * horizon
            offsets = np.asarray((-width, -0.5 * width, -1.0, 0.0, 1.0, 0.5 * width, width))
            predictions[method] = median[None, :, :] + offsets[:, None, None]
        cases.append({
            "fold": fold,
            "truth": truth,
            "predictions": predictions,
            "anchors": np.asarray([f"2026-0{fold}-{day + 1:02d}T00:00:00+00:00" for day in range(origins)]),
        })
    return cases


def test_scoring_and_pooling() -> None:
    cases = synthetic_cases()
    for case in cases:
        for prediction in case["predictions"].values():
            MODULE.validate_surface(case["truth"], prediction, case["anchors"])
    tables = MODULE.metric_tables(cases)
    assert len(tables["metrics"]) == 12
    assert set(tables["metrics"].fold) == {0, 1, 2, 3}
    assert len(tables["horizons"].query("fold == 0")) == 3 * 96
    assert len(tables["blocks"].query("fold == 0")) == 3 * 4
    assert len(tables["quantiles"].query("fold == 0")) == 3 * 7
    assert np.isfinite(tables["metrics"].select_dtypes(include=[np.number])).all().all()
    for case in cases:
        index = MODULE.representative_origin(case)
        assert 0 <= index < case["truth"].shape[0]


def test_alignment_guards() -> None:
    case = synthetic_cases()[0]
    good = case["predictions"]["r111b"]
    MODULE.validate_surface(case["truth"], good, case["anchors"])
    try:
        MODULE.validate_surface(case["truth"], good[:, :, :-1], case["anchors"])
    except RuntimeError as error:
        assert "geometry" in str(error)
    else:
        raise AssertionError("invalid horizon geometry was accepted")
    broken = good.copy()
    broken[0, 0, 0] = np.nan
    try:
        MODULE.validate_surface(case["truth"], broken, case["anchors"])
    except RuntimeError as error:
        assert "nonfinite" in str(error)
    else:
        raise AssertionError("nonfinite surface was accepted")


def test_pdf_generation() -> None:
    cases = synthetic_cases()
    tables = MODULE.metric_tables(cases)
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "diagnostics.pdf"
        pages = MODULE.write_pdf(path, cases, tables)
        assert pages == 10
        assert path.is_file()
        assert path.stat().st_size > 50_000


def main() -> int:
    test_scoring_and_pooling()
    test_alignment_guards()
    test_pdf_generation()
    print("R111D BG recursive comparison tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
