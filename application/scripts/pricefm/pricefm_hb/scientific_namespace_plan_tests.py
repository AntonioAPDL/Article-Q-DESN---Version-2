import unittest
from . import scientific_namespace_plan as m


def base():
    rows=[{'relative':'R_HOME/f%d'%i,'bytes':1,'mode':0o644,'sha256':'a'*64} for i in range(680)]
    rows[0]['bytes']=rows[1]['bytes']=55941589
    return {'schema':'pricefm_streaming_runtime_archive_v1','file_count':680,'total_bytes':111883856,'files':rows}

def addon():
    return {'schema':'r179_scientific_code_closure_v1','status':'COMPLETE_ADDITIVE_CODE_CARRIERS_NOT_RUNTIME_OR_NUMERICAL_PROOF',
            'R_executions':0,'scientific_data_access':False,'namespace_startup_proved':False,'base_members_overwritten':[],
            'file_count':1599,'code_bytes':163614891,'parts':[{'runtime_file_count':1311,'runtime_total_bytes':106506843},{'runtime_file_count':288,'runtime_total_bytes':57108048}]}


class NamespaceEnvelopeTests(unittest.TestCase):
    def test_new_purpose_and_envelope_do_not_waive_old_gate(self):
        r=m.validate_closure(base(),addon())
        self.assertEqual(r['assembled_files'],2279)
        self.assertEqual(r['assembled_bytes'],275498747)
        self.assertTrue(r['old_startup2048_gate_unchanged'])
        self.assertFalse(r['numerical_admission'])

    def test_claimed_startup_or_old_gate_part_overrun_fails(self):
        a=addon();a['namespace_startup_proved']=True
        with self.assertRaises(ValueError):m.validate_closure(base(),a)
        a=addon();a['parts'][0]['runtime_file_count']=2049
        with self.assertRaises(ValueError):m.validate_closure(base(),a)

    def test_joint_limits_are_not_unbounded(self):
        a=addon();a['code_bytes']=m.MAX_BYTES
        with self.assertRaises(ValueError):m.validate_closure(base(),a)
        a=addon();a['file_count']=m.MAX_FILES
        with self.assertRaises(ValueError):m.validate_closure(base(),a)

    def test_overwrite_dataset_and_path_escape_fail(self):
        b=base();row={'relative':'R_HOME/library/pkg/R/pkg.rdb','bytes':1,'mode':0o644,'sha256':'b'*64}
        m.validate_part_members(b,[{'files':[row]}])
        for name in ['R_HOME/f0','R_HOME/library/pkg/data/target.rda','../target','R_HOME/a/../b']:
            with self.subTest(name=name),self.assertRaises(ValueError):m.validate_part_members(b,[{'files':[dict(row,relative=name)]}])


if __name__=='__main__':unittest.main()
