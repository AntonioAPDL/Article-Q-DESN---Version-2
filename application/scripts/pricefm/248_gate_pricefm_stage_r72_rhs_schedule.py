#!/usr/bin/env python3
"""Compare bounded RHS initialization schedules beyond the tau release point."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from typing import Any

import numpy as np
import pandas as pd
import yaml


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R69B = DATA / "experiment_grids/pricefm_stage_r69b_bounded_cran111_independent_vb_20260831/case_manifest.csv"
R72 = DATA / "experiment_grids/pricefm_stage_r72_missing_al_repair_20260901/task_manifest.csv"
MECHANISM_GATE = DATA / "authoritative/pricefm_stage_r72_mechanism_gates_20260901/summary.json"
RUNTIME = DATA / "runtime_libraries/exdqlm_pricefm_r72_spd_repair"
RUNTIME_MANIFEST = RUNTIME / "pricefm_stage_r72_spd_repair_manifest.json"
OUTPUT = DATA / "authoritative/pricefm_stage_r72_rhs_schedule_gate_20260901"
TARGETS = (
    ("pricefm_joint_bg_f1", 0.25, "failed_early"),
    ("pricefm_joint_sk_f2", 0.75, "failed_late"),
    ("pricefm_joint_es_f3", 0.25, "completed_control"),
)
SCHEDULES = (("init_one", 1.0), ("init_tau0", 0.001))


def parse_bool(value: str | bool) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).lower() in {"true", "1", "yes"}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, default=Path(__file__).resolve().parents[3])
    p.add_argument("--r69b-manifest", type=Path, default=R69B)
    p.add_argument("--r72-manifest", type=Path, default=R72)
    p.add_argument("--mechanism-gate", type=Path, default=MECHANISM_GATE)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--max-iter", type=int, default=60)
    p.add_argument("--freeze-iters", type=int, default=50)
    p.add_argument("--cpu-list", default="52,53,54,55,56,57")
    p.add_argument("--run-probes", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def parse_cpus(value: str) -> list[int]:
    cpus = [int(item.strip()) for item in value.split(",") if item.strip()]
    if len(cpus) != 6 or len(set(cpus)) != 6 or not set(cpus).issubset(range(os.cpu_count() or 0)):
        raise RuntimeError("R72 RHS gate requires six unique online CPUs")
    return cpus


def task_from_anchor(anchor: pd.Series, case_id: str, tau: float) -> dict[str, Any]:
    source_config = Path(anchor.config)
    config = yaml.safe_load(source_config.read_text())["pricefm_desn_smoke"]
    qcfg = config.get("qdesn_vb") or {}
    return {
        "stage": "R72", "case_id": case_id, "region": anchor.region,
        "fold": int(anchor.fold), "tau": tau, "likelihood_family": "al",
        "method_id": "qdesn_al_rhs_ns_pricefm_r72_spd_repair",
        "source_case_config": str(source_config), "adapter_dir": str(Path(anchor.adapter_dir)),
        "r_library": str(RUNTIME), "runtime_manifest": str(RUNTIME_MANIFEST),
        "selection_split": "val", "selection_is_validation_only": True,
        "max_iter": max(60, int(qcfg.get("max_iter", 60))),
        "tol": float(qcfg.get("tol", 1e-4)), "n_samp": 20, "n_samp_xi": 20,
        "rhs_tau0": float(anchor.rhs_tau0), "rhs_freeze_tau_iters": 50,
        "rhs_freeze_tau_warmup_iters": 50, "seed": 20260912,
        "exal_mechanism_gate_passed": False, "test_access_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "joint_model_authorized": False, "mcmc_authorized": False,
    }


def pinball(y: np.ndarray, prediction: np.ndarray, tau: float) -> float:
    residual = y - prediction
    return float(np.mean(np.where(residual >= 0, tau * residual, (tau - 1) * residual)))


def evaluate(task: dict[str, Any], role: str, schedule: str) -> dict[str, Any]:
    output = Path(task["output_dir"])
    terminal = json.loads((output / "terminal.json").read_text())
    parameter = pd.read_csv(output / "parameter_summary.csv")
    spd = pd.read_csv(output / "spd_factorization_trace.csv")
    rhs = json.loads((output / "rhs_diagnostics.json").read_text())
    prediction = pd.read_csv(output / "predictions_scaled.csv").pred_scaled.to_numpy(float)
    y_val = np.loadtxt(Path(task["adapter_dir"]) / "y_val.csv", delimiter=",", ndmin=1)
    summary = rhs.get("summary") or {}
    relative = pd.to_numeric(spd.relative_jitter, errors="coerce")
    completed = terminal.get("status") == "completed"
    finite = bool(
        np.isfinite(prediction).all()
        and pd.to_numeric(parameter.beta_l2, errors="coerce").notna().all()
        and pd.to_numeric(parameter.sigma, errors="coerce").notna().all()
    )
    collapse = bool(summary.get("collapse_flag") or summary.get("collapse_pattern"))
    return {
        "task_id": task["task_id"], "case_id": task["case_id"], "region": task["region"],
        "fold": task["fold"], "tau": task["tau"], "case_role": role,
        "schedule": schedule, "rhs_init_tau": task["rhs_init_tau"],
        "rhs_freeze_iters": task["rhs_freeze_tau_iters"],
        "completed": completed, "finite": finite, "converged": bool(terminal.get("converged")),
        "iter": terminal.get("iter"), "collapse_flag": collapse,
        "final_rhs_tau": summary.get("tau"), "rhs_tau_update_count": summary.get("rhs_tau_update_count"),
        "beta_l2": float(parameter.beta_l2.iloc[0]), "sigma": float(parameter.sigma.iloc[0]),
        "validation_pinball_scaled": pinball(y_val, prediction, float(task["tau"])),
        "max_relative_spd_jitter": float(relative.max()),
        "bounded_spd": bool(relative.notna().all() and relative.max() <= 1e-8),
        "output_dir": str(output),
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    mechanism = json.loads(args.mechanism_gate.read_text())
    if mechanism.get("al_repair_launch_gate_passed") is not True or mechanism.get("exal_launch_gate_passed") is not False:
        raise RuntimeError("R72 base mechanism gate is not AL-pass/exAL-blocked")
    if args.max_iter <= args.freeze_iters:
        raise RuntimeError("RHS schedule probes must cross the tau release point")
    if args.output_dir.exists() and any(args.output_dir.iterdir()):
        if not args.force:
            raise FileExistsError(args.output_dir)
        shutil.rmtree(args.output_dir)
    args.output_dir.mkdir(parents=True)
    anchors = pd.read_csv(args.r69b_manifest).set_index("case_id")
    r72 = pd.read_csv(args.r72_manifest)
    cpus = parse_cpus(args.cpu_list)
    jobs: list[tuple[dict[str, Any], str, str, Path, int]] = []
    for case_id, tau, role in TARGETS:
        anchor = anchors.loc[case_id]
        base = task_from_anchor(anchor, case_id, tau)
        for schedule, init_tau in SCHEDULES:
            task = dict(base)
            task["task_id"] = f"{case_id}__tau_{str(tau).replace('.', 'p')}__{schedule}__rhs_gate"
            task["rhs_init_tau"] = init_tau
            task["rhs_freeze_tau_iters"] = args.freeze_iters
            task["rhs_freeze_tau_warmup_iters"] = args.freeze_iters
            task["max_iter"] = args.max_iter
            task["output_dir"] = str(args.output_dir / "probes" / task["task_id"])
            task_path = args.output_dir / "tasks" / f"{task['task_id']}.json"
            write_json(task_path, task)
            jobs.append((task, role, schedule, task_path, cpus[len(jobs)]))

    def execute(job: tuple[dict[str, Any], str, str, Path, int]) -> None:
        task, _, _, task_path, cpu = job
        log = Path(task["output_dir"]).parent / f"{task['task_id']}.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ)
        for key in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "RCPP_PARALLEL_NUM_THREADS"):
            env[key] = "1"
        with log.open("w") as handle:
            subprocess.run([
                "taskset", "-c", str(cpu), "Rscript",
                str(args.code_root / "application/scripts/pricefm/243_run_pricefm_stage_r72_repair_component.R"),
                "--task-config", str(task_path),
            ], cwd=args.code_root, env=env, stdout=handle, stderr=subprocess.STDOUT, check=True)

    if args.run_probes:
        with ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(execute, jobs))
    results = pd.DataFrame([evaluate(task, role, schedule) for task, role, schedule, _, _ in jobs])
    results.to_csv(args.output_dir / "pricefm_stage_r72_rhs_schedule_probe_results.csv", index=False)
    aggregates = results.groupby("schedule", as_index=False).agg(
        probes=("task_id", "count"), completed=("completed", "sum"), finite=("finite", "sum"),
        collapsed=("collapse_flag", "sum"), bounded_spd=("bounded_spd", "sum"),
        converged=("converged", "sum"), mean_validation_pinball_scaled=("validation_pinball_scaled", "mean"),
        max_beta_l2=("beta_l2", "max"), max_sigma=("sigma", "max"),
        max_relative_spd_jitter=("max_relative_spd_jitter", "max"),
    )
    aggregates["mechanism_pass"] = (
        aggregates.completed.eq(3) & aggregates.finite.eq(3)
        & aggregates.collapsed.eq(0) & aggregates.bounded_spd.eq(3)
    )
    eligible = aggregates[aggregates.mechanism_pass].sort_values(
        ["mean_validation_pinball_scaled", "max_beta_l2", "schedule"]
    )
    if eligible.empty:
        raise RuntimeError("Neither RHS initialization schedule passed the mechanism gate")
    selected_schedule = str(eligible.iloc[0].schedule)
    selected_init = dict(SCHEDULES)[selected_schedule]
    aggregates["selected"] = aggregates.schedule.eq(selected_schedule)
    aggregates.to_csv(args.output_dir / "pricefm_stage_r72_rhs_schedule_comparison.csv", index=False)
    gates = pd.DataFrame([
        {"gate": "all_six_probes_terminal", "passed": bool(results.completed.all()), "observed": int(results.completed.sum())},
        {"gate": "at_least_one_schedule_mechanism_valid", "passed": bool(aggregates.mechanism_pass.any()), "observed": int(aggregates.mechanism_pass.sum())},
        {"gate": "selected_schedule_crossed_release", "passed": args.max_iter > args.freeze_iters, "observed": f"max_iter={args.max_iter};freeze={args.freeze_iters}"},
        {"gate": "selected_schedule_no_collapse", "passed": bool(results.loc[results.schedule == selected_schedule, "collapse_flag"].eq(False).all()), "observed": selected_schedule},
        {"gate": "exal_test_registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
    ])
    if not gates.passed.all():
        raise RuntimeError("R72 RHS schedule gates failed")
    gates.to_csv(args.output_dir / "pricefm_stage_r72_rhs_schedule_gates.csv", index=False)
    source_paths = [Path(__file__).resolve(), args.r69b_manifest.resolve(), args.r72_manifest.resolve(),
                    args.mechanism_gate.resolve()] + [job[3].resolve() for job in jobs]
    pd.DataFrame([{"path": str(p), "sha256": sha256(p), "bytes": p.stat().st_size} for p in source_paths]).to_csv(
        args.output_dir / "source_manifest.csv", index=False
    )
    summary = {
        "status": "rhs_schedule_selected_al_launch_ready",
        "al_repair_launch_gate_passed": True, "exal_launch_gate_passed": False,
        "selected_rhs_schedule": selected_schedule, "selected_rhs_init_tau": selected_init,
        "selected_rhs_freeze_iters": args.freeze_iters,
        "selection_basis": "mechanism_valid_then_lowest_mean_validation_pinball_across_three_representative_cases",
        "probe_cases": 3, "probe_fits": 6, "probe_max_iter": args.max_iter,
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
    }
    write_json(args.output_dir / "summary.json", summary)
    (args.output_dir / "pricefm_stage_r72_rhs_schedule_report.md").write_text(
        "# PriceFM Stage-R72 RHS Schedule Gate\n\n"
        f"Selected `{selected_schedule}` (`init_tau={selected_init:g}`, freeze={args.freeze_iters}) "
        "after six bounded AL fits crossed the RHS release point. Selection required finite, "
        "non-collapsed, bounded-SPD fits and then used validation pinball loss. exAL and all "
        "test/registry/article/joint/MCMC actions remain blocked.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
