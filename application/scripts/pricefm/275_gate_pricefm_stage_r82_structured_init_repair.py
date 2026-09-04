#!/usr/bin/env python3
"""Close out R82 diagnostics and gate only the 14 failed R76 exAL atoms."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil

import numpy as np
import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R77 = DATA / "authoritative/pricefm_stage_r77_exal_failure_atlas_20260904"
R80_GATE = DATA / "authoritative/pricefm_stage_r80_zero_freeze_repair_gate_20260904"
R82_GRID = DATA / "experiment_grids/pricefm_stage_r82_structured_init_diagnostics_20260904"
R82_RUNS = DATA / "runs/pricefm_stage_r82_structured_init_diagnostics_20260904"
OUTPUT = DATA / "authoritative/pricefm_stage_r82_structured_init_repair_gate_20260904"
REPAIR = (
    "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-"
    "plus-structured-plugin-init"
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r77-dir", type=Path, default=R77)
    p.add_argument("--r80-gate-dir", type=Path, default=R80_GATE)
    p.add_argument("--r82-grid-dir", type=Path, default=R82_GRID)
    p.add_argument("--r82-runs-dir", type=Path, default=R82_RUNS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--force", action="store_true")
    return p


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_control(path: Path) -> dict:
    terminal_path = path / "terminal.json"
    terminal = json.loads(terminal_path.read_text())
    if terminal.get("status") != "completed" or terminal.get("test_loaded") is not False:
        raise RuntimeError(f"R82 diagnostic did not complete under its firewall: {path}")
    trace = pd.read_csv(path / "vb_trace.csv")
    method = pd.read_csv(path / "method_summary.csv").iloc[0]
    parameter = pd.read_csv(path / "parameter_summary.csv").iloc[0]
    required = ["sigma", "gamma", "delta_state", "delta_sigma", "delta_gamma", "delta_s"]
    trace_finite = bool(np.isfinite(trace[required].to_numpy(dtype=float)).all())
    return {
        "task_id": terminal["task_id"],
        "case_id": terminal["case_id"],
        "region": terminal["region"],
        "fold": int(terminal["fold"]),
        "tau": float(terminal["tau"]),
        "iter": int(terminal["iter"]),
        "converged": bool(terminal["converged"]),
        "structured_updates": int(terminal["structured_updates"]),
        "trace_finite": trace_finite,
        "package_version": str(method.package_version),
        "package_repair": str(method.repair),
        "initial_beta_l2": float(parameter.al_init_beta_l2),
        "final_beta_l2": float(parameter.beta_l2),
        "beta_l2_ratio": float(parameter.beta_l2 / max(parameter.al_init_beta_l2, 1e-12)),
        "initial_sigma": float(parameter.al_init_sigma),
        "final_sigma": float(parameter.sigma),
        "max_sigma": float(trace.sigma.max()),
        "max_sigma_ratio": float(trace.sigma.max() / max(parameter.al_init_sigma, 1e-12)),
        "max_abs_gamma": float(trace.gamma.abs().max()),
        "first_delta_state": float(trace.delta_state.iloc[0]),
        "tail_max_delta_state": float(trace.tail(10).delta_state.max()),
        "tail_max_delta_sigma": float(trace.tail(10).delta_sigma.max()),
        "terminal_sha256": sha256(terminal_path),
        "trace_sha256": sha256(path / "vb_trace.csv"),
        "output_dir": str(path.resolve()),
    }


def run(args: argparse.Namespace) -> dict:
    r77 = json.loads((args.r77_dir / "summary.json").read_text())
    if r77.get("failed_atoms") != 14 or r77.get("failed_cases") != 11:
        raise RuntimeError("R77 failure boundary is not the frozen 14 atoms across 11 cases")
    r80 = json.loads((args.r80_gate_dir / "summary.json").read_text())
    if r80.get("r81_retry_authorized") is not False:
        raise RuntimeError("R80 zero-freeze gate must remain failed")
    manifest = pd.read_csv(args.r82_grid_dir / "diagnostic_manifest.csv")
    expected = {("pricefm_joint_fr_f3", 0.25), ("pricefm_joint_se_4_f1", 0.25),
                ("pricefm_joint_se_4_f1", 0.75)}
    if len(manifest) != 3 or set(zip(manifest.case_id, manifest.tau)) != expected:
        raise RuntimeError("R82 diagnostic manifest identity changed")
    controls = pd.DataFrame([
        read_control(Path(row.output_dir)) for row in manifest.itertuples(index=False)
    ]).sort_values(["case_id", "tau"])

    all_three = len(controls) == 3
    provenance_ok = bool(
        all_three
        and controls.package_version.eq("1.1.1.9004").all()
        and controls.package_repair.eq(REPAIR).all()
    )
    finite_ok = bool(all_three and controls.trace_finite.all())
    updates_ok = bool(all_three and controls.structured_updates.ge(35).all())
    bounded_sigma = bool(all_three and controls.max_sigma.lt(100).all())
    bounded_beta = bool(all_three and controls.beta_l2_ratio.lt(10).all())
    bounded_gamma = bool(all_three and controls.max_abs_gamma.lt(4).all())
    bounded_first_step = bool(all_three and controls.first_delta_state.lt(100).all())
    bounded_tail = bool(
        all_three
        and controls.tail_max_delta_state.lt(2).all()
        and controls.tail_max_delta_sigma.lt(2).all()
    )
    authorized = bool(
        provenance_ok and finite_ok and updates_ok and bounded_sigma and bounded_beta
        and bounded_gamma and bounded_first_step and bounded_tail
    )
    gates = pd.DataFrame([
        {"gate": "frozen_failure_boundary_is_14_atoms", "passed": True, "observed": 14},
        {"gate": "old_zero_freeze_only_hypothesis_remains_falsified", "passed": True,
         "observed": r80.get("status")},
        {"gate": "three_repaired_controls_completed", "passed": all_three, "observed": len(controls)},
        {"gate": "r82_runtime_provenance", "passed": provenance_ok, "observed": "1.1.1.9004"},
        {"gate": "all_required_trace_fields_finite", "passed": finite_ok,
         "observed": int(controls.trace_finite.sum())},
        {"gate": "minimum_35_structured_updates", "passed": updates_ok,
         "observed": int(controls.structured_updates.min())},
        {"gate": "max_sigma_below_100", "passed": bounded_sigma,
         "observed": float(controls.max_sigma.max())},
        {"gate": "final_beta_l2_below_10x_al_anchor", "passed": bounded_beta,
         "observed": float(controls.beta_l2_ratio.max())},
        {"gate": "gamma_inside_numerical_guard", "passed": bounded_gamma,
         "observed": float(controls.max_abs_gamma.max())},
        {"gate": "first_state_step_below_100", "passed": bounded_first_step,
         "observed": float(controls.first_delta_state.max())},
        {"gate": "last_10_state_and_sigma_steps_below_2", "passed": bounded_tail,
         "observed": float(max(controls.tail_max_delta_state.max(), controls.tail_max_delta_sigma.max()))},
        {"gate": "bounded_r83_retry_authorized", "passed": authorized,
         "observed": 14 if authorized else 0},
        {"gate": "test_registry_article_still_blocked", "passed": True, "observed": "blocked"},
    ])

    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True)
    controls.to_csv(output / "pricefm_stage_r82_control_results.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r82_repair_gates.csv", index=False)
    sources = [
        args.r77_dir / "summary.json",
        args.r80_gate_dir / "summary.json",
        args.r82_grid_dir / "diagnostic_manifest.csv",
    ]
    for row in manifest.itertuples(index=False):
        run_dir = Path(row.output_dir)
        sources.extend([run_dir / "terminal.json", run_dir / "vb_trace.csv",
                        run_dir / "method_summary.csv", run_dir / "parameter_summary.csv"])
    pd.DataFrame([
        {"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in sources
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "structured_init_repair_gate_passed" if authorized else "structured_init_repair_gate_failed",
        "root_cause": "nonsmooth_abs_gamma_delta_initialization_invalidated_initial_xi",
        "diagnostic_controls": int(len(controls)),
        "r83_retry_authorized": authorized,
        "r83_retry_atoms": 14 if authorized else 0,
        "successful_r76_atoms_refit": 0,
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    (output / "pricefm_stage_r82_structured_init_repair_report.md").write_text(
        "# PriceFM Stage-R82 Structured Initialization Repair Gate\n\n"
        "R80 showed that changing only the frozen warm-up schedule was insufficient. At gamma=0, "
        "the exAL lambda term contains an absolute value, so a Gaussian second-order delta "
        "correction is not valid at the initialization point. The observed correction made the "
        "initial likelihood precision negative; flooring it effectively removed the likelihood "
        "from the first coefficient update. R82 instead uses plug-in moments at the AL warm start "
        "for the first CAVI update and then the exact structured gamma-grid / conditional-GIG "
        "factor. The gate above authorizes only the 14 failed R76 atoms and never authorizes test, "
        "registry, or article access.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
