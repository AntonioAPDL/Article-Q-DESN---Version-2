"""Source-bound startup adapter for the r176 conservative-stop candidate only.

The frozen adapter is loaded in a private module and retains every gate.  The
source closure explicitly adds the candidate and both frozen originals.  R
startup cannot finalize using a receipt from a different supervision profile.
"""
import hashlib
import importlib.util
from pathlib import Path
import sys

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).absolute().parents[1]))
from pricefm_hb import startup_stop_candidate as candidate

ORIGINAL_ADAPTER_SHA256 = "8833cb4af5c8e5037ad6ed9e86dbed7955a8cbbe77d97c72dd7d74ca733f882b"
_path = Path(__file__).absolute().with_name("startup_helper.py")
candidate.verified_original()
candidate.require(not any(p.is_symlink() for p in (_path, *_path.parents)), "canonical frozen adapter required")
_raw = _path.read_bytes()
candidate.require(hashlib.sha256(_raw).hexdigest() == ORIGINAL_ADAPTER_SHA256,
                  "frozen startup adapter bytes differ")
_spec = importlib.util.spec_from_file_location("_pricefm_r176_original_startup_adapter", _path)
_base = importlib.util.module_from_spec(_spec)
exec(compile(_raw, str(_path), "exec"), _base.__dict__)
_source_pins = _base.source_pins
_finalize = _base.finalize


def source_pins(role):
    result = _source_pins(role)
    result.update(original_supervisor=result["supervisor"], original_adapter=result["adapter"],
                  adapter=_base.pin(Path(__file__).absolute()),
                  supervisor=_base.pin(Path(__file__).absolute().with_name("startup_stop_candidate.py")))
    return result


def finalize(plan_pin, authority_pin, review_pin, guard_pin):
    candidate.require_candidate_receipt(_base.read(guard_pin))
    return _finalize(plan_pin, authority_pin, review_pin, guard_pin)


_base.source_pins = source_pins
_base.finalize = finalize


def __getattr__(name):
    return getattr(_base, name)


def main(argv=None):
    return _base.main(argv)


if __name__ == "__main__":
    main()
