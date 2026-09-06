#!/usr/bin/env python3
"""Prepare the fixed-origin Part 2 bridge forecast chain.

The chain consumes the verified Part 2 Normal RHS/VB winner and launches only
forecast/adaptation jobs. It does not rerun the ridge or RHS screens.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shlex
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_WINNER = (
    "normal_part2_rhs_top16_part2ridge_targeted_0016_disc_covars__D1_n2500__"
    "a080_r070__reftau1e00_disctau1em03"
)
DEFAULT_BASE = "part2ridge_targeted_0016_disc_covars__D1_n2500__a080_r070"
DEFAULT_SOURCE_ROOT = os.environ.get(
    "APP_GLOFAS_JEREZ_SOURCE_ROOT",
    "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_part2_rhs_jerez_20260904",
)
DEFAULT_BASE_CONFIG = (
    f"{DEFAULT_SOURCE_ROOT}/local_trackers/runtime_configs/"
    "glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml"
)
DEFAULT_RHS_RUNTIME = (
    f"{DEFAULT_SOURCE_ROOT}/local_trackers/runtime_configs/"
    "glofas_normal_part2_rhs_top50_jerez_recovery_20260904"
)
QUANTILES = [0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95]


def repo_root() -> Path:
    here = Path(__file__).resolve()
    return here.parents[2]


def rel(path: Path, root: Path) -> str:
    try:
        return str(path.resolve().relative_to(root.resolve()))
    except ValueError:
        return str(path)


def qslug(tau: float) -> str:
    return f"q{tau:.2f}".replace(".", "p")


def safe_session(label: str) -> str:
    out = "".join(ch if ch.isalnum() or ch == "_" else "_" for ch in label)
    return out[:180]


def quote_cmd(parts: list[str]) -> str:
    return " ".join(shlex.quote(str(p)) for p in parts)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_csv(path: Path, rows: list[dict], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row.get(k, "") for k in fieldnames})


def normal_job(
    *,
    job_id: str,
    root: Path,
    session_label: str,
    base_config: str,
    rhs_runtime_root: str,
    rhs_candidate_id: str,
    candidate_id: str,
    method: str,
    run_label: str,
    deps: list[str],
    horizon_days: int,
    origin_date: str,
    forecast_mode: str,
    n_draws: int,
    seed: int,
    forecast_backend: str,
) -> dict:
    out_root = root / job_id
    cmd = [
        "Rscript",
        "application/scripts/65_run_glofas_part2_normal_bridge_forecast.R",
        "--base_config",
        base_config,
        "--rhs_runtime_root",
        rhs_runtime_root,
        "--runtime_root",
        rel(out_root, repo_root()),
        "--run_label",
        run_label,
        "--method",
        method,
        "--rhs_candidate_id",
        rhs_candidate_id,
        "--candidate_id",
        candidate_id,
        "--horizon_days",
        str(horizon_days),
        "--origin_date",
        origin_date,
        "--forecast_mode",
        forecast_mode,
        "--n_draws",
        str(n_draws),
        "--seed",
        str(seed),
        "--retain_draws",
        "false",
        "--forecast_backend",
        forecast_backend,
        "--strict_winner",
        "true",
    ]
    return job_row(job_id, "normal", method, "", deps, out_root, run_label, session_label, quote_cmd(cmd))


def quantile_job(
    *,
    job_id: str,
    root: Path,
    session_label: str,
    base_config: str,
    rhs_runtime_root: str,
    rhs_candidate_id: str,
    candidate_id: str,
    model_family: str,
    tau_arg: str,
    deps: list[str],
    run_label: str,
    horizon_days: int,
    origin_date: str,
    max_iter: int,
    min_iter: int,
    tol: float,
    freeze_beta_warmup_iters: int,
    min_beta_updates: int,
    forecast_backend: str,
    init_fit_path: str = "",
    init_fit_paths: str = "",
) -> dict:
    out_root = root / job_id
    progress = out_root / "logs" / f"{run_label}_progress.csv"
    cmd = [
        "Rscript",
        "application/scripts/66_run_glofas_part2_quantile_bridge_forecast.R",
        "--base_config",
        base_config,
        "--rhs_runtime_root",
        rhs_runtime_root,
        "--runtime_root",
        rel(out_root, repo_root()),
        "--run_label",
        run_label,
        "--model_family",
        model_family,
        "--quantile",
        tau_arg,
        "--rhs_candidate_id",
        rhs_candidate_id,
        "--candidate_id",
        candidate_id,
        "--horizon_days",
        str(horizon_days),
        "--origin_date",
        origin_date,
        "--max_iter",
        str(max_iter),
        "--min_iter",
        str(min_iter),
        "--tol",
        str(tol),
        "--progress_every",
        "1",
        "--freeze_beta_warmup_iters",
        str(freeze_beta_warmup_iters),
        "--min_beta_updates",
        str(min_beta_updates),
        "--progress_path",
        rel(progress, repo_root()),
        "--forecast_backend",
        forecast_backend,
        "--strict_winner",
        "true",
    ]
    if init_fit_path:
        cmd.extend(["--init_fit_path", init_fit_path])
    if init_fit_paths:
        cmd.extend(["--init_fit_paths", init_fit_paths])
    return job_row(job_id, "quantile", model_family, tau_arg, deps, out_root, run_label, session_label, quote_cmd(cmd))


def job_row(
    job_id: str,
    phase: str,
    model_family: str,
    tau_arg: str,
    deps: list[str],
    output_root: Path,
    run_label: str,
    session_label: str,
    command: str,
) -> dict:
    root = output_root.parent
    status_dir = root / "status"
    log_path = root / "logs" / f"{job_id}.log"
    fit_suffix = "_fit.rds" if phase == "quantile" else "_retained_fit_view.rds"
    return {
        "job_id": job_id,
        "phase": phase,
        "model_family": model_family,
        "tau": tau_arg,
        "dependencies": "|".join(deps),
        "run_label": run_label,
        "output_root": rel(output_root, repo_root()),
        "fit_path": rel(output_root / "objects" / f"{run_label}{fit_suffix}", repo_root()),
        "progress_path": rel(output_root / "logs" / f"{run_label}_progress.csv", repo_root()),
        "status_running_path": rel(status_dir / f"{job_id}.running", repo_root()),
        "status_done_path": rel(status_dir / f"{job_id}.done", repo_root()),
        "status_failed_path": rel(status_dir / f"{job_id}.failed", repo_root()),
        "log_path": rel(log_path, repo_root()),
        "tmux_session": safe_session(f"{session_label}__{job_id}"),
        "command": command,
    }


def build_jobs(args: argparse.Namespace, root: Path) -> list[dict]:
    base_config = args.base_config
    rhs_runtime_root = args.rhs_runtime_root
    rhs_id = args.rhs_candidate_id
    candidate_id = args.candidate_id
    jobs: list[dict] = []

    jobs.append(
        normal_job(
            job_id="normal_ridge",
            root=root,
            session_label=args.session_label,
            base_config=base_config,
            rhs_runtime_root=rhs_runtime_root,
            rhs_candidate_id=rhs_id,
            candidate_id=candidate_id,
            method="ridge",
            run_label="part2_normal_ridge_bridge_forecast",
            deps=[],
            horizon_days=args.horizon_days,
            origin_date=args.origin_date,
            forecast_mode="plugin_mean_recursive",
            n_draws=0,
            seed=args.seed,
            forecast_backend=args.forecast_backend,
        )
    )
    jobs.append(
        normal_job(
            job_id="normal_rhs_vb",
            root=root,
            session_label=args.session_label,
            base_config=base_config,
            rhs_runtime_root=rhs_runtime_root,
            rhs_candidate_id=rhs_id,
            candidate_id=candidate_id,
            method="rhs",
            run_label="part2_normal_rhs_vb_bridge_forecast",
            deps=["normal_ridge"],
            horizon_days=args.horizon_days,
            origin_date=args.origin_date,
            forecast_mode="draw_recursive",
            n_draws=args.normal_rhs_draws,
            seed=args.seed + 1,
            forecast_backend=args.forecast_backend,
        )
    )

    al_deps = {
        0.50: ["normal_rhs_vb"],
        0.35: ["independent_al_q0p50"],
        0.20: ["independent_al_q0p35"],
        0.05: ["independent_al_q0p20"],
        0.65: ["independent_al_q0p50"],
        0.80: ["independent_al_q0p65"],
        0.95: ["independent_al_q0p80"],
    }
    for tau in [0.50, 0.35, 0.20, 0.05, 0.65, 0.80, 0.95]:
        slug = qslug(tau)
        jobs.append(
            quantile_job(
                job_id=f"independent_al_{slug}",
                root=root,
                session_label=args.session_label,
                base_config=base_config,
                rhs_runtime_root=rhs_runtime_root,
                rhs_candidate_id=rhs_id,
                candidate_id=candidate_id,
                model_family="independent_al",
                tau_arg=f"{tau:.2f}",
                deps=al_deps[tau],
                run_label=f"part2_independent_al_{slug}_bridge_forecast",
                horizon_days=args.horizon_days,
                origin_date=args.origin_date,
                max_iter=args.quantile_max_iter,
                min_iter=args.quantile_min_iter,
                tol=args.quantile_tol,
                freeze_beta_warmup_iters=args.freeze_beta_warmup_iters,
                min_beta_updates=args.min_beta_updates,
                forecast_backend=args.forecast_backend,
            )
        )

    def al_fit(tau: float) -> str:
        slug = qslug(tau)
        return rel(root / f"independent_al_{slug}" / "objects" / f"part2_independent_al_{slug}_bridge_forecast_fit.rds", repo_root())

    def exal_fit(tau: float) -> str:
        slug = qslug(tau)
        return rel(root / f"independent_exal_{slug}" / "objects" / f"part2_independent_exal_{slug}_bridge_forecast_fit.rds", repo_root())

    for tau in QUANTILES:
        slug = qslug(tau)
        jobs.append(
            quantile_job(
                job_id=f"independent_exal_{slug}",
                root=root,
                session_label=args.session_label,
                base_config=base_config,
                rhs_runtime_root=rhs_runtime_root,
                rhs_candidate_id=rhs_id,
                candidate_id=candidate_id,
                model_family="independent_exal",
                tau_arg=f"{tau:.2f}",
                deps=[f"independent_al_{slug}"],
                run_label=f"part2_independent_exal_{slug}_bridge_forecast",
                horizon_days=args.horizon_days,
                origin_date=args.origin_date,
                max_iter=args.quantile_max_iter,
                min_iter=args.quantile_min_iter,
                tol=args.quantile_tol,
                freeze_beta_warmup_iters=args.freeze_beta_warmup_iters,
                min_beta_updates=args.min_beta_updates,
                forecast_backend=args.forecast_backend,
                init_fit_path=al_fit(tau),
            )
        )

    all_al = [f"independent_al_{qslug(t)}" for t in QUANTILES]
    all_exal = [f"independent_exal_{qslug(t)}" for t in QUANTILES]
    al_paths = ",".join(al_fit(t) for t in QUANTILES)
    exal_paths = ",".join(exal_fit(t) for t in QUANTILES)

    jobs.append(
        quantile_job(
            job_id="joint_al_all7",
            root=root,
            session_label=args.session_label,
            base_config=base_config,
            rhs_runtime_root=rhs_runtime_root,
            rhs_candidate_id=rhs_id,
            candidate_id=candidate_id,
            model_family="joint_al",
            tau_arg="all7",
            deps=all_al,
            run_label="part2_joint_al_all7_bridge_forecast",
            horizon_days=args.horizon_days,
            origin_date=args.origin_date,
            max_iter=args.quantile_max_iter,
            min_iter=args.quantile_min_iter,
            tol=args.quantile_tol,
            freeze_beta_warmup_iters=args.freeze_beta_warmup_iters,
            min_beta_updates=args.min_beta_updates,
            forecast_backend=args.forecast_backend,
            init_fit_paths=al_paths,
        )
    )
    jobs.append(
        quantile_job(
            job_id="joint_exal_all7",
            root=root,
            session_label=args.session_label,
            base_config=base_config,
            rhs_runtime_root=rhs_runtime_root,
            rhs_candidate_id=rhs_id,
            candidate_id=candidate_id,
            model_family="joint_exal",
            tau_arg="all7",
            deps=["joint_al_all7"] + all_exal,
            run_label="part2_joint_exal_all7_bridge_forecast",
            horizon_days=args.horizon_days,
            origin_date=args.origin_date,
            max_iter=args.quantile_max_iter,
            min_iter=args.quantile_min_iter,
            tol=args.quantile_tol,
            freeze_beta_warmup_iters=args.freeze_beta_warmup_iters,
            min_beta_updates=args.min_beta_updates,
            forecast_backend=args.forecast_backend,
            init_fit_paths=exal_paths,
        )
    )
    for idx, job in enumerate(jobs, start=1):
        job["job_index"] = idx
    return jobs


def write_artifact_lists(root: Path) -> None:
    rows = []
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        if path.name in {"artifact_manifest.csv", "artifact_file_list.csv"}:
            continue
        st = path.stat()
        rows.append(
            {
                "relative_path": rel(path, root),
                "repo_relative_path": rel(path, repo_root()),
                "size_bytes": st.st_size,
                "sha256": sha256_file(path),
                "mtime_utc": datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat(),
            }
        )
    write_csv(root / "tables" / "artifact_file_list.csv", rows, ["relative_path", "repo_relative_path", "size_bytes", "sha256", "mtime_utc"])
    manifest = [
        {
            "artifact_group": Path(r["relative_path"]).parts[0] if Path(r["relative_path"]).parts else ".",
            "path": r["relative_path"],
            "size_bytes": r["size_bytes"],
            "sha256": r["sha256"],
        }
        for r in rows
    ]
    write_csv(root / "tables" / "artifact_manifest.csv", manifest, ["artifact_group", "path", "size_bytes", "sha256"])


def write_plan(root: Path, args: argparse.Namespace, jobs: list[dict]) -> None:
    lines = [
        "# Jerez Part 2 Bridge Forecast Chain Plan",
        "",
        f"Prepared UTC: {datetime.now(timezone.utc).isoformat()}",
        f"Authoritative RHS runtime: `{args.rhs_runtime_root}`",
        f"Verified RHS winner: `{args.rhs_candidate_id}`",
        f"Base ridge candidate: `{args.candidate_id}`",
        "",
        "## Contract",
        "",
        "- Target is observed discrepancy: retrospective GloFAS minus USGS.",
        "- Corrected path is retrospective GloFAS minus predicted discrepancy.",
        "- Winner inputs are discrepancy lags 1:360 and realized PRISM/ERA5 ppt/soil lags 0:180.",
        "- Direct USGS/GloFAS lag inputs, rolling origins, CEFS, forecast ensembles, and synthesis are disabled.",
        "- Normal Ridge/RHS fits are retained from the verified Part 2 runtime; only fixed-origin forecasts are run.",
        "- This retained-fit launcher is diagnostic-only for Dec25 planning; final Dec25 production refits use the 380-series final-refit scripts.",
        "- Normal RHS uncertainty uses posterior coefficient draws and Normal observation-scale draws from the retained compact fit.",
        "",
        "## Dependency Order",
        "",
        "| # | job_id | model_family | tau | dependencies |",
        "|---:|---|---|---|---|",
    ]
    for job in jobs:
        lines.append(
            f"| {job['job_index']} | `{job['job_id']}` | `{job['model_family']}` | `{job['tau']}` | `{job['dependencies'] or 'none'}` |"
        )
    lines.extend(
        [
            "",
            "## Reproducibility",
            "",
            f"- Runtime root: `{rel(root, repo_root())}`",
            f"- Worker cap: {args.workers}",
            "- Thread guards: OMP/OPENBLAS/MKL/VECLIB/NUMEXPR all set to 1 in the scheduler.",
            "- Health tables and artifact manifests are refreshed by the checker and scheduler.",
        ]
    )
    path = root / "configs" / "part2_bridge_forecast_chain_plan.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base_config", default=DEFAULT_BASE_CONFIG)
    parser.add_argument("--rhs_runtime_root", default=DEFAULT_RHS_RUNTIME)
    parser.add_argument("--runtime_root", default="local_trackers/runtime_configs/glofas_part2_bridge_forecast_chain_final_dec25_2022_jerez_20260905")
    parser.add_argument("--session_label", default="glofas_part2_bridge_forecast_final_dec25_2022_jerez_20260905")
    parser.add_argument("--rhs_candidate_id", default=DEFAULT_WINNER)
    parser.add_argument("--candidate_id", default=DEFAULT_BASE)
    parser.add_argument("--workers", type=int, default=20)
    parser.add_argument("--horizon_days", type=int, default=30)
    parser.add_argument("--origin_date", default="2022-12-25")
    parser.add_argument("--allow_non_dec25_diagnostic", action="store_true")
    parser.add_argument("--normal_rhs_draws", type=int, default=500)
    parser.add_argument("--seed", type=int, default=20260904)
    parser.add_argument("--forecast_backend", choices=["auto", "cpp", "r"], default="auto")
    parser.add_argument("--quantile_max_iter", type=int, default=100)
    parser.add_argument("--quantile_min_iter", type=int, default=30)
    parser.add_argument("--quantile_tol", type=float, default=0.01)
    parser.add_argument("--freeze_beta_warmup_iters", type=int, default=20)
    parser.add_argument("--min_beta_updates", type=int, default=30)
    args = parser.parse_args()

    if args.origin_date != "2022-12-25" and not args.allow_non_dec25_diagnostic:
        raise SystemExit("Part 2 Dec25 workflows require --origin_date 2022-12-25; pass --allow_non_dec25_diagnostic only to label old artifacts.")
    if args.horizon_days != 30:
        raise SystemExit("Part 2 Dec25 workflows require --horizon_days 30.")

    root = (repo_root() / args.runtime_root).resolve() if not os.path.isabs(args.runtime_root) else Path(args.runtime_root).resolve()
    for sub in ["configs", "tables", "logs", "status"]:
        (root / sub).mkdir(parents=True, exist_ok=True)

    jobs = build_jobs(args, root)
    fields = [
        "job_index",
        "job_id",
        "phase",
        "model_family",
        "tau",
        "dependencies",
        "run_label",
        "output_root",
        "fit_path",
        "progress_path",
        "status_running_path",
        "status_done_path",
        "status_failed_path",
        "log_path",
        "tmux_session",
        "command",
    ]
    write_csv(root / "tables" / "part2_bridge_forecast_job_manifest.csv", jobs, fields)
    config = {
        "runtime_root": rel(root, repo_root()),
        "authoritative_rhs_runtime": args.rhs_runtime_root,
        "verified_rhs_candidate_id": args.rhs_candidate_id,
        "base_ridge_candidate_id": args.candidate_id,
        "base_config": args.base_config,
        "session_label": args.session_label,
        "workers": args.workers,
        "horizon_days": args.horizon_days,
        "origin_date": args.origin_date,
        "normal_rhs_draws": args.normal_rhs_draws,
        "quantile_controls": {
            "max_iter": args.quantile_max_iter,
            "min_iter": args.quantile_min_iter,
            "tol": args.quantile_tol,
            "progress_every": 1,
            "freeze_beta_warmup_iters": args.freeze_beta_warmup_iters,
            "min_beta_updates": args.min_beta_updates,
        },
        "prepared_utc": datetime.now(timezone.utc).isoformat(),
        "no_synthesis": True,
    }
    (root / "configs" / "part2_bridge_forecast_chain_config.json").write_text(json.dumps(config, indent=2, sort_keys=True) + "\n")
    write_plan(root, args, jobs)
    write_artifact_lists(root)

    print(f"Prepared Part 2 bridge forecast chain: {rel(root, repo_root())}")
    print(f"Jobs: {len(jobs)}")
    print(f"Manifest: {rel(root / 'tables' / 'part2_bridge_forecast_job_manifest.csv', repo_root())}")
    print(f"Plan: {rel(root / 'configs' / 'part2_bridge_forecast_chain_plan.md', repo_root())}")
    print(f"Launch with: python3 application/scripts/69_launch_glofas_part2_bridge_forecast_chain.py --runtime_root {shlex.quote(rel(root, repo_root()))} --workers {args.workers}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
