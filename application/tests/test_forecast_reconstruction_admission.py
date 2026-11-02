#!/usr/bin/env python3.11
"""Synthetic metadata only; no fit/forecast input, SSH, scheduler or controller."""
from __future__ import annotations
import copy
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location("admission",ROOT/"scripts/check_forecast_reconstruction_admission.py")
gate=importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
NOW=dt.datetime(2030,1,1,tzinfo=dt.timezone.utc)


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix="reconstruction-cost-test-")
        self.root=Path(self.tmp.name)
        self.source=dict(source_commit="a"*40,source_tree="b"*40,
                         source_manifest_sha256="c"*64,target_sha256="d"*64)
        self.evidence={role:self.pin(role+".json",json.dumps({"test_role":role}).encode())
                       for role in ("precision","native_parity","production_source_smoke")}
        registry=self.pin("registry.csv",
            b"stratum,member_count,adapter,empirical_measure\nAL,100,mq,native\nexAL,200,mq,native\n")
        self.data=dict(schema_version="forecast_reconstruction_cost_gate_v1",
            allow_refit=False,allow_launch=False,identity=self.source,
            expires_utc="2031-01-01T00:00:00Z",scope="MQ",stratum_registry=registry,
            expected_members=300,benchmarks=[],contingency_multiplier=1.25,
            overhead=dict(cpu_seconds=10,retained_bytes=1000),
            budget=dict(cpu_seconds=10000,retained_bytes=100000,
                        calendar_seconds=10000),hosts=[])
        self.benchmarks={}
        for label in ("AL","exAL"):
            item=dict(schema_version="forecast_reconstruction_benchmark_v1",stratum=label,
                identity=self.source,registry_sha256=registry["sha256"],
                measurement_kind="bounded_actual_execution",
                precision_gate="PASS",native_parity_gate="PASS",source_closure_gate="PASS",
                evidence=self.evidence,measured_members=10,cpu_seconds=20,wall_seconds=25,
                artifact_bytes=1000,log_and_admin_bytes=50,peak_rss_bytes=1024)
            self.benchmarks[label]=item
            self.data["benchmarks"].append(self.pin(label+".json",json.dumps(item).encode()))
        self.data["hosts"]=[dict(host="muscat",new_scope_physical_cores=2,
            free_disk_bytes=1000000,other_reserved_bytes=1000,
            max_staged_and_pending_bytes=10000,disk_floor_bytes=100000,
            final_retained_allocation_bytes=50000,
            available_ram_after_other_reservations_bytes=10000,
            new_scope_grant_verified=True,method_source_runtime_verified=True,
            return_and_accounting_verified=True,
            grant_receipt=self.pin("grant.json",b"{}"),
            runtime_receipt=self.pin("runtime.json",b"{}"),
            return_and_accounting_receipt=self.pin("accounting.json",b"{}"))]

    def tearDown(self):
        self.tmp.cleanup()

    def pin(self,name,data):
        path=self.root/name
        path.write_bytes(data)
        return dict(path=str(path),bytes=len(data),sha256=hashlib.sha256(data).hexdigest())

    def assess(self,data=None):
        return gate.assess(data or self.data,now=NOW)

    def test_complete_pricing_is_not_a_launch_or_eta(self):
        got=self.assess()
        self.assertEqual(got["members"],300)
        self.assertEqual(got["strata"],2)
        self.assertEqual(got["priced_cpu_seconds"],762.5)
        self.assertEqual(got["priced_retained_bytes"],40625)
        self.assertEqual(got["optimistic_calendar_floor_seconds"],468.75)
        self.assertFalse(got["allow_launch"])
        self.assertFalse(got["allow_refit"])
        self.assertFalse(got["publication_authorized"])
        self.assertTrue(got["calendar_floor_is_not_eta"])
        self.assertFalse(got["external_receipt_semantics_validated_here"])
        self.assertTrue(got["host_and_numerical_admission_still_required"])

    def test_incomplete_scope_or_cost_cannot_pass(self):
        changes=[
            ("allow_refit",True),("allow_launch",True),("scope","all"),
            ("expected_members",299),("expected_members",300.0),
            ("contingency_multiplier",1.0),("contingency_multiplier",float("inf")),
            ("expires_utc","2029-01-01T00:00:00Z"),("expires_utc","2031-01-01T00:00:00"),
            ("benchmarks",self.data["benchmarks"][:1]),
            ("benchmarks",self.data["benchmarks"]*2),("hosts",[])]
        for key,value in changes:
            with self.subTest(key=key,value=value):
                data=copy.deepcopy(self.data);data[key]=value
                with self.assertRaises(gate.AdmissionError):self.assess(data)

    def test_all_resource_budgets_matter(self):
        for key,value in (("cpu_seconds",700),("retained_bytes",40000),("calendar_seconds",400),
                          ("cpu_seconds",True)):
            with self.subTest(key=key):
                data=copy.deepcopy(self.data);data["budget"][key]=value
                with self.assertRaises(gate.AdmissionError):self.assess(data)

    def test_other_lanes_disk_and_actual_runtime_grants_are_not_borrowed(self):
        changes=[
            ("new_scope_physical_cores",0),("other_reserved_bytes",950000),
            ("final_retained_allocation_bytes",40000),
            ("final_retained_allocation_bytes",950000),
            ("available_ram_after_other_reservations_bytes",10),
            ("new_scope_grant_verified",False),("method_source_runtime_verified",False),
            ("return_and_accounting_verified",False)]
        for key,value in changes:
            with self.subTest(key=key):
                data=copy.deepcopy(self.data);data["hosts"][0][key]=value
                with self.assertRaises(gate.AdmissionError):self.assess(data)
        data=copy.deepcopy(self.data);data["hosts"]*=2
        with self.assertRaises(gate.AdmissionError):self.assess(data)

    def test_every_benchmark_is_source_bound_and_measured(self):
        changes=[
            ("measurement_kind","extrapolated_from_single_unit"),
            ("precision_gate","REVIEW"),("native_parity_gate","REVIEW"),
            ("source_closure_gate","REVIEW"),("measured_members",0),
            ("cpu_seconds",0),("wall_seconds",float("nan")),("artifact_bytes",-1),
            ("registry_sha256","0"*64),("identity",dict(self.source,source_commit="f"*40))]
        for i,(key,value) in enumerate(changes):
            with self.subTest(key=key):
                data=copy.deepcopy(self.data)
                benchmark=copy.deepcopy(self.benchmarks["AL"]);benchmark[key]=value
                data["benchmarks"][0]=self.pin("changed"+str(i)+".json",json.dumps(benchmark).encode())
                with self.assertRaises(gate.AdmissionError):self.assess(data)

    def test_hash_symlink_and_missing_evidence_rejected(self):
        data=copy.deepcopy(self.data);data["benchmarks"][0]["sha256"]="0"*64
        with self.assertRaises(gate.AdmissionError):self.assess(data)
        data=copy.deepcopy(self.data)
        linked=self.root/"link.csv";linked.symlink_to(data["stratum_registry"]["path"])
        data["stratum_registry"]["path"]=str(linked)
        with self.assertRaises(gate.AdmissionError):self.assess(data)
        data=copy.deepcopy(self.data)
        benchmark=copy.deepcopy(self.benchmarks["AL"]);benchmark["evidence"].pop("precision")
        data["benchmarks"][0]=self.pin("missing-evidence.json",json.dumps(benchmark).encode())
        with self.assertRaises(gate.AdmissionError):self.assess(data)

    def test_duplicate_metadata_fields_rejected(self):
        with self.assertRaises(gate.AdmissionError):
            gate.read_json(b'{"allow_launch":false,"allow_launch":true}')
        data=copy.deepcopy(self.data)
        data["stratum_registry"]=self.pin("duplicate-columns.csv",
            b"stratum,stratum,member_count,adapter,empirical_measure\nAL,AL,300,mq,native\n")
        with self.assertRaises(gate.AdmissionError):self.assess(data)


if __name__=="__main__":
    unittest.main()
