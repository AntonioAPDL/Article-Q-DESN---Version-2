#!/usr/bin/env python3.11
"""Generated metadata/process fixtures only; no original data or native R job."""
import copy
import csv
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = ROOT / "scripts/run_glofas_innovation_reference.py"
spec = importlib.util.spec_from_file_location("innovation_controller", CONTROLLER)
C = importlib.util.module_from_spec(spec)
spec.loader.exec_module(C)


def until(predicate, seconds=10):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(.04)
    raise AssertionError("generated fixture did not reach expected state")


class ControllerTests(unittest.TestCase):
    def make_purpose(self, tmp):
        root = tmp / "generated_source"
        root.mkdir()
        (root / "local_trackers").mkdir()
        scratch = tmp / "scratch"
        scratch.mkdir(mode=0o700)
        meta = tmp / "generated_metadata.json"
        meta.write_text("{}\n")
        pin = dict(path=str(meta), size_bytes=meta.stat().st_size,
            sha256=hashlib.sha256(meta.read_bytes()).hexdigest())
        prior = {name: dict(pin) for name in ("receipt", "summary", "manifest", "terminal")}
        b = dict(cpu_seconds=3600, wall_seconds=3600, memory_bytes=16*C.GiB, output_bytes=64*C.MiB,
            logical_cpu=26, max_workers=4, child_logical_cpus=[26,27,28,29], child_cpu_seconds=3600,
            aggregate_cpu_seconds=18000, aggregate_memory_bytes=80*C.GiB,
            memory_headroom_bytes=180*C.GiB, max_draw_memory_bytes=8*C.MiB)
        c = dict(schema_version="glofas_innovation_reference_contract_v1",
            purpose="MEDIAN_AL_FIXED_PARAMETER_INNOVATION_PCN_PILOT_NO_FULL_REFIT", mode="computational_pilot",
            execution_mode="fork_four", nonce="ab"*16,
            expires_utc=(dt.datetime.now(dt.timezone.utc)+dt.timedelta(hours=2)).isoformat(),
            source_root=str(root), source_commit="a"*40, source_tree="b"*40, source_files=[], limits=b,
            output_root=str(root / "local_trackers" / "pilot"), metadata_scratch_root=str(scratch),
            design=dict(path="/NONEXISTENT_TEST_ONLY/shared_truth_free_design.rds",size_bytes=4014834693,
                sha256="193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3"),
            median_model=dict(path="/NONEXISTENT_TEST_ONLY/fit.rds",size_bytes=137820489,
                sha256="f56b4b7792ab04bd431838c8ef94ff88dd859d16cd70cb68116eecf6fade5881"),
            collection=dict(pin), input_manifest=dict(pin), baseline=copy.deepcopy(prior),
            prior_replay=copy.deepcopy(prior), prior_recovery=copy.deepcopy(prior),
            diagnostic_dependencies=dict(versions=dict(pin),sources=dict(pin),library_root="/GENERATED_ONLY"),
            read_budget=dict(max_RDS_deserializations=2,max_generated_RDS_deserializations=0,
                max_deserialization_bytes=8*C.GiB,max_payload_hash_bytes=16*C.GiB,max_metadata_bytes=64*C.MiB),
            innovation=dict(likelihood_family="al",tau=.5,
                parameter_rule="retained_theta_mean_fixed_coefficient_covariance_zero",
                scale_rule="reciprocal_retained_inverse_scale_means_not_scale_means",parity_tolerance=1e-10,
                minimum_tail_seconds=120,max_total_forward_evaluations=7000,
                max_total_inverse_evaluations=16,max_total_reference_evaluations=32,
                sampler=dict(warmup=500,samples=1000,max_evaluations=1501,
                    seeds=[2026110501,2026110502,2026110503,2026110504],adapt_warmup=True,
                    rhat_max=1.01,min_ess=400,max_quantile_mcse=.001,max_wall_seconds=2400,
                    delta_initial=.15,delta_min=.0001,delta_max=.95,target_accept=.234,progress_every=250)),
            draw_export=dict(filename="innovation_draws.rds",max_bytes=4*C.MiB),
            **{k:True for k in C.YES}, **{k:False for k in C.NO})
        return c

    def save_purpose(self, tmp, c):
        p = tmp / "purpose.json"
        p.write_text(json.dumps(c))
        p.chmod(0o600)
        return p, hashlib.sha256(p.read_bytes()).hexdigest()

    def admitted(self, tmp, c):
        p,digest = self.save_purpose(tmp,c)
        with mock.patch.object(C,"pin_source"), mock.patch.object(C,"freshness",return_value={"generated":True}), \
             mock.patch.object(C,"git",side_effect=lambda root,*args:args[-1]):
            return C.validate_contract(p,digest,launching=True)

    def test_default_does_not_launch_or_call_historical_scope(self):
        with mock.patch.object(C,"launch_tmux") as launch, \
             mock.patch.object(C.U,"validate_contract",side_effect=AssertionError("historical scope forbidden")):
            self.assertEqual(C.main([]),0)
            launch.assert_not_called()
        with self.assertRaisesRegex(ValueError,"requires explicit"):
            C.main(["--launch"])

    def test_new_source_closure_and_historical_globals_unchanged(self):
        self.assertEqual(len(C.SOURCE_PATHS),22)
        self.assertEqual(C.CPUS,{26,27,28,29})
        self.assertEqual(C.U.CPUS,{20,21,22,23,26,27,28,29})
        self.assertEqual(C.U.READER,"scripts/glofas_reference_recovery_reader.R")
        self.assertIn("scripts/run_glofas_reference_recovery.py",C.SOURCE_PATHS)
        self.assertNotIn("scripts/glofas_reference_recovery_reader.R",C.SOURCE_PATHS)

    def test_complete_generated_purpose_opens_no_original_payload(self):
        with tempfile.TemporaryDirectory() as tmp0:
            tmp=Path(tmp0);c=self.make_purpose(tmp)
            real_sha=C.sha
            def safe_sha(path,*args):
                self.assertNotEqual(Path(path).suffix.lower(),".rds")
                return real_sha(path,*args)
            with mock.patch.object(C,"sha",side_effect=safe_sha):
                actual,_=self.admitted(tmp,c)
            self.assertEqual(actual["read_budget"]["max_generated_RDS_deserializations"],0)

    def test_permission_resource_input_and_sampler_mutations_fail_closed(self):
        mutations = [
            lambda c:c.update(allow_truth_read=True),
            lambda c:c.update(allow_generated_numeric_array_read=True),
            lambda c:c.update(allow_proposal_calibration=True),
            lambda c:c.update(allow_unknown_operation=True),
            lambda c:c.update(execution_mode="fork_eight"),
            lambda c:c["limits"].update(child_logical_cpus=[20,21,22,23]),
            lambda c:c["limits"].update(aggregate_memory_bytes=64*C.GiB),
            lambda c:c["limits"].update(memory_headroom_bytes=179*C.GiB),
            lambda c:c["limits"].update(logical_cpu=20),
            lambda c:c["limits"].update(max_workers=8),
            lambda c:c["median_model"].update(sha256="d"*64),
            lambda c:c["read_budget"].update(max_RDS_deserializations=3),
            lambda c:c["read_budget"].update(max_generated_RDS_deserializations=1),
            lambda c:c["innovation"]["sampler"].update(samples=2000),
            lambda c:c["innovation"]["sampler"].update(seeds=[1,2,3,4]),
            lambda c:c["innovation"]["sampler"].update(rhat_max=1.05),
            lambda c:c["innovation"].update(max_total_forward_evaluations=10000),
            lambda c:c["draw_export"].update(max_bytes=8*C.MiB),
            lambda c:c.update(expires_utc=dt.datetime.now(dt.timezone.utc).isoformat()),
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as tmp0:
                tmp=Path(tmp0);c=self.make_purpose(tmp);mutation(c)
                with self.assertRaises(ValueError):self.admitted(tmp,c)

    def test_purpose_digest_private_mode_output_and_duplicate_keys(self):
        with tempfile.TemporaryDirectory() as tmp0:
            tmp=Path(tmp0);c=self.make_purpose(tmp);p,digest=self.save_purpose(tmp,c)
            with self.assertRaisesRegex(ValueError,"digest"):C.validate_contract(p,"f"*64)
            p.chmod(0o644)
            with self.assertRaisesRegex(ValueError,"private"):C.validate_contract(p,digest)
            p.chmod(0o600);p.write_text('{"same":1,"same":2}')
            with self.assertRaisesRegex(ValueError,"duplicate"):C.read_json(p)
            Path(c["output_root"]).mkdir()
            with self.assertRaisesRegex(ValueError,"already exists"):self.admitted(tmp,c)

    def generated_manifest(self,out):
        c=dict(source_commit="a"*40,source_tree="b"*40,output_root=str(out),
            draw_export=dict(max_bytes=4*C.MiB),limits=dict(output_bytes=64*C.MiB,
                child_cpu_seconds=3600,memory_bytes=16*C.GiB,aggregate_cpu_seconds=18000),
            innovation=dict(max_total_forward_evaluations=7000,max_total_inverse_evaluations=16,
                max_total_reference_evaluations=32))
        reads=[]
        for role in ("design","median_model"):
            c[role]=dict(path="/NONEXISTENT_TEST_ONLY/"+role+".rds",size_bytes=123,sha256="c"*64)
            reads.append(dict(role=role,**c[role],pre_read_sha256="c"*64,post_read_sha256="c"*64,status="DESERIALIZED"))
        p=out/"innovation_draws.rds"
        p.write_bytes(b"tiny GENERATED file fixture, not scientific data")
        export=dict(path=str(p),relative_path=p.name,size_bytes=p.stat().st_size,
            sha256=hashlib.sha256(p.read_bytes()).hexdigest(),generated_array_only=True,
            full_parameter_posterior_draws=False,dimensions=[1000,4,28],finite_values=112000,missing_values=0)
        timing=dict(measured_forward_max_seconds=.05,safety_factor=2,projected_chain_seconds=.05*2*1501,
            max_chain_evaluations=1501,sampler_wall_seconds=2400,minimum_tail_seconds=120,remaining_seconds_at_fork=3500)
        receipt=dict(schema_version="glofas_innovation_reference_receipt_v1",
            status="PILOT_COMPLETE_NOT_PRODUCTION_QUALIFICATION",source_commit=c["source_commit"],source_tree=c["source_tree"],
            purpose_sha256="d"*64,generated_draw_export=export,original_RDS_deserializations=2,
            generated_numeric_array_deserializations=0,saved_callback_calls=0,full_parameter_refits=0,future_truth_read=False,
            attempted_reads=reads,timing_admission=timing,forward_evaluations=6004,inverse_evaluations=4,reference_evaluations=4,
            aggregate_cpu_seconds=1.2,
            fixed_point=dict(parameter_id="GENERATED_ONLY_FIXED_POINT"),
            worker_proofs=[dict(pid=900000+i,ppid=888000,pgrp=888000,cpus=str(cpu),logical_cpu=cpu,
                native_cpu_limits=[3600,3600],native_address_space_limits=[16*C.GiB,16*C.GiB],CPU_seconds=.2,starttime="0")
                for i,cpu in enumerate(sorted(C.CPUS))],**{k:False for k in C.QUALIFICATIONS})
        C.write_new(out/"INNOVATION_REFERENCE_RECEIPT.json",receipt)
        C.write_new(out/"innovation_summary.json",dict(schema_version="glofas_innovation_reference_summary_v1",
            status=receipt["status"],diagnostic_thresholds_passed=False,fixed_point=receipt["fixed_point"],
            forward_evaluations=6004,inverse_evaluations=4,reference_evaluations=4,
            **{k:False for k in C.QUALIFICATIONS}))
        (out/"innovation_parity.csv").write_text("generated_only\n")
        for i in range(1,5):
            C.write_new(out/f"progress_chain_{i}.json",dict(schema_version="glofas_innovation_progress_v1",
                chain_id=i,completed_iterations=1500,retained_iterations=1000,fully_completed=True,callback_evaluations=1501))
        self.re_manifest(out)
        return c

    def re_manifest(self,out):
        with (out/"artifact_manifest.csv").open("w",newline="") as f:
            w=csv.writer(f);w.writerow(["relative_path","size_bytes","sha256"])
            for p in sorted(out.iterdir()):
                if p.name!="artifact_manifest.csv":
                    w.writerow([p.name,p.stat().st_size,hashlib.sha256(p.read_bytes()).hexdigest()])

    def test_closed_generated_manifest_without_reopening_originals(self):
        with tempfile.TemporaryDirectory() as tmp:
            c=self.generated_manifest(Path(tmp))
            closed=C.verify_manifest(c)
            self.assertTrue(closed["output_manifest_verified"])
            self.assertEqual(closed["original_RDS_deserializations"],2)
            self.assertEqual(closed["generated_numeric_array_deserializations"],0)

    def test_manifest_tamper_unlisted_output_and_false_qualification_rejected(self):
        for change in ("unlisted","array","qualified","read","incomplete","CPU","timing","evaluations","progress"):
            with self.subTest(change=change),tempfile.TemporaryDirectory() as tmp0:
                out=Path(tmp0);c=self.generated_manifest(out)
                if change=="unlisted":(out/"unlisted.json").write_text("{}")
                elif change=="array":(out/"innovation_draws.rds").write_bytes(b"different generated bytes")
                elif change=="progress":
                    p=out/"progress_chain_4.json";r=json.loads(p.read_text())
                    r["fully_completed"]=False;p.write_text(json.dumps(r));self.re_manifest(out)
                else:
                    p=out/"INNOVATION_REFERENCE_RECEIPT.json";r=json.loads(p.read_text())
                    if change=="qualified":r["reference_qualified"]=True
                    elif change=="read":r["attempted_reads"][0]["post_read_sha256"]="f"*64
                    elif change=="incomplete":r["generated_draw_export"]["missing_values"]=1
                    elif change=="CPU":r["worker_proofs"][0]["logical_cpu"]=48
                    elif change=="timing":r["timing_admission"]["measured_forward_max_seconds"]=100
                    elif change=="evaluations":r["forward_evaluations"]=7001
                    p.write_text(json.dumps(r));self.re_manifest(out)
                with self.assertRaises(ValueError):C.verify_manifest(c)

    def test_timing_gate_requires_measured_cost_not_optimistic_or_relaxed_budget(self):
        good=dict(measured_forward_max_seconds=.05,safety_factor=2,projected_chain_seconds=.05*2*1501,
            max_chain_evaluations=1501,sampler_wall_seconds=2400,minimum_tail_seconds=120,remaining_seconds_at_fork=3500)
        C.verify_timing(good)
        for field,value in (("safety_factor",1),("remaining_seconds_at_fork",2520),
            ("projected_chain_seconds",1),("sampler_wall_seconds",3000),("measured_forward_max_seconds",float("nan"))):
            with self.subTest(field=field),self.assertRaises(ValueError):C.verify_timing(dict(good,**{field:value}))

    def test_native_command_fixed_reader_limits_and_no_arbitrary_contract_command(self):
        c=dict(limits=dict(logical_cpu=26,cpu_seconds=3600,wall_seconds=3600,memory_bytes=16*C.GiB,
            output_bytes=64*C.MiB),command="FORBIDDEN_CONTRACT_COMMAND")
        a=C.native_command(c,"/EXTERNAL/purpose.json","a"*64,Path("/PRIVATE"))
        self.assertIn(C.READER,a);self.assertNotIn(c["command"],a)
        at=a.index("/usr/bin/timeout")
        self.assertEqual(a[at+1:at+5],["--signal=TERM","--kill-after=1s","3599s","/usr/bin/prlimit"])

    def test_original_and_other_rds_hashes_are_forbidden(self):
        with tempfile.TemporaryDirectory() as tmp0:
            out=Path(tmp0);p=out/"fit.rds";p.write_bytes(b"generated sentinel")
            with self.assertRaisesRegex(ValueError,"must not open"):C.sha(p)
            with self.assertRaisesRegex(ValueError,"only exact bounded"):C.generated_array_sha(p,out,1000)

    def test_atomic_writer_preserves_existing_failure_evidence(self):
        with tempfile.TemporaryDirectory() as tmp0:
            p=Path(tmp0)/"terminal.json";C.write_new(p,dict(failure="preserve"))
            with self.assertRaisesRegex(ValueError,"overwrite"):C.write_new(p,dict(success=True))
            self.assertEqual(json.loads(p.read_text()),dict(failure="preserve"))

    def test_progress_atomic_names_and_output_scanner(self):
        self.assertTrue(C.expected_pending(Path("/out/progress_chain_1.json.new"),Path("/control"),Path("/out")))
        self.assertFalse(C.expected_pending(Path("/out/progress_worker_01.json.new"),Path("/control"),Path("/out")))
        with tempfile.TemporaryDirectory() as tmp0:
            control=Path(tmp0)/"control";out=Path(tmp0)/"output";control.mkdir();out.mkdir()
            (control/"a.txt").write_text("abc");(out/"b.txt").write_text("four")
            self.assertEqual(C.scan_output_bytes(control,out),7)
            (out/"link").symlink_to(out/"b.txt")
            with self.assertRaisesRegex(ValueError,"symlink"):C.scan_output_bytes(control,out)

    def test_native_limit_checker_and_live_child_monitor(self):
        c=dict(output_root="/GENERATED_OUTPUT",limits=dict(cpu_seconds=60,child_cpu_seconds=60,memory_bytes=1000,
            output_bytes=2000,aggregate_memory_bytes=10000,aggregate_cpu_seconds=1000,wall_seconds=60))
        limits="Max cpu time              60                   60                   seconds\n" \
            "Max address space         1000                 1000                 bytes\n" \
            "Max file size             2000                 2000                 bytes\n"
        parent=dict(pid=100,session=90,pgid=91)
        children=[dict(pid=200+i,ppid=100,session=90,pgid=91,comm="R",CPUs_allowed_list=str(cpu),limits=limits,
            starttime_ticks=str(i),cpu_seconds=.1,rss_bytes=10) for i,cpu in enumerate(sorted(C.CPUS))]
        child=mock.Mock();child.poll.side_effect=[None,0];child.wait.return_value=0
        with mock.patch.object(C,"owned_rows",return_value=children),mock.patch.object(C,"scan_output_bytes",return_value=0), \
             mock.patch.object(C.time,"sleep"):
            result=C.monitor(child,{},c,Path("/GENERATED_CONTROL"),parent)
        self.assertEqual(len(result["independently_observed_workers"]),4)
        bad=dict(children[0],CPUs_allowed_list="48")
        child.poll.side_effect=[None]
        with mock.patch.object(C,"owned_rows",return_value=[bad]),self.assertRaisesRegex(ValueError,"affinity"):
            C.monitor(child,{},c,Path("/GENERATED_CONTROL"),parent)
        with self.assertRaisesRegex(ValueError,"soft/hard"):
            C.check_limits(dict(limits=limits.replace("1000","unlimited")),c)

    def test_four_role_native_capture_checks_lineage_caps_affinity_and_purpose(self):
        c=dict(source_commit="a"*40,source_tree="b"*40,
            limits=dict(logical_cpu=26,child_cpu_seconds=60,memory_bytes=1000,output_bytes=2000))
        limits="Max cpu time              60                   60                   seconds\n" \
            "Max address space         1000                 1000                 bytes\n" \
            "Max file size             2000                 2000                 bytes\n"
        digest="d"*64;purpose=Path("/EXTERNAL/generated_purpose.json")
        rows=[dict(pid=100,ppid=99,pgid=100,comm="bash"),dict(pid=101,ppid=100,pgid=100,comm="time"),
            dict(pid=102,ppid=101,pgid=102,comm="timeout"),dict(pid=103,ppid=102,pgid=102,comm="R",
                CPUs_allowed_list="26",limits=limits,command=f"{C.READER} --contract {purpose} --sha256 {digest}")]
        child=mock.Mock(pid=100);child.poll.return_value=None
        with mock.patch.object(C,"owned_rows",return_value=rows):
            captured=C.capture(child,{},c,purpose,digest)
        self.assertEqual(set(captured["processes"]),{"shell","time","timeout","R"})
        self.assertTrue(captured["native_limits_verified"])
        for field,value in (("CPUs_allowed_list","48"),("pgid",999),("command","unbound purpose")):
            bad=copy.deepcopy(rows);bad[-1][field]=value
            with self.subTest(field=field),mock.patch.object(C,"owned_rows",return_value=bad), \
                 self.assertRaisesRegex(ValueError,"lineage"):
                C.capture(child,{},c,purpose,digest)

    def test_cleanup_owns_session_and_preserves_unrelated_process(self):
        unrelated=subprocess.Popen(["/usr/bin/sleep","30"],start_new_session=True)
        child=subprocess.Popen(["/usr/bin/bash","--noprofile","--norc","-c",
            "/usr/bin/timeout --signal=TERM --kill-after=1s 30s /usr/bin/sleep 30 &\nwait\nrc=$?\nexit \"$rc\""],
            start_new_session=True)
        identity=C.process(child.pid)
        try:
            until(lambda:any(r["comm"]=="timeout" for r in C.owned_rows(identity)))
            C.cleanup_owned(child,identity)
            self.assertFalse(C.owned_rows(identity));self.assertIsNone(unrelated.poll())
        finally:
            if child.poll() is None:C.cleanup_owned(child,identity)
            unrelated.terminate();unrelated.wait(timeout=3)

    def test_failed_job_retains_unknown_read_status_and_closes_only_owned_actors(self):
        with tempfile.TemporaryDirectory() as tmp:
            control=Path(tmp);c=dict(source_root=tmp,output_root=str(control/"out"),
                limits=dict(aggregate_memory_bytes=256*C.MiB,aggregate_cpu_seconds=20,wall_seconds=5,output_bytes=4*C.MiB))
            code=C.run_owned_job(c=c,control=control,argv=["/usr/bin/sleep","30"],env=os.environ.copy(),
                capture_live=lambda *_:(_ for _ in ()).throw(ValueError("generated capture failure")),
                verify_after=lambda:self.fail("a failed native must not verify success"))
            r=json.loads((control/"terminal.json").read_text())
            self.assertEqual(code,1);self.assertFalse(r["computational_closure"])
            self.assertTrue(r["owner_terminated"])
            self.assertEqual(r["original_RDS_deserializations"],"UNKNOWN_NO_INDEPENDENT_CLOSED_RECEIPT")

    @unittest.skipUnless(shutil.which("tmux"),"tmux required for generated durable fixture")
    def test_private_tmux_survives_launcher_exit_and_records_terminal(self):
        nonce="ef"*16;control=C.new_control(nonce)
        with tempfile.TemporaryDirectory() as tmp0:
            tmp=Path(tmp0);driver=tmp/"generated_driver.py"
            driver.write_text('''import importlib.util,os,pathlib,sys
s=importlib.util.spec_from_file_location("C",sys.argv[1]);C=importlib.util.module_from_spec(s);s.loader.exec_module(C)
p=pathlib.Path(sys.argv[2]);C.write_new(p/"fixture_started.json",{"pid":os.getpid()})
c=dict(source_root=str(p),output_root=str(p/"out"),limits=dict(aggregate_memory_bytes=512*C.MiB,
 aggregate_cpu_seconds=20,wall_seconds=5,output_bytes=4*C.MiB))
job="import time;time.sleep(1.5)"
sys.exit(C.run_owned_job(c=c,control=p,argv=[sys.executable,"-B","-c",job],env=os.environ.copy(),
 capture_live=lambda child,identity:{"fixture":True},verify_after=lambda:{"generated_fixture":True,"original_RDS_deserializations":0}))
''')
            launcher=tmp/"generated_launcher.py"
            launcher.write_text('''import importlib.util,json,sys
s=importlib.util.spec_from_file_location("C",sys.argv[1]);C=importlib.util.module_from_spec(s);s.loader.exec_module(C)
print(json.dumps(C.launch_tmux(sys.argv[2],sys.argv[3],[sys.executable,"-B",sys.argv[4],sys.argv[1],sys.argv[2]])))
''')
            try:
                front=subprocess.run([sys.executable,"-B",str(launcher),str(CONTROLLER),str(control),nonce,str(driver)],
                    capture_output=True,text=True,timeout=10)
                self.assertEqual(front.returncode,0,front.stderr)
                until(lambda:(control/"fixture_started.json").exists())
                self.assertFalse((control/"terminal.json").exists())
                until(lambda:(control/"terminal.json").exists())
                terminal=json.loads((control/"terminal.json").read_text())
                self.assertTrue(terminal["computational_closure"],terminal)
                self.assertTrue(terminal["generated_fixture"])
                self.assertEqual(terminal["native_exit_code"],0)
                self.assertTrue(all(terminal[k] is False for k in C.QUALIFICATIONS))
            finally:
                if (control/"server.sock").exists():
                    subprocess.run(["/usr/bin/tmux","-S",str(control/"server.sock"),"kill-server"],capture_output=True,timeout=5)
                shutil.rmtree(control)


if __name__=="__main__":unittest.main()
