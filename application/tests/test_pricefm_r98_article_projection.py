"""Article-contract checks for the complete PriceFM R98 authority."""

from __future__ import annotations

import csv
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_pricefm_r98_projection_is_complete_and_reader_facing():
    completed = subprocess.run(
        [sys.executable, str(ROOT / "scripts/check_pricefm_r98_article_projection.py")],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    assert "PRICEFM_R98_ARTICLE_CHECK=PASS" in completed.stdout

    with (ROOT / "tables/pricefm_r98_authoritative_registry.csv").open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    assert len(rows) == 114
    assert len({row["region"] for row in rows}) == 38
    assert {int(row["fold"]) for row in rows} == {1, 2, 3}
    assert all(row["selection_is_validation_only"] == "True" for row in rows)
    assert all(row["test_driven_case_mixing_used"] == "False" for row in rows)
    assert all(row["R92_case_fallback_used"] == "False" for row in rows)

    manifest = json.loads(
        (ROOT / "tables/pricefm_r98_article_projection_manifest.json").read_text()
    )
    assert manifest["mean_AQL"] == {
        "R98_QDESN": 7.217007319836696,
        "cached_PriceFM": 7.03868534653447,
        "deprecated_R92_QDESN": 6.823677420470439,
    }
    assert manifest["qdesn_lower_cases"] == 54
    assert manifest["pricefm_lower_cases"] == 60
