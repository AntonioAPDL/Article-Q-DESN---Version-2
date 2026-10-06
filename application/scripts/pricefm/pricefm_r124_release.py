#!/usr/bin/env python3
"""Run the inherited and R124 release checks in an isolated evidence directory."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
TAG = "pricefm_stage_r124_covariance_preserving_replay_v2_20261006"
PYTHON_TESTS = (
    "test_pricefm_internal_target_embargo.py",
    "test_pricefm_stage_r120_explicit_lag_search.py",
    "test_pricefm_stage_r121_targeted_dense_refinement.py",
    "test_pricefm_stage_r122_continuation.py",
    "test_pricefm_stage_r122_frozen_closeout.py",
    "test_pricefm_stage_r122_long_memory_launch.py",
    "test_pricefm_stage_r122_numerical_and_evaluation_contract.py",
    "test_pricefm_stage_r122_stage0_and_long_memory.py",
    "test_pricefm_stage_r123_centre_audit.py",
    "test_pricefm_stage_r123_certified_successor.py",
    "test_pricefm_stage_r123_closeout_hardening.py",
    "test_pricefm_stage_r123_connectivity.py",
    "test_pricefm_stage_r123_recovery.py",
    "test_pricefm_stage_r123_stationarity.py",
    "test_pricefm_stage_r123_dependency_resume.py",
    "test_pricefm_stage_r124_covariance_replay.py",
)


def run(output, cpu):
    expected = DATA / "launch_prep" / TAG / "release"
    if not output.resolve().is_relative_to(expected) or output.exists():
        raise ValueError("new assigned release evidence directory required")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT):
        raise ValueError("committed clean release source required")
    if cpu not in os.sched_getaffinity(0): raise ValueError("CPU outside permitted affinity")
    os.sched_setaffinity(0, {cpu})
    output.mkdir(parents=True); (output / "tmp").mkdir()
    env = dict(os.environ)
    for name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
        env[name] = "1"
    env["PYTHONDONTWRITEBYTECODE"] = "1"; env["TMPDIR"] = str(output / "tmp")
    rhome = Path("/data/jaguir26/local/opt/R/4.6.0")
    env["PATH"] = str(rhome / "bin") + os.pathsep + env["PATH"]
    env["LD_LIBRARY_PATH"] = str(rhome / "lib64/R/lib") + os.pathsep + env.get("LD_LIBRARY_PATH", "")
    rscript = str(rhome / "bin/Rscript")
    normal = str(DATA / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm")
    cran = str(DATA / "runtime_libraries/exdqlm_cran_1p1p1")
    commands = [[sys.executable, "-B", "-m", "pytest", "-q", "-p", "no:cacheprovider",
        "--basetemp=" + str(output / "pytest_tmp"), "--junitxml=" + str(output / "python.xml"),
        *["application/tests/" + name for name in PYTHON_TESTS]],
        [rscript, "application/tests/test_pricefm_recursive_normal_fit.R"],
        [rscript, "application/tests/test_pricefm_rhs_stationarity.R", normal],
        [rscript, "application/tests/test_pricefm_stage_r123_prior_gate.R", "--normal-runtime", normal,
            "--cran-library", cran, "--output", str(output / "prior_gate.json")],
        [rscript, "application/tests/test_pricefm_stage_r123_cran_al_initialization.R", "--cran-library", cran,
            "--output", str(output / "cran_al_initialization.json")]]
    outcomes = []
    for index, command in enumerate(commands):
        with (output / f"suite_{index}.log").open("x") as stream:
            result = subprocess.run(command, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT)
        outcomes.append(dict(command=command, exit_code=result.returncode))
        print(json.dumps(outcomes[-1]), flush=True)
        if result.returncode: break
    suites = ET.parse(output / "python.xml").getroot().findall("testsuite")
    counts = {key: sum(int(s.get(key, 0)) for s in suites) for key in ("tests", "failures", "errors", "skipped")}
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT):
        raise RuntimeError("release altered tracked source")
    receipt = dict(source_head=head, host=socket.gethostname(), python=sys.executable, cpu=cpu,
        python_tests=counts["tests"], failures=counts["failures"], errors=counts["errors"],
        skipped=counts["skipped"], r_suites=sum(row["exit_code"] == 0 for row in outcomes[1:]),
        r124_tests_included=PYTHON_TESTS[-1] == "test_pricefm_stage_r124_covariance_replay.py",
        outcomes=outcomes, evidence_sha256={str(p): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in output.glob("*") if p.is_file()})
    passed = (len(outcomes) == 5 and all(row["exit_code"] == 0 for row in outcomes)
              and receipt["python_tests"] >= 399 and not receipt["failures"] and not receipt["errors"] and not receipt["skipped"])
    (output / ("validation.json" if passed else "failed.json")).write_text(json.dumps(receipt, indent=2) + "\n")
    if not passed: raise RuntimeError("release checks failed; evidence preserved")
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cpu", type=int, required=True)
    args = parser.parse_args()
    print(json.dumps(run(args.output, args.cpu)), flush=True)
