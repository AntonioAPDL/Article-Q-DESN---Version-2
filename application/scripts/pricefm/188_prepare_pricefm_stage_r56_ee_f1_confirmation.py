#!/usr/bin/env python3
"""Prepare the bounded PriceFM R56 EE-fold-1 full-budget confirmation."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
PRICEFM_ROOT = ARTIFACT_REPO / "application/data_local/pricefm"
R55 = PRICEFM_ROOT / "authoritative/pricefm_stage_r55_functional_convergence_20260820"
R53_PREP = PRICEFM_ROOT / "authoritative/pricefm_stage_r52_r53_exal_m0_launch_prep_20260811"
OUTPUT = PRICEFM_ROOT / "authoritative/pricefm_stage_r56_ee_f1_confirmation_prep_20260820"
GRID = PRICEFM_ROOT / "experiment_grids/pricefm_stage_r56_ee_f1_full_budget_confirmation_20260820"
RUNS = PRICEFM_ROOT / "runs/pricefm_stage_r56_ee_f1_full_budget_confirmation_20260820"
RUN_TAG = "pricefm_stage_r56_ee_f1_full_budget_confirmation_20260820"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
M0_MODE = "m0_v_collapsed_support_logit"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r55-dir", type=Path, default=R55)
    p.add_argument("--stage-r53-prep-dir", type=Path, default=R53_PREP)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--chains", type=int, default=4)
    p.add_argument("--n-burn", type=int, default=5000)
    p.add_argument("--n-mcmc", type=int, default=20000)
    p.add_argument("--workers", type=int, default=20)
    p.add_argument("--expected-targets", type=int, default=1)
    p.add_argument("--authorize-launch", type=parse_bool, default=False)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def git_head(path: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
    ).strip()


def prepare_dir(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(f"Output exists: {path}")
    path.mkdir(parents=True, exist_ok=True)


def bool_value(value: object) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() == "true"


def tau_label(tau: float) -> str:
    return f"tau{int(round(float(tau) * 100)):02d}"


def confirmation_seed(tau_index: int, chain: int) -> int:
    return 202608200 + tau_index * 100 + chain


def read_completed_case_summary(path: Path) -> dict:
    payload = json.loads(path.read_text())
    if payload.get("status") != "completed" or not payload.get("m0_launch_eligible"):
        raise RuntimeError(f"Frozen R52 case is not M0 eligible: {path}")
    return payload


def validate_design(design: pd.DataFrame, summary: dict, args) -> pd.Series:
    if summary.get("status") != "completed_read_only_functional_convergence_audit":
        raise RuntimeError("R55 is not a completed functional-convergence audit")
    if len(design) != args.expected_targets:
        raise RuntimeError(f"Expected {args.expected_targets} R55 target, found {len(design)}")
    target = design.iloc[0]
    if str(target.case_id) != "r52_ee_f1" or str(target.region) != "EE" or int(target.fold) != 1:
        raise RuntimeError("R56 is bounded to the preregistered EE/fold-1 target")
    quantiles = tuple(float(value) for value in json.loads(str(target.quantiles)))
    if quantiles != TAUS:
        raise RuntimeError(f"R55 quantile contract changed: {quantiles}")
    if int(target.chains_per_quantile) != args.chains or args.chains != 4:
        raise RuntimeError("R56 requires four chains per quantile")
    if int(target.recommended_burn) != args.n_burn or int(target.recommended_retained_per_chain) != args.n_mcmc:
        raise RuntimeError("R56 budget must match the R55 established-budget recommendation")
    if "validation_selected" not in str(target.selection_basis):
        raise RuntimeError("R56 target was not selected from validation evidence")
    if bool_value(target.launch_authorized):
        raise RuntimeError("R55 must remain a read-only audit; launch authorization belongs to R56 prep")
    return target


def run(args) -> dict:
    if args.workers != 20:
        raise ValueError("R56 is preregistered for exactly 20 physical-core workers")
    if args.n_burn != 5000 or args.n_mcmc != 20000:
        raise ValueError("R56 requires the established 5000 burn-in and 20000 retained draws")

    out = args.output_dir.resolve()
    grid = args.grid_dir.resolve()
    runs = args.run_dir.resolve()
    prepare_dir(out, args.force)
    prepare_dir(grid, args.force)
    (grid / "chain_configs").mkdir(parents=True, exist_ok=True)
    (runs / "chains").mkdir(parents=True, exist_ok=True)

    design_path = args.stage_r55_dir / "pricefm_stage_r55_confirmation_design.csv"
    r55_summary_path = args.stage_r55_dir / "summary.json"
    source_manifest_path = args.stage_r53_prep_dir / "pricefm_stage_r53_launch_manifest.csv"
    source_cases_path = args.stage_r53_prep_dir / "pricefm_stage_r52_case_manifest.csv"
    r53_summary_path = args.stage_r53_prep_dir / "summary.json"
    design = pd.read_csv(design_path)
    r55_summary = json.loads(r55_summary_path.read_text())
    target = validate_design(design, r55_summary, args)

    source_manifest = pd.read_csv(source_manifest_path)
    source_cases = pd.read_csv(source_cases_path)
    source_jobs = source_manifest[source_manifest.case_id.eq(target.case_id)].copy()
    source_case = source_cases[source_cases.id.eq(target.case_id)].copy()
    if len(source_case) != 1 or len(source_jobs) != len(TAUS) * args.chains:
        raise RuntimeError("R53 does not contain the complete frozen EE/fold-1 surface")
    if source_jobs.groupby("tau").chain.nunique().ne(args.chains).any():
        raise RuntimeError("R53 EE/fold-1 chains are incomplete")
    if tuple(sorted(source_jobs.tau.unique())) != TAUS:
        raise RuntimeError("R53 EE/fold-1 quantiles changed")

    r53_summary = json.loads(r53_summary_path.read_text())
    source_configs = [Path(path) for path in source_jobs.config]
    for path in source_configs:
        if not path.is_file():
            raise FileNotFoundError(path)
    template_payload = yaml.safe_load(source_configs[0].read_text())["pricefm_stage_r53_m0"]
    case_summary_path = Path(template_payload["case_summary"])
    read_completed_case_summary(case_summary_path)
    exdqlm_path = Path(template_payload["exdqlm_path"])
    if git_head(exdqlm_path) != r53_summary.get("exdqlm_head"):
        raise RuntimeError("Collapsed-M0 engine drifted from the frozen R53 campaign")

    source_seeds = set(source_jobs.seed.astype(int))
    rows: list[dict] = []
    init_sources: set[Path] = set()
    for tau_index, tau in enumerate(TAUS, start=1):
        source_for_tau = source_jobs[source_jobs.tau.round(8).eq(round(tau, 8))].sort_values("chain")
        if len(source_for_tau) != args.chains:
            raise RuntimeError(f"Missing R53 source chains for tau={tau}")
        for chain in range(1, args.chains + 1):
            source_row = source_for_tau[source_for_tau.chain.eq(chain)].iloc[0]
            source_payload = yaml.safe_load(Path(source_row.config).read_text())
            cfg = dict(source_payload["pricefm_stage_r53_m0"])
            init_path = Path(cfg["init_path"])
            if not init_path.is_file():
                raise FileNotFoundError(init_path)
            init_sources.add(init_path)
            job_id = f"r56_ee_f1_{tau_label(tau)}_chain{chain}"
            output_dir = runs / "chains" / job_id
            config_path = grid / "chain_configs" / f"{job_id}.yaml"
            seed = confirmation_seed(tau_index, chain)
            if seed in source_seeds:
                raise RuntimeError("R56 fresh-restart seed collides with R53")
            cfg.update({
                "id": job_id,
                "seed": seed,
                "n_burn": int(args.n_burn),
                "n_mcmc": int(args.n_mcmc),
                "output_dir": str(output_dir),
                "core_update_mode": M0_MODE,
                "init_from_vb": False,
                "store_latent_draws": False,
                "store_rhs_draws": True,
                "registry_mutation_authorized": False,
                "article_mutation_authorized": False,
            })
            config_path.write_text(yaml.safe_dump({"pricefm_stage_r53_m0": cfg}, sort_keys=False))
            rows.append({
                "id": job_id,
                "case_id": str(target.case_id),
                "region": "EE",
                "fold": 1,
                "tau": tau,
                "chain": chain,
                "seed": seed,
                "n_burn": int(args.n_burn),
                "n_mcmc": int(args.n_mcmc),
                "restart_mode": "fresh_from_frozen_explicit_vb_init",
                "source_r53_job_id": str(source_row.id),
                "source_r53_config": str(Path(source_row.config)),
                "init_path": str(init_path),
                "config": str(config_path),
                "output_dir": str(output_dir),
                "status": "prepared_not_launched",
            })

    manifest = pd.DataFrame(rows).sort_values(["tau", "chain"]).reset_index(drop=True)
    manifest_path = out / "pricefm_stage_r56_launch_manifest.csv"
    manifest.to_csv(manifest_path, index=False)

    expected_jobs = len(TAUS) * args.chains
    gates = pd.DataFrame([
        {"gate": "r55_completed", "passed": True, "observed": r55_summary.get("status")},
        {"gate": "single_bounded_target", "passed": len(design) == 1, "observed": len(design)},
        {"gate": "target_is_ee_fold1", "passed": manifest.region.eq("EE").all() and manifest.fold.eq(1).all(), "observed": "EE/fold=1"},
        {"gate": "validation_only_selection", "passed": "validation_selected" in str(target.selection_basis), "observed": str(target.selection_basis)},
        {"gate": "seven_quantiles", "passed": manifest.tau.nunique() == 7, "observed": manifest.tau.nunique()},
        {"gate": "four_chains_per_quantile", "passed": manifest.groupby("tau").chain.nunique().eq(4).all(), "observed": 4},
        {"gate": "complete_28_job_surface", "passed": len(manifest) == expected_jobs, "observed": len(manifest)},
        {"gate": "established_full_budget", "passed": manifest.n_burn.eq(5000).all() and manifest.n_mcmc.eq(20000).all(), "observed": "5000+20000"},
        {"gate": "fresh_restart_disclosed", "passed": manifest.restart_mode.eq("fresh_from_frozen_explicit_vb_init").all(), "observed": "no retained sampler state"},
        {"gate": "collapsed_m0_pinned", "passed": template_payload.get("core_update_mode") == M0_MODE, "observed": template_payload.get("core_update_mode")},
        {"gate": "frozen_case_replay_reused", "passed": case_summary_path.is_file(), "observed": str(case_summary_path)},
        {"gate": "frozen_initializations_present", "passed": all(path.is_file() for path in init_sources), "observed": len(init_sources)},
        {"gate": "registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    gates_path = out / "pricefm_stage_r56_prelaunch_gates.csv"
    gates.to_csv(gates_path, index=False)
    if not gates.passed.astype(bool).all():
        raise RuntimeError("R56 prelaunch gates failed")

    worker = Path(__file__).with_name("184_run_pricefm_stage_r53_exal_m0_chain.R")
    launcher = Path(__file__).with_name("189_launch_pricefm_stage_r56_ee_f1_confirmation.py")
    required_sources = {
        design_path,
        r55_summary_path,
        source_manifest_path,
        source_cases_path,
        r53_summary_path,
        case_summary_path,
        worker,
        launcher,
        Path(__file__).resolve(),
        *source_configs,
        *init_sources,
    }
    source_rows = [
        {"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in sorted(required_sources, key=str)
    ]
    source_manifest_out = out / "source_manifest.csv"
    pd.DataFrame(source_rows).to_csv(source_manifest_out, index=False)

    launch_yaml = out / "pricefm_stage_r56_launch.yaml"
    launch_payload = {
        "pricefm_stage_r56_launch": {
            "run_tag": RUN_TAG,
            "manifest": str(manifest_path),
            "worker": str(worker.resolve()),
            "launcher": str(launcher.resolve()),
            "jobs": args.workers,
            "required_idle_physical_cores": args.workers,
            "one_process_per_physical_core": True,
            "threads_per_process": 1,
            "maximum_load_1m": 36.0,
            "minimum_memory_gib": 128.0,
            "minimum_disk_gib": 100.0,
            "resume": True,
            "fresh_restart": True,
            "exact_continuation_possible": False,
            "launch_authorized_by_user": bool(args.authorize_launch),
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        }
    }
    launch_yaml.write_text(yaml.safe_dump(launch_payload, sort_keys=False))

    summary = {
        "status": (
            "materialized_ready_to_launch"
            if args.authorize_launch
            else "materialized_waiting_for_explicit_launch_authorization"
        ),
        "run_tag": RUN_TAG,
        "target_cases": 1,
        "target": "EE/fold=1",
        "quantiles": len(TAUS),
        "chains_per_quantile": args.chains,
        "chain_jobs": len(manifest),
        "n_burn": args.n_burn,
        "n_mcmc": args.n_mcmc,
        "workers": args.workers,
        "estimated_core_hours_from_r53_linear_scaling": 1372.9,
        "estimated_wall_hours_at_20_workers": 68.6,
        "fresh_restart": True,
        "exact_continuation_possible": False,
        "launch_yaml": str(launch_yaml),
        "launch_authorized": bool(args.authorize_launch),
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    write_json(out / "summary.json", summary)
    (out / "pricefm_stage_r56_confirmation_prep_report.md").write_text(
        "# PriceFM Stage-R56 EE/fold-1 confirmation prep\n\n"
        "R56 contains exactly one case selected by the frozen R55 gate: EE fold 1. "
        "It retains all seven manuscript quantiles and four chains, using 5,000 burn-in "
        "iterations and 20,000 retained draws per chain. The 28 chains restart from the "
        "frozen explicit VB initializations because R53 did not retain exact sampler state.\n\n"
        "The launcher requires 20 idle physical cores, one numerical thread per process, "
        "load/memory/disk gates, resumable outputs, and the global PriceFM campaign lock. "
        "No registry or article mutation is authorized.\n"
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
