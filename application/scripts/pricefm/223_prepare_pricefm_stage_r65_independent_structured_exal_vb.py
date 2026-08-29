#!/usr/bin/env python3
"""Prepare the complete R65 independent structured-exAL VB campaign."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R62 = DATA / "authoritative/pricefm_stage_r62_matched_seven_quantile_authority_20260827"
TAG = "pricefm_stage_r65_independent_structured_exal_vb_20260829"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r65_independent_structured_exal_vb_prep_20260829"
PYTHON = DATA / "venv/bin/python"
PACKAGE = Path("/data/jaguir26/local/src/exdqlm__wt__pricefm_r65_cc85a75")
PACKAGE_LIBRARY = DATA / "runtime_libraries/exdqlm_cc85a75"
PACKAGE_COMMIT = "cc85a75ceca51c6e6a699147c45742591c7e3679"
PACKAGE_HASHES = {
    "R/exal_ldvb_engine.R": "c55e3cb960f8d1d695e4340c496334b4acbf73500399872b0d5a09896493add5",
    "R/exal_inference_config.R": "18f6a140e0dc4e33702528b21db8bf3b264b743fc745f2daf0b276143fb11044",
    "R/exal_sigmagam_structured.R": "4bc6e0d11736ec5e7ef73a267c84aedf7b1de36ad218f81859e0060ec552052f",
}
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
METHOD_AL = "qdesn_al_rhs_ns_exact_chunked_r65_parity"
METHOD_EXAL = "qdesn_exal_rhs_ns_exact_chunked_structured_r65"
LEGACY_AL = "qdesn_al_rhs_ns_exact_chunked"
LEGACY_EXAL = "qdesn_exal_rhs_ns_exact_chunked"
STRUCTURED_PROFILE = {
    "factorization": "structured",
    "structured_grid_size": 151,
    "structured_span_sd": 6.0,
    "freeze_warmup_iters": 10,
    "force_after_warmup": True,
    "postwarmup_damping": 0.6,
    "postwarmup_damping_iters": 5,
    "min_postwarmup_updates": 1,
}
RUNTIME_CODE_SOURCES = (
    "application/scripts/pricefm/07_build_desn_direct_horizon_adapter.py",
    "application/scripts/pricefm/09_summarize_desn_model_smoke.py",
    "application/scripts/pricefm/224_run_pricefm_stage_r65_independent_structured_exal_vb_case.R",
    "application/scripts/pricefm/pricefm_stage_r65_vb_helpers.R",
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, required=True)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--r62-dir", type=Path, default=R62)
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
    observed = {name: sha256(path / name) for name in PACKAGE_HASHES}
    if observed != PACKAGE_HASHES:
        raise RuntimeError(f"Pinned package source hashes differ: {observed}")
    return {"path": str(path), "commit": PACKAGE_COMMIT, "source_sha256": observed}


def verify_runtime_library(path: Path) -> str:
    path = path.resolve()
    manifest_path = path / "pricefm_r65_install_manifest.json"
    if not manifest_path.is_file() or not (path / "exdqlm").is_dir():
        raise RuntimeError(f"R65 package runtime library is not materialized: {path}")
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("source_commit") != PACKAGE_COMMIT or manifest.get("source_sha256") != PACKAGE_HASHES:
        raise RuntimeError("R65 package runtime library does not match its pinned source")
    return str(path)


def prepare_dir(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(f"Output exists: {path}")
    path.mkdir(parents=True, exist_ok=True)


def parse_list(value) -> list[str]:
    if isinstance(value, list):
        return [str(item) for item in value]
    parsed = json.loads(str(value))
    if not isinstance(parsed, list):
        raise TypeError(f"Expected list value, got {type(parsed).__name__}")
    return [str(item) for item in parsed]


def tau_key(value: float) -> str:
    return f"{float(value):.12g}"


def tau_slug(value: float) -> str:
    return tau_key(value).replace("-", "m").replace(".", "p")


def load_smoke(path: Path) -> dict:
    payload = yaml.safe_load(path.read_text())
    if not isinstance(payload, dict) or "pricefm_desn_smoke" not in payload:
        raise ValueError(f"Not a PriceFM DESN config: {path}")
    return payload["pricefm_desn_smoke"]


def resolve_from_repo(path: str | Path, repo: Path) -> Path:
    value = Path(path)
    return value if value.is_absolute() else (repo / value).resolve()


def portable_data_config(source: Path, destination: Path, repo: Path) -> None:
    payload = yaml.safe_load(source.read_text())
    block = payload.get("pricefm", {})
    block["allow_absolute_local_paths"] = True
    for key in ("raw_dir", "interim_dir", "processed_dir", "external_repo_dir", "log_dir"):
        value = block.get(key)
        if value and not Path(value).is_absolute():
            block[key] = str((repo / value).resolve())
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(yaml.safe_dump(payload, sort_keys=False))


def normalized_scientific_payload(smoke: dict) -> dict:
    value = copy.deepcopy(smoke)
    value.pop("data_config", None)
    value.pop("python_bin", None)
    value["quantiles"] = "<single-paper-quantile>"
    value.get("adapter", {}).pop("output_dir", None)
    value.get("run", {}).pop("output_dir", None)
    if "exact_equivalence" in value:
        value["exact_equivalence"]["quantile"] = "<single-paper-quantile>"
    warm = value.get("warm_start", {}).get("qdesn", {})
    if "al" in warm:
        warm["al"]["tau_order"] = "<single-paper-quantile>"
    return value


def component_sources(row: pd.Series, repo: Path) -> dict[float, dict]:
    configs = [resolve_from_repo(path, repo) for path in parse_list(row.config_paths)]
    metrics = [resolve_from_repo(path, repo) for path in parse_list(row.metric_paths)]
    features = [resolve_from_repo(path, repo) for path in parse_list(row.feature_manifest_paths)]
    if not (len(configs) == len(metrics) == len(features) == 7):
        raise RuntimeError(f"Incomplete component bundle for {row.region} fold {row.fold}")
    out = {}
    reference = None
    method = LEGACY_AL if str(row.likelihood_family) == "al" else LEGACY_EXAL
    for config_path, metric_path, feature_path in zip(configs, metrics, features):
        for path in (config_path, metric_path, feature_path):
            if not path.is_file():
                raise FileNotFoundError(path)
        smoke = load_smoke(config_path)
        quantiles = [float(value) for value in smoke["quantiles"]]
        if len(quantiles) != 1:
            raise RuntimeError(f"Legacy component is not one-quantile: {config_path}")
        tau = quantiles[0]
        normalized = normalized_scientific_payload(smoke)
        if reference is None:
            reference = normalized
        elif normalized != reference:
            raise RuntimeError(f"Scientific drift within legacy bundle: {row.region} fold {row.fold}")
        frame = pd.read_csv(metric_path)
        selected = frame[
            frame.method_id.astype(str).eq(method)
            & frame.split.astype(str).eq("val")
            & frame.unit.astype(str).eq("original")
        ]
        if len(selected) != 1:
            raise RuntimeError(f"Missing legacy metric for {config_path} / {method}")
        out[tau] = {
            "config": config_path,
            "metric": metric_path,
            "feature_manifest": feature_path,
            "validation_AQL": float(selected.iloc[0].AQL),
            "smoke": smoke,
        }
    if sorted(out) != list(TAUS):
        raise RuntimeError(f"Wrong paper quantiles for {row.region} fold {row.fold}: {sorted(out)}")
    return out


def generated_config(
    source: dict,
    case_id: str,
    region: str,
    fold: int,
    data_config: Path,
    package: dict,
    python_bin: Path,
    adapter_dir: Path,
    output_dir: Path,
    authority_row: pd.Series,
    code_source_sha256: dict[str, str],
) -> dict:
    smoke = copy.deepcopy(source)
    smoke["data_config"] = str(data_config.resolve())
    smoke["python_bin"] = str(python_bin.absolute())
    smoke["package_path"] = package["path"]
    smoke["region"] = region
    smoke["fold"] = int(fold)
    smoke["splits"] = ["train", "val"]
    smoke["quantiles"] = list(TAUS)
    smoke["adapter"]["output_dir"] = str(adapter_dir.resolve())
    smoke["run"]["output_dir"] = str(output_dir.resolve())
    smoke["qdesn_vb"]["likelihoods"] = ["al", "exal"]
    smoke["qdesn_vb"]["readout_modes"] = ["shared_static"]
    smoke["qdesn_vb"]["sigmagam"] = copy.deepcopy(STRUCTURED_PROFILE)
    smoke.setdefault("exact_equivalence", {})["enabled"] = False
    smoke.setdefault("warm_start", {})["enabled"] = True
    qwarm = smoke["warm_start"].setdefault("qdesn", {})
    qwarm["al"] = {
        "enabled": True,
        "source_each_tau": "shared_normal_rhs_anchor",
        "components": ["beta", "beta_state", "sigma"],
    }
    qwarm["exal"] = {
        "enabled": True,
        "source": "al_same_tau",
        "components": ["beta", "beta_state", "sigma"],
        "gamma_policy": "zero",
    }
    smoke["artifact_hygiene"] = {"enabled": False}
    r65 = {
        "stage": "R65",
        "case_id": case_id,
        "selection_split": "val",
        "selection_metric": "raw_original_seven_quantile_mean_AQL",
        "authority_scientific_contract_sha256": str(authority_row.scientific_contract_sha256),
        "authority_feature_semantics_sha256": str(authority_row.feature_semantics_sha256),
        "package": package,
        "code": {"source_sha256": code_source_sha256},
        "structured_sigmagam": copy.deepcopy(STRUCTURED_PROFILE),
        "method_ids": {"al": METHOD_AL, "exal": METHOD_EXAL},
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    return {"pricefm_desn_smoke": smoke, "pricefm_stage_r65": r65}


def run(args: argparse.Namespace) -> dict:
    code_root = args.code_root.resolve()
    artifact_repo = args.artifact_repo.resolve()
    r62 = args.r62_dir.resolve()
    grid = args.grid_dir.resolve()
    runs = args.run_dir.resolve()
    output = args.output_dir.resolve()
    prepare_dir(grid, args.force)
    prepare_dir(output, args.force)
    runs.mkdir(parents=True, exist_ok=True)
    package = verify_package(args.package_path)
    package["library"] = verify_runtime_library(args.package_library)
    code_source_sha256 = {
        relative_path: sha256(code_root / relative_path)
        for relative_path in RUNTIME_CODE_SOURCES
    }

    authority_path = r62 / "pricefm_stage_r62_matched_seven_quantile_authority.csv"
    ledger_path = r62 / "pricefm_stage_r62_candidate_bundle_ledger.csv"
    summary_path = r62 / "summary.json"
    authority = pd.read_csv(authority_path)
    ledger = pd.read_csv(ledger_path)
    summary = json.loads(summary_path.read_text())
    if len(authority) != args.expected_cases or summary.get("matched_cells") != args.expected_cases:
        raise RuntimeError(f"Expected {args.expected_cases} complete R62 authority cases")
    if summary.get("coverage_gap_cells") != 0 or summary.get("provenance_conflict_cells") != 0:
        raise RuntimeError("R62 authority is not a conflict-free complete surface")

    config_dir = grid / "configs/cases"
    data_dir = grid / "configs/data"
    config_dir.mkdir(parents=True, exist_ok=True)
    data_dir.mkdir(parents=True, exist_ok=True)
    case_rows = []
    component_rows = []
    source_rows = []

    for auth in authority.sort_values(["region", "fold"]).itertuples(index=False):
        selected = ledger[
            ledger.panel_dir.astype(str).eq(str(auth.selected_panel_dir))
            & ledger.base_id.astype(str).eq(str(auth.selected_base_id))
            & ledger.region.astype(str).eq(str(auth.region))
            & ledger.fold.astype(int).eq(int(auth.fold))
        ]
        if set(selected.likelihood_family.astype(str)) != {"al", "exal"} or len(selected) != 2:
            raise RuntimeError(f"R62 selected bundle is not a paired AL/exAL surface: {auth.case_id}")
        al_row = selected[selected.likelihood_family.astype(str).eq("al")].iloc[0]
        exal_row = selected[selected.likelihood_family.astype(str).eq("exal")].iloc[0]
        if not bool(al_row.integrity_pass) or not bool(exal_row.integrity_pass):
            raise RuntimeError(f"R62 component integrity failed for {auth.case_id}")
        al_sources = component_sources(al_row, artifact_repo)
        exal_sources = component_sources(exal_row, artifact_repo)
        for tau in TAUS:
            if al_sources[tau]["config"] != exal_sources[tau]["config"]:
                raise RuntimeError(f"AL/exAL config mismatch for {auth.case_id} at {tau}")

        template = al_sources[0.50]["smoke"]
        source_data = resolve_from_repo(template["data_config"], artifact_repo)
        data_config = data_dir / f"{auth.case_id}.yaml"
        portable_data_config(source_data, data_config, artifact_repo)
        case_root = runs / auth.case_id
        adapter_dir = case_root / "adapter"
        model_dir = case_root / "model"
        config_path = config_dir / f"{auth.case_id}.yaml"
        generated = generated_config(
            template,
            str(auth.case_id),
            str(auth.region),
            int(auth.fold),
            data_config,
            package,
            args.python_bin,
            adapter_dir,
            model_dir,
            pd.Series(auth._asdict()),
            code_source_sha256,
        )
        config_path.write_text(yaml.safe_dump(generated, sort_keys=False))
        case_rows.append({
            "case_id": auth.case_id,
            "region": auth.region,
            "fold": int(auth.fold),
            "config": str(config_path),
            "config_sha256": sha256(config_path),
            "adapter_dir": str(adapter_dir),
            "output_dir": str(model_dir),
            "scientific_contract_sha256": auth.scientific_contract_sha256,
            "feature_semantics_sha256": auth.feature_semantics_sha256,
            "legacy_selected_family": auth.selected_seven_quantile_family,
            "legacy_selected_validation_AQL": float(auth.selected_seven_quantile_validation_AQL),
            "legacy_al_validation_AQL": float(al_row.validation_AQL_recomputed),
            "legacy_exal_validation_AQL": float(exal_row.validation_AQL_recomputed),
            "selection_split": "val",
            "paper_quantiles": json.dumps(TAUS),
            "package_commit": PACKAGE_COMMIT,
            "launch_authorized": False,
            "test_access_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "joint_model_authorized": False,
            "mcmc_authorized": False,
            "status": "prepared_not_launched",
        })
        for tau in TAUS:
            component_dir = model_dir / "components" / f"tau={tau_slug(tau)}"
            component_rows.append({
                "case_id": auth.case_id,
                "region": auth.region,
                "fold": int(auth.fold),
                "tau": tau,
                "config": str(config_path),
                "component_dir": str(component_dir),
                "legacy_component_config": str(al_sources[tau]["config"]),
                "legacy_component_config_sha256": sha256(al_sources[tau]["config"]),
                "legacy_al_metric": str(al_sources[tau]["metric"]),
                "legacy_al_validation_AQL": al_sources[tau]["validation_AQL"],
                "legacy_exal_metric": str(exal_sources[tau]["metric"]),
                "legacy_exal_validation_AQL": exal_sources[tau]["validation_AQL"],
                "expected_al_method_id": METHOD_AL,
                "expected_exal_method_id": METHOD_EXAL,
                "selection_role": "whole_bundle_component_not_independent_selection",
                "test_access_authorized": False,
            })
            for item in (al_sources[tau], exal_sources[tau]):
                for key in ("config", "metric", "feature_manifest"):
                    path = item[key]
                    source_rows.append({"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size})
        for path in (config_path, data_config):
            source_rows.append({"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size})

    cases = pd.DataFrame(case_rows).sort_values(["region", "fold"]).reset_index(drop=True)
    components = pd.DataFrame(component_rows).sort_values(["region", "fold", "tau"]).reset_index(drop=True)
    case_manifest = grid / "case_manifest.csv"
    component_ledger = grid / "component_ledger.csv"
    cases.to_csv(case_manifest, index=False)
    components.to_csv(component_ledger, index=False)

    gates = pd.DataFrame([
        {"gate": "r62_complete_case_surface", "passed": len(cases) == args.expected_cases, "observed": len(cases)},
        {"gate": "seven_components_per_case", "passed": components.groupby("case_id").size().eq(7).all(), "observed": len(components)},
        {"gate": "paper_quantiles_exact", "passed": all(tuple(group.tau) == TAUS for _, group in components.groupby("case_id", sort=False)), "observed": json.dumps(TAUS)},
        {"gate": "unique_region_fold_cases", "passed": not cases.duplicated(["region", "fold"]).any(), "observed": len(cases)},
        {"gate": "case_specific_contracts_retained", "passed": cases.scientific_contract_sha256.notna().all() and cases.feature_semantics_sha256.notna().all(), "observed": cases.scientific_contract_sha256.nunique()},
        {"gate": "pinned_structured_package", "passed": package["commit"] == PACKAGE_COMMIT and package["source_sha256"] == PACKAGE_HASHES, "observed": package["commit"]},
        {"gate": "train_validation_only", "passed": True, "observed": "train,val"},
        {"gate": "test_registry_article_joint_mcmc_blocked", "passed": (~cases[["test_access_authorized", "registry_mutation_authorized", "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized"]]).all().all(), "observed": "blocked"},
        {"gate": "no_launch_yaml", "passed": not any(grid.rglob("*.yaml")) or all("configs" in path.parts for path in grid.rglob("*.yaml")), "observed": "case/data configs only"},
    ])
    if not gates.passed.all():
        raise RuntimeError(f"R65 preparation gates failed: {gates.loc[~gates.passed].to_dict('records')}")
    gates.to_csv(output / "pricefm_stage_r65_preparation_gates.csv", index=False)

    fixed_sources = [
        authority_path,
        ledger_path,
        summary_path,
        Path(__file__).resolve(),
        Path(package["library"]) / "pricefm_r65_install_manifest.json",
        *(code_root / relative_path for relative_path in RUNTIME_CODE_SOURCES),
    ]
    source_rows.extend(
        {"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in fixed_sources
    )
    pd.DataFrame(source_rows).drop_duplicates(["path", "sha256"]).sort_values("path").to_csv(
        output / "source_manifest.csv", index=False
    )
    result = {
        "status": "prepared_complete_independent_structured_exal_vb_not_launched",
        "code_root": str(code_root),
        "artifact_repo": str(artifact_repo),
        "r62_authority_cases": len(cases),
        "planned_case_jobs": len(cases),
        "planned_quantile_components": len(components),
        "new_fit_roles": ["al_parity_control", "structured_exal_candidate"],
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
    (output / "pricefm_stage_r65_preparation_report.md").write_text(
        "# PriceFM Stage-R65 independent structured-exAL VB preparation\n\n"
        f"Prepared {len(cases)} case-grouped train/validation jobs and {len(components)} atomic quantile components. "
        "Each case retains its frozen R62 DESN and information-set contract, fits AL only as a parity/warm-start control, "
        "and fits structured exAL as the new candidate. No production launch YAML was written and test, registry, article, "
        "joint-model, and MCMC actions remain blocked.\n"
    )
    return result


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
