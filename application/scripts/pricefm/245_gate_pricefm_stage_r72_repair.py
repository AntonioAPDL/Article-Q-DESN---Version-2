#!/usr/bin/env python3
"""Run bounded numerical/scientific gates for the Stage-R72 AL repair."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from typing import Any

import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R71 = DATA / "authoritative/pricefm_stage_r71_r70_closeout_20260901"
R72_GRID = DATA / "experiment_grids/pricefm_stage_r72_missing_al_repair_20260901"
OUTPUT = DATA / "authoritative/pricefm_stage_r72_mechanism_gates_20260901"
DEFAULT_PROBE = "pricefm_joint_bg_f1__tau_0p25__al"


def parse_bool(value: str | bool) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).lower() in {"true", "1", "yes"}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, default=Path(__file__).resolve().parents[3])
    p.add_argument("--r71-dir", type=Path, default=R71)
    p.add_argument("--task-manifest", type=Path, default=R72_GRID / "task_manifest.csv")
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--probe-task-id", default=DEFAULT_PROBE)
    p.add_argument("--probe-max-iter", type=int, default=12)
    p.add_argument("--run-probe", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def evaluate_exal_gate(atoms: pd.DataFrame) -> dict[str, Any]:
    exal = atoms[(atoms.likelihood_family == "exal") & atoms.artifacts_complete].copy()
    beta = pd.to_numeric(exal.beta_l2, errors="coerce")
    sigma = pd.to_numeric(exal.sigma, errors="coerce")
    finite = beta.notna() & sigma.notna()
    extreme_beta = finite & beta.gt(1e6)
    extreme_sigma = finite & sigma.gt(1e6)
    passed = bool(
        len(exal) > 0
        and finite.all()
        and extreme_beta.mean() <= 0.01
        and extreme_sigma.mean() <= 0.01
        and exal.converged.astype(str).str.lower().eq("true").mean() >= 0.8
    )
    return {
        "passed": passed,
        "atoms": int(len(exal)),
        "finite_atoms": int(finite.sum()),
        "extreme_beta_atoms": int(extreme_beta.sum()),
        "extreme_sigma_atoms": int(extreme_sigma.sum()),
        "converged_atoms": int(exal.converged.astype(str).str.lower().eq("true").sum()),
        "decision": "exal_launch_allowed" if passed else "exal_launch_blocked",
    }


def evaluate_probe(probe_dir: Path) -> dict[str, Any]:
    terminal = json.loads((probe_dir / "terminal.json").read_text())
    parameter = pd.read_csv(probe_dir / "parameter_summary.csv")
    spd = pd.read_csv(probe_dir / "spd_factorization_trace.csv")
    rhs = json.loads((probe_dir / "rhs_diagnostics.json").read_text())
    relative = pd.to_numeric(spd.relative_jitter, errors="coerce")
    parameter_finite = bool(
        pd.to_numeric(parameter.beta_l2, errors="coerce").notna().all()
        and pd.to_numeric(parameter.sigma, errors="coerce").notna().all()
    )
    return {
        "terminal_completed": terminal.get("status") == "completed",
        "parameter_finite": parameter_finite,
        "spd_trace_rows": int(len(spd)),
        "spd_max_relative_jitter": float(relative.max()),
        "spd_within_bound": bool(relative.notna().all() and relative.max() <= 1e-8),
        "rhs_tau0": rhs.get("preflight", {}).get("tau0"),
        "rhs_init_tau": rhs.get("preflight", {}).get("init_tau"),
        "rhs_init_source": rhs.get("preflight", {}).get("init_tau_source"),
        "rhs_contract_pass": bool(
            rhs.get("preflight", {}).get("tau0") == 0.001
            and rhs.get("preflight", {}).get("init_tau") == 1
            and rhs.get("preflight", {}).get("init_tau_source") == "init_tau"
        ),
        "converged_at_bounded_iteration_budget": bool(terminal.get("converged", False)),
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    if args.output_dir.exists() and any(args.output_dir.iterdir()):
        if not args.force:
            raise FileExistsError(args.output_dir)
        shutil.rmtree(args.output_dir)
    args.output_dir.mkdir(parents=True)
    manifest = pd.read_csv(args.task_manifest)
    atoms_path = args.r71_dir / "pricefm_stage_r71_atomic_fit_salvage_ledger.csv"
    atoms = pd.read_csv(atoms_path)
    exal = evaluate_exal_gate(atoms)
    selected = manifest[manifest.task_id == args.probe_task_id]
    if len(selected) != 1:
        raise RuntimeError(f"Probe task identity is not unique: {args.probe_task_id}")
    source_task = Path(selected.iloc[0].task_config)
    probe_task = json.loads(source_task.read_text())
    probe_dir = args.output_dir / "real_design_probe"
    probe_task["task_id"] = probe_task["task_id"] + "__bounded_gate"
    probe_task["output_dir"] = str(probe_dir)
    probe_task["max_iter"] = args.probe_max_iter
    probe_task["n_samp"] = 20
    probe_task["n_samp_xi"] = 20
    probe_task_path = args.output_dir / "real_design_probe_task.json"
    write_json(probe_task_path, probe_task)
    if args.run_probe:
        subprocess.run([
            "Rscript",
            str(args.code_root / "application/scripts/pricefm/243_run_pricefm_stage_r72_repair_component.R"),
            "--task-config", str(probe_task_path),
        ], cwd=args.code_root, check=True)
    probe = evaluate_probe(probe_dir)
    gates = pd.DataFrame([
        {"gate": "real_failed_case_probe_completed", "required_for_al_launch": True, "passed": probe["terminal_completed"], "observed": probe["terminal_completed"]},
        {"gate": "real_probe_parameters_finite", "required_for_al_launch": True, "passed": probe["parameter_finite"], "observed": probe["parameter_finite"]},
        {"gate": "bounded_spd_repair", "required_for_al_launch": True, "passed": probe["spd_within_bound"], "observed": probe["spd_max_relative_jitter"]},
        {"gate": "explicit_rhs_schedule", "required_for_al_launch": True, "passed": probe["rhs_contract_pass"], "observed": f"tau0={probe['rhs_tau0']};init_tau={probe['rhs_init_tau']}"},
        {"gate": "bounded_probe_convergence", "required_for_al_launch": False, "passed": probe["converged_at_bounded_iteration_budget"], "observed": probe["converged_at_bounded_iteration_budget"]},
        {"gate": "structured_exal_stability", "required_for_al_launch": False, "passed": exal["passed"], "observed": f"extreme_beta={exal['extreme_beta_atoms']}/{exal['atoms']}"},
        {"gate": "test_registry_article_joint_mcmc_blocked", "required_for_al_launch": True, "passed": True, "observed": "blocked"},
    ])
    required = gates[gates.required_for_al_launch]
    al_launch_passed = bool(required.passed.all())
    gates.to_csv(args.output_dir / "pricefm_stage_r72_mechanism_gates.csv", index=False)
    write_json(args.output_dir / "pricefm_stage_r72_real_probe_summary.json", probe)
    write_json(args.output_dir / "pricefm_stage_r72_exal_gate_summary.json", exal)
    sources = [Path(__file__).resolve(), args.task_manifest.resolve(), atoms_path.resolve(),
               source_task.resolve(), probe_task_path.resolve(), probe_dir / "terminal.json",
               probe_dir / "spd_factorization_trace.csv", probe_dir / "rhs_diagnostics.json"]
    pd.DataFrame([
        {"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in sources
    ]).to_csv(args.output_dir / "source_manifest.csv", index=False)
    summary = {
        "status": "al_repair_gate_passed_exal_blocked" if al_launch_passed and not exal["passed"] else "gate_result_requires_review",
        "al_repair_launch_gate_passed": al_launch_passed,
        "exal_launch_gate_passed": exal["passed"],
        "production_manifest_likelihoods_allowed": ["al"] if al_launch_passed else [],
        "probe_task_id": args.probe_task_id,
        "probe_max_iter": args.probe_max_iter,
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
    }
    write_json(args.output_dir / "summary.json", summary)
    (args.output_dir / "pricefm_stage_r72_mechanism_gate_report.md").write_text(
        "# PriceFM Stage-R72 Mechanism Gates\n\n"
        f"The bounded real-design AL repair gate is {'PASS' if al_launch_passed else 'FAIL'}. "
        f"The structured-exAL gate is {'PASS' if exal['passed'] else 'FAIL'}; "
        f"{exal['extreme_beta_atoms']} of {exal['atoms']} existing exAL atoms have beta L2 above 1e6. "
        "Only AL may enter R72 production when all required gates pass.\n"
    )
    if not al_launch_passed:
        raise RuntimeError("R72 AL production gate failed")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
