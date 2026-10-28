"""Independent finite metadata custody tests; all scheduler I/O is mocked."""
import copy
import multiprocessing
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest import mock
from . import activation as a, lifecycle as l, registry as r, handoff


def _race_poll(directory, epoch, queue):
    l.CENTRAL = Path(directory)
    l.owner = lambda: None
    with mock.patch.object(l.time, "time", return_value=epoch):
        try:
            l.Ledger().poll("key")
            queue.put("accepted")
        except a.ActivationError:
            queue.put("blocked")


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.central = self.root / "canonical"
        self.release_root = self.root / "release"
        self.release_root.mkdir()
        self.now = time.time()
        self.config = {"user": "jaguir26", "host": "hb.ucsc.edu", "remote_root": "/mnt/beegfs/home/jaguir26/test"}
        self.release = dict(schema=l.RELEASE_SCHEMA, purpose="CONTROL_TEST", study="TEST", task_key="key",
            scientific_exclusion_key="TEST|fixed", scope_id="scope-01", plan_sha256="a" * 64,
            resources=dict(cpus=1,memory_MiB=4096,wall_seconds=120,cpu_seconds=120),
            runtime_python="/fixed/python", node="node-13", policy_pin={"path": "/policy", "sha256": "b" * 64},
            source_hashes={"science.py": "c" * 64}, remote_root="/mnt/beegfs/home/jaguir26/test/r157-fixed",
            release_id="r157-" + "d" * 32)
        r.write(self.release_root / "release.json", self.release)
        r.write(self.release_root / "launch-request.json", {})
        for target, name, value in ((l,"CENTRAL",self.central),(l,"owner",lambda:None),
                (l,"policy_document",lambda pin:{}),(l,"hb_concurrency",lambda packet:1)):
            patch = mock.patch.object(target,name,value); patch.start(); self.addCleanup(patch.stop)
        self.ledger = l.Ledger()

    def reserve(self):
        return self.ledger.reserve(self.release,self.release_root,self.config)

    def state(self, state="SUBMITTED", **fields):
        claim = self.reserve()
        claim.update(state=state,job_id="868901",**fields)
        value=self.ledger.snapshot();value["claims"]["key"]=claim;r.write(self.ledger.path,value)
        return claim

    def test_spent_TEST_is_nonrenewing_after_reconciliation(self):
        self.state("FAILED_RECONCILED")
        changed=dict(self.release,task_key="other-key")
        with self.assertRaises(a.ActivationError): self.ledger.reserve(changed,self.release_root,self.config)
        self.assertEqual(self.ledger.snapshot()["spent_tests"],["key"])

    def test_cost_requires_one_accepted_drained_same_source_TEST(self):
        cost=dict(self.release,purpose="COST_ONLY",study="FI",task_key="cost",scope_id="cost-01")
        with self.assertRaises(a.ActivationError): self.ledger.reserve(cost,self.release_root,self.config)
        claim=self.state("COLLECTED",application_accepted=True)
        with mock.patch.object(l,"verify_release",return_value=self.release):
            accepted=self.ledger.reserve(cost,self.release_root,self.config)
        self.assertEqual(accepted["task"]["purpose"],"COST_ONLY")
        state=self.ledger.snapshot();del state["claims"]["cost"];state["claims"]["key"]["application_accepted"]=False;r.write(self.ledger.path,state)
        with mock.patch.object(l,"verify_release",return_value=self.release),self.assertRaises(a.ActivationError):
            self.ledger.reserve(cost,self.release_root,self.config)
        state["claims"]["key"]["application_accepted"]=True;r.write(self.ledger.path,state)
        with mock.patch.object(l,"verify_release",return_value=dict(self.release,source_hashes={"science.py":"f"*64})),self.assertRaises(a.ActivationError):
            self.ledger.reserve(cost,self.release_root,self.config)

    def test_claim_identity_and_state_transitions_cannot_be_overwritten(self):
        self.reserve()
        with self.assertRaises(a.ActivationError): self.ledger.transition("key","RESERVED","SUBMITTED")
        with self.assertRaises(a.ActivationError): self.ledger.transition("key","RESERVED","STAGED",resources={"cpus":2})
        self.ledger.transition("key","RESERVED","STAGED")
        with self.assertRaises(a.ActivationError): self.ledger.transition("key","RESERVED","AMBIGUOUS")

    def test_poll_throttle_is_atomic_across_processes(self):
        self.state(last_poll=self.now-301)
        context=multiprocessing.get_context("fork");queue=context.Queue()
        workers=[context.Process(target=_race_poll,args=(str(self.central),self.now,queue)) for _ in range(2)]
        for worker in workers:worker.start()
        for worker in workers:worker.join(5);self.assertEqual(worker.exitcode,0)
        self.assertEqual(sorted([queue.get(timeout=1),queue.get(timeout=1)]),["accepted","blocked"])

    def test_startup_subscription_and_poll_clock_cannot_be_reset(self):
        self.state(last_poll=self.now)
        self.ledger.update("key",startup_event_claimed=True)
        with self.assertRaises(a.ActivationError):self.ledger.update("key",startup_event_claimed=True)
        with self.assertRaises(a.ActivationError):self.ledger.update("key",startup_event_claimed=False)
        with self.assertRaises(a.ActivationError):self.ledger.update("key",last_poll=self.now-1)

    def test_ambiguous_submission_spends_attempt_without_guessing_job_ID(self):
        calls=[]
        def remote(config,argv):
            calls.append(argv)
            if argv[0]=="sha256sum":return r.digest(self.release_root/"release.json")+"  release.json"
            if argv[0]=="sbatch":raise subprocess.TimeoutExpired(argv,10)
            return ""
        with mock.patch.object(l,"verify_release",return_value=self.release),mock.patch.object(l,"validate_request"),\
                mock.patch.object(l.ctl,"config",return_value=self.config),mock.patch.object(l,"remote",side_effect=remote),\
                mock.patch.object(l,"bind_control"),\
                mock.patch.object(l,"transfer"):
            with self.assertRaises(subprocess.TimeoutExpired):l.submit_component(self.release_root,"config")
            claim=self.ledger.snapshot()["claims"]["key"]
            self.assertEqual(claim["state"],"AMBIGUOUS");self.assertNotIn("job_id",claim)
            with self.assertRaises(a.ActivationError):l.submit_component(self.release_root,"config")
        self.assertEqual(sum(row[0]=="sbatch" for row in calls),1)

    def test_cancellation_requires_exact_pending_server_job(self):
        claim=self.state("HELD")
        binding=(self.ledger,claim,self.release,self.config)
        with mock.patch.object(l,"_bound_claim",return_value=binding),mock.patch.object(l,"remote",return_value="JobId=868901 JobState=RUNNING") as remote:
            with self.assertRaises(a.ActivationError):l.cancel_held("key","config")
            self.assertEqual(remote.call_count,1)
        with mock.patch.object(l,"_bound_claim",return_value=binding),mock.patch.object(l,"remote",side_effect=["JobId=868901 JobState=PENDING",""]) as remote:
            result=l.cancel_held("key","config")
            self.assertEqual(result["state"],"AMBIGUOUS")
            self.assertEqual(remote.call_args.args[1],["scancel","868901"])

    def test_never_allocated_CANCELLED_is_terminal_but_never_complete(self):
        text="868901|CANCELLED by 1000|0:0|0|0|00:00:00||None|Unknown|Unknown\n"
        parsed=l.parse_accounting(text,"868901",self.release["resources"])
        self.assertTrue(parsed["terminal"]);self.assertFalse(parsed["complete"])
        self.assertTrue(parsed["unstarted_cancelled"])

    def test_unstarted_cancellation_rejects_duplicate_or_running_extern(self):
        primary="868901|CANCELLED by 1000|0:0|0|0|00:00:00||None|Unknown|Unknown\n"
        extern="868901.extern|COMPLETED|0:0|0|0|00:00:00||None|Unknown|Unknown\n"
        for bad in (primary+extern+extern,primary+extern.replace("COMPLETED","RUNNING"),primary.replace("|0|0|00:","|0|1|00:")):
            with self.subTest(bad=bad),self.assertRaises((a.ActivationError,ValueError)):
                l.parse_accounting(bad,"868901",self.release["resources"])

    def test_accounting_cannot_hide_CPU_or_wall_scope_violation(self):
        rows=[]
        for suffix in ("",".batch",".0"):
            rows.append("868901"+suffix+"|COMPLETED|0:0|121|1|00:02:01|1024K|node-13|2026-10-28T00:00:00|2026-10-28T00:02:01")
        result=l.parse_accounting("\n".join(rows),"868901",self.release["resources"])
        self.assertFalse(result["complete"]);self.assertEqual(len(result["scope_violations"]),3)

    def request_fixture(self):
        self.pins={}
        def add(name,value):
            path=self.root/(name+".json");r.write(path,value);pin=dict(path=str(path),sha256=r.digest(path));self.pins[str(path)]=value;return pin
        request=dict(schema=a.REQUEST_SCHEMA,automatic_retry=False,policy_pin=self.release["policy_pin"],
            purpose=self.release['purpose'],study=self.release['study'],scientific_exclusion_key=self.release['scientific_exclusion_key'],
            handoff_receipt=add("handoff",{"observed_epoch":self.now}),
            all_hosts_observation=add("hosts",dict(status="NO_OVERLAP",observed_epoch=self.now,overlapping_scientific_claims=[],
                controller=a.OWNER,hosts=[a.OWNER,'jerez.be.ucsc.edu','hb.ucsc.edu'],scientific_exclusion_key=self.release['scientific_exclusion_key'])),
            site_admission=add("site",dict(status="ADMITTED_COST_ONLY_RESOURCES",observed_epoch=self.now,available_cpus=1,
                memory_mib=4096,available_memory_mib=8192,minimum_required_memory_mib=1024,node="node-13",
                account="128x24",partition="128x24",qos="normal",calendar_expires_epoch=self.now+3600,
                purpose=self.release['purpose'],study=self.release['study'],execution_plan_sha256=self.release['plan_sha256'])),
            execution_plan_sha256=self.release["plan_sha256"])
        return request

    def test_request_release_mismatch_and_unknown_handoff_rejected(self):
        request=self.request_fixture()
        with mock.patch.object(a,"read_pin",side_effect=lambda pin:self.pins[pin["path"]]),\
                mock.patch.object(a,"validate_qualification",return_value={"runtime":{"executable":"/fixed/python"}}),\
                mock.patch.object(handoff,"validate_handoff_receipt") as validate,\
                mock.patch.object(a,"validate_policy_sources"):
            l.validate_request(request,self.release)
            validate.assert_called_with(mock.ANY,mock.ANY,check_live=True)
            with self.assertRaises(a.ActivationError):l.validate_request(dict(request,execution_plan_sha256="f"*64),self.release)
            validate.side_effect=handoff.HandoffError("unproved held owner")
            with self.assertRaises(handoff.HandoffError):l.validate_request(request,self.release)

    def test_task_identity_and_cross_host_key_mismatch_block_before_claim(self):
        request=self.request_fixture()
        with mock.patch.object(a,'read_pin',side_effect=lambda pin:self.pins[pin['path']]),\
                mock.patch.object(a,'validate_qualification',return_value={'runtime':{'executable':'/fixed/python'}}),\
                mock.patch.object(handoff,'validate_handoff_receipt'),mock.patch.object(a,'validate_policy_sources'):
            for field,wrong in (('purpose','COST_ONLY'),('study','DK2'),('scientific_exclusion_key','other')):
                with self.subTest(field=field),self.assertRaises(a.ActivationError):
                    l.validate_request(dict(request,**{field:wrong}),self.release)
            self.pins[request['all_hosts_observation']['path']]['hosts']=[a.OWNER]
            with self.assertRaises(a.ActivationError):l.validate_request(request,self.release)

    def test_create_only_evidence_and_explicit_proof_roots_are_enforced(self):
        first=l.write_new(self.root/"evidence.json",{"one":1})
        with self.assertRaises(FileExistsError):l.write_new(self.root/"evidence.json",{"one":2})
        parent=l.write_new(self.root/"parent.json",{"nested":first})
        roots={'parent':parent,'child':first}
        manifest=l.pack_proofs(self.root/"packed",roots)
        self.assertEqual(set(manifest),{first["path"],parent["path"]})
        a.verify_proof_manifest({"proof_manifest":manifest},self.root/"packed")
        Path(first["path"]).write_text("{}")
        with self.assertRaises(a.ActivationError):l.pack_proofs(self.root/"repacked",roots)

    def test_historical_nested_pin_is_opaque_and_never_loads_missing_array(self):
        historical={'past':{'path':'/obsolete/history/large-array.npz','sha256':'f'*64}}
        parent=l.write_new(self.root/'historical-original.json',historical)
        manifest=l.pack_proofs(self.root/'opaque',{'controller_validated_historical_snapshot':parent})
        self.assertEqual(set(manifest),{parent['path']})
        original=a.read_pin(parent,{'proof_manifest':manifest},root=self.root/'opaque')
        self.assertEqual(original,historical)


if __name__=="__main__":unittest.main()
