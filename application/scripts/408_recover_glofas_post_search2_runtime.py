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


def validate_excluded_dependencies(source_rows, recovery_jobs, excluded):
    source = {row["job_id"]: row for row in source_rows}
    excluded = set(excluded)
    for job_id in recovery_jobs:
        blocked = set(filter(None, source[job_id]["dependencies"].split("|"))) & excluded
        if blocked:
            raise SystemExit(
                f"cannot recover {job_id}; excluded dependencies are completed: {sorted(blocked)}"
            )


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


def validate_scientific_sources(source_runtime, destination_runtime):
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
    if missing or changed:
        raise SystemExit(
            "scientific source mismatch prevents recovery; "
            f"missing={missing}; changed={changed}"
        )
    unexpected_changed = sorted(
        path for path in set(old) & set(new)
        if old[path] != new[path] and path not in ALLOWED_SOURCE_DIFFERENCES
        and not path.startswith("local_trackers/runtime_configs/")
    )
    if unexpected_changed:
        raise SystemExit(f"non-orchestration source changed: {unexpected_changed}")


def required_artifacts(job, source_runtime, source_part4_runtime):
    job_id = job["job_id"]
    paths = set()
    for path in source_runtime.rglob("*"):
        if not path.is_file() or path.parent.name in {"status", "scripts"}:
            continue
        if job_id in path.name:
            paths.add(("main", path.relative_to(source_runtime)))
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
    parser.add_argument("--expected-completed", type=int, default=21)
    parser.add_argument("--exclude-job-ids", default="")
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
    completed = recovery_job_ids(source_completed, excluded)
    if "part4_prepare_runtime" in source_completed and "part4_prepare_runtime" not in excluded:
        raise SystemExit(
            "Part 4 runtime preparation is operational and must be explicitly excluded"
        )
    source_by_id = {row["job_id"]: row for row in source_manifest}
    validate_excluded_dependencies(source_manifest, completed, excluded)
    validate_job_contracts(source_manifest, destination_manifest, completed)
    validate_scientific_sources(source_runtime, destination_runtime)

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
