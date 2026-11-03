"""One fixed compute child: authenticate/compile, actual native ACK, fixed run4.

Six CLI values are exact spec/authority/source-review path/SHA pins. This module
does not import any numerical kernel, R interface, target loader or native FFI.
The reviewed native_contract is interpreted only from exact captured bytes.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import sys

def _require(condition, message):
    if not condition:
        raise ValueError(message)

def _first_job():
    # Must run before command-line records or any supplied source/library opens.
    job = os.environ.get("SLURM_JOB_ID", "")
    _require(re.fullmatch("[1-9][0-9]{0,19}", job), "actual Slurm child required before records")
    text = Path("/proc/self/status").read_text()
    match = re.search(r"^TracerPid:\s*([0-9]+)$", text, re.M)
    cgroup = Path("/proc/self/cgroup").read_text()
    _require(match is not None and int(match.group(1)) == os.getppid()
             and "slurm" in cgroup
             and re.search(r"(?:^|/)job_" + re.escape(job) + r"(?:/|\n|$)", cgroup),
             "actual parent-owned Slurm ptrace required")

def _physical(value):
    _require(type(value) is str and value.startswith("/") and "\x00" not in value,
             "absolute physical source/metadata path")
    p = Path(value)
    _require(str(p) == value and ".." not in p.parts
             and not any(x.is_symlink() for x in (p, *p.parents)), "no source/metadata aliases")
    return p

def _captured(pin):
    _require(type(pin) is dict and set(pin) == {"path", "sha256"}
             and type(pin["sha256"]) is str and re.fullmatch("[0-9a-f]{64}", pin["sha256"]),
             "exact input pin")
    p = _physical(pin["path"])
    fd = os.open(p, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        before = os.fstat(stream.fileno())
        _require(stat.S_ISREG(before.st_mode) and before.st_uid == os.getuid()
                 and before.st_nlink == 1 and before.st_size <= 2 * 1024**2,
                 "bounded owned physical source")
        raw = stream.read(2 * 1024**2 + 1)
        after = os.fstat(stream.fileno())
    fields = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns, s.st_uid, s.st_nlink)
    _require(fields(before) == fields(after) == fields(p.stat())
             and len(raw) == before.st_size
             and hashlib.sha256(raw).hexdigest() == pin["sha256"], "stable exact authenticated bytes")
    return raw

def _json(raw):
    def pairs(items):
        value = {}
        for key, item in items:
            _require(key not in value, "duplicate JSON key")
            value[key] = item
        return value
    return json.loads(raw, object_pairs_hook=pairs,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite JSON")))

def _module(code, path, name):
    description = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(description)
    sys.modules[name] = module
    exec(code, module.__dict__)
    return module

def main(argv=None):
    _first_job()
    args = sys.argv[1:] if argv is None else argv
    _require(len(args) == 6, "six exact pin arguments")
    spec_pin, authority_pin, review_pin = (
        {"path": args[i], "sha256": args[i + 1]} for i in (0, 2, 4))
    review = _json(_captured(review_pin))
    pins = review.get("source_pins", {})
    self_pin = pins.get("native_python/python_bootstrap.py")
    contract_pin = pins.get("native_python/native_contract.py")
    root = Path(__file__).absolute().parent.parent
    _require(self_pin is not None and self_pin["path"] == str(root / "native_python/python_bootstrap.py")
             and contract_pin is not None
             and contract_pin["path"] == str(root / "native_python/native_contract.py"),
             "fixed reviewed bootstrap and native contract")
    _captured(self_pin)
    raw_contract = _captured(contract_pin)
    native = _module(compile(raw_contract, contract_pin["path"], "exec"),
                     contract_pin["path"], "_pricefm_r201_native_contract")
    handle = native.prepare(spec_pin, authority_pin, review_pin)
    context = handle._context
    spec = context["spec"]
    # preflight has compiled every pinned Python source and authenticated all
    # other source bytes. It has not evaluated R/C or a numerical kernel.
    frame = {"status": "R200_PINNED_SOURCE_PARSE_PASS_BEFORE_ENTRYPOINT",
             "purpose": spec["purpose"], "nonce": spec["nonce"], "role": spec["role"],
             "job_id": spec["job_id"], "node": spec["node"],
             "source_pins": context["review"]["source_pins"],
             "optimizer_invocations": 0, "scientific_target_data_read": False}
    print(json.dumps(frame, sort_keys=True, separators=(",", ":")), flush=True)
    handle.cross_once()  # Actual original TSYNC/proof/parent ACK; no callback.
    handle.verify_live()
    ack_pin = native.pin_file(spec["acknowledgement_path"])
    ack = native.linked(ack_pin)
    native.require(ack.get("spec") == spec_pin and ack.get("authority") == authority_pin
                   and ack.get("source_review") == review_pin
                   and ack.get("child") == {"pid": os.getpid(),
                       "start_ticks": native._proc(os.getpid())["start_ticks"]},
                   "same exact actual parent parse gate after native ACK")
    relative = ("qualification/qualification_entry.py" if spec["role"] == native.INITIAL
                else "regional_reference/reference_compute.py")
    # Execute only the already captured and compiled fixed selected source.
    entry = _module(context["compiled"][relative],
                    context["review"]["source_pins"][relative]["path"], "_pricefm_r201_fixed_entry")
    handle.verify_live()
    result = entry.run(spec_pin, authority_pin, review_pin, ack_pin)
    handle.verify_live()
    writer_key = "owner/reference_return.py"
    writer = _module(context["compiled"][writer_key],
                     context["review"]["source_pins"][writer_key]["path"], "_pricefm_r201_fixed_writer")
    writer.write_parts(spec_pin, authority_pin, review_pin, ack_pin, result)
    handle.verify_live()
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
