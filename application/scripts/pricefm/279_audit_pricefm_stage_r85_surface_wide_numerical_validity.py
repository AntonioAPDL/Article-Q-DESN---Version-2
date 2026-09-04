#!/usr/bin/env python3
"""Quarantine R84 and audit every R76/R83 exAL atom under one numerical gate."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
from typing import Any

import numpy as np
import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R76 = DATA / "experiment_grids/pricefm_stage_r76_repaired_exal_surface_20260902"
R83 = DATA / "experiment_grids/pricefm_stage_r83_structured_init_failed_atom_retry_20260904"
R84 = DATA / "authoritative/pricefm_stage_r84_independent_vb_family_selection_20260904"
OUTPUT = DATA / "authoritative/pricefm_stage_r85_surface_wide_numerical_audit_20260904"
BINARY_SUFFIXES = {".rds", ".rda", ".RData", ".rdata"}
TRACE_COLUMNS = ["sigma", "gamma", "delta_state", "delta_sigma", "delta_gamma", "delta_s"]
RUNTIME = {
    "R76": ("1.1.1.9002", "scale-aware-SPD-plus-large-n-GIG"),
    "R83": (
        "1.1.1.9004",
        "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-plus-structured-plugin-init",
    ),
}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r76-manifest", type=Path, default=R76 / "task_manifest.csv")
    p.add_argument("--r76-status", type=Path, default=R76 / "launch_status.csv")
    p.add_argument("--r83-manifest", type=Path, default=R83 / "retry_manifest.csv")
    p.add_argument("--r83-status", type=Path, default=R83 / "launch_status.csv")
    p.add_argument("--r83-summary", type=Path, default=R83 / "launch_summary.json")
    p.add_argument("--r84-summary", type=Path, default=R84 / "summary.json")
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--force", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def boolish(value: Any) -> bool:
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def numeric_frame(frame: pd.DataFrame, columns: list[str], source: Path) -> pd.DataFrame:
    try:
        return frame.loc[:, columns].apply(pd.to_numeric, errors="raise").astype(float)
    except (KeyError, TypeError, ValueError) as error:
        raise RuntimeError(f"Invalid numerical trace: {source}") from error


def trace_diagnostics(trace: pd.DataFrame, parameter: pd.Series, minimum_updates: int) -> dict[str, Any]:
    numeric = numeric_frame(trace, TRACE_COLUMNS, Path("<in-memory>"))
    values = numeric.to_numpy(dtype=float)
    beta_l2 = float(parameter.beta_l2)
    al_beta_l2 = float(parameter.al_init_beta_l2)
    diagnostics = {
        "trace_finite": bool(np.isfinite(values).all()),
        "structured_updates_pass": bool(len(numeric) >= minimum_updates),
        "max_sigma": float(numeric.sigma.max()),
        "beta_l2_ratio": float(beta_l2 / max(al_beta_l2, 1e-12)),
        "max_abs_gamma": float(numeric.gamma.abs().max()),
        "first_delta_state": float(numeric.delta_state.iloc[0]),
        "tail_max_delta_state": float(numeric.tail(10).delta_state.max()),
        "tail_max_delta_sigma": float(numeric.tail(10).delta_sigma.max()),
        "final_delta_state": float(numeric.delta_state.iloc[-1]),
        "final_delta_sigma": float(numeric.delta_sigma.iloc[-1]),
    }
    diagnostics.update({
        "sigma_bound_pass": diagnostics["max_sigma"] < 100,
        "beta_bound_pass": diagnostics["beta_l2_ratio"] < 10,
        "gamma_bound_pass": diagnostics["max_abs_gamma"] < 4,
        "first_step_bound_pass": diagnostics["first_delta_state"] < 100,
        "tail_bound_pass": (
            diagnostics["tail_max_delta_state"] < 2
            and diagnostics["tail_max_delta_sigma"] < 2
        ),
    })
    diagnostics["visible_numerical_bounds_pass"] = bool(
        diagnostics["trace_finite"]
        and diagnostics["structured_updates_pass"]
        and diagnostics["sigma_bound_pass"]
        and diagnostics["beta_bound_pass"]
        and diagnostics["gamma_bound_pass"]
        and diagnostics["first_step_bound_pass"]
        and diagnostics["tail_bound_pass"]
    )
    return diagnostics


def audit_output(output: Path, task_id: str, source_stage: str) -> dict[str, Any]:
    terminal_path = output / "terminal.json"
    terminal = json.loads(terminal_path.read_text())
    if (
        terminal.get("status") != "completed"
        or terminal.get("task_id") != task_id
        or terminal.get("test_loaded") is not False
    ):
        raise RuntimeError(f"Invalid completed terminal: {terminal_path}")
    required = [
        "predictions_scaled.csv", "method_summary.csv", "parameter_summary.csv",
        "beta_summary.csv", "vb_trace.csv", "warm_start_manifest.json",
    ]
    if source_stage == "R83":
        required.append("structured_initialization.json")
    hashes = terminal.get("artifact_sha256") or {}
    for name in required:
        path = output / name
        if not path.is_file() or hashes.get(name) != sha256(path):
            raise RuntimeError(f"Changed completed artifact: {path}")
    if any(path.suffix in BINARY_SUFFIXES for path in output.rglob("*") if path.is_file()):
        raise RuntimeError(f"Binary model artifact found: {output}")
    version, repair = RUNTIME[source_stage]
    package = terminal.get("package") or {}
    if package.get("version") != version or package.get("repair") != repair:
        raise RuntimeError(f"Runtime provenance mismatch: {terminal_path}")
    method = pd.read_csv(output / "method_summary.csv").iloc[0]
    parameter = pd.read_csv(output / "parameter_summary.csv").iloc[0]
    trace = pd.read_csv(output / "vb_trace.csv")
    diagnostics = trace_diagnostics(trace, parameter, minimum_updates=35)
    return {
        "source_stage": source_stage,
        "source_task_id": task_id,
        "output_dir": str(output.resolve()),
        "terminal_path": str(terminal_path.resolve()),
        "terminal_sha256": sha256(terminal_path),
        "prediction_path": str((output / "predictions_scaled.csv").resolve()),
        "prediction_sha256": sha256(output / "predictions_scaled.csv"),
        "beta_path": str((output / "beta_summary.csv").resolve()),
        "beta_sha256": sha256(output / "beta_summary.csv"),
        "package_version": version,
        "package_repair": repair,
        "converged": boolish(method.converged),
        "iter": int(method.iter),
        "structured_updates": int(method.structured_updates),
        **diagnostics,
        "test_opened": False,
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest76 = pd.read_csv(args.r76_manifest)
    status76 = pd.read_csv(args.r76_status).set_index("task_id")
    manifest83 = pd.read_csv(args.r83_manifest)
    status83 = pd.read_csv(args.r83_status).set_index("task_id")
    summary83 = json.loads(args.r83_summary.read_text())
    summary84 = json.loads(args.r84_summary.read_text())
    if len(manifest76) != 294 or manifest76.task_id.duplicated().any():
        raise RuntimeError("R76 is not the frozen 294-atom exAL surface")
    if summary83.get("status") != "completed" or summary83.get("failed") != 0:
        raise RuntimeError("R83 did not complete cleanly")
    if summary84.get("test_opened") is not False:
        raise RuntimeError("R84 test firewall was not preserved")
    completed76 = manifest76[manifest76.task_id.map(status76.status).eq("completed")].copy()
    failed76 = manifest76[manifest76.task_id.map(status76.status).eq("failed")].copy()
    if len(completed76) != 280 or len(failed76) != 14:
        raise RuntimeError("R76 terminal partition changed")
    replacements = manifest83.set_index("source_task_id")
    if set(replacements.index) != set(failed76.task_id) or len(manifest83) != 14:
        raise RuntimeError("R83 is not the exact 14-atom R76 replacement set")

    rows: list[dict[str, Any]] = []
    for row in completed76.sort_values(["region", "fold", "tau"]).itertuples(index=False):
        audit = audit_output(Path(row.output_dir), row.task_id, "R76")
        rows.append({
            "case_id": row.case_id, "region": row.region, "fold": int(row.fold),
            "tau": float(row.tau), "initializer_valid": False,
            "homogeneous_final_surface_eligible": False, **audit,
        })
    for original in failed76.sort_values(["region", "fold", "tau"]).itertuples(index=False):
        replacement = replacements.loc[original.task_id]
        if str(status83.loc[replacement.task_id, "status"]) not in {"completed", "skipped_completed"}:
            raise RuntimeError(f"R83 replacement incomplete: {replacement.task_id}")
        audit = audit_output(Path(replacement.output_dir), str(replacement.task_id), "R83")
        rows.append({
            "case_id": original.case_id, "region": original.region, "fold": int(original.fold),
            "tau": float(original.tau), "initializer_valid": True,
            "homogeneous_final_surface_eligible": bool(audit["visible_numerical_bounds_pass"]),
            **audit,
        })
    ledger = pd.DataFrame(rows).sort_values(["region", "fold", "tau"])
    if len(ledger) != 294 or ledger.case_id.nunique() != 42:
        raise RuntimeError("R85 atom ledger is incomplete")

    old_metrics = ledger[ledger.source_stage.eq("R76")].set_index("source_task_id")
    refit = completed76.copy()
    refit["r85_visible_numerical_bounds_pass"] = refit.task_id.map(
        old_metrics.visible_numerical_bounds_pass
    ).astype(bool)
    refit["r85_refit_reason"] = "invalid_nonsmooth_delta_initializer_requires_homogeneous_runtime"
    refit["r85_refit_required"] = True
    refit["test_access_authorized"] = False
    refit["registry_mutation_authorized"] = False
    refit["article_mutation_authorized"] = False
    retained = ledger[ledger.source_stage.eq("R83")].copy()
    case_summary = ledger.groupby(["case_id", "region", "fold"], as_index=False).agg(
        atoms=("tau", "size"),
        legacy_r76_atoms=("source_stage", lambda x: int((x == "R76").sum())),
        repaired_r83_atoms=("source_stage", lambda x: int((x == "R83").sum())),
        visibly_bounded_atoms=("visible_numerical_bounds_pass", "sum"),
    )
    case_summary["contains_invalid_initializer"] = case_summary.legacy_r76_atoms.gt(0)
    case_summary["r84_scientific_authority"] = False

    visible_failures = int((~old_metrics.visible_numerical_bounds_pass).sum())
    gates = pd.DataFrame([
        {"gate": "r76_partition_280_completed_14_failed", "passed": True, "observed": "280/14"},
        {"gate": "r83_exact_14_atom_replacement", "passed": len(retained) == 14, "observed": len(retained)},
        {"gate": "all_42_exal_cases_contain_legacy_initializer", "passed": bool(case_summary.contains_invalid_initializer.all()), "observed": int(case_summary.contains_invalid_initializer.sum())},
        {"gate": "r84_quarantined", "passed": True, "observed": "no scientific authority"},
        {"gate": "r86_refit_scope_is_all_280_legacy_atoms", "passed": len(refit) == 280, "observed": len(refit)},
        {"gate": "test_registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
    ])
    if not gates.passed.all():
        raise RuntimeError("R85 audit gates failed")

    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True)
    ledger.to_csv(output / "pricefm_stage_r85_atom_numerical_validity.csv", index=False)
    case_summary.to_csv(output / "pricefm_stage_r85_case_numerical_validity.csv", index=False)
    refit.to_csv(output / "pricefm_stage_r85_legacy_refit_manifest.csv", index=False)
    retained.to_csv(output / "pricefm_stage_r85_retained_r83_atoms.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r85_gates.csv", index=False)
    fixed = [args.r76_manifest, args.r76_status, args.r83_manifest, args.r83_status,
             args.r83_summary, args.r84_summary, Path(__file__).resolve()]
    pd.DataFrame([
        {"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in fixed
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "r84_quarantined_r86_homogeneous_refit_authorized",
        "atoms_audited": 294,
        "legacy_r76_atoms": 280,
        "legacy_r76_visible_bound_failures": visible_failures,
        "legacy_r76_atoms_requiring_refit": 280,
        "retained_r83_atoms": 14,
        "exal_cases": 42,
        "r84_scientific_authority": False,
        "r86_launch_prep_authorized": True,
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
        "joint_or_mcmc_authorized": False,
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    (output / "pricefm_stage_r85_surface_wide_numerical_audit_report.md").write_text(
        "# PriceFM Stage-R85 Surface-Wide Numerical Audit\n\n"
        f"R85 audited all 294 exAL atoms and found {visible_failures}/280 terminally completed "
        "R76 atoms outside at least one pre-registered R82 numerical bound. All 280 R76 atoms "
        "used the invalid nonsmooth delta initializer, so terminal appearance cannot establish "
        "estimator equivalence. R84 is quarantined. R86 may refit exactly those 280 atoms with "
        "the R82 structured plug-in initialization, retain the 14 R83 atoms, and leave the 392 "
        "R73 AL atoms unchanged. Test, registry, article, joint, and MCMC actions remain blocked.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
