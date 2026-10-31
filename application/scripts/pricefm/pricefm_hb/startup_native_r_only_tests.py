"""Metadata/failure-injection doubles only: no SSH, Slurm, child or R runs."""
import copy
import hashlib
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

from . import startup_native_r_only as n
from . import startup_helper as h
from .startup_helper_kernel_tests import CASE_ROWS


class NativeTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="r180_unit_metadata_")
        self.addCleanup(self.temp.cleanup);self.path=Path(self.temp.name)
        self.registry=self.path/"registry";self.registry.mkdir()
        self.root=self.registry/n.ROLE;self.root.mkdir()
        self.source=Path(n.__file__).absolute().parent
        self.hashes={name:n.digest(self.source/name) for name in n.NAMES}
        self.config=dict(frontend_source=h.pin(n.__file__),source_dir=str(self.source),
            publication=self.save("publication.json",{"status":"UNIT_DOUBLE_NOT_PUBLICATION"}),
            source_review=self.save("source_review.json",{"status":"UNIT_DOUBLE_NOT_REVIEW"}),
            node="node-13",remote_namespace="/mnt/beegfs/home/jaguir26/pricefm_r180_UNIT")
        self.config["registry"]=str(self.registry)
        self.site=dict(account="128x24",partition="128x24",qos="normal",user="jaguir26")
        self.packet=dict(role=n.ROLE,scope_id="r180-R46-unit",remote_root=self.config["remote_namespace"]+"/r180-R46-unit")
        pp=self.save("registry/"+n.ROLE+"/PACKET.json",self.packet)
        n.append(self.root,"PREPARED",packet=pp);n.append(self.root,"STAGED")

    def save(self,name,value):
        path=self.path/name;path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(json.dumps(value,sort_keys=True));return h.pin(path)

    def start_submit(self):
        self.started=n.started_action(self.registry,n.ROLE,"submit",self.config,self.hashes)
        self.start=h.read(h.pin(self.started))

    def known_submit(self,*,interrupted=False):
        self.start_submit()
        reply=dict(returncode=0,stdout="887286\n",stderr="",argv=n.submission_argv(self.config,self.site,self.packet))
        native=[dict(returncode=0,stdout="",stderr=""),reply]
        original=n._base.append
        def append(root,state,**fields):
            if interrupted and state=="SUBMITTED":raise OSError("unit interrupt after complete JOB before final journal")
            return original(root,state,**fields)
        with patch.object(n._base,"run_native",side_effect=native),patch.object(n._base,"append",side_effect=append):
            if interrupted:
                with self.assertRaisesRegex(OSError,"after complete JOB"):
                    n._base.submit(self.config,{"expires_epoch":time.time()+3600},self.site,self.root)
            else:
                n._base.submit(self.config,{"expires_epoch":time.time()+3600},self.site,self.root)
        self.guard=dict(returncode=125,independent_guardian=True,all_owned_descendants_reaped=True,
            aggregate_CPU_seconds=2.094932,owned_stop_witness=dict(session_id=self.start["command_pid"],
                leader_start_ticks=self.start["command_birth_ticks"],failure="STOP_WAIT_CPU_UPPER_BOUNDARY",
                permitted_stopped_states=["T","t","Z"],states_are_not_accepted_for_accounting=True,
                exact_proved_owned_items=[dict(state="D")]))
        self.gp=self.save("failed_guard.json",self.guard)

    def acknowledge(self):
        return n.acknowledge_failed_previous(self.registry,n.ROLE,self.gp["path"],config=self.config,site=self.site)

    def rewrite_job(self,change):
        p=self.root/"JOB.json";value=h.read(h.pin(p));change(value);p.write_text(json.dumps(value))

    def test_interrupted_submit_acknowledges_known_job_only(self):
        self.known_submit(interrupted=True)
        self.assertEqual(n.records(self.root)[-1]["state"],"SUBMISSION_INTENT")
        value=self.acknowledge()
        self.assertEqual(value["job_binding"]["kind"],"INTERRUPTED_SUBMIT_OBSERVED_COMPLETE_JOB_NOT_SUBMIT_SUCCESS")
        self.assertTrue(value["no_successor_compute_authority"] and value["no_job_submission_success_claim"])
        self.assertTrue((self.root/"ROLE_FAILED_SPENT.json").is_file())
        self.assertFalse((self.root/"ACCEPTED.json").exists())
        self.assertIsNone(n.finish_previous(self.registry,None))

    def test_completed_submitted_journal_still_supported(self):
        self.known_submit()
        self.assertEqual(self.acknowledge()["job_binding"]["kind"],"COMPLETED_SUBMITTED_JOURNAL")

    def test_interrupted_ack_then_exact_cancel_tail_has_no_SUBMITTED_dependency(self):
        self.known_submit(interrupted=True);self.acknowledge()
        with patch.object(n._base,"run_native",return_value=dict(returncode=0,stdout="",stderr="")) as native:
            value=n.cancel(self.site,self.root)
        self.assertEqual(value["status"],"CANCEL_REQUESTED_NOT_TERMINAL_PROOF")
        self.assertEqual(native.call_args.args[1],["scancel","--user","jaguir26","--name",self.packet["scope_id"],"887286"])
        self.assertTrue((self.root/"ROLE_FAILED_SPENT.json").exists())

    def test_failed_JOB_directory_sync_after_complete_bytes_is_recoverable(self):
        self.start_submit();original=h.write_new
        def write(path,value):
            original(path,value)
            if Path(path).name=="JOB.json":raise OSError("unit directory fsync interruption")
        reply=dict(returncode=0,stdout="887286\n",stderr="",argv=n.submission_argv(self.config,self.site,self.packet))
        with patch.object(n._base,"run_native",side_effect=[dict(returncode=0,stdout="",stderr=""),reply]),patch.object(h,"write_new",side_effect=write):
            with self.assertRaisesRegex(OSError,"fsync"):
                n._base.submit(self.config,{"expires_epoch":time.time()+3600},self.site,self.root)
        self.guard=dict(returncode=125,independent_guardian=True,all_owned_descendants_reaped=True,
                        session_id=self.start["command_pid"],leader_start_ticks=self.start["command_birth_ticks"])
        self.gp=self.save("failed_guard.json",self.guard)
        self.assertTrue(self.acknowledge()["no_job_submission_success_claim"])

    def test_ambiguous_reply_without_JOB_stays_spent_unrecoverable(self):
        self.start_submit()
        with patch.object(n._base,"run_native",side_effect=[dict(returncode=0,stdout="",stderr=""),TimeoutError("lost reply")]):
            with self.assertRaises(TimeoutError):
                n._base.submit(self.config,{"expires_epoch":time.time()+3600},self.site,self.root)
        self.gp=self.save("failed_guard.json",{"returncode":125})
        with self.assertRaises(FileNotFoundError):self.acknowledge()
        self.assertEqual(n.records(self.root)[-1]["state"],"AMBIGUOUS_SPENT")

    def test_real_main_submit_exception_tail_can_acknowledge_complete_JOB(self):
        original=n._base.append
        def append(root,state,**fields):
            if state=="SUBMITTED":raise OSError("unit actual CLI journal interruption")
            return original(root,state,**fields)
        reply=dict(returncode=0,stdout="887286\n",stderr="",argv=n.submission_argv(self.config,self.site,self.packet))
        scope=dict(issued_epoch=time.time()-10,fixed_latest_submit_epoch=time.time()+100,
                   expires_epoch=time.time()+3600)
        with patch.object(n,"load_config",return_value=(self.config,scope,self.site,self.hashes)), \
             patch.object(n._base,"require_outer_context"),patch.object(n.resource,"getrlimit",return_value=(4,4)), \
             patch.object(n.sys,"argv",["unit_frontend","submit","--config","UNIT_NOT_AUTHORITY","--role",n.ROLE]), \
             patch.object(n._base,"run_native",side_effect=[dict(returncode=0,stdout="",stderr=""),reply]), \
             patch.object(n._base,"append",side_effect=append):
            with self.assertRaisesRegex(OSError,"actual CLI"):
                n.main()
        self.started=next(self.registry.glob("control_*.started.json"));self.start=h.read(h.pin(self.started))
        self.guard=dict(returncode=125,independent_guardian=True,all_owned_descendants_reaped=True,
            session_id=self.start["command_pid"],leader_start_ticks=self.start["command_birth_ticks"])
        self.gp=self.save("failed_guard.json",self.guard)
        self.assertEqual([x["state"] for x in n.records(self.root)][-2:],["SUBMISSION_INTENT","ACTION_FAILED_RETAINED"])
        value=self.acknowledge()
        self.assertEqual(value["job_binding"]["retained_submit_exception_tail"]["action"],"submit")
        self.assertTrue(value["no_successor_compute_authority"])

    def test_missing_submit_intent_fails_closed(self):
        self.known_submit(interrupted=True);(self.root/"submit.intent.json").unlink()
        with self.assertRaises(FileNotFoundError):self.acknowledge()

    def test_partial_JOB_fails_closed_without_quarantine_or_cancel(self):
        self.known_submit(interrupted=True);(self.root/"JOB.json").write_text('{"job_id":')
        with self.assertRaises(ValueError):self.acknowledge()
        self.assertFalse((self.root/"ROLE_FAILED_SPENT.json").exists())

    def test_reply_job_or_scope_or_argv_mismatch_rejected(self):
        self.known_submit(interrupted=True);original=(self.root/"JOB.json").read_bytes()
        changes=[lambda x:x.update(job_id="999"),lambda x:x.update(scope_id="foreign"),
                 lambda x:x["submission"]["argv"].append("unreviewed"),
                 lambda x:x["submission"].update(stdout="warning\n887286\n")]
        for change in changes:
            (self.root/"JOB.json").write_bytes(original);self.rewrite_job(change)
            with self.assertRaises(ValueError):self.acknowledge()

    def test_wrong_guard_PID_birth_or_drain_rejected(self):
        self.known_submit(interrupted=True)
        for key,value in (("all_owned_descendants_reaped",False),("independent_guardian",False),("returncode",0)):
            guard=copy.deepcopy(self.guard);guard[key]=value;self.gp=self.save("failed_guard.json",guard)
            with self.assertRaises(ValueError):self.acknowledge()
        guard=copy.deepcopy(self.guard);guard["owned_stop_witness"]["leader_start_ticks"]+=1
        self.gp=self.save("failed_guard.json",guard)
        with self.assertRaises(ValueError):self.acknowledge()

    def test_changed_start_source_or_compute_closure_rejected(self):
        self.known_submit(interrupted=True)
        for field in ("source_sha256","compute_source_files","frontend_source"):
            value=copy.deepcopy(self.start);value[field]={} if field!="source_sha256" else "0"*64
            self.started.write_text(json.dumps(value))
            with self.assertRaises(ValueError):self.acknowledge()

    def test_quarantine_precedes_ack_publication(self):
        self.known_submit(interrupted=True);original=h.write_new
        def writer(path,value):
            if str(path).endswith(".failed_ack.json"):raise OSError("unit ack interrupted")
            return original(path,value)
        with patch.object(h,"write_new",side_effect=writer):
            with self.assertRaisesRegex(OSError,"ack interrupted"):self.acknowledge()
        self.assertTrue((self.root/"ROLE_FAILED_SPENT.json").is_file())
        self.assertFalse(self.started.with_name(self.started.name.replace(".started.json",".failed_ack.json")).exists())

    def test_foreign_existing_quarantine_rejected(self):
        self.known_submit(interrupted=True)
        self.save("registry/"+n.ROLE+"/ROLE_FAILED_SPENT.json",{"foreign":True})
        with self.assertRaisesRegex(ValueError,"inconsistent"):self.acknowledge()

    def test_R_only_envelope_retains_original_action_caps(self):
        self.assertEqual(n.NATIVE_CONTROL_TOTAL,128)
        self.assertEqual(n.ROLES,("EXACT_R46_STARTUP_METADATA",))
        self.assertEqual(n.action_limits("submit"),dict(local_CPU=4,remote_unknown_fee=4,wall=45,maximum_calls=1))
        self.assertEqual(len(n.NAMES),14)
        self.assertNotIn("startup_native_r_only.py",n.NAMES)
        self.assertEqual(n._base.ROLES,("COMPUTE_RUNTIME_INVENTORY","EXACT_R46_STARTUP_METADATA"))

    def test_inherited_R_accept_and_finalize_do_not_take_inventory_branch(self):
        registry=self.path/"R_accept_registry";registry.mkdir();root=registry/n.ROLE;root.mkdir()
        relative=str(root.relative_to(self.path))
        packet=dict(role=n.ROLE,scope_id="r180-R46-accepted-unit",remote_root="/mnt/beegfs/home/jaguir26/pricefm_r180_UNIT/R",
                    spec_sha256="a"*64,sources={})
        pp=self.save(relative+"/PACKET.json",packet);n.append(root,"PREPARED",packet=pp)
        self.save(relative+"/JOB.json",dict(job_id="888",scope_id=packet["scope_id"]))
        rp=self.save(relative+"/returned/RESULT.json",dict(status="R46_STARTUP_METADATA_PASS_NOT_NUMERICAL_PARITY",
            job_id="888",role=n.ROLE,scope_id=packet["scope_id"],spec_sha256="a"*64,new_models=0,sources={},node="node-13",
            outcome=dict(status="PASS_R_METADATA_STARTUP_UNDER_OWNED_HELPER_GUARD",R_startup_proved=True,
                         production_ready=False,numerical_parity_proved=False)))
        mp=self.save(relative+"/returned/RETURN_MANIFEST.json",dict(schema="pricefm_startup_batch_return_manifest_v1",
            scope_id=packet["scope_id"],job_id="888",files=[dict(relative="RESULT.json",sha256=rp["sha256"],bytes=Path(rp["path"]).stat().st_size)]))
        ap=self.save("accepted_account.json",dict(complete=True,terminal=True,canonical_primary_CPU_seconds=2.))
        n.append(root,"OBSERVED",accounting=ap);n.append(root,"RETURNED",manifest=mp)
        peer=self.save("accepted_peer.json",dict(status="PASS_REVIEWED_STARTUP_BATCH_ROLE",job_id="888",role=n.ROLE,
            result=rp,return_manifest=mp,accounting=ap))
        started=n.started_action(registry,n.ROLE,"accept",self.config,self.hashes)
        with patch.object(n._base,"run_native",return_value=dict(returncode=0,stdout="",stderr="")):
            value=n.accept(self.config,self.site,root,peer["path"])
        self.assertFalse(value["kernel_matrix_pass"])
        n.pending_action(started,value);start=h.read(h.pin(started))
        guard=dict(returncode=0,command_returncode=0,cap_reason=None,CPU_limit=5,aggregate_CPU_seconds=.2,
            complete_lifecycle_wall_seconds=.3,guardian_forced_monitor_stop=False,session_id=start["command_pid"],
            leader_start_ticks=start["command_birth_ticks"],stdout=json.dumps(value))
        for field in ("all_owned_descendants_reaped","independent_guardian","kernel_escape_filter","orphan_subreaper","guardian_included_in_CPU","inherited_waited_history_included_once"):guard[field]=True
        gp=self.save("accepted_outer_guard.json",guard)
        n.finish_previous(registry,gp["path"])
        final=h.read(h.pin(root/"ACCEPTED.json"))
        self.assertEqual(final["role"],n.ROLE);self.assertFalse(final["kernel_matrix_pass"])
        self.assertFalse((registry/"COMPUTE_RUNTIME_INVENTORY").exists())

    def test_narrow_scope_rejects_second_role_old_mode_or_extra_budget(self):
        scope=dict(status="PROSPECTIVE_TWO_ROLE_HB_RUNTIME_QUALIFICATION_SCOPE",mode=n.MODE,roles=[n.ROLE],
            maximum_jobs=1,compute_CPU_reservation=600,max_concurrent_jobs=1,old_roles_reopened=False,
            automatic_retries=False,issued_epoch=100.,fixed_latest_submit_epoch=200.,expires_epoch=2000.)
        n.validate_scope(scope,now=150.)
        for field,value in (("mode","OLD"),("maximum_jobs",2),("roles",["COMPUTE_RUNTIME_INVENTORY",n.ROLE]),
                            ("compute_CPU_reservation",1200),("old_roles_reopened",True),("automatic_retries",True)):
            with self.assertRaises(ValueError):n.validate_scope(dict(scope,**{field:value}),now=150.)

    def test_canonical_identity_binds_carrier_frontend_and_reused_component(self):
        keys=("scope","site","native_control_budget","registry","remote_namespace","node","cached_python",
            "cached_python_sha256","source_dir","publication","source_review","frontend_source",
            "accepted_inventory","reuse_review","canonical_state_root","placement_proof","carrier","carrier_manifest")
        config={key:"UNIT_"+key for key in keys}
        identity=n.canonical_identity(config)
        self.assertEqual(identity,config)
        for field in ("carrier","frontend_source","reuse_review","accepted_inventory"):
            self.assertNotEqual(identity,n.canonical_identity(dict(config,**{field:"CHANGED"})))

    def test_fixed_submission_cutoff_precedes_native_call(self):
        with patch.object(n._base,"submit") as native:
            with self.assertRaisesRegex(ValueError,"cutoff"):
                n.submit({},dict(issued_epoch=1.,fixed_latest_submit_epoch=2.),{},self.root)
            native.assert_not_called()

    def test_probe_directory_or_tmp_cannot_be_canonical_registry(self):
        with self.assertRaisesRegex(ValueError,"persistent home"):
            n.validate_placement(dict(canonical_state_root="/tmp/r180_wrong"),{})

    def placement_fixture(self):
        root=self.path;device=root.stat().st_dev
        payload=dict(status="OBSERVED_OWNED_METADATA_FSYNC_READBACK_NOT_LATENCY_GUARANTEE",root=str(root),
                     device=device,rows=[{}]*8,new_jobs_or_scientific_calls=0)
        guard=dict(returncode=0,command_returncode=0,cap_reason=None,CPU_limit=4,aggregate_CPU_seconds=.2,
                   complete_lifecycle_wall_seconds=.3,guardian_forced_monitor_stop=False,stdout=json.dumps(payload))
        for field in ("all_owned_descendants_reaped","independent_guardian","kernel_escape_filter","orphan_subreaper","guardian_included_in_CPU","inherited_waited_history_included_once"):guard[field]=True
        gp=self.save("placement_guard.json",guard)
        proof=dict(same_original_H4_caps_and_stopped_rules=True,both_probe_fees_retained=True,
                   no_hard_latency_guarantee_or_job_admission=True,
                   rows=[dict(label="home",root=str(root),device=device,returncode=0,files=8,guard=gp)])
        pp=self.save("placement.json",proof)
        allowed=root/"R_only_UNIT";allowed.mkdir(mode=0o700)
        return dict(canonical_state_root=str(root),placement_proof=pp,registry=str(allowed/"registry")),dict(allowed_metadata_output_root=str(allowed)),guard,proof

    def test_new_private_home_child_can_be_prepared_without_admission(self):
        config,scope,guard,proof=self.placement_fixture()
        self.assertIsNone(n.validate_placement(config,scope))
        self.assertFalse(Path(config["registry"]).exists())

    def test_probe_root_itself_cannot_be_reused_as_canonical_child(self):
        config,scope,guard,proof=self.placement_fixture()
        with self.assertRaisesRegex(ValueError,"new private child"):
            n.validate_placement(config,dict(allowed_metadata_output_root=str(self.path)))

    def test_placement_requires_actual_guard_payload_root(self):
        config,scope,guard,proof=self.placement_fixture()
        payload=json.loads(guard["stdout"]);payload["root"]="/tmp/foreign";guard["stdout"]=json.dumps(payload)
        proof["rows"][0]["guard"]=self.save("placement_guard.json",guard)
        config["placement_proof"]=self.save("placement.json",proof)
        with self.assertRaisesRegex(ValueError,"probe payload"):
            n.validate_placement(config,scope)


class ComponentTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="r180_UNIT_COMPONENT_NOT_PROOF_");self.addCleanup(self.temp.cleanup)
        self.path=Path(self.temp.name);self.source=Path(n.__file__).absolute().parent
        self.hashes={name:n.digest(self.source/name) for name in n.NAMES}
        self.returned=self.path/"returned";self.returned.mkdir();(self.returned/"kernel").mkdir()
        self.outcome=dict(status="PASS_COMPUTE_OWNED_HELPER_KERNEL_MATRIX_NOT_R",error=None,all_private_descendants_reaped=True,
            R_startup_proved=False,numerical_parity_proved=False,
            case_results=[dict(label=label,expected=expected,test_expectation_met=True,all_private_descendants_reaped=True)
                          for label,case,expected,wall in CASE_ROWS])
        self.result=dict(status="INVENTORY_COMPLETE_KERNEL_PASS_NO_R",role="COMPUTE_RUNTIME_INVENTORY",error=None,
            job_id="887283",scope_id="UNIT_OLD_SCOPE",node="node-13",new_models=0,optimizer_invocations=0,outcome=self.outcome,
            sources={name:dict(path="/UNIT_NOT_EXECUTED/"+name,sha256=sha) for name,sha in self.hashes.items()})
        self.cached="/mnt/beegfs/home/jaguir26/pricefm_UNIT/runtime/venv/bin/python"
        oldspec=dict(cached_python=self.cached,cached_python_sha256="c"*64,node="node-13",sources=self.result["sources"])
        sp=self.save("packet/SPEC.json",oldspec)
        self.result["spec_sha256"]=sp["sha256"]
        self.save("PACKET.json",dict(role="COMPUTE_RUNTIME_INVENTORY",scope_id="UNIT_OLD_SCOPE",
            spec_sha256=sp["sha256"],sources=self.result["sources"]))
        self.inventory=dict(status="COMPUTE_RUNTIME_FACTS_NO_R",node="node-13",hostname="node-13",job_id="887283",
            uname=["Linux","node-13","UNIT_KERNEL","UNIT_BUILD","x86_64"],python=dict(path="/UNIT_NATIVE/python",sha256="c"*64),
            python_version="UNIT_PYTHON",libc="UNIT_LIBC",helpers={},cpus_per_task=1,affinity=[0])
        ip=self.save("returned/INVENTORY.json",self.inventory)
        self.rp=self.save("returned/RESULT.json",self.result);self.kp=self.save("returned/kernel/KERNEL_MATRIX_RESULT.json",self.outcome)
        rows=[dict(relative=str(Path(p["path"]).relative_to(self.returned)),sha256=p["sha256"],bytes=Path(p["path"]).stat().st_size) for p in (self.rp,self.kp,ip)]
        self.mp=self.save("returned/RETURN_MANIFEST.json",dict(schema="pricefm_startup_batch_return_manifest_v1",job_id="887283",scope_id="UNIT_OLD_SCOPE",new_models=0,files=rows))
        self.ap=self.save("account.json",dict(complete=True,terminal=True,job_id="887283",primary_charge_counted_once=True,canonical_primary_CPU_seconds=4.667))
        self.peer=self.save("peer.json",dict(status="PASS_REVIEWED_STARTUP_BATCH_ROLE",role="COMPUTE_RUNTIME_INVENTORY",job_id="887283",result=self.rp,return_manifest=self.mp,accounting=self.ap))
        self.candidate=dict(status="ACCEPTANCE_PENDING_ACTUAL_OUTER_GUARD",role="COMPUTE_RUNTIME_INVENTORY",job_id="887283",scope_id="UNIT_OLD_SCOPE",kernel_matrix_pass=True,primary_charge_counted_once=True,canonical_primary_CPU_seconds=4.667,result=self.rp,full_return_manifest=self.mp,accounting=self.ap,independent_review=self.peer)
        guard=dict(returncode=0,command_returncode=0,cap_reason=None,CPU_limit=5,aggregate_CPU_seconds=.2,
                   complete_lifecycle_wall_seconds=.3,guardian_forced_monitor_stop=False,stdout=json.dumps(self.candidate))
        for field in ("all_owned_descendants_reaped","independent_guardian","kernel_escape_filter","orphan_subreaper","guardian_included_in_CPU","inherited_waited_history_included_once"):guard[field]=True
        gp=self.save("guard.json",guard)
        self.accepted=dict(self.candidate,status="ACCEPTED_COMPLETE_STARTUP_BATCH_METADATA_ROLE",actual_accept_action_guard=gp)
        self.accepted_pin=self.save("ACCEPTED.json",self.accepted)
        self.config=dict(accepted_inventory=self.accepted_pin,node="node-13",frontend_source=h.pin(n.__file__),
            cached_python=self.cached,cached_python_sha256="c"*64,scope=self.save("new_scope.json",{"status":"UNIT_NOT_AUTHORITY"}))

    def save(self,name,value):
        path=self.path/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value,sort_keys=True));return h.pin(path)

    def test_existing_component_checks_do_not_issue_R_authority(self):
        value=n.inspect_accepted_component(self.config,self.hashes)
        self.assertEqual(value,self.accepted)
        self.assertFalse((self.path/n.ROLE).exists())

    def test_changed_compute_source_refuses_reuse(self):
        hashes=dict(self.hashes);hashes["startup_stop_candidate.py"]="0"*64
        with self.assertRaisesRegex(ValueError,"fourteen"):n.inspect_accepted_component(self.config,hashes)

    def test_changed_cached_runtime_refuses_reuse(self):
        with self.assertRaisesRegex(ValueError,"cached Python"):
            n.inspect_accepted_component(dict(self.config,cached_python_sha256="d"*64),self.hashes)

    def test_changed_READY_context_blocks_release_before_network(self):
        ready=dict(inventory=dict(self.inventory,libc="DIFFERENT_LIBC"))
        root=self.path/"new_R";root.mkdir();self.save("new_R/READY.json",ready)
        with patch.object(n._base,"release") as network:
            with self.assertRaisesRegex(ValueError,"READY kernel"):
                n.release(self.config,{},root,"unused_bundle")
            network.assert_not_called()

    def test_same_runtime_different_one_CPU_allocation_is_explicit(self):
        ready=dict(inventory=dict(self.inventory,affinity=[1]))
        self.assertIsNone(n.validate_current_runtime_context(self.config,ready))

    def test_missing_or_failed_case_refuses_reuse(self):
        self.result["outcome"]["case_results"].pop()
        self.config["accepted_inventory"]=self.save("ACCEPTED.json",dict(self.accepted,result=self.save("returned/RESULT.json",self.result)))
        with self.assertRaisesRegex(ValueError,"six exact"):n.inspect_accepted_component(self.config,self.hashes)

    def test_no_fresh_cross_context_review_no_reuse(self):
        self.config["reuse_review"]=self.save("reuse.json",{"status":"PREPARED_NOT_REVIEWED"})
        with self.assertRaisesRegex(ValueError,"cross-context"):n.validate_kernel_reuse(self.config,{},self.hashes)

    def test_cross_context_review_binds_new_frontend_scope_and_all_sources(self):
        review=dict(status="PASS_REVIEWED_ACCEPTED_KERNEL_REUSE_FOR_FRESH_R_SCOPE",accepted_inventory=self.accepted_pin,
            accepted_result=self.rp,full_return_manifest=self.mp,actual_accept_action_guard=self.accepted["actual_accept_action_guard"],
            source_files=self.hashes,frontend_source=self.config["frontend_source"],scope=self.config["scope"],node="node-13",
            fresh_R_role_required=True,old_failed_R_role_reopened=False)
        self.config["reuse_review"]=self.save("reuse.json",review)
        self.assertEqual(n.validate_kernel_reuse(self.config,{},self.hashes),self.accepted)
        for field,value in (("scope",{}),("frontend_source",{}),("old_failed_R_role_reopened",True)):
            self.config["reuse_review"]=self.save("reuse.json",dict(review,**{field:value}))
            with self.assertRaisesRegex(ValueError,"cross-context"):n.validate_kernel_reuse(self.config,{},self.hashes)

    def test_fabricated_inventory_journal_is_never_preparation_input(self):
        registry=self.path/"registry";registry.mkdir();(registry/"COMPUTE_RUNTIME_INVENTORY").mkdir()
        with self.assertRaisesRegex(ValueError,"fabricated"):
            n.prepare({}, {},n.ROLE,self.hashes,registry)

    def test_fresh_R_packet_embeds_original_component_without_inventory_journal(self):
        registry=self.path/"registry";registry.mkdir()
        scope=self.save("packet_scope.json",{"status":"UNIT_NOT_EXECUTION_AUTHORITY"})
        carrier=self.path/"UNIT_NOT_RUNTIME.tar.gz";carrier.write_bytes(b"UNIT_NOT_RUNTIME")
        config=dict(self.config,scope=scope,source_dir=str(self.source),remote_namespace="/mnt/beegfs/home/jaguir26/pricefm_r180_UNIT",
            publication=self.save("publication.json",{"commit":"a"*40}),source_review=self.save("review.json",{"status":"UNIT_NOT_REVIEW"}),
            reuse_review=self.save("reuse.json",{"status":"UNIT_NOT_REUSE_AUTHORITY"}),
            cached_python="/mnt/beegfs/home/jaguir26/pricefm_unit/runtime/venv/bin/python",cached_python_sha256="c"*64,
            carrier=h.pin(carrier),carrier_manifest=self.save("carrier_manifest.json",{"status":"UNIT_NOT_RUNTIME"}))
        with patch.object(n,"validate_kernel_reuse",return_value=self.accepted),patch.object(n.os,"fork",side_effect=AssertionError("metadata cannot fork")):
            packet=n.prepare(config,{"expires_epoch":2000000000.},n.ROLE,self.hashes,registry)
        root=registry/n.ROLE/"packet";spec=json.loads((root/"SPEC.json").read_text())
        self.assertEqual(spec["accepted_inventory"],self.accepted)
        self.assertEqual(spec["accepted_inventory_reference"],self.accepted_pin)
        self.assertEqual(spec["native_frontend_source"],h.pin(n.__file__))
        self.assertEqual({k:v["sha256"] for k,v in spec["sources"].items()},self.hashes)
        self.assertNotIn("startup_native_r_only.py",spec["sources"])
        self.assertIn("startup_batch_stop_worker.py",(root/"job.sbatch").read_text())
        self.assertTrue(packet["scope_id"].startswith("r180-R46-"))
        self.assertFalse((registry/"COMPUTE_RUNTIME_INVENTORY").exists())


if __name__=="__main__":unittest.main()
