"""Bounded Slurm qualification controller; no production task submission API."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import time
import uuid
from . import registry as r

TOKEN = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]*\Z")


def config(path):
    c = r.read(path)
    if c.get("host") != "hb.ucsc.edu" or c.get("user") != "jaguir26" or c.get("account") != "128x24" or c.get("partition") != "128x24" or c.get("qos") != "normal":
        raise ValueError("only the verified HB qualification association is supported")
    for key in ("known_hosts_file", "ssh_identity_file"):
        if not Path(c[key]).is_absolute() or not r.no_links(c[key]).is_file():
            raise ValueError("missing configured private identity/host trust file")
    root = c.get("remote_root", "")
    if not re.fullmatch(r"(?:/home|/mnt/beegfs/home)/jaguir26/[A-Za-z0-9_/-]+", root) or ".." in Path(root).parts:
        raise ValueError("new verified home namespace required")
    return c


def ssh(c):
    return ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "UpdateHostKeys=no",
            "-o", "CheckHostIP=no", "-o", "ControlMaster=no", "-o", "ControlPath=none",
            "-o", "IdentitiesOnly=yes", "-o", "IdentityAgent=none", "-o", "ForwardAgent=no",
            "-o", "ClearAllForwardings=yes", "-o", "PreferredAuthentications=publickey",
            "-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no",
            "-o", "ConnectTimeout=10", "-o", "ConnectionAttempts=1", "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2", "-o", "UserKnownHostsFile="+c["known_hosts_file"],
            "-i", c["ssh_identity_file"], c["user"]+"@"+c["host"]]


def run(argv, timeout=120):
    p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    if p.returncode:
        raise RuntimeError("command failed (%s): %s" % (p.returncode, p.stderr[-4000:]))
    return p.stdout


def remote(c, args):
    return run(ssh(c)+[shlex.join(args)])


def safe_tree(path):
    path = r.no_links(path)
    if path.exists() and any(p.is_symlink() or (not p.is_dir() and not p.is_file()) for p in path.rglob("*")):
        raise ValueError("only regular files/directories may be staged or retrieved")
    return path


def seal_release(root, task, command, limits, **execution):
    """Seal an already populated allowlisted payload; never recurse outside root."""
    root = safe_tree(root)
    if set(execution)-{"runtime_python","environment_bundle","numerical_profile"}:
        raise ValueError("unreviewed execution metadata")
    if any((root/name).exists() for name in ("outputs","logs","runtime")):
        raise ValueError("new immutable payload namespace required")
    if task.get("kind") not in r.KINDS or task.get("namespace") != "TEST":
        raise ValueError("not a qualification task")
    if not command or any(not isinstance(s, str) or "\n" in s or "\x00" in s for s in command):
        raise ValueError("invalid reviewed command")
    if (root/"release.json").exists():
        raise FileExistsError("release already sealed")
    for p in root.rglob("*"):
        if {".ssh", ".git", ".codex"} & set(p.relative_to(root).parts):
            raise ValueError("credential/Git/agent directories are excluded")
    files = {str(p.relative_to(root)): {"sha256": r.digest(p), "bytes": p.stat().st_size}
             for p in sorted(root.rglob("*")) if p.is_file()}
    manifest = {"schema": r.SCHEMA, "release_id": "r156-"+uuid.uuid4().hex,
                "task": task, "command": command, "limits": limits, "files": files,
                "scientific_fits": 0, "official_origins": 0, **execution}
    r.write(root/"release.json", manifest)
    return manifest


def verify_release(root):
    root = safe_tree(root); m = r.read(root/"release.json")
    if m.get("schema") != r.SCHEMA or m.get("task", {}).get("namespace") != "TEST" or m["task"]["kind"] not in r.KINDS:
        raise ValueError("unsupported release")
    if not re.fullmatch(r"r156-[0-9a-f]{32}", m.get("release_id", "")):
        raise ValueError("invalid release ID")
    # Remote output/runtime directories are created only after admission. The
    # immutable release verifier permits those explicitly, never arbitrary files.
    observed = {str(p.relative_to(root)) for p in root.rglob("*") if p.is_file() and p.relative_to(root).parts[0] not in {"outputs","logs","runtime"}}
    if observed != set(m["files"]) | {"release.json"}:
        raise ValueError("release membership changed")
    for name, meta in m["files"].items():
        if Path(name).is_absolute() or ".." in Path(name).parts:
            raise ValueError("unsafe release member")
        p = root/name
        if r.digest(p) != meta["sha256"] or p.stat().st_size != meta["bytes"]:
            raise ValueError("release digest changed: "+name)
    return m


def stage_and_submit(registry_root, config_path, authority_path, release_root):
    c = config(config_path); a = r.read(authority_path); m = verify_release(release_root)
    r.validate_authority(a)
    if m["limits"] != {k: a["jobs"][m["task"]["kind"]][k] for k in ("cpus", "memory_MiB", "wall_seconds")}:
        raise ValueError("admitted and staged resources differ")
    # Existing HB work must be counted; this first qualification is serial.
    if remote(c, ["squeue", "-h", "-u", c["user"], "-o", "%i"]).strip():
        raise ValueError("another HB job exists; defer qualification")
    reg = r.Registry(registry_root)
    claim = reg.reserve(a, m["task"], r.digest(Path(release_root)/"release.json"))
    key = claim["task_key"]; target = c["remote_root"]+"/"+m["release_id"]
    try:
        remote(c, ["mkdir", "-p", c["remote_root"]])
        remote(c, ["mkdir", target])  # no overwrite/resubmission path
        run(["rsync", "-rlt", "--checksum", "--partial", "--delay-updates", "--no-links", "-e", shlex.join(ssh(c)[:-1]),
             str(Path(release_root).absolute())+"/", c["user"]+"@"+c["host"]+":"+target+"/"], timeout=180)
        observed = remote(c, ["sha256sum", target+"/release.json"]).split()[0]
        if observed != claim["release_sha256"]:
            raise ValueError("remote staged manifest differs")
        remote(c, ["mkdir", target+"/outputs", target+"/logs"])
        reg.transition(key, "RESERVED", "STAGED", remote_root=target, config_sha256=r.identity(c), release_path=str(Path(release_root).absolute()))
    except Exception as e:
        reg.transition(key, "RESERVED", "AMBIGUOUS", diagnostic="stage interrupted: "+str(e), remote_root=target)
        raise
    limits = m["limits"]
    seconds = limits["wall_seconds"]; wall = "%02d:%02d:%02d" % (seconds//3600, seconds%3600//60, seconds%60)
    argv = ["sbatch", "--parsable", "--export=NONE", "--nodes=1", "--ntasks=1", "--cpus-per-task=1", "--no-requeue",
            "--mem="+str(limits["memory_MiB"])+"M", "--time="+wall,
            "--account="+c["account"], "--partition="+c["partition"], "--qos="+c["qos"],
            "--job-name="+m["release_id"], "--chdir="+target,
            "--output="+target+"/logs/%j.out", "--error="+target+"/logs/%j.err", target+"/job.sh", target, claim["release_sha256"]]
    reg.transition(key, "STAGED", "SUBMISSION_INTENT", submission_argv=argv)
    try:
        response = remote(c, argv).strip()
        if not re.fullmatch(r"[1-9][0-9]*(?:;[A-Za-z0-9_.-]+)?", response):
            raise ValueError("ambiguous sbatch response")
    except Exception as e:
        reg.transition(key, "SUBMISSION_INTENT", "AMBIGUOUS", diagnostic="submission may have reached Slurm: "+str(e))
        raise
    return reg.transition(key, "SUBMISSION_INTENT", "SUBMITTED", job_id=response.split(";", 1)[0], response=response)


def cpu_seconds(value):
    match = re.fullmatch(r"(?:(\d+)-)?(?:(\d+):)?(\d\d):(\d\d(?:\.\d+)?)", value)
    if not match: raise ValueError("invalid accounting CPU time")
    days, hours, minutes, seconds = match.groups()
    if int(minutes)>=60 or float(seconds)>=60: raise ValueError("invalid accounting CPU fields")
    return int(days or 0)*86400+int(hours or 0)*3600+int(minutes)*60+float(seconds)


def accounting(text, job_id, limits):
    rows = [line.split("|") for line in text.splitlines() if line.strip()]
    allowed = {job_id, job_id+".batch", job_id+".extern", job_id+".0"}
    seen = set(); result = {"complete": False, "terminal": False, "rows": rows}
    terminal = {"COMPLETED", "FAILED", "CANCELLED", "TIMEOUT", "OUT_OF_MEMORY", "NODE_FAIL", "PREEMPTED", "BOOT_FAIL", "DEADLINE"}
    if not rows: return result
    for row in rows:
        if len(row)!=8 or row[0] not in allowed or row[0] in seen: raise ValueError("unexpected/duplicate accounting row")
        seen.add(row[0])
        if not re.fullmatch(r"\d+:\d+", row[2]): raise ValueError("invalid exit code")
        elapsed, cpus = int(row[3]), int(row[4]); cpu = cpu_seconds(row[5])
        if elapsed<0 or elapsed>limits["wall_seconds"]+60 or cpus not in (0,1) or cpu>limits["wall_seconds"]+60:
            raise ValueError("allocation outside admitted bounds")
        if row[0] in {job_id, job_id+".0"} and cpus!=1: raise ValueError("one allocated CPU required")
        if row[6]:
            rss = re.fullmatch(r"(\d+(?:\.\d+)?)([KMGTP]?)", row[6])
            if not rss: raise ValueError("invalid MaxRSS")
            factor={"":1,"K":1,"M":1024,"G":1024**2,"T":1024**3,"P":1024**4}[rss[2]]
            if float(rss[1])*factor>limits["memory_MiB"]*1024: raise ValueError("RSS exceeds admitted memory")
    result["terminal"] = job_id in seen and all(row[1].split()[0] in terminal for row in rows)
    result["complete"] = {job_id, job_id+".batch", job_id+".0"} <= seen and all(row[1]=="COMPLETED" and row[2]=="0:0" for row in rows)
    return result


def status(registry_root, config_path, key, receipt_path):
    c = config(config_path); reg = r.Registry(registry_root); claim = reg.poll(key)
    if claim["config_sha256"] != r.identity(c): raise ValueError("configuration changed")
    m = verify_release(claim["release_path"]); job = claim["job_id"]
    if r.digest(Path(claim["release_path"])/"release.json")!=claim["release_sha256"]:
        raise ValueError("admitted local release changed")
    # Completed jobs may already be purged from squeue's in-memory cache;
    # querying an explicit purged ID returns an error on this Slurm version.
    # A bounded own-user queue query avoids interpreting that error as success.
    own_queue = remote(c, ["squeue", "-h", "-u", c["user"], "-o", "%i|%T|%R"])
    sq = "\n".join(line for line in own_queue.splitlines() if line.split("|",1)[0] == job)
    sa = remote(c, ["sacct", "-nP", "--units=K", "-j", job, "--format=JobID,State%30,ExitCode,ElapsedRaw,AllocCPUS,TotalCPU,MaxRSS,NodeList"])
    parsed = accounting(sa, job, m["limits"])
    result = {"task_key": key, "job_id": job, "checked": time.time(), "release_sha256": claim["release_sha256"],
              "squeue": sq, "own_queue": own_queue, "sacct": sa, "complete": not sq.strip() and parsed["complete"], "terminal": not sq.strip() and parsed["terminal"]}
    receipt_path = r.no_links(receipt_path)
    if receipt_path.exists(): raise FileExistsError("use a new receipt path")
    r.write(receipt_path, result)
    return result


def validate_outputs(outputs, claim, manifest):
    outputs=safe_tree(outputs);seal=r.read(outputs/"completed_evidence.json")
    if (seal.get("schema")!=r.SCHEMA or seal.get("task_key")!=claim["task_key"] or
            seal.get("release_sha256")!=claim["release_sha256"] or seal.get("job_id")!=claim["job_id"] or
            seal.get("kind")!=manifest["task"]["kind"] or seal.get("fits")!=0 or seal.get("official_origins")!=0):
        raise ValueError("output provenance mismatch")
    files=seal["files"]
    observed={str(p.relative_to(outputs)) for p in outputs.rglob("*") if p.is_file() and p!=outputs/"completed_evidence.json"}
    if observed!=set(files):raise ValueError("unsealed/missing output files")
    for name,sha in files.items():
        if Path(name).is_absolute() or ".." in Path(name).parts or r.digest(outputs/name)!=sha:raise ValueError("output checksum mismatch")
    allocation=seal.get("allocation",{})
    if allocation.get("job_id")!=claim["job_id"] or allocation.get("cpus_per_task")!=1 or len(allocation.get("affinity",[]))!=1:
        raise ValueError("output allocation mismatch")
    return seal


def collect(registry_root, config_path, key, receipt_path, incoming, destination):
    c = config(config_path); reg = r.Registry(registry_root); claim = reg.snapshot()["claims"][key]
    if claim["state"]!="SUBMITTED" or claim["config_sha256"]!=r.identity(c): raise ValueError("claim/configuration mismatch")
    m=verify_release(claim["release_path"]); receipt=r.read(receipt_path)
    if r.digest(Path(claim["release_path"])/"release.json")!=claim["release_sha256"]:
        raise ValueError("admitted local release changed")
    if receipt.get("task_key")!=key or receipt.get("job_id")!=claim["job_id"] or receipt.get("release_sha256")!=claim["release_sha256"]:
        raise ValueError("accounting identity mismatch")
    parsed=accounting(receipt["sacct"], claim["job_id"], m["limits"])
    if receipt["squeue"].strip() or not parsed["terminal"]: raise ValueError("incomplete/unknown work retains its claim")
    incoming=safe_tree(incoming); destination=r.no_links(destination)
    if destination.exists(): raise FileExistsError("publication is create-only")
    incoming.mkdir(parents=True,exist_ok=True)
    if set(p.name for p in incoming.iterdir())-{"outputs","logs","accounting.json","release.json"}: raise ValueError("unrelated incoming data")
    for name in ("outputs", "logs"):
        (incoming/name).mkdir(exist_ok=True)
        run(["rsync","-rlt","--partial","--delay-updates","--safe-links","--no-links","-e",shlex.join(ssh(c)[:-1]),
             c["user"]+"@"+c["host"]+":"+claim["remote_root"]+"/"+name+"/",str((incoming/name).absolute())+"/"],timeout=180)
    safe_tree(incoming)
    r.write(incoming/"accounting.json", receipt); shutil.copyfile(Path(claim["release_path"])/"release.json",incoming/"release.json")
    # Application acceptance is independent of scheduler completion.
    accepted=False
    if parsed["complete"]:
        seal=validate_outputs(incoming/"outputs",claim,m)
        if m["task"]["kind"]=="environment":
            report=r.read(incoming/"outputs"/"build-report.json")
            accepted=seal.get("application_passed") is True and report.get("schema")=="pricefm-hb-environment-v1" and report.get("status")=="verified"
            if accepted:
                runtime=r.read(incoming/"outputs/environment-evidence/runtime-verification.json")
                artifacts=incoming/"outputs/environment-evidence/interpreter-artifact-manifest.json"
                if (runtime.get("status")!="verified" or runtime.get("python_version")!="3.11.13" or
                        runtime.get("allocation")!=seal["allocation"] or report["allocation"]!=seal["allocation"] or
                        report["interpreter_artifacts"]["manifest_sha256"]!=r.digest(artifacts) or
                        runtime["bundle"]["manifest_sha256"]!=m["files"]["env/wheel-manifest.json"]["sha256"] or
                        not runtime["threadpoolctl"] or any(p.get("num_threads")!=1 for p in runtime["threadpoolctl"])):
                    raise ValueError("locked environment evidence mismatch")
        else:
            report=r.read(incoming/"outputs"/"TEST/parity/parity.json")
            accepted=seal.get("application_passed") is True and report.get("status")=="PASS_TEST_FORECAST_PARITY" and report.get("accepted") is True
            if accepted and m.get("numerical_profile"):
                from .environment import validate_reference_profile_record
                validate_reference_profile_record(r.read(incoming/"outputs/environment-runtime.json")["reference_numerical_profile"])
    destination.parent.mkdir(parents=True,exist_ok=True)
    tmp=destination.parent/(".hb-incoming-"+uuid.uuid4().hex)
    try:
        shutil.copytree(incoming,tmp,symlinks=True);safe_tree(tmp)
        if parsed["complete"]:validate_outputs(tmp/"outputs",claim,m)
        with r.lock(destination.parent/"publication.lock"):
            if destination.exists():raise FileExistsError("publication already exists")
            tmp.rename(destination)
    finally:
        if tmp.exists():shutil.rmtree(tmp)
    target="COLLECTED" if parsed["complete"] and accepted else "FAILED_RECONCILED"
    return reg.transition(key,"SUBMITTED",target,publication=str(destination.absolute()),application_accepted=accepted,accounting_path=str(Path(receipt_path).absolute()))


def main():
    p=argparse.ArgumentParser(description=__doc__);s=p.add_subparsers(dest="action",required=True)
    for name in ("submit","status","collect"):
        q=s.add_parser(name);q.add_argument("--registry",required=True);q.add_argument("--config",required=True)
        if name=="submit":q.add_argument("--authority",required=True);q.add_argument("--release",required=True)
        else:q.add_argument("--key",required=True);q.add_argument("--receipt",required=True)
        if name=="collect":q.add_argument("--incoming",required=True);q.add_argument("--destination",required=True)
    a=p.parse_args()
    if a.action=="submit":out=stage_and_submit(a.registry,a.config,a.authority,a.release)
    elif a.action=="status":out=status(a.registry,a.config,a.key,a.receipt)
    else:out=collect(a.registry,a.config,a.key,a.receipt,a.incoming,a.destination)
    print(json.dumps(out,sort_keys=True,indent=2,allow_nan=False))


if __name__=="__main__":main()
