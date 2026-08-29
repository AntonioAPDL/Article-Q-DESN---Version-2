#!/usr/bin/env python3
"""Prepare the checkpoint-reusing R66 corrected structured-exAL VB campaign."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R65_TAG = "pricefm_stage_r65_independent_structured_exal_vb_20260829"
R65_GRID = DATA / "experiment_grids" / R65_TAG
R65_CLOSEOUT = DATA / "authoritative/pricefm_stage_r65_early_stop_closeout_20260829"
TAG = "pricefm_stage_r66_corrected_structured_exal_vb_20260829"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r66_corrected_structured_exal_vb_prep_20260829"
PYTHON = DATA / "venv/bin/python"
PACKAGE = Path("/data/jaguir26/local/src/exdqlm__wt__pricefm_r66_ab5741c")
PACKAGE_LIBRARY = DATA / "runtime_libraries/exdqlm_ab5741c"
PACKAGE_COMMIT = "ab5741ceb854db9a53889a17c91d2d30f4d8c41d"
PACKAGE_HASHES = {
    "R/exal_ldvb_engine.R": "d82d1be56a156c32eb681f5464ac00ea8765992034c84824c0c98066d09912e3",
    "R/exal_inference_config.R": "18f6a140e0dc4e33702528b21db8bf3b264b743fc745f2daf0b276143fb11044",
    "R/exal_sigmagam_structured.R": "c039125ab261c950ea464cc886f48257558b273df1e400aa407f72ff36e5d762",
}
R65_PACKAGE_COMMIT = "cc85a75ceca51c6e6a699147c45742591c7e3679"
R65_METHOD_AL = "qdesn_al_rhs_ns_exact_chunked_r65_parity"
METHOD_AL = "qdesn_al_rhs_ns_exact_chunked_r66_parity"
METHOD_EXAL = "qdesn_exal_rhs_ns_exact_chunked_structured_corrected_r66"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
GATE_CASE_ID = "pricefm_joint_at_f1"
STRUCTURED_PROFILE = {
    "factorization": "structured",
    "structured_grid_size": 151,
    "structured_span_sd": 6.0,
    "freeze_warmup_iters": 10,
    "force_after_warmup": True,
    "postwarmup_damping": 0.2,
    "postwarmup_damping_iters": 30,
    "min_postwarmup_updates": 35,
    "minimum_exact_commits": 5,
    "minimum_gamma_relative_boundary_margin": 1e-6,
}
ADAPTER_FILES = (
    "adapter_manifest.json",
    "feature_manifest.json",
    "X_train.csv",
    "y_train.csv",
    "X_val.csv",
    "rows_train.csv",
    "rows_val.csv",
)
FORBIDDEN_TEST_FILES = ("X_test.csv", "y_test.csv", "rows_test.csv")
RUNTIME_CODE_SOURCES = (
    "application/scripts/pricefm/07_build_desn_direct_horizon_adapter.py",
    "application/scripts/pricefm/09_summarize_desn_model_smoke.py",
    "application/scripts/pricefm/230_run_pricefm_stage_r66_corrected_structured_exal_vb_case.R",
    "application/scripts/pricefm/pricefm_stage_r66_vb_helpers.R",
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, required=True)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--r65-manifest", type=Path, default=R65_GRID / "case_manifest.csv")
    p.add_argument("--r65-components", type=Path, default=R65_GRID / "component_ledger.csv")
    p.add_argument(
        "--r65-reuse-manifest",
        type=Path,
        default=R65_CLOSEOUT / "pricefm_stage_r65_checkpoint_reuse_manifest.csv",
    )
    p.add_argument("--r65-closeout-summary", type=Path, default=R65_CLOSEOUT / "summary.json")
    p.add_argument("--package-path", type=Path, default=PACKAGE)
    p.add_argument("--package-library", type=Path, default=PACKAGE_LIBRARY)
    p.add_argument("--python-bin", type=Path, default=PYTHON)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-cases", type=int, default=114)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def git_head(path: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
    ).strip()


def verify_package(path: Path) -> dict:
    path = path.resolve()
    if git_head(path) != PACKAGE_COMMIT:
        raise RuntimeError(f"Package checkout is not pinned to {PACKAGE_COMMIT}")
    if subprocess.check_output(
        ["git", "-C", str(path), "status", "--porcelain"], text=True
    ).strip():
        raise RuntimeError("Pinned R66 package checkout is dirty")
    observed = {name: sha256(path / name) for name in PACKAGE_HASHES}
    if observed != PACKAGE_HASHES:
        raise RuntimeError(f"Pinned package source hashes differ: {observed}")
    return {"path": str(path), "commit": PACKAGE_COMMIT, "source_sha256": observed}


def verify_runtime_library(path: Path) -> str:
    path = path.resolve()
    manifest_path = path / "pricefm_r66_install_manifest.json"
    if not manifest_path.is_file() or not (path / "exdqlm").is_dir():
        raise RuntimeError(f"R66 package runtime library is not materialized: {path}")
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("source_commit") != PACKAGE_COMMIT:
        raise RuntimeError("R66 installed package commit differs from the pinned source")
    if manifest.get("source_sha256") != PACKAGE_HASHES:
        raise RuntimeError("R66 installed package hashes differ from the pinned source")
    return str(path)


def prepare_dir(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(f"Output exists: {path}")
    path.mkdir(parents=True, exist_ok=True)


def boolish(value) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def tau_key(value: float) -> str:
    return f"{float(value):.12g}"


def tau_slug(value: float) -> str:
    return tau_key(value).replace("-", "m").replace(".", "p")


def load_payload(path: Path) -> dict:
    payload = yaml.safe_load(path.read_text())
    if not isinstance(payload, dict) or "pricefm_desn_smoke" not in payload:
        raise ValueError(f"Not a PriceFM DESN config: {path}")
    return payload


def fit_contract(status_path: Path, fit_path: Path, expected: dict) -> dict | None:
    if not status_path.is_file() or not fit_path.is_file():
        return None
    status = json.loads(status_path.read_text())
    for key, value in expected.items():
        if str(status.get(key)) != str(value):
            return None
    observed = sha256(fit_path)
    if str(status.get("fit_sha256")) != observed:
        return None
    return {
        "fit_path": str(fit_path.resolve()),
        "status_path": str(status_path.resolve()),
        "fit_sha256": observed,
        "status_sha256": sha256(status_path),
    }


def adapter_contract(path: Path) -> dict | None:
    path = path.resolve()
    if any((path / name).exists() for name in FORBIDDEN_TEST_FILES):
        raise RuntimeError(f"R65 adapter violates the test firewall: {path}")
    required = [path / name for name in ADAPTER_FILES]
    if not all(item.is_file() for item in required):
        return None
    return {
        "path": str(path),
        "source_sha256": {item.name: sha256(item) for item in required},
    }


def source_row(path: Path, role: str) -> dict:
    return {
        "role": role,
        "path": str(path.resolve()),
        "sha256": sha256(path),
        "bytes": path.stat().st_size,
    }


def generated_payload(
    source: dict,
    case_id: str,
    region: str,
    fold: int,
    data_config: Path,
    adapter_dir: Path,
    output_dir: Path,
    package: dict,
    python_bin: Path,
    code_hashes: dict[str, str],
    r65_row: pd.Series,
    adapter_reuse: dict | None,
    normal_reuse: dict | None,
    al_reuse: dict[str, dict],
) -> dict:
    smoke = copy.deepcopy(source["pricefm_desn_smoke"])
    smoke["data_config"] = str(data_config.resolve())
    smoke["python_bin"] = str(python_bin.absolute())
    smoke["package_path"] = package["path"]
    smoke["splits"] = ["train", "val"]
    smoke["quantiles"] = list(TAUS)
    smoke["adapter"]["output_dir"] = str(adapter_dir.resolve())
    smoke["run"]["output_dir"] = str(output_dir.resolve())
    smoke["qdesn_vb"]["likelihoods"] = ["al", "exal"]
    smoke["qdesn_vb"]["readout_modes"] = ["shared_static"]
    smoke["qdesn_vb"]["max_iter"] = max(150, int(smoke["qdesn_vb"]["max_iter"]))
    smoke["qdesn_vb"]["sigmagam"] = {
        key: value for key, value in STRUCTURED_PROFILE.items()
        if key not in {"minimum_exact_commits", "minimum_gamma_relative_boundary_margin"}
    }
    smoke.setdefault("exact_equivalence", {})["enabled"] = False
    smoke.setdefault("warm_start", {})["enabled"] = True
    smoke["warm_start"]["fallback_to_cold"] = False
    smoke["warm_start"]["qdesn"] = {
        "al": {
            "enabled": True,
            "source_each_tau": "hash_valid_r65_al_or_shared_normal_rhs_anchor",
            "components": ["beta", "beta_state", "sigma"],
        },
        "exal": {
            "enabled": True,
            "source": "same_tau_hash_valid_al",
            "components": ["beta", "beta_state", "sigma"],
            "gamma_policy": "zero",
        },
    }
    smoke["artifact_hygiene"] = {"enabled": False}
    r66 = {
        "stage": "R66",
        "case_id": case_id,
        "selection_split": "val",
        "selection_metric": "raw_original_seven_quantile_mean_AQL",
        "gate_case_id": GATE_CASE_ID,
        "source_r65_config": str(Path(r65_row.config).resolve()),
        "source_r65_config_sha256": str(r65_row.config_sha256),
        "authority_scientific_contract_sha256": str(r65_row.scientific_contract_sha256),
        "authority_feature_semantics_sha256": str(r65_row.feature_semantics_sha256),
        "package": package,
        "code": {"source_sha256": code_hashes},
        "structured_sigmagam": copy.deepcopy(STRUCTURED_PROFILE),
        "method_ids": {"al": METHOD_AL, "exal": METHOD_EXAL},
        "reuse": {
            "source_stage": "R65",
            "source_package_commit": R65_PACKAGE_COMMIT,
            "adapter": adapter_reuse,
            "normal_anchor": normal_reuse,
            "al_by_tau": al_reuse,
            "r65_exal_reuse_authorized": False,
        },
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    return {"pricefm_desn_smoke": smoke, "pricefm_stage_r66": r66}


def run(args: argparse.Namespace) -> dict:
    code_root = args.code_root.resolve()
    grid = args.grid_dir.resolve()
    runs = args.run_dir.resolve()
    output = args.output_dir.resolve()
    prepare_dir(grid, args.force)
    prepare_dir(output, args.force)
    runs.mkdir(parents=True, exist_ok=True)

    package = verify_package(args.package_path)
    package["library"] = verify_runtime_library(args.package_library)
    code_hashes = {path: sha256(code_root / path) for path in RUNTIME_CODE_SOURCES}
    r65 = pd.read_csv(args.r65_manifest)
    r65_components = pd.read_csv(args.r65_components)
    reuse = pd.read_csv(args.r65_reuse_manifest)
    closeout = json.loads(args.r65_closeout_summary.read_text())
    if closeout.get("status") != "scientifically_stopped_mechanism_failure":
        raise RuntimeError("R65 is not frozen under the expected early-stop status")
    if len(r65) != args.expected_cases or len(r65_components) != args.expected_cases * 7:
        raise RuntimeError("R65 does not expose the complete case/component contract")
    if len(reuse) != args.expected_cases * 7:
        raise RuntimeError("R65 checkpoint-reuse manifest is incomplete")
    if r65.duplicated(["region", "fold"]).any() or reuse.duplicated(["case_id", "tau"]).any():
        raise RuntimeError("R65 source manifests contain duplicate scientific cells")

    config_dir = grid / "configs/cases"
    data_dir = grid / "configs/data"
    config_dir.mkdir(parents=True, exist_ok=True)
    data_dir.mkdir(parents=True, exist_ok=True)
    case_rows: list[dict] = []
    component_rows: list[dict] = []
    source_rows: list[dict] = []

    for row in r65.sort_values(["region", "fold"]).itertuples(index=False):
        source_config = Path(row.config).resolve()
        if sha256(source_config) != str(row.config_sha256):
            raise RuntimeError(f"R65 config hash drift: {row.case_id}")
        source = load_payload(source_config)
        if set(source) != {"pricefm_desn_smoke", "pricefm_stage_r65"}:
            raise RuntimeError(f"Unexpected R65 config shape: {source_config}")
        source_smoke = source["pricefm_desn_smoke"]
        if list(map(float, source_smoke["quantiles"])) != list(TAUS):
            raise RuntimeError(f"R65 quantile contract drift: {row.case_id}")
        if list(map(str, source_smoke["splits"])) != ["train", "val"]:
            raise RuntimeError(f"R65 test firewall drift: {row.case_id}")

        source_data = Path(source_smoke["data_config"]).resolve()
        data_config = data_dir / f"{row.case_id}.yaml"
        shutil.copyfile(source_data, data_config)
        source_rows.append(source_row(source_data, "r65_data_config"))

        source_adapter = adapter_contract(Path(row.adapter_dir))
        new_case_root = runs / str(row.case_id)
        adapter_dir = Path(source_adapter["path"]) if source_adapter else new_case_root / "adapter"
        source_model = Path(row.output_dir)
        normal_reuse = fit_contract(
            source_model / "normal_anchor/normal_rhs_anchor.json",
            source_model / "normal_anchor/normal_rhs_anchor.rds",
            {
                "config_sha256": row.config_sha256,
                "package_head": R65_PACKAGE_COMMIT,
                "case_id": row.case_id,
                "role": "shared_normal_rhs_anchor",
            },
        )

        case_reuse = reuse[reuse.case_id.astype(str).eq(str(row.case_id))].copy()
        source_components = r65_components[
            r65_components.case_id.astype(str).eq(str(row.case_id))
        ].copy()
        if len(case_reuse) != 7 or set(round(float(value), 12) for value in case_reuse.tau) != set(TAUS):
            raise RuntimeError(f"R65 reuse coverage is incomplete: {row.case_id}")
        if len(source_components) != 7:
            raise RuntimeError(f"R65 source component coverage is incomplete: {row.case_id}")
        al_by_tau: dict[str, dict] = {}
        reused_count = 0
        for component in case_reuse.sort_values("tau").itertuples(index=False):
            tau = float(component.tau)
            source_component = source_components[
                source_components.tau.astype(float).round(12).eq(round(tau, 12))
            ]
            if len(source_component) != 1:
                raise RuntimeError(f"R65 source component is ambiguous: {row.case_id} tau={tau}")
            source_component = source_component.iloc[0]
            contract = None
            if boolish(component.reuse_al_fit_authorized):
                contract = fit_contract(
                    Path(component.al_status_path),
                    Path(component.al_fit_path),
                    {
                        "config_sha256": row.config_sha256,
                        "package_head": R65_PACKAGE_COMMIT,
                        "case_id": row.case_id,
                        "tau": tau_key(tau),
                        "method_id": R65_METHOD_AL,
                    },
                )
                if contract is None or contract["fit_sha256"] != str(component.al_fit_sha256):
                    raise RuntimeError(f"Authorized R65 AL checkpoint failed validation: {row.case_id} tau={tau}")
                contract["source_method_id"] = R65_METHOD_AL
                contract["authorized"] = True
                reused_count += 1
            al_by_tau[tau_key(tau)] = contract
            component_rows.append({
                "case_id": row.case_id,
                "region": row.region,
                "fold": int(row.fold),
                "tau": tau,
                "reuse_r65_al_authorized": contract is not None,
                "r65_al_fit_path": contract["fit_path"] if contract else "",
                "r65_al_fit_sha256": contract["fit_sha256"] if contract else "",
                "legacy_al_validation_AQL": float(source_component.legacy_al_validation_AQL),
                "legacy_exal_validation_AQL": float(source_component.legacy_exal_validation_AQL),
                "r66_al_action": "reuse_hash_valid_r65_al" if contract else "fit_al_from_normal_anchor",
                "r66_exal_action": "fit_fresh_corrected_structured_exal",
                "r65_exal_reuse_authorized": False,
                "selection_role": "whole_bundle_component_not_independent_selection",
                "test_access_authorized": False,
            })

        output_dir = new_case_root / "model"
        config_path = config_dir / f"{row.case_id}.yaml"
        generated = generated_payload(
            source,
            str(row.case_id),
            str(row.region),
            int(row.fold),
            data_config,
            adapter_dir,
            output_dir,
            package,
            args.python_bin,
            code_hashes,
            pd.Series(row._asdict()),
            source_adapter,
            normal_reuse,
            al_by_tau,
        )
        config_path.write_text(yaml.safe_dump(generated, sort_keys=False))
        case_rows.append({
            "case_id": row.case_id,
            "region": row.region,
            "fold": int(row.fold),
            "config": str(config_path),
            "config_sha256": sha256(config_path),
            "adapter_dir": str(adapter_dir.resolve()),
            "adapter_reused_from_r65": source_adapter is not None,
            "normal_anchor_reused_from_r65": normal_reuse is not None,
            "reused_r65_al_components": reused_count,
            "new_al_components_required": 7 - reused_count,
            "new_corrected_exal_components_required": 7,
            "output_dir": str(output_dir.resolve()),
            "scientific_contract_sha256": row.scientific_contract_sha256,
            "feature_semantics_sha256": row.feature_semantics_sha256,
            "legacy_selected_family": row.legacy_selected_family,
            "legacy_selected_validation_AQL": float(row.legacy_selected_validation_AQL),
            "legacy_al_validation_AQL": float(row.legacy_al_validation_AQL),
            "legacy_exal_validation_AQL": float(row.legacy_exal_validation_AQL),
            "selection_split": "val",
            "paper_quantiles": json.dumps(TAUS),
            "package_commit": PACKAGE_COMMIT,
            "production_gate_case": str(row.case_id) == GATE_CASE_ID,
            "launch_authorized": False,
            "test_access_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "joint_model_authorized": False,
            "mcmc_authorized": False,
            "status": "prepared_not_launched",
        })
        source_rows.extend([
            source_row(source_config, "r65_case_config"),
            source_row(data_config, "r66_data_config"),
            source_row(config_path, "r66_case_config"),
        ])
        if source_adapter:
            for name, digest in source_adapter["source_sha256"].items():
                path = Path(source_adapter["path"]) / name
                source_rows.append({
                    "role": "r65_reused_adapter",
                    "path": str(path),
                    "sha256": digest,
                    "bytes": path.stat().st_size,
                })
        if normal_reuse:
            source_rows.extend([
                source_row(Path(normal_reuse["fit_path"]), "r65_reused_normal_fit"),
                source_row(Path(normal_reuse["status_path"]), "r65_reused_normal_status"),
            ])
        for contract in al_by_tau.values():
            if contract:
                source_rows.extend([
                    source_row(Path(contract["fit_path"]), "r65_reused_al_fit"),
                    source_row(Path(contract["status_path"]), "r65_reused_al_status"),
                ])

    cases = pd.DataFrame(case_rows).sort_values(["region", "fold"]).reset_index(drop=True)
    components = pd.DataFrame(component_rows).sort_values(["region", "fold", "tau"]).reset_index(drop=True)
    cases.to_csv(grid / "case_manifest.csv", index=False)
    components.to_csv(grid / "component_ledger.csv", index=False)
    gates = pd.DataFrame([
        {"gate": "r65_frozen_mechanism_failure", "passed": closeout.get("status") == "scientifically_stopped_mechanism_failure", "observed": closeout.get("status")},
        {"gate": "complete_case_surface", "passed": len(cases) == args.expected_cases, "observed": len(cases)},
        {"gate": "complete_quantile_surface", "passed": len(components) == args.expected_cases * 7, "observed": len(components)},
        {"gate": "r65_exal_never_reused", "passed": not components.r65_exal_reuse_authorized.map(boolish).any(), "observed": 0},
        {"gate": "corrected_package_pinned", "passed": package["commit"] == PACKAGE_COMMIT and package["source_sha256"] == PACKAGE_HASHES, "observed": package["commit"]},
        {"gate": "real_gate_case_unique", "passed": int(cases.production_gate_case.map(boolish).sum()) == 1, "observed": int(cases.production_gate_case.map(boolish).sum())},
        {"gate": "train_validation_only", "passed": True, "observed": "train,val"},
        {"gate": "test_registry_article_joint_mcmc_blocked", "passed": (~cases[["test_access_authorized", "registry_mutation_authorized", "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized"]]).all().all(), "observed": "blocked"},
        {"gate": "no_launch_yaml", "passed": all("configs" in path.parts for path in grid.rglob("*.yaml")), "observed": "case/data configs only"},
    ])
    if not gates.passed.all():
        raise RuntimeError(f"R66 preparation gates failed: {gates.loc[~gates.passed].to_dict('records')}")
    gates.to_csv(output / "pricefm_stage_r66_preparation_gates.csv", index=False)

    fixed = [
        args.r65_manifest.resolve(), args.r65_components.resolve(), args.r65_reuse_manifest.resolve(),
        args.r65_closeout_summary.resolve(), Path(__file__).resolve(),
        Path(package["library"]) / "pricefm_r66_install_manifest.json",
        *(code_root / path for path in RUNTIME_CODE_SOURCES),
    ]
    source_rows.extend(source_row(path, "fixed_contract_source") for path in fixed)
    pd.DataFrame(source_rows).drop_duplicates(["path", "sha256"]).sort_values(["role", "path"]).to_csv(
        output / "source_manifest.csv", index=False
    )
    result = {
        "status": "prepared_corrected_r66_not_launched",
        "planned_case_jobs": len(cases),
        "planned_quantile_components": len(components),
        "reused_r65_adapters": int(cases.adapter_reused_from_r65.map(boolish).sum()),
        "reused_r65_normal_anchors": int(cases.normal_anchor_reused_from_r65.map(boolish).sum()),
        "reused_r65_al_components": int(components.reuse_r65_al_authorized.map(boolish).sum()),
        "fresh_al_components": int((~components.reuse_r65_al_authorized.map(boolish)).sum()),
        "fresh_corrected_exal_components": len(components),
        "production_gate_case": GATE_CASE_ID,
        "package_commit": PACKAGE_COMMIT,
        "structured_sigmagam": STRUCTURED_PROFILE,
        "selection_split": "val",
        "selection_unit": "whole_seven_quantile_region_fold_bundle",
        "launch_authorized": False,
        "test_opened": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    write_json(output / "summary.json", result)
    (output / "pricefm_stage_r66_preparation_report.md").write_text(
        "# PriceFM Stage-R66 corrected structured-exAL VB preparation\n\n"
        f"Prepared {len(cases)} case-specific train/validation jobs. R66 reuses "
        f"{result['reused_r65_adapters']} hash-bound adapters, {result['reused_r65_normal_anchors']} normal anchors, "
        f"and {result['reused_r65_al_components']} AL fits, while all {len(components)} exAL components are fresh. "
        f"The real production gate is `{GATE_CASE_ID}`. Test, registry, article, joint-model, and MCMC actions remain blocked.\n"
    )
    return result


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
