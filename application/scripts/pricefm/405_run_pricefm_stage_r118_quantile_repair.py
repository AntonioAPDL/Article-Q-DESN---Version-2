#!/usr/bin/env python3
"""Run and close out the bounded PriceFM R118 exact-CRAN mechanism probes."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any

import pandas as pd


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_common import sha256_file, write_json


TAG = "pricefm_stage_r118_exact_cran_quantile_repair_20260925"
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
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
    value.add_argument("--cpu-list", default="0,1,2,3")
    return value


def parse_cpus(value: str) -> list[int]:
    cpus = [int(token.strip()) for token in str(value).split(",") if token.strip()]
    if not cpus or len(cpus) != len(set(cpus)) or min(cpus) < 0 or max(cpus) >= (os.cpu_count() or 0):
        raise ValueError("invalid R118 CPU list")
    return cpus


def verify_manifest(path: Path) -> None:
    value = json.loads(path.read_text())
    if value.get("status") != "hash_sealed_training_only_sources" or value.get("test_opened"):
        raise RuntimeError("invalid R118 source manifest")
    for record in value["files"]:
        source = Path(record["path"])
        if not source.is_file() or sha256_file(source) != record["sha256"]:
            raise RuntimeError(f"R118 source drift: {source}")


def run_one(rscript: str, runner: Path, config: Path, log: Path, cpu: int) -> None:
    log.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.update({name: "1" for name in THREAD_ENV})
    command = ["taskset", "-c", str(cpu), rscript, str(runner), "--config", str(config)]
    with log.open("a") as handle:
        handle.write("$ {}\n".format(" ".join(command)))
        handle.flush()
        result = subprocess.run(command, env=env, stdout=handle, stderr=subprocess.STDOUT, check=False)
    if result.returncode:
        raise RuntimeError(f"R118 probe failed: {config}")


def closeout(manifest: pd.DataFrame, campaign: Path) -> dict[str, Any]:
    rows = []
    target_hashes = {
        family: set(group.posterior_target_sha256.astype(str))
        for family, group in manifest.groupby("family")
    }
    if set(target_hashes) != {"al", "exal"} or any(len(value) != 1 for value in target_hashes.values()):
        raise RuntimeError("R118 schedules do not share one posterior target within family")
    if target_hashes["al"] == target_hashes["exal"]:
        raise RuntimeError("AL and exAL must not claim the same posterior target")
    for record in manifest.itertuples(index=False):
        terminal_path = Path(record.output_dir) / "terminal.json"
        terminal = json.loads(terminal_path.read_text())
        expected_target = next(iter(target_hashes[str(record.family)]))
        if terminal.get("test_opened") or terminal.get("posterior_target_sha256") != expected_target:
            raise RuntimeError(f"invalid R118 probe terminal: {terminal_path}")
        for artifact in terminal["artifacts"]:
            path = terminal_path.parent / artifact["path"]
            if not path.is_file() or sha256_file(path) != artifact["sha256"]:
                raise RuntimeError(f"R118 probe artifact hash mismatch: {path}")
        rows.append({
            "arm_id": terminal["arm_id"],
            "family": terminal["family"],
            "formal_converged": bool(terminal["formal_converged"]),
            "external_gate_passed": bool(terminal["external_gate_passed"]),
            "finite_core": bool(terminal["finite_core"]),
            "bounded": bool(terminal["bounded"]),
            "sigma": float(terminal["sigma"]),
            "gamma": float(terminal["gamma"]),
            "relative_state_tail_max": float(terminal["relative_state_tail_max"]),
            "relative_sigma_tail_max": float(terminal["relative_sigma_tail_max"]),
            "relative_elbo_tail_max": float(terminal["relative_elbo_tail_max"]),
            "post_release_updates": int(terminal["post_release_updates"]),
            "train_seconds": float(terminal["train_seconds"]),
            "priority": int(record.priority),
            "terminal_path": str(terminal_path),
            "terminal_sha256": sha256_file(terminal_path),
        })
    frame = pd.DataFrame(rows).sort_values(["family", "priority", "arm_id"], kind="mergesort")
    al = frame[frame.family.eq("al")]
    exal = frame[frame.family.eq("exal") & frame.external_gate_passed]
    al_passed = len(al) == 1 and bool(al.iloc[0].external_gate_passed)
    exal_passed = not exal.empty
    selected_exal = None if exal.empty else str(exal.sort_values(
        ["priority", "relative_state_tail_max", "relative_elbo_tail_max"], kind="mergesort"
    ).iloc[0].arm_id)
    decision = (
        "continue_al_and_exal" if al_passed and exal_passed
        else "continue_al_only" if al_passed
        else "stop_reparameterize_readout"
    )
    closeout_dir = campaign / "probe_closeout"
    closeout_dir.mkdir(parents=True, exist_ok=True)
    frame.to_csv(closeout_dir / "probe_results.csv", index=False)
    summary = {
        "stage": "R118_probe",
        "status": "completed_training_only_mechanism_probe",
        "decision": decision,
        "al_external_gate_passed": bool(al_passed),
        "exal_external_gate_passed": bool(exal_passed),
        "selected_exal_schedule": selected_exal,
        "posterior_target_sha256_by_family": {
            family: next(iter(values)) for family, values in target_hashes.items()
        },
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
        "joint_model_fitted": False,
        "mcmc_fitted": False,
    }
    write_json(closeout_dir / "summary.json", summary)
    (closeout_dir / "README.md").write_text(
        "# PriceFM R118 mechanism-probe closeout\n\n"
        f"Decision: `{decision}`\n\n"
        "The package formal convergence flag and the scale-aware external numerical gate "
        "are reported separately. A passed schedule changes optimization timing only; all "
        "arms retain the frozen prior and posterior-target hash.\n"
    )
    write_json(closeout_dir / "manifest.json", {
        "status": "hash_sealed_r118_probe_closeout",
        "files": [
            {"path": str(path), "sha256": sha256_file(path)}
            for path in (
                closeout_dir / "probe_results.csv",
                closeout_dir / "summary.json",
                closeout_dir / "README.md",
            )
        ],
        "test_opened": False,
    })
    return summary


def run(args: argparse.Namespace) -> dict[str, Any]:
    artifact = args.artifact_repo.resolve()
    code = args.code_root.resolve()
    data = artifact / "application/data_local/pricefm"
    prep = (args.prep_dir or data / "launch_prep" / TAG).resolve()
    control = json.loads((prep / "launch_control.json").read_text())
    if control.get("status") != "prepared_not_launched" or control.get("test_opened"):
        raise RuntimeError("invalid R118 launch control")
    verify_manifest(Path(control["source_manifest"]))
    manifest = pd.read_csv(control["probe_manifest"])
    exal_targets = manifest.loc[manifest.family.eq("exal"), "posterior_target_sha256"]
    if (
        manifest.test_access_authorized.astype(bool).any()
        or exal_targets.nunique() != 1
        or manifest.posterior_target_sha256.nunique() != 2
    ):
        raise RuntimeError("R118 manifest firewall or target mismatch")
    cpus = parse_cpus(args.cpu_list)
    if len(cpus) < len(manifest):
        raise RuntimeError("R118 probe requires one distinct CPU per arm")
    runner = code / "application/scripts/pricefm/404_probe_pricefm_stage_r118_quantile_mechanism.R"
    campaign = Path(control["campaign_root"])
    tasks = []
    for index, record in enumerate(manifest.itertuples(index=False)):
        terminal = Path(record.output_dir) / "terminal.json"
        if terminal.is_file():
            continue
        tasks.append((record.arm_id, Path(record.config_path), cpus[index]))
    with ThreadPoolExecutor(max_workers=len(cpus)) as pool:
        futures = {
            pool.submit(
                run_one, control["rscript"], runner, config,
                campaign / "logs" / f"{arm_id}.log", cpu,
            ): arm_id
            for arm_id, config, cpu in tasks
        }
        for future in as_completed(futures):
            future.result()
    return closeout(manifest, campaign)


def main() -> int:
    result = run(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
