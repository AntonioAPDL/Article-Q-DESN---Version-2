#!/usr/bin/env python3
"""Regression tests for the frozen PriceFM R139 cohort closeout."""

from __future__ import annotations

import csv
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/474_closeout_pricefm_stage_r139_cohort_diagnostics.py"
SPEC = importlib.util.spec_from_file_location("r139_closeout", SCRIPT)
assert SPEC and SPEC.loader
R139 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R139)


def dump_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def dump_csv(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def seal(base: Path, artifacts: list[str], metadata: dict[str, object]) -> None:
    dump_json(
        base / "completed_evidence.json",
        {
            "artifacts": {name: R139.sha256_file(base / name) for name in artifacts},
            "metadata": metadata,
        },
    )


class R139CloseoutTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.quantiles = np.array([0.1, 0.25, 0.45, 0.5, 0.55, 0.75, 0.9])
        self.operators = ["cdf_pool_clipped", "normal_driver"]
        self.r137_head = "1" * 40
        self.r138_head = "2" * 40
        self.regions = ["AA", "BB", "CC", "DD"]
        self.config = self.root / "config.json"
        dump_json(
            self.config,
            {
                "schema_version": "test_r139_v1",
                "run_tag": "test_r139",
                "quantiles": self.quantiles.tolist(),
                "forecast_horizon": 96,
                "horizon_blocks": [
                    {"label": "h01_24", "start": 1, "end": 24},
                    {"label": "h25_48", "start": 25, "end": 48},
                    {"label": "h49_72", "start": 49, "end": 72},
                    {"label": "h73_96", "start": 73, "end": 96},
                ],
                "operators": self.operators,
                "primary_operator": "cdf_pool_clipped",
                "r137": {
                    "regions": self.regions,
                    "source_branch": "test/r137",
                    "source_head": self.r137_head,
                    "terminal_status": "R137_REGION_COMPLETE_NOT_PROMOTED",
                    "expected_completed_tasks": 6,
                    "expected_origins_by_fold": {"1": 2, "2": 2, "3": 2},
                },
                "r138_negative_control": {
                    "region": "NEG",
                    "source_branch": "test/r138",
                    "source_head": self.r138_head,
                    "terminal_status": "R138_DK1_COMPLETE_NOT_PROMOTED",
                    "expected_completed_tasks": 6,
                    "expected_origins_by_fold": {"1": 2, "2": 2, "3": 2},
                },
                "decision_contract": {"primary_goal": "beat_authority"},
            },
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def make_campaign(self, region: str, stage: str, model_bias: float = 0.0) -> Path:
        root = self.root / f"campaign_{region}"
        expected = R139.read_json(self.config)["r137" if stage == "r137" else "r138_negative_control"]
        dump_json(
            root / "terminal.json",
            {
                "status": expected["terminal_status"],
                "source": {"branch": expected["source_branch"], "head": expected["source_head"]},
            },
        )
        dump_json(
            root / "progress.json",
            {"completed": 6, "active": 0, "pending": 0, "failures": []},
        )
        fold_rows: list[dict[str, object]] = []
        offsets = np.array([-4.0, -2.0, -0.5, 0.0, 0.5, 2.0, 4.0])
        for fold in (1, 2, 3):
            truth = np.arange(192, dtype=float).reshape(2, 96) / 20.0 + fold
            primary = truth[..., None] + offsets + model_bias
            driver = truth[..., None] + offsets * 1.1 + model_bias
            predictions = {
                "cdf_pool_clipped": primary,
                "normal_driver": driver,
                "truth": truth,
                "anchors_ns": np.array([fold * 10, fold * 10 + 1], dtype=np.int64) * R139.NS_PER_HOUR,
                "positions": np.array([0, 1], dtype=np.int64),
            }
            forecast = root / "tasks_done" / f"{region}_fold{fold}_forecast000"
            forecast.mkdir(parents=True)
            np.savez(forecast / "predictions.npz", **predictions)
            dump_json(forecast / "result.json", {"certified": True})
            seal(
                forecast,
                ["predictions.npz", "result.json"],
                {"source_head": expected["source_head"], "certified": True},
            )
            design = root / "tasks_done" / f"{region}_fold{fold}_design"
            (design / "design").mkdir(parents=True)
            np.asarray(truth, dtype="<f8").tofile(design / "design/y.bin")
            dump_json(
                design / "design/scaler.json",
                {"training_origin_count": 2, "price_mean": 0.0, "price_scale": 1.0},
            )
            seal(
                design,
                ["design/y.bin", "design/scaler.json"],
                {"source_head": expected["source_head"], "certified": True},
            )
            for operator, values in (("cdf_pool_clipped", primary), ("normal_driver", driver)):
                metrics = R139.metric_record(truth, values, self.quantiles)
                fold_rows.append({
                    "region": region,
                    "fold": fold,
                    "operator": operator,
                    "AQL": metrics["AQL"],
                    "median_MAE": metrics["median_MAE"],
                    "coverage_80": metrics["coverage_80"],
                    "width_80": metrics["width_80"],
                    "exceedance": json.dumps(metrics["exceedance"]),
                    "qdesn_AQL": metrics["AQL"] + 1.0,
                    "pricefm_AQL": metrics["AQL"] - 0.2,
                    "operational_pricefm_AQL": metrics["AQL"] - 0.4,
                })
        closeout = root / "closeout"
        dump_csv(closeout / "fold_comparison.csv", fold_rows)
        seal(
            closeout,
            ["fold_comparison.csv"],
            {"source": {"branch": expected["source_branch"], "head": expected["source_head"]}},
        )
        return root

    def test_pinball_metric_algebra(self) -> None:
        truth = np.array([0.0, 2.0])
        prediction = np.array([[-1.0, 0.0, 1.0], [1.0, 2.0, 3.0]])
        quantiles = np.array([0.1, 0.5, 0.9])
        losses = R139.pinball_loss(truth, prediction, quantiles)
        expected = np.array([[0.1, 0.0, 0.1], [0.1, 0.0, 0.1]])
        np.testing.assert_allclose(losses, expected)

    def test_manifest_rejects_tampering(self) -> None:
        base = self.root / "sealed"
        base.mkdir()
        (base / "value.txt").write_text("original", encoding="utf-8")
        seal(base, ["value.txt"], {})
        R139.verify_artifact_manifest(base, base / "completed_evidence.json")
        (base / "value.txt").write_text("changed", encoding="utf-8")
        with self.assertRaises(R139.EvidenceError):
            R139.verify_artifact_manifest(base, base / "completed_evidence.json")

    def test_region_reconstructs_and_matches_frozen_metrics(self) -> None:
        campaign = self.make_campaign("AA", "r137")
        output = self.root / "packet_AA"
        R139.run_region(self.config, "r137", "AA", campaign, output)
        terminal = R139.read_json(output / "terminal.json")
        self.assertEqual(terminal["status"], "R139_REGION_PACKET_COMPLETE")
        self.assertTrue(terminal["frozen_metrics_reproduced"])
        self.assertEqual(len(R139.read_csv(output / "horizon_metrics.csv")), 3 * 2 * 96)
        R139.verify_region_packet(output)

    def test_aggregate_requires_exact_cohort_and_excludes_negative_control(self) -> None:
        packets: list[str] = []
        for region in self.regions:
            campaign = self.make_campaign(region, "r137")
            packet = self.root / f"packet_{region}"
            R139.run_region(self.config, "r137", region, campaign, packet)
            packets.append(f"{region}={packet}")
        negative_campaign = self.make_campaign("NEG", "r138", model_bias=2.0)
        negative_packet = self.root / "packet_NEG"
        R139.run_region(self.config, "r138", "NEG", negative_campaign, negative_packet)
        with self.assertRaises(R139.EvidenceError):
            R139.run_aggregate(self.config, packets[:-1], negative_packet, self.root / "bad_aggregate")
        output = self.root / "aggregate"
        R139.run_aggregate(self.config, packets, negative_packet, output)
        decision = R139.read_json(output / "decision.json")
        self.assertEqual(decision["decision"], "PROMISING_FOR_FROZEN_PROSPECTIVE_ROLLOUT")
        self.assertTrue(decision["negative_control"]["excluded_from_cohort"])
        self.assertFalse(decision["authority_replaced"])
        manifest = R139.read_json(output / "source_manifest.json")
        self.assertTrue(manifest["r138_excluded_from_r137_aggregate"])
        R139.verify_artifact_manifest(output, output / "completed_evidence.json")


if __name__ == "__main__":
    unittest.main()
