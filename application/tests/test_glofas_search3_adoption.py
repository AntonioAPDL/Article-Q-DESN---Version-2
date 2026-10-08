from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "search3_adoption", ROOT / "application/scripts/434_finalize_glofas_search3_adoption.py"
)
ADOPTION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ADOPTION)


def row(target, candidate, score, eligible, incumbent=False, worst=0.3):
    return {
        "target": target,
        "candidate_id": candidate,
        "confirmation_crps_4dp": f"{score:.4f}",
        "adoption_eligible": eligible,
        "is_incumbent": incumbent,
        "worst_fold_crps": worst,
        "mean_secondary_crps": score,
        "n_state_features": 1000,
        "mean_runtime_seconds": 10,
    }


class Search3AdoptionTest(unittest.TestCase):
    def test_raw_leader_failing_gate_is_not_selected(self):
        decisions = [
            row("reference", "ref_inc", 0.14, True, incumbent=True),
            row("reference", "ref_bad", 0.10, False),
            row("reference", "ref_bad2", 0.11, False),
            row("discrepancy", "dis_inc", 0.12, True, incumbent=True),
            row("discrepancy", "dis_raw", 0.09, False),
            row("discrepancy", "dis_valid", 0.10, True),
        ]
        selected = ADOPTION.choose_adoptions(
            decisions,
            {"reference": "ref_inc", "discrepancy": "dis_inc"},
        )
        self.assertEqual(
            {item["target"]: item["candidate_id"] for item in selected},
            {"reference": "ref_inc", "discrepancy": "dis_valid"},
        )

    def test_ties_use_frozen_secondary_order(self):
        decisions = [
            row("reference", "ref_inc", 0.14, True, incumbent=True),
            row("reference", "ref_a", 0.10, True, worst=0.30),
            row("reference", "ref_b", 0.10, True, worst=0.25),
            row("discrepancy", "dis_inc", 0.12, True, incumbent=True),
        ]
        selected = ADOPTION.choose_adoptions(
            decisions,
            {"reference": "ref_inc", "discrepancy": "dis_inc"},
        )
        self.assertEqual(selected[0]["candidate_id"], "ref_b")
        self.assertEqual(selected[1]["candidate_id"], "dis_inc")

    def test_expected_decision_mismatch_fails_closed(self):
        decisions = [
            row("reference", "ref_inc", 0.14, True, incumbent=True),
            row("discrepancy", "dis_inc", 0.12, True, incumbent=True),
        ]
        with self.assertRaises(RuntimeError):
            ADOPTION.choose_adoptions(
                decisions,
                {"reference": "ref_inc", "discrepancy": "dis_inc"},
                {"reference": "unexpected", "discrepancy": "dis_inc"},
            )


if __name__ == "__main__":
    unittest.main()
