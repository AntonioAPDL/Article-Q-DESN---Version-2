#!/usr/bin/env python3
"""Repair the R103 exAL diagnostic gate without changing fitted models."""

from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import tempfile
from typing import Any

import numpy as np
import pandas as pd

from pricefm_common import sha256_file, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PREP = DATA / "launch_prep/pricefm_stage_r103_recursive_quantile_20260916"
CAMPAIGN = DATA / "campaigns/pricefm_stage_r103_recursive_quantile_20260916"
OUTPUT = CAMPAIGN / "diagnostic_repairs/pricefm_stage_r103_exal_gate_20260917"
THRESHOLD = 0.01
RAW_TRACE_COLUMNS = (
    "sigma", "gamma", "delta_state", "delta_sigma", "delta_gamma", "delta_s"
)
MISSING_CHECKS = {
    "trace_complete",
    "trace_finite",
    "tail_relative_state_below_0p01",
    "tail_prediction_scaled_below_0p01",
}
PROTECTED_ATOM_ROLES = {
    "beta_mean",
    "beta_cov",
    "parameter_summary",
    "vb_trace",
}
PROTECTED_CASE_ROLES = {
    "al_validation_quantiles",
    "exal_validation_quantiles",
}


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--prep-dir", type=Path, default=PREP)
    value.add_argument("--campaign-root", type=Path, default=CAMPAIGN)
    value.add_argument("--output-dir", type=Path, default=OUTPUT)
    value.add_argument("--write", action="store_true")
    value.add_argument("--force", action="store_true")
    return value


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def require_within(path: Path, root: Path, label: str) -> None:
    try:
        path.resolve().relative_to(root.resolve())
    except ValueError as error:
        raise RuntimeError("R103 {} escapes campaign root: {}".format(label, path)) from error


def atomic_csv(frame: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary_name = tempfile.mkstemp(prefix=path.name + ".tmp.", dir=path.parent)
    os.close(handle)
    temporary = Path(temporary_name)
    try:
        frame.to_csv(temporary, index=False, quoting=csv.QUOTE_MINIMAL)
        temporary.replace(path)
    finally:
        if temporary.exists():
            temporary.unlink()


def validate_artifacts(terminal: dict[str, Any]) -> None:
    for record in terminal["artifacts"]:
        path = Path(record["path"])
        if not path.is_file() or sha256_file(path) != record["sha256"]:
            raise RuntimeError("R103 artifact changed: {}".format(path))


def artifact_manifest(
    owner: str,
    records: list[dict[str, Any]],
    roles: set[str],
) -> list[dict[str, Any]]:
    manifest = []
    for record in records:
        if record["role"] not in roles:
            continue
        path = Path(record["path"])
        manifest.append({
            "owner": owner,
            "role": record["role"],
            "path": str(path.resolve()),
            "bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        })
    return manifest


def robust_scale(y: np.ndarray) -> float:
    values = np.asarray(y, dtype=float)
    scale = float(np.median(np.abs(values - np.median(values))) * 1.4826)
    if not math.isfinite(scale) or scale <= 0:
        scale = float(np.std(values, ddof=1))
    return scale if math.isfinite(scale) and scale > 0 else 1.0


def design_bound(design_dir: Path, chunk_size: int = 4096) -> dict[str, float]:
    meta = read_json(design_dir / "design.json")
    n, p = int(meta["n"]), int(meta["p"])
    x = np.memmap(design_dir / "X.bin", mode="r", dtype="<f8", shape=(n, p))
    y = np.memmap(design_dir / "y.bin", mode="r", dtype="<f8", shape=(n,))
    squared = 0.0
    for start in range(0, n, chunk_size):
        row_l1 = np.sum(np.abs(x[start : start + chunk_size]), axis=1)
        squared += float(row_l1 @ row_l1)
    return {
        "n": n,
        "p": p,
        "rms_row_l1": math.sqrt(squared / n),
        "response_scale": robust_scale(y),
    }


def proof_from_trace(trace: pd.DataFrame, bound: dict[str, float]) -> dict[str, Any]:
    if trace.empty or any(name not in trace for name in RAW_TRACE_COLUMNS):
        raise RuntimeError("R103 exAL raw trace is incomplete")
    raw = trace.loc[:, RAW_TRACE_COLUMNS].to_numpy(dtype=float)
    if not np.isfinite(raw).all():
        raise RuntimeError("R103 exAL raw trace is non-finite")
    tail_state = float(trace.tail(10).delta_state.abs().max())
    relative_upper = tail_state
    prediction_upper = tail_state * bound["rms_row_l1"] / bound["response_scale"]
    return {
        **bound,
        "tail_rows": min(10, len(trace)),
        "tail_delta_state_max_abs": tail_state,
        "tail_delta_state_relative_upper_bound": relative_upper,
        "tail_delta_prediction_scaled_upper_bound": prediction_upper,
        "threshold": THRESHOLD,
        "relative_bound_passed": relative_upper < THRESHOLD,
        "prediction_bound_passed": prediction_upper < THRESHOLD,
        "proof": (
            "delta_state_relative <= max_abs(delta_beta); "
            "RMS(X delta_beta)/MAD(y) <= max_abs(delta_beta) "
            "* RMS(row_L1(X))/MAD(y)"
        ),
    }


def repairable(terminal: dict[str, Any]) -> bool:
    checks = terminal.get("numerical_checks", {})
    if terminal.get("family") != "exal" or terminal.get("formal_converged") is not True:
        return False
    false_checks = {name for name, value in checks.items() if value is not True}
    return bool(false_checks) and false_checks.issubset(MISSING_CHECKS)


def refresh_record(record: dict[str, Any]) -> None:
    path = Path(record["path"])
    record["bytes"] = path.stat().st_size
    record["sha256"] = sha256_file(path)


def repair_atom(terminal_path: Path, bound: dict[str, float], write: bool) -> dict[str, Any]:
    terminal = read_json(terminal_path)
    validate_artifacts(terminal)
    if terminal.get("diagnostic_gate_method") == "conservative_bound_repair_v1":
        return {
            "atom_id": terminal["atom_id"],
            "status": "already_repaired",
            "terminal_path": str(terminal_path.resolve()),
            "terminal_sha256": sha256_file(terminal_path),
        }
    if terminal.get("numerical_gate_passed") is True:
        return {"atom_id": terminal["atom_id"], "status": "already_passed"}
    if not repairable(terminal):
        raise RuntimeError("R103 exAL atom has non-repairable failures: {}".format(terminal["atom_id"]))
    trace_path = terminal_path.parent / "vb_trace.csv"
    proof = proof_from_trace(pd.read_csv(trace_path), bound)
    if not proof["relative_bound_passed"] or not proof["prediction_bound_passed"]:
        raise RuntimeError("R103 conservative diagnostic proof failed: {}".format(terminal["atom_id"]))
    result = {
        "atom_id": terminal["atom_id"],
        "status": "repairable_not_written" if not write else "repaired",
        "original_terminal_sha256": sha256_file(terminal_path),
        "original_numerical_gate_sha256": sha256_file(terminal_path.parent / "numerical_gate.json"),
        "model_artifacts_changed": False,
        "protected_artifact_count": len(artifact_manifest(
            terminal["atom_id"], terminal["artifacts"], PROTECTED_ATOM_ROLES
        )),
        "proof": proof,
    }
    if not write:
        return result
    checks = {
        name: value
        for name, value in terminal["numerical_checks"].items()
        if name not in MISSING_CHECKS
    }
    checks.update({
        "raw_trace_complete": True,
        "raw_trace_finite": True,
        "tail_relative_state_conservative_bound_below_0p01": True,
        "tail_prediction_scaled_conservative_bound_below_0p01": True,
    })
    repair_path = terminal_path.parent / "diagnostic_gate_repair.json"
    repair_record = {
        **result,
        "stage": "R103",
        "repair_method": "conservative_bound_repair_v1",
        "repair_script": str(Path(__file__).resolve()),
        "repair_script_sha256": sha256_file(Path(__file__)),
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "test_opened": False,
    }
    write_json(repair_path, repair_record)
    gate_path = terminal_path.parent / "numerical_gate.json"
    write_json(gate_path, {
        "checks": checks,
        "passed": True,
        "method": "conservative_bound_repair_v1",
        "proof_path": str(repair_path.resolve()),
        "proof_sha256": sha256_file(repair_path),
    })
    artifacts = list(terminal["artifacts"])
    by_role = {record["role"]: record for record in artifacts}
    refresh_record(by_role["numerical_gate"])
    artifacts.append({
        "path": str(repair_path.resolve()),
        "role": "diagnostic_gate_repair",
        "bytes": repair_path.stat().st_size,
        "sha256": sha256_file(repair_path),
    })
    terminal.update({
        "numerical_gate_passed": True,
        "numerical_checks": checks,
        "diagnostic_gate_method": "conservative_bound_repair_v1",
        "model_artifacts_changed_by_gate_repair": False,
        "artifacts": artifacts,
    })
    write_json(terminal_path, terminal)
    result["terminal_sha256"] = sha256_file(terminal_path)
    result["repair_path"] = str(repair_path.resolve())
    result["repair_sha256"] = sha256_file(repair_path)
    return result


def refresh_completed_case(case_dir: Path, atoms: pd.DataFrame) -> dict[str, Any]:
    fit_path = case_dir / "fit_terminal.json"
    case_path = case_dir / "terminal.json"
    if not fit_path.is_file() and not case_path.is_file():
        return {"case": case_dir.name, "status": "incomplete_case"}
    if not fit_path.is_file():
        raise RuntimeError("R103 completed-case metadata is incomplete: {}".format(case_dir))
    fit = read_json(fit_path)
    eligible = 0
    for record in fit["atom_terminals"]:
        path = Path(record["path"])
        record["sha256"] = sha256_file(path)
        eligible += int(read_json(path).get("numerical_gate_passed") is True)
    fit["atoms_numerically_eligible"] = eligible
    fit["diagnostic_gate_repair_applied"] = True
    write_json(fit_path, fit)

    if not case_path.is_file():
        return {
            "case_id": fit["case_id"],
            "status": "fit_complete_scoring_incomplete_refreshed",
            "atoms_numerically_eligible": eligible,
            "fit_terminal_sha256": sha256_file(fit_path),
        }

    metrics_path = case_dir / "family_validation_metrics.csv"
    metrics = pd.read_csv(metrics_path)
    exal_ok = True
    for row in atoms[atoms.family.eq("exal")].itertuples(index=False):
        value = read_json(Path(row.output_dir) / "terminal.json")
        exal_ok = exal_ok and value.get("numerical_gate_passed") is True
    metrics.loc[metrics.family.eq("exal"), "numerically_eligible"] = exal_ok
    atomic_csv(metrics, metrics_path)

    sources_path = case_dir / "source_manifest.csv"
    sources = pd.read_csv(sources_path)
    selected = sources.role.eq("fit_terminal")
    if selected.sum() != 1:
        raise RuntimeError("R103 case source manifest omits fit terminal")
    sources.loc[selected, "bytes"] = fit_path.stat().st_size
    sources.loc[selected, "sha256"] = sha256_file(fit_path)
    atomic_csv(sources, sources_path)

    case = read_json(case_path)
    for record in case["artifacts"]:
        if record["role"] in {"family_validation_metrics", "source_manifest"}:
            refresh_record(record)
    case["diagnostic_gate_repair_applied"] = True
    case["exal_numerically_eligible"] = exal_ok
    write_json(case_path, case)
    return {
        "case_id": case["case_id"],
        "status": "completed_case_refreshed",
        "exal_numerically_eligible": exal_ok,
        "atoms_numerically_eligible": eligible,
        "case_terminal_sha256": sha256_file(case_path),
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    prep = args.prep_dir.resolve()
    campaign = args.campaign_root.resolve()
    output = args.output_dir.resolve()
    if args.write and output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    summary = read_json(prep / "summary.json")
    if summary.get("status") != "prepared_validation_only_campaign" or summary.get("test_opened") is not False:
        raise RuntimeError("R103 repair requires a valid validation-only prep")
    for role, name in summary["output_files"].items():
        if sha256_file(prep / name) != summary["output_sha256"][role]:
            raise RuntimeError("R103 prep hash mismatch: {}".format(role))
    for row in pd.read_csv(prep / "source_manifest.csv").itertuples(index=False):
        path = Path(row.path)
        if not path.is_file() or sha256_file(path) != str(row.sha256):
            raise RuntimeError("R103 source changed: {}".format(path))
    cases = pd.read_csv(prep / "pricefm_stage_r103_case_manifest.csv")
    atoms = pd.read_csv(prep / "pricefm_stage_r103_atom_manifest.csv")
    require_within(output, campaign, "repair output")
    for path in atoms.output_dir:
        require_within(Path(path), campaign, "atom output")
    for path in cases.output_dir:
        require_within(Path(path), campaign, "case output")
    bound_cache: dict[str, dict[str, float]] = {}
    candidates = []
    validations = []
    protected_before = []
    for row in atoms[atoms.family.eq("exal")].itertuples(index=False):
        terminal_path = Path(row.output_dir) / "terminal.json"
        if not terminal_path.is_file():
            continue
        terminal = read_json(terminal_path)
        protected_before.extend(artifact_manifest(
            str(row.atom_id), terminal["artifacts"], PROTECTED_ATOM_ROLES
        ))
        case_id = str(row.case_id)
        if case_id not in bound_cache:
            config = read_json(Path(row.case_config))
            bound_cache[case_id] = design_bound(Path(config["design_dir"]))
        candidates.append((terminal_path, bound_cache[case_id]))
        validations.append(repair_atom(terminal_path, bound_cache[case_id], False))
    repairable_count = sum(
        value["status"] in {"already_repaired", "repairable_not_written"}
        for value in validations
    )
    if any(value["status"] == "already_passed" for value in validations):
        raise RuntimeError("R103 historical exAL terminal unexpectedly passed without exact diagnostics")
    case_records = []
    for row in cases.itertuples(index=False):
        case_terminal_path = Path(row.output_dir) / "terminal.json"
        if case_terminal_path.is_file():
            case_terminal = read_json(case_terminal_path)
            protected_before.extend(artifact_manifest(
                str(row.case_id), case_terminal["artifacts"], PROTECTED_CASE_ROLES
            ))
    repairs = validations
    if args.write:
        repairs = [repair_atom(path, bound, True) for path, bound in candidates]
        for row in cases.itertuples(index=False):
            case_dir = Path(row.output_dir)
            case_atoms = atoms[atoms.case_id.astype(str).eq(str(row.case_id))]
            case_records.append(refresh_completed_case(case_dir, case_atoms))
    result = {
        "stage": "R103",
        "status": "validated_not_written" if not args.write else "completed_exal_gate_metadata_repair",
        "exal_terminals_seen": len(repairs),
        "exal_terminals_repairable_or_repaired": repairable_count,
        "completed_cases_refreshed": sum(value.get("status") == "completed_case_refreshed" for value in case_records),
        "fit_complete_cases_refreshed": sum(
            value.get("status") == "fit_complete_scoring_incomplete_refreshed"
            for value in case_records
        ),
        "model_artifacts_changed": False,
        "predictions_changed": False,
        "validation_loss_values_changed": False,
        "eligibility_metadata_changed": bool(repairable_count),
        "test_opened": False,
    }
    if not args.write:
        print(json.dumps(result, indent=2, sort_keys=True))
        return result
    output.mkdir(parents=True, exist_ok=True)
    repairs_frame = pd.json_normalize(repairs)
    cases_frame = pd.DataFrame(case_records)
    protected_frame = pd.DataFrame(protected_before).sort_values(["owner", "role", "path"])
    for row in protected_frame.itertuples(index=False):
        if Path(row.path).stat().st_size != int(row.bytes) or sha256_file(row.path) != row.sha256:
            raise RuntimeError("R103 protected artifact changed during repair: {}".format(row.path))
    atomic_csv(repairs_frame, output / "atom_repairs.csv")
    atomic_csv(cases_frame, output / "case_repairs.csv")
    atomic_csv(protected_frame, output / "protected_artifact_manifest.csv")
    result["output_files"] = {
        "atom_repairs": "atom_repairs.csv",
        "case_repairs": "case_repairs.csv",
        "protected_artifacts": "protected_artifact_manifest.csv",
    }
    result["output_sha256"] = {
        role: sha256_file(output / name) for role, name in result["output_files"].items()
    }
    write_json(output / "summary.json", result)
    print(json.dumps(result, indent=2, sort_keys=True))
    return result


def main() -> int:
    run(parser().parse_args())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
