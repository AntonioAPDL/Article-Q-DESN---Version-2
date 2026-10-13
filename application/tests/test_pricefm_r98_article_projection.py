"""Article-contract checks for the complete PriceFM R98 authority."""

from __future__ import annotations

import csv
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "pricefm_r98_projection_checker", ROOT / "scripts/check_pricefm_r98_article_projection.py"
)
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


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


class PriceFMProjectionMutationTest(unittest.TestCase):
    """An isolated display fixture cannot change its scientific authority."""

    @classmethod
    def setUpClass(cls):
        CHECKER.check(ROOT)
        cls.fixture_temp = tempfile.TemporaryDirectory(prefix="pricefm-editorial-fixture-")
        cls.fixture = Path(cls.fixture_temp.name)
        dependencies = CHECKER.presentation_checker(ROOT).dependency_paths(ROOT)
        manifest = json.loads((ROOT / "tables/pricefm_r98_article_projection_manifest.json").read_text())
        dependencies.update(row["path"] for row in manifest["outputs"])
        dependencies.update({
            "tables/pricefm_r98_article_projection_manifest.json",
            "overleaf/article_files.txt", "main.tex", "qdesn-supplement.tex",
            CHECKER.PRESENTATION_CHECKER,
        })
        for relative in dependencies:
            path = cls.fixture / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, path)

    @classmethod
    def tearDownClass(cls):
        cls.fixture_temp.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pricefm-editorial-mutation-")
        self.root = Path(self.temp.name)
        shutil.copytree(self.fixture, self.root, dirs_exist_ok=True)

    def tearDown(self):
        self.temp.cleanup()

    def test_isolated_current_projection_passes(self):
        self.assertEqual(CHECKER.check(self.root)["rows"], 114)

    def test_coordinated_scientific_manifest_edit_is_rejected(self):
        path = self.root / "tables/pricefm_r98_article_projection_manifest.json"
        receipt = json.loads(path.read_text())
        receipt["mean_AQL"]["R98_QDESN"] = 6.8
        path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(RuntimeError, "original PriceFM projection manifest changed"):
            CHECKER.check(self.root)

    def test_original_registry_edit_is_rejected(self):
        path = self.root / "tables/pricefm_r98_authoritative_registry.csv"
        with path.open("a") as stream:
            stream.write("\n")
        with self.assertRaisesRegex(RuntimeError, "output (size|hash) changed"):
            CHECKER.check(self.root)

    def test_old_publication_display_is_rejected(self):
        path = self.root / "overleaf/article_files.txt"
        with path.open("a") as stream:
            stream.write("figures/pricefm_application/pricefm_r98_region_aql_comparison.pdf\n")
        with self.assertRaisesRegex(RuntimeError, "superseded|allowlist|publication"):
            CHECKER.check(self.root)


if __name__ == "__main__":
    unittest.main()
