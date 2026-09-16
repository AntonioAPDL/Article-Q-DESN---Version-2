#!/usr/bin/env python3
"""Prepare the post-Search-II Part 1-4 GloFAS execution DAG."""

import argparse
import copy
import csv
import hashlib
import json
import os
import shlex
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from glofas_post_search2_resources import validate_worker_resources


TAUS = ("0.05", "0.20", "0.35", "0.50", "0.65", "0.80", "0.95")
AL_ORDER = ("0.50", "0.35", "0.65", "0.20", "0.80", "0.05", "0.95")
AL_PARENT = {"0.50": None, "0.35": "0.50", "0.65": "0.50", "0.20": "0.35",
             "0.80": "0.65", "0.05": "0.20", "0.95": "0.80"}


def repo_root():
    return Path(__file__).resolve().parents[2]


def resolve(path):
    p = Path(path)
    return p.resolve() if p.is_absolute() else (repo_root() / p).resolve()


def relative(path):
    try:
        return str(path.resolve().relative_to(repo_root()))
    except ValueError:
        return str(path.resolve())


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_output(*args):
    return subprocess.check_output(["git"] + list(args), cwd=str(repo_root()),
                                   universal_newlines=True).strip()


OPERATIONAL_PATH_KEYS = {
    "input_bundle", "input_bundle_manifest", "input_manifest", "data_local",
    "cache", "runs", "logs", "generated_outputs", "quantile_grid", "model_grid",
}


def source_files(args, runtime_configs=()):
    files = list((repo_root() / "application" / "R").glob("*.R"))
    files += [repo_root() / "application" / "scripts" / name for name in (
        "381_run_glofas_dec25_final_refit_job.R",
        "386_run_glofas_part4_latent_family_job.R",
        "403_run_glofas_post_search2_support_job.R",
        "404_prepare_glofas_post_search2_runtime.py",
        "405_launch_glofas_post_search2_dag.py",
        "406_check_glofas_post_search2_dag.py",
        "407_prepare_glofas_post_search2_inputs.R",
        "408_recover_glofas_post_search2_runtime.py",
        "glofas_post_search2_resources.py",
    )]
    files += [
        repo_root() / "application" / "src" / "glofas_external_driver_forecast.cpp",
        resolve(args.input_hash_contract), resolve(args.selected_components),
    ]
    files += list(runtime_configs)
    return sorted(set(path.resolve() for path in files))


def read_yaml(path):
    with path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def write_yaml(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        yaml.safe_dump(value, handle, default_flow_style=False)


def canonical_hash(value):
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def scientific_config_hash(config):
    value = copy.deepcopy(config)
    paths = value.get("paths") or {}
    for key in OPERATIONAL_PATH_KEYS:
        if key in paths:
            paths[key] = f"__OPERATIONAL_PATH__:{key}"
    return canonical_hash(value)


def require_empty_destination(path, label):
    if not path.exists():
        return
    if path.is_dir() and not any(path.iterdir()):
        path.rmdir()
        return
    raise SystemExit(f"{label} already exists and is non-empty: {path}")


def load_hash_contract(path):
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    required = {"input_id", "relative_path", "size_bytes", "sha256", "required", "model_role"}
    if not rows or not required.issubset(rows[0]):
        raise SystemExit(f"invalid input hash contract: {path}")
    ids = [row["input_id"] for row in rows]
    if len(ids) != len(set(ids)):
        raise SystemExit("input hash contract contains duplicate input_id values")
    for row in rows:
        relative_path = Path(row["relative_path"])
        if relative_path.is_absolute() or ".." in relative_path.parts:
            raise SystemExit(
                f"input hash contract contains an unsafe relative path: {row['relative_path']}"
            )
        digest = row["sha256"].lower()
        if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
            raise SystemExit(f"input hash contract contains an invalid SHA256: {row['input_id']}")
        if row["required"].lower() not in {"true", "false"}:
            raise SystemExit(f"input hash contract contains an invalid required flag: {row['input_id']}")
    return rows


def validate_input_source(source_root, contract_rows):
    verified = []
    for row in contract_rows:
        path = source_root / row["relative_path"]
        if not path.is_file():
            raise SystemExit(f"missing authoritative input: {path}")
        expected_size = int(row["size_bytes"])
        actual_size = path.stat().st_size
        actual_hash = sha256(path)
        if actual_size != expected_size:
            raise SystemExit(
                f"authoritative input size mismatch for {row['input_id']}: "
                f"expected {expected_size}, got {actual_size}"
            )
        if actual_hash.lower() != row["sha256"].lower():
            raise SystemExit(f"authoritative input hash mismatch for {row['input_id']}: {path}")
        verified.append({**row, "source_path": str(path.resolve()), "verified_sha256": actual_hash})
    return verified


def copy_input_bundle(source_root, destination, contract_rows):
    if destination.exists():
        raise SystemExit(f"runtime input destination already exists: {destination}")
    destination.mkdir(parents=True)
    for row in contract_rows:
        source = source_root / row["relative_path"]
        target = destination / row["relative_path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    validate_input_source(destination, contract_rows)


def copy_config_asset(config, key, destination_dir):
    value = (config.get("paths") or {}).get(key)
    if not value:
        return
    source = resolve(value)
    if not source.is_file():
        raise SystemExit(f"missing config asset for paths.{key}: {source}")
    destination = destination_dir / f"{key}{source.suffix}"
    shutil.copy2(source, destination)
    config["paths"][key] = str(destination.resolve())


def apply_part4_oracle_covariate_contract(config):
    config = copy.deepcopy(config)
    covariates = config.setdefault("covariates", {})
    covariates["enabled"] = True
    covariates["variables"] = ["ppt", "soil"]
    covariates["source_policy"] = "realized_history_and_oracle_future"
    covariates["future_policy"] = "oracle_realized"
    covariates["allow_realized_future"] = True
    covariates["allow_realized_future_blend"] = False
    covariates["forecast"] = {"provider": "realized_future_oracle", "horizon_days": 28}
    for variable in ("ppt", "soil"):
        settings = covariates.setdefault(variable, {})
        settings["forecast_noise"] = {"enabled": False}
        settings["noisy_blend"] = {"enabled": False}
        settings["realized_future_correction"] = {"enabled": False, "observed_weight": 0}
        settings["observed_blend"] = {"enabled": False, "observed_weight": 0}
    return config


def freeze_runtime_config(source_path, destination, runtime, input_bundle_path,
                          input_manifest_path, bundle_manifest_path, copy_grid_assets,
                          config_transform=None):
    original = read_yaml(source_path)
    frozen = config_transform(original) if config_transform else copy.deepcopy(original)
    frozen.setdefault("paths", {})
    frozen["paths"].update({
        "input_bundle": str(input_bundle_path.resolve()),
        "input_bundle_manifest": str(bundle_manifest_path.resolve()),
        "input_manifest": str(input_manifest_path.resolve()),
        "data_local": str((runtime / "inputs").resolve()),
        "cache": str((runtime / "cache").resolve()),
        "runs": str((runtime / "runs").resolve()),
        "logs": str((runtime / "application_logs").resolve()),
        "generated_outputs": str((runtime / "generated").resolve()),
    })
    if copy_grid_assets:
        asset_dir = runtime / "configs" / "part123_base_assets"
        asset_dir.mkdir(parents=True, exist_ok=True)
        for key in ("quantile_grid", "model_grid"):
            copy_config_asset(frozen, key, asset_dir)
    write_yaml(destination, frozen)
    original_effective = config_transform(original) if config_transform else original
    original_hash = scientific_config_hash(original_effective)
    frozen_hash = scientific_config_hash(frozen)
    if original_hash != frozen_hash:
        raise SystemExit(f"scientific config changed while freezing {source_path}")
    return {
        "original_path": str(source_path.resolve()),
        "original_sha256": sha256(source_path),
        "frozen_path": str(destination.resolve()),
        "frozen_sha256": sha256(destination),
        "scientific_config_sha256": original_hash,
        "scientific_transform": "part4_oracle_covariate_contract" if config_transform else "none",
    }


def engine_contract(base_config):
    dependencies = base_config.get("dependencies") or {}
    engine = Path(dependencies.get("qdesn_engine_repo_hint", "")).resolve()
    expected = dependencies.get("qdesn_engine_required_commit", "")
    if not engine.is_dir() or not expected:
        raise SystemExit("base config does not declare a usable pinned exdqlm engine")
    head = subprocess.check_output(
        ["git", "-C", str(engine), "rev-parse", "HEAD"], universal_newlines=True
    ).strip()
    dirty = subprocess.check_output(
        ["git", "-C", str(engine), "status", "--porcelain", "--untracked-files=no"],
        universal_newlines=True,
    ).strip()
    if head != expected:
        raise SystemExit(f"pinned exdqlm HEAD mismatch: expected {expected}, got {head}")
    if dirty:
        raise SystemExit(f"pinned exdqlm tracked worktree is dirty: {engine}")
    return {"path": str(engine), "head": head, "expected_head": expected, "tracked_clean": True}


def write_launch_readiness(runtime, artifacts, engine, input_readiness_path):
    rows = []
    for path in artifacts:
        path = Path(path).resolve()
        if not path.is_file():
            raise SystemExit(f"launch-readiness artifact is missing: {path}")
        rows.append({"path": relative(path), "size_bytes": path.stat().st_size, "sha256": sha256(path)})
    payload = {
        "schema_version": "glofas_post_search2_launch_readiness_v2",
        "status": "ready",
        "prepared_utc": datetime.now(timezone.utc).isoformat(),
        "git_head": git_output("rev-parse", "HEAD"),
        "git_branch": git_output("rev-parse", "--abbrev-ref", "HEAD"),
        "engine": engine,
        "input_readiness_path": relative(input_readiness_path),
        "input_readiness_sha256": sha256(input_readiness_path),
        "artifacts": rows,
    }
    path = runtime / "configs" / "launch_readiness.json"
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def qslug(tau):
    return "q" + tau.replace(".", "p")


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = list(rows[0])
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def add(rows, job_id, part, stage, command,
        dependencies=(), model_family="", tau="", role=""):
    rows.append({
        "job_id": job_id,
        "part": part,
        "stage": stage,
        "model_family": model_family,
        "tau": tau,
        "dependencies": "|".join(dependencies),
        "worker_slots": 1,
        "role": role,
        "command_json": json.dumps(command),
    })


def common_support(args, runtime, job_id, job_type):
    return [
        "Rscript", "application/scripts/403_run_glofas_post_search2_support_job.R",
        "--runtime_root", relative(runtime), "--job_id", job_id, "--job_type", job_type,
        "--base_config", args.base_config,
        "--selected_components", args.selected_components,
        "--calibration_path", relative(runtime / "configs" / "full_data_rhs_calibration.csv"),
        "--part2_runtime_root", relative(runtime), "--part3_runtime_root", relative(runtime),
        "--part4_runtime_root", relative(resolve(args.part4_runtime_root)),
        "--part4_base_config", args.part4_base_config, "--part4_run_label", args.part4_run_label,
        "--max_iter", str(args.max_iter), "--min_iter", str(args.min_iter),
        "--tol", str(args.tol), "--n_draws", str(args.n_draws),
        "--seed", str(args.seed), "--forecast_backend", args.forecast_backend,
        "--freeze_beta_warmup_iters", str(args.freeze_beta_warmup_iters),
        "--min_beta_updates", str(args.min_beta_updates),
    ]


def bridge_command(args, runtime, part, job_id, job_type,
                   model_family="", tau="", fit_job_id="", init_ids="", method=""):
    return [
        "Rscript", "application/scripts/381_run_glofas_dec25_final_refit_job.R",
        "--runtime_root", relative(runtime), "--part", part, "--job_id", job_id,
        "--job_type", job_type, "--model_family", model_family, "--tau", tau,
        "--fit_job_id", fit_job_id, "--init_fit_job_ids", init_ids,
        "--method", method, "--base_config", args.base_config,
        "--selected_components", args.selected_components,
        "--calibration_path", relative(runtime / "configs" / "full_data_rhs_calibration.csv"),
        "--normal_driver_bank_path", relative(runtime / "objects" / f"{part}_normal_rhs_driver_bank.rds"),
        "--origin_date", "2022-12-25", "--horizon_days", "30",
        "--max_iter", str(args.max_iter), "--min_iter", str(args.min_iter),
        "--tol", str(args.tol), "--normal_draws", str(args.n_draws),
        "--seed", str(args.seed), "--forecast_backend", args.forecast_backend,
        "--freeze_beta_warmup_iters", str(args.freeze_beta_warmup_iters),
        "--min_beta_updates", str(args.min_beta_updates),
    ]


def support_command(args, runtime, job_id, job_type, **values):
    cmd = common_support(args, runtime, job_id, job_type)
    for name, value in values.items():
        cmd.extend(["--" + name, str(value)])
    return cmd


def build_part123(args, runtime):
    rows = []
    add(rows, "part1_design", "part1", "design", support_command(args, runtime, "part1_design", "part1_design"), role="selected_reference_design")
    for part in ("part2", "part3"):
        jid = f"{part}_design"
        add(rows, jid, part, "design", bridge_command(args, runtime, part, jid, "design_cache"), role="selected_component_design")

    add(rows, "part1_fit_normal_ridge", "part1", "fit",
        support_command(args, runtime, "part1_fit_normal_ridge", "part1_fit", model_family="normal_ridge"),
        ("part1_design",), "normal_ridge", role="full_data_ridge")
    add(rows, "part2_fit_normal_ridge", "part2", "fit",
        bridge_command(args, runtime, "part2", "part2_fit_normal_ridge", "fit", model_family="normal_ridge"),
        ("part2_design",), "normal_ridge", role="full_data_ridge")
    add(rows, "full_data_rhs_calibration", "shared", "calibration",
        support_command(args, runtime, "full_data_rhs_calibration", "calibration"),
        ("part1_fit_normal_ridge", "part2_fit_normal_ridge"), role="full_data_tau0_calibration")

    add(rows, "part1_fit_normal_rhs_vb", "part1", "fit",
        support_command(args, runtime, "part1_fit_normal_rhs_vb", "part1_fit", model_family="normal_rhs_vb"),
        ("part1_fit_normal_ridge", "full_data_rhs_calibration"), "normal_rhs_vb", role="full_data_rhs")
    add(rows, "part2_fit_normal_rhs_vb", "part2", "fit",
        bridge_command(args, runtime, "part2", "part2_fit_normal_rhs_vb", "fit", model_family="normal_rhs_vb"),
        ("part2_fit_normal_ridge", "full_data_rhs_calibration"), "normal_rhs_vb", role="full_data_rhs")

    add(rows, "part3_fit_normal_ridge", "part3", "fit",
        bridge_command(args, runtime, "part3", "part3_fit_normal_ridge", "fit", model_family="normal_ridge"),
        ("part3_design",), "normal_ridge", role="full_data_joint_ridge")
    add(rows, "part3_fit_normal_rhs_vb", "part3", "fit",
        bridge_command(args, runtime, "part3", "part3_fit_normal_rhs_vb", "fit", model_family="normal_rhs_vb"),
        ("part3_fit_normal_ridge", "full_data_rhs_calibration"), "normal_rhs_vb", role="full_data_joint_rhs")

    for part in ("part1", "part2", "part3"):
        for method in ("normal_ridge", "normal_rhs_vb"):
            jid = f"{part}_forecast_{method}"
            fit_id = f"{part}_fit_{method}"
            if part == "part1":
                cmd = support_command(args, runtime, jid, "part1_forecast", model_family=method,
                                      fit_job_id=fit_id,
                                      normal_driver_bank_path=relative(runtime / "objects" / "part1_normal_rhs_driver_bank.rds"))
            else:
                cmd = bridge_command(args, runtime, part, jid, "forecast", model_family=method,
                                     fit_job_id=fit_id, method="ridge" if method == "normal_ridge" else "rhs")
            add(rows, jid, part, "forecast", cmd, (fit_id,), method, role="recursive_normal_forecast")

    for part in ("part1", "part2", "part3"):
        bank_job = f"{part}_forecast_normal_rhs_vb"
        worker = "support" if part == "part1" else "bridge"
        al_ids = []
        exal_ids = []
        for tau in AL_ORDER:
            slug = qslug(tau)
            jid = f"{part}_fit_independent_al_{slug}"
            parent_tau = AL_PARENT[tau]
            parent = f"{part}_fit_normal_rhs_vb" if parent_tau is None else f"{part}_fit_independent_al_{qslug(parent_tau)}"
            if worker == "support":
                cmd = support_command(args, runtime, jid, "part1_fit", model_family="independent_al",
                                      tau=tau, likelihood="AL", fit_structure="independent",
                                      init_fit_job_ids=parent)
            else:
                cmd = bridge_command(args, runtime, part, jid, "fit", "independent_al", tau,
                                     init_ids=parent)
                cmd.extend(["--likelihood", "AL", "--fit_structure", "independent"])
            add(rows, jid, part, "fit", cmd, (parent,), "independent_al", tau, "independent_al_rhs_vb")
            al_ids.append(jid)
            fjid = f"{part}_forecast_independent_al_{slug}"
            if worker == "support":
                fcmd = support_command(args, runtime, fjid, "part1_forecast", model_family="independent_al",
                                       tau=tau, fit_job_id=jid,
                                       normal_driver_bank_path=relative(runtime / "objects" / f"{part}_normal_rhs_driver_bank.rds"))
            else:
                fcmd = bridge_command(args, runtime, part, fjid, "forecast", "independent_al", tau, fit_job_id=jid)
            add(rows, fjid, part, "forecast", fcmd, (jid, bank_job), "independent_al", tau, "external_normal_driver_forecast")

        for tau in TAUS:
            slug = qslug(tau)
            al_id = f"{part}_fit_independent_al_{slug}"
            jid = f"{part}_fit_independent_exal_{slug}"
            if worker == "support":
                cmd = support_command(args, runtime, jid, "part1_fit", model_family="independent_exal",
                                      tau=tau, likelihood="exAL", fit_structure="independent",
                                      init_fit_job_ids=al_id)
            else:
                cmd = bridge_command(args, runtime, part, jid, "fit", "independent_exal", tau, init_ids=al_id)
                cmd.extend(["--likelihood", "exAL", "--fit_structure", "independent"])
            add(rows, jid, part, "fit", cmd, (al_id,), "independent_exal", tau, "independent_exal_rhs_vb")
            exal_ids.append(jid)
            fjid = f"{part}_forecast_independent_exal_{slug}"
            if worker == "support":
                fcmd = support_command(args, runtime, fjid, "part1_forecast", model_family="independent_exal",
                                       tau=tau, fit_job_id=jid,
                                       normal_driver_bank_path=relative(runtime / "objects" / f"{part}_normal_rhs_driver_bank.rds"))
            else:
                fcmd = bridge_command(args, runtime, part, fjid, "forecast", "independent_exal", tau, fit_job_id=jid)
            add(rows, fjid, part, "forecast", fcmd, (jid, bank_job), "independent_exal", tau, "external_normal_driver_forecast")

        for family, likelihood, dependencies in (("joint_al", "AL", al_ids), ("joint_exal", "exAL", exal_ids)):
            jid = f"{part}_fit_{family}_all7"
            init_ids = "|".join(dependencies)
            if worker == "support":
                cmd = support_command(args, runtime, jid, "part1_fit", model_family=family,
                                      tau="all7", likelihood=likelihood, fit_structure="joint",
                                      init_fit_job_ids=init_ids)
            else:
                cmd = bridge_command(args, runtime, part, jid, "fit", family, "all7", init_ids=init_ids)
                cmd.extend(["--likelihood", likelihood, "--fit_structure", "joint"])
            add(rows, jid, part, "fit", cmd, tuple(dependencies), family, "all7", f"{family}_rhs_vb")
            fjid = f"{part}_forecast_{family}_all7"
            if worker == "support":
                fcmd = support_command(args, runtime, fjid, "part1_forecast", model_family=family,
                                       tau="all7", fit_job_id=jid,
                                       normal_driver_bank_path=relative(runtime / "objects" / f"{part}_normal_rhs_driver_bank.rds"))
            else:
                fcmd = bridge_command(args, runtime, part, fjid, "forecast", family, "all7", fit_job_id=jid)
            add(rows, fjid, part, "forecast", fcmd, (jid, bank_job), family, "all7", "external_normal_driver_forecast")
    return rows


def build_part4(args, runtime, rows):
    anchor = "post_search2_anchor_manifest"
    add(rows, anchor, "part4", "prepare", support_command(args, runtime, anchor, "anchor_manifest"),
        ("part1_fit_normal_rhs_vb", "part2_fit_normal_rhs_vb"), role="frozen_selected_anchors")
    prior = "part4_normal_driver_prior"
    add(rows, prior, "part4", "prepare",
        support_command(args, runtime, prior, "part4_prior",
                        normal_driver_bank_path=relative(runtime / "objects" / "part3_normal_rhs_driver_bank.rds")),
        ("part3_forecast_normal_rhs_vb",), role="truth_free_28_day_joint_gaussian_prior")
    prepared = "part4_prepare_runtime"
    add(rows, prepared, "part4", "prepare", support_command(args, runtime, prepared, "part4_prepare"),
        (anchor, prior), role="part4_manifest_and_configs")

    families = [("normal_ridge_diagnostic", None), ("normal_rhs_vb_diagnostic", None)]
    families += [("independent_al_rhs_vb", tau) for tau in AL_ORDER]
    families += [("independent_exal_rhs_vb", tau) for tau in TAUS]
    families += [("joint_al_rhs_vb", None), ("joint_exal_rhs_vb", None)]
    run_label = args.part4_run_label
    part4_root = relative(resolve(args.part4_runtime_root))

    def internal_id(family, tau):
        return f"{run_label}_{family}" + (f"_p{int(round(float(tau) * 100)):02d}" if tau else "")

    def internal_dependencies(family, tau):
        if family == "normal_ridge_diagnostic": return []
        if family == "normal_rhs_vb_diagnostic": return [internal_id("normal_ridge_diagnostic", None)]
        if family == "independent_al_rhs_vb":
            parent = AL_PARENT[tau]
            return [internal_id("normal_rhs_vb_diagnostic", None) if parent is None else internal_id(family, parent)]
        if family == "independent_exal_rhs_vb": return [internal_id("independent_al_rhs_vb", tau)]
        if family == "joint_al_rhs_vb": return [internal_id("independent_al_rhs_vb", q) for q in TAUS]
        if family == "joint_exal_rhs_vb": return [internal_id("independent_exal_rhs_vb", q) for q in TAUS]
        raise ValueError(family)

    all_internal = {internal_id(f, q): (f, q) for f, q in families}
    for family, tau in families:
        iid = internal_id(family, tau)
        jid = "part4__" + iid
        deps = [prepared] + ["part4__" + dep for dep in internal_dependencies(family, tau)]
        command = ["Rscript", "application/scripts/386_run_glofas_part4_latent_family_job.R",
                   "--runtime_root", part4_root, "--job_id", iid]
        add(rows, jid, "part4", "fit", command, tuple(dict.fromkeys(deps)), family, tau or "all7", "part4_latent_family_fit")
    assert len(all_internal) == 18


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", default="local_trackers/runtime_configs/glofas_post_search2_part14_20260916")
    parser.add_argument("--part4-runtime-root", default="local_trackers/runtime_configs/glofas_part4_post_search2_normal_driver_20260916")
    parser.add_argument("--part4-run-label", default="glofas_part4_post_search2_normal_driver_20260916")
    parser.add_argument("--base-config", required=True)
    parser.add_argument("--part4-base-config", default="application/config/glofas_latent_path_al_vb_dec25_main.yaml")
    parser.add_argument("--selected-components", required=True)
    parser.add_argument("--authoritative-input-root", required=True)
    parser.add_argument("--input-bundle-config", default="application/config/input_bundle_authoritative_dec25.yaml")
    parser.add_argument("--input-hash-contract", default="application/config/glofas_dec25_input_hash_contract.csv")
    parser.add_argument("--session-prefix", default="glofas_post_search2_20260916_r7")
    parser.add_argument("--workers", type=int, default=25)
    parser.add_argument("--cpu-pool", default="0-24")
    parser.add_argument("--max-iter", type=int, default=100)
    parser.add_argument("--min-iter", type=int, default=30)
    parser.add_argument("--tol", type=float, default=0.01)
    parser.add_argument("--n-draws", type=int, default=500)
    parser.add_argument("--seed", type=int, default=20260916)
    parser.add_argument("--forecast-backend", choices=("auto", "cpp", "r"), default="cpp")
    parser.add_argument("--freeze-beta-warmup-iters", type=int, default=20)
    parser.add_argument("--min-beta-updates", type=int, default=30)
    args = parser.parse_args()
    if args.n_draws != 500:
        raise SystemExit("The adopted recursive forecast contract requires exactly 500 paths.")
    if args.max_iter < args.min_iter or args.min_iter < 30 or args.freeze_beta_warmup_iters < 0:
        raise SystemExit("Invalid VB iteration controls.")
    try:
        resource_contract = validate_worker_resources(args.workers, args.cpu_pool)
    except ValueError as exc:
        raise SystemExit(f"invalid worker resource contract: {exc}")
    original_base_config = resolve(args.base_config)
    original_part4_config = resolve(args.part4_base_config)
    selected_components = resolve(args.selected_components)
    input_bundle_config = resolve(args.input_bundle_config)
    input_hash_contract = resolve(args.input_hash_contract)
    authoritative_input_root = resolve(args.authoritative_input_root)
    for source in (
        original_base_config, original_part4_config, selected_components,
        input_bundle_config, input_hash_contract,
    ):
        if not source.exists(): raise SystemExit(f"missing required input: {source}")
    if not authoritative_input_root.is_dir():
        raise SystemExit(f"missing authoritative input root: {authoritative_input_root}")
    dirty = git_output("status", "--porcelain", "--untracked-files=no")
    if dirty:
        raise SystemExit("tracked worktree must be clean before production preparation")
    runtime = resolve(args.runtime_root)
    part4_runtime = resolve(args.part4_runtime_root)
    require_empty_destination(runtime, "post-Search-II runtime")
    require_empty_destination(part4_runtime, "Part 4 runtime")
    for sub in ("configs", "objects", "forecasts", "scores", "traces", "coefficients", "tables", "logs", "status", "figures", "scripts", "docs"):
        (runtime / sub).mkdir(parents=True, exist_ok=True)

    contract_rows = load_hash_contract(input_hash_contract)
    verified_inputs = validate_input_source(authoritative_input_root, contract_rows)
    runtime_input_root = runtime / "inputs" / "authoritative_dec25"
    copy_input_bundle(authoritative_input_root, runtime_input_root, contract_rows)
    write_csv(runtime / "configs" / "input_source_verification.csv", verified_inputs)

    runtime_input_manifest = runtime / "configs" / "input_manifest.csv"
    runtime_bundle_manifest = runtime / "configs" / "input_bundle_manifest.csv"
    runtime_bundle_config = runtime / "configs" / "input_bundle_runtime.yaml"
    bundle_cfg = read_yaml(input_bundle_config)
    bundle_cfg["bundle_root"] = str(runtime_input_root.resolve())
    bundle_cfg["copy_files"] = False
    bundle_cfg["manifest_output"] = str(runtime_input_manifest.resolve())
    bundle_cfg["bundle_manifest_output"] = str(runtime_bundle_manifest.resolve())
    for input_id in (bundle_cfg.get("inputs") or {}):
        if input_id in {row["input_id"] for row in contract_rows}:
            bundle_cfg["inputs"][input_id]["required"] = True
    write_yaml(runtime_bundle_config, bundle_cfg)

    part123_runtime_config = runtime / "configs" / "part123_base_config_frozen.yaml"
    part4_runtime_config = runtime / "configs" / "part4_base_config_frozen.yaml"
    part123_config_contract = freeze_runtime_config(
        original_base_config, part123_runtime_config, runtime,
        runtime_bundle_config, runtime_input_manifest, runtime_bundle_manifest,
        copy_grid_assets=True,
    )
    part4_config_contract = freeze_runtime_config(
        original_part4_config, part4_runtime_config, part4_runtime,
        runtime_bundle_config, runtime_input_manifest, runtime_bundle_manifest,
        copy_grid_assets=False,
        config_transform=apply_part4_oracle_covariate_contract,
    )

    input_audit = runtime / "configs" / "input_semantic_audit.csv"
    input_readiness = runtime / "configs" / "input_readiness.json"
    subprocess.run([
        "Rscript", "application/scripts/407_prepare_glofas_post_search2_inputs.R",
        "--config", relative(part4_runtime_config),
        "--hash_contract", relative(input_hash_contract),
        "--audit_output", relative(input_audit),
        "--readiness_output", relative(input_readiness),
    ], cwd=str(repo_root()), check=True)
    input_readiness_payload = json.loads(input_readiness.read_text(encoding="utf-8"))
    if input_readiness_payload.get("status") != "ready":
        raise SystemExit("runtime input readiness did not reach ready")

    engine = engine_contract(read_yaml(original_base_config))
    args.base_config = relative(part123_runtime_config)
    args.part4_base_config = relative(part4_runtime_config)
    rows = build_part123(args, runtime)
    build_part4(args, runtime, rows)
    ids = [row["job_id"] for row in rows]
    if len(ids) != len(set(ids)):
        raise SystemExit("duplicate job IDs in post-Search-II DAG")
    known = set(ids)
    for row in rows:
        missing = set(filter(None, row["dependencies"].split("|"))) - known
        if missing: raise SystemExit(f"unknown dependencies for {row['job_id']}: {sorted(missing)}")
    manifest = runtime / "tables" / "post_search2_job_manifest.csv"
    write_csv(manifest, rows)
    runtime_config_files = [
        original_base_config, original_part4_config, input_bundle_config,
        part123_runtime_config, part4_runtime_config, runtime_bundle_config,
        runtime_input_manifest, runtime_bundle_manifest, input_audit, input_readiness,
        runtime / "configs" / "input_source_verification.csv",
    ] + sorted((runtime / "configs" / "part123_base_assets").glob("*"))
    frozen_sources = source_files(args, runtime_config_files)
    missing_sources = [str(path) for path in frozen_sources if not path.is_file()]
    if missing_sources: raise SystemExit("missing frozen sources: " + ", ".join(missing_sources))
    source_manifest = runtime / "configs" / "post_search2_source_manifest.csv"
    write_csv(source_manifest, [{
        "path": relative(path), "size_bytes": path.stat().st_size, "sha256": sha256(path)
    } for path in frozen_sources])
    metadata = {
        "schema_version": "glofas_post_search2_execution_dag_v3",
        "prepared_utc": datetime.now(timezone.utc).isoformat(),
        "runtime_root": relative(runtime),
        "part4_runtime_root": relative(part4_runtime),
        "selection_path": relative(selected_components),
        "selection_sha256": sha256(selected_components),
        "git_head": git_output("rev-parse", "HEAD"),
        "git_branch": git_output("rev-parse", "--abbrev-ref", "HEAD"),
        "source_manifest": relative(source_manifest),
        "source_manifest_sha256": sha256(source_manifest),
        "source_file_count": len(frozen_sources),
        "input_root": relative(runtime_input_root),
        "input_hash_contract": relative(input_hash_contract),
        "input_hash_contract_sha256": sha256(input_hash_contract),
        "input_manifest": relative(runtime_input_manifest),
        "input_manifest_sha256": sha256(runtime_input_manifest),
        "input_bundle_manifest": relative(runtime_bundle_manifest),
        "input_bundle_manifest_sha256": sha256(runtime_bundle_manifest),
        "input_readiness": relative(input_readiness),
        "input_readiness_sha256": sha256(input_readiness),
        "part123_config_contract": part123_config_contract,
        "part4_config_contract": part4_config_contract,
        "engine_contract": engine,
        "resource_contract": resource_contract,
        "cutoff": "2022-12-25",
        "part123_forecast_window": ["2022-12-26", "2023-01-24"],
        "part4_issued_window_days": 28,
        "n_driver_paths": args.n_draws,
        "job_count": len(rows),
        "jobs_by_part": {part: sum(row["part"] == part for row in rows) for part in ("part1", "part2", "part3", "part4", "shared")},
        "preparation_state": "ready",
    }
    execution_contract = runtime / "configs" / "post_search2_execution_contract.json"
    execution_contract.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    launch_readiness = write_launch_readiness(
        runtime,
        [
            execution_contract, manifest, source_manifest, selected_components,
            input_hash_contract, runtime_input_manifest, runtime_bundle_manifest,
            input_audit, input_readiness, part123_runtime_config,
            part4_runtime_config, runtime_bundle_config,
        ],
        engine,
        input_readiness,
    )
    launch = runtime / "scripts" / "launch.sh"
    launch.write_text(
        "#!/usr/bin/env bash\nset -euo pipefail\n"
        "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1\n"
        f"python3 application/scripts/405_launch_glofas_post_search2_dag.py --runtime-root {shlex.quote(relative(runtime))} --workers {args.workers} --cpu-pool {shlex.quote(args.cpu_pool)} --session-prefix {shlex.quote(args.session_prefix)} --background\n"
    )
    launch.chmod(0o755)
    print(f"runtime_root={relative(runtime)}")
    print(f"manifest={relative(manifest)}")
    print(f"launch_readiness={relative(launch_readiness)}")
    print(f"jobs={len(rows)}")
    print(json.dumps(metadata["jobs_by_part"], sort_keys=True))
    print("preparation_state=ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
