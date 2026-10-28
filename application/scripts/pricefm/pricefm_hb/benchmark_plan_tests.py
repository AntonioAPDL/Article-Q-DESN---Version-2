"""Stdlib/mocked verification of unadmitted cost-panel preparation."""
from __future__ import annotations

import collections
import copy
import datetime as dt
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from . import benchmark_plan as b
from .fixture import digest


def metadata(study="FI"):
    region = "FI" if study == "FI" else "DK_2"
    ids = ["C0", "C0_alt", *b.BENCHMARK_PACKAGES[study][1:]]
    ids += ["package" + str(i) for i in range(b.COUNTS[study]["packages"] - len(ids))]
    packages = [dict(package_id=p, candidate_id="candidate_C0" if p in ("C0", "C0_alt") else "candidate_" + p, p=385) for p in ids]
    config = dict(region=region, control="C0", benchmark_D_packages=b.BENCHMARK_PACKAGES[study],
        benchmark_S_packages=b.BENCHMARK_PACKAGES[study], benchmark_D_repeats=3, benchmark_S_repeats=1,
        benchmark_max_seconds=1200, chunk_origins=8, clock_offsets_steps=[0, 24, 48, 72], horizon_steps=96,
        paths=100, quantiles=[.1, .25, .45, .5, .55, .75, .9], AL_authorized=False,
        official_evaluation_authorized=False, promotion_authorized=False, test_used_for_selection=False)
    tasks = []
    for package in packages:
        for split in (1, 2, 3):
            positions = list(range(700 + 8 * split, 708 + 8 * split))
            stamps = [(dt.datetime(2023, 1, 1, tzinfo=dt.timezone.utc) + dt.timedelta(days=i)).isoformat() for i in range(8)]
            for mode, seed in (("D", 0), ("S", 0), ("S", 1), ("S", 2)):
                p = package["package_id"]
                tasks.append(dict(name=region + "_" + p + "_s" + str(split) + "_" + mode + "_seed" + str(seed),
                    package_id=p, candidate_id=package["candidate_id"], p=package["p"], split=split,
                    mode=mode, seed_index=seed, forecast_seed=2026101502, region=region,
                    clock_offsets_steps=[0, 24, 48, 72], daily_origin_positions=positions,
                    origin_timestamps={"0": stamps}, scientific_identity_sha256="science-" + p,
                    parent_task="parent-" + p + "-" + str(split), parent_fit="/logical/fit/" + p + "/" + str(split),
                    parent_seal_sha256="seal-" + p, parent_input_sha256={"/logical/fit.rds": "opaque"},
                    scaler_path="/logical/scaler.json", scaler_sha256="scaler", bank=dict(path="/logical/bank.npz", sha256="bank")))
    preparation = dict(source=dict(head=b.SOURCE_HEADS[study]), region=region, control="C0", packages=packages,
        tasks=tasks, test_opened=False, posterior_updated=False, new_model_fits=0)
    return config, preparation


class ScheduleTests(unittest.TestCase):
    def test_exact_18_call_order_and_zero_loss_serialization(self):
        config, prep = metadata()
        b.validate_metadata("FI", config, prep)
        calls = b.make_schedule("FI", config, prep)
        timed = [call for call in calls if call["kind"] == "timed_prediction"]
        self.assertEqual(collections.Counter(call["mode"] for call in timed), {"D": 12, "S": 4})
        self.assertEqual([call["sequence"] for call in calls if call["kind"] == "control_replay"], [2, 15])
        self.assertEqual([(calls[i]["mode"], calls[i]["package_id"], calls[i]["repetition"]) for i in (0, 2, 3, 13, 15)],
            [("D", "C0", 0), ("D", "C0", 1), ("D", "C0", 2), ("S", "C0", 0), ("S", b.BENCHMARK_PACKAGES["FI"][1], 0)])
        self.assertEqual(sum(call["cold_context_before_call"] for call in calls), 8)
        for call in timed:
            self.assertIs(call["serialization"]["compute_loss"], False)
            self.assertIs(call["serialization"]["zero_origin_AQL"], True)
            self.assertEqual(call["descriptor"]["stable_rng_origin_keys"], [p * 96 for p in call["descriptor"]["origin_positions"]])
            self.assertEqual((call["split"], call["seed_index"]), (3, 0))

    def test_both_canonical_regions_have_complete_all_parent_preflight(self):
        for study, expected in (("FI", 60), ("DK2", 63)):
            config, prep = metadata(study)
            b.validate_metadata(study, config, prep)
            parents = b.make_preflight(prep)
            self.assertEqual(len(parents), expected)
            self.assertEqual(len({(row["package_id"], row["split"]) for row in parents}), expected)
            self.assertTrue(all(row["covariance_bytes"] == 8 * 385 * 385 for row in parents))
            self.assertTrue(all(row["forecasts"] == 0 and row["included_in_whole_1200CPU_1200wall"] for row in parents))

    def test_changed_schedule_geometry_and_old_DK2_lineage_are_rejected(self):
        config, prep = metadata("DK2")
        prep["source"]["head"] = "older-smoke-source"
        with self.assertRaisesRegex(ValueError, "lineage"):
            b.validate_metadata("DK2", config, prep)
        config, prep = metadata()
        for change in (dict(benchmark_D_repeats=1), dict(benchmark_S_repeats=2), dict(horizon_steps=30), dict(paths=500), dict(AL_authorized=True)):
            with self.subTest(change=change), self.assertRaises(ValueError):
                b.validate_metadata("FI", {**config, **change}, prep)

    def test_subchunk_or_missing_parent_stops_planning(self):
        config, prep = metadata()
        selected = next(t for t in prep["tasks"] if t["package_id"] == "C0" and t["split"] == 3 and t["mode"] == "D")
        selected["daily_origin_positions"] = selected["daily_origin_positions"][:1]
        with self.assertRaisesRegex(ValueError, "eight-origin"):
            b.make_schedule("FI", config, prep)
        config, prep = metadata()
        prep["tasks"] = [t for t in prep["tasks"] if not (t["package_id"] == "C0" and t["split"] == 1 and t["mode"] == "D")]
        with self.assertRaises(KeyError):
            b.make_preflight(prep)


class InventoryTests(unittest.TestCase):
    def test_complete_allowlist_keeps_opaque_RDS_without_reading_binaries(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            files = {name: root / name for name in ("fit.rds", "beta_cov.bin", "bank.npz", "scaler.json", "parent.json", "config.json", "preparation.json")}
            for path in files.values():
                path.write_bytes(b"synthetic bytes")
            original_hashes = {str(files[name]): "declared-" + name for name in ("fit.rds", "beta_cov.bin", "bank.npz", "scaler.json")}
            prep = dict(source_sha256={}, input_sha256={str(files["fit.rds"]): original_hashes[str(files["fit.rds"])]},
                tasks=[dict(parent_input_sha256={str(files[name]): original_hashes[str(files[name])] for name in ("fit.rds", "beta_cov.bin")},
                    scaler_path=str(files["scaler.json"]), scaler_sha256=original_hashes[str(files["scaler.json"])])],
                banks={"training": dict(path=str(files["bank.npz"]), sha256=original_hashes[str(files["bank.npz"])])})
            config = dict(parent_preparation=str(files["parent.json"]), parent_preparation_sha256=digest(files["parent.json"]))
            def metadata_digest(path):
                if Path(path).suffix in (".rds", ".bin", ".npz"):
                    raise AssertionError("binary data read during metadata preparation")
                return digest(path)
            with patch.object(b, "SOURCE_PINS", {}), patch.object(b, "digest", side_effect=metadata_digest):
                assets = b.make_allowlist(files["config.json"], files["preparation.json"], config, prep)
            self.assertTrue(assets[str(files["fit.rds"])]["opaque_provenance"])
            self.assertEqual(assets[str(files["fit.rds"])]["sha256"], original_hashes[str(files["fit.rds"])])
            self.assertIn(str(files["beta_cov.bin"]), assets)
            self.assertIn(str(files["bank.npz"]), assets)
            summary = b.allowlist_summary(assets)
            self.assertFalse(summary["numerical_bytes_rehashed"])
            self.assertEqual(summary["bytes_staged"], 0)
            self.assertEqual(summary["extensions"][".rds"]["files"], 1)

    def test_conflicting_original_parent_digest_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fit.rds"
            path.write_bytes(b"opaque")
            prep = dict(source_sha256={}, input_sha256={str(path): "first"},
                tasks=[dict(parent_input_sha256={str(path): "different"})])
            with self.assertRaisesRegex(ValueError, "conflicts"):
                b.make_allowlist("unused", "unused", {}, prep)


class AdmissionTests(unittest.TestCase):
    def plan(self):
        config, prep = metadata()
        return dict(schema=b.SCHEMA, status="METADATA_PLAN_COMPLETE_BENCHMARK_NOT_ADMITTED", study="FI",
            resources=b.LIMITS, schedule=b.make_schedule("FI", config, prep),
            all_parent_preflight=b.make_preflight(prep), schedule_summary=dict(arithmetic_calls=18), inventory=dict(files=1),
            launch_manifest=dict(status="NOT_ADMITTED", actual_model_execution_authorized=False),
            adapter_feasibility=dict(status="COST_ONLY_RUNTIME_IMPLEMENTED_NOT_ADMITTED_NOT_SCIENTIFICALLY_QUALIFIED"))

    def test_sealed_dry_run_never_admits_or_executes_models(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.plan()
            path = b.write_plan(plan, directory)
            result = b.dry_run(path)
            self.assertEqual(result["status"], "DRY_RUN_VALID_PLAN_EXECUTION_NOT_ADMITTED")
            self.assertEqual(result["model_calls_executed"], 0)
            self.assertIs(result["controller_role_implemented"], True)
            self.assertIs(result["authority_issuer_implemented"], True)
            self.assertIs(result["new_authority_issued"], False)
            self.assertIs(result["execution_allowed"], False)
            self.assertIs(result["region_benchmark_executed"], False)
            self.assertNotIn("missing_new_controller_role_and_authority", result)
            commands = result["cost_controller_handoff"]["commands"]
            self.assertEqual([step["argv"][4] for step in commands],
                ["prepare-launch", "submit-held", "issue-authority", "release-job", "status", "collect"])
            self.assertIn("new_region_specific_1200CPU_1200wall_authority", result["required_gates"])
            with self.assertRaisesRegex(FileExistsError, "scope already exists"):
                b.write_plan(plan, directory)
            path.write_text(path.read_text() + "\n")
            with self.assertRaisesRegex(ValueError, "seal differs"):
                b.dry_run(path)

    def test_execution_gate_cannot_be_enabled_by_setting_plan_booleans(self):
        plan = self.plan()
        plan["launch_manifest"]["status"] = "ADMITTED"
        plan["launch_manifest"]["actual_model_execution_authorized"] = True
        with self.assertRaisesRegex(RuntimeError, "NOT_ADMITTED"):
            b.require_execution_admission(plan)

    def test_original_506_feasibility_is_source_only_and_honest(self):
        source = b.SOURCE_PINS["canonical506"][0]
        report = b.feasibility(source)
        self.assertEqual(report["status"], "COST_ONLY_RUNTIME_IMPLEMENTED_NOT_ADMITTED_NOT_SCIENTIFICALLY_QUALIFIED")
        self.assertFalse(report["unchanged_method_direct_execution_portable"])
        self.assertTrue(report["cost_controller_role_implemented"])
        self.assertTrue(report["cost_authority_issuer_implemented"])
        self.assertFalse(report["actual_region_cost_panel_executed"])
        self.assertNotIn("support in a new controller role", " ".join(report["remaining_gates"]))
        self.assertEqual(report["original_methods"]["benchmark"]["source_sha256"], b.SOURCE_PINS["canonical506"][1])
        self.assertEqual(set(report["original_methods"]), {"benchmark", "numeric_preflight", "predict", "legacy_control_replay"})


if __name__ == "__main__":
    unittest.main()
