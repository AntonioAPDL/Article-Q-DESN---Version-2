"""Fresh metadata producer -> independent numeric prerequisite consumer.

All2279 runtime rows and prior native facts are synthetic NONCANDIDATE metadata;
no runtime bytes, target arrays, R, jobs or network are accessed.
"""
import copy,json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
from . import startup_helper as h,numerical_stage_prepare as producer,numerical_stage_owner as owner
from . import numerical_stage_contract as contract,numerical_independent_peer as peer,scientific_batch


def put(path,value):
    path.write_text(json.dumps(value,sort_keys=True,indent=2)+'\n');return h.pin(path)


class PrerequisiteOriginTests(unittest.TestCase):
    def fixture(self,folder):
        remote='/UNIT_NONCANDIDATE/result';returned=folder/'returned';(returned/'owner').mkdir(parents=True)
        route='a'*32;node='node-15';role='SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER'
        native=dict(schema='r157_traced_bootstrap_guard_receipt_v1',status='EXITED',returncode=0,reaped=True,drained=True,
            CPU_accounting_complete=True,all_newborns_kernel_traced_before_execution=True,tracer_death_kernel_EXITKILL_enabled=True,
            postbootstrap_TSYNC_scientific_fork_denial=True,scientific_target_access_handshake=True,remaining_owned_lifetimes=[],
            unexpected_untraced_child_waits=[],scientific_filter_kernel_attestation=dict(operation='SECCOMP_SET_MODE_FILTER',flags='TSYNC',kernel_return=0))
        np=put(returned/'owner/owned_guard.json',native)
        outcome=dict(status='PASS_HB_NATIVE_SCIENTIFIC_BOUNDARY_NO_TARGET_NO_OPTIMIZER',original_guard_source_preserved=True,
            owned_guard=dict(path=remote+'/owner/owned_guard.json',sha256=np['sha256']))
        put(returned/'owner/RESULT.json',outcome)
        put(returned/'INVENTORY.json',dict(job_id='221',node=node,qualification_route_id=route))
        installation=dict(status='INSTALLED_CODE_BYTES_ONLY_NOT_NAMESPACE_OR_SCIENTIFIC_PROOF',files=2279,bytes=275498747,job_id='221',R_HOME='/UNIT_NONCANDIDATE/code/R_HOME')
        source=Path(producer.__file__).parent;hashes={name:h.pin(source/name)['sha256'] for name in scientific_batch.NAMES}
        sources={name:dict(path='/UNIT_NONCANDIDATE/source/'+name,sha256=sha) for name,sha in hashes.items()}
        rp=put(returned/'RESULT.json',dict(status='PASS_COMPLETE_SCIENTIFIC_METADATA_WORKER',job_id='221',node=node,qualification_route_id=route,
            role=role,sources=sources,outcome=outcome,installation=installation))
        (returned/'owner/child.stdout').write_bytes(b'');(returned/'owner/child.stderr').write_bytes(b'')
        rows=[dict(relative=str(p.relative_to(returned)),bytes=p.stat().st_size,sha256=h.pin(p)['sha256']) for p in sorted(returned.rglob('*')) if p.is_file()]
        mp=put(returned/'RETURN_MANIFEST.json',dict(job_id='221',scope_id='UNIT_NONCANDIDATE',files=rows))
        ap=put(folder/'account.json',dict(terminal=True,complete=True,job_id='221',primary_charge_counted_once=True,canonical_primary_CPU_seconds=1.23))
        pp=put(folder/'peer.json',dict(status='PASS_REVIEWED_COMPLETE_SCIENTIFIC_METADATA_ROLE',job_id='221',role=role,result=rp,accounting=ap,return_manifest=mp))
        candidate=dict(status='ACCEPTANCE_PENDING_ACTUAL_OUTER_GUARD',role=role,job_id='221',scope_id='UNIT_NONCANDIDATE',qualification_route_id=route,
            namespace_proved=True,scientific_boundary_proved=True,result=rp,full_return_manifest=mp,accounting=ap,independent_review=pp,canonical_primary_CPU_seconds=1.23)
        guard=dict(returncode=0,command_returncode=0,cap_reason=None,CPU_limit=5,aggregate_CPU_seconds=.25,complete_lifecycle_wall_seconds=1,
            guardian_forced_monitor_stop=False,stdout=json.dumps(candidate),**{k:True for k in ['all_owned_descendants_reaped','independent_guardian',
            'kernel_escape_filter','orphan_subreaper','guardian_included_in_CPU','inherited_waited_history_included_once']})
        gp=put(folder/'accept.guard.json',guard);accepted=put(folder/'ACCEPTED.json',dict(candidate,status='ACCEPTED_COMPLETE_SCIENTIFIC_METADATA_ROLE',actual_accept_action_guard=gp))
        code=[dict(relative='R_HOME/bin/exec/R',sha256=contract.NATIVE_SHA,bytes=100000),dict(relative='R_HOME/bin/Rscript',sha256='b'*64,bytes=100000)]
        code += [dict(relative='R_HOME/library/UNIT/code_%04d'%i,sha256='a'*64,bytes=100000) for i in range(2277)]
        code[-1]['bytes']+=275498747-sum(row['bytes'] for row in code)
        manifests={name:put(folder/name,dict(files=part)) for name,part in zip(['base_manifest.json','addon01_manifest.json','addon02_manifest.json'],[code[:680],code[680:1480],code[1480:]])}
        scope=put(folder/'SCOPE.json',dict(execution_node=node,qualification_node=node,qualification_route_id=route,cached_artifact_origin_node='node-13'))
        publication=put(folder/'UNIT_PUBLICATION.json',dict(status='UNIT_NONCANDIDATE_SYNTHETIC_SOURCE',core_source_maps=dict(source_family_files=dict(scientific=hashes))))
        return accepted,manifests,dict(node=node,scope=scope,publication=publication)
    def test_actual_helper_then_independent_consumer_and_origin_refusal(self):
        with tempfile.TemporaryDirectory(prefix='UNIT_PREREQUISITE_ORIGIN_') as name:
            folder=Path(name);accepted,manifests,config=self.fixture(folder);hashes={name:pin['sha256'] for name,pin in manifests.items()}
            with patch.dict(owner.namespace_contract.INPUT_HASHES,hashes),patch.dict(peer.MANIFESTS,hashes,clear=True):
                receipt=producer.prerequisite_inputs(accepted,manifests,folder/'prepared',expected_node='node-15',expected_route_id='a'*32)
                config.update(prerequisite_bundle=receipt['bundle'],runtime_reuse=receipt['runtime_reuse'])
                bundle,reuse=peer.prerequisites(config)
                self.assertEqual(reuse['cached_artifact_origin_node'],'node-13');self.assertEqual(reuse['qualification_node'],'node-15')
                self.assertEqual(len(reuse['runtime_files']),2279);self.assertFalse(receipt['target_arrays_opened'])
                for key,value in [('cached_artifact_origin_node',None),('cached_artifact_origin_node','node-15'),('qualification_node','node-13'),('qualification_route_id','b'*32)]:
                    bad=copy.deepcopy(reuse)
                    if value is None:bad.pop(key)
                    else:bad[key]=value
                    fork=folder/('UNIT_BAD_'+key+('_missing' if value is None else '_'+str(value))+'.json')
                    badconfig=dict(config,runtime_reuse=put(fork,bad))
                    with self.subTest(key=key,value=value),self.assertRaises(ValueError):peer.prerequisites(badconfig)


if __name__=='__main__':unittest.main()
