"""Compute-node wrapper for the two admitted qualification job classes."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
from . import registry as r
from .control import verify_release, safe_tree
from .environment import require_compute, THREAD_ENV, REFERENCE_NUMERICAL_ENV, validate_reference_profile_record


def execute(release, expected_sha):
    release=Path(release).absolute()
    if r.digest(release/"release.json")!=expected_sha:raise ValueError("admitted manifest digest mismatch")
    manifest=verify_release(release)
    allocation=require_compute()
    outputs=release/"outputs"
    if set(outputs.iterdir()):raise FileExistsError("existing output; no retry/overwrite")
    env=dict(os.environ,**THREAD_ENV,PYTHONNOUSERSITE="1",PYTHONDONTWRITEBYTECODE="1",PYTHONPATH=str(release/"code"))
    if manifest.get("numerical_profile") is not None:
        if manifest["numerical_profile"]!="Sandybridge_AVX_v1":raise ValueError("unreviewed numerical profile")
        env.update(REFERENCE_NUMERICAL_ENV)
    passed=False;error=None;kind=manifest["task"]["kind"]
    try:
        if kind=="environment":
            prefix=release/"runtime"
            subprocess.run(["bash",str(release/"code/pricefm_hb/environment_build.sh"),"--bundle",str(release/"env"),
                "--prefix",str(prefix),"--report",str(outputs/"build-report.json")],env=env,check=True,timeout=manifest["limits"]["wall_seconds"]-30)
            report=r.read(outputs/"build-report.json")
            if report["status"]!="verified" or report["allocation"]!=allocation:raise ValueError("environment attestation mismatch")
            evidence=outputs/"environment-evidence";evidence.mkdir()
            for name in ("interpreter-artifact-manifest.json","runtime-verification.json","conda-explicit.txt",
                         "conda-create.log","venv-create.log","pip-install.log","pip-check.log","runtime-verification.log"):
                shutil.copyfile(prefix/name,evidence/name)
            passed=True
        else:
            runtime=manifest["runtime_python"];bundle=manifest["environment_bundle"]
            if not Path(runtime).is_absolute() or not runtime.endswith("/runtime/venv/bin/python") or not Path(bundle).is_absolute():
                raise ValueError("verified interpreter/bundle path required")
            subprocess.run([runtime,"-B","-m","pricefm_hb.environment","verify-runtime","--bundle",bundle,
                "--report",str(outputs/"environment-runtime.json")],env=env,check=True,timeout=120)
            runtime_report=r.read(outputs/"environment-runtime.json")
            if manifest.get("numerical_profile"):
                validate_reference_profile_record(runtime_report["reference_numerical_profile"])
            r.write(outputs/"native-library-sha256.json",{pool["filepath"]:r.digest(pool["filepath"]) for pool in runtime_report["threadpoolctl"]})
            subprocess.run([runtime,"-B","-m","pricefm_hb.science",str(release/"fixture/manifest.json"),
                str(outputs/"TEST/parity")],env=env,check=True,timeout=manifest["limits"]["wall_seconds"]-150)
            parity=r.read(outputs/"TEST/parity/parity.json")
            if parity.get("status")!="PASS_TEST_FORECAST_PARITY" or parity.get("accepted") is not True:
                raise ValueError("complete parity not accepted")
            passed=True
    except Exception as exc:
        error={"type":type(exc).__name__,"message":str(exc)}
        r.write(outputs/"worker-failure.json",error)
        prefix=release/"runtime"
        if kind=="environment" and prefix.exists():
            evidence=outputs/"environment-evidence";evidence.mkdir(exist_ok=True)
            for path in prefix.glob("*.log"):
                shutil.copyfile(path,evidence/path.name)
    safe_tree(outputs)
    files={str(p.relative_to(outputs)):r.digest(p) for p in sorted(outputs.rglob("*")) if p.is_file()}
    r.write(outputs/"completed_evidence.json",{"schema":r.SCHEMA,"task_key":r.identity(manifest["task"]),
        "release_sha256":expected_sha,"job_id":allocation["job_id"],"allocation":allocation,
        "application_passed":passed,"kind":kind,"error":error,"files":files,"fits":0,"official_origins":0})
    if not passed:raise RuntimeError("qualification failed; outputs and accounting retained")
    return {"status":"PASS_QUALIFICATION","kind":kind}


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument("--release",required=True);p.add_argument("--release-sha256",required=True)
    a=p.parse_args();print(execute(a.release,a.release_sha256))


if __name__=="__main__":main()
