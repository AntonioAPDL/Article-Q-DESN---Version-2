"""Metadata/opaque-code tests only; no R, ELF execution or target arrays."""
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from . import scientific_runtime_carrier as m


class ClosureTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(dir='/dev/shm');self.root=Path(self.tmp.name)
    def tearDown(self):self.tmp.cleanup()

    def test_description_continuations_and_dependency_scope(self):
        p=self.root/'DESCRIPTION';p.write_text('Package: toy\nVersion: 1.0\nImports: stats,\n methods, Rcpp (>= 1.0)\nSuggests: forbiddenDatasetPackage\nLinkingTo: BH\n')
        f=m.description(p)
        self.assertEqual(m.dependencies(f),['Rcpp','methods','stats'])
        self.assertNotIn('BH',m.dependencies(f))

    def test_duplicate_or_unsafe_description_is_rejected(self):
        p=self.root/'DESCRIPTION';p.write_text('Package: x\nPackage: y\n')
        with self.assertRaises(ValueError):m.description(p)
        with self.assertRaises(ValueError):m.dependencies({'Imports':'../../target'})

    def test_installed_data_and_documentation_are_not_carried(self):
        p=self.root/'toy';(p/'R').mkdir(parents=True);(p/'data').mkdir();(p/'doc').mkdir()
        (p/'R'/'toy.rdb').write_bytes(b'opaque-code');(p/'data'/'scientific.rda').write_bytes(b'not-read');(p/'doc'/'vignette.pdf').write_bytes(b'not-read')
        src,omitted=m.code_sources({'toy':{'path':str(p)}},{})
        self.assertEqual(set(src),{'R_HOME/library/toy/R/toy.rdb'})
        self.assertEqual(omitted['toy'],['data','doc'])

    def test_code_symlink_escape_and_base_collision_fail(self):
        p=self.root/'toy';p.mkdir();outside=self.root/'target.bin';outside.write_bytes(b'target')
        (p/'escape').symlink_to(outside)
        with self.assertRaises(ValueError):m.code_sources({'toy':{'path':str(p)}},{})
        (p/'escape').unlink();(p/'DESCRIPTION').write_text('code')
        with self.assertRaises(ValueError):m.code_sources({'toy':{'path':str(p)}},{'R_HOME/library/toy/DESCRIPTION':{'sha256':'0'*64}})

    def test_base_members_are_reused_only_for_identical_bytes(self):
        p=self.root/'toy';p.mkdir();f=p/'DESCRIPTION';f.write_text('code')
        src,_=m.code_sources({'toy':{'path':str(p)}},{'R_HOME/library/toy/DESCRIPTION':{'sha256':hashlib.sha256(b'code').hexdigest()}})
        self.assertEqual(src,{})

    def test_partitions_retain_unchanged_archive_caps(self):
        rows=[{'relative':'R_HOME/library/x/file%d'%i,'bytes':60*1024**2,'mode':0o644} for i in range(3)]
        parts=m.partition(rows)
        self.assertEqual([len(x) for x in parts],[1,1,1])
        with self.assertRaises(ValueError):m.partition([dict(rows[0],bytes=65*1024**2)])

    def test_host_glibc_is_not_bundled(self):
        p=self.root/'x.so';p.write_bytes(b'opaque')
        with patch.object(m.native,'dynamic',return_value=(['libc.so.6'],['GLIBC_2.28'])):
            src,proof=m.native_closure({'R_HOME/library/x/libs/x.so':p},{})
        self.assertEqual(list(src),['R_HOME/library/x/libs/x.so'])
        self.assertEqual(proof['host_glibc_not_bundled'],['libc.so.6'])
        self.assertTrue(proof['actual_compute_ABI_and_namespace_startup_required'])


if __name__=='__main__':unittest.main()
