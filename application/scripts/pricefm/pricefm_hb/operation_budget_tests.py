"""Private metadata tests for prospective, nonrefundable control CPU meters."""
from pathlib import Path
import tempfile
import time
import unittest
from unittest import mock
from . import operation_budget as b, policy as p, registry as r


class OperationBudgetTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.now=time.time()
        patch=mock.patch.object(b,"owner");patch.start();self.addCleanup(patch.stop)
        self.store=self.create("INITIAL")

    def create(self,kind):
        auth=dict(status="ROOT_ADMITTED_R157_CONTROL_CPU_SCOPE",controller=b.OWNER,
            scope_id="control-"+kind,kind=kind,CPU_ceiling=720 if kind=="INITIAL" else 1800,
            nonrenewing=True,expires_epoch=self.now+3600)
        path=self.root/(kind+"-auth.json");r.write(path,auth)
        return b.OperationBudget.create(self.root/(kind+"-budget.json"),scope_id=auth["scope_id"],
            authorization_pin=p.pin(path),expires_epoch=auth["expires_epoch"],kind=kind,now=self.now)

    def test_initial_claim_and_publication_reservations_sum_exactly720(self):
        for key in ("TEST","FI","DK2"):self.store.reserve_claim(key)
        self.store.reserve_publication()
        state=self.store.snapshot()
        self.assertEqual(state["claim_reserved_CPU"]+state["publication_reserved_CPU"],720)
        self.assertEqual(state["claims"]["TEST"]["priced_command_and_parent_maximum_CPU"],217)
        with self.assertRaises(b.BudgetError):self.store.reserve_claim("fourth")
        with self.assertRaises(b.BudgetError):self.store.reserve_publication()

    def test_failed_operation_and_small_actual_cost_do_not_refund(self):
        self.store.reserve_claim("TEST")
        token=self.store.start_operation("TEST","metadata")
        self.assertEqual(self.store.snapshot()["claims"]["TEST"]["counts"]["metadata"],1)
        self.store.finish_operation("TEST",token,local_CPU=.01,remote_CPU=.02,outcome="FAILED")
        claim=self.store.snapshot()["claims"]["TEST"]
        self.assertEqual(claim["reserved_CPU"],230);self.assertEqual(claim["operation_reserved_CPU"],3)
        with self.assertRaises(b.BudgetError):self.store.finish_operation("TEST",token,local_CPU=0,remote_CPU=0)
        with self.assertRaises(b.BudgetError):self.store.reserve_claim("TEST")

    def test_interrupted_charged_operation_blocks_more_IO_until_reconciled(self):
        self.store.reserve_claim("TEST");token=self.store.start_operation("TEST","transfer")
        with self.assertRaises(b.BudgetError):self.store.start_operation("TEST","metadata")
        self.store.finish_operation("TEST",token,local_CPU=1,remote_CPU=2)
        self.store.start_operation("TEST","metadata")

    def test_unknown_or_excess_CPU_is_persisted_and_blocks_future_operations(self):
        for key,local,remote in (("unknown",0,None),("local-excess",2,0),("remote-excess",0,3)):
            self.store.reserve_claim(key);token=self.store.start_operation(key,"metadata")
            with self.assertRaises(b.BudgetError):self.store.finish_operation(key,token,local_CPU=local,remote_CPU=remote)
            self.assertTrue(self.store.snapshot()["claims"][key]["violations"])
            with self.assertRaises(b.BudgetError):self.store.start_operation(key,"metadata")

    def test_per_claim_operation_counts_are_finite_even_with_zero_actual_CPU(self):
        self.store.reserve_claim("TEST")
        for unused in range(20):
            token=self.store.start_operation("TEST","metadata")
            self.store.finish_operation("TEST",token,local_CPU=0,remote_CPU=0)
        with self.assertRaises(b.BudgetError):self.store.start_operation("TEST","metadata")
        token=self.store.start_operation("TEST","ready_watch")
        self.store.finish_operation("TEST",token,local_CPU=0,remote_CPU=0)
        with self.assertRaises(b.BudgetError):self.store.start_operation("TEST","ready_watch")

    def test_parent_rusage_is_monotonic_across_process_restarts(self):
        self.store.reserve_claim("TEST")
        identity=dict(pid=10,start_ticks=100,boot_id="boot-fixture")
        self.assertEqual(self.store.checkpoint_parent("TEST",identity,3),3)
        self.assertEqual(self.store.checkpoint_parent("TEST",identity,5),5)
        with self.assertRaises(b.BudgetError):self.store.checkpoint_parent("TEST",identity,4)
        other=dict(identity,pid=11,start_ticks=200)
        self.assertEqual(self.store.checkpoint_parent("TEST",other,2),7)
        with self.assertRaises(b.BudgetError):self.store.checkpoint_parent("TEST",other,60)
        with self.assertRaises(b.BudgetError):self.store.start_operation("TEST","metadata")

    def test_old_scope_clock_and_initial_price_cannot_be_reset(self):
        with self.assertRaises(FileExistsError):self.create("INITIAL")
        with self.assertRaises(b.BudgetError):self.store.reserve_claim("TEST",reservation=229)
        with self.assertRaises(b.BudgetError):self.store.reserve_claim("TEST",parent_CPU_cap=61)
        with self.assertRaises(b.BudgetError):self.store.snapshot(now=self.now+3601)

    def test_interrupted_parent_slices_cannot_refund_or_renew_the60CPU_cap(self):
        self.store.reserve_claim("TEST")
        for pid in range(10,17):
            identity=dict(pid=pid,start_ticks=pid*100,boot_id="boot-fixture")
            self.store.reserve_parent_slice("TEST",identity,8)
            # Simulated SIGKILL: no checkpoint or close is ever delivered.
        self.assertEqual(self.store.snapshot()["claims"]["TEST"]["parent_reserved_CPU"],56)
        with self.assertRaises(b.BudgetError):
            self.store.reserve_parent_slice("TEST",dict(pid=20,start_ticks=2000,boot_id="boot-fixture"),8)

    def test_parent_slice_is_one_use_and_measurement_cannot_exceed_own_slice(self):
        self.store.reserve_claim("TEST");identity=dict(pid=10,start_ticks=100,boot_id="boot-fixture")
        self.store.reserve_parent_slice("TEST",identity,8)
        self.store.close_parent_slice("TEST",identity,1)
        self.assertEqual(self.store.snapshot()["claims"]["TEST"]["parent_reserved_CPU"],8)
        with self.assertRaises(b.BudgetError):self.store.reserve_parent_slice("TEST",identity,8)
        other=dict(identity,pid=11,start_ticks=200)
        with self.assertRaises(b.BudgetError):self.store.checkpoint_parent("TEST",other,1)
        self.store.reserve_parent_slice("TEST",other,8)
        with self.assertRaises(b.BudgetError):self.store.checkpoint_parent("TEST",other,9)

    def test_PREFIX_needs_complete_separately_admitted_control_price(self):
        store=self.create("PREFIX")
        limits=dict(metadata=1,transfer=1,ready_watch=1,admission_refresh=0)
        price=dict(status="ROOT_ADMITTED_EXACT_PREFIX_CONTROL_PRICE",controller=b.OWNER,scope_id="control-PREFIX",
            claim_key="FI-component",reservation_CPU=30,operation_limits=limits,parent_CPU_cap=5)
        path=self.root/"prefix-price.json";r.write(path,price)
        store.reserve_claim("FI-component",reservation=30,limits=limits,parent_CPU_cap=5,price_pin=p.pin(path))
        self.assertEqual(store.snapshot()["CPU_ceiling"],1800)
        price["claim_key"]="FI-too-small";price["reservation_CPU"]=29;r.write(path,price)
        with self.assertRaises(b.BudgetError):
            store.reserve_claim("FI-too-small",reservation=29,limits=limits,parent_CPU_cap=5,price_pin=p.pin(path))
        self.assertEqual(len(store.snapshot()["claims"]),1)

    def test_authorization_hash_and_controller_identity_are_required(self):
        path=self.root/"INITIAL-auth.json";value=r.read(path);value["controller"]="unknown";r.write(path,value)
        with self.assertRaises(b.BudgetError):
            b.OperationBudget.create(self.root/"other.json",scope_id="control-INITIAL",authorization_pin=p.pin(path),
                expires_epoch=self.now+3600,now=self.now)


if __name__=="__main__":unittest.main()
