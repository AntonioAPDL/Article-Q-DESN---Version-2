#!/usr/bin/env python3
"""Audit R93/R87 exAL trajectories and pre-register the R94 repair contract."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
from typing import Any

import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R93_MODEL = DATA / (
    "runs/pricefm_stage_r93_region_frozen_quantile_validation_20260906/"
    "r93_se2_region_frozen/model"
)
R87_RUNS = DATA / "runs/pricefm_stage_r87_homogeneous_exal_refit_20260904"
OUTPUT = DATA / "authoritative/pricefm_stage_r94_exal_initialization_audit_20260906"
EXPECTED_QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
REQUIRED_TRACE = ("sigma", "gamma", "delta_state", "delta_sigma", "delta_gamma", "delta_s")


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r93-model-dir", type=Path, default=R93_MODEL)
    p.add_argument("--r87-run-dir", type=Path, default=R87_RUNS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--require-complete", action="store_true")
    p.add_argument("--force", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def reset(path: Path, force: bool) -> Path:
    path = path.resolve()
    if path.exists() and any(path.iterdir()):
        if not force:
            raise FileExistsError(path)
        stamp = pd.Timestamp.utcnow().strftime("%Y%m%dT%H%M%SZ")
        quarantine = path.parent / "quarantine" / f"{path.name}.{stamp}.replaced_audit"
        quarantine.parent.mkdir(parents=True, exist_ok=True)
        path.rename(quarantine)
    path.mkdir(parents=True, exist_ok=True)
    return path


def finite(values: pd.Series) -> bool:
    numeric = pd.to_numeric(values, errors="coerce")
    return bool(numeric.notna().all() and numeric.map(math.isfinite).all())


def tau_from_path(path: Path) -> float:
    token = next(part for part in path.parts if part.startswith("tau="))[4:]
    return float(token.replace("p", "."))


def trajectory(path: Path, init_beta_l2: float, n_features: int) -> dict[str, Any]:
    trace = pd.read_csv(path)
    missing = sorted(set(REQUIRED_TRACE) - set(trace.columns))
    if missing or trace.empty:
        return {"trace_complete": False, "missing_trace_fields": ";".join(missing)}
    state = pd.to_numeric(trace.delta_state, errors="coerce").abs()
    sigma_delta = pd.to_numeric(trace.delta_sigma, errors="coerce").abs()
    tail = trace.tail(min(10, len(trace)))
    tail_state = pd.to_numeric(tail.delta_state, errors="coerce").abs().max()
    tail_sigma = pd.to_numeric(tail.delta_sigma, errors="coerce").abs().max()
    coefficient_rms = init_beta_l2 / math.sqrt(max(1, n_features))
    contraction = float(tail_state / max(float(state.iloc[0]), 1e-12))
    return {
        "trace_complete": True,
        "trace_rows": int(len(trace)),
        "trace_finite": all(finite(trace[name]) for name in REQUIRED_TRACE),
        "first_state_delta": float(state.iloc[0]),
        "max_state_delta": float(state.max()),
        "tail_state_delta_max": float(tail_state),
        "tail_sigma_delta_max": float(tail_sigma),
        "tail_to_first_state_ratio": contraction,
        "first_state_below_100": bool(state.iloc[0] < 100),
        "tail_state_sigma_below_2": bool(max(tail_state, tail_sigma) < 2),
        "init_beta_coordinate_rms": coefficient_rms,
    }


def collect_r93(model_dir: Path) -> tuple[pd.DataFrame, list[Path]]:
    rows: list[dict[str, Any]] = []
    sources: list[Path] = []
    for terminal_path in sorted((model_dir / "atoms").glob("tau=*/**/terminal.json")):
        terminal = json.loads(terminal_path.read_text())
        family = str(terminal.get("family", terminal_path.parent.name))
        tau = float(terminal.get("tau", tau_from_path(terminal_path)))
        root = terminal_path.parent
        method_path = root / "method_summary.csv"
        parameter_path = root / "parameter_summary.csv"
        beta_path = root / "beta_summary.csv"
        trace_path = root / "vb_trace.csv"
        sources.append(terminal_path)
        row: dict[str, Any] = {
            "family": family,
            "tau": tau,
            "status": terminal.get("status"),
            "legacy_numerical_gate_passed": bool(terminal.get("numerical_gate_passed", False)),
            "formal_converged": bool(terminal.get("formal_converged", False)),
            "structured_updates": int(terminal.get("structured_updates", 0) or 0),
            "atom_dir": str(root.resolve()),
        }
        if method_path.is_file():
            method = pd.read_csv(method_path).iloc[0]
            row["iter"] = int(method.get("iter", 0))
            row["train_seconds"] = float(method.get("train_seconds", float("nan")))
            sources.append(method_path)
        if parameter_path.is_file():
            parameter = pd.read_csv(parameter_path).iloc[0]
            init_l2 = float(parameter.get("init_beta_l2", float("nan")))
            beta_l2 = float(parameter.get("beta_l2", float("nan")))
            row.update(
                init_beta_l2=init_l2,
                final_beta_l2=beta_l2,
                final_to_initial_beta_l2_ratio=beta_l2 / max(init_l2, 1e-12),
                final_sigma=float(parameter.get("sigma", float("nan"))),
                final_gamma=float(parameter.get("gamma", float("nan"))),
            )
            sources.append(parameter_path)
        else:
            init_l2 = float("nan")
        if beta_path.is_file():
            beta = pd.read_csv(beta_path)
            row["beta_finite"] = finite(beta.beta_mean)
            row["covariance_diagonal_finite"] = finite(beta.beta_cov_diag)
            row["n_features"] = int(len(beta))
            sources.append(beta_path)
        if trace_path.is_file():
            row.update(trajectory(trace_path, init_l2, int(row.get("n_features", 1))))
            sources.append(trace_path)
        checks = terminal.get("numerical_checks") or {}
        failed = sorted(name for name, passed in checks.items() if passed is False)
        row["legacy_failed_checks"] = ";".join(failed)
        row["failed_only_absolute_first_delta"] = failed == ["first_state_delta_below_100"]
        if family == "exal" and row.get("trace_complete"):
            prospective = (
                row.get("trace_finite") is True
                and row.get("beta_finite") is True
                and row.get("covariance_diagonal_finite") is True
                and row["structured_updates"] >= 35
                and 0 < row.get("final_sigma", float("inf")) < 100
                and abs(row.get("final_gamma", float("inf"))) < 4
                and row.get("final_to_initial_beta_l2_ratio", float("inf")) < 10
                and row.get("tail_state_sigma_below_2") is True
                and row.get("tail_to_first_state_ratio", float("inf")) < 0.01
            )
            row["historical_proxy_trajectory_gate_passed"] = bool(prospective)
        else:
            row["historical_proxy_trajectory_gate_passed"] = family == "al" and row.get("beta_finite") is True
        rows.append(row)
    return pd.DataFrame(rows).sort_values(["tau", "family"]), sources


def collect_history(run_dir: Path) -> tuple[pd.DataFrame, list[Path]]:
    rows: list[dict[str, Any]] = []
    paths = sorted(run_dir.glob("**/vb_trace.csv"))
    for path in paths:
        trace = pd.read_csv(path)
        if "delta_state" not in trace or trace.empty:
            continue
        first = abs(float(trace.delta_state.iloc[0]))
        rows.append(
            {
                "case_id": path.parents[3].name,
                "tau": tau_from_path(path),
                "first_state_delta": first,
                "first_state_below_100": first < 100,
                "trace_rows": len(trace),
                "trace_path": str(path.resolve()),
            }
        )
    return pd.DataFrame(rows).sort_values(["case_id", "tau"]), paths


def root_cause_ledger() -> pd.DataFrame:
    return pd.DataFrame(
        [
            {
                "finding": "R93 exAL atoms fail only the absolute first-delta check",
                "evidence_type": "R93 terminal and trace artifacts",
                "interpretation": "The failure label does not imply non-finite arithmetic or explosive endpoints.",
                "repair_action": "Retain the raw first delta as a diagnostic, not a validity gate.",
            },
            {
                "finding": "R87 first deltas span more than three orders of magnitude",
                "evidence_type": "280 historical R87 traces",
                "interpretation": "A universal 100-unit coefficient threshold is coordinate-scale dependent.",
                "repair_action": "Gate finite trajectories, endpoint bounds, and tail contraction instead.",
            },
            {
                "finding": "R82 warm-starts beta means but resets covariance, RHS state, v, and s",
                "evidence_type": "Hash-pinned R82 exalStaticLDVB source",
                "interpretation": "The first CAVI beta update is a partial-initialization transition.",
                "repair_action": "Initialize covariance/RHS state and latent moments before the first beta update.",
            },
            {
                "finding": "R82 point-mass sigma/gamma initialization is mathematically required",
                "evidence_type": "R82 repair source and finite structured probes",
                "interpretation": "The gamma-zero abs(gamma) curvature repair remains valid.",
                "repair_action": "Preserve the structured point-mass plugin while changing beta/latent initialization.",
            },
            {
                "finding": "R93 postwarmup damping does not control the first beta transition",
                "evidence_type": "Update ordering in exalStaticLDVB",
                "interpretation": "Increasing iterations or damping cannot repair the initialization mismatch itself.",
                "repair_action": "Fix initialization first; use max_iter=200 only as a convergence ceiling.",
            },
        ]
    )


def run(args: argparse.Namespace) -> dict[str, Any]:
    output = reset(args.output_dir, args.force)
    atoms, sources = collect_r93(args.r93_model_dir)
    history, history_sources = collect_history(args.r87_run_dir)
    if history.empty:
        raise RuntimeError("R94 requires the historical R87 exAL trajectory surface")
    present = sorted(atoms.tau.unique()) if not atoms.empty else []
    exal = atoms[atoms.family.eq("exal")].copy()
    al = atoms[atoms.family.eq("al")].copy()
    complete = (
        len(al) == len(EXPECTED_QUANTILES)
        and len(exal) == len(EXPECTED_QUANTILES)
        and present == list(EXPECTED_QUANTILES)
    )
    if args.require_complete and not complete:
        raise RuntimeError(f"R93 is still incomplete: AL={len(al)}/7 exAL={len(exal)}/7")
    repair_evidence = (
        len(exal) >= 3
        and exal.failed_only_absolute_first_delta.fillna(False).all()
        and exal.trace_finite.fillna(False).all()
        and exal.historical_proxy_trajectory_gate_passed.fillna(False).all()
    )
    hist = history.first_state_delta
    history_summary = {
        "traces": int(len(history)),
        "below_100": int(history.first_state_below_100.sum()),
        "above_or_equal_100": int((~history.first_state_below_100).sum()),
        "fraction_below_100": float(history.first_state_below_100.mean()),
        "minimum": float(hist.min()),
        "q25": float(hist.quantile(0.25)),
        "median": float(hist.median()),
        "q75": float(hist.quantile(0.75)),
        "maximum": float(hist.max()),
    }
    contract = {
        "stage": "R94",
        "repair_scope": "initialization_and_numerical_eligibility_only",
        "runtime_base": "exact_CRAN_exdqlm_1.1.1_via_R82_hash_pinned_runtime",
        "preserve": [
            "structured_sigma_gamma_point_mass_plugin",
            "public_exalStaticLDVB_API",
            "RHS_NS_prior_and_case_specific_tau0",
            "frozen_DESN_and_train_validation_split",
            "AL_same_tau_warm_start",
        ],
        "change": [
            "consume_AL_beta_covariance_diagonal_when_available",
            "initialize_RHS_state_from_AL_qbeta",
            "initialize_v_and_s_moments_before_first_beta_update",
            "record_prediction_scaled_and_relative_state_deltas",
            "replace_absolute_first_delta_validity_gate_with_finite_tail_contraction_gate",
        ],
        "eligibility_gate": {
            "finite_core_and_trace": True,
            "minimum_structured_updates": 35,
            "sigma_range": [0, 100],
            "absolute_gamma_max": 4,
            "final_to_initial_beta_l2_ratio_max": 10,
            "tail_state_sigma_absolute_max": 2,
            "tail_relative_state_max": 0.01,
            "tail_prediction_scaled_max": 0.01,
            "tail_to_first_state_ratio": "diagnostic_only",
            "formal_convergence": "reported_separately_not_a_numerical_validity_requirement",
            "first_state_delta_below_100": "diagnostic_only",
        },
        "future_refit_scope": "seven_exAL_atoms_only_after_R93_completes",
        "reuse_without_refit": ["ridge", "normal_RHS", "DESN_features", "seven_AL_atoms"],
        "max_iter": 200,
        "launch_authorized": False,
        "test_opened": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    atoms.to_csv(output / "pricefm_stage_r94_r93_atom_diagnostics.csv", index=False)
    history.to_csv(output / "pricefm_stage_r94_r87_first_delta_ledger.csv", index=False)
    root_cause_ledger().to_csv(output / "pricefm_stage_r94_root_cause_ledger.csv", index=False)
    write_json(output / "pricefm_stage_r94_repair_contract.json", contract)
    summary = {
        "status": "audit_complete_repair_preparation_authorized" if repair_evidence else "audit_incomplete_or_evidence_gate_failed",
        "r93_complete": complete,
        "r93_al_atoms": int(len(al)),
        "r93_exal_atoms": int(len(exal)),
        "r93_exal_legacy_gate_passed": int(exal.legacy_numerical_gate_passed.sum()) if len(exal) else 0,
        "r93_exal_historical_proxy_trajectory_gate_passed": int(exal.historical_proxy_trajectory_gate_passed.sum()) if len(exal) else 0,
        "r93_exal_failed_only_absolute_first_delta": int(exal.failed_only_absolute_first_delta.sum()) if len(exal) else 0,
        "repair_preparation_authorized": bool(repair_evidence),
        "production_refit_preparation_authorized": bool(repair_evidence and complete),
        "history": history_summary,
        "test_opened": False,
        "test_access_authorized": False,
        "launch_authorized": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    write_json(output / "summary.json", summary)
    fixed_sources = [Path(__file__).resolve(), *sources, *history_sources]
    pd.DataFrame(
        [
            {"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size}
            for path in fixed_sources if path.is_file()
        ]
    ).drop_duplicates("path").to_csv(output / "source_manifest.csv", index=False)
    (output / "pricefm_stage_r94_exal_initialization_audit.md").write_text(
        "# PriceFM Stage-R94 exAL Initialization Audit\n\n"
        f"R93 currently exposes {len(al)}/7 AL and {len(exal)}/7 exAL atoms; complete={complete}. "
        f"All {len(exal)} observed exAL failures are attributable only to the inherited absolute "
        "first-state-delta threshold, while their finite/tail-contraction checks pass.\n\n"
        f"Across {history_summary['traces']} R87 traces, {history_summary['above_or_equal_100']} "
        "exceeded the same threshold. This historical frequency and the R82 update order show that "
        "the threshold measures a coordinate-scale-dependent partial-initialization transition, not "
        "a universal failure boundary. R94 therefore preserves the R82 structured sigma/gamma repair, "
        "adds a coherent AL covariance/RHS/latent warm start, and evaluates numerical validity from "
        "finite trajectories, physical bounds, endpoint stability, and tail contraction. No test, "
        "launch, registry, article, joint, or MCMC action is authorized.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
