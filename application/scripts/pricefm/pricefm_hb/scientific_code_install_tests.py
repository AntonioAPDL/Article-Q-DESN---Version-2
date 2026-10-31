import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from . import scientific_code_install as m
from . import runtime_archive as a


class InstallGateTests(unittest.TestCase):
    def fixture(self):
        pins=[{'path':'/meta/'+n+'.json','sha256':str(i)*64} for i,n in enumerate(['spec','authority','review'],1)]
        spec={'schema':'r179_scientific_code_install_spec_v1','purpose':m.n.PURPOSE,
              'bounds':{'files':m.n.MAX_FILES,'bytes':m.n.MAX_BYTES,'one_file_bytes':m.n.MAX_FILE},
              'R_executions':0,'scientific_target_data':False,'optimizer_invocations':0,'job_id':'999','node':'node-13','affinity':[0]}
        auth={'status':'ROOT_ADMITTED_NEW_SCIENTIFIC_CODE_NAMESPACE_ONLY','spec':pins[0],'sources':m.sources(),
              'issued_epoch':1,'expires_epoch':10000,'memory_MiB':8192,'max_calls':1}
        review={'status':'PASS_REVIEWED_SCIENTIFIC_CODE_INSTALL_SOURCE_AND_SPEC','spec':pins[0],'authority':pins[1],'sources':m.sources()}
        return pins,[spec,auth,review]

    def run_validate(self,rows):
        pins,_=self.fixture()
        with patch.object(a,'read',side_effect=rows):
            return m.validate(*pins,now=100,environment={'SLURM_JOB_ID':'999','SLURMD_NODENAME':'node-13','SLURM_CPUS_PER_TASK':'1'},affinity={0},node='node-13')

    def test_distinct_compute_role_and_exact_review_required(self):
        pins,rows=self.fixture();self.assertEqual(self.run_validate(rows),rows[0])
        rows[2]['authority']={'path':'/other','sha256':'a'*64}
        with self.assertRaises(ValueError):self.run_validate(rows)

    def test_no_old_role_numeric_permission_or_envelope_waiver(self):
        for key,value in [('purpose','R_STARTUP_METADATA_ONLY'),('R_executions',1),('scientific_target_data',True),
                          ('bounds',{'files':99999,'bytes':99999,'one_file_bytes':99999})]:
            pins,rows=self.fixture();rows[0][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):self.run_validate(rows)

    def test_expired_or_wrong_job_cannot_install(self):
        pins,rows=self.fixture();rows[1]['expires_epoch']=600
        with self.assertRaises(ValueError):self.run_validate(rows)
        pins,rows=self.fixture();rows[0]['job_id']='other'
        with self.assertRaises(ValueError):self.run_validate(rows)

    def test_regular_code_extract_is_create_only(self):
        with tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
            root=Path(tmp);source=root/'source';source.write_bytes(b'opaque runtime code')
            row=dict(a.binding(source),relative='R_HOME/library/pkg/R/pkg.rdb',sha256=a.digest(source))
            a.stream_archive(root/'carrier',[row],'REAL_R46_STARTUP_ARCHIVE',{'test':True},root)
            manifest=a.read_json(root/'carrier/CARRIER_MANIFEST.json');archive_pin=a.pin(root/'carrier/runtime_carrier.tar.gz')
            out=root/'new';out.mkdir();seen=set()
            m.install_one(archive_pin,manifest,out,seen)
            self.assertEqual((out/row['relative']).read_bytes(),b'opaque runtime code')
            with self.assertRaises(ValueError):m.install_one(archive_pin,manifest,out,seen)
            self.assertEqual((out/row['relative']).read_bytes(),b'opaque runtime code')


if __name__=='__main__':unittest.main()
