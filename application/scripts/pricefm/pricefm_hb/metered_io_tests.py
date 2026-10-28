"""No-network CPU receipt, interruption and safe transport tests."""
import base64
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from types import SimpleNamespace
from unittest import mock
from . import metered_io as io


class MeteredIOTests(unittest.TestCase):
    def setUp(self):
        self.budget=mock.Mock();self.budget.start_operation.return_value="token"
        self.config=dict(remote_root="/mnt/beegfs/home/jaguir26/approved",user="jaguir26",host="hb.ucsc.edu")
        patch=mock.patch.object(io.ctl,"ssh",return_value=["ssh","-T","jaguir26@hb.ucsc.edu"])
        patch.start();self.addCleanup(patch.stop)

    def result(self,argv,mode="COMMAND",rc=0,CPU=.05,stdout="answer\n",stderr=""):
        value=dict(schema=io.SCHEMA,argv=argv,mode=mode,returncode=rc,
            stdout_b64=base64.b64encode(stdout.encode()).decode(),stderr_b64=base64.b64encode(stderr.encode()).decode(),
            CPU_seconds_observed_before_final_receipt=CPU,final_receipt_CPU_included_in_reserved_upper_bound=True)
        return SimpleNamespace(returncode=0,stdout=json.dumps(value),stderr="")

    def test_metadata_is_charged_before_IO_and_preserves_stdout(self):
        order=[]
        self.budget.start_operation.side_effect=lambda *x:(order.append("charged") or "token")
        def run(*x,**kw):
            order.append("I/O");self.assertEqual(kw["cpu"],1);compile(kw["stdin"],"<remote>","exec")
            return self.result(["squeue","-h"]),.02
        with mock.patch.object(io,"_run",side_effect=run):
            self.assertEqual(io.remote(self.config,["squeue","-h"],self.budget,"key"),"answer\n")
        self.assertEqual(order,["charged","I/O"])
        self.budget.finish_operation.assert_called_once_with("key","token",local_CPU=.02,remote_CPU=.05,outcome="COMPLETE")

    def test_command_failure_retains_remote_CPU_and_stderr_receipt(self):
        with mock.patch.object(io,"_run",return_value=(self.result(["sacct"],rc=1,stderr="denied"),.01)):
            with self.assertRaises(io.MeteredIOError) as caught:io.remote(self.config,["sacct"],self.budget,"key")
        self.assertEqual(caught.exception.receipt["stderr"],"denied")
        self.assertEqual(self.budget.finish_operation.call_args.kwargs["remote_CPU"],.05)

    def test_disconnect_or_tampered_receipt_never_assumes_remote_CPU_zero(self):
        for outcome in (SimpleNamespace(returncode=255,stdout="",stderr="disconnect"),
                        self.result(["different-job"]),SimpleNamespace(returncode=0,stdout="{}",stderr="")):
            self.budget.reset_mock();self.budget.start_operation.return_value="token"
            with mock.patch.object(io,"_run",return_value=(outcome,.01)),self.assertRaises(io.MeteredIOError):
                io.remote(self.config,["squeue"],self.budget,"key")
            self.assertIsNone(self.budget.finish_operation.call_args.kwargs["remote_CPU"])

    def test_watch_uses_one_prepriced_slot_and_bounded_source(self):
        with mock.patch.object(io,"_run",return_value=(self.result([],mode="WATCH",CPU=.1,stdout='{"ready":true}\n'),.03)):
            value=io.watch(self.config,"print('{\"ready\":true}')",self.budget,"key",timeout=60)
        self.assertIn("ready",value);self.budget.start_operation.assert_called_once_with("key","ready_watch")
        with self.assertRaises(ValueError):io.watch(self.config,"x"*65537,self.budget,"key",timeout=60)

    def test_transfer_receipt_fetch_is_in_same_finite5local6remote_price(self):
        calls=[]
        def run(argv,**kw):
            calls.append((argv,kw))
            if argv[0]=="rsync":return SimpleNamespace(returncode=0,stdout="",stderr=""),.1
            return SimpleNamespace(returncode=0,stdout=json.dumps(dict(schema="r157_rsync_remote_CPU_receipt_v1",
                returncode=0,CPU_seconds_observed_before_final_receipt=.2,
                final_receipt_CPU_included_in_reserved_upper_bound=True)),stderr=""),.1
        with mock.patch.object(io,"_run",side_effect=run),mock.patch.object(io,"_children_cpu",side_effect=[0,.2]):
            io.transfer(self.config,"/local/release",self.config["remote_root"]+"/release",self.budget,"key")
        self.assertEqual(len(calls),2);self.assertEqual(calls[0][1]["cpu"],3);self.assertEqual(calls[1][1]["cpu"],1)
        self.assertIn("--no-links",calls[0][0]);self.assertIn(".r157-control-CPU/",calls[1][1]["stdin"])
        self.budget.finish_operation.assert_called_once_with("key","token",local_CPU=.2,remote_CPU=1.2,outcome="COMPLETE")

    def test_transfer_scope_escape_and_missing_receipt_block(self):
        with self.assertRaises(ValueError):io.transfer(self.config,"/local","/unapproved",self.budget,"key")
        self.assertIsNone(self.budget.finish_operation.call_args.kwargs["remote_CPU"])
        with mock.patch.object(io,"_run",side_effect=[(SimpleNamespace(returncode=0,stdout="",stderr=""),.1),
                (SimpleNamespace(returncode=255,stdout="",stderr="lost"),.1)]),self.assertRaises(io.MeteredIOError):
            io.transfer(self.config,"/local",self.config["remote_root"]+"/release",self.budget,"key")
        self.assertIsNone(self.budget.finish_operation.call_args.kwargs["remote_CPU"])

    @unittest.skipUnless(Path('/usr/bin/rsync').is_file(),"local rsync unavailable")
    def test_actual_local_wrapper_can_lower_child4_under_parent_soft1_hard5(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"receipt.json"
            result=subprocess.run(['/usr/bin/python3','-B','-c',io._rsync_wrapper(str(path)),'--version'],
                text=True,capture_output=True,timeout=10)
            self.assertEqual(result.returncode,0,result.stderr)
            value=json.loads(path.read_text())
            self.assertEqual(value['returncode'],0)
            self.assertLess(value['CPU_seconds_observed_before_final_receipt'],5)


if __name__=='__main__':unittest.main()
