#!/usr/bin/env python3
"""Prepare the Dec25 GloFAS Part 2/3 final-refit DAG without launching it."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shlex
from datetime import datetime, timezone
from pathlib import Path


CONTRACT = {
    "cutoff_id": "dec25_2022",
    "train_end": "2022-12-25",
    "origin_date": "2022-12-25",
    "forecast_start": "2022-12-26",
    "forecast_end": "2023-01-24",
    "horizon_days": 30,
    "horizons": list(range(1, 31)),
    "part2_final_train_rows": 12495,
    "part3_final_dates": 12495,
    "part3_final_stacked_rows": 24990,
    "discrepancy_sign": "retrospective_glofas_minus_usgs",
    "prohibited": [
        "inferred_origin",
        "rolling_origin",
        "CEFS",
        "forecast_ensemble_substitution",
        "crossing_fix",
        "synthesis",
        "short_horizon",
        "part4",
    ],
}
QUANTILES = ("0.05", "0.20", "0.35", "0.50", "0.65", "0.80", "0.95")
AL_ORDER = ("0.50", "0.35", "0.65", "0.20", "0.80", "0.05", "0.95")
DEFAULT_SOURCE_ROOT = os.environ.get(
    "APP_GLOFAS_JEREZ_SOURCE_ROOT",
    "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_part2_rhs_jerez_20260904",
)
DEFAULT_PART3_SOURCE_ROOT = os.environ.get(
    "APP_GLOFAS_JEREZ_PART3_SOURCE_ROOT",
    "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_part3_quantile_forecast_jerez_20260904",
)
DEFAULT_BASE_CONFIG = (
    f"{DEFAULT_SOURCE_ROOT}/local_trackers/runtime_configs/"
    "glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml"
)
DEFAULT_PART2_RHS_RUNTIME = (
    f"{DEFAULT_SOURCE_ROOT}/local_trackers/runtime_configs/"
    "glofas_normal_part2_rhs_top50_jerez_recovery_20260904"
)
DEFAULT_PART2_OLD_QUANTILE_RUNTIME = (
    f"{DEFAULT_SOURCE_ROOT}/local_trackers/runtime_configs/"
    "glofas_part2_bridge_forecast_chain_jerez_20260904"
)
DEFAULT_PART3_OLD_QUANTILE_RUNTIME = (
    f"{DEFAULT_PART3_SOURCE_ROOT}/local_trackers/runtime_configs/"
    "glofas_part3_quantile_forecast_jerez_20260904"
)
DEFAULT_PART3_WINNER_MANIFEST = (
    f"{DEFAULT_SOURCE_ROOT}/local_trackers/runtime_configs/"
    "glofas_part3_normal_historical_jerez_20260904/configs/part3_frozen_g1_g2_winners.csv"
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def rel(path: Path, root: Path) -> str:
    try:
        return str(path.resolve().relative_to(root.resolve()))
    except ValueError:
        return str(path)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def shell_join(parts: list[str]) -> str:
    return " ".join(shlex.quote(str(part)) for part in parts)


def write_csv(path: Path, rows: list[dict], fields: list[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = fields or list(rows[0])
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fields})


def qslug(tau: str) -> str:
    return "q" + tau.replace(".", "p")


def status_path(runtime: Path, job_id: str, state: str) -> str:
    return rel(runtime / "status" / f"{job_id}.{state}", repo_root())


def add_job(rows: list[dict], runtime: Path, args: argparse.Namespace, *, job_id: str, part: str,
            stage: str, model_family: str = "", tau: str = "", likelihood: str = "",
            fit_structure: str = "", deps: tuple[str, ...] = (), command: list[str] | None = None,
            role: str = "", initializer_policy: str = "") -> None:
    command = command or []
    rows.append({
        "job_index": len(rows) + 1,
        "job_id": job_id,
        "part": part,
        "stage": stage,
        "model_family": model_family,
        "tau": tau,
        "likelihood": likelihood,
        "fit_structure": fit_structure,
        "dependencies": "|".join(deps),
        "thread_slots": 1,
        "worker_script": command[1] if len(command) > 1 and command[0] in {"Rscript", "python3"} else "",
        "command_json": json.dumps(command),
        "command": shell_join(command),
        "status_running_path": status_path(runtime, job_id, "running"),
        "status_completed_path": status_path(runtime, job_id, "completed"),
        "status_failed_path": status_path(runtime, job_id, "failed"),
        "output_role": role,
        "initializer_policy": initializer_policy,
        "production_safe_to_launch": "yes_after_tests_and_operator_launch",
    })


def worker_cmd(args: argparse.Namespace, *, part: str, job_id: str, job_type: str,
               model_family: str = "", tau: str = "", likelihood: str = "",
               fit_structure: str = "", fit_job_id: str = "", init_fit_job_ids: str = "",
               method: str = "") -> list[str]:
    cmd = [
        "Rscript", "application/scripts/381_run_glofas_dec25_final_refit_job.R",
        "--runtime_root", args.runtime_root,
        "--part", part,
        "--job_id", job_id,
        "--job_type", job_type,
        "--base_config", args.base_config,
        "--origin_date", CONTRACT["origin_date"],
        "--horizon_days", str(CONTRACT["horizon_days"]),
        "--max_iter", str(args.max_iter),
        "--min_iter", str(args.min_iter),
        "--tol", str(args.tol),
        "--normal_draws", str(args.normal_draws),
        "--forecast_backend", args.forecast_backend,
        "--freeze_beta_warmup_iters", str(args.freeze_beta_warmup_iters),
        "--min_beta_updates", str(args.min_beta_updates),
        "--quantile_route", args.quantile_route,
        "--part2_old_quantile_runtime_root", args.part2_old_quantile_runtime_root,
        "--part3_old_quantile_runtime_root", args.part3_old_quantile_runtime_root,
    ]
    if part == "part2":
        cmd.extend([
            "--rhs_runtime_root", args.part2_rhs_runtime_root,
            "--rhs_candidate_id", args.part2_rhs_candidate_id,
            "--candidate_id", args.part2_candidate_id,
        ])
    if part == "part3":
        cmd.extend(["--winner_manifest", args.part3_winner_manifest])
    for key, value in {
        "--model_family": model_family,
        "--tau": tau,
        "--likelihood": likelihood,
        "--fit_structure": fit_structure,
        "--fit_job_id": fit_job_id,
        "--init_fit_job_ids": init_fit_job_ids,
        "--method": method,
    }.items():
        if value:
            cmd.extend([key, value])
    return cmd


def package_cmd(args: argparse.Namespace, *, part: str, kind: str) -> list[str]:
    return [
        "python3", "application/scripts/382_package_glofas_dec25_final_refit.py",
        "--runtime-root", args.runtime_root,
        "--part", part,
        "--package-kind", kind,
        "--output-dir", args.package_output_dir,
    ]


def init_matrix(args: argparse.Namespace) -> list[dict]:
    rows = []

    def row(part: str, model: str, block: str, source: str, decision: str, reason: str) -> None:
        rows.append({
            "part": part,
            "final_model": model,
            "parameter_block": block,
            "candidate_initializer": source,
            "compatibility_status": "pending_hash_and_objective_audit",
            "planned_decision_rule": decision,
            "required_certifications": "target_sign|feature_order|intercept|geometry|seed|lags|state_transform|standardization|prior|likelihood|quantile|source_sha256",
            "notes": reason,
        })

    for part in ("part2", "part3"):
        row(part, "normal_ridge", "readout", "final_dec25_design_closed_form", "fit_from_final_design", "Ridge ignores beta-freeze controls.")
        row(part, "normal_rhs_vb", "readout_and_rhs", "matching_final_normal_ridge", "required_initializer", "RHS starts from the final Dec25 ridge fit, not an old holdout fit.")
        row(part, "independent_al_q0p50", "readout_rhs_scale_latent", "same-model old q0.50 or final normal_rhs_vb", "choose_best_finite_initial_objective", "Old fits are evidence only until Dec25 design and sign are certified.")
        for tau in ("0.35", "0.20", "0.05", "0.65", "0.80", "0.95"):
            parent = {"0.35": "q0p50", "0.20": "q0p35", "0.05": "q0p20", "0.65": "q0p50", "0.80": "q0p65", "0.95": "q0p80"}[tau]
            row(part, f"independent_al_{qslug(tau)}", "readout_rhs_scale_latent", f"same-model old {qslug(tau)}, final normal_rhs_vb, or final independent_al_{parent}", "choose_best_finite_initial_objective", "Same-quantile old fits allow parallel AL when certified; adjacent final AL remains the sequential fallback route.")
        for tau in QUANTILES:
            row(part, f"independent_exal_{qslug(tau)}", "readout_rhs_scale_gamma_latent", f"final independent_al_{qslug(tau)}", "required_initializer", "Each exAL starts from the same-tau final AL.")
        row(part, "joint_al_all7", "joint_readout_rhs_scale_latent", "all seven final independent AL fits", "required_initializer", "No crossing fix or synthesis is introduced.")
        row(part, "joint_exal_all7", "joint_readout_rhs_scale_gamma_latent", "all seven final independent exAL fits", "required_initializer", "Joint exAL waits for every same-tau exAL fit.")
    return rows


def inventory_rows(args: argparse.Namespace) -> list[dict]:
    return [
        {
            "item": "Part 1 reference final refit and forecast",
            "status": "keep",
            "action": "reuse_as_fixed_reference_evidence",
            "reason": "Already selected, final-refit through 2022-12-25, and forecast on 2022-12-26..2023-01-24.",
        },
        {
            "item": "Part 2 ridge and RHS/VB screens",
            "status": "keep",
            "action": "reuse_for_spec_and_tau_selection_only",
            "reason": "200/200 RHS screen selected the discrepancy geometry and tau0; it is not the final full-data refit.",
        },
        {
            "item": "Part 2 winner geometry",
            "status": "keep",
            "action": "freeze_D1_n2500_alpha0.8_rho0.7_disc_covars_tau0_0.001",
            "reason": "Winner contract is fixed and must keep discrepancy lags plus PPT/soil lags only.",
        },
        {
            "item": "Part 2 old forecasts",
            "status": "replace",
            "action": "label_diagnostic_only_and_reforecast_after_final_refits",
            "reason": "Existing forecast artifacts used an earlier origin and cannot answer the Dec25 contract.",
        },
        {
            "item": "Part 2 final design cache",
            "status": "build",
            "action": "build_once_reuse_by_every_worker",
            "reason": "Must contain exactly 12,495 rows through 2022-12-25 and target GloFAS-USGS.",
        },
        {
            "item": "Part 2 final models",
            "status": "refit",
            "action": "fit_18_final_models_then_18_separate_forecasts",
            "reason": "Final full-data refit is required after selection; reference model is not redundantly refit inside Part 2.",
        },
        {
            "item": "Part 3 old Normal/quantile fits and forecasts",
            "status": "keep_as_initializer_evidence_replace_as_final_results",
            "action": "audit_initializers_then_refit_on_final_dec25_cache",
            "reason": "Old fits are not final Dec25 full-data fits, but may be useful compatible starts.",
        },
        {
            "item": "Part 3 final design cache",
            "status": "build",
            "action": "build_once_reuse_by_every_worker",
            "reason": "Must contain 12,495 dates and 24,990 stacked Normal observations through the immutable cutoff.",
        },
        {
            "item": "Part 3 final models",
            "status": "refit",
            "action": "fit_18_final_models_then_18_separate_forecasts",
            "reason": "Final Normal and quantile bridge fits must share the same Dec25 cutoff and 30-day window.",
        },
        {
            "item": "Crossing fix, synthesis, ensembles, Part 4",
            "status": "do_not_run",
            "action": "forbidden_by_contract",
            "reason": "The requested scientific contract explicitly excludes these steps.",
        },
    ]


def build_jobs(args: argparse.Namespace, runtime: Path) -> list[dict]:
    rows: list[dict] = []
    for part in ("part2", "part3"):
        add_job(
            rows, runtime, args,
            job_id=f"{part}_design_cache",
            part=part,
            stage="design_cache",
            deps=(),
            command=worker_cmd(args, part=part, job_id=f"{part}_design_cache", job_type="design_cache"),
            role="immutable_final_dec25_design_cache",
        )
        add_job(
            rows, runtime, args,
            job_id=f"{part}_fit_normal_ridge",
            part=part,
            stage="fit",
            model_family="normal_ridge",
            deps=(f"{part}_design_cache",),
            command=worker_cmd(args, part=part, job_id=f"{part}_fit_normal_ridge", job_type="fit", model_family="normal_ridge"),
            role="final_dec25_closed_form_normal_ridge_fit",
            initializer_policy="cold_final_design_closed_form",
        )
        add_job(
            rows, runtime, args,
            job_id=f"{part}_fit_normal_rhs_vb",
            part=part,
            stage="fit",
            model_family="normal_rhs_vb",
            deps=(f"{part}_fit_normal_ridge",),
            command=worker_cmd(args, part=part, job_id=f"{part}_fit_normal_rhs_vb", job_type="fit", model_family="normal_rhs_vb", init_fit_job_ids=f"{part}_fit_normal_ridge"),
            role="final_dec25_normal_rhs_vb_fit",
            initializer_policy="final_dec25_normal_ridge",
        )
        add_job(
            rows, runtime, args,
            job_id=f"{part}_initializer_audit",
            part=part,
            stage="initializer_audit",
            deps=(f"{part}_fit_normal_rhs_vb",),
            command=worker_cmd(args, part=part, job_id=f"{part}_initializer_audit", job_type="initializer_audit"),
            role="certified_same_tau_quantile_initializer_audit",
            initializer_policy="same_tau_old_fit_or_final_normal_rhs_best_objective",
        )
        add_job(
            rows, runtime, args,
            job_id=f"{part}_forecast_normal_ridge",
            part=part,
            stage="forecast",
            model_family="normal_ridge",
            deps=(f"{part}_fit_normal_ridge",),
            command=worker_cmd(args, part=part, job_id=f"{part}_forecast_normal_ridge", job_type="forecast", model_family="normal_ridge", fit_job_id=f"{part}_fit_normal_ridge", method="ridge"),
            role="final_dec25_normal_ridge_30_day_forecast",
        )
        add_job(
            rows, runtime, args,
            job_id=f"{part}_forecast_normal_rhs_vb",
            part=part,
            stage="forecast",
            model_family="normal_rhs_vb",
            deps=(f"{part}_fit_normal_rhs_vb",),
            command=worker_cmd(args, part=part, job_id=f"{part}_forecast_normal_rhs_vb", job_type="forecast", model_family="normal_rhs_vb", fit_job_id=f"{part}_fit_normal_rhs_vb", method="rhs"),
            role="final_dec25_normal_rhs_vb_30_day_forecast",
        )
        al_parent = {
            "0.50": f"{part}_fit_normal_rhs_vb",
            "0.35": f"{part}_fit_independent_al_q0p50",
            "0.65": f"{part}_fit_independent_al_q0p50",
            "0.20": f"{part}_fit_independent_al_q0p35",
            "0.80": f"{part}_fit_independent_al_q0p65",
            "0.05": f"{part}_fit_independent_al_q0p20",
            "0.95": f"{part}_fit_independent_al_q0p80",
        }
        for tau in AL_ORDER:
            slug = qslug(tau)
            job_id = f"{part}_fit_independent_al_{slug}"
            dep = al_parent[tau]
            if args.quantile_route == "same_tau_parallel":
                al_deps = (f"{part}_fit_normal_rhs_vb", f"{part}_initializer_audit")
                al_init = "AUTO_AUDIT"
                init_policy = "audited_same_tau_old_fit_or_final_normal_rhs_best_objective"
            else:
                al_deps = (dep, f"{part}_initializer_audit")
                al_init = dep
                init_policy = "sequential_adjacent_final_al_fallback_after_initializer_audit"
            add_job(
                rows, runtime, args,
                job_id=job_id,
                part=part,
                stage="fit",
                model_family="independent_al",
                tau=tau,
                likelihood="AL",
                fit_structure="independent",
                deps=al_deps,
                command=worker_cmd(args, part=part, job_id=job_id, job_type="fit", model_family="independent_al", likelihood="AL", fit_structure="independent", tau=tau, init_fit_job_ids=al_init),
                role="final_dec25_independent_al_fit",
                initializer_policy=init_policy,
            )
            add_job(
                rows, runtime, args,
                job_id=f"{part}_forecast_independent_al_{slug}",
                part=part,
                stage="forecast",
                model_family="independent_al",
                tau=tau,
                likelihood="AL",
                fit_structure="independent",
                deps=(job_id,),
                command=worker_cmd(args, part=part, job_id=f"{part}_forecast_independent_al_{slug}", job_type="forecast", model_family="independent_al", likelihood="AL", fit_structure="independent", tau=tau, fit_job_id=job_id),
                role="final_dec25_independent_al_30_day_forecast",
            )
        for tau in QUANTILES:
            slug = qslug(tau)
            al_fit = f"{part}_fit_independent_al_{slug}"
            job_id = f"{part}_fit_independent_exal_{slug}"
            add_job(
                rows, runtime, args,
                job_id=job_id,
                part=part,
                stage="fit",
                model_family="independent_exal",
                tau=tau,
                likelihood="exAL",
                fit_structure="independent",
                deps=(al_fit,),
                command=worker_cmd(args, part=part, job_id=job_id, job_type="fit", model_family="independent_exal", likelihood="exAL", fit_structure="independent", tau=tau, init_fit_job_ids=al_fit),
                role="final_dec25_independent_exal_fit",
                initializer_policy="same_tau_final_al",
            )
            add_job(
                rows, runtime, args,
                job_id=f"{part}_forecast_independent_exal_{slug}",
                part=part,
                stage="forecast",
                model_family="independent_exal",
                tau=tau,
                likelihood="exAL",
                fit_structure="independent",
                deps=(job_id,),
                command=worker_cmd(args, part=part, job_id=f"{part}_forecast_independent_exal_{slug}", job_type="forecast", model_family="independent_exal", likelihood="exAL", fit_structure="independent", tau=tau, fit_job_id=job_id),
                role="final_dec25_independent_exal_30_day_forecast",
            )
        al_fits = tuple(f"{part}_fit_independent_al_{qslug(tau)}" for tau in QUANTILES)
        exal_fits = tuple(f"{part}_fit_independent_exal_{qslug(tau)}" for tau in QUANTILES)
        for family, likelihood, deps in (
            ("joint_al", "AL", al_fits),
            ("joint_exal", "exAL", exal_fits),
        ):
            fit_id = f"{part}_fit_{family}_all7"
            add_job(
                rows, runtime, args,
                job_id=fit_id,
                part=part,
                stage="fit",
                model_family=family,
                tau="all7",
                likelihood=likelihood,
                fit_structure="joint",
                deps=deps,
                command=worker_cmd(args, part=part, job_id=fit_id, job_type="fit", model_family=family, likelihood=likelihood, fit_structure="joint", tau="all7", init_fit_job_ids="|".join(deps)),
                role=f"final_dec25_{family}_fit",
                initializer_policy="all_matching_final_independent_quantiles",
            )
            add_job(
                rows, runtime, args,
                job_id=f"{part}_forecast_{family}_all7",
                part=part,
                stage="forecast",
                model_family=family,
                tau="all7",
                likelihood=likelihood,
                fit_structure="joint",
                deps=(fit_id,),
                command=worker_cmd(args, part=part, job_id=f"{part}_forecast_{family}_all7", job_type="forecast", model_family=family, likelihood=likelihood, fit_structure="joint", tau="all7", fit_job_id=fit_id),
                role=f"final_dec25_{family}_30_day_forecast",
            )
        add_job(
            rows, runtime, args,
            job_id=f"{part}_package_compact",
            part=part,
            stage="package",
            deps=tuple(row["job_id"] for row in rows if row["part"] == part and row["stage"] == "forecast"),
            command=package_cmd(args, part=part, kind="compact"),
            role="future_muscat_compact_package",
        )
        add_job(
            rows, runtime, args,
            job_id=f"{part}_package_heavy",
            part=part,
            stage="package",
            deps=tuple(row["job_id"] for row in rows if row["part"] == part and row["stage"] == "fit"),
            command=package_cmd(args, part=part, kind="heavy"),
            role="future_muscat_heavy_fit_continuation_package",
        )
    return rows


def write_plan(runtime: Path, args: argparse.Namespace, rows: list[dict]) -> Path:
    counts = {}
    for part in ("part2", "part3"):
        part_rows = [row for row in rows if row["part"] == part]
        counts[part] = {
            "design_cache_jobs": sum(row["stage"] == "design_cache" for row in part_rows),
            "initializer_audit_jobs": sum(row["stage"] == "initializer_audit" for row in part_rows),
            "fit_jobs": sum(row["stage"] == "fit" for row in part_rows),
            "forecast_jobs": sum(row["stage"] == "forecast" for row in part_rows),
            "package_jobs": sum(row["stage"] == "package" for row in part_rows),
        }
    lines = [
        "# GloFAS Part 2/3 Dec25 Final-Refit Relaunch Plan",
        "",
        f"Prepared UTC: {datetime.now(timezone.utc).isoformat()}",
        f"Runtime root: `{args.runtime_root}`",
        "",
        "## Immutable Contract",
        "",
        "- `cutoff_id=dec25_2022`; `train_end=origin_date=2022-12-25`.",
        "- Forecast window is exactly `2022-12-26` through `2023-01-24` with horizons `1:30`.",
        "- No inferred/default origin, rolling origin, CEFS/GEFS, crossing fix, synthesis, ensemble substitution, shortened horizon, or Part 4.",
        "- Discrepancy sign is always `retrospective GloFAS - USGS`; opposite-sign artifacts abort.",
        "",
        "## Scientific Inventory",
        "",
        "- Keep the Part 1 final reference work unchanged.",
        "- Keep Part 2 ridge/RHS screens only as selection evidence; refit the frozen winner on the Dec25 full-data design.",
        "- Keep old Part 2/3 fits only as initializer evidence after compatibility and objective checks.",
        "- Treat old wrong-origin forecasts as diagnostic-only and replace them after final Dec25 fits.",
        "",
        "## Job Counts",
        "",
        "| Part | Design Caches | Initializer Audits | Final Fits | Forecasts | Packages |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for part in ("part2", "part3"):
        c = counts[part]
        lines.append(f"| {part} | {c['design_cache_jobs']} | {c['initializer_audit_jobs']} | {c['fit_jobs']} | {c['forecast_jobs']} | {c['package_jobs']} |")
    lines.extend([
        "",
        "Total production model fits and forecasts prepared: `72` (`36` per part).",
        "Initializer-audit and package jobs are included in the DAG but are not model fits.",
        f"Quantile route prepared: `{args.quantile_route}`.",
        "",
        "## Dependency Rules",
        "",
        "- Part 2 and Part 3 design caches may run concurrently.",
        "- Final ridge fits depend only on their part-specific design cache.",
        "- Each Normal RHS/VB fit depends only on the matching final ridge fit.",
        "- Forecast jobs are separate retryable jobs and hash-verify the retained final fit.",
        "- `same_tau_parallel` runs all seven independent AL fits for a part after the Normal RHS fit and initializer audit certify finite compatible starts.",
        "- `sequential_fallback` keeps the `.50 -> .35/.65 -> .20/.80 -> .05/.95` AL chain when same-quantile starts cannot be certified.",
        "- Each exAL tau waits for the same-tau final AL fit.",
        "- Joint AL waits for all seven final AL fits; joint exAL waits for all seven final exAL fits.",
        "",
        "## Launch Commands For Later",
        "",
        "Do not run these until the operator authorizes production:",
        "",
        "```bash",
        "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1",
        f"python3 application/scripts/383_launch_glofas_dec25_final_refit_dag.py --runtime-root {shlex.quote(args.runtime_root)} --workers {args.workers} --session-prefix glofas_dec25_final_jerez_20260905 --background",
        f"python3 application/scripts/384_check_glofas_dec25_final_refit_dag.py --runtime-root {shlex.quote(args.runtime_root)} --session-prefix glofas_dec25_final_jerez_20260905 --write",
        "```",
        "",
        "## Handoff Packaging For Later",
        "",
        "```bash",
        f"python3 application/scripts/382_package_glofas_dec25_final_refit.py --runtime-root {shlex.quote(args.runtime_root)} --part part2 --package-kind compact --output-dir {shlex.quote(args.package_output_dir)}",
        f"python3 application/scripts/382_package_glofas_dec25_final_refit.py --runtime-root {shlex.quote(args.runtime_root)} --part part2 --package-kind heavy --output-dir {shlex.quote(args.package_output_dir)}",
        f"python3 application/scripts/382_package_glofas_dec25_final_refit.py --runtime-root {shlex.quote(args.runtime_root)} --part part3 --package-kind compact --output-dir {shlex.quote(args.package_output_dir)}",
        f"python3 application/scripts/382_package_glofas_dec25_final_refit.py --runtime-root {shlex.quote(args.runtime_root)} --part part3 --package-kind heavy --output-dir {shlex.quote(args.package_output_dir)}",
        "```",
    ])
    path = runtime / "docs" / "glofas_dec25_final_refit_relaunch_plan.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def write_artifact_manifest(runtime: Path) -> None:
    rows = []
    for path in sorted(p for p in runtime.rglob("*") if p.is_file()):
        if path.name in {"artifact_manifest.csv", "artifact_file_list.csv"}:
            continue
        rows.append({
            "relative_path": rel(path, runtime),
            "repo_relative_path": rel(path, repo_root()),
            "size_bytes": path.stat().st_size,
            "sha256": sha256_file(path),
            "role": Path(rel(path, runtime)).parts[0],
        })
    if rows:
        write_csv(runtime / "manifests" / "artifact_file_list.csv", rows)
        write_csv(runtime / "manifests" / "artifact_manifest.csv", rows)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", dest="runtime_root", default="local_trackers/runtime_configs/glofas_part23_final_dec25_2022_relaunch_jerez_20260905")
    parser.add_argument("--base-config", dest="base_config", default=DEFAULT_BASE_CONFIG)
    parser.add_argument("--part2-rhs-runtime-root", dest="part2_rhs_runtime_root", default=DEFAULT_PART2_RHS_RUNTIME)
    parser.add_argument("--part2-rhs-candidate-id", dest="part2_rhs_candidate_id", default="normal_part2_rhs_top16_part2ridge_targeted_0016_disc_covars__D1_n2500__a080_r070__reftau1e00_disctau1em03")
    parser.add_argument("--part2-candidate-id", dest="part2_candidate_id", default="part2ridge_targeted_0016_disc_covars__D1_n2500__a080_r070")
    parser.add_argument("--part2-old-quantile-runtime-root", dest="part2_old_quantile_runtime_root", default=DEFAULT_PART2_OLD_QUANTILE_RUNTIME)
    parser.add_argument("--part3-old-quantile-runtime-root", dest="part3_old_quantile_runtime_root", default=DEFAULT_PART3_OLD_QUANTILE_RUNTIME)
    parser.add_argument("--part3-winner-manifest", dest="part3_winner_manifest", default=DEFAULT_PART3_WINNER_MANIFEST)
    parser.add_argument("--package-output-dir", dest="package_output_dir", default="local_trackers/muscat_handoffs")
    parser.add_argument("--workers", type=int, default=40)
    parser.add_argument("--quantile-route", dest="quantile_route", choices=("same_tau_parallel", "sequential_fallback"), default="same_tau_parallel")
    parser.add_argument("--max-iter", dest="max_iter", type=int, default=100)
    parser.add_argument("--min-iter", dest="min_iter", type=int, default=30)
    parser.add_argument("--tol", type=float, default=0.01)
    parser.add_argument("--normal-draws", dest="normal_draws", type=int, default=500)
    parser.add_argument("--forecast-backend", dest="forecast_backend", choices=("auto", "cpp", "r"), default="cpp")
    parser.add_argument("--freeze-beta-warmup-iters", dest="freeze_beta_warmup_iters", type=int, default=20)
    parser.add_argument("--min-beta-updates", dest="min_beta_updates", type=int, default=30)
    parser.add_argument("--source-freeze-root", dest="source_freeze_root", default="")
    args = parser.parse_args()

    if args.runtime_root.startswith("/"):
        runtime = Path(args.runtime_root).resolve()
    else:
        runtime = (repo_root() / args.runtime_root).resolve()
    for sub in ("configs", "tables", "logs", "status", "scripts", "docs", "manifests", "objects", "scores", "traces", "coefficients", "forecasts", "figures"):
        (runtime / sub).mkdir(parents=True, exist_ok=True)
    if args.workers < 1 or args.workers > 40:
        raise SystemExit("Use 1..40 one-thread workers for this Dec25 relaunch DAG.")
    if args.max_iter < args.min_iter or args.min_iter < 1 or args.tol <= 0:
        raise SystemExit("Invalid VB controls.")
    if args.freeze_beta_warmup_iters < 0 or args.min_beta_updates < 0:
        raise SystemExit("Beta-freeze controls must be nonnegative.")

    jobs = build_jobs(args, runtime)
    contract = {
        **CONTRACT,
        "prepared_utc": datetime.now(timezone.utc).isoformat(),
        "runtime_root": rel(runtime, repo_root()),
        "base_config": args.base_config,
        "part2_rhs_runtime_root": args.part2_rhs_runtime_root,
        "part2_rhs_candidate_id": args.part2_rhs_candidate_id,
        "part2_candidate_id": args.part2_candidate_id,
        "part2_old_quantile_runtime_root": args.part2_old_quantile_runtime_root,
        "part3_old_quantile_runtime_root": args.part3_old_quantile_runtime_root,
        "part3_winner_manifest": args.part3_winner_manifest,
        "quantile_route": args.quantile_route,
        "source_freeze_root": args.source_freeze_root,
        "thread_guards": {
            "OMP_NUM_THREADS": "1",
            "OPENBLAS_NUM_THREADS": "1",
            "MKL_NUM_THREADS": "1",
            "VECLIB_MAXIMUM_THREADS": "1",
            "NUMEXPR_NUM_THREADS": "1",
        },
    }
    (runtime / "configs" / "final_dec25_contract.json").write_text(json.dumps(contract, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_csv(runtime / "tables" / "keep_refit_replace_inventory.csv", inventory_rows(args))
    write_csv(runtime / "tables" / "initialization_compatibility_matrix.csv", init_matrix(args))
    fields = list(jobs[0])
    write_csv(runtime / "tables" / "final_dec25_job_manifest.csv", jobs, fields)
    for part in ("part2", "part3"):
        write_csv(runtime / "tables" / f"{part}_dry_run_job_manifest.csv", [row for row in jobs if row["part"] == part], fields)

    metadata = {
        "schema_version": "glofas_part23_final_dec25_2022_relaunch_plan_v1",
        "runtime_root": rel(runtime, repo_root()),
        "job_counts": {
            "total": len(jobs),
            "model_fit_jobs": sum(row["stage"] == "fit" for row in jobs),
            "forecast_jobs": sum(row["stage"] == "forecast" for row in jobs),
            "design_cache_jobs": sum(row["stage"] == "design_cache" for row in jobs),
            "initializer_audit_jobs": sum(row["stage"] == "initializer_audit" for row in jobs),
            "package_jobs": sum(row["stage"] == "package" for row in jobs),
            "part2_fits": sum(row["part"] == "part2" and row["stage"] == "fit" for row in jobs),
            "part2_forecasts": sum(row["part"] == "part2" and row["stage"] == "forecast" for row in jobs),
            "part3_fits": sum(row["part"] == "part3" and row["stage"] == "fit" for row in jobs),
            "part3_forecasts": sum(row["part"] == "part3" and row["stage"] == "forecast" for row in jobs),
        },
        "production_launched": False,
    }
    (runtime / "configs" / "final_dec25_relaunch_metadata.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    plan_path = write_plan(runtime, args, jobs)
    launch_path = runtime / "scripts" / "launch_after_operator_approval.sh"
    launch_path.write_text(
        "#!/usr/bin/env bash\n"
        "set -euo pipefail\n"
        "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1\n"
        f"python3 application/scripts/383_launch_glofas_dec25_final_refit_dag.py --runtime-root {shlex.quote(rel(runtime, repo_root()))} --workers {args.workers} --session-prefix glofas_dec25_final_jerez_20260905 --background\n",
        encoding="utf-8",
    )
    launch_path.chmod(0o755)
    write_artifact_manifest(runtime)

    print(f"runtime_root={rel(runtime, repo_root())}")
    print(f"job_manifest={rel(runtime / 'tables' / 'final_dec25_job_manifest.csv', repo_root())}")
    print(f"relaunch_plan={rel(plan_path, repo_root())}")
    print(f"model_fit_jobs={metadata['job_counts']['model_fit_jobs']}")
    print(f"forecast_jobs={metadata['job_counts']['forecast_jobs']}")
    print("production_launched=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
