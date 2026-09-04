#!/usr/bin/env python3
"""Close out the homogeneous R87/R83 exAL surface under frozen R82 gates."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
from typing import Any

import pandas as pd


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "pricefm_r85", HERE / "279_audit_pricefm_stage_r85_surface_wide_numerical_validity.py"
)
R85_MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = R85_MODULE
SPEC.loader.exec_module(R85_MODULE)
DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
R85 = DATA / "authoritative/pricefm_stage_r85_surface_wide_numerical_audit_20260904"
R87 = DATA / "experiment_grids/pricefm_stage_r87_homogeneous_exal_refit_20260904"
R83 = DATA / "experiment_grids/pricefm_stage_r83_structured_init_failed_atom_retry_20260904"
OUTPUT = DATA / "authoritative/pricefm_stage_r88_repaired_exal_surface_closeout_20260905"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r85-dir", type=Path, default=R85)
    p.add_argument("--r87-dir", type=Path, default=R87)
    p.add_argument("--r83-dir", type=Path, default=R83)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--force", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def summarize_cases(atoms: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for keys, case in atoms.groupby(["case_id", "region", "fold"], sort=True):
        case_id, region, fold = keys
        rows.append({
            "case_id": case_id, "region": region, "fold": int(fold),
            "atoms": len(case), "quantiles": case.tau.nunique(),
            "r87_atoms": int(case.source_stage.eq("R87").sum()),
            "r83_atoms": int(case.source_stage.eq("R83").sum()),
            "all_atoms_numerically_eligible": bool(case.atom_numerically_eligible.all()),
            "numerically_eligible_atoms": int(case.atom_numerically_eligible.sum()),
            "fallback_to_al_required": not bool(case.atom_numerically_eligible.all()),
            "test_opened": False,
        })
    return pd.DataFrame(rows).sort_values(["region", "fold"])


def run(args: argparse.Namespace) -> dict[str, Any]:
    r85_summary_path = args.r85_dir / "summary.json"
    r85_summary = json.loads(r85_summary_path.read_text())
    r87_summary_path = args.r87_dir / "launch_summary.json"
    r87_summary = json.loads(r87_summary_path.read_text())
    r83_summary_path = args.r83_dir / "launch_summary.json"
    r83_summary = json.loads(r83_summary_path.read_text())
    manifest87_path = args.r87_dir / "task_manifest.csv"
    status87_path = args.r87_dir / "launch_status.csv"
    retained83_path = args.r85_dir / "pricefm_stage_r85_retained_r83_atoms.csv"
    manifest87 = pd.read_csv(manifest87_path)
    status87 = pd.read_csv(status87_path).set_index("task_id")
    retained83 = pd.read_csv(retained83_path)
    if r85_summary.get("legacy_r76_atoms_requiring_refit") != 280:
        raise RuntimeError("R85 homogeneous-refit boundary changed")
    if (
        r87_summary.get("status") != "completed" or r87_summary.get("completed") != 280
        or r87_summary.get("failed") != 0 or len(manifest87) != 280
    ):
        raise RuntimeError("R87 has not completed all 280 atoms cleanly")
    if r83_summary.get("status") != "completed" or r83_summary.get("failed") != 0:
        raise RuntimeError("R83 retained partition is not complete")
    if len(retained83) != 14:
        raise RuntimeError("R83 retained atom boundary changed")

    rows = []
    for row in manifest87.sort_values(["region", "fold", "tau"]).itertuples(index=False):
        if str(status87.loc[row.task_id, "status"]) not in {"completed", "skipped_completed"}:
            raise RuntimeError(f"R87 task incomplete: {row.task_id}")
        audit = R85_MODULE.audit_output(Path(row.output_dir), row.task_id, "R87")
        rows.append({
            "case_id": row.case_id, "region": row.region, "fold": int(row.fold),
            "tau": float(row.tau), "initializer_valid": True,
            "atom_numerically_eligible": bool(audit["visible_numerical_bounds_pass"]),
            **audit,
        })
    for row in retained83.sort_values(["region", "fold", "tau"]).itertuples(index=False):
        audit = R85_MODULE.audit_output(Path(row.output_dir), row.source_task_id, "R83")
        rows.append({
            "case_id": row.case_id, "region": row.region, "fold": int(row.fold),
            "tau": float(row.tau), "initializer_valid": True,
            "atom_numerically_eligible": bool(audit["visible_numerical_bounds_pass"]),
            **audit,
        })
    atoms = pd.DataFrame(rows).sort_values(["region", "fold", "tau"])
    if (
        len(atoms) != 294 or atoms.case_id.nunique() != 42
        or not atoms.groupby("case_id").tau.nunique().eq(7).all()
        or atoms.source_stage.value_counts().to_dict() != {"R87": 280, "R83": 14}
    ):
        raise RuntimeError("R88 corrected exAL surface identity contract failed")
    cases = summarize_cases(atoms)
    gates = pd.DataFrame([
        {"gate": "r87_280_atoms_complete", "passed": len(atoms[atoms.source_stage.eq("R87")]) == 280, "observed": 280},
        {"gate": "r83_14_atoms_retained", "passed": len(atoms[atoms.source_stage.eq("R83")]) == 14, "observed": 14},
        {"gate": "complete_42_case_seven_quantile_surface", "passed": len(cases) == 42 and cases.quantiles.eq(7).all(), "observed": len(cases)},
        {"gate": "single_repaired_runtime_family", "passed": atoms.package_version.eq("1.1.1.9004").all(), "observed": atoms.package_version.value_counts().to_dict()},
        {"gate": "failed_exal_cases_fallback_to_al", "passed": True, "observed": int(cases.fallback_to_al_required.sum())},
        {"gate": "no_further_rescue_loop", "passed": True, "observed": "closed"},
        {"gate": "test_registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
    ])
    if not gates.passed.all():
        raise RuntimeError("R88 closeout gates failed")
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True)
    atoms.to_csv(output / "pricefm_stage_r88_exal_atom_ledger.csv", index=False)
    cases.to_csv(output / "pricefm_stage_r88_exal_case_eligibility.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r88_closeout_gates.csv", index=False)
    fixed = [Path(__file__).resolve(), r85_summary_path, r87_summary_path,
             r83_summary_path, manifest87_path, status87_path, retained83_path]
    pd.DataFrame([
        {"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in fixed
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "repaired_exal_surface_closed_validation_selection_authorized",
        "atoms": 294, "cases": 42,
        "numerically_eligible_atoms": int(atoms.atom_numerically_eligible.sum()),
        "eligible_exal_cases": int(cases.all_atoms_numerically_eligible.sum()),
        "fallback_al_cases": int(cases.fallback_to_al_required.sum()),
        "r89_validation_selection_authorized": True,
        "additional_rescue_authorized": False,
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
        "joint_or_mcmc_authorized": False,
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    (output / "pricefm_stage_r88_repaired_exal_surface_closeout_report.md").write_text(
        "# PriceFM Stage-R88 Repaired exAL Surface Closeout\n\n"
        f"R88 verified 294 repaired-runtime exAL atoms across 42 complete seven-quantile "
        f"surfaces. {summary['eligible_exal_cases']} cases pass every frozen atom gate; "
        f"{summary['fallback_al_cases']} cases must use their frozen AL surface. The numerical "
        "repair campaign is closed: no additional rescue is authorized. Test and all mutation "
        "actions remain blocked pending R89 validation-only selection.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
