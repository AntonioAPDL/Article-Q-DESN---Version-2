#!/usr/bin/env python3
"""Prepare the validation-only R103 recursive independent AL/exAL campaign."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
from typing import Any

import pandas as pd

from pricefm_common import sha256_file, write_json
from pricefm_recursive_quantile import QUANTILES, WARM_ORDER, WARM_PARENT
from pricefm_region_frozen_contract import git_identity


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R102_PREP = DATA / "launch_prep/pricefm_stage_r102_recursive_normal_20260916"
R102B_PREP = DATA / "launch_prep/pricefm_stage_r102b_recursive_validation_20260916"
R102B_CLOSEOUT = DATA / "authoritative/pricefm_stage_r102b_recursive_validation_closeout_20260916"
RUNTIME = DATA / "runtime_libraries/exdqlm_pricefm_r94_coherent_exal_init"
RUNTIME_MANIFEST = RUNTIME / "pricefm_stage_r94_coherent_exal_init_manifest.json"
OUTPUT = DATA / "launch_prep/pricefm_stage_r103_recursive_quantile_20260916"
CAMPAIGN = DATA / "campaigns/pricefm_stage_r103_recursive_quantile_20260916"
EXPECTED_REPAIR = (
    "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-"
    "plus-structured-plugin-init-plus-coherent-al-latent-init"
)
BLOCKED = (
    "test_access_authorized",
    "joint_model_authorized",
    "mcmc_authorized",
    "registry_mutation_authorized",
    "article_mutation_authorized",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--code-root", type=Path, required=True)
    value.add_argument("--r102-prep", type=Path, default=R102_PREP)
    value.add_argument("--r102b-prep", type=Path, default=R102B_PREP)
    value.add_argument("--r102b-closeout", type=Path, default=R102B_CLOSEOUT)
    value.add_argument("--runtime", type=Path, default=RUNTIME)
    value.add_argument("--runtime-manifest", type=Path, default=RUNTIME_MANIFEST)
    value.add_argument("--output-dir", type=Path, default=OUTPUT)
    value.add_argument("--campaign-root", type=Path, default=CAMPAIGN)
    value.add_argument("--workers", type=int, default=12)
    value.add_argument("--write", action="store_true")
    value.add_argument("--force", action="store_true")
    return value


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def canonical_hash(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(payload.encode()).hexdigest()


def verify_closeout(path: Path) -> tuple[dict[str, Any], pd.DataFrame]:
    summary = read_json(path / "summary.json")
    expected = {
        "stage": "R102B",
        "status": "completed_recursive_normal_panel_frozen",
        "selected_prior_type": "rhs_ns",
        "selected_driver_rows": 114,
        "selection_split": "validation_only",
        "test_opened": False,
        "quantile_fit_started": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    for key, value in expected.items():
        if summary.get(key) != value:
            raise RuntimeError("R102B closeout gate failed: {}".format(key))
    for role, name in summary["output_files"].items():
        if sha256_file(path / name) != summary["output_sha256"][role]:
            raise RuntimeError("R102B closeout hash mismatch: {}".format(role))
    driver = pd.read_csv(path / summary["output_files"]["selected_driver_panel"])
    if (
        len(driver) != 114
        or driver[["region", "fold"]].duplicated().any()
        or driver.region.astype(str).nunique() != 38
        or set(driver.fold.astype(int)) != {1, 2, 3}
        or driver.test_access_authorized.astype(bool).any()
    ):
        raise RuntimeError("R102B selected driver panel is incomplete")
    return summary, driver


def file_record(path: Path, role: str) -> dict[str, Any]:
    path = path.resolve()
    return {
        "role": role,
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    if not 1 <= int(args.workers) <= 20:
        raise RuntimeError("R103 permits 1--20 one-core workers")
    code_root = args.code_root.resolve()
    git = git_identity(code_root)
    if not git.clean or git.head != git.upstream_head or not git.branch.startswith("work/pricefm-"):
        raise RuntimeError("R103 preparation requires a clean synchronized PriceFM task branch")
    r102 = args.r102_prep.resolve()
    r102b = args.r102b_prep.resolve()
    closeout = args.r102b_closeout.resolve()
    runtime = args.runtime.resolve()
    runtime_manifest = args.runtime_manifest.resolve()
    for path in (r102, r102b, closeout, runtime):
        if not path.is_dir():
            raise FileNotFoundError(path)
    if not runtime_manifest.is_file():
        raise FileNotFoundError(runtime_manifest)
    runtime_meta = read_json(runtime_manifest)
    if (
        runtime_meta.get("status") != "installed_coherent_exal_initialization_runtime"
        or runtime_meta.get("version") != "1.1.1.9005"
        or runtime_meta.get("repair") != EXPECTED_REPAIR
        or runtime_meta.get("test_opened") is not False
    ):
        raise RuntimeError("R103 requires the hash-pinned coherent exAL runtime")

    r102_summary = read_json(r102 / "summary.json")
    for role, name in r102_summary["output_files"].items():
        if sha256_file(r102 / name) != r102_summary["output_sha256"][role]:
            raise RuntimeError("R102 prep hash mismatch: {}".format(role))
    closeout_summary, selected = verify_closeout(closeout)
    designs = pd.read_csv(r102 / "pricefm_stage_r102_design_manifest.csv")
    fits = pd.read_csv(r102 / "pricefm_stage_r102_fit_manifest.csv")
    tasks = pd.read_csv(r102b / "pricefm_stage_r102b_task_manifest.csv")
    selected_panel = str(closeout_summary["selected_panel"])
    selected_surface = tasks[
        tasks.panel.astype(str).eq(selected_panel)
        & tasks.prior_type.astype(str).eq("rhs_ns")
    ].copy()
    selected_surface["fold"] = selected_surface.fold.astype(int)
    surface_by_fold = selected_surface.set_index("fold", drop=False)
    if len(surface_by_fold) != 3:
        raise RuntimeError("R103 requires three selected Normal-RHS validation surfaces")
    design_by_id = designs.set_index("design_id")
    fit_by_id = fits.set_index("fit_id")
    campaign = args.campaign_root.resolve()
    output = args.output_dir.resolve()
    source_files = [
        Path(__file__),
        Path(__file__).with_name("pricefm_recursive_quantile.py"),
        Path(__file__).with_name("344_run_pricefm_stage_r103_quantile_case.R"),
        Path(__file__).with_name("345_run_pricefm_stage_r103_quantile_case.py"),
        Path(__file__).with_name("346_closeout_pricefm_stage_r103_recursive_quantile.py"),
        Path(__file__).with_name("347_orchestrate_pricefm_stage_r103_recursive_quantile.py"),
        Path(__file__).with_name("348_repair_pricefm_stage_r103_exal_gate.py"),
        Path(__file__).with_name("pricefm_stage_r67_cran111_adapter.R"),
        Path(__file__).with_name("pricefm_stage_r72_repair_adapter.R"),
        Path(__file__).with_name("pricefm_stage_r75_large_n_gig_adapter.R"),
    ]
    if any(not path.is_file() for path in source_files):
        raise FileNotFoundError("R103 source set is incomplete")
    source_records = [file_record(path, "R103_source") for path in source_files]
    source_records.extend([
        file_record(closeout / "summary.json", "R102B_closeout_summary"),
        file_record(closeout / closeout_summary["output_files"]["selected_driver_panel"], "R102B_selected_driver"),
        file_record(closeout / closeout_summary["output_files"]["decision"], "R102B_decision"),
        file_record(r102 / "pricefm_stage_r102_design_manifest.csv", "R102_design_manifest"),
        file_record(r102 / "pricefm_stage_r102_fit_manifest.csv", "R102_fit_manifest"),
        file_record(r102b / "pricefm_stage_r102b_task_manifest.csv", "R102B_task_manifest"),
        file_record(runtime_manifest, "coherent_exAL_runtime_manifest"),
    ])
    runtime_package = runtime / "exdqlm"
    for relative in (
        "DESCRIPTION",
        "R/exdqlm.rdb",
        "R/exdqlm.rdx",
        "libs/exdqlm.so",
    ):
        source_records.append(file_record(runtime_package / relative, "coherent_exAL_runtime_binary"))

    case_rows: list[dict[str, Any]] = []
    atom_rows: list[dict[str, Any]] = []
    configs: dict[str, dict[str, Any]] = {}
    for row in selected.sort_values(["region", "fold"]).itertuples(index=False):
        region = str(row.region)
        fold = int(row.fold)
        fit = fit_by_id.loc[str(row.rhs_fit_id)]
        design = design_by_id.loc[str(fit.design_id)]
        surface = surface_by_fold.loc[fold]
        case_id = "r103_{}_f{}".format(region.lower(), fold)
        case_output = campaign / "cases" / "region={}".format(region) / "fold={}".format(fold)
        config_path = output / "cases" / "{}.json".format(case_id)
        atoms = []
        for order, tau in enumerate(WARM_ORDER, start=1):
            parent_family, parent_tau = WARM_PARENT[tau]
            al_id = "{}_al_{}".format(case_id, str(tau).replace(".", "p"))
            exal_id = "{}_exal_{}".format(case_id, str(tau).replace(".", "p"))
            for family, atom_id, p_family, p_tau in (
                ("al", al_id, parent_family, parent_tau),
                ("exal", exal_id, "al", tau),
            ):
                atom_output = case_output / "atoms" / atom_id
                atom = {
                    "atom_id": atom_id,
                    "case_id": case_id,
                    "region": region,
                    "fold": fold,
                    "family": family,
                    "tau": float(tau),
                    "warm_order": order,
                    "parent_family": p_family,
                    "parent_tau": None if p_tau is None else float(p_tau),
                    "output_dir": str(atom_output.resolve()),
                    "seed": int(json.loads(str(design.spec_json))["seed"]) + fold * 1000 + order * 10 + (family == "exal"),
                }
                atom["posterior_target_sha256"] = canonical_hash({
                    "design_id": str(fit.design_id),
                    "family": family,
                    "tau": float(tau),
                    "prior": "rhs_ns",
                    "tau0": float(fit.tau0),
                    "shrink_intercept": False,
                    "sigma_prior": {"a": 1.0, "b": 1.0},
                    "gamma_prior": {"mu0": 0.0, "s20": 10.0} if family == "exal" else None,
                })
                atoms.append(atom)
                atom_rows.append({**atom, "case_config": str(config_path.resolve())})
        config = {
            "schema_version": 1,
            "stage": "R103",
            "case_id": case_id,
            "region": region,
            "fold": fold,
            "panel": selected_panel,
            "design_id": str(fit.design_id),
            "spec_json": str(design.spec_json),
            "active_regions": json.loads(str(design.active_regions)),
            "data_config_path": str(Path(design.data_config_path).resolve()),
            "statistics_dir": str(Path(design.statistics_dir).resolve()),
            "normal_fit_dir": str(Path(fit.output_dir).resolve()),
            "normal_rhs_fit_id": str(row.rhs_fit_id),
            "normal_driver_surface": str(Path(surface.output_dir).resolve()),
            "normal_driver_task_id": str(surface.task_id),
            "design_dir": str((case_output / "design").resolve()),
            "output_dir": str(case_output.resolve()),
            "runtime_library": str(runtime),
            "runtime_manifest": str(runtime_manifest),
            "runtime_manifest_sha256": sha256_file(runtime_manifest),
            "adapters": [file_record(path, "fit_adapter") for path in source_files[-3:]],
            "atoms": atoms,
            "quantiles": list(QUANTILES),
            "posterior_paths": 500,
            "rhs": {
                "tau0": float(fit.tau0),
                "init_tau": 1.0,
                "shrink_intercept": False,
                "freeze_tau_iters": 50,
                "freeze_tau_warmup_iters": 50,
            },
            "qdesn_vb": {
                "max_iter": 500,
                "tol": 1e-4,
                "n_samp": 200,
                "n_samp_xi": 200,
                "prior_sigma": {"a": 1.0, "b": 1.0},
                "prior_gamma": {"mu0": 0.0, "s20": 10.0},
                "structured_sigmagam": {
                    "factorization": "structured",
                    "structured_grid_size": 151,
                    "structured_span_sd": 6.0,
                    "freeze_warmup_iters": 0,
                    "force_after_warmup": True,
                    "postwarmup_damping": 0.2,
                    "postwarmup_damping_iters": 30,
                    "min_postwarmup_updates": 35,
                },
            },
            "selection_split": "validation_only",
            "training_split": "train_only_causal_teacher_forced",
            "recursive_driver": "common_selected_normal_rhs_500_paths",
            "family_selection_rule": "fold1_validation_whole_family_then_numerical_fallback_to_AL",
            "test_opened": False,
            **{name: False for name in BLOCKED},
        }
        config["case_contract_sha256"] = canonical_hash(config)
        configs[case_id] = config
        case_rows.append({
            "case_id": case_id,
            "region": region,
            "fold": fold,
            "panel": selected_panel,
            "design_id": str(fit.design_id),
            "normal_rhs_fit_id": str(row.rhs_fit_id),
            "normal_driver_task_id": str(surface.task_id),
            "case_config": str(config_path.resolve()),
            "case_contract_sha256": config["case_contract_sha256"],
            "output_dir": str(case_output.resolve()),
            "selection_split": "validation_only",
            "test_access_authorized": False,
        })

    cases = pd.DataFrame(case_rows)
    atoms = pd.DataFrame(atom_rows)
    if len(cases) != 114 or len(atoms) != 1596:
        raise RuntimeError("R103 manifest cardinality is not 114 cases / 1596 atoms")
    gates = pd.DataFrame([
        ("r102b_g3_complete", True, closeout_summary["status"]),
        ("selected_whole_rhs_panel", selected_panel in {"r98_control", "r100_primary"}, selected_panel),
        ("case_surface_complete", len(cases) == 114, len(cases)),
        ("atom_surface_complete", len(atoms) == 1596, len(atoms)),
        ("seven_quantiles_two_families", True, "7x2x114"),
        ("posterior_paths_fixed", True, 500),
        ("runtime_hash_pinned", True, runtime_meta["version"]),
        ("test_and_mutations_blocked", True, ";".join(BLOCKED)),
    ], columns=["gate", "passed", "observed"])
    if not gates.passed.all():
        raise RuntimeError("R103 preparation gate failed")
    preview = {
        "stage": "R103",
        "status": "validated_not_materialized" if not args.write else "prepared_validation_only_campaign",
        "selected_panel": selected_panel,
        "cases": len(cases),
        "atoms": len(atoms),
        "workers": int(args.workers),
        "posterior_paths": 500,
        "test_opened": False,
        "launch_authorized": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    if not args.write:
        print(json.dumps(preview, indent=2, sort_keys=True))
        return preview
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        (temporary / "cases").mkdir()
        for case_id, config in configs.items():
            write_json(temporary / "cases" / "{}.json".format(case_id), config)
        # Paths were computed for the final output directory; the atomic rename preserves them.
        cases.to_csv(temporary / "pricefm_stage_r103_case_manifest.csv", index=False, quoting=csv.QUOTE_MINIMAL)
        atoms.to_csv(temporary / "pricefm_stage_r103_atom_manifest.csv", index=False, quoting=csv.QUOTE_MINIMAL)
        gates.to_csv(temporary / "pricefm_stage_r103_prep_gates.csv", index=False)
        pd.DataFrame(source_records).sort_values(["role", "path"]).to_csv(temporary / "source_manifest.csv", index=False)
        control = {
            "stage": "R103",
            "campaign_root": str(campaign),
            "prep_dir": str(output),
            "code_root": str(code_root),
            "source_git": git.to_dict(),
            "workers": int(args.workers),
            "approval_token": "RUN_PRICEFM_R103_RECURSIVE_QUANTILE",
            "expected_cases": 114,
            "expected_atoms": 1596,
            "test_opened": False,
            **{name: False for name in BLOCKED},
        }
        write_json(temporary / "pricefm_stage_r103_launch_control.json", control)
        report = """# PriceFM Stage-R103 recursive quantile preparation

R103 reuses the validation-selected **{panel}** Normal-RHS driver and its 114
region-fold contracts. It fits 1,596 independent VB atoms: seven AL and seven
structured exAL quantiles per case. Training is causal teacher forced; validation
readouts consume the same 500 synchronized Normal-RHS paths. Family selection is
one whole seven-quantile family per region from Fold-1 validation, with no fold or
quantile mixing. Test, joint models, MCMC, registry, and article mutation remain
blocked.
""".format(panel=selected_panel)
        (temporary / "pricefm_stage_r103_launch_prep.md").write_text(report)
        outputs = {
            "cases": "pricefm_stage_r103_case_manifest.csv",
            "atoms": "pricefm_stage_r103_atom_manifest.csv",
            "gates": "pricefm_stage_r103_prep_gates.csv",
            "sources": "source_manifest.csv",
            "control": "pricefm_stage_r103_launch_control.json",
            "report": "pricefm_stage_r103_launch_prep.md",
        }
        summary = {
            **preview,
            "status": "prepared_validation_only_campaign",
            "source_git": git.to_dict(),
            "output_files": outputs,
            "output_sha256": {role: sha256_file(temporary / name) for role, name in outputs.items()},
        }
        write_json(temporary / "summary.json", summary)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> int:
    run(parser().parse_args())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
