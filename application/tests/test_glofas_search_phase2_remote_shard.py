#!/usr/bin/env python3

import csv
import hashlib
import importlib.util
from pathlib import Path
import subprocess
import tempfile


REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "application" / "scripts" / "402_manage_glofas_search_phase2_remote_shard.py"
spec = importlib.util.spec_from_file_location("remote_shard", SCRIPT)
remote = importlib.util.module_from_spec(spec)
spec.loader.exec_module(remote)


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def run(*args):
    return subprocess.run(["python3", str(SCRIPT), *map(str, args)], universal_newlines=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)


with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    repo = temp / "repo"
    subprocess.run(["git", "init", "-q", repo], check=True)
    subprocess.run(["git", "-C", repo, "config", "user.email", "test@example.org"], check=True)
    subprocess.run(["git", "-C", repo, "config", "user.name", "Test"], check=True)
    (repo / "tracked").write_text("source\n")
    subprocess.run(["git", "-C", repo, "add", "tracked"], check=True)
    subprocess.run(["git", "-C", repo, "commit", "-qm", "fixture"], check=True)
    head = subprocess.check_output(["git", "-C", repo, "rev-parse", "HEAD"], universal_newlines=True).strip()
    subprocess.run(["git", "-C", repo, "branch", "upstream"], check=True)
    subprocess.run(["git", "-C", repo, "branch", "--set-upstream-to", "upstream"], check=True,
                   stdout=subprocess.DEVNULL)

    source = temp / "source"
    for directory in remote.INPUT_DIRS + remote.OUTPUT_DIRS + ("control",):
        (source / directory).mkdir(parents=True, exist_ok=True)
    model = source / "model_inputs" / "reference__fold_a.rds"
    score = source / "scoring_inputs" / "reference__fold_a.csv"
    model.write_bytes(b"model")
    score.write_text("date,observed\n2020-01-01,1\n")
    jobs = []
    for number in (1, 2):
        jobs.append({"job_id": f"job_{number}", "candidate_id": f"candidate_{number}",
                     "target": "reference", "fold_id": "fold_a", "memory_weight": "1",
                     "model_packet_path": str(model), "model_packet_sha256": remote.sha256_file(model)})
    write_csv(source / "configs" / "job_manifest.csv", jobs)
    write_csv(source / "configs" / "candidate_manifest.csv", [
        {"candidate_id": "candidate_1", "target": "reference"},
        {"candidate_id": "candidate_2", "target": "reference"},
    ])
    write_csv(source / "configs" / "model_packet_registry.csv", [{
        "target": "reference", "fold_id": "fold_a", "model_packet_path": str(model),
        "model_packet_sha256": remote.sha256_file(model),
    }])
    write_csv(source / "configs" / "scoring_packet_registry.csv", [{
        "target": "reference", "fold_id": "fold_a", "scoring_packet_path": str(score),
        "scoring_packet_sha256": remote.sha256_file(score),
    }])
    (source / "configs" / "run_manifest.yaml").write_text(
        f"version: test\nrepo_root: {repo}\ngit_head: {head}\n"
    )
    (source / "status" / "job_2.failed").write_text(remote.HOLD_TEXT)
    selected = temp / "selected.txt"
    selected.write_text("job_2\n")
    staging = temp / "staging"
    destination = temp / "destination"

    result = run("prepare", "--source-runtime-root", source, "--staging-root", staging,
                 "--destination-runtime-root", destination, "--destination-repo-root", repo,
                 "--job-id-file", selected, "--expected-head", head)
    assert result.returncode == 0, result.stderr
    shutil_target = destination
    staging.rename(shutil_target)
    result = run("verify", "--runtime-root", shutil_target, "--repo-root", repo,
                 "--expected-head", head, "--expected-jobs", "1")
    assert result.returncode == 0, result.stderr
    assert (shutil_target / "control" / "remote_shard_manager.py").is_file()
    relocated = remote.read_csv(shutil_target / "configs" / "job_manifest.csv")
    assert len(relocated) == 1 and relocated[0]["job_id"] == "job_2"
    assert relocated[0]["model_packet_path"].startswith(str(destination))

    job = "job_2"
    outputs = {
        "forecasts": f"{job}_forecast.csv", "fits": f"{job}_summary.csv",
        "traces": f"{job}_trace.csv", "warm_starts": f"{job}_warm_start.rds",
    }
    for directory, name in outputs.items():
        (shutil_target / directory / name).write_text("x\n")
    for name in (f"{job}_summary.csv", f"{job}_detail.csv"):
        (shutil_target / "scores" / name).write_text("x\n")
    for name in (f"{job}_top50.csv", f"{job}_activity.csv"):
        (shutil_target / "coefficients" / name).write_text("x\n")
    for suffix in (".model_done", ".done"):
        (shutil_target / "status" / f"{job}{suffix}").write_text("ok\n")
    result = run("finalize", "--runtime-root", shutil_target)
    assert result.returncode == 0, result.stderr

    central = temp / "central"
    for directory in remote.OUTPUT_DIRS:
        (central / directory).mkdir(parents=True, exist_ok=True)
    (central / "status" / f"{job}.failed").write_text(remote.HOLD_TEXT)
    result = run("import-results", "--shard-runtime-root", shutil_target,
                 "--central-runtime-root", central)
    assert result.returncode == 0, result.stderr
    assert (central / "status" / f"{job}.done").exists()
    assert not (central / "status" / f"{job}.failed").exists()

print("Search-II remote shard tests passed")
