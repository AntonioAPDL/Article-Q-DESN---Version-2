#!/usr/bin/env python3
"""Freeze a no-launch Stage-R64 joint-MCMC confirmation contract."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
SOURCE_ROOT = Path(__file__).resolve().parents[3]
R63_CLOSEOUT = DATA / "authoritative/pricefm_stage_r63_corrected_joint_closeout_20260827"
R63_GRID = DATA / "experiment_grids/pricefm_stage_r63_corrected_joint_campaign_20260827"
OUTPUT = DATA / "authoritative/pricefm_stage_r64_joint_mcmc_confirmation_prep_20260829"
TAUS = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--queue", type=Path, default=R63_CLOSEOUT / "pricefm_stage_r63_confirmation_queue.csv",
    )
    p.add_argument("--manifest", type=Path, default=R63_GRID / "launch_manifest.csv")
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--source-root", type=Path, default=SOURCE_ROOT)
    p.add_argument("--rscript", default="Rscript")
    p.add_argument("--expected-candidates", type=int, default=3)
    p.add_argument("--chains", type=int, default=4)
    p.add_argument("--n-iter", type=int, default=2000)
    p.add_argument("--burn", type=int, default=1000)
    p.add_argument("--thin", type=int, default=1)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def runtime_config(path: Path) -> dict:
    payload = yaml.safe_load(path.read_text())
    if not isinstance(payload, dict):
        raise RuntimeError(f"Invalid runtime config: {path}")
    cfg = payload.get("pricefm_stage_r61_joint_mechanism")
    if not isinstance(cfg, dict):
        raise RuntimeError(f"R64 requires an R61/R63 joint runtime config: {path}")
    return cfg


def probe_checkpoint(path: Path, rscript: str) -> dict:
    expression = r'''
x <- readRDS(commandArgs(TRUE)[[1L]])
scalar <- function(value, default = "") {
  if (is.null(value) || !length(value)) default else as.character(value[[1L]])
}
rhs <- x$rhs_control
values <- c(
  scalar(x$case_id), scalar(x$stage), scalar(x$format), scalar(x$likelihood_family),
  scalar(x$p), length(x$tau), length(x$beta), length(x$alpha), length(x$sigma),
  all(is.finite(as.numeric(x$beta))), all(is.finite(as.numeric(x$alpha))),
  all(is.finite(as.numeric(x$sigma))), scalar(rhs$anchor_tau0),
  scalar(rhs$innovation_tau0)
)
cat(paste(values, collapse = "\t"), "\n")
'''
    result = subprocess.run(
        [rscript, "-e", expression, str(path)], text=True, capture_output=True, check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Checkpoint probe failed for {path}: {result.stderr.strip()}")
    fields = result.stdout.strip().split("\t")
    if len(fields) != 14:
        raise RuntimeError(f"Checkpoint probe returned {len(fields)} fields for {path}")
    return {
        "checkpoint_case_id": fields[0], "checkpoint_stage_label": fields[1],
        "checkpoint_format": fields[2], "checkpoint_family": fields[3],
        "checkpoint_p": int(fields[4]), "checkpoint_K": int(fields[5]),
        "checkpoint_beta_length": int(fields[6]), "checkpoint_alpha_length": int(fields[7]),
        "checkpoint_sigma_length": int(fields[8]),
        "checkpoint_beta_finite": fields[9] == "TRUE",
        "checkpoint_alpha_finite": fields[10] == "TRUE",
        "checkpoint_sigma_finite": fields[11] == "TRUE",
        "checkpoint_anchor_tau0": float(fields[12]),
        "checkpoint_innovation_tau0": float(fields[13]),
    }


def kernel_capabilities(source_root: Path) -> pd.DataFrame:
    joint = source_root / "application/R/joint_qvp_qdesn.R"
    readiness = source_root / "application/R/joint_qdesn_mcmc_readiness.R"
    r50 = source_root / "application/scripts/pricefm/178_run_pricefm_stage_r50_mcmc_chain.R"
    joint_text = joint.read_text()
    readiness_text = readiness.read_text()
    r50_text = r50.read_text()
    pricefm_scripts = "\n".join(
        path.read_text(errors="replace")
        for path in sorted((source_root / "application/scripts/pricefm").glob("*"))
        if path.is_file() and path.suffix in {".R", ".py"} and path.name != Path(__file__).name
    )
    rows = [
        ("genuine_joint_al_mcmc_kernel", "implemented", "app_joint_qvp_fit_al_mcmc_tiny <- function" in joint_text, joint),
        ("split_anchor_innovation_rhs", "implemented", all(token in joint_text for token in ("anchor_tau0 = tau0", "innovation_tau0 = tau0")), joint),
        ("vb_checkpoint_initialization", "implemented", "init <- app_joint_qvp_normalize_init(init, K, p)" in joint_text, joint),
        ("joint_chain_pooling_diagnostics", "implemented", "app_joint_qdesn_phase122_pool_mcmc_chains" in readiness_text, readiness),
        ("collapsed_exal_gamma_kernel", "implemented_not_immediate", "collapsed_logit_slice" in joint_text, joint),
        ("old_pricefm_r50_is_joint_equivalent", "not_equivalent", not ("cfg$tau" in r50_text and "exal_mcmc_fit" in r50_text), r50),
        ("dedicated_pricefm_joint_mcmc_runner", "missing", "app_joint_qvp_fit_al_mcmc_tiny" in pricefm_scripts, source_root / "application/scripts/pricefm"),
        ("production_scale_runtime_benchmark", "missing", False, readiness),
    ]
    return pd.DataFrame([
        {"capability": name, "status": status, "supported": bool(supported), "evidence": str(path)}
        for name, status, supported, path in rows
    ])


def build_candidate_contract(queue: pd.DataFrame, manifest: pd.DataFrame, rscript: str) -> pd.DataFrame:
    rows = []
    for selected in queue.sort_values(["region", "fold"]).itertuples(index=False):
        match = manifest[manifest.case_id.astype(str).eq(str(selected.selected_case_id))]
        if len(match) != 1:
            raise RuntimeError(f"R63 winner lacks one manifest row: {selected.selected_case_id}")
        launch = match.iloc[0]
        config_path = Path(launch.config)
        cfg = runtime_config(config_path)
        model = Path(launch.output_dir)
        summary = json.loads((model / "job_summary.json").read_text())
        checkpoint = Path(selected.checkpoint)
        adapter = model.parent / "adapter"
        adapter_manifest_path = adapter / "adapter_manifest.json"
        adapter_manifest = json.loads(adapter_manifest_path.read_text())
        probe = probe_checkpoint(checkpoint, rscript)
        quantiles = [float(value) for value in cfg["quantiles"]]
        rhs = cfg["rhs_control"]
        checkpoint_hash_ok = sha256(checkpoint) == str(selected.checkpoint_sha256)
        summary_integrity_ok = (
            summary.get("status") == "completed"
            and summary.get("postfit_repaired") is True
            and summary.get("split_firewall") == "train_validation_only"
            and summary.get("test_accessed") is False
            and str(summary.get("checkpoint")) == str(checkpoint)
            and str(summary.get("checkpoint_sha256")) == str(selected.checkpoint_sha256)
        )
        schema_ok = (
            probe["checkpoint_case_id"] == str(selected.selected_case_id)
            and probe["checkpoint_format"] == "pricefm_joint_vb_checkpoint_v2"
            and probe["checkpoint_family"] == str(selected.selected_family)
            and str(cfg["likelihood_family"]) == str(selected.selected_family)
            and quantiles == TAUS
            and probe["checkpoint_p"] == int(summary["n_slopes"])
            and probe["checkpoint_K"] == len(TAUS)
            and probe["checkpoint_beta_length"] == int(summary["joint_dimension"])
            and probe["checkpoint_alpha_length"] == len(TAUS)
            and probe["checkpoint_sigma_length"] == len(TAUS)
            and all(probe[key] for key in (
                "checkpoint_beta_finite", "checkpoint_alpha_finite", "checkpoint_sigma_finite",
            ))
            and math.isclose(
                probe["checkpoint_anchor_tau0"], float(rhs["anchor_tau0"]),
                rel_tol=0, abs_tol=1e-15,
            )
            and math.isclose(
                probe["checkpoint_innovation_tau0"], float(rhs["innovation_tau0"]),
                rel_tol=0, abs_tol=1e-15,
            )
        )
        adapter_hash_contract = all(
            split in adapter_manifest.get("splits", {})
            and all(
                adapter_manifest["splits"][split].get(name)
                for name in ("X_sha256", "y_sha256", "rows_sha256")
            )
            for split in ("train", "val")
        )
        rows.append({
            "source_case_id": selected.source_case_id, "region": selected.region,
            "fold": int(selected.fold), "selected_case_id": selected.selected_case_id,
            "selected_family": selected.selected_family,
            "fit_structure": "single_joint_ordered_seven_quantile_model",
            "quantiles": ";".join(map(str, quantiles)), "K": len(quantiles),
            "n_train": int(summary["n_train"]), "n_validation": int(summary["n_validation"]),
            "n_slopes": int(summary["n_slopes"]),
            "joint_dimension": int(summary["joint_dimension"]),
            "anchor_tau0": float(rhs["anchor_tau0"]),
            "innovation_tau0": float(rhs["innovation_tau0"]),
            "vb_elapsed_seconds": float(summary["elapsed_seconds"]),
            "vb_iterations": int(summary["iterations"]),
            "validation_AQL": float(selected.selected_contract_validation_AQL),
            "independent_validation_AQL": float(selected.independent_validation_AQL),
            "old_joint_validation_AQL": float(selected.old_joint_validation_AQL),
            "checkpoint": str(checkpoint), "checkpoint_sha256": str(selected.checkpoint_sha256),
            "checkpoint_hash_ok": checkpoint_hash_ok, "checkpoint_schema_ok": schema_ok,
            "r63_summary_integrity_ok": summary_integrity_ok,
            "checkpoint_stage_label": probe["checkpoint_stage_label"],
            "legacy_stage_label_only": probe["checkpoint_stage_label"] == "R61",
            "runtime_config": str(config_path), "runtime_config_sha256": sha256(config_path),
            "smoke_config": str(Path(cfg["smoke_config"])),
            "adapter_manifest": str(adapter_manifest_path),
            "adapter_hash_contract_retained": adapter_hash_contract,
            "adapter_rebuild_required": True, "adapter_rebuild_verified": False,
            "selection_role": "frozen_r63_validation_only",
            "test_access_authorized": False, "mcmc_launch_authorized": False,
            "registry_mutation_authorized": False, "article_mutation_authorized": False,
        })
    return pd.DataFrame(rows)


def resource_envelope(candidates: pd.DataFrame, chains: int, n_iter: int) -> pd.DataFrame:
    out = candidates[[
        "source_case_id", "region", "fold", "n_train", "n_slopes", "K",
        "joint_dimension", "vb_elapsed_seconds", "vb_iterations",
    ]].copy()
    out["latent_cells_per_chain"] = out.n_train * out.K
    out["stacked_design_nnz_per_iteration"] = out.n_train * out.n_slopes * out.K
    out["stacked_design_conservative_gib"] = (
        out.stacked_design_nnz_per_iteration * 16 / 2**30
    )
    out["precision_dense_gib"] = out.joint_dimension.pow(2) * 8 / 2**30
    out["planned_chains"] = int(chains)
    out["planned_iterations_per_chain"] = int(n_iter)
    out["vb_linear_hours_per_chain"] = (
        out.vb_elapsed_seconds / 3600 * n_iter / out.vb_iterations
    )
    out["vb_linear_core_hours_all_chains"] = out.vb_linear_hours_per_chain * chains
    out["runtime_estimate_role"] = "heuristic_only_not_a_production_mcmc_benchmark"
    out["production_runtime_validated"] = False
    return out


def chain_seed_plan(candidates: pd.DataFrame, chains: int) -> pd.DataFrame:
    rows = []
    for case_index, selected in enumerate(
        candidates.sort_values(["region", "fold"]).itertuples(index=False), start=1,
    ):
        for chain in range(1, chains + 1):
            rows.append({
                "source_case_id": selected.source_case_id, "region": selected.region,
                "fold": int(selected.fold), "chain": chain,
                "seed": 2026082900 + case_index * 100 + chain,
                "status": "design_only_not_launchable", "mcmc_launch_authorized": False,
            })
    return pd.DataFrame(rows)


def source_manifest(paths: list[Path]) -> pd.DataFrame:
    unique = sorted({Path(path).resolve() for path in paths if Path(path).is_file()})
    return pd.DataFrame([
        {"path": str(path), "sha256": sha256(path), "bytes": int(path.stat().st_size)}
        for path in unique
    ])


def report(candidates: pd.DataFrame, resources: pd.DataFrame, gates: pd.DataFrame) -> str:
    winner_lines = [
        f"- {row.region} fold {int(row.fold)}: AL, validation AQL {row.validation_AQL:.6f}, "
        f"dimension {int(row.joint_dimension):,}."
        for row in candidates.itertuples(index=False)
    ]
    max_hours = resources.vb_linear_hours_per_chain.max()
    return "\n".join([
        "# PriceFM Stage-R64 joint-MCMC confirmation prep", "",
        "R64 freezes the three R63 validation winners without opening test data or creating a launch YAML.",
        "It requires one genuine joint ordered seven-quantile model per region/fold and explicitly rejects",
        "the historical Stage-R50 independent single-tau runner as an equivalent confirmation engine.", "",
        "## Frozen candidates", "", *winner_lines, "",
        "## Capability decision", "",
        "The core joint AL kernel accepts the full VB checkpoint state and split anchor/innovation RHS scales.",
        "However, no dedicated PriceFM joint-MCMC runner rebuilds and verifies the cleaned adapter, and the",
        "current prototype reconstructs a large sparse stacked design inside every MCMC iteration. Full-data",
        f"runtime is unbenchmarked; linear VB scaling alone reaches up to {max_hours:.1f} hours per chain.",
        "Launching now would therefore turn confirmatory inference into an uncontrolled compute experiment.", "",
        "## Required next implementation", "",
        "Implement a dedicated, resumable PriceFM joint-MCMC runner with hash-verified adapter reconstruction,",
        "checkpoint mapping, cached/blockwise sufficient-statistic operations, one thread per chain, and durable",
        "Rhat/ESS and prediction diagnostics. Benchmark that exact kernel before authorizing the frozen 12-chain",
        "campaign. Test, registry, article, main, and Overleaf remain blocked.", "",
        f"Hard/prelaunch gates passing now: {int(gates.passed.sum())}/{len(gates)}.", "",
    ])


def run(args: argparse.Namespace) -> dict:
    if args.expected_candidates < 1 or args.chains < 4:
        raise ValueError("R64 requires a positive candidate count and at least four chains")
    if args.n_iter <= 0 or args.burn < 0 or args.burn >= args.n_iter or args.thin < 1:
        raise ValueError("Invalid R64 MCMC design controls")
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    queue = pd.read_csv(args.queue)
    manifest = pd.read_csv(args.manifest)
    if len(queue) != args.expected_candidates:
        raise RuntimeError(
            f"R64 expected {args.expected_candidates} frozen candidates; observed {len(queue)}"
        )
    if not queue.validation_confirmation_eligible.astype(bool).all():
        raise RuntimeError("R64 queue contains a candidate that failed the R63 validation gate")
    if queue.test_opened.astype(bool).any():
        raise RuntimeError("R64 refuses an R63 queue that opened test data")

    candidates = build_candidate_contract(queue, manifest, args.rscript)
    capabilities = kernel_capabilities(args.source_root.resolve())
    resources = resource_envelope(candidates, args.chains, args.n_iter)
    seeds = chain_seed_plan(candidates, args.chains)
    if seeds.seed.duplicated().any():
        raise RuntimeError("R64 chain seeds are not unique")
    capability = capabilities.set_index("capability").supported.to_dict()
    gates = pd.DataFrame([
        {"gate": "frozen_r63_queue", "passed": len(candidates) == args.expected_candidates, "observed": len(candidates)},
        {"gate": "validation_only_selection", "passed": not queue.test_opened.astype(bool).any(), "observed": False},
        {"gate": "all_checkpoint_hashes", "passed": candidates.checkpoint_hash_ok.all(), "observed": int(candidates.checkpoint_hash_ok.sum())},
        {"gate": "all_checkpoint_schemas", "passed": candidates.checkpoint_schema_ok.all(), "observed": int(candidates.checkpoint_schema_ok.sum())},
        {"gate": "all_r63_summary_integrity", "passed": candidates.r63_summary_integrity_ok.all(), "observed": int(candidates.r63_summary_integrity_ok.sum())},
        {"gate": "seven_joint_quantiles", "passed": candidates.K.eq(7).all(), "observed": ";".join(map(str, sorted(candidates.K.unique())))},
        {"gate": "adapter_hash_contract_retained", "passed": candidates.adapter_hash_contract_retained.all(), "observed": int(candidates.adapter_hash_contract_retained.sum())},
        {"gate": "genuine_joint_al_kernel", "passed": capability["genuine_joint_al_mcmc_kernel"], "observed": capability["genuine_joint_al_mcmc_kernel"]},
        {"gate": "split_rhs_kernel", "passed": capability["split_anchor_innovation_rhs"], "observed": capability["split_anchor_innovation_rhs"]},
        {"gate": "old_r50_runner_rejected", "passed": not capability["old_pricefm_r50_is_joint_equivalent"], "observed": "independent_single_tau"},
        {"gate": "adapter_rebuild_replayed", "passed": False, "observed": "pending"},
        {"gate": "dedicated_pricefm_joint_runner", "passed": capability["dedicated_pricefm_joint_mcmc_runner"], "observed": capability["dedicated_pricefm_joint_mcmc_runner"]},
        {"gate": "production_runtime_benchmark", "passed": capability["production_scale_runtime_benchmark"], "observed": capability["production_scale_runtime_benchmark"]},
        {"gate": "mcmc_launch_blocked", "passed": True, "observed": False},
        {"gate": "registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    candidates.to_csv(output / "pricefm_stage_r64_candidate_contract.csv", index=False)
    capabilities.to_csv(output / "pricefm_stage_r64_kernel_capability_audit.csv", index=False)
    resources.to_csv(output / "pricefm_stage_r64_resource_envelope.csv", index=False)
    seeds.to_csv(output / "pricefm_stage_r64_chain_seed_plan.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r64_prelaunch_gates.csv", index=False)
    source_paths = [
        Path(__file__).resolve(), args.queue, args.manifest,
        args.queue.parent / "summary.json",
        args.queue.parent / "pricefm_stage_r63_case_decisions.csv",
        args.queue.parent / "pricefm_stage_r63_closeout_gates.csv",
        args.queue.parent / "source_manifest.csv",
        args.source_root / "application/R/joint_qvp_qdesn.R",
        args.source_root / "application/R/joint_qdesn_mcmc_readiness.R",
        args.source_root / "application/scripts/pricefm/178_run_pricefm_stage_r50_mcmc_chain.R",
    ]
    for row in candidates.itertuples(index=False):
        source_paths.extend([
            Path(row.checkpoint), Path(row.runtime_config), Path(row.smoke_config),
            Path(row.adapter_manifest), Path(row.adapter_manifest).with_name("feature_manifest.json"),
            Path(row.adapter_manifest).with_name("feature_map_matrix.npz"),
        ])
    source_manifest(source_paths).to_csv(output / "source_manifest.csv", index=False)
    blocking = gates.loc[~gates.passed, "gate"].tolist()
    summary = {
        "status": "completed_r64_design_blocked_before_launch",
        "frozen_candidates": len(candidates), "candidate_cells": [
            f"{row.region}/fold={int(row.fold)}" for row in candidates.itertuples(index=False)
        ],
        "likelihood_families": sorted(candidates.selected_family.unique()),
        "planned_chains_per_candidate": int(args.chains),
        "planned_total_chains": int(len(seeds)), "planned_n_iter": int(args.n_iter),
        "planned_burn": int(args.burn), "planned_thin": int(args.thin),
        "blocking_gates": blocking, "launch_yaml_written": False,
        "adapter_rebuild_performed": False, "models_fit": 0, "test_opened": False,
        "mcmc_launch_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r64_joint_mcmc_confirmation_report.md").write_text(
        report(candidates, resources, gates)
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
