"""Private JSON-only closure proof, without any campaign/model calls."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
HERE=Path(__file__).resolve().parents[1]/'scripts/pricefm'
sys.path.insert(0,str(HERE));sys.dont_write_bytecode=True
import pricefm_r155_final_contract as c


class TestFinalClosure(unittest.TestCase):
    def fixture(self,root,change=None):
        def save(path,value):
            path=Path(path);path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value));return c.pin(path)
        source={'branch':'work/pricefm-r155-ee-final-component-private','head':'a'*40}
        source_root=root/'source';entry=source_root/'application/scripts/pricefm/528_run_pricefm_stage_r155_final_component.py'
        entry.parent.mkdir(parents=True);entry.write_text('pass\n')
        scopes=[]
        for i,charge in enumerate((10961.212634375985,2692.2750262410004)):
            scopes.append(dict(exit=save(root/f'old_exit{i}.json',{'status':'INCOMPLETE'}),
                supervisor_exit=save(root/f'old_super{i}.json',{'all_inclusive_charged_CPU_seconds':charge}),conservative_CPU_charge=charge))
        paid={'schema':'r155_paid_scope_chain_v1','scopes':scopes}
        prep={'source':source,'execution_source_sha256':{str(entry):c.digest(entry)},'previous_paid_scope':paid,
            'remaining_component_names':['B3'],'composite_inventory':save(root/'inventory.json',{})}
        pp=save(root/'preparation.json',prep);out=root/'science';locks=root/'locks';locks.mkdir();lock=locks/'permit.lock';lock.touch();st=lock.stat()
        glob=save(root/'global.json',{'lock_dir':str(locks)})
        a={'schema':'r155_final_authority_v1','status':'ADMITTED','max_new_tasks':1,'source':source,
            'preparation':pp,'previous_paid_scope':paid,'output_dir':str(out),'scope_id':'final','permit_id':'permit',
            'global_contract':glob,'original_global_lock_identity':{'device':st.st_dev,'inode':st.st_ino},'unit':'final.service'}
        authority=save(root/'authority.json',a);save(out/'authority.json',a)
        dead={'pid':987654,'start_ticks':1,'boot_id':'fixture'}
        save(out/'claim.json',dict(authority=authority,scope_id='final',permit_id='permit',study='EE',output_dir=str(out),process=dead))
        execution=dict(source=source,scope_id='final',authority=c.pin(out/'authority.json'))
        assessment=dict(status='COMPLETE_INITIAL_PREFIX_NO_S0_QUALIFIER',full_D_components=78,full_S0_components=9,
            new_D=0,new_S0=1,new_component_names=['B3'],carried_partial_chunks=15,new_chunks=73,
            total_public_chunk_calls=74,extra_seed_admitted=False,new_fits=0,official_origins=0,
            promotion_authorized=False,execution=execution,previous_paid_scope=paid)
        if change:assessment.update(change)
        ap=save(out/'assessment.json',assessment);asp=save(out/'assessment_seal.json',dict(assessment=ap,execution=execution))
        xp=save(out/'exit_receipt.json',{'status':'COMPLETE_INITIAL_PREFIX'})
        sp=save(out/'supervisor_exit_receipt.json',dict(child_exit_code=0,parent=dead,payload=dead))
        save(out/'guardian.json',dict(process=dead,payload=dead));save(out/'payload_identity.json',dict(process=dead,parent=dead))
        launch=root/'launch.json';closing=root/'closing.json'
        manifest=dict(schema='r155_root_final_EE_execution_v1',status='ROOT_ADMITTED_ONCE',authority=authority,
            preparation=pp,source_root=str(source_root),source=source,required_RemainAfterExit=True,
            entry=c.pin(entry),prior_scopes_retained=paid,root_closing_proof_path=str(closing),
            root_launch_receipt_path=str(launch),direct_unit='final.service')
        mp=save(root/'manifest.json',manifest)
        unit=dict(Id='final.service',LoadState='loaded',ActiveState='active',SubState='exited',MainPID='0',
            Result='success',ExecMainStatus='0',RemainAfterExit='yes',InvocationID='invocation')
        lp=save(launch,dict(execution_manifest=mp,authority=authority,source=source,
            unit_show=dict(unit,MainPID=str(dead['pid']),ExecMainPID=str(dead['pid']))))
        save(closing,dict(schema='r155_root_final_EE_closeout_v1',status='PASS',execution_manifest=mp,launch_receipt=lp,
            authority=authority,source=source,prior_scopes_retained=paid,assessment=ap,assessment_seal=asp,
            science_exit=xp,supervisor_exit=sp,final_unit_show=unit,exact_lifetimes_gone=True,same_global_flock_free=True))
        return source,mp,unit

    def test_complete_new_scope_accepts_incomplete_paid_predecessors_and_rejects_partial(self):
        for change in (None,{'full_S0_components':8},{'new_S0':2},{'status':'INCOMPLETE'},{'extra_seed_admitted':True}):
            with self.subTest(change=change),tempfile.TemporaryDirectory() as d:
                source,manifest,unit=self.fixture(Path(d),change)
                with (patch.object(c,'source_identity',return_value=source),patch.object(c,'process_identity',return_value=None),
                      patch.object(c.subprocess,'check_output',return_value='\n'.join(k+'='+v for k,v in unit.items()))):
                    if change:
                        with self.assertRaises(RuntimeError):c.verify_final_initial_closure(manifest)
                    else:
                        result=c.verify_final_initial_closure(manifest)
                        self.assertEqual(result['status'],'PASS_COMPLETE_INITIAL_METADATA_CLOSURE')
                        self.assertEqual(len(result['paid_scope_chain']['scopes']),2)
                        self.assertTrue(result['physical_drain']['same_global_flock_free'])

    def test_claim_guardian_and_launched_pid_must_be_the_same_actual_lifetime(self):
        for filename,field in (('claim.json','process'),('guardian.json','process'),('payload_identity.json','parent')):
            with self.subTest(file=filename),tempfile.TemporaryDirectory() as d:
                root=Path(d);source,manifest,unit=self.fixture(root)
                path=root/'science'/filename;record=c.read(path);record[field]=dict(record[field],start_ticks=2);path.write_text(json.dumps(record))
                with (patch.object(c,'source_identity',return_value=source),patch.object(c,'process_identity',return_value=None),
                      patch.object(c.subprocess,'check_output',return_value='\n'.join(k+'='+v for k,v in unit.items()))):
                    with self.assertRaises(RuntimeError):c.verify_final_initial_closure(manifest)


if __name__=='__main__':unittest.main()
