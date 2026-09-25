from __future__ import annotations

import csv
import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "search3_seal", ROOT / "application/scripts/433_seal_glofas_search3_stage.py"
)
seal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(seal)


class Search3StageSealTest(unittest.TestCase):
    def test_inventory_excludes_derived_tables(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "scores").mkdir(); (root / "tables").mkdir(); (root / "reports").mkdir()
            (root / "scores/a.csv").write_text("x\n1\n")
            (root / "tables/derived.csv").write_text("x\n2\n")
            (root / "reports/derived.md").write_text("derived\n")
            rows = seal.inventory(root)
            self.assertEqual([row["relative_path"] for row in rows], ["scores/a.csv"])

    def test_atomic_csv_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "manifest.csv"
            seal.atomic_csv(path, [{"a": "x", "b": 1}], ["a", "b"])
            with path.open(newline="") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(rows, [{"a": "x", "b": "1"}])


if __name__ == "__main__":
    unittest.main()
