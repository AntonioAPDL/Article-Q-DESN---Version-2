#!/usr/bin/env python3
"""Run the staged BG extended-readout mechanism campaign."""

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

from pricefm_common import sha256_file, write_json  # noqa: E402
from pricefm_r117_engine import (  # noqa: E402
    QUANTILES, corrected_arrays, fingerprint, load_normal_fit, load_quantile_fit,
    load_windows, normalize_spec, prediction_metrics, recursive_quantile_forecast,
)
from pricefm_r118_engine import audit_atom  # noqa: E402


TAG = "pricefm_stage_r119_bg_extended_all_layer_exact_cran_20260925"
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
    value.add_argument("--minimum-free-gib", type=float, default=120.0)
    value.add_argument("--minimum-memory-gib", type=float, default=80.0)
    value.add_argument("--preflight-only", action="store_true")
    return value


def parse_cpus(value: str) -> list[int]:
    result: list[int] = []
    for token in str(value).split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            lower, upper = token.split("-", 1)
            result.extend(range(int(lower), int(upper) + 1))
        else:
            result.append(int(token))
    available = os.cpu_count() or 0
    if (
        not result or len(result) != len(set(result)) or min(result) < 0
        or max(result) >= available
    ):
        raise ValueError("invalid R119 CPU list")
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


def run_command(command: list[str], code_root: Path, log: Path, cpu: int) -> None:
    log.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.update({name: "1" for name in THREAD_ENV})
    actual = ["taskset", "-c", str(cpu), *command]
    with log.open("a") as handle:
        handle.write("$ {}\n".format(" ".join(actual)))
        handle.flush()
        result = subprocess.run(
            actual, cwd=str(code_root), env=env, stdout=handle,
            stderr=subprocess.STDOUT, check=False,
        )
    if result.returncode:
        raise RuntimeError(f"R119 command failed ({result.returncode}): {' '.join(command)}")


def run_tasks(
    tasks: list[tuple[str, list[str], Path]], cpus: list[int], code_root: Path,
) -> None:
    if not tasks:
        return
    for offset in range(0, len(tasks), len(cpus)):
        batch = tasks[offset:offset + len(cpus)]
        with ThreadPoolExecutor(max_workers=len(batch)) as pool:
            futures = {
                pool.submit(run_command, command, code_root, log, cpus[index]): task_id
                for index, (task_id, command, log) in enumerate(batch)
            }
            for future in as_completed(futures):
                future.result()


def load_control(prep: Path) -> dict[str, Any]:
    control_path = prep / "launch_control.json"
    control = json.loads(control_path.read_text())
    required_false = (
        "test_access_authorized", "registry_mutation_authorized",
        "article_mutation_authorized", "joint_model_authorized",
        "mcmc_authorized", "exal_authorized",
    )
    if (
        control.get("stage") != "R119"
        or control.get("status") != "prepared_not_launched"
        or any(control.get(name) is not False for name in required_false)
    ):
        raise RuntimeError("R119 launch control firewall violation")
    for path_key, hash_key in (
        ("frozen_winner", "frozen_winner_sha256"),
        ("decision_contract", "decision_contract_sha256"),
        ("source_manifest", "source_manifest_sha256"),
        ("cran_manifest", "cran_manifest_sha256"),
        ("cran_tarball", "cran_tarball_sha256"),
        ("cran_adapter", "cran_adapter_sha256"),
    ):
        path = Path(control[path_key])
        if not path.is_file() or sha256_file(path) != control[hash_key]:
            raise RuntimeError(f"R119 source hash mismatch: {path}")
    manifest = pd.read_csv(control["source_manifest"])
    for row in manifest.itertuples(index=False):
        path = Path(row.path)
        if not path.is_file() or sha256_file(path) != row.sha256:
            raise RuntimeError(f"R119 frozen source changed: {path}")
    return control


def preflight(
    artifact: Path, campaign: Path, cpus: list[int], minimum_free_gib: float,
    minimum_memory_gib: float,
) -> dict[str, Any]:
    usage = shutil.disk_usage(artifact)
    free_gib = usage.free / (1024 ** 3)
    memory_gib = 0.0
    for line in Path("/proc/meminfo").read_text().splitlines():
        if line.startswith("MemAvailable:"):
            memory_gib = float(line.split()[1]) / (1024 ** 2)
            break
    passed = free_gib >= minimum_free_gib and memory_gib >= minimum_memory_gib
    result = {
        "stage": "R119_preflight", "status": "passed" if passed else "failed",
        "hostname": os.uname().nodename, "cpu_list": cpus,
        "assigned_logical_cpus": len(cpus), "free_disk_gib": free_gib,
        "available_memory_gib": memory_gib, "minimum_free_gib": minimum_free_gib,
        "minimum_memory_gib": minimum_memory_gib, "test_opened": False,
    }
    campaign.mkdir(parents=True, exist_ok=True)
    write_json(campaign / "launch_preflight.json", result)
    if not passed:
        raise RuntimeError("R119 resource preflight failed")
    return result


def install_winner(control: dict[str, Any], campaign: Path) -> dict[str, Any]:
    source = Path(control["frozen_winner"])
    winner = json.loads(source.read_text())
    if (
        winner.get("status") != "frozen_r119_extended_rhs_winner"
        or winner.get("spec", {}).get("readout") != "extended_all_layers"
        or winner.get("outer_validation_used_for_tuning") is not False
        or float(winner.get("tau0", 0)) <= 0
    ):
        raise RuntimeError("R119 frozen winner is invalid")
    destination = campaign / "winner/extended_winner.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_file() and sha256_file(destination) != sha256_file(source):
        raise RuntimeError("R119 campaign winner changed")
    if not destination.is_file():
        shutil.copy2(source, destination)
    return winner


def design_root(campaign: Path, fold: int) -> Path:
    return campaign / f"extended/full_folds/fold={fold}"


def ensure_design(
    fold: int, control: dict[str, Any], campaign: Path, code: Path, cpu: int,
) -> None:
    root = design_root(campaign, fold)
    if (root / "design_terminal.json").is_file():
        return
    command = [
        control["python"],
        str(code / "application/scripts/pricefm/400_run_pricefm_stage_r117_bg_pilot.py"),
        "--mode", "full-design", "--artifact-repo", control["artifact_repo"],
        "--code-root", str(code), "--prep-dir", control["r117_prep"],
        "--campaign-root", str(campaign), "--variant", "extended",
        "--fold", str(fold),
    ]
    run_command(command, code, campaign / f"logs/design/fold={fold}.log", cpu)
    terminal = json.loads((root / "design_terminal.json").read_text())
    design = json.loads((root / "quantile_design/design.json").read_text())
    names = list(design.get("feature_names", []))
    if (
        terminal.get("status") != "completed_r117_full_fold_design"
        or terminal.get("variant") != "extended"
        or not any(str(name).startswith("input::") for name in names)
        or not all(any(str(name).startswith(f"layer{layer}::") for name in names) for layer in (1, 2, 3))
    ):
        raise RuntimeError(f"R119 fold {fold} extended design identity failed")


def normal_contract(
    fold: int, winner: dict[str, Any], control: dict[str, Any], campaign: Path,
    code: Path,
) -> Path:
    root = design_root(campaign, fold)
    stats = root / "normal_stats"
    output = root / "normal_rhs"
    fit_id = f"r119_extended_full_f{fold}"
    value = {
        "fit_id": fit_id, "stats_dir": str(stats), "output_dir": str(output),
        "prior_type": "rhs_ns", "tau0": float(winner["tau0"]),
        "package_path": control["normal_runtime"],
        "helper_path": str(code / "application/R/pricefm_recursive_normal_fit.R"),
        "max_iter": 1000, "min_iter": 100, "tol": 1e-5,
        "convergence_mode": "predictive_fixed_point", "stability_window": 10,
        "predictive_tol": 1e-7, "relative_beta_tol": 1e-6,
        "sigma_relative_tol": 1e-8, "prior_rms_log_precision_tol": 1e-6,
        "posterior_target_sha256": fingerprint({
            "stage": "R119_normal", "fold": fold, "tau0": winner["tau0"],
            "stats": sha256_file(stats / "terminal.json"),
        }),
        # Canonical firewall label required by the frozen R102 Normal runner.
        # The underlying packet is still the corrected teacher-forced training design.
        "selection_split": "train_validation_only",
        "test_access_authorized": False,
    }
    path = campaign / f"contracts/normal/fold={fold}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and json.loads(path.read_text()) != value:
        raise RuntimeError(f"R119 normal contract changed for fold {fold}")
    write_json(path, value)
    return path


def valid_normal(root: Path, contract: Path) -> bool:
    terminal = root / "terminal.json"
    if not terminal.is_file():
        return False
    try:
        value = json.loads(terminal.read_text())
        design = json.loads(contract.read_text())
        return (
            value.get("status") == "completed_recursive_normal_fit"
            and value.get("test_opened") is False
            and value.get("posterior_target_sha256") == design["posterior_target_sha256"]
            and (root / "beta_mean.bin").is_file()
        )
    except (OSError, KeyError, json.JSONDecodeError):
        return False


def ensure_normal(
    fold: int, winner: dict[str, Any], control: dict[str, Any], campaign: Path,
    code: Path, cpu: int,
) -> Path:
    root = design_root(campaign, fold) / "normal_rhs"
    contract = normal_contract(fold, winner, control, campaign, code)
    if not valid_normal(root, contract):
        run_command(
            [control["rscript"], str(code / "application/scripts/pricefm/336_fit_pricefm_stage_r102_recursive_normal.R"), "--contract", str(contract)],
            code, campaign / f"logs/normal/fold={fold}.log", cpu,
        )
    if not valid_normal(root, contract):
        raise RuntimeError(f"R119 normal fit failed for fold {fold}")
    return root


def quantile_contract(
    fold: int, tau: float, parent: Path, parent_type: str,
    winner: dict[str, Any], control: dict[str, Any], campaign: Path,
) -> Path:
    root = design_root(campaign, fold)
    design = root / "quantile_design"
    output = campaign / f"production/family=al/fold={fold}/tau={tau:.2f}"
    parent_tau = WARM_PARENT[float(tau)]
    parent_label = "normal_rhs" if parent_type == "normal_rhs" else f"al_tau_{parent_tau:.2f}"
    target = fingerprint({
        "stage": "R119_production", "variant": "extended", "fold": fold,
        "family": "al", "tau": tau, "tau0": winner["tau0"],
        "design_terminal_sha256": sha256_file(design / "terminal.json"),
        "prior_sigma": {"a": 1, "b": 1}, "beta_prior": "rhs_ns",
    })
    value = {
        "stage": "R119_production", "tag": TAG,
        "atom_id": f"r119_extended_f{fold}_al_tau{tau:.2f}",
        "variant": "extended", "readout": "extended_all_layers",
        "fold": fold, "family": "al", "tau": tau,
        "tau0": float(winner["tau0"]), "design_dir": str(design),
        "design_terminal_sha256": sha256_file(design / "terminal.json"),
        "parent_dir": str(parent), "parent_type": parent_type,
        "parent_label": parent_label,
        "parent_terminal_sha256": sha256_file(parent / "terminal.json"),
        "output_dir": str(output),
        **{key: control[key] for key in (
            "cran_library", "cran_manifest", "cran_manifest_sha256",
            "cran_tarball", "cran_tarball_sha256", "cran_adapter",
            "cran_adapter_sha256",
        )},
        "max_iter": 500, "tol": 1e-5, "n_samp_xi": 200, "n_samp": 200,
        "seed": 2026092529 + fold * 1000 + int(round(tau * 100)),
        "posterior_target_sha256": target,
        "training_split": "train_only_corrected_teacher_forced",
        "test_access_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False, "exal_authorized": False,
    }
    path = campaign / f"contracts/quantile/fold={fold}/tau={tau:.2f}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and json.loads(path.read_text()) != value:
        raise RuntimeError(f"R119 quantile contract changed: fold={fold} tau={tau}")
    write_json(path, value)
    return path


def fit_quantile_folds(
    folds: tuple[int, ...], winner: dict[str, Any], control: dict[str, Any],
    campaign: Path, code: Path, cpus: list[int],
) -> dict[tuple[int, float], Path]:
    paths: dict[tuple[int, float], Path] = {}
    for fold in folds:
        for tau in QUANTILES:
            output = campaign / f"production/family=al/fold={fold}/tau={tau:.2f}"
            contract = campaign / f"contracts/quantile/fold={fold}/tau={tau:.2f}.json"
            if contract.is_file() and audit_atom(output, contract).get("admissible"):
                paths[(fold, float(tau))] = output
    runner = code / "application/scripts/pricefm/410_fit_pricefm_stage_r119_quantile_atom.R"
    for level in WARM_LEVELS:
        tasks: list[tuple[str, list[str], Path]] = []
        contracts: dict[tuple[int, float], Path] = {}
        for fold in folds:
            for tau in level:
                key = (fold, float(tau))
                if key in paths:
                    continue
                parent_tau = WARM_PARENT[float(tau)]
                parent = (
                    design_root(campaign, fold) / "normal_rhs"
                    if parent_tau is None
                    else paths[(fold, float(parent_tau))]
                )
                parent_type = "normal_rhs" if parent_tau is None else "quantile"
                contract = quantile_contract(
                    fold, float(tau), parent, parent_type, winner, control, campaign,
                )
                output = Path(json.loads(contract.read_text())["output_dir"])
                contracts[key] = contract
                if not audit_atom(output, contract).get("admissible"):
                    tasks.append((
                        f"al_f{fold}_tau{tau:.2f}",
                        [control["rscript"], str(runner), "--config", str(contract)],
                        campaign / f"logs/quantile/fold={fold}_tau={tau:.2f}.log",
                    ))
        run_tasks(tasks, cpus, code)
        for key, contract in contracts.items():
            output = Path(json.loads(contract.read_text())["output_dir"])
            audit = audit_atom(output, contract)
            if not audit.get("admissible"):
                raise RuntimeError(f"R119 AL atom failed: fold={key[0]} tau={key[1]}")
            paths[key] = output
    rows = []
    for fold in folds:
        for tau in QUANTILES:
            output = paths[(fold, float(tau))]
            contract = campaign / f"contracts/quantile/fold={fold}/tau={tau:.2f}.json"
            rows.append({"fold": fold, "family": "al", "tau": tau, **audit_atom(output, contract)})
    pd.DataFrame(rows).to_csv(
        campaign / f"production/al_family_manifest_folds_{'_'.join(map(str, folds))}.csv",
        index=False,
    )
    return paths


def inverse_scale(values: np.ndarray, scaler: Any) -> np.ndarray:
    array = np.asarray(values, dtype=float)
    return scaler.inverse_transform(array.reshape(-1, 1)).reshape(array.shape)


def forecast_fold(
    fold: int, fit_paths: dict[tuple[int, float], Path], winner: dict[str, Any],
    control: dict[str, Any], campaign: Path,
) -> dict[str, Any]:
    output = campaign / f"forecasts/family=al/fold={fold}"
    terminal = output / "terminal.json"
    if terminal.is_file():
        return json.loads(terminal.read_text())
    spec = normalize_spec(winner["spec"])
    arrays = corrected_arrays(
        load_windows(Path(control["runtime_processed"]), fold, "val", spec), spec,
    )
    normal = load_normal_fit(design_root(campaign, fold) / "normal_rhs")
    qfits = {tau: load_quantile_fit(fit_paths[(fold, tau)]) for tau in QUANTILES}
    values = recursive_quantile_forecast(
        arrays, spec, normal, qfits, paths=int(control["posterior_paths"]),
        seed=2026092530 + fold * 100,
    )
    scaler_path = Path(control["runtime_processed"]) / f"scalers/fold_{fold}/per_region_separate_xy_scalers.joblib"
    scaler = joblib.load(scaler_path)["BG"]["y_scaler"]
    rows = []
    for operator in ("path_specific", "mean_feature", "normal_driver"):
        scaled = prediction_metrics(values["truth"], values[operator])
        original = prediction_metrics(
            inverse_scale(values["truth"], scaler),
            inverse_scale(values[operator], scaler),
        )
        rows.append({
            "variant": "extended", "fold": fold, "family": "al",
            "operator": operator,
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
            "status": "completed_r119_recursive_forecast", "stage": "R119_production",
            "variant": "extended", "readout": "extended_all_layers",
            "fold": fold, "family": "al", "paths": int(control["posterior_paths"]),
            "files": [
                {"path": path.name, "bytes": path.stat().st_size, "sha256": sha256_file(path)}
                for path in files
            ],
            "test_opened": False, "registry_mutated": False,
            "article_mutated": False, "joint_model_fitted": False,
            "mcmc_fitted": False,
        })

    atomic_directory(output, writer)
    return json.loads(terminal.read_text())


def evaluate_fold1_gate(metrics: pd.DataFrame, decision: dict[str, Any]) -> dict[str, Any]:
    eligible = metrics.loc[
        metrics.fold.eq(1) & metrics.operator.isin(decision["eligible_operators"])
    ].sort_values(["AQL", "late_AQL", "operator"], kind="mergesort")
    if len(eligible) != 2:
        raise RuntimeError("R119 Fold-1 operator surface is incomplete")
    selected = eligible.iloc[0]
    limits = decision["thresholds"]
    checks = {
        "AQL": float(selected.AQL) <= float(limits["maximum_AQL"]),
        "late_AQL": float(selected.late_AQL) <= float(limits["maximum_late_AQL"]),
        "median_MAE": float(selected.median_MAE) <= float(limits["maximum_median_MAE"]),
        "coverage_lower": float(selected.interval_80_coverage) >= float(limits["minimum_interval_80_coverage"]),
        "coverage_upper": float(selected.interval_80_coverage) <= float(limits["maximum_interval_80_coverage"]),
        "width_lower": float(selected.interval_80_width) >= float(limits["minimum_interval_80_width"]),
        "width_upper": float(selected.interval_80_width) <= float(limits["maximum_interval_80_width"]),
        "crossing": float(selected.crossing_rate) <= float(limits["maximum_crossing_rate"]),
    }
    return {
        "stage": "R119_fold1_gate", "status": "passed" if all(checks.values()) else "failed",
        "selected_family": "al", "selected_operator": str(selected.operator),
        "selected_metrics": {
            key: float(selected[key]) for key in (
                "AQL", "late_AQL", "median_MAE", "interval_80_coverage",
                "interval_80_width", "crossing_rate",
            )
        },
        "checks": checks, "thresholds": limits,
        "continue_folds_2_3": bool(all(checks.values())),
        "retuning_authorized": False, "promotion_authorized": False,
        "test_opened": False,
    }


def family_manifest(campaign: Path) -> pd.DataFrame:
    rows = []
    for fold in (1, 2, 3):
        for tau in QUANTILES:
            output = campaign / f"production/family=al/fold={fold}/tau={tau:.2f}"
            contract = campaign / f"contracts/quantile/fold={fold}/tau={tau:.2f}.json"
            rows.append({"fold": fold, "family": "al", "tau": tau, **audit_atom(output, contract)})
    result = pd.DataFrame(rows)
    if len(result) != 21 or not result.admissible.astype(bool).all():
        raise RuntimeError("R119 final AL manifest is incomplete")
    result.to_csv(campaign / "production/al_family_manifest.csv", index=False)
    return result


def closeout(campaign: Path, gate: dict[str, Any], control: dict[str, Any]) -> dict[str, Any]:
    metrics = pd.concat([
        pd.read_csv(campaign / f"forecasts/family=al/fold={fold}/metrics.csv")
        for fold in (1, 2, 3)
    ], ignore_index=True)
    selected_operator = gate["selected_operator"]
    frozen = metrics.loc[metrics.operator.eq(selected_operator)].copy()
    output = campaign / "closeout"
    output.mkdir(parents=True, exist_ok=True)
    metrics.to_csv(output / "all_metrics.csv", index=False)
    frozen.to_csv(output / "fold1_frozen_choice_metrics.csv", index=False)
    summary = {
        "stage": "R119_production", "status": "completed_extended_bg_not_promoted",
        "selected_family": "al", "selected_operator": selected_operator,
        "fold1_selection_AQL": float(frozen.loc[frozen.fold.eq(1), "AQL"].iloc[0]),
        "three_fold_mean_AQL": float(frozen.AQL.mean()),
        "posterior_paths": int(control["posterior_paths"]),
        "selection_rule": "Fold1_mechanism_gate_then_frozen_Folds2_3",
        "quantile_atoms": 21, "exal_atoms": 0,
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
        "joint_model_fitted": False, "mcmc_fitted": False,
        "promotion_authorized": False,
        "next_gate": "read_only_R119_comparison",
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
    control = load_control(prep)
    cpus = parse_cpus(args.cpu_list)
    audit = preflight(
        artifact, campaign, cpus, args.minimum_free_gib, args.minimum_memory_gib,
    )
    if args.preflight_only:
        return audit

    lock_path = campaign / "controller.lock"
    lock_handle = lock_path.open("a+")
    try:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        raise RuntimeError("another R119 controller holds the campaign lock") from error

    winner = install_winner(control, campaign)
    decision = json.loads(Path(control["decision_contract"]).read_text())

    ensure_design(1, control, campaign, code, cpus[0])
    ensure_normal(1, winner, control, campaign, code, cpus[0])
    fold1_paths = fit_quantile_folds((1,), winner, control, campaign, code, cpus)
    forecast_fold(1, fold1_paths, winner, control, campaign)
    fold1_metrics = pd.read_csv(campaign / "forecasts/family=al/fold=1/metrics.csv")
    gate = evaluate_fold1_gate(fold1_metrics, decision)
    write_json(campaign / "fold1_mechanism_gate.json", gate)
    if not gate["continue_folds_2_3"]:
        result = {
            "stage": "R119_production",
            "status": "stopped_after_failed_fold1_mechanism_gate",
            "folds_completed": [1], "quantile_atoms": 7,
            "selected_operator": gate["selected_operator"],
            "fold1_AQL": gate["selected_metrics"]["AQL"],
            "retuning_authorized": False, "promotion_authorized": False,
            "test_opened": False, "registry_mutated": False,
            "article_mutated": False, "joint_model_fitted": False,
            "mcmc_fitted": False,
        }
        write_json(campaign / "campaign_terminal.json", result)
        return result

    design_tasks = []
    for index, fold in enumerate((2, 3)):
        command = [
            control["python"],
            str(code / "application/scripts/pricefm/400_run_pricefm_stage_r117_bg_pilot.py"),
            "--mode", "full-design", "--artifact-repo", control["artifact_repo"],
            "--code-root", str(code), "--prep-dir", control["r117_prep"],
            "--campaign-root", str(campaign), "--variant", "extended",
            "--fold", str(fold),
        ]
        if not (design_root(campaign, fold) / "design_terminal.json").is_file():
            design_tasks.append((f"design_f{fold}", command, campaign / f"logs/design/fold={fold}.log"))
    run_tasks(design_tasks, cpus, code)
    for fold in (2, 3):
        ensure_design(fold, control, campaign, code, cpus[fold - 2])

    normal_tasks = []
    for fold in (2, 3):
        contract = normal_contract(fold, winner, control, campaign, code)
        root = design_root(campaign, fold) / "normal_rhs"
        if not valid_normal(root, contract):
            normal_tasks.append((
                f"normal_f{fold}",
                [control["rscript"], str(code / "application/scripts/pricefm/336_fit_pricefm_stage_r102_recursive_normal.R"), "--contract", str(contract)],
                campaign / f"logs/normal/fold={fold}.log",
            ))
    run_tasks(normal_tasks, cpus, code)
    for fold in (2, 3):
        ensure_normal(fold, winner, control, campaign, code, cpus[fold - 2])

    remaining = fit_quantile_folds((2, 3), winner, control, campaign, code, cpus)
    all_paths = {**fold1_paths, **remaining}
    family_manifest(campaign)
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [
            pool.submit(forecast_fold, fold, all_paths, winner, control, campaign)
            for fold in (2, 3)
        ]
        for future in futures:
            future.result()
    result = closeout(campaign, gate, control)
    subprocess.run([
        control["python"],
        str(code / "application/scripts/pricefm/412_closeout_pricefm_stage_r119_comparison.py"),
        "--artifact-repo", str(artifact), "--campaign-root", str(campaign),
    ], cwd=str(code), check=True)
    return result


def main() -> int:
    args = parser().parse_args()
    result = run(args)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
