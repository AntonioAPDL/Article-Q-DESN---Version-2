#!/usr/bin/env python3
"""Certify and import completed post-Search-II jobs into a fresh runtime."""

import argparse
import csv
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path


ALLOWED_SOURCE_DIFFERENCES = {
    "application/scripts/404_prepare_glofas_post_search2_runtime.py",
    "application/scripts/405_launch_glofas_post_search2_dag.py",
    "application/scripts/406_check_glofas_post_search2_dag.py",
    "application/scripts/407_prepare_glofas_post_search2_inputs.R",
    "application/scripts/408_recover_glofas_post_search2_runtime.py",
    "application/scripts/glofas_post_search2_resources.py",
}

SCIENTIFIC_SOURCE_TRANSITIONS = {
    "application/R/glofas_quantile_integrity.R": {
        "source_sha256": "a65e02707a102294b25db47ed46a4f4d5a9c2bd033ca8873c97c3048ee822b83",
        "destination_sha256": "f55bb6c9b41c637a26fcce569ccb7a67424838dee302a4bd95475f45518e86a1",
        "scope": "explicit_adjacent_tau_policy_preserves_completed_exact_tau_fits",
    },
    "application/R/glofas_part1_quantile_oracle_forecast.R": {
        "source_sha256": "cf3ff154f2bc4c40e605cb2005795cfbba95f08f414ef08664e224ddd0b99073",
        "destination_sha256": "b2a64eae31776aeb6028f3f2403634f31175d52acb3263b972075f26ba439b97",
        "scope": "adjacent_tau_initializer_and_rhs_state_transfer_preserve_completed_median",
    },
    "application/R/glofas_part3_quantile_bridge.R": {
        "source_sha256": "7e7dd74b749f449928e745a5b01db8544d1a4b6368b6b92d4b77ea6d4b4cbba7",
        "destination_sha256": "ef57fd49adbd2e220fea47b7f32e9304cb46242c2358dc9d6e462a48f60fafe8",
        "scope": "adjacent_tau_initializer_preserves_completed_median_and_exact_tau_fits",
    },
    "application/R/glofas_post_search2_workflow.R": {
        "source_sha256": "072ae864339bf03550ec53d5e5e27bb5ea56a6e4609f72f1b35de9d83ff5e87c",
        "destination_sha256": "81165528ce37e957ac23686d5037591900c1c6528ef07dc83e1260c3be627f35",
        "scope": "validated_part1_normal_rhs_iteration_contract",
        "nonrecoverable_job_ids": [
            "part1_fit_normal_rhs_vb",
            "part1_forecast_normal_rhs_vb",
        ],
    },
    "application/scripts/381_run_glofas_dec25_final_refit_job.R": {
        "source_sha256": "6fd9b9fcf7fa62d39a5e43396660d7ed802e64a6ac03b9637d47c2db03d9ed42",
        "destination_sha256": "9387b0a01a73ee1a82244ae82c12587b6f7e61390ae66b788b95a58244812df4",
        "scope": "explicit_model_family_initializer_policy_preserves_completed_exact_tau_fits",
    },
    "application/scripts/403_run_glofas_post_search2_support_job.R": {
        "source_sha256": "2fe46f6cf63fb33be5b3553529524f1299ffb4d07734bd898e33c60874a3c35a",
        "destination_sha256": "571232338d5c4e5a334b69b08acfa52e61a86f0444fa8eb831d6a418936b25c6",
        "scope": "part1_rhs_200_iteration_repair_and_explicit_initializer_policy",
        "nonrecoverable_job_ids": [
            "part1_fit_normal_rhs_vb",
            "part1_forecast_normal_rhs_vb",
        ],
    },
    "application/R/glofas_external_driver_forecast.R": {
        "source_sha256": "b351d06d897435a0c1784036682bd0ed40bec0c8caa66184f62821b435c90be1",
        "destination_sha256": "6d99d03c03a145ee922ead360c95a54ddb2d51093c3877a8149d5e1328da8e13",
        "scope": "part2_part3_external_quantile_forecasts_must_be_recomputed",
    },
    "application/R/glofas_part2_bridge_forecast.R": {
        "source_sha256": "bc1c672546e303a7b13844b728921057439a7eafcd7b562605081580d4c5798c",
        "destination_sha256": "db972024e8b536883bfb6c6bc8e8d47facaecb6afb0ded63aca75a48d474c2d5",
        "scope": "part2_design_and_all_descendants_must_be_recomputed",
        "recoverable_job_ids": ["part1_design", "part3_design"],
    },
    "application/R/glofas_dec25_final_refit_workflow.R": {
        "source_sha256": "59c33dbc1f41f02e88d1b827b2adb580c275ec39068564f90918b18d0414801e",
        "destination_sha256": "9cc96a57b93dd4510e0ac4f8a97c46762b0081f3cc3d844ca5e40ca990225d2b",
        "scope": "part2_design_alignment_and_equivalence_repair",
        "recoverable_job_ids": ["part1_design", "part3_design"],
    },
}

ALLOWED_INITIALIZER_DEPENDENCY_WAIVERS = {
    ("part1_fit_independent_al_q0p50", "part1_fit_normal_rhs_vb"),
}

SPECIAL_MAIN_ARTIFACTS = {
    "part1_design": ("configs/part1_post_search2_design_cache.rds",),
    "part2_design": (
        "configs/part2_final_dec25_design_cache.rds",
        "configs/part2_final_dec25_design_cache_certificate.csv",
    ),
    "part3_design": (
        "configs/part3_final_dec25_design_cache.rds",
        "configs/part3_final_dec25_design_cache_certificate.csv",
    ),
    "full_data_rhs_calibration": (
        "configs/full_data_rhs_calibration.csv",
        "configs/full_data_rhs_calibration.rds",
    ),
    "post_search2_anchor_manifest": ("configs/post_search2_selected_anchor_manifest.csv",),
    "part1_forecast_normal_rhs_vb": ("objects/part1_normal_rhs_driver_bank.rds",),
    "part2_forecast_normal_rhs_vb": ("objects/part2_normal_rhs_driver_bank.rds",),
    "part3_forecast_normal_rhs_vb": ("objects/part3_normal_rhs_driver_bank.rds",),
}

SPECIAL_PART4_ARTIFACTS = {
    "part4_normal_driver_prior": ("objects/part4_normal_driver_prior.rds",),
}

IGNORED_COMMAND_FLAGS = {
    "--runtime_root", "--base_config", "--selected_components", "--calibration_path",
    "--part2_runtime_root", "--part3_runtime_root", "--part4_runtime_root",
    "--part4_base_config", "--part4_run_label", "--normal_driver_bank_path",
}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_csv(path):
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def command_scientific_signature(command_json):
    command = json.loads(command_json)
    out = []
    i = 0
    while i < len(command):
        value = command[i]
        if value in IGNORED_COMMAND_FLAGS:
            i += 2
            continue
        out.append(value)
        i += 1
    return out


def completed_job_ids(runtime, manifest_rows):
    status = runtime / "status"
    return {
        row["job_id"] for row in manifest_rows
        if (status / f"{row['job_id']}.completed").is_file()
    }


def recovery_job_ids(completed, excluded):
    excluded = set(excluded)
    unknown = excluded - set(completed)
    if unknown:
        raise SystemExit(f"excluded recovery jobs are not completed in source: {sorted(unknown)}")
    return set(completed) - excluded


def parse_initializer_dependency_waivers(value):
    pairs = set()
    for token in filter(None, (item.strip() for item in value.split(","))):
        if token.count(":") != 1:
            raise SystemExit(f"invalid initializer dependency waiver: {token}")
        child, parent = (item.strip() for item in token.split(":", 1))
        pair = (child, parent)
        if pair not in ALLOWED_INITIALIZER_DEPENDENCY_WAIVERS:
            raise SystemExit(f"initializer dependency waiver is not allowlisted: {token}")
        pairs.add(pair)
    return pairs


def validate_excluded_dependencies(source_rows, recovery_jobs, excluded, waivers=None):
    source = {row["job_id"]: row for row in source_rows}
    excluded = set(excluded)
    waivers = set(waivers or ())
    for child, parent in waivers:
        if child not in recovery_jobs or parent not in excluded:
            raise SystemExit(
                f"initializer dependency waiver requires recovered child and excluded parent: {child}:{parent}"
            )
        if parent not in set(filter(None, source[child]["dependencies"].split("|"))):
            raise SystemExit(f"initializer dependency waiver is not an actual DAG edge: {child}:{parent}")
    for job_id in recovery_jobs:
        blocked = set(filter(None, source[job_id]["dependencies"].split("|"))) & excluded
        allowed = {parent for child, parent in waivers if child == job_id}
        unexpected = blocked - allowed
        if unexpected:
            raise SystemExit(
                f"cannot recover {job_id}; excluded dependencies are completed: {sorted(unexpected)}"
            )


def certify_initializer_dependency_waivers(source_runtime, source_rows, waivers):
    source = {row["job_id"]: row for row in source_rows}
    certificates = []
    for child, parent in sorted(waivers):
        child_row = source[child]
        parent_row = source[parent]
        if (
            child_row.get("stage") != "fit"
            or child_row.get("model_family") != "independent_al"
            or child_row.get("tau") != "0.50"
            or parent_row.get("model_family") != "normal_rhs_vb"
        ):
            raise SystemExit(f"initializer dependency waiver has an invalid scientific contract: {child}:{parent}")

        child_fit = source_runtime / "objects" / f"{child}_fit.rds"
        parent_fit = source_runtime / "objects" / f"{parent}_fit.rds"
        child_execution = source_runtime / "logs" / f"{child}_execution_contract.csv"
        parent_execution = source_runtime / "logs" / f"{parent}_execution_contract.csv"
        progress_path = source_runtime / "traces" / f"{child}_progress.csv"
        for path in (child_fit, parent_fit, child_execution, parent_execution, progress_path):
            if not path.is_file():
                raise SystemExit(f"initializer dependency waiver evidence is missing: {path}")

        execution_rows = read_csv(child_execution)
        progress_rows = read_csv(progress_path)
        if len(execution_rows) != 1 or not progress_rows:
            raise SystemExit(f"initializer dependency waiver evidence is malformed: {child}")
        execution = execution_rows[0]
        terminal = progress_rows[-1]
        if (
            execution.get("model_family") != "independent_al"
            or float(execution.get("tau", "nan")) != 0.5
            or execution.get("converged") != "TRUE"
            or int(float(execution.get("iterations", 0))) < 200
            or terminal.get("converged") != "TRUE"
            or int(float(terminal.get("iter", 0))) < 200
            or int(float(terminal.get("beta_update_count", 0))) < 180
            or float(terminal.get("max_beta_change", "inf")) > 1.0e-8
        ):
            raise SystemExit(f"initializer dependency waiver convergence gate failed: {child}")

        expression = (
            "x <- readRDS(commandArgs(TRUE)[1]); "
            "cat(normalizePath(x$init_source_path, mustWork=TRUE))"
        )
        result = subprocess.run(
            ["Rscript", "-e", expression, str(child_fit)],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            universal_newlines=True,
        )
        initializer_path = Path(result.stdout.strip()).resolve()
        if initializer_path != parent_fit.resolve():
            raise SystemExit(
                f"initializer dependency waiver parent mismatch for {child}: {initializer_path}"
            )
        certificates.append({
            "child_job_id": child,
            "parent_job_id": parent,
            "scientific_reason": "completed_child_is_stationary_and_parent_was_initialization_only",
            "child_fit_path": str(child_fit),
            "child_fit_sha256": sha256(child_fit),
            "parent_initializer_path": str(parent_fit),
            "parent_initializer_sha256": sha256(parent_fit),
            "child_execution_contract_path": str(child_execution),
            "child_execution_contract_sha256": sha256(child_execution),
            "parent_execution_contract_path": str(parent_execution),
            "parent_execution_contract_sha256": sha256(parent_execution),
            "terminal_progress_path": str(progress_path),
            "terminal_progress_sha256": sha256(progress_path),
            "terminal_iteration": int(float(terminal["iter"])),
            "terminal_beta_update_count": int(float(terminal["beta_update_count"])),
            "terminal_max_beta_change": float(terminal["max_beta_change"]),
        })
    return certificates


def validate_job_contracts(source_rows, destination_rows, job_ids):
    source = {row["job_id"]: row for row in source_rows}
    destination = {row["job_id"]: row for row in destination_rows}
    fields = ("job_id", "part", "stage", "model_family", "tau", "dependencies", "worker_slots", "role")
    for job_id in sorted(job_ids):
        if job_id not in destination:
            raise SystemExit(f"recovery job is absent from destination DAG: {job_id}")
        for field in fields:
            if source[job_id].get(field, "") != destination[job_id].get(field, ""):
                raise SystemExit(f"job contract mismatch for {job_id}.{field}")
        if command_scientific_signature(source[job_id]["command_json"]) != command_scientific_signature(
            destination[job_id]["command_json"]
        ):
            raise SystemExit(f"scientific command mismatch for recovery job: {job_id}")


def validate_transition_job_scope(source_rows, job_ids, transitioned_paths):
    source = {row["job_id"]: row for row in source_rows}
    for path in transitioned_paths:
        transition = SCIENTIFIC_SOURCE_TRANSITIONS[path]
        recoverable = transition.get("recoverable_job_ids")
        if recoverable is not None:
            blocked = sorted(set(job_ids) - set(recoverable))
            if blocked:
                raise SystemExit(
                    f"scientific transition {path} requires recomputing these jobs: "
                    + ", ".join(blocked)
                )
        nonrecoverable = transition.get("nonrecoverable_job_ids", [])
        blocked = sorted(set(job_ids) & set(nonrecoverable))
        if blocked:
            raise SystemExit(
                f"scientific transition {path} requires recomputing these jobs: "
                + ", ".join(blocked)
            )
        elif path == "application/R/glofas_external_driver_forecast.R":
            blocked = sorted(
                job_id for job_id in job_ids
                if source[job_id].get("part") in {"part2", "part3"}
                and source[job_id].get("role") == "external_normal_driver_forecast"
            )
            if blocked:
                raise SystemExit(
                    "forecast-adapter transition requires recomputing these jobs: "
                    + ", ".join(blocked)
                )


def validate_scientific_sources(source_runtime, destination_runtime, source_rows, job_ids):
    old_rows = read_csv(source_runtime / "configs" / "post_search2_source_manifest.csv")
    new_rows = read_csv(destination_runtime / "configs" / "post_search2_source_manifest.csv")
    old = {row["path"]: row["sha256"] for row in old_rows}
    new = {row["path"]: row["sha256"] for row in new_rows}
    required = {
        path for path in old
        if path.startswith("application/R/")
        or path in {
            "application/scripts/381_run_glofas_dec25_final_refit_job.R",
            "application/scripts/386_run_glofas_part4_latent_family_job.R",
            "application/scripts/403_run_glofas_post_search2_support_job.R",
            "application/src/glofas_external_driver_forecast.cpp",
        }
    }
    missing = sorted(required - set(new))
    changed = sorted(path for path in required & set(new) if old[path] != new[path])
    transitioned = []
    unauthorized = []
    for path in changed:
        transition = SCIENTIFIC_SOURCE_TRANSITIONS.get(path)
        if (
            transition
            and old[path] == transition["source_sha256"]
            and new[path] == transition["destination_sha256"]
        ):
            transitioned.append(path)
        else:
            unauthorized.append(path)
    if missing or unauthorized:
        raise SystemExit(
            "scientific source mismatch prevents recovery; "
            f"missing={missing}; changed={unauthorized}"
        )
    validate_transition_job_scope(source_rows, job_ids, transitioned)
    unexpected_changed = sorted(
        path for path in set(old) & set(new)
        if old[path] != new[path] and path not in ALLOWED_SOURCE_DIFFERENCES
        and path not in transitioned
        and not path.startswith("local_trackers/runtime_configs/")
    )
    if unexpected_changed:
        raise SystemExit(f"non-orchestration source changed: {unexpected_changed}")
    return [
        {"path": path, **SCIENTIFIC_SOURCE_TRANSITIONS[path]}
        for path in transitioned
    ]


def required_artifacts(job, source_runtime, source_part4_runtime):
    job_id = job["job_id"]
    paths = set()
    for path in source_runtime.rglob("*"):
        if not path.is_file() or path.parent.name in {"status", "scripts"}:
            continue
        relative = path.relative_to(source_runtime)
        if relative.parts[:2] == ("configs", "recovery_certificates"):
            continue
        if relative in {
            Path("configs/recovery_contract.json"),
            Path("configs/recovery_artifact_manifest.csv"),
        }:
            continue
        if job_id in path.name:
            paths.add(("main", relative))
    for relative in SPECIAL_MAIN_ARTIFACTS.get(job_id, ()):
        paths.add(("main", Path(relative)))
    for relative in SPECIAL_PART4_ARTIFACTS.get(job_id, ()):
        paths.add(("part4", Path(relative)))

    if job["stage"] == "fit":
        paths.add(("main", Path("objects") / f"{job_id}_fit.rds"))
    if job_id == "part1_forecast_normal_ridge" or job_id == "part1_forecast_normal_rhs_vb":
        paths.add(("main", Path("objects") / f"{job_id}_forecast_draws.rds"))
    if job_id.startswith("part2_forecast_normal_"):
        paths.add(("main", Path("objects") / f"{job_id}_retained_fit_view.rds"))
    if job_id.startswith("part3_forecast_normal_"):
        paths.add(("main", Path("forecasts") / f"{job_id}_forecast.rds"))

    resolved = []
    for root_kind, relative in sorted(paths, key=lambda item: (item[0], str(item[1]))):
        root = source_runtime if root_kind == "main" else source_part4_runtime
        path = root / relative
        if not path.is_file():
            raise SystemExit(f"required recovery artifact is missing for {job_id}: {path}")
        resolved.append((root_kind, relative, path))
    if not resolved:
        raise SystemExit(f"no recovery artifacts resolved for completed job: {job_id}")
    return resolved


def copy_reflink(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ["cp", "--reflink=auto", "--preserve=mode,timestamps", str(source), str(destination)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
    )
    if result.returncode != 0:
        shutil.copy2(source, destination)


def validate_rds(paths):
    rds = [str(path) for path in paths if path.suffix.lower() == ".rds"]
    if not rds:
        return
    expression = (
        "paths <- commandArgs(TRUE); "
        "for (p in paths) { x <- readRDS(p); rm(x); gc(FALSE) }; "
        "cat('RECOVERY_RDS_READ_PASS\\n')"
    )
    subprocess.run(["Rscript", "-e", expression, *rds], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-runtime", required=True)
    parser.add_argument("--source-part4-runtime", required=True)
    parser.add_argument("--destination-runtime", required=True)
    parser.add_argument("--destination-part4-runtime", required=True)
    parser.add_argument("--expected-completed", type=int, default=25)
    parser.add_argument("--exclude-job-ids", default="")
    parser.add_argument("--initializer-dependency-waivers", default="")
    args = parser.parse_args()

    source_runtime = Path(args.source_runtime).resolve()
    source_part4_runtime = Path(args.source_part4_runtime).resolve()
    destination_runtime = Path(args.destination_runtime).resolve()
    destination_part4_runtime = Path(args.destination_part4_runtime).resolve()
    for root in (source_runtime, source_part4_runtime, destination_runtime):
        if not root.is_dir():
            raise SystemExit(f"required runtime does not exist: {root}")
    destination_part4_runtime.mkdir(parents=True, exist_ok=True)
    if any((destination_runtime / "status").glob("*.completed")):
        raise SystemExit("destination runtime already contains completed markers")
    if any((destination_runtime / "status").glob("*.failed")):
        raise SystemExit("destination runtime contains failed markers")

    source_manifest = read_csv(source_runtime / "tables" / "post_search2_job_manifest.csv")
    destination_manifest = read_csv(destination_runtime / "tables" / "post_search2_job_manifest.csv")
    source_completed = completed_job_ids(source_runtime, source_manifest)
    if len(source_completed) != args.expected_completed:
        raise SystemExit(
            f"expected {args.expected_completed} completed source jobs, found {len(source_completed)}"
        )
    excluded = {
        value.strip() for value in args.exclude_job_ids.split(",") if value.strip()
    }
    waivers = parse_initializer_dependency_waivers(args.initializer_dependency_waivers)
    completed = recovery_job_ids(source_completed, excluded)
    if "part4_prepare_runtime" in source_completed and "part4_prepare_runtime" not in excluded:
        raise SystemExit(
            "Part 4 runtime preparation is operational and must be explicitly excluded"
        )
    source_by_id = {row["job_id"]: row for row in source_manifest}
    validate_excluded_dependencies(source_manifest, completed, excluded, waivers)
    waiver_certificates = certify_initializer_dependency_waivers(
        source_runtime, source_manifest, waivers
    )
    validate_job_contracts(source_manifest, destination_manifest, completed)
    scientific_transitions = validate_scientific_sources(
        source_runtime, destination_runtime, source_manifest, completed
    )

    artifact_rows = []
    planned = {}
    for job_id in sorted(completed):
        planned[job_id] = required_artifacts(
            source_by_id[job_id], source_runtime, source_part4_runtime
        )
        for root_kind, relative, source in planned[job_id]:
            artifact_rows.append({
                "job_id": job_id,
                "root_kind": root_kind,
                "relative_path": str(relative),
                "size_bytes": source.stat().st_size,
                "sha256": sha256(source),
                "source_path": str(source),
            })
    for certificate in waiver_certificates:
        parent = certificate["parent_job_id"]
        for label, source_path in (
            ("fit", certificate["parent_initializer_path"]),
            ("execution_contract", certificate["parent_execution_contract_path"]),
        ):
            source = Path(source_path)
            relative = Path("configs/recovery_legacy_initializers") / f"{parent}_{label}{source.suffix}"
            artifact_rows.append({
                "job_id": certificate["child_job_id"],
                "root_kind": "main",
                "relative_path": str(relative),
                "size_bytes": source.stat().st_size,
                "sha256": sha256(source),
                "source_path": str(source),
            })

    staging = destination_runtime / ".recovery_staging"
    if staging.exists():
        raise SystemExit(f"recovery staging path already exists: {staging}")
    staging_part4 = staging / "part4"
    staging_main = staging / "main"
    try:
        copied = []
        for row in artifact_rows:
            source = Path(row["source_path"])
            root = staging_main if row["root_kind"] == "main" else staging_part4
            destination = root / row["relative_path"]
            copy_reflink(source, destination)
            if sha256(destination) != row["sha256"]:
                raise SystemExit(f"recovery copy hash mismatch: {destination}")
            copied.append(destination)
        validate_rds(copied)

        recovery_dir = destination_runtime / "configs" / "recovery_certificates"
        recovery_dir.mkdir(parents=True, exist_ok=True)
        for job_id in sorted(completed):
            job_rows = [row for row in artifact_rows if row["job_id"] == job_id]
            payload = {
                "schema_version": "glofas_post_search2_recovered_job_v1",
                "job_id": job_id,
                "source_runtime": str(source_runtime),
                "source_marker_sha256": sha256(source_runtime / "status" / f"{job_id}.completed"),
                "artifacts": job_rows,
            }
            certificate = recovery_dir / f"{job_id}.json"
            certificate.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

        for staged_root, final_root in (
            (staging_main, destination_runtime),
            (staging_part4, destination_part4_runtime),
        ):
            if not staged_root.exists():
                continue
            for source in sorted(staged_root.rglob("*")):
                if not source.is_file():
                    continue
                relative = source.relative_to(staged_root)
                destination = final_root / relative
                if destination.exists():
                    raise SystemExit(f"recovery would overwrite destination artifact: {destination}")
                destination.parent.mkdir(parents=True, exist_ok=True)
                os.replace(source, destination)

        manifest_path = destination_runtime / "configs" / "recovery_artifact_manifest.csv"
        write_csv(manifest_path, artifact_rows)
        recovery_contract = {
            "schema_version": "glofas_post_search2_recovery_v1",
            "source_runtime": str(source_runtime),
            "source_part4_runtime": str(source_part4_runtime),
            "destination_runtime": str(destination_runtime),
            "destination_part4_runtime": str(destination_part4_runtime),
            "completed_jobs": sorted(completed),
            "completed_job_count": len(completed),
            "source_completed_job_count": len(source_completed),
            "excluded_completed_jobs": sorted(excluded),
            "scientific_source_transitions": scientific_transitions,
            "initializer_dependency_waivers": waiver_certificates,
            "artifact_count": len(artifact_rows),
            "artifact_manifest": str(manifest_path),
            "artifact_manifest_sha256": sha256(manifest_path),
        }
        contract_path = destination_runtime / "configs" / "recovery_contract.json"
        contract_path.write_text(json.dumps(recovery_contract, indent=2, sort_keys=True) + "\n", encoding="utf-8")

        for job_id in sorted(completed):
            certificate = recovery_dir / f"{job_id}.json"
            marker = destination_runtime / "status" / f"{job_id}.completed"
            marker.write_text(
                f"recovered_from={source_runtime}\n"
                f"source_marker_sha256={sha256(source_runtime / 'status' / f'{job_id}.completed')}\n"
                f"certificate={certificate}\n"
                f"certificate_sha256={sha256(certificate)}\n",
                encoding="utf-8",
            )
    finally:
        if staging.exists():
            shutil.rmtree(staging)

    print(f"source_completed_jobs={len(source_completed)}")
    print(f"excluded_completed_jobs={len(excluded)}")
    print(f"recovered_jobs={len(completed)}")
    print(f"recovered_artifacts={len(artifact_rows)}")
    print(f"recovery_contract={contract_path}")
    print("POST_SEARCH2_RECOVERY_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
