"""Typed metadata regressions for the real R builtin-handle enumeration issue.

No R, DLL, optimizer, target input or namespace is executed by these tests.
"""
import unittest

from . import scientific_metadata_owner as owner
from . import scientific_batch as batch
from . import scientific_batch_tests as fixtures


class NamespaceIntrinsicTests(unittest.TestCase):
    def fixture(self):
        helper=fixtures.ScientificRegressionTests();ns=helper.namespace();frame=helper.frame()
        native=dict(path='/new/code/R_HOME/bin/exec/R',sha256='9d76330f01cace4574a9ec7a5407ca50b9faacc9813bbf4339595582e5c33c27')
        spec=dict(role=batch.ROLES[0],job_id='999',node='node-13',nonce='a'*32,affinity=[0],R_native=native)
        frame['builtin_DLLs']=[dict(entry_name='base',name='base',path='base',kind='R_INTRINSIC_NO_EXTERNAL_FILE',external_file=False,native_R=native)]
        return spec,ns,frame

    def test_exact_intrinsic_base_has_native_binding_and_no_fabricated_external_hash(self):
        spec,ns,frame=self.fixture();owner.validate_frames([frame],spec,ns)
        self.assertNotIn('sha256',frame['builtin_DLLs'][0])
        self.assertEqual(frame['builtin_DLLs'][0]['native_R'],spec['R_native'])

    def test_missing_duplicate_and_unknown_intrinsics_cannot_pass(self):
        for value in [None,[],[{},{}],[dict(name='other',path='other')]]:
            spec,ns,frame=self.fixture();frame['builtin_DLLs']=value
            with self.subTest(value=value),self.assertRaises(ValueError):owner.validate_frames([frame],spec,ns)
        spec,ns,frame=self.fixture();frame['builtin_DLLs']*=2
        with self.assertRaises(ValueError):owner.validate_frames([frame],spec,ns)

    def test_intrinsic_name_path_kind_external_flag_and_record_shape_are_exact(self):
        for field,value in [('entry_name','other'),('name','Base'),('path','/missing/base.so'),('kind','FILE'),('external_file',True),('external_file',0),('sha256','0'*64)]:
            spec,ns,frame=self.fixture();frame['builtin_DLLs'][0][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):owner.validate_frames([frame],spec,ns)

    def test_intrinsic_is_bound_to_current_native_executable_path_and_bytes(self):
        for field,value in [('path','/other/R'),('sha256','0'*64)]:
            spec,ns,frame=self.fixture();frame['builtin_DLLs'][0]['native_R']=dict(spec['R_native']);frame['builtin_DLLs'][0]['native_R'][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):owner.validate_frames([frame],spec,ns)
        spec,ns,frame=self.fixture();spec['R_native']=dict(path='/other/R',sha256=spec['R_native']['sha256'])
        with self.assertRaises(ValueError):owner.validate_frames([frame],spec,ns)

    def test_unknown_pseudo_empty_relative_or_missing_external_DLL_cannot_be_skipped(self):
        for path in ['base','other-pseudo','','relative/lib.so','/new/code/R_HOME/library/missing/libs/unknown.so']:
            spec,ns,frame=self.fixture();frame['loaded_DLLs'].append(dict(entry_name='unknown',name='unknown',path=path,sha256='0'*64))
            with self.subTest(path=path),self.assertRaises(ValueError):owner.validate_frames([frame],spec,ns)
        spec,ns,frame=self.fixture();frame['loaded_DLLs'].pop()
        with self.assertRaises(ValueError):owner.validate_frames([frame],spec,ns)

    def test_builtin_exception_does_not_relax_real_DLL_hash_or_file_identity(self):
        spec,ns,frame=self.fixture();frame['loaded_DLLs'][0]['sha256']='0'*64
        with self.assertRaises(ValueError):owner.validate_frames([frame],spec,ns)
        for field in ['entry_name','name']:
            spec,ns,frame=self.fixture();frame['loaded_DLLs'][0][field]='base'
            with self.subTest(field=field),self.assertRaises(ValueError):owner.validate_frames([frame],spec,ns)
        spec,ns,frame=self.fixture();frame['loaded_DLLs'][0]['external_file']=False
        with self.assertRaises(ValueError):owner.validate_frames([frame],spec,ns)


if __name__=='__main__':unittest.main()
