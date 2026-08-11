#!/usr/bin/env python3
"""Materialize the full PriceFM R52 replay and R53 collapsed-M0 campaign."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import subprocess
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
ARTICLE_REPO = Path(__file__).resolve().parents[3]
EXDQLM_REPO = Path("/data/jaguir26/local/src/exdqlm__wt__independent_exal_m0_relaunch_v1_1p0p0")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R51 = DATA / "authoritative/pricefm_stage_r51_exal_m0_authority_freeze_20260811"
PREP = DATA / "authoritative/pricefm_stage_r52_r53_exal_m0_launch_prep_20260811"
GRID = DATA / "experiment_grids/pricefm_stage_r53_exal_m0_full_surface_20260811"
RUNS = DATA / "runs/pricefm_stage_r53_exal_m0_full_surface_20260811"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
M0_MODE = "m0_v_collapsed_support_logit"
EXPECTED_EXDQLM_HEAD = "10ca8e356ff445f600c4eee15f36db8a69330016"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--article-repo", type=Path, default=ARTICLE_REPO)
    p.add_argument("--exdqlm-repo", type=Path, default=EXDQLM_REPO)
    p.add_argument("--stage-r51-dir", type=Path, default=R51)
    p.add_argument("--output-dir", type=Path, default=PREP)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--chains", type=int, default=4)
    p.add_argument("--n-burn", type=int, default=500)
    p.add_argument("--n-mcmc", type=int, default=500)
    p.add_argument("--expected-targets", type=int, default=87)
    p.add_argument("--expected-exdqlm-head", default=EXPECTED_EXDQLM_HEAD)
    p.add_argument("--vb-parity-relative-tolerance", type=float, default=0.02)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def git_head(path: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
    ).strip()


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            h.update(block)
    return h.hexdigest()


def prepare_dir(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(f"Output exists: {path}")
    path.mkdir(parents=True, exist_ok=True)


def slug(region: str, fold: int) -> str:
    return f"{str(region).lower()}_f{int(fold)}"


def tau_label(tau: float) -> str:
    return f"tau{int(round(float(tau) * 100)):02d}"


def job_seed(case_index: int, tau_index: int, chain: int) -> int:
    return 202608110 + case_index * 1000 + tau_index * 10 + chain


def materialize_adapter_config(target, destination: Path, adapter_dir: Path, exdqlm_repo: Path):
    payload = yaml.safe_load(Path(target.source_config).read_text())
    cfg = payload["pricefm_desn_smoke"]
    cfg["package_path"] = str(exdqlm_repo.resolve())
    cfg["quantiles"] = list(TAUS)
    cfg["adapter"]["output_dir"] = str(adapter_dir.resolve())
    cfg["run"]["output_dir"] = str((adapter_dir.parent / "unused_vb_model").resolve())
    cfg.setdefault("artifact_hygiene", {})["enabled"] = False
    destination.write_text(yaml.safe_dump(payload, sort_keys=False))


def run(args) -> dict:
    if args.chains < 4 or args.n_burn < 500 or args.n_mcmc < 500:
        raise ValueError("R53 requires at least four chains and 500 warmup/retained draws")
    engine_head = git_head(args.exdqlm_repo)
    if engine_head != args.expected_exdqlm_head:
        raise RuntimeError(f"Collapsed-M0 engine drifted: {engine_head}")

    out, grid, runs = args.output_dir.resolve(), args.grid_dir.resolve(), args.run_dir.resolve()
    prepare_dir(out, args.force)
    prepare_dir(grid, args.force)
    for path in (grid / "adapter_configs", grid / "case_configs", grid / "chain_configs", runs / "cases"):
        path.mkdir(parents=True, exist_ok=True)

    targets_path = args.stage_r51_dir / "pricefm_stage_r51_exal_target_ledger.csv"
    freeze_path = args.stage_r51_dir / "pricefm_stage_r51_case_specification_freeze.csv"
    r51_summary_path = args.stage_r51_dir / "summary.json"
    targets = pd.read_csv(targets_path).sort_values(["region", "fold"]).reset_index(drop=True)
    specs = pd.read_csv(freeze_path)
    r51_summary = json.loads(r51_summary_path.read_text())
    if len(targets) != args.expected_targets or not targets.m0_eligible.astype(bool).all():
        raise RuntimeError(f"R51 target contract changed: {len(targets)} rows")
    if r51_summary.get("exdqlm_head") != engine_head:
        raise RuntimeError("R51 and R52 exdqlm commits differ")

    python_exe = args.artifact_repo / "application/data_local/pricefm/venv/bin/python"
    adapter_builder = args.artifact_repo / "application/scripts/pricefm/07_build_desn_direct_horizon_adapter.py"
    case_runner = Path(__file__).with_name("183_prepare_pricefm_stage_r52_exal_m0_case.R")
    chain_runner = Path(__file__).with_name("184_run_pricefm_stage_r53_exal_m0_chain.R")
    launcher = Path(__file__).with_name("185_launch_pricefm_stage_r53_exal_m0.py")
    closeout = Path(__file__).with_name("186_closeout_pricefm_stage_r54_exal_m0.R")
    required = [python_exe, adapter_builder, case_runner, chain_runner, launcher, closeout]
    for path in required:
        if not path.exists():
            raise FileNotFoundError(path)

    case_rows: list[dict] = []
    chain_rows: list[dict] = []
    for case_index, target in enumerate(targets.itertuples(index=False), start=1):
        key = slug(target.region, int(target.fold))
        case_id = f"r52_{key}"
        case_dir = runs / "cases" / case_id
        adapter_dir = case_dir / "adapter"
        adapter_config = grid / "adapter_configs" / f"{case_id}.yaml"
        materialize_adapter_config(target, adapter_config, adapter_dir, args.exdqlm_repo)

        spec = specs[
            specs.region.eq(target.region)
            & specs.fold.eq(int(target.fold))
            & specs.experiment_id.eq(target.experiment_id)
        ]
        if len(spec) != 1:
            raise RuntimeError(f"Missing unique frozen spec for {target.region}/fold={target.fold}")
        case_config = grid / "case_configs" / f"{case_id}.yaml"
        case_payload = {
            "pricefm_stage_r52_case": {
                "id": case_id, "region": str(target.region), "fold": int(target.fold),
                "experiment_id": str(target.experiment_id), "method_id": str(target.qdesn_method_id),
                "taus": list(TAUS), "selection_unit": "region_fold_seven_quantile_bundle",
                "adapter_config": str(adapter_config), "adapter_dir": str(adapter_dir),
                "source_config": str(Path(target.source_config).resolve()),
                "source_adapter_manifest": str(Path(target.source_adapter_manifest).resolve()),
                "source_metric_summary": str(Path(target.source_metric_summary).resolve()),
                "exdqlm_path": str(args.exdqlm_repo.resolve()),
                # Keep the venv entrypoint itself. Resolving its symlink would
                # invoke the system interpreter without the PriceFM packages.
                "python_executable": str(python_exe),
                "adapter_builder": str(adapter_builder.resolve()),
                "output_dir": str(case_dir.resolve()),
                "authority_qdesn_AQL": float(target.qdesn_AQL),
                "cached_pricefm_AQL": float(target.pricefm_AQL),
                "authority_validation_AQL": None if pd.isna(target.lineage_val_AQL) else float(target.lineage_val_AQL),
                "lineage_status": str(target.lineage_status),
                "vb_parity_relative_tolerance": float(args.vb_parity_relative_tolerance),
                "seed": int(spec.iloc[0].seed),
                "core_update_mode": M0_MODE,
                "registry_mutation_authorized": False,
                "article_mutation_authorized": False,
            }
        }
        case_config.write_text(yaml.safe_dump(case_payload, sort_keys=False))
        case_rows.append({
            "id": case_id, "region": target.region, "fold": int(target.fold),
            "experiment_id": target.experiment_id, "lineage_status": target.lineage_status,
            "config": str(case_config), "adapter_config": str(adapter_config),
            "adapter_dir": str(adapter_dir), "output_dir": str(case_dir),
            "status": "prepared_not_launched",
        })

        for tau_index, tau in enumerate(TAUS, start=1):
            for chain in range(1, args.chains + 1):
                jid = f"r53_{key}_{tau_label(tau)}_chain{chain}"
                job_out = runs / "chains" / jid
                chain_config = grid / "chain_configs" / f"{jid}.yaml"
                chain_payload = {
                    "pricefm_stage_r53_m0": {
                        "id": jid, "case_id": case_id, "region": str(target.region),
                        "fold": int(target.fold), "tau": float(tau), "chain": int(chain),
                        "seed": job_seed(case_index, tau_index, chain),
                        "case_config": str(case_config),
                        "case_summary": str(case_dir / "case_summary.json"),
                        "adapter_dir": str(adapter_dir),
                        "init_path": str(case_dir / "initialization" / f"{tau_label(tau)}_init.rds"),
                        "exdqlm_path": str(args.exdqlm_repo.resolve()),
                        "output_dir": str(job_out), "likelihood_family": "exal",
                        "prior_family": "rhs_ns", "n_burn": int(args.n_burn),
                        "n_mcmc": int(args.n_mcmc), "thin": 1,
                        "core_update_mode": M0_MODE, "width_gamma": 4.0,
                        "max_steps_out": 100, "max_shrink": 1000,
                        "core_extra_passes": 0, "init_from_vb": False,
                        "store_latent_draws": False, "store_rhs_draws": True,
                        "registry_mutation_authorized": False,
                        "article_mutation_authorized": False,
                    }
                }
                chain_config.write_text(yaml.safe_dump(chain_payload, sort_keys=False))
                chain_rows.append({
                    "id": jid, "case_id": case_id, "region": target.region,
                    "fold": int(target.fold), "tau": float(tau), "chain": chain,
                    "seed": job_seed(case_index, tau_index, chain),
                    "n_burn": int(args.n_burn), "n_mcmc": int(args.n_mcmc),
                    "config": str(chain_config), "output_dir": str(job_out),
                    "status": "prepared_not_launched",
                })

    cases = pd.DataFrame(case_rows)
    chains = pd.DataFrame(chain_rows)
    cases.to_csv(out / "pricefm_stage_r52_case_manifest.csv", index=False)
    chains.to_csv(out / "pricefm_stage_r53_launch_manifest.csv", index=False)

    expected_jobs = args.expected_targets * len(TAUS) * args.chains
    gates = pd.DataFrame([
        {"gate": "r51_complete", "passed": r51_summary.get("status") == "completed_authority_freeze", "observed": r51_summary.get("status")},
        {"gate": "case_specific_targets", "passed": len(cases) == args.expected_targets, "observed": len(cases)},
        {"gate": "seven_quantiles_per_case", "passed": chains.groupby("case_id").tau.nunique().eq(7).all(), "observed": int(chains.tau.nunique())},
        {"gate": "four_chains_per_case_tau", "passed": chains.groupby(["case_id", "tau"]).chain.nunique().eq(args.chains).all(), "observed": args.chains},
        {"gate": "full_job_surface", "passed": len(chains) == expected_jobs, "observed": len(chains)},
        {"gate": "collapsed_m0_pinned", "passed": engine_head == args.expected_exdqlm_head, "observed": engine_head},
        {"gate": "al_rows_excluded", "passed": not targets.qdesn_method_id.astype(str).str.contains("_al_").any(), "observed": "exAL only"},
        {"gate": "test_not_in_selection", "passed": targets.selection_role.eq("validation_only").all(), "observed": "validation only"},
        {"gate": "registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    gates.to_csv(out / "pricefm_stage_r52_r53_prelaunch_gates.csv", index=False)
    if not gates.passed.all():
        raise RuntimeError("Stage-R52/R53 prelaunch gates failed")

    launch_config = {
        "pricefm_stage_r53_launch": {
            "run_tag": "pricefm_stage_r53_exal_m0_full_surface_20260811",
            "case_manifest": str(out / "pricefm_stage_r52_case_manifest.csv"),
            "chain_manifest": str(out / "pricefm_stage_r53_launch_manifest.csv"),
            "case_runner": str(case_runner.resolve()), "chain_runner": str(chain_runner.resolve()),
            "jobs": 24, "cpu_policy": "unused_distinct_physical_cores",
            "one_process_per_physical_core": True, "threads_per_process": 1,
            "resume": True, "phases": ["case_replay", "m0_chains"],
            "launch_authorized_by_user": True,
            "registry_mutation_authorized": False, "article_mutation_authorized": False,
        }
    }
    launch_yaml = out / "pricefm_stage_r53_launch.yaml"
    launch_yaml.write_text(yaml.safe_dump(launch_config, sort_keys=False))

    sources = [
        targets_path, freeze_path, r51_summary_path, Path(__file__).resolve(),
        case_runner, chain_runner, launcher, closeout,
        args.exdqlm_repo / "R/exal_mcmc_collapsed_scale_shape.R",
        args.exdqlm_repo / "R/exal_mcmc_fit.R",
    ]
    pd.DataFrame([
        {"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in sources
    ]).to_csv(out / "source_manifest.csv", index=False)

    summary = {
        "status": "materialized_ready_to_launch", "article_head": git_head(args.article_repo),
        "exdqlm_head": engine_head, "cases": len(cases), "quantiles": len(TAUS),
        "chains_per_quantile": args.chains, "chain_jobs": len(chains),
        "n_burn": args.n_burn, "n_mcmc": args.n_mcmc,
        "core_update_mode": M0_MODE, "launch_yaml": str(launch_yaml),
        "launch_authorized": True, "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    write_json(out / "summary.json", summary)
    (out / "pricefm_stage_r52_r53_exal_m0_launch_prep_report.md").write_text(
        "# PriceFM Stage-R52/R53 exAL collapsed-M0 launch prep\n\n"
        f"The campaign contains {len(cases)} independent region/fold designs, seven paper "
        f"quantiles, four chains, and {len(chains)} production chain jobs. Each case rebuilds "
        "its frozen adapter, verifies historical hashes, regenerates AL-to-exAL VB starts, and "
        "then runs the opt-in collapsed M0 transition.\n\n"
        "Selection is by the complete seven-quantile validation bundle. Test metrics are read "
        "only by the later closeout. Registry and article mutation remain blocked.\n"
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
