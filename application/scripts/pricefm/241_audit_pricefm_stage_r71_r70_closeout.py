#!/usr/bin/env python3
"""Freeze and audit the terminal Stage-R70 independent-VB campaign.

R71 is deliberately read-only with respect to R70.  It inventories every
case/quantile/likelihood atom, records what can be reused, quarantines the R70
structured-exAL surface, and writes validation-only closeout evidence.  It
never reads test data and never writes launch YAML.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
from typing import Any

import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r69b_bounded_cran111_independent_vb_20260831"
GRID = DATA / "experiment_grids" / TAG
MANIFEST = GRID / "case_manifest.csv"
STATUS = GRID / "launch_status.csv"
OUTPUT = DATA / "authoritative/pricefm_stage_r71_r70_closeout_20260901"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
LIKELIHOODS = ("al", "exal")
BINARY_SUFFIXES = {".rds", ".rda", ".RData", ".rdata"}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=MANIFEST)
    p.add_argument("--launch-status", type=Path, default=STATUS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-cases", type=int, default=56)
    p.add_argument("--expected-complete", type=int, default=25)
    p.add_argument("--expected-failed", type=int, default=31)
    p.add_argument("--expected-terminal-components", type=int, default=250)
    return p


def boolish(value: Any) -> bool:
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def finite(value: Any) -> bool:
    try:
        return bool(pd.notna(value) and float(value) not in (float("inf"), float("-inf")))
    except (TypeError, ValueError):
        return False


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def tau_slug(tau: float) -> str:
    return f"{tau:.12f}".rstrip("0").rstrip(".").replace(".", "p")


def parse_quantiles(value: Any) -> tuple[float, ...]:
    parsed = json.loads(str(value))
    return tuple(float(item) for item in parsed)


def read_one(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    frame = pd.read_csv(path)
    if len(frame) != 1:
        raise RuntimeError(f"Expected one row in {path}, found {len(frame)}")
    return frame.iloc[0].to_dict()


def failure_class(text: str) -> str:
    lowered = text.lower()
    if "leading minor of order" in lowered and "not positive" in lowered:
        return "qbeta_cholesky_non_positive_definite"
    if "no finite" in lowered and ("gamma" in lowered or "grid" in lowered):
        return "structured_exal_gamma_grid_nonfinite"
    if "error" in lowered or "execution halted" in lowered:
        return "other_runtime_error"
    return "no_error_text_found"


def leading_minor(text: str) -> int | None:
    match = re.search(r"leading minor of order\s+(\d+)\s+is not positive", text, re.I)
    return int(match.group(1)) if match else None


def method_id(row: Any, likelihood: str) -> str:
    key = "expected_al_method_id" if likelihood == "al" else "expected_exal_method_id"
    return str(getattr(row, key))


def atomic_row(row: Any, tau: float, likelihood: str) -> dict[str, Any]:
    model = Path(row.output_dir)
    component = model / "components" / f"tau={tau_slug(tau)}"
    terminal_path = component / "component_terminal.json"
    prefix = likelihood
    prediction = component / f"{prefix}_predictions_scaled.csv"
    method = component / f"{prefix}_method_summary.csv"
    parameter = component / f"{prefix}_parameter_summary.csv"
    trace = component / f"{prefix}_trace.csv"
    beta = component / f"{prefix}_beta_mean.csv"
    covariance = component / f"{prefix}_beta_cov_diag.csv"
    required = (prediction, method, parameter, trace, beta, covariance, terminal_path)
    exists = all(path.is_file() for path in required)
    terminal = json.loads(terminal_path.read_text()) if terminal_path.is_file() else {}
    method_values = read_one(method)
    parameter_values = read_one(parameter)
    prediction_finite = False
    if prediction.is_file():
        predictions = pd.read_csv(prediction)
        prediction_finite = bool(
            len(predictions) > 0
            and "pred_scaled" in predictions
            and pd.to_numeric(predictions["pred_scaled"], errors="coerce").notna().all()
        )
    converged = boolish(method_values.get("converged")) if method_values else False
    beta_l2 = parameter_values.get("beta_l2")
    sigma = parameter_values.get("sigma")
    parameter_finite = finite(beta_l2) and finite(sigma)
    if not exists:
        disposition = "missing_requires_r72_refit" if likelihood == "al" else "missing_exal_blocked"
    elif likelihood == "exal":
        disposition = "quarantine_r70_structured_exal_instability"
    elif prediction_finite and parameter_finite:
        disposition = "reuse_r70_al_validation_artifact"
    else:
        disposition = "invalid_requires_r72_refit"
    return {
        "case_id": row.case_id,
        "region": row.region,
        "fold": int(row.fold),
        "tau": tau,
        "likelihood_family": likelihood,
        "method_id": method_id(row, likelihood),
        "component_dir": str(component),
        "artifacts_complete": exists,
        "terminal_recorded": terminal_path.is_file(),
        "converged": converged,
        "prediction_finite": prediction_finite,
        "parameter_finite": parameter_finite,
        "beta_l2": float(beta_l2) if finite(beta_l2) else None,
        "sigma": float(sigma) if finite(sigma) else None,
        "gamma": (
            float(parameter_values.get("gamma"))
            if finite(parameter_values.get("gamma"))
            else None
        ),
        "selection_eligible_as_recorded": boolish(terminal.get("selection_eligible")),
        "prediction_sha256": sha256(prediction) if prediction.is_file() else "",
        "parameter_sha256": sha256(parameter) if parameter.is_file() else "",
        "disposition": disposition,
        "test_opened": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }


def case_row(row: Any, launcher: dict[str, Any], atoms: pd.DataFrame) -> dict[str, Any]:
    model = Path(row.output_dir)
    worker_log = Path(str(launcher.get("worker_log", model.parent / "worker.log")))
    log_text = worker_log.read_text(errors="replace") if worker_log.is_file() else ""
    complete_pairs = int(
        atoms.groupby("tau")["artifacts_complete"].all().sum()
    )
    missing_taus = [tau for tau in TAUS if not bool(
        atoms.loc[atoms["tau"].eq(tau), "artifacts_complete"].all()
    )]
    return {
        "case_id": row.case_id,
        "region": row.region,
        "fold": int(row.fold),
        "launcher_status": launcher.get("status", "missing_status"),
        "returncode": launcher.get("returncode"),
        "elapsed_seconds": launcher.get("elapsed_seconds"),
        "complete_likelihood_quantile_atoms": int(atoms["artifacts_complete"].sum()),
        "complete_paired_components": complete_pairs,
        "missing_paired_components": len(TAUS) - complete_pairs,
        "next_missing_tau": missing_taus[0] if missing_taus else None,
        "metric_summary_present": (model / "metric_summary.csv").is_file(),
        "failure_class": failure_class(log_text),
        "leading_minor_order": leading_minor(log_text),
        "worker_log": str(worker_log),
        "worker_log_sha256": sha256(worker_log) if worker_log.is_file() else "",
        "test_opened": False,
    }


def validation_row(row: Any) -> dict[str, Any] | None:
    metric_path = Path(row.output_dir) / "metric_summary.csv"
    if not metric_path.is_file():
        return None
    metrics = pd.read_csv(metric_path)
    metrics = metrics[(metrics["split"] == "val") & (metrics["unit"] == "original")]
    observed = dict(zip(metrics["method_id"], metrics["AQL"], strict=False))
    al = float(observed[method_id(row, "al")])
    exal = float(observed[method_id(row, "exal")])
    naive = min(float(value) for key, value in observed.items() if str(key).startswith("naive"))
    prior = float(row.r69a_validation_AQL_recomputed)
    operational = prior - float(row.qdesn_minus_operational_pricefm_AQL)
    cached = prior - float(row.qdesn_minus_cached_pricefm_AQL)
    improves_prior = al < prior
    improves_operational = al < operational
    improves_cached = al < cached
    promotion = improves_prior and improves_operational and improves_cached
    return {
        "case_id": row.case_id,
        "region": row.region,
        "fold": int(row.fold),
        "selected_method_validation_only": method_id(row, "al") if al <= exal else method_id(row, "exal"),
        "al_validation_AQL": al,
        "exal_validation_AQL": exal,
        "best_naive_validation_AQL": naive,
        "prior_authoritative_qdesn_validation_AQL": prior,
        "operational_pricefm_validation_AQL": operational,
        "cached_pricefm_validation_AQL": cached,
        "al_minus_prior_qdesn": al - prior,
        "al_minus_operational_pricefm": al - operational,
        "al_minus_cached_pricefm": al - cached,
        "al_beats_best_naive": al < naive,
        "al_beats_prior_qdesn": improves_prior,
        "al_beats_operational_pricefm": improves_operational,
        "al_beats_cached_pricefm": improves_cached,
        "passes_validation_promotion_gate": promotion,
        "decision": "promotion_queue" if promotion else "blocked_validation_gate",
        "test_opened": False,
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest = pd.read_csv(args.manifest)
    status = pd.read_csv(args.launch_status)
    if manifest["case_id"].duplicated().any() or status["case_id"].duplicated().any():
        raise RuntimeError("R71 requires unique case identifiers")
    if set(manifest["case_id"]) != set(status["case_id"]):
        raise RuntimeError("R70 manifest/status case sets differ")
    if any(parse_quantiles(value) != TAUS for value in manifest["paper_quantiles"]):
        raise RuntimeError("R70 manifest does not contain the exact seven-quantile contract")
    blocked = [
        "test_access_authorized", "registry_mutation_authorized",
        "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
    ]
    if any(manifest[name].map(boolish).any() for name in blocked):
        raise RuntimeError("R70 firewall declarations are not all false")

    status_by_case = status.set_index("case_id").to_dict("index")
    atom_rows: list[dict[str, Any]] = []
    case_rows: list[dict[str, Any]] = []
    validation_rows: list[dict[str, Any]] = []
    for row in manifest.itertuples(index=False):
        case_atoms = [atomic_row(row, tau, likelihood) for tau in TAUS for likelihood in LIKELIHOODS]
        atom_rows.extend(case_atoms)
        atom_frame = pd.DataFrame(case_atoms)
        case_rows.append(case_row(row, status_by_case[row.case_id], atom_frame))
        comparison = validation_row(row)
        if comparison:
            validation_rows.append(comparison)

    atoms = pd.DataFrame(atom_rows).sort_values(["region", "fold", "tau", "likelihood_family"])
    cases = pd.DataFrame(case_rows).sort_values(["region", "fold"])
    validation = pd.DataFrame(validation_rows).sort_values(["region", "fold"])
    complete = int(cases["metric_summary_present"].sum())
    failed = int((cases["launcher_status"] == "failed").sum())
    terminal_pairs = int(cases["complete_paired_components"].sum())
    binaries = [
        path for output in manifest["output_dir"].map(Path)
        for path in output.rglob("*") if path.is_file() and path.suffix in BINARY_SUFFIXES
    ]
    missing_al = int(
        ((atoms["likelihood_family"] == "al") & ~atoms["artifacts_complete"]).sum()
    )
    quarantined_exal = int(atoms["disposition"].str.startswith("quarantine_").sum())
    gates = pd.DataFrame([
        {"gate": "expected_case_count", "passed": len(cases) == args.expected_cases, "observed": len(cases)},
        {"gate": "expected_complete_cases", "passed": complete == args.expected_complete, "observed": complete},
        {"gate": "expected_failed_cases", "passed": failed == args.expected_failed, "observed": failed},
        {"gate": "expected_terminal_paired_components", "passed": terminal_pairs == args.expected_terminal_components, "observed": terminal_pairs},
        {"gate": "no_binary_model_artifacts", "passed": len(binaries) == 0, "observed": len(binaries)},
        {"gate": "test_registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
        {"gate": "no_validation_promotion", "passed": bool(validation.empty or ~validation["passes_validation_promotion_gate"].any()), "observed": int(validation["passes_validation_promotion_gate"].sum()) if not validation.empty else 0},
        {"gate": "r72_launch_not_authorized_by_r71", "passed": True, "observed": "blocked"},
    ])
    if not gates["passed"].all():
        failed_gates = gates.loc[~gates["passed"], "gate"].tolist()
        raise RuntimeError(f"R71 closeout gates failed: {failed_gates}")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    atoms.to_csv(args.output_dir / "pricefm_stage_r71_atomic_fit_salvage_ledger.csv", index=False)
    cases.to_csv(args.output_dir / "pricefm_stage_r71_case_closeout.csv", index=False)
    validation.to_csv(args.output_dir / "pricefm_stage_r71_validation_comparison.csv", index=False)
    failure_atlas = cases[cases["launcher_status"] == "failed"].copy()
    failure_atlas.to_csv(args.output_dir / "pricefm_stage_r71_failure_atlas.csv", index=False)
    gates.to_csv(args.output_dir / "pricefm_stage_r71_closeout_gates.csv", index=False)

    source_paths = [Path(__file__).resolve(), args.manifest.resolve(), args.launch_status.resolve()]
    for path in sorted({Path(value) for value in cases["worker_log"] if Path(value).is_file()}):
        source_paths.append(path.resolve())
    sources = pd.DataFrame([
        {"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in dict.fromkeys(source_paths)
    ])
    sources.to_csv(args.output_dir / "source_manifest.csv", index=False)

    summary = {
        "status": "r70_frozen_closed_out_no_promotion",
        "cases": int(len(cases)),
        "complete_cases": complete,
        "failed_cases": failed,
        "expected_paired_components": int(len(cases) * len(TAUS)),
        "terminal_paired_components": terminal_pairs,
        "missing_paired_components": int(len(cases) * len(TAUS) - terminal_pairs),
        "existing_al_atoms": int(((atoms.likelihood_family == "al") & atoms.artifacts_complete).sum()),
        "missing_or_invalid_al_atoms": missing_al,
        "existing_exal_atoms_quarantined": quarantined_exal,
        "exal_atoms_authorized_for_reuse": 0,
        "validation_cases_audited": int(len(validation)),
        "validation_promotion_candidates": int(validation["passes_validation_promotion_gate"].sum()) if not validation.empty else 0,
        "binary_model_artifact_count": len(binaries),
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
        "joint_or_mcmc_run": False,
        "r72_launch_authorized": False,
    }
    write_json(args.output_dir / "pricefm_stage_r71_closeout_summary.json", summary)
    report = f"""# PriceFM Stage-R71 R70 Closeout

R70 is frozen as terminal evidence: {complete} complete cases and {failed} failed cases
across {len(cases)} case-specific PriceFM targets. It materialized {terminal_pairs} of
{len(cases) * len(TAUS)} paired quantile components. The remaining
{len(cases) * len(TAUS) - terminal_pairs} AL atoms require an atomic R72 refit.

The {quarantined_exal} existing structured-exAL atoms are quarantined campaign-wide:
their instability makes selective reuse scientifically unsafe. R71 opened no test
data and authorizes no launch, registry, article, joint-model, or MCMC action.

Validation-only comparison found {summary['validation_promotion_candidates']} cases
that beat the prior authoritative QDESN result and both PriceFM references. Therefore
R70 itself supplies no promotion candidate.
"""
    (args.output_dir / "pricefm_stage_r71_closeout_report.md").write_text(report)
    if list(args.output_dir.rglob("*.yaml")) or list(args.output_dir.rglob("*.yml")):
        raise RuntimeError("R71 must not produce launch YAML")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
