"""Pure host-bound metadata tests, without SSH, R or process observations."""
import unittest
import ast
from . import jerez_readiness as m
from .local_readiness import ReadinessError


def fixture():
    return {'schema':'r178_jerez_metadata_observation_v1','host':'jerez.be.ucsc.edu','observed_epoch':1000,
            'affinity':[31],'R_started':False,'numerical_admission':False,'signals':0,'source_or_runtime_changes':0,
            'new_peer_allowances':[],'all_process_arguments_redacted':True,'runtime_errors':[],
            'runtime_files':[{'matches':True}],'same_UID_numerical_intersections_pair30_62':[],
            'process_observation_errors':[],'disk_free_bytes':66*1024**3,'memory':{'MemAvailable':300*1024**3},
            'topology':{'30':'30,62','62':'30,62','31':'31,63','63':'31,63'}}


class HostReadinessTests(unittest.TestCase):
    def test_remote_metadata_program_is_parseable_without_execution(self):
        runtime={'package_path':'/runtime/pkg','actual_executable':'/runtime/R','actual_executable_sha256':'a'*64,
                 'Rscript':'/runtime/Rscript','Rscript_sha256':'b'*64,'loaded_shared_object_sha256':{},'package_files_sha256':{}}
        text=m.remote_program(runtime)
        tree=ast.parse(text)
        self.assertFalse(any(isinstance(n,(ast.Import,ast.ImportFrom)) and any(a.name in {'numpy','scipy','subprocess'} for a in n.names) for n in ast.walk(tree)))
        self.assertIn('RLIMIT_CPU,(8,8)',text)
        self.assertIn('signal.alarm(60)',text)
        argv=m.ssh_argv(runtime)
        self.assertEqual(argv[0],'/usr/bin/ssh')
        self.assertEqual(argv[-2],'jerez')

    def test_matching_runtime_is_not_numerical_admission(self):
        r=m.summarize(fixture())
        self.assertIs(r['runtime_bytes_match_Muscat_binding'],True)
        self.assertIs(r['numerical_admission'],False)
        self.assertIn('EXISTING_R164_NUMERICAL_LAUNCHER_IS_MUSCAT_ONLY',r['blockers'])

    def test_jerez50_does_not_weaken_original_muscat80(self):
        r=m.summarize(fixture())
        self.assertTrue(r['disk_floor50_GiB_preserved'])
        self.assertIn('UNCHANGED_MUSCAT_GUARD_DISK80_FLOOR_WOULD_FAIL_ON_JEREZ',r['blockers'])

    def test_other_host_science_or_peer_waivers_fail(self):
        for key,value in [('host','muscat'),('R_started',True),('numerical_admission',True),
                          ('new_peer_allowances',[1]),('signals',1),('all_process_arguments_redacted',False)]:
            x=fixture();x[key]=value
            with self.subTest(key=key),self.assertRaises(ReadinessError):m.summarize(x)

    def test_mismatched_runtime_and_unreviewed_peers_remain_blockers(self):
        x=fixture();x['runtime_files']=[{'matches':False}];x['same_UID_numerical_intersections_pair30_62']=[{'pid':1}]
        r=m.summarize(x)
        self.assertIn('PINNED_REQUIRED_RUNTIME_BYTES_MISSING_OR_DIFFERENT',r['blockers'])
        self.assertIn('UNREVIEWED_PHYSICAL_PAIR_PROCESS_IDENTITIES',r['blockers'])


if __name__=='__main__':unittest.main()
