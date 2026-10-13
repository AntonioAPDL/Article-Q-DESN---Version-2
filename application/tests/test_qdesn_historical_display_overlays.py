"""Exact-source and fail-closed tests for two presentation-only TeX overlays."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("qdesn_historical_display", ROOT / "scripts/build_qdesn_historical_display_overlays.py")
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)


class HistoricalDisplayTests(unittest.TestCase):
    def test_exact_sources_and_reproducible_derivatives(self):
        manifest = BUILDER.check(ROOT)
        self.assertEqual(len(manifest["assets"]), 2)
        self.assertEqual(manifest["new_model_runs"], 0)
        self.assertEqual(manifest["scores_recomputed"], 0)
        for contract in BUILDER.CONTRACTS:
            source = (ROOT / contract["source"]).read_text()
            self.assertEqual((ROOT / contract["output"]).read_text(), BUILDER.mapped_source(source, contract))

    def test_historical_header_does_not_claim_current_model_equivalence(self):
        table = (ROOT / BUILDER.CONTRACTS[0]["output"]).read_text()
        self.assertIn("Historical multiquantile", table)
        self.assertIn("Historical replicated VB comparison", table)
        self.assertNotIn("MQ--DESN", table)
        self.assertNotIn("Joint: AL-exAL", table)
        self.assertEqual(table.count(" & 50 "), 8)
        uncertainty = (ROOT / BUILDER.CONTRACTS[1]["output"]).read_text()
        self.assertIn("For Q--DESN under AL and exAL", uncertainty)
        self.assertIn("pre-specified product coupling", uncertainty)

    def test_missing_or_duplicated_old_wording_is_rejected(self):
        for contract in BUILDER.CONTRACTS:
            original = (ROOT / contract["source"]).read_text()
            old = contract["replacements"][0][0]
            with self.assertRaises(AssertionError):
                BUILDER.mapped_source(original.replace(old, "unexpected", 1), contract)
            with self.assertRaises(AssertionError):
                BUILDER.mapped_source(original + "\n" + old, contract)

    def test_numerical_and_source_tampering_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="qdesn-historical-display-negative-") as temporary:
            root = Path(temporary)
            for contract in BUILDER.CONTRACTS:
                for field in ("source", "output"):
                    destination = root / contract[field]
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(ROOT / contract[field], destination)
            (root / BUILDER.MANIFEST).write_bytes((ROOT / BUILDER.MANIFEST).read_bytes())
            output = root / BUILDER.CONTRACTS[0]["output"]
            output.write_text(output.read_text().replace("-0.054", "-0.055", 1))
            with self.assertRaises(AssertionError):
                BUILDER.check(root)
            source = root / BUILDER.CONTRACTS[0]["source"]
            source.write_text(source.read_text().replace("-0.054", "-0.055", 1))
            with self.assertRaises(AssertionError):
                BUILDER.build(root, root)


if __name__ == "__main__":
    unittest.main(verbosity=2)
