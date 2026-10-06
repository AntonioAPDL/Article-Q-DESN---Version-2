#!/usr/bin/env python3
"""Continue R118 from passed probes through the pure-readout quantile forecast."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any, Callable

import joblib
import numpy as np
import pandas as pd


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_common import sha256_file, write_json
from pricefm_r117_engine import (
    QUANTILES, corrected_arrays, fingerprint, load_normal_fit, load_quantile_fit,
    load_windows, normalize_spec, prediction_metrics, recursive_quantile_forecast,
)
from pricefm_r118_engine import audit_atom


SOURCE_TAG = "pricefm_stage_r117_bg_pure_all_layer_recursive_20260925"
TAG = "pricefm_stage_r118_exact_cran_quantile_repair_20260925"
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
WARM_LEVELS = ((0.50,), (0.45, 0.55), (0.25, 0.75), (0.10, 0.90))
WARM_PARENT = {0.50: None, 0.45: 0.50, 0.55: 0.50, 0.25: 0.45, 0.75: 0.55, 0.10: 0.25, 0.90: 0.75}
THREAD_ENV = (
    "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "RCPP_PARALLEL_NUM_THREADS",
    "BLIS_NUM_THREADS",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    value.add_argument("--prep-dir", type=Path)
    value.add_argument("--cpu-list", default="17-31")
    value.add_argument("--posterior-paths", type=int, default=500)
    return value


def parse_cpus(value: str) -> list[int]:
    result = []
    for token in str(value).split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            lower, upper = token.split("-", 1)
            result.extend(range(int(lower), int(upper) + 1))
        else:
            result.append(int(token))
    if not result or len(result) != len(set(result)) or min(result) < 0 or max(result) >= (os.cpu_count() or 0):
        raise ValueError("invalid R118 CPU list")
    return result


def atomic_directory(output: Path, writer: Callable[[Path], None]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.parent / f"{output.name}.tmp.{os.getpid()}"
    if temporary.exists():
        shutil.rmtree(temporary)
    temporary.mkdir()
    try:
        writer(temporary)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def run_command(command: list[str], code: Path, log: Path, cpu: int) -> None:
    log.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.update({name: "1" for name in THREAD_ENV})
    actual = ["taskset", "-c", str(cpu), *command]
    with log.open("a") as handle:
        handle.write("$ {}\n".format(" ".join(actual)))
        handle.flush()
        result = subprocess.run(actual, cwd=str(code), env=env, stdout=handle, stderr=subprocess.STDOUT, check=False)
    if result.returncode:
        raise RuntimeError(f"R118 command failed ({result.returncode}): {' '.join(command)}")


def run_tasks(tasks: list[tuple[str, list[str], Path]], cpus: list[int], code: Path) -> None:
    if not tasks:
        return
    if len(tasks) > len(cpus):
        raise RuntimeError("R118 attempted more simultaneous models than assigned CPUs")
    with ThreadPoolExecutor(max_workers=len(tasks)) as pool:
        futures = {
            pool.submit(run_command, command, code, log, cpus[index]): task_id
            for index, (task_id, command, log) in enumerate(tasks)
        }
        for future in as_completed(futures):
            future.result()


def r117_contract(source: Path, fold: int, family: str, tau: float) -> Path:
    return source / f"full_folds/fold={fold}/quantile_contracts/{family}_tau={tau:.2f}.json"


def r117_atom(source: Path, fold: int, family: str, tau: float) -> Path:
    return source / f"full_folds/fold={fold}/quantiles/{family}/tau={tau:.2f}"


def adoption_inventory(source: Path, family: str) -> tuple[dict[tuple[int, float], Path], pd.DataFrame]:
    adopted: dict[tuple[int, float], Path] = {}
    rows = []
    for fold in (1, 2, 3):
        for tau in QUANTILES:
            atom = r117_atom(source, fold, family, float(tau))
            contract = r117_contract(source, fold, family, float(tau))
            audit = audit_atom(atom, contract)
            row = {"source_stage": "R117", "fold": fold, "family": family, "tau": float(tau), **audit}
            rows.append(row)
            if audit.get("admissible"):
                adopted[(fold, float(tau))] = atom
    return adopted, pd.DataFrame(rows)


def full_target_al_continuation_gate(adoption: pd.DataFrame) -> dict[str, Any]:
    completed = adoption.loc[~adoption.reason.eq("missing_terminal_or_contract")].copy()
    central = completed.loc[completed.tau.isin([0.45, 0.50, 0.55])]
    central_coverage = {
        fold: sorted(central.loc[central.fold.eq(fold), "tau"].tolist())
        for fold in (1, 2, 3)
    }
    authorized = (
        len(completed) >= 9
        and completed.admissible.astype(bool).all()
        and all(values == [0.45, 0.5, 0.55] for values in central_coverage.values())
    )
    return {
        "stage": "R118_production_gate",
        "status": "full_target_al_evidence_audited",
        "authorized": bool(authorized),
        "completed_full_target_al_atoms": int(len(completed)),
        "admissible_full_target_al_atoms": int(completed.admissible.astype(bool).sum()),
        "central_quantile_coverage_by_fold": central_coverage,
        "rationale": (
            "Exact-CRAN full-design fits are direct evidence for the production target; "
            "the row-strided probe changed that target and is retained as a failed mechanism diagnostic."
        ),
        "exal_authorized": False,
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
    }


def runtime_contract(prep: Path) -> dict[str, Any]:
    probe = json.loads((prep / "contracts/al_reference.json").read_text())
    return {
        key: probe[key]
        for key in (
            "cran_library", "cran_manifest", "cran_manifest_sha256",
            "cran_tarball", "cran_tarball_sha256", "cran_adapter", "cran_adapter_sha256",
        )
    }


def family_schedule(prep: Path, family: str, probe_summary: dict[str, Any]) -> dict[str, Any]:
    if family == "al":
        return {
            "arm_id": "al_reference",
            "sigmagam_freeze_warmup_iters": 0,
            "rhs_freeze_tau_warmup_iters": 0,
        }
    selected = probe_summary.get("selected_exal_schedule")
    if not selected:
        raise RuntimeError("exAL continuation requested without a passed schedule")
    value = json.loads((prep / f"contracts/{selected}.json").read_text())
    return {
        "arm_id": selected,
        "sigmagam_freeze_warmup_iters": int(value["sigmagam_freeze_warmup_iters"]),
        "rhs_freeze_tau_warmup_iters": int(value["rhs_freeze_tau_warmup_iters"]),
    }


def quantile_contract(
    prep: Path,
    campaign: Path,
    source: Path,
    family: str,
    fold: int,
    tau: float,
    parent: Path,
    parent_type: str,
    schedule: dict[str, Any],
    runtime: dict[str, Any],
) -> Path:
    winner = json.loads((source / "winner/winner.json").read_text())
    design_dir = source / f"full_folds/fold={fold}/quantile_design"
    output = campaign / f"production/family={family}/fold={fold}/tau={tau:.2f}"
    parent_terminal = parent / "terminal.json"
    target = fingerprint({
        "stage": "R118_production",
        "variant": "pure",
        "fold": fold,
        "family": family,
        "tau": tau,
        "tau0": winner["tau0"],
        "design_terminal_sha256": sha256_file(design_dir / "terminal.json"),
        "prior_sigma": {"a": 1, "b": 1},
        "prior_gamma": None if family == "al" else {"mu0": 0, "s20": 10},
        "beta_prior": "rhs_ns",
    })
    config = {
        "stage": "R118_production", "tag": TAG,
        "atom_id": f"r118_pure_f{fold}_{family}_tau{tau:.2f}",
        "variant": "pure", "fold": fold, "family": family, "tau": tau,
        "tau0": float(winner["tau0"]),
        "design_dir": str(design_dir),
        "design_terminal_sha256": sha256_file(design_dir / "terminal.json"),
        "parent_dir": str(parent), "parent_type": parent_type,
        "parent_label": (
            "normal_rhs" if parent_type == "normal_rhs"
            else f"al_tau_{tau:.2f}" if family == "exal"
            else f"al_tau_{WARM_PARENT.get(tau):.2f}"
        ),
        "parent_terminal_sha256": sha256_file(parent_terminal),
        "output_dir": str(output),
        **runtime,
        "max_iter": 500, "tol": 1e-5, "n_samp_xi": 200, "n_samp": 200,
        "sigmagam_freeze_warmup_iters": int(schedule["sigmagam_freeze_warmup_iters"]),
        "rhs_freeze_tau_warmup_iters": int(schedule["rhs_freeze_tau_warmup_iters"]),
        "structured_grid_size": 151, "structured_span_sd": 6.0,
        "min_postwarmup_updates": 35,
        "seed": 2026092519 + fold * 1000 + int(round(tau * 100)) + (500 if family == "exal" else 0),
        "posterior_target_sha256": target,
        "schedule_sha256": fingerprint(schedule),
        "training_split": "train_only_corrected_teacher_forced",
        "test_access_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    path = prep / f"production_contracts/family={family}/fold={fold}/tau={tau:.2f}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    write_json(path, config)
    return path


def completed_r118_atom(output: Path, contract: Path) -> bool:
    audit = audit_atom(output, contract)
    return bool(audit.get("admissible"))


def fit_al(
    prep: Path, campaign: Path, source: Path, code: Path, cpus: list[int],
    rscript: str, runtime: dict[str, Any], probe_summary: dict[str, Any],
) -> tuple[dict[tuple[int, float], Path], pd.DataFrame]:
    paths, adoption = adoption_inventory(source, "al")
    schedule = family_schedule(prep, "al", probe_summary)
    runner = code / "application/scripts/pricefm/406_fit_pricefm_stage_r118_quantile_atom.R"
    for level in WARM_LEVELS:
        tasks = []
        contracts: dict[tuple[int, float], Path] = {}
        for fold in (1, 2, 3):
            for tau in level:
                key = (fold, float(tau))
                if key in paths:
                    continue
                parent_tau = WARM_PARENT[float(tau)]
                parent = (
                    source / f"full_folds/fold={fold}/normal_rhs"
                    if parent_tau is None else paths[(fold, float(parent_tau))]
                )
                parent_type = "normal_rhs" if parent_tau is None else "quantile"
                contract = quantile_contract(
                    prep, campaign, source, "al", fold, float(tau), parent,
                    parent_type, schedule, runtime,
                )
                output = Path(json.loads(contract.read_text())["output_dir"])
                contracts[key] = contract
                if not completed_r118_atom(output, contract):
                    tasks.append((
                        f"al_f{fold}_tau{tau:.2f}",
                        [rscript, str(runner), "--config", str(contract)],
                        campaign / f"logs/production/al_f{fold}_tau{tau:.2f}.log",
                    ))
        run_tasks(tasks, cpus, code)
        for key, contract in contracts.items():
            output = Path(json.loads(contract.read_text())["output_dir"])
            audit = audit_atom(output, contract)
            if not audit.get("admissible"):
                raise RuntimeError(f"R118 AL atom failed external gate: fold={key[0]} tau={key[1]}")
            paths[key] = output
    return paths, adoption


def fit_exal(
    prep: Path, campaign: Path, source: Path, code: Path, cpus: list[int],
    rscript: str, runtime: dict[str, Any], probe_summary: dict[str, Any],
    al_paths: dict[tuple[int, float], Path],
) -> dict[tuple[int, float], Path]:
    schedule = family_schedule(prep, "exal", probe_summary)
    runner = code / "application/scripts/pricefm/406_fit_pricefm_stage_r118_quantile_atom.R"
    tasks = []
    contracts: dict[tuple[int, float], Path] = {}
    paths: dict[tuple[int, float], Path] = {}
    for fold in (1, 2, 3):
        for tau in QUANTILES:
            key = (fold, float(tau))
            contract = quantile_contract(
                prep, campaign, source, "exal", fold, float(tau), al_paths[key],
                "quantile", schedule, runtime,
            )
            output = Path(json.loads(contract.read_text())["output_dir"])
            contracts[key] = contract
            if completed_r118_atom(output, contract):
                paths[key] = output
            else:
                tasks.append((
                    f"exal_f{fold}_tau{tau:.2f}",
                    [rscript, str(runner), "--config", str(contract)],
                    campaign / f"logs/production/exal_f{fold}_tau{tau:.2f}.log",
                ))
    for start in range(0, len(tasks), len(cpus)):
        run_tasks(tasks[start:start + len(cpus)], cpus, code)
    for key, contract in contracts.items():
        output = Path(json.loads(contract.read_text())["output_dir"])
        audit = audit_atom(output, contract)
        if not audit.get("admissible"):
            raise RuntimeError(f"R118 exAL atom failed external gate: fold={key[0]} tau={key[1]}")
        paths[key] = output
    return paths


def inverse_scale(values: np.ndarray, scaler: Any) -> np.ndarray:
    array = np.asarray(values, dtype=float)
    return scaler.inverse_transform(array.reshape(-1, 1)).reshape(array.shape)


def forecast_fold(
    campaign: Path, source: Path, family: str, fold: int,
    fit_paths: dict[tuple[int, float], Path], paths: int,
) -> dict[str, Any]:
    output = campaign / f"forecasts/family={family}/fold={fold}"
    terminal = output / "terminal.json"
    if terminal.is_file():
        return json.loads(terminal.read_text())
    winner = json.loads((source / "winner/winner.json").read_text())
    spec = normalize_spec(winner["spec"])
    processed = source / "processed"
    arrays = corrected_arrays(load_windows(processed, fold, "val", spec), spec)
    normal = load_normal_fit(source / f"full_folds/fold={fold}/normal_rhs")
    qfits = {tau: load_quantile_fit(fit_paths[(fold, tau)]) for tau in QUANTILES}
    values = recursive_quantile_forecast(
        arrays, spec, normal, qfits, paths=paths,
        seed=2026092520 + fold * 100 + (50 if family == "exal" else 0),
    )
    scaler_path = processed / f"scalers/fold_{fold}/per_region_separate_xy_scalers.joblib"
    scaler = joblib.load(scaler_path)["BG"]["y_scaler"]
    rows = []
    for operator in ("path_specific", "mean_feature", "normal_driver"):
        scaled = prediction_metrics(values["truth"], values[operator])
        original = prediction_metrics(
            inverse_scale(values["truth"], scaler), inverse_scale(values[operator], scaler),
        )
        rows.append({
            "variant": "pure", "fold": fold, "family": family, "operator": operator,
            **{f"scaled_{key}": value for key, value in scaled.items()}, **original,
        })

    def writer(temp: Path) -> None:
        np.savez_compressed(
            temp / "predictions.npz", anchors=arrays.anchors,
            quantiles=np.asarray(QUANTILES), **values,
        )
        pd.DataFrame(rows).to_csv(temp / "metrics.csv", index=False)
        files = [temp / "predictions.npz", temp / "metrics.csv"]
        write_json(temp / "terminal.json", {
            "status": "completed_r118_recursive_forecast", "stage": "R118_production",
            "variant": "pure", "fold": fold, "family": family, "paths": paths,
            "selection_complete_before_outer_validation": True,
            "files": [
                {"path": path.name, "bytes": path.stat().st_size, "sha256": sha256_file(path)}
                for path in files
            ],
            "test_opened": False, "registry_mutated": False, "article_mutated": False,
        })
    atomic_directory(output, writer)
    return json.loads(terminal.read_text())


def family_manifest(
    campaign: Path, prep: Path, family: str,
    paths: dict[tuple[int, float], Path], adoption: pd.DataFrame | None,
) -> pd.DataFrame:
    rows = []
    for fold in (1, 2, 3):
        for tau in QUANTILES:
            path = paths[(fold, tau)]
            if SOURCE_TAG in str(path):
                contract = r117_contract(Path(str(path).split("/full_folds/")[0]), fold, family, tau)
                origin = "adopted_r117"
            else:
                contract = prep / f"production_contracts/family={family}/fold={fold}/tau={tau:.2f}.json"
                origin = "fit_r118"
            audit = audit_atom(path, contract)
            rows.append({"fold": fold, "family": family, "tau": tau, "origin": origin, **audit})
    result = pd.DataFrame(rows)
    if len(result) != 21 or not result.admissible.all():
        raise RuntimeError(f"R118 {family} family manifest is incomplete or ineligible")
    result.to_csv(campaign / f"production/{family}_family_manifest.csv", index=False)
    if adoption is not None:
        adoption.to_csv(campaign / "production/al_r117_adoption_audit.csv", index=False)
    return result


def closeout(campaign: Path, families: list[str], posterior_paths: int) -> dict[str, Any]:
    metrics = pd.concat([
        pd.read_csv(campaign / f"forecasts/family={family}/fold={fold}/metrics.csv")
        for family in families for fold in (1, 2, 3)
    ], ignore_index=True)
    eligible = metrics.loc[
        metrics.fold.eq(1) & metrics.operator.isin(["path_specific", "mean_feature"])
    ].sort_values(["AQL", "late_AQL", "family", "operator"], kind="mergesort")
    selected = eligible.iloc[0]
    frozen = metrics.loc[
        metrics.family.eq(selected.family) & metrics.operator.eq(selected.operator)
    ].copy()
    output = campaign / "closeout"
    output.mkdir(parents=True, exist_ok=True)
    metrics.to_csv(output / "all_metrics.csv", index=False)
    frozen.to_csv(output / "fold1_frozen_choice_metrics.csv", index=False)
    summary = {
        "stage": "R118_production", "status": "completed_pure_bg_not_promoted",
        "families_completed": families,
        "selected_family": str(selected.family), "selected_operator": str(selected.operator),
        "fold1_selection_AQL": float(selected.AQL),
        "three_fold_mean_AQL": float(frozen.AQL.mean()),
        "posterior_paths": int(posterior_paths), "selection_rule": "fold1_only_then_frozen_folds2_3",
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
        "joint_model_fitted": False, "mcmc_fitted": False,
        "extended_variant_authorized": False,
        "next_gate": "read_only_comparison_before_any_extended_or_promotion_work",
    }
    write_json(output / "summary.json", summary)
    write_json(campaign / "campaign_terminal.json", summary)
    return summary


def run(args: argparse.Namespace) -> dict[str, Any]:
    artifact = args.artifact_repo.resolve()
    code = args.code_root.resolve()
    data = artifact / "application/data_local/pricefm"
    prep = (args.prep_dir or data / "launch_prep" / TAG).resolve()
    campaign = data / "campaigns" / TAG
    source = data / "campaigns" / SOURCE_TAG
    probe_summary = json.loads((campaign / "probe_closeout/summary.json").read_text())
    decision = probe_summary.get("decision")
    _, preliminary_adoption = adoption_inventory(source, "al")
    al_gate = full_target_al_continuation_gate(preliminary_adoption)
    al_gate_path = campaign / "probe_closeout/al_full_target_continuation_gate.json"
    write_json(al_gate_path, al_gate)
    authorization_source = "mechanism_probe"
    if decision == "stop_reparameterize_readout" and al_gate["authorized"]:
        decision = "continue_al_only"
        authorization_source = "full_target_existing_al_atoms"
    if decision not in {"continue_al_only", "continue_al_and_exal"}:
        raise RuntimeError(f"R118 has no valid production continuation: {decision}")
    cpus = parse_cpus(args.cpu_list)
    runtime = runtime_contract(prep)
    rscript = json.loads((prep / "launch_control.json").read_text())["rscript"]
    production_sources = [
        code / "application/scripts/pricefm/406_fit_pricefm_stage_r118_quantile_atom.R",
        code / "application/scripts/pricefm/407_continue_pricefm_stage_r118_quantile_repair.py",
        code / "application/scripts/pricefm/pricefm_r118_engine.py",
        code / "application/scripts/pricefm/pricefm_r117_engine.py",
        Path(runtime["cran_adapter"]), Path(runtime["cran_manifest"]), Path(runtime["cran_tarball"]),
        source / "winner/winner.json", campaign / "probe_closeout/summary.json", al_gate_path,
    ]
    production_manifest = {
        "status": "hash_sealed_r118_production_sources",
        "files": [{"path": str(path), "sha256": sha256_file(path)} for path in production_sources],
        "test_opened": False,
    }
    production_manifest_path = prep / "production_source_manifest.json"
    if production_manifest_path.is_file():
        existing = json.loads(production_manifest_path.read_text())
        if existing != production_manifest:
            raise RuntimeError("R118 production source manifest changed after fitting began")
    else:
        write_json(production_manifest_path, production_manifest)
    al_paths, adoption = fit_al(
        prep, campaign, source, code, cpus, rscript, runtime, probe_summary,
    )
    family_manifest(campaign, prep, "al", al_paths, adoption)
    families = ["al"]
    family_paths = {"al": al_paths}
    if decision == "continue_al_and_exal":
        exal_paths = fit_exal(
            prep, campaign, source, code, cpus, rscript, runtime, probe_summary, al_paths,
        )
        family_manifest(campaign, prep, "exal", exal_paths, None)
        families.append("exal")
        family_paths["exal"] = exal_paths
    forecast_tasks = []
    with ThreadPoolExecutor(max_workers=min(len(cpus), len(families) * 3)) as pool:
        for family in families:
            for fold in (1, 2, 3):
                forecast_tasks.append(pool.submit(
                    forecast_fold, campaign, source, family, fold,
                    family_paths[family], int(args.posterior_paths),
                ))
        for future in as_completed(forecast_tasks):
            future.result()
    result = closeout(campaign, families, int(args.posterior_paths))
    result["production_authorization_source"] = authorization_source
    result["mechanism_probe_decision"] = probe_summary.get("decision")
    write_json(campaign / "closeout/summary.json", result)
    write_json(campaign / "campaign_terminal.json", result)
    return result


def main() -> int:
    args = parser().parse_args()
    artifact = args.artifact_repo.resolve()
    campaign = artifact / "application/data_local/pricefm/campaigns" / TAG
    campaign.mkdir(parents=True, exist_ok=True)
    lock = (campaign / "production_controller.lock").open("a+")
    try:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        raise RuntimeError("another R118 production controller owns this campaign") from error
    try:
        result = run(args)
    finally:
        lock.close()
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
