#!/usr/bin/env python3
"""Audit Stage-R53/R54 functional convergence and freeze bounded follow-up evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import yaml
from scipy.stats import norm, rankdata

from pricefm_common import parse_bool, write_json


ARTIFACT_ROOT = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
STAGE_R54 = ARTIFACT_ROOT / "authoritative/pricefm_stage_r54_exal_m0_closeout_20260812"
STAGE_R53_PREP = ARTIFACT_ROOT / "authoritative/pricefm_stage_r52_r53_exal_m0_launch_prep_20260811"
STAGE_R53_RUN = ARTIFACT_ROOT / "runs/pricefm_stage_r53_exal_m0_full_surface_20260811"
OUTPUT = ARTIFACT_ROOT / "authoritative/pricefm_stage_r55_functional_convergence_20260820"
PARAMETERS = ("sigma", "gamma", "rhs_tau", "rhs_c2", "beta_l2")


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r54-dir", type=Path, default=STAGE_R54)
    p.add_argument("--stage-r53-prep-dir", type=Path, default=STAGE_R53_PREP)
    p.add_argument("--stage-r53-run-dir", type=Path, default=STAGE_R53_RUN)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-cases", type=int, default=87)
    p.add_argument("--expected-chain-jobs", type=int, default=2436)
    p.add_argument("--expected-confirmation-targets", type=int, default=1)
    p.add_argument("--rhat-threshold", type=float, default=1.01)
    p.add_argument("--ess-threshold", type=float, default=400.0)
    p.add_argument("--chain-spread-threshold", type=float, default=0.005)
    p.add_argument("--path-nrmse-threshold", type=float, default=0.01)
    p.add_argument("--established-burn", type=int, default=5000)
    p.add_argument("--established-retained", type=int, default=20000)
    p.add_argument("--hash-compact-evidence", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def git_head(path: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
    ).strip()


def prepare_output(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(f"Output exists: {path}")
    path.mkdir(parents=True, exist_ok=True)


def split_chains(chains: np.ndarray) -> np.ndarray:
    values = np.asarray(chains, dtype=float)
    if values.ndim != 2 or values.shape[0] < 2 or values.shape[1] < 4:
        raise ValueError("Diagnostics require at least two chains and four draws")
    if not np.isfinite(values).all():
        raise ValueError("Diagnostics received nonfinite draws")
    half = values.shape[1] // 2
    return np.concatenate((values[:, :half], values[:, -half:]), axis=0)


def rank_normalize(chains: np.ndarray) -> np.ndarray:
    values = np.asarray(chains, dtype=float)
    ranks = rankdata(values.reshape(-1), method="average")
    transformed = norm.ppf((ranks - 0.375) / (len(ranks) + 0.25))
    return transformed.reshape(values.shape)


def basic_rhat(chains: np.ndarray) -> float:
    values = np.asarray(chains, dtype=float)
    m, n = values.shape
    within = float(np.mean(np.var(values, axis=1, ddof=1)))
    total = float(np.var(values, ddof=1))
    if within <= np.finfo(float).eps:
        return 1.0 if total <= np.finfo(float).eps else float("inf")
    between = n * float(np.var(np.mean(values, axis=1), ddof=1))
    variance = ((n - 1) / n) * within + between / n
    return float(math.sqrt(max(variance / within, 0.0)))


def rank_folded_rhat(chains: np.ndarray) -> tuple[float, float, float]:
    split = split_chains(chains)
    rank_rhat = basic_rhat(rank_normalize(split))
    folded = np.abs(split - np.median(split))
    folded_rhat = basic_rhat(rank_normalize(folded))
    return rank_rhat, folded_rhat, max(rank_rhat, folded_rhat)


def autocovariance(values: np.ndarray) -> np.ndarray:
    centered = np.asarray(values, dtype=float) - float(np.mean(values))
    n = len(centered)
    size = 1 << (2 * n - 1).bit_length()
    spectrum = np.fft.rfft(centered, n=size)
    return np.fft.irfft(spectrum * np.conjugate(spectrum), n=size)[:n] / n


def effective_sample_size(chains: np.ndarray) -> float:
    values = np.asarray(chains, dtype=float)
    m, n = values.shape
    within = float(np.mean(np.var(values, axis=1, ddof=1)))
    between = n * float(np.var(np.mean(values, axis=1), ddof=1))
    variance = ((n - 1) / n) * within + between / n
    total = float(m * n)
    if not math.isfinite(variance) or variance <= np.finfo(float).eps:
        return total
    autocov = np.vstack([autocovariance(chain) for chain in values])
    rho = np.ones(n, dtype=float)
    for lag in range(1, n):
        rho[lag] = 1.0 - (within - float(np.mean(autocov[:, lag]))) / variance
    pair_sums: list[float] = []
    for lag in range(0, n - 1, 2):
        pair = float(rho[lag] + rho[lag + 1])
        if pair < 0:
            break
        if pair_sums:
            pair = min(pair, pair_sums[-1])
        pair_sums.append(pair)
    tau = -1.0 + 2.0 * sum(pair_sums)
    if not math.isfinite(tau) or tau <= 0:
        return total
    return float(min(total, max(1.0, total / tau)))


def modern_diagnostics(chains: np.ndarray) -> dict[str, float]:
    split = split_chains(chains)
    rank_rhat, folded_rhat, combined_rhat = rank_folded_rhat(chains)
    bulk_values = rank_normalize(split)
    bulk_ess = effective_sample_size(bulk_values)
    flat = split.reshape(-1)
    lower, upper = np.quantile(flat, [0.05, 0.95])
    lower_ess = effective_sample_size((split <= lower).astype(float))
    upper_ess = effective_sample_size((split >= upper).astype(float))
    tail_ess = min(lower_ess, upper_ess)
    mcse_mean = float(np.std(flat, ddof=1) / math.sqrt(max(bulk_ess, 1.0)))
    return {
        "rank_rhat": rank_rhat,
        "folded_rhat": folded_rhat,
        "combined_rhat": combined_rhat,
        "bulk_ess": bulk_ess,
        "tail_ess": tail_ess,
        "mcse_mean": mcse_mean,
    }


def bool_series(frame: pd.DataFrame, column: str) -> pd.Series:
    values = frame[column]
    if values.dtype == bool:
        return values
    return values.astype(str).str.lower().eq("true")


def load_inputs(args) -> tuple[pd.DataFrame, ...]:
    r54 = args.stage_r54_dir
    prep = args.stage_r53_prep_dir
    decisions = pd.read_csv(r54 / "pricefm_stage_r54_case_decisions.csv")
    classic = pd.read_csv(r54 / "pricefm_stage_r54_chain_diagnostics.csv")
    quantile = pd.read_csv(r54 / "pricefm_stage_r54_quantile_metrics.csv")
    chain_metrics = pd.read_csv(r54 / "pricefm_stage_r54_chain_metrics.csv")
    manifest = pd.read_csv(prep / "pricefm_stage_r53_launch_manifest.csv")
    cases = pd.read_csv(prep / "pricefm_stage_r52_case_manifest.csv")
    if len(decisions) != args.expected_cases or len(cases) != args.expected_cases:
        raise RuntimeError("R55 requires the complete R54 case surface")
    if len(manifest) != args.expected_chain_jobs:
        raise RuntimeError("R55 requires the complete R53 chain manifest")
    expected_diagnostics = args.expected_cases * 7 * len(PARAMETERS)
    if len(classic) != expected_diagnostics:
        raise RuntimeError(f"R54 diagnostic surface changed: {len(classic)} != {expected_diagnostics}")
    if manifest.groupby(["case_id", "tau"]).chain.nunique().ne(4).any():
        raise RuntimeError("Every R55 case/quantile requires four unique chains")
    return decisions, classic, quantile, chain_metrics, manifest, cases


def compute_modern_diagnostics(manifest: pd.DataFrame, args) -> pd.DataFrame:
    records: list[dict] = []
    for (case_id, tau), jobs in manifest.groupby(["case_id", "tau"], sort=True):
        jobs = jobs.sort_values("chain")
        scalar_frames = []
        for job in jobs.itertuples(index=False):
            path = Path(job.output_dir) / "scalar_draws.csv.gz"
            if not path.is_file():
                raise FileNotFoundError(path)
            scalar = pd.read_csv(path)
            if not set(PARAMETERS).issubset(scalar.columns):
                raise RuntimeError(f"Scalar contract changed: {path}")
            scalar_frames.append(scalar)
        lengths = {len(frame) for frame in scalar_frames}
        if len(lengths) != 1:
            raise RuntimeError(f"Unequal chain lengths for {case_id}/tau={tau}")
        for parameter in PARAMETERS:
            chains = np.vstack([frame[parameter].to_numpy(float) for frame in scalar_frames])
            diagnostic = modern_diagnostics(chains)
            records.append({
                "case_id": case_id,
                "region": str(jobs.iloc[0].region),
                "fold": int(jobs.iloc[0].fold),
                "tau": float(tau),
                "parameter": parameter,
                "chains": int(chains.shape[0]),
                "draws_per_chain": int(chains.shape[1]),
                **diagnostic,
                "rhat_threshold": args.rhat_threshold,
                "ess_threshold": args.ess_threshold,
                "rhat_pass": diagnostic["combined_rhat"] <= args.rhat_threshold,
                "bulk_ess_pass": diagnostic["bulk_ess"] >= args.ess_threshold,
                "tail_ess_pass": diagnostic["tail_ess"] >= args.ess_threshold,
                "modern_diagnostic_pass": (
                    diagnostic["combined_rhat"] <= args.rhat_threshold
                    and diagnostic["bulk_ess"] >= args.ess_threshold
                    and diagnostic["tail_ess"] >= args.ess_threshold
                ),
            })
    return pd.DataFrame(records)


def confirmation_candidates(decisions: pd.DataFrame) -> pd.DataFrame:
    mask = (
        bool_series(decisions, "validation_selected")
        & bool_series(decisions, "validation_harm_guard_pass")
        & bool_series(decisions, "authority_replay_pass")
        & bool_series(decisions, "beats_authoritative_qdesn")
        & bool_series(decisions, "beats_cached_pricefm")
    )
    return decisions.loc[mask].copy()


def diagnostic_comparison_cases(decisions: pd.DataFrame) -> pd.DataFrame:
    mask = (
        bool_series(decisions, "validation_selected")
        & bool_series(decisions, "beats_authoritative_qdesn")
        & bool_series(decisions, "beats_cached_pricefm")
    )
    return decisions.loc[mask].copy()


def compute_path_stability(
    comparison: pd.DataFrame,
    manifest: pd.DataFrame,
    cases: pd.DataFrame,
    chain_metrics: pd.DataFrame,
    args,
) -> pd.DataFrame:
    case_map = cases.set_index("id")
    records: list[dict] = []
    for case in comparison.itertuples(index=False):
        case_jobs = manifest[manifest.case_id.eq(case.case_id)]
        adapter_dir = Path(case_map.loc[case.case_id, "adapter_dir"])
        for tau, jobs in case_jobs.groupby("tau", sort=True):
            predictions = []
            for job in jobs.sort_values("chain").itertuples(index=False):
                path = Path(job.output_dir) / "posterior_mean_predictions.csv.gz"
                frame = pd.read_csv(path)
                required = {"origin_id", "horizon", "split", "chain", "pred_scaled"}
                if not required.issubset(frame.columns):
                    raise RuntimeError(f"Prediction contract changed: {path}")
                predictions.append(frame[list(required)])
            predictions = pd.concat(predictions, ignore_index=True)
            for split in ("val", "test"):
                rows = pd.read_csv(adapter_dir / f"rows_{split}.csv")
                subset = predictions[predictions.split.eq(split)]
                pivot = subset.pivot(index=["origin_id", "horizon"], columns="chain", values="pred_scaled")
                if pivot.shape[1] != 4 or len(pivot) != len(rows):
                    raise RuntimeError(f"Incomplete prediction paths for {case.case_id}/tau={tau}/{split}")
                group_a = pivot[[1, 2]].mean(axis=1)
                group_b = pivot[[3, 4]].mean(axis=1)
                delta = group_a.to_numpy() - group_b.to_numpy()
                y_sd = float(np.std(rows.y_scaled.to_numpy(float), ddof=1))
                denominator = max(y_sd, np.finfo(float).eps)
                path_nrmse = float(np.sqrt(np.mean(delta * delta)) / denominator)
                path_p95 = float(np.quantile(np.abs(delta), 0.95) / denominator)
                loss_rows = chain_metrics[
                    chain_metrics.case_id.eq(case.case_id)
                    & np.isclose(chain_metrics.tau, tau)
                    & chain_metrics.split.eq(split)
                ].sort_values("chain")
                if len(loss_rows) != 4:
                    raise RuntimeError("R54 chain-metric surface is incomplete")
                losses = loss_rows.original_AQL.to_numpy(float)
                mean_loss = max(float(np.mean(losses)), np.finfo(float).eps)
                group_loss_delta = abs(float(np.mean(losses[:2]) - np.mean(losses[2:]))) / mean_loss
                chain_spread = float((max(losses) - min(losses)) / mean_loss)
                records.append({
                    "case_id": case.case_id,
                    "region": case.region,
                    "fold": int(case.fold),
                    "tau": float(tau),
                    "split": split,
                    "path_group_nrmse": path_nrmse,
                    "path_group_p95_normalized": path_p95,
                    "chain_group_loss_relative_delta": group_loss_delta,
                    "chain_relative_spread": chain_spread,
                    "path_nrmse_threshold": args.path_nrmse_threshold,
                    "chain_spread_threshold": args.chain_spread_threshold,
                    "functional_stability_pass": (
                        path_nrmse <= args.path_nrmse_threshold
                        and chain_spread <= args.chain_spread_threshold
                    ),
                    "promotion_gate_role": "diagnostic_only_no_automatic_promotion",
                })
    return pd.DataFrame(records)


def build_case_triage(
    decisions: pd.DataFrame,
    modern: pd.DataFrame,
    functional: pd.DataFrame,
) -> pd.DataFrame:
    modern_case = modern.groupby("case_id", as_index=False).agg(
        modern_diagnostics_pass=("modern_diagnostic_pass", "all"),
        max_combined_rhat=("combined_rhat", "max"),
        min_bulk_ess=("bulk_ess", "min"),
        min_tail_ess=("tail_ess", "min"),
        failed_modern_diagnostic_cells=("modern_diagnostic_pass", lambda x: int((~x).sum())),
    )
    if functional.empty:
        functional_case = pd.DataFrame(columns=["case_id", "functional_path_pass", "max_path_group_nrmse"])
    else:
        functional_case = functional.groupby("case_id", as_index=False).agg(
            functional_path_pass=("functional_stability_pass", "all"),
            max_path_group_nrmse=("path_group_nrmse", "max"),
            max_chain_relative_spread=("chain_relative_spread", "max"),
            failed_functional_cells=("functional_stability_pass", lambda x: int((~x).sum())),
        )
    triage = decisions.merge(modern_case, on="case_id", how="left").merge(
        functional_case, on="case_id", how="left"
    )
    validation_dual = (
        bool_series(triage, "validation_selected")
        & bool_series(triage, "beats_authoritative_qdesn")
        & bool_series(triage, "beats_cached_pricefm")
    )
    confirmation = (
        validation_dual
        & bool_series(triage, "validation_harm_guard_pass")
        & bool_series(triage, "authority_replay_pass")
    )
    triage["validation_selected_dual_reference"] = validation_dual
    triage["bounded_confirmation_target"] = confirmation
    triage["confirmation_launch_authorized"] = False
    triage["recommended_action"] = np.select(
        [
            confirmation,
            validation_dual & ~bool_series(triage, "validation_harm_guard_pass"),
            bool_series(triage, "validation_selected"),
        ],
        [
            "design_case_specific_full_budget_confirmation",
            "do_not_confirm_quantile_harm",
            "retain_current_authority_validation_selected_not_dual",
        ],
        default="retain_current_authority",
    )
    return triage


def build_confirmation_manifest(
    triage: pd.DataFrame,
    manifest: pd.DataFrame,
    args,
) -> pd.DataFrame:
    records: list[dict] = []
    for case in triage[triage.bounded_confirmation_target].itertuples(index=False):
        jobs = manifest[manifest.case_id.eq(case.case_id)]
        current_draws = int(jobs.n_mcmc.unique()[0])
        minimum_ess = max(min(float(case.min_bulk_ess), float(case.min_tail_ess)), 1.0)
        linear_projection = int(math.ceil(current_draws * args.ess_threshold / minimum_ess / 1000) * 1000)
        recommended_retained = max(args.established_retained, linear_projection)
        records.append({
            "case_id": case.case_id,
            "region": case.region,
            "fold": int(case.fold),
            "quantiles": json.dumps(sorted(float(x) for x in jobs.tau.unique())),
            "chains_per_quantile": 4,
            "planned_chain_jobs": int(len(jobs)),
            "current_burn": int(jobs.n_burn.unique()[0]),
            "current_retained_per_chain": current_draws,
            "established_burn": args.established_burn,
            "established_retained_per_chain": args.established_retained,
            "linear_ess_projected_retained_per_chain": linear_projection,
            "recommended_burn": args.established_burn,
            "recommended_retained_per_chain": recommended_retained,
            "selection_basis": "validation_selected+harm_guard+authority_replay; dual test comparison audit_only",
            "required_prelaunch_audit": "exact_restart_state_and_runtime_budget_capability",
            "launch_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        })
    return pd.DataFrame(records)


def files_matching(root: Path, pattern: str) -> list[Path]:
    return [path for path in root.glob(pattern) if path.is_file()]


def inventory_row(name: str, files: list[Path], action: str, reason: str) -> dict:
    return {
        "artifact_group": name,
        "file_count": len(files),
        "bytes": sum(path.stat().st_size for path in files),
        "gib": sum(path.stat().st_size for path in files) / 2**30,
        "retention_action": action,
        "reason": reason,
        "deletion_authorized": False,
    }


def build_retention_inventory(args, confirmation: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    run = args.stage_r53_run_dir
    chains = run / "chains"
    cases = run / "cases"
    target_ids = set(confirmation.case_id) if not confirmation.empty else set()
    target_chain_dirs = {
        path for case_id in target_ids for path in chains.glob(case_id.replace("r52_", "r53_") + "_tau*_chain*")
    }
    compact_names = ("job_summary.json", "scalar_draws.csv.gz", "posterior_mean_predictions.csv.gz", "chain.log", "job_owner.json")
    compact = [path for name in compact_names for path in chains.glob(f"*/{name}")]
    posterior = files_matching(chains, "*/posterior_draws.rds")
    target_posterior = [path for path in posterior if path.parent in target_chain_dirs]
    other_posterior = [path for path in posterior if path.parent not in target_chain_dirs]
    target_case_files = [
        path for case_id in target_ids for path in (cases / case_id).rglob("*") if path.is_file()
    ]
    other_case_files = [
        path for case_dir in cases.iterdir() if case_dir.is_dir() and case_dir.name not in target_ids
        for path in case_dir.rglob("*") if path.is_file()
    ]
    r54_files = [path for path in args.stage_r54_dir.iterdir() if path.is_file()]
    prep_files = [path for path in args.stage_r53_prep_dir.rglob("*") if path.is_file()]
    inventory = pd.DataFrame([
        inventory_row("r54_closeout", r54_files, "retain", "authoritative read-only decision evidence"),
        inventory_row("r51_r53_manifests", prep_files, "retain", "reproducibility and launch provenance"),
        inventory_row("all_chain_compact_evidence", compact, "retain", "metrics diagnostics ownership and logs"),
        inventory_row("confirmation_target_posterior", target_posterior, "retain", "bounded follow-up target"),
        inventory_row("noncandidate_posterior", other_posterior, "cleanup_review", "regenerable beta draws after frozen handoff"),
        inventory_row("confirmation_target_case_artifacts", target_case_files, "retain", "adapter and initialization reuse"),
        inventory_row("noncandidate_case_artifacts", other_case_files, "cleanup_review", "regenerable adapters and initialization after hash review"),
    ])
    critical = sorted(set(r54_files + prep_files + compact + target_posterior))
    if not args.hash_compact_evidence:
        critical = sorted(set(r54_files + [
            args.stage_r53_prep_dir / "pricefm_stage_r52_case_manifest.csv",
            args.stage_r53_prep_dir / "pricefm_stage_r53_launch_manifest.csv",
        ]))
    hashes = pd.DataFrame([
        {
            "path": str(path.resolve()),
            "bytes": path.stat().st_size,
            "sha256": sha256(path),
            "retention_action": "retain",
            "deletion_authorized": False,
        }
        for path in critical if path.is_file()
    ])
    return inventory, hashes


def source_manifest(args, output_files: list[Path]) -> dict:
    sources = [
        args.stage_r54_dir / "summary.json",
        args.stage_r54_dir / "pricefm_stage_r54_case_decisions.csv",
        args.stage_r54_dir / "pricefm_stage_r54_chain_diagnostics.csv",
        args.stage_r54_dir / "pricefm_stage_r54_quantile_metrics.csv",
        args.stage_r54_dir / "pricefm_stage_r54_chain_metrics.csv",
        args.stage_r53_prep_dir / "pricefm_stage_r52_case_manifest.csv",
        args.stage_r53_prep_dir / "pricefm_stage_r53_launch_manifest.csv",
    ]
    return {
        "article_repo_head": git_head(Path(__file__).resolve().parents[3]),
        "sources": [
            {"path": str(path.resolve()), "bytes": path.stat().st_size, "sha256": sha256(path)}
            for path in sources
        ],
        "outputs": [
            {"path": str(path.resolve()), "bytes": path.stat().st_size, "sha256": sha256(path)}
            for path in output_files if path.is_file()
        ],
    }


def write_report(path: Path, summary: dict, confirmation: pd.DataFrame, inventory: pd.DataFrame) -> None:
    target_text = "none"
    if not confirmation.empty:
        target_text = ", ".join(f"{row.region} fold {int(row.fold)}" for row in confirmation.itertuples())
    cleanup_gib = float(inventory.loc[inventory.retention_action.eq("cleanup_review"), "gib"].sum())
    path.write_text("\n".join([
        "# PriceFM Stage-R55 functional convergence audit",
        "",
        "## Decision",
        "",
        f"R53/R54 is complete, but zero of {summary['cases']} cases passes the registered confirmation gate.",
        f"The only bounded confirmation design target is {target_text}; launch remains unauthorized.",
        "",
        "## Diagnosis",
        "",
        f"- Validation-selected dual-reference comparison cases: {summary['validation_selected_dual_reference_cases']}.",
        f"- Bounded full-budget confirmation targets: {summary['bounded_confirmation_targets']}.",
        f"- Cases passing modern scalar diagnostics: {summary['modern_diagnostic_pass_cases']}.",
        f"- Regenerable storage marked for cleanup review: {cleanup_gib:.2f} GiB.",
        "- Test results are audit-only and do not reopen model or quantile selection.",
        "- No registry, article, launch YAML, fitting, or deletion is authorized by this stage.",
        "",
        "## Recommended sequence",
        "",
        "1. Review the functional and modern scalar diagnostics.",
        "2. Audit exact restart/checkpoint capability and the full-budget runtime before materializing a launch.",
        "3. If authorized later, confirm only the frozen seven-quantile target and reapply all R54 gates.",
        "4. Freeze an integration handoff before any cleanup or article action.",
        "",
    ]), encoding="utf-8")


def run(args) -> dict:
    prepare_output(args.output_dir, args.force)
    decisions, classic, quantile, chain_metrics, manifest, cases = load_inputs(args)
    modern = compute_modern_diagnostics(manifest, args)
    comparison = diagnostic_comparison_cases(decisions)
    functional = compute_path_stability(comparison, manifest, cases, chain_metrics, args)
    triage = build_case_triage(decisions, modern, functional)
    confirmation = build_confirmation_manifest(triage, manifest, args)
    if len(confirmation) != args.expected_confirmation_targets:
        raise RuntimeError(
            f"Bounded confirmation target count changed: {len(confirmation)} != {args.expected_confirmation_targets}"
        )
    inventory, hashes = build_retention_inventory(args, confirmation)

    outputs = {
        "modern": args.output_dir / "pricefm_stage_r55_modern_scalar_diagnostics.csv",
        "functional": args.output_dir / "pricefm_stage_r55_functional_stability.csv",
        "triage": args.output_dir / "pricefm_stage_r55_case_triage.csv",
        "confirmation": args.output_dir / "pricefm_stage_r55_confirmation_design.csv",
        "inventory": args.output_dir / "pricefm_stage_r55_retention_inventory.csv",
        "hashes": args.output_dir / "pricefm_stage_r55_retained_evidence_hashes.csv",
    }
    modern.to_csv(outputs["modern"], index=False)
    functional.to_csv(outputs["functional"], index=False)
    triage.to_csv(outputs["triage"], index=False)
    confirmation.to_csv(outputs["confirmation"], index=False)
    inventory.to_csv(outputs["inventory"], index=False)
    hashes.to_csv(outputs["hashes"], index=False)

    summary = {
        "status": "completed_read_only_functional_convergence_audit",
        "cases": int(len(triage)),
        "chain_jobs": int(len(manifest)),
        "validation_selected_cases": int(bool_series(triage, "validation_selected").sum()),
        "validation_selected_dual_reference_cases": int(triage.validation_selected_dual_reference.sum()),
        "bounded_confirmation_targets": int(triage.bounded_confirmation_target.sum()),
        "modern_diagnostic_pass_cases": int(triage.modern_diagnostics_pass.sum()),
        "functional_comparison_cases": int(len(comparison)),
        "confirmation_launch_authorized": False,
        "cleanup_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    summary_path = args.output_dir / "summary.json"
    write_json(summary_path, summary)
    report_path = args.output_dir / "pricefm_stage_r55_functional_convergence_report.md"
    write_report(report_path, summary, confirmation, inventory)
    manifest_data = source_manifest(args, list(outputs.values()) + [summary_path, report_path])
    write_json(args.output_dir / "source_manifest.json", manifest_data)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> None:
    run(parser().parse_args())


if __name__ == "__main__":
    main()
