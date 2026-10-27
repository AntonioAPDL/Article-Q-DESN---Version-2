"""Metadata-only cold-floor regression checks; no models or forecasts."""
import ast
import copy
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
SCRIPTS=Path(__file__).resolve().parents[1]/'scripts/pricefm'
sys.dont_write_bytecode=True
sys.path.insert(0,str(SCRIPTS))
spec=importlib.util.spec_from_file_location('qualified_cold_floor_preparer',SCRIPTS/'528_prepare_pricefm_stage_r155_qualified_seeds.py')
p=importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


class TestKnownColdFloor(unittest.TestCase):
    def evidence(self):
        return dict(status='PASS_EXACT_FINAL_SOURCE_ACTUAL_HOST_ADAPTER',
            source=dict(branch='work/pricefm-r155-ee-final-component-20261027',head='e35584833719bb35969cfbd5ea5047aeca8f8838'),
            helper={'sha256':'65049f0003c1ccd0c95468fd6d84a96b11037eec4da98b43e9cb84048be0246a'},
            CPU_affinity=[31],numpy_imported=False,claims_created=0,global_permits_claimed=0,
            rows=[{'CPU_seconds':.418455},{'CPU_seconds':.376812},{'CPU_seconds':.363579}])

    def run_profile(self,cold=None,fresh=(.10,.20,.15)):
        cold=self.evidence() if cold is None else cold
        ticks=[0.,fresh[0],1.,1.+fresh[1],2.,2.+fresh[2]]
        with (patch.object(p.c,'cpu_seconds',side_effect=ticks),
              patch.object(p.c,'all_processes',return_value=[{'threads':[]} for _ in range(101)]),
              patch.object(p.c,'reviewed_peer_conflicts',return_value=([],[])),
              patch.object(p.c,'read',return_value={'three_scan_max_CPU_seconds':.321704}),
              patch.object(p.c,'verify_pin',return_value=cold),
              patch.object(p.c,'digest',return_value='65049f0003c1ccd0c95468fd6d84a96b11037eec4da98b43e9cb84048be0246a'),
              patch.object(p.c,'pin',side_effect=lambda path:dict(path=str(path),sha256='1'*64)),
              patch.object(p.os,'readlink',return_value='pid:[4026531836]')):
            return p.profile({}, {}, {})

    def test_warm_scans_never_replace_known_actual_cold_floor(self):
        value=self.run_profile()
        self.assertAlmostEqual(value['upper_scan_CPU'],.6276825)
        self.assertEqual(value['known_cold_scan_CPU_floor'],.418455)
        self.assertEqual(value['historical_LV_scan_CPU_floor'],.321704)
        self.assertEqual(value['floor_evidence']['sha256'],'d634761d7c0031805f04ba309f80ba031bbc1ae645d0977c6827ab7a14dba9a3')

    def test_new_slower_scan_raises_ceiling(self):
        self.assertAlmostEqual(self.run_profile(fresh=(.10,.50,.15))['upper_scan_CPU'],.75)

    def test_mixed_source_helper_or_scientific_evidence_rejected(self):
        for mutation in ('source','helper','affinity','numpy','claim','lowfloor'):
            with self.subTest(mutation=mutation):
                cold=self.evidence()
                if mutation=='source':cold['source']['head']='0'*40
                elif mutation=='helper':cold['helper']['sha256']='0'*64
                elif mutation=='affinity':cold['CPU_affinity']=[30]
                elif mutation=='numpy':cold['numpy_imported']=True
                elif mutation=='claim':cold['claims_created']=1
                else:cold['rows']=[{'CPU_seconds':.30}]
                with self.assertRaises(RuntimeError):self.run_profile(cold)

    def test_only_profile_changes_and_runtime_science_bytes_are_unchanged(self):
        old=SCRIPTS.parents[3]/'pricefm_r155_qualified_seeds_20261027/application/scripts/pricefm'
        def functions(path):
            return {n.name:ast.dump(n,include_attributes=False) for n in ast.parse(path.read_text()).body if isinstance(n,ast.FunctionDef)}
        name='528_prepare_pricefm_stage_r155_qualified_seeds.py'
        before=functions(old/name)
        after=functions(SCRIPTS/name)
        self.assertEqual([n for n in before if before[n]!=after[n]],['profile'])
        for name in ('529_run_pricefm_stage_r155_qualified_seeds.py','pricefm_r155_seed_contract.py',
                     'pricefm_r155_completion_contract.py','pricefm_r155_completion_inventory.py','pricefm_r155_metadata_waiter.py'):
            self.assertEqual((old/name).read_bytes(),(SCRIPTS/name).read_bytes(),name)


if __name__=='__main__':unittest.main()
