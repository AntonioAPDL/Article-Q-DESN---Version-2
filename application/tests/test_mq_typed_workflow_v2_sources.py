#!/usr/bin/python3.11
"""Pure source inventory negatives plus exact current tracked-byte check."""
import copy
import csv
import hashlib
import importlib.util
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('v2_source_guard',ROOT/'scripts/check_mq_typed_workflow_v2_sources.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class SourceTests(unittest.TestCase):
    def rows(self):
        with (ROOT/m.MANIFEST).open() as stream:return list(csv.DictReader(stream))
    def test_exact_source(self):
        result=m.check(ROOT,hashlib.sha256((ROOT/m.MANIFEST).read_bytes()).hexdigest())
        self.assertFalse(result['production_authorized']);self.assertEqual(result['legacy_files'],27)
    def test_structure_negatives(self):
        rows=self.rows();bad_cases=[rows[:-1],rows+rows[-1:],list(reversed(rows))]
        for key,value in [('path','scripts/unlisted.R'),('role','production_authorized'),('mode','100755'),
                          ('sha256','0'),('blob','bad')]:
            bad=copy.deepcopy(rows);bad[0][key]=value;bad_cases.append(bad)
        for bad in bad_cases:
            with self.assertRaises(ValueError):m.structure(bad)
    def test_bad_pin(self):
        with self.assertRaises(ValueError):m.check(ROOT,'0'*64)

if __name__=='__main__':unittest.main()
