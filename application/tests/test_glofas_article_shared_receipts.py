#!/usr/bin/env python3
"""Generated exact-scope shared receipt tests; no scientific inputs or remotes."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("glofas_shared_refresh", str(ROOT / "scripts/refresh_glofas_article_shared_receipts.py"))
REFRESH = importlib.util.module_from_spec(spec)
spec.loader.exec_module(REFRESH)


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


class ScopeTests(unittest.TestCase):
    def setUp(self):
        self.baseline = {
            "schema": "independent-forecast-300-500-article-v1",
            "authority_id": "independent_forecast_300_primary_500_sensitivity_v1",
            "sources": {path: digest("old " + path) for path in REFRESH.MUTABLE},
            "outputs": {"tables/generated_science.csv": digest("science")},
            "editorial_source_refresh": {"schema": "retained historical receipt", "updated_paths": ["main.tex", "qdesn-supplement.tex"]},
            "fits_launched": 0, "forecasts_launched": 0, "primary_cutoff": 300,
        }
        self.baseline["sources"]["tables/generated_original.csv"] = digest("original")
        self.hashes = dict(self.baseline["sources"])
        self.hashes.update(self.baseline["outputs"])
        self.hashes.update({path: digest("new " + path) for path in REFRESH.MUTABLE})
        self.context = {
            "added_paths": ["tables/generated_{:02d}.csv".format(i) for i in range(21)],
            "authority_sha256": digest("authority"), "asset_manifest_sha256": digest("manifest"),
            "scored_packet_manifest_sha256": digest("packet"), "refresher_sha256": digest("refresher"),
            "producer_source_commit": "fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6",
        }

    def plan(self, current=None):
        return REFRESH.build_refresh_plan(self.baseline, current or self.baseline, self.hashes.__getitem__, self.context)

    def test_exact_three_paths_and_all_science_preserved(self):
        result = self.plan()
        restored = copy.deepcopy(result)
        field = restored.pop(REFRESH.FIELD)
        for path in REFRESH.MUTABLE:
            self.assertEqual(restored["sources"][path], self.hashes[path])
            restored["sources"][path] = self.baseline["sources"][path]
        self.assertEqual(restored, self.baseline)
        self.assertEqual(field["updated_paths"], list(REFRESH.MUTABLE))
        self.assertFalse(field["scientific_values_changed"])
        self.assertFalse(field["scientific_outputs_regenerated"])
        self.assertEqual(self.plan(result), result)

    def test_repeat_refresh_of_document_only(self):
        previous = self.plan()
        self.hashes["main.tex"] = digest("later main")
        result = self.plan(previous)
        self.assertEqual(result["sources"]["main.tex"], self.hashes["main.tex"])
        self.assertEqual(result["editorial_source_refresh"], self.baseline["editorial_source_refresh"])

    def test_repeat_verified_presentation_context_update(self):
        previous = self.plan()
        self.context["asset_manifest_sha256"] = digest("later presentation")
        self.context["authority_sha256"] = digest("later reviewed authority")
        result = self.plan(previous)
        self.assertEqual(result[REFRESH.FIELD]["asset_manifest_sha256"], self.context["asset_manifest_sha256"])
        self.assertEqual(result["outputs"], self.baseline["outputs"])

    def test_reject_any_noneditorial_mutation(self):
        mutations = [
            lambda value: value.update(fits_launched=1),
            lambda value: value.update(forecasts_launched=1),
            lambda value: value.update(primary_cutoff=1000),
            lambda value: value.update(authority_id="other"),
            lambda value: value.update(unreviewed="field"),
            lambda value: value["outputs"].update({"tables/generated_science.csv": digest("changed")}),
            lambda value: value["sources"].update({"tables/generated_original.csv": digest("changed")}),
            lambda value: value["sources"].update({"tables/extra.csv": digest("changed")}),
            lambda value: value["editorial_source_refresh"].update(schema="modified history"),
        ]
        for mutation in mutations:
            current = copy.deepcopy(self.baseline); mutation(current)
            with self.subTest(mutation=mutation), self.assertRaises(REFRESH.RefreshError):
                self.plan(current)

    def test_reject_immutable_disk_source_or_output_mutation(self):
        for path in ("tables/generated_original.csv", "tables/generated_science.csv"):
            original = self.hashes[path]; self.hashes[path] = digest("disk changed")
            with self.subTest(path=path), self.assertRaises(REFRESH.RefreshError):
                self.plan()
            self.hashes[path] = original

    def test_reject_widened_previous_scope(self):
        mutations = [lambda value: value.update(updated_paths=list(REFRESH.MUTABLE) + ["tables/generated_science.csv"]),
                     lambda value: value.update(scientific_outputs_regenerated=True),
                     lambda value: value.update(original_manifest_sha256="0" * 64),
                     lambda value: value.update(fits_launched=1),
                     lambda value: value["updated_source_sha256"].update({"main.tex": "0" * 64}),
                     lambda value: value.update(unknown="extra")]
        for mutation in mutations:
            current = self.plan(); mutation(current[REFRESH.FIELD])
            with self.subTest(mutation=mutation), self.assertRaises(REFRESH.RefreshError):
                self.plan(current)

    def test_reject_incomplete_context(self):
        for field in ("authority_sha256", "asset_manifest_sha256", "scored_packet_manifest_sha256", "refresher_sha256", "producer_source_commit"):
            original = self.context[field]; self.context[field] = "invalid"
            with self.subTest(field=field), self.assertRaises(REFRESH.RefreshError):
                self.plan()
            self.context[field] = original
        self.context["added_paths"].pop()
        with self.assertRaises(REFRESH.RefreshError):
            self.plan()

    def test_duplicate_json_keys_rejected(self):
        with self.assertRaises(REFRESH.RefreshError):
            REFRESH.decode_json(b'{"sources":{},"sources":{}}', "generated")

    def test_generated_atomic_write_and_check(self):
        with tempfile.TemporaryDirectory(prefix="glofas_generated_receipt_") as directory:
            root = Path(directory); target = root / REFRESH.RECEIPT
            target.parent.mkdir(parents=True)
            before = json.dumps(self.baseline).encode("utf-8"); target.write_bytes(before)
            result = self.plan()
            with mock.patch.object(REFRESH, "prepare", return_value=(root, self.baseline, result, {REFRESH.RECEIPT: REFRESH.sha(before)})):
                with self.assertRaises(REFRESH.RefreshError):
                    REFRESH.refresh(root, write=False)
                REFRESH.refresh(root, write=True)
            self.assertEqual(json.loads(target.read_text()), result)
            self.assertEqual(list(target.parent.glob(".glofas_shared_receipt_*")), [])
            after = target.read_bytes()
            with mock.patch.object(REFRESH, "prepare", return_value=(root, result, result, {REFRESH.RECEIPT: REFRESH.sha(after)})):
                self.assertEqual(REFRESH.refresh(root), result)

    def test_changed_source_during_refresh_rejected(self):
        with tempfile.TemporaryDirectory(prefix="glofas_generated_race_") as directory:
            root = Path(directory); target = root / REFRESH.RECEIPT
            target.parent.mkdir(parents=True); target.write_text("changed")
            with mock.patch.object(REFRESH, "prepare", return_value=(root, self.baseline, self.plan(), {REFRESH.RECEIPT: digest("original")})):
                with self.assertRaises(REFRESH.RefreshError):
                    REFRESH.refresh(root, write=True)
            self.assertEqual(target.read_text(), "changed")


class AllowlistTests(unittest.TestCase):
    def setUp(self):
        self.before = b"# Retained exact comment\n\na/a.tex\nz/z.tex\n"
        self.added = {"tables/generated_{:02d}.csv".format(i) for i in range(21)}
        self.after = b"# Retained exact comment\n\n" + ("\n".join(sorted({"a/a.tex", "z/z.tex"} | self.added)) + "\n").encode("utf-8")

    def test_exact_sorted_additions_preserve_original_bytes(self):
        self.assertEqual(REFRESH.verify_allowlist(self.before, self.after, self.added), sorted(self.added))

    def test_reject_every_unapproved_allowlist_change(self):
        cases = [self.after.replace(b"a/a.tex\n", b""), self.after.replace(b"# Retained", b"# Changed"),
                 self.after.replace(b"z/z.tex\n", b"zz/new.tex\nz/z.tex\n"),
                 self.after.replace(b"a/a.tex\n", b"a/a.tex\na/a.tex\n"),
                 self.after.replace(b"tables/generated_00.csv\n", b""),
                 self.after.replace(b"\n", b"\r\n"),
                 self.after.replace(b"a/a.tex\n", b" a/a.tex\n")]
        # Deliberately unsort two existing entries as an additional exact-order test.
        lines = self.after.decode().splitlines(keepends=True)
        lines[2], lines[-1] = lines[-1], lines[2]
        cases.append("".join(lines).encode())
        for index, current in enumerate(cases):
            with self.subTest(index=index), self.assertRaises(REFRESH.RefreshError):
                REFRESH.verify_allowlist(self.before, current, self.added)


if __name__ == "__main__":
    unittest.main()
