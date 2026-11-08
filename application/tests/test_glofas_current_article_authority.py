#!/usr/bin/env python3
"""Focused mutation tests for the current GloFAS hybrid authority guard."""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/glofas_current_article_authority.py"
SPEC = importlib.util.spec_from_file_location("glofas_authority", str(SCRIPT))
GUARD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GUARD)


class AuthorityFixture:
    """Reusable exact-tree fixture for editorial adapter mutation tests."""
    def __init__(self, base):
        self.root = Path(base)
        for relative in GUARD.authority_dependency_paths(ROOT):
            source = ROOT / relative
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(str(source), str(target))
        self.main = (self.root / "main.tex").read_text()
        self.supp = (self.root / "qdesn-supplement.tex").read_text()

    def write(self, relative, value):
        target = self.root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(value, bytes):
            target.write_bytes(value)
        else:
            target.write_text(value)


class HybridAuthorityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="glofas_hybrid_authority_")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for relative in GUARD.authority_dependency_paths(ROOT):
            source = ROOT / relative
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(str(source), str(target))

    def assert_rejected(self, fragment):
        with self.assertRaises(GUARD.AuthorityError) as context:
            GUARD.validate_authority_tree(self.root)
        self.assertIn(fragment, str(context.exception))

    def test_current_tree_and_complete_surface_pass(self):
        authority = GUARD.validate_authority_tree(self.root)
        self.assertEqual(authority["status"], "FINAL_SCIENTIFIC_ACCEPTANCE_PASS")
        self.assertEqual(authority["final_acceptance_receipt"]["hard_gates_passed"], 12)
        self.assertEqual(len(GUARD.EXPECTED_ASSETS), 16)

    def test_rejected_november_alias_cannot_be_reactivated(self):
        path = self.root / "main.tex"
        path.write_text(path.read_text() + "\n\\input{" + GUARD.REJECTED_ALIAS + "}\n")
        self.assert_rejected("rejected November alias remains active")

    def test_public_score_mutation_breaks_manifest(self):
        path = self.root / ("tables/" + GUARD.PREFIX + "_part4_scores.csv")
        path.write_text(path.read_text().replace("0.929869042793488", "0.929869042793489", 1))
        self.assert_rejected("asset bytes differ")

    def test_path_prior_lineage_cannot_change(self):
        path = self.root / GUARD.AUTHORITY_PATH
        path.write_text(path.read_text().replace(
            "0202bc19e26d84d6cbb55c2256a2071695f9c386c9dc64933005bd4d5acbb357",
            "1202bc19e26d84d6cbb55c2256a2071695f9c386c9dc64933005bd4d5acbb357"))
        self.assert_rejected("reviewed source lineage differs")

    def test_final_acceptance_receipt_cannot_change(self):
        path = self.root / GUARD.ACCEPTANCE_PATH
        path.write_text(path.read_text().replace('"hard_gates_passed": 12',
                                                 '"hard_gates_passed": 11'))
        self.assert_rejected("final scientific-acceptance receipt hash differs")

    def test_rejected_reporting_rule_cannot_return(self):
        path = self.root / "main.tex"
        path.write_text(path.read_text() +
                        "\n% m_{p,h}+\\Phi^{-1}(p)\\sqrt{V_{p,hh}}\n")
        self.assert_rejected("rejected November target language remains active")


if __name__ == "__main__":
    unittest.main()
