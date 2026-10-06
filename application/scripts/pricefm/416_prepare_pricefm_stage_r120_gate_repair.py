#!/usr/bin/env python3
"""Record the audited R120 convergence-gate repair without rewriting provenance."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess

import pandas as pd

from pricefm_common import sha256_file, write_json


CONTROLLER = "414_run_pricefm_stage_r120_explicit_lag_search.py"
ATOM = "415_fit_pricefm_stage_r120_quantile_atom.R"
TAG = "pricefm_stage_r120_bg_explicit_lag_all_layer_search_20260925"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--prep-dir", type=Path, required=True)
    value.add_argument("--campaign-root", type=Path, required=True)
    value.add_argument("--code-root", type=Path, required=True)
    return value


def _terminal(campaign: Path, variant: str, family: str, tau: float) -> dict:
    path = campaign / f"variant_{variant}/full_folds/fold=1/quantiles/{family}/tau={tau:.2f}/terminal.json"
    if not path.is_file():
        raise FileNotFoundError(path)
    return json.loads(path.read_text())


def prepare(prep: Path, campaign: Path, code: Path) -> dict:
    prep = prep.resolve(); campaign = campaign.resolve(); code = code.resolve()
    sources = pd.read_csv(prep / "source_manifest.csv")
    selected = sources[sources.path.str.endswith(CONTROLLER)]
    atom = sources[sources.path.str.endswith(ATOM)]
    if len(selected) != 1 or len(atom) != 1:
        raise RuntimeError("R120 frozen source identities are incomplete")
    controller_path = code / "application/scripts/pricefm" / CONTROLLER
    atom_path = code / "application/scripts/pricefm" / ATOM
    repair_script = Path(__file__).resolve()
    if sha256_file(atom_path) != str(atom.iloc[0].sha256):
        raise RuntimeError("R120 atom implementation changed; gate-only recovery is invalid")
    pure_al = [_terminal(campaign, "pure", "al", tau) for tau in (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)]
    pure_exal = [_terminal(campaign, "pure", "exal", tau) for tau in (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)]
    extended_median = _terminal(campaign, "extended", "al", 0.50)
    checks = {
        "pure_al_complete_eligible": all(value.get("numerically_eligible") is True for value in pure_al),
        "pure_exal_contains_ineligible": any(value.get("numerically_eligible") is not True for value in pure_exal),
        "extended_median_ineligible": extended_median.get("numerically_eligible") is False,
        "campaign_not_terminal": not (campaign / "campaign_terminal.json").exists(),
    }
    if not all(checks.values()):
        raise RuntimeError(f"R120 gate-repair evidence changed: {checks}")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=code, text=True).strip()
    value = {
        "status": "prepared_r120_quantile_gate_repair",
        "tag": TAG,
        "campaign_root": str(campaign),
        "source_manifest_sha256": sha256_file(prep / "source_manifest.csv"),
        "controller_path": str(controller_path.resolve()),
        "original_controller_sha256": str(selected.iloc[0].sha256),
        "repaired_controller_sha256": sha256_file(controller_path),
        "quantile_atom_path": str(atom_path.resolve()),
        "quantile_atom_sha256": sha256_file(atom_path),
        "repair_script_path": str(repair_script),
        "repair_script_sha256": sha256_file(repair_script),
        "repaired_git_head": head,
        "evidence_checks": checks,
        "repair_scope": "controller eligibility, whole-family forecast gate, resumable continuation",
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    write_json(prep / "gate_repair_manifest.json", value)
    return value


def main() -> int:
    args = parser().parse_args()
    print(json.dumps(prepare(args.prep_dir, args.campaign_root, args.code_root), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
