"""Meaningful failure tests on synthetic JSON; no real evidence/network opened."""
import ast
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

P = Path(__file__).with_name('training_evidence_read.py')
spec = importlib.util.spec_from_file_location('bounded_training_evidence_read',P)
reader = importlib.util.module_from_spec(spec);spec.loader.exec_module(reader)

class ReaderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
    def tearDown(self): self.tmp.cleanup()
    def file(self,value):
        p=self.root/'input.json';p.write_text(value);return p
    def test_missing_is_explicit(self):
        self.assertEqual(reader.read_one(self.root/'absent.json')['exists'],False)
    def test_original_exact_bytes_are_pinned(self):
        p=self.file('{"score": 3.5}\n');x=reader.read_one(p)
        self.assertEqual(x['bytes'],p.stat().st_size)
        self.assertEqual(reader.base64.b64decode(x['base64']),p.read_bytes())
    def test_symlink_is_rejected(self):
        p=self.file('{}');link=self.root/'alias.json';link.symlink_to(p)
        with self.assertRaises(ValueError):reader.read_one(link)
    def test_parent_symlink_is_rejected(self):
        target=self.root/'directory';target.mkdir();(target/'x.json').write_text('{}')
        alias=self.root/'alias';alias.symlink_to(target,target_is_directory=True)
        with self.assertRaises(ValueError):reader.read_one(alias/'x.json')
    def test_duplicate_keys_are_rejected(self):
        with self.assertRaises(ValueError):reader.read_one(self.file('{"a":1,"a":2}'))
    def test_nonfinite_and_overflow_are_rejected(self):
        for value in ('NaN','Infinity','1e999'):
            p=self.root/'input.json';p.write_text('{"value":'+value+'}')
            with self.assertRaises(ValueError):reader.read_one(p)
    def test_oversized_metadata_is_rejected(self):
        p=self.root/'input.json';p.write_bytes(b' '* (reader.MAX_BYTES+1))
        with self.assertRaises(ValueError):reader.read_one(p)
    def test_directory_is_rejected(self):
        with self.assertRaises(ValueError):reader.read_one(self.root)
    def test_relative_path_is_rejected(self):
        with self.assertRaises(ValueError):reader.read_one(Path('relative.json'))
    def test_source_is_python36_compatible(self):
        ast.parse(P.read_text(),feature_version=(3,6))

if __name__=='__main__':unittest.main(verbosity=2)
