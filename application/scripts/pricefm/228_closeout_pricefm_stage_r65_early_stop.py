#!/usr/bin/env python3
"""Freeze and diagnose the intentionally stopped PriceFM Stage-R65 campaign."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

import numpy as np
import pandas as pd

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r65_independent_structured_exal_vb_20260829"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r65_early_stop_closeout_20260829"
METHOD_AL = "qdesn_al_rhs_ns_exact_chunked_r65_parity"
METHOD_EXAL = "qdesn_exal_rhs_ns_exact_chunked_structured_r65"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
REQUIRED_ADAPTER_FILES = (
    "adapter_manifest.json",
    "feature_manifest.json",
    "X_train.csv",
    "y_train.csv",
    "X_val.csv",
    "y_val.csv",
    "rows_val.csv",
)
FORBIDDEN_TEST_FILES = ("X_test.csv", "y_test.csv", "rows_test.csv")


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=GRID / "case_manifest.csv")
    p.add_argument("--component-ledger", type=Path, default=GRID / "component_ledger.csv")
    p.add_argument("--launch-status", type=Path, default=GRID / "launch_status.csv")
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-cases", type=int, default=114)
    p.add_argument("--verify-fit-hashes", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def boolish(value) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def read_json(path: Path) -> dict:
    if not path.is_file():
        return {}
    value = json.loads(path.read_text())
    return value if isinstance(value, dict) else {}


def directory_bytes(path: Path) -> int:
    if not path.exists():
        return 0
    return sum(item.stat().st_size for item in path.rglob("*") if item.is_file())


def active_r65_processes() -> list[dict]:
    result = subprocess.run(
        ["pgrep", "-af", "224_run_pricefm_stage_r65|225_launch_pricefm_stage_r65"],
        text=True,
        capture_output=True,
        check=False,
    )
    rows = []
    for line in result.stdout.splitlines():
        if not line.strip() or "pgrep -af" in line or "228_closeout" in line:
            continue
        pid, command = line.split(" ", 1)
        rows.append({"pid": int(pid), "command": command})
    return rows


def fit_contract(status_path: Path, fit_path: Path, verify_hash: bool) -> dict:
    status = read_json(status_path)
    recorded = str(status.get("fit_sha256", ""))
    observed = ""
    if fit_path.is_file() and recorded and verify_hash:
        observed = sha256(fit_path)
    elif fit_path.is_file() and recorded:
        observed = recorded
    passed = bool(fit_path.is_file() and status_path.is_file() and recorded and observed == recorded)
    return {
        "status_exists": status_path.is_file(),
        "fit_exists": fit_path.is_file(),
        "recorded_sha256": recorded,
        "observed_sha256": observed,
        "hash_pass": passed,
        "converged": boolish(status.get("converged", False)),
        "fit_state": str(status.get("fit_state", "")),
        "package_head": str(status.get("package_head", "")),
    }


def metric(frame: pd.DataFrame, method: str, column: str = "AQL") -> float:
    selected = frame[
        frame.method_id.astype(str).eq(method)
        & frame.split.astype(str).eq("val")
        & frame.unit.astype(str).eq("original")
    ]
    if len(selected) != 1:
        return float("nan")
    return float(selected.iloc[0][column])


def source_row(path: Path, role: str) -> dict:
    return {
        "path": str(path.resolve()),
        "role": role,
        "sha256": sha256(path),
        "bytes": path.stat().st_size,
    }


def component_inventory(
    manifest: pd.DataFrame,
    components: pd.DataFrame,
    verify_hashes: bool,
) -> tuple[pd.DataFrame, list[dict]]:
    manifest_by_case = manifest.set_index("case_id")
    rows = []
    sources = []
    for component in components.sort_values(["region", "fold", "tau"]).itertuples(index=False):
        case = manifest_by_case.loc[str(component.case_id)]
        model = Path(case.output_dir)
        slug = str(float(component.tau)).rstrip("0").rstrip(".").replace(".", "p")
        root = model / "components" / f"tau={slug}"
        al_fit = root / "al_fit.rds"
        al_status = root / "al_status.json"
        exal_fit = root / "exal_fit.rds"
        exal_status = root / "exal_status.json"
        terminal_path = root / "component_terminal.json"
        al = fit_contract(al_status, al_fit, verify_hashes)
        exal = fit_contract(exal_status, exal_fit, verify_hashes)
        terminal = read_json(terminal_path)
        al_predictions = root / "al_predictions_scaled.csv"
        al_summary = root / "al_method_summary.csv"
        if al_status.is_file():
            sources.append(source_row(al_status, "r65_al_status"))
        if exal_status.is_file():
            sources.append(source_row(exal_status, "r65_exal_status"))
        if terminal_path.is_file():
            sources.append(source_row(terminal_path, "r65_component_terminal"))
        state = "not_started"
        if al["hash_pass"] and exal["hash_pass"] and terminal_path.is_file():
            state = "terminal_pair"
        elif al["hash_pass"] and exal["hash_pass"]:
            state = "fit_pair_without_terminal"
        elif al["hash_pass"]:
            state = "al_checkpoint_only"
        elif any((root.exists(), al["fit_exists"], exal["fit_exists"])):
            state = "incomplete_or_invalid_checkpoint"
        rows.append({
            "case_id": component.case_id,
            "region": component.region,
            "fold": int(component.fold),
            "tau": float(component.tau),
            "component_state": state,
            "terminal_json_exists": terminal_path.is_file(),
            "selection_eligible": boolish(terminal.get("selection_eligible", False)),
            "al_fit_exists": al["fit_exists"],
            "al_status_exists": al["status_exists"],
            "al_fit_sha256": al["observed_sha256"],
            "al_fit_hash_pass": al["hash_pass"],
            "al_converged": al["converged"],
            "al_predictions_exists": al_predictions.is_file(),
            "al_method_summary_exists": al_summary.is_file(),
            "exal_fit_exists": exal["fit_exists"],
            "exal_status_exists": exal["status_exists"],
            "exal_fit_sha256": exal["observed_sha256"],
            "exal_fit_hash_pass": exal["hash_pass"],
            "exal_converged": exal["converged"],
            "r65_package_head": exal["package_head"] or al["package_head"],
            "reuse_al_fit_authorized": al["hash_pass"],
            "reuse_al_predictions_authorized": al["hash_pass"] and al_predictions.is_file(),
            "al_fit_path": str(al_fit),
            "al_status_path": str(al_status),
            "al_predictions_path": str(al_predictions),
            "r66_action": "reuse_al_fit_corrected_exal_only" if al["hash_pass"] else "fit_missing_al_then_corrected_exal",
            "test_opened": False,
        })
    return pd.DataFrame(rows), sources


def completed_diagnostics(manifest: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, list[dict]]:
    cases = []
    quantiles = []
    sources = []
    for row in manifest.sort_values(["region", "fold"]).itertuples(index=False):
        model = Path(row.output_dir)
        required = {
            "metrics": model / "metric_summary.csv",
            "parameters": model / "model_parameter_summary.csv",
            "components": model / "r65_component_status.csv",
            "fit_summary": model / "r65_case_fit_summary.json",
            "predictions": model / "model_predictions_scaled.csv",
        }
        if not all(path.is_file() for path in required.values()):
            continue
        metric_frame = pd.read_csv(required["metrics"])
        parameter_frame = pd.read_csv(required["parameters"])
        component_frame = pd.read_csv(required["components"])
        al_aql = metric(metric_frame, METHOD_AL)
        exal_aql = metric(metric_frame, METHOD_EXAL)
        al_aqcr = metric(metric_frame, METHOD_AL, "AQCR")
        exal_aqcr = metric(metric_frame, METHOD_EXAL, "AQCR")
        authority = float(row.legacy_selected_validation_AQL)
        winner = bool(
            len(component_frame) == 7
            and component_frame.selection_eligible.map(boolish).all()
            and np.isfinite(exal_aql)
            and exal_aql < min(authority, al_aql)
        )
        cases.append({
            "case_id": row.case_id,
            "region": row.region,
            "fold": int(row.fold),
            "legacy_selected_family": row.legacy_selected_family,
            "r62_authority_validation_AQL": authority,
            "r65_al_validation_AQL": al_aql,
            "r65_structured_exal_validation_AQL": exal_aql,
            "al_parity_absolute_delta": al_aql - float(row.legacy_al_validation_AQL),
            "structured_delta_vs_al": exal_aql - al_aql,
            "structured_ratio_vs_al": exal_aql / al_aql,
            "structured_delta_vs_r62": exal_aql - authority,
            "structured_ratio_vs_r62": exal_aql / authority,
            "al_crossing_rate": al_aqcr,
            "structured_crossing_rate": exal_aqcr,
            "eligible_components": int(component_frame.selection_eligible.map(boolish).sum()),
            "structured_bundle_promotable": winner,
            "decision": "reject_r65_structured_bundle_mechanism_failure",
            "test_opened": False,
        })
        for param in parameter_frame.itertuples(index=False):
            if str(param.method_id) != METHOD_EXAL:
                continue
            status = component_frame[np.isclose(component_frame.tau.astype(float), float(param.tau))]
            quantiles.append({
                "case_id": row.case_id,
                "region": row.region,
                "fold": int(row.fold),
                "tau": float(param.tau),
                "exal_converged": boolish(status.iloc[0].exal_converged) if len(status) == 1 else False,
                "selection_eligible": boolish(status.iloc[0].selection_eligible) if len(status) == 1 else False,
                "gamma": float(param.gamma),
                "sigma": float(param.sigma),
                "beta_l2": float(param.beta_l2),
                "beta_max_abs": float(param.beta_max_abs),
            })
        sources.extend(source_row(path, f"r65_completed_{role}") for role, path in required.items())
    return pd.DataFrame(cases), pd.DataFrame(quantiles), sources


def run(args: argparse.Namespace) -> dict:
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    manifest = pd.read_csv(args.manifest)
    components = pd.read_csv(args.component_ledger)
    status = pd.read_csv(args.launch_status) if args.launch_status.is_file() else pd.DataFrame()
    if len(manifest) != args.expected_cases:
        raise RuntimeError(f"Expected {args.expected_cases} R65 cases, found {len(manifest)}")
    if len(components) != args.expected_cases * len(TAUS):
        raise RuntimeError("R65 component ledger is not a complete seven-quantile surface")
    if manifest.duplicated(["region", "fold"]).any() or components.duplicated(["case_id", "tau"]).any():
        raise RuntimeError("R65 manifest contains duplicate scientific cells")

    inventory, component_sources = component_inventory(
        manifest, components, args.verify_fit_hashes
    )
    diagnostics, quantile_diagnostics, completed_sources = completed_diagnostics(manifest)
    launcher_by_case = status.set_index("case_id").status.to_dict() if not status.empty else {}
    case_rows = []
    forbidden_test_paths = []
    for row in manifest.sort_values(["region", "fold"]).itertuples(index=False):
        model = Path(row.output_dir)
        adapter = Path(row.adapter_dir)
        subset = inventory[inventory.case_id.astype(str).eq(str(row.case_id))]
        metric_complete = bool((model / "metric_summary.csv").is_file())
        adapter_ready = all((adapter / name).is_file() for name in REQUIRED_ADAPTER_FILES)
        normal_status = model / "normal_anchor/normal_rhs_anchor.json"
        normal_fit = model / "normal_anchor/normal_rhs_anchor.rds"
        normal = fit_contract(normal_status, normal_fit, args.verify_fit_hashes)
        forbidden = [adapter / name for name in FORBIDDEN_TEST_FILES if (adapter / name).exists()]
        forbidden_test_paths.extend(forbidden)
        prediction_path = model / "model_predictions_scaled.csv"
        prediction_test_rows = 0
        if prediction_path.is_file():
            prediction = pd.read_csv(prediction_path, usecols=["split"])
            prediction_test_rows = int(prediction.split.astype(str).eq("test").sum())
        has_scientific_checkpoint = bool(
            adapter_ready
            or normal["fit_exists"]
            or normal["status_exists"]
            or subset.al_fit_exists.any()
            or subset.al_status_exists.any()
            or subset.exal_fit_exists.any()
            or subset.exal_status_exists.any()
            or subset.terminal_json_exists.any()
        )
        if metric_complete and int(subset.terminal_json_exists.sum()) == 7:
            state = "metric_complete"
        elif has_scientific_checkpoint:
            state = "partial_checkpointed"
        else:
            state = "not_started"
        case_rows.append({
            "case_id": row.case_id,
            "region": row.region,
            "fold": int(row.fold),
            "early_stop_state": state,
            "launcher_status": launcher_by_case.get(row.case_id, "not_recorded_before_interrupt"),
            "metric_complete": metric_complete,
            "terminal_components": int(subset.terminal_json_exists.sum()),
            "al_fit_checkpoints": int(subset.al_fit_hash_pass.sum()),
            "exal_fit_checkpoints": int(subset.exal_fit_hash_pass.sum()),
            "eligible_components": int(subset.selection_eligible.sum()),
            "adapter_ready": adapter_ready,
            "normal_anchor_ready": normal["hash_pass"],
            "case_bytes": directory_bytes(model.parent),
            "forbidden_test_files": len(forbidden),
            "prediction_test_rows": prediction_test_rows,
            "test_opened": False,
        })
    cases = pd.DataFrame(case_rows)
    if forbidden_test_paths or cases.prediction_test_rows.sum():
        raise RuntimeError(f"R65 test firewall violation: {forbidden_test_paths}")

    active = active_r65_processes()
    promotion = diagnostics[diagnostics.structured_bundle_promotable].copy()
    if not promotion.empty:
        raise RuntimeError("R65 unexpectedly contains a promotable structured-exAL bundle")

    cases.to_csv(output / "pricefm_stage_r65_early_stop_case_inventory.csv", index=False)
    inventory.to_csv(output / "pricefm_stage_r65_early_stop_component_inventory.csv", index=False)
    diagnostics.to_csv(output / "pricefm_stage_r65_completed_case_failure_diagnostics.csv", index=False)
    quantile_diagnostics.to_csv(output / "pricefm_stage_r65_completed_quantile_failure_diagnostics.csv", index=False)
    promotion.to_csv(output / "pricefm_stage_r65_promotion_queue.csv", index=False)
    inventory[[
        "case_id", "region", "fold", "tau", "component_state",
        "reuse_al_fit_authorized", "reuse_al_predictions_authorized",
        "al_fit_path", "al_status_path", "al_predictions_path",
        "al_fit_sha256", "r65_package_head", "r66_action", "test_opened",
    ]].to_csv(output / "pricefm_stage_r65_checkpoint_reuse_manifest.csv", index=False)

    median_ratio = float(diagnostics.structured_ratio_vs_al.median())
    gates = pd.DataFrame([
        {"gate": "full_manifest_frozen", "passed": len(cases) == args.expected_cases, "observed": len(cases)},
        {"gate": "full_component_ledger_frozen", "passed": len(inventory) == args.expected_cases * 7, "observed": len(inventory)},
        {"gate": "no_active_r65_process", "passed": not active, "observed": len(active)},
        {"gate": "test_firewall_intact", "passed": not forbidden_test_paths and cases.prediction_test_rows.sum() == 0, "observed": "sealed"},
        {"gate": "al_parity_reproduced_on_completed_cases", "passed": bool(np.nanmax(np.abs(diagnostics.al_parity_absolute_delta)) <= 1e-9), "observed": float(np.nanmax(np.abs(diagnostics.al_parity_absolute_delta)))},
        {"gate": "zero_structured_promotions", "passed": promotion.empty, "observed": len(promotion)},
        {"gate": "mechanism_stop_justified", "passed": median_ratio > 1.0, "observed": median_ratio},
        {"gate": "registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
    ])
    if not gates.passed.all():
        raise RuntimeError(f"R65 early-stop closeout gates failed: {gates.loc[~gates.passed].to_dict('records')}")
    gates.to_csv(output / "pricefm_stage_r65_early_stop_gates.csv", index=False)

    source_paths = [
        source_row(args.manifest.resolve(), "r65_case_manifest"),
        source_row(args.component_ledger.resolve(), "r65_component_ledger"),
        source_row(Path(__file__).resolve(), "closeout_script"),
    ]
    if args.launch_status.is_file():
        source_paths.append(source_row(args.launch_status.resolve(), "r65_partial_launch_status"))
    source_frame = pd.DataFrame(source_paths + component_sources + completed_sources)
    source_frame.drop_duplicates(["path", "sha256"]).sort_values(["role", "path"]).to_csv(
        output / "source_manifest.csv", index=False
    )

    convergence_by_tau = {}
    if not quantile_diagnostics.empty:
        convergence_by_tau = {
            f"{tau:g}": int(group.exal_converged.sum())
            for tau, group in quantile_diagnostics.groupby("tau", sort=True)
        }
    summary = {
        "status": "scientifically_stopped_mechanism_failure",
        "expected_cases": len(cases),
        "metric_complete_cases": int(cases.metric_complete.sum()),
        "partial_checkpointed_cases": int(cases.early_stop_state.eq("partial_checkpointed").sum()),
        "not_started_cases": int(cases.early_stop_state.eq("not_started").sum()),
        "expected_components": len(inventory),
        "terminal_components": int(inventory.terminal_json_exists.sum()),
        "valid_al_fit_checkpoints": int(inventory.al_fit_hash_pass.sum()),
        "valid_exal_fit_checkpoints": int(inventory.exal_fit_hash_pass.sum()),
        "eligible_components": int(inventory.selection_eligible.sum()),
        "adapter_ready_cases": int(cases.adapter_ready.sum()),
        "normal_anchor_ready_cases": int(cases.normal_anchor_ready.sum()),
        "completed_case_structured_winners": 0,
        "completed_case_median_structured_ratio_vs_al": median_ratio,
        "completed_case_min_structured_ratio_vs_al": float(diagnostics.structured_ratio_vs_al.min()),
        "completed_case_max_structured_ratio_vs_al": float(diagnostics.structured_ratio_vs_al.max()),
        "completed_case_median_al_crossing_rate": float(diagnostics.al_crossing_rate.median()),
        "completed_case_median_structured_crossing_rate": float(diagnostics.structured_crossing_rate.median()),
        "structured_exal_converged_cases_by_tau": convergence_by_tau,
        "runtime_bytes": int(cases.case_bytes.sum()),
        "active_r65_processes": active,
        "test_opened": False,
        "promotion_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
        "r66_authorized": False,
    }
    write_json(output / "summary.json", summary)
    report = (
        "# PriceFM Stage-R65 early-stop closeout\n\n"
        "## Decision\n\n"
        "R65 is frozen as `scientifically_stopped_mechanism_failure`. The stop preserved every atomic "
        "checkpoint and did not open test data. No R65 candidate enters a promotion queue.\n\n"
        "## Frozen state\n\n"
        f"- Cases: {summary['metric_complete_cases']} metric-complete, "
        f"{summary['partial_checkpointed_cases']} partial, {summary['not_started_cases']} not started.\n"
        f"- Components: {summary['terminal_components']}/{summary['expected_components']} terminal; "
        f"{summary['valid_al_fit_checkpoints']} valid AL fits and "
        f"{summary['valid_exal_fit_checkpoints']} valid structured-exAL fits.\n"
        f"- Median structured/AL validation AQL ratio: {median_ratio:.6f}.\n"
        f"- Median crossing rate: AL {summary['completed_case_median_al_crossing_rate']:.6f}; "
        f"structured exAL {summary['completed_case_median_structured_crossing_rate']:.6f}.\n\n"
        "## Mechanism diagnosis\n\n"
        "The R65 package reported a structured factorization but the production engine refreshed downstream "
        "expectations from its Gaussian delta summary instead of the conditional-GIG moments. Its optimizer "
        "also discarded a valid continuation start in favor of the global coarse-grid maximum. Tail fits then "
        "moved toward boundary modes, contracted scale, failed convergence, and produced severe crossing/AQL harm.\n\n"
        "## Next-stage contract\n\n"
        "R66 may reuse hash-verified R65 adapters, normal anchors, and AL fits. It must fit corrected exAL only, "
        "in a new output namespace and immutable corrected package runtime. Launch remains blocked until the "
        "seven-quantile package gate and a real production-tail mechanism gate pass. Test, registry, article, "
        "joint-model, and MCMC actions remain blocked.\n"
    )
    (output / "pricefm_stage_r65_early_stop_closeout_report.md").write_text(report)
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
