"""Python3.6-compatible bootstrap: verify transmitted source bytes before exec."""
import base64
import hashlib
import json
import math
import re
import resource
import signal
import sys

def require(value, reason):
    if not value:
        raise ValueError(reason)

def unique_pairs(values):
    result = {}
    for key, value in values:
        require(key not in result, "duplicate plan key")
        result[key] = value
    return result

def finite_float(text):
    value = float(text)
    require(math.isfinite(value), "nonfinite plan float")
    return value

def verified_payload(source_base64, expected_sha256, plan_base64):
    require(re.fullmatch(r"[0-9a-f]{64}", expected_sha256), "exact reviewed sourceSHA256 required")
    raw = base64.b64decode(source_base64, validate=True)
    require(0 < len(raw) <= 131072 and hashlib.sha256(raw).hexdigest() == expected_sha256,
            "actual transmitted collector source bytes differ")
    plan_raw = base64.b64decode(plan_base64, validate=True)
    require(len(plan_raw) <= 2097152, "plan byte cap")
    def bad_constant(value):
        raise ValueError("nonfinite plan constant")
    plan = json.loads(plan_raw, object_pairs_hook=unique_pairs, parse_float=finite_float, parse_constant=bad_constant)
    require(plan.get("collector_source_sha256") == expected_sha256, "plan and verified source differ")
    return raw

def main():
    resource.setrlimit(resource.RLIMIT_CPU, (6, 6))
    signal.alarm(120)
    require(len(sys.argv) == 4, "sourceBASE64 reviewedSOURCE_SHA256 planBASE64 required")
    source, expected, plan = sys.argv[1:]
    raw = verified_payload(source, expected, plan)
    namespace = {"__name__": "__main__", "__file__": "<pricefm-verified-collector-" + expected + ">",
                 "_PRICEFM_VERIFIED_COLLECTOR_SOURCE_SHA256": expected}
    sys.argv = [namespace["__file__"], "--collect-plan-base64", plan]
    exec(compile(raw, namespace["__file__"], "exec"), namespace)

if __name__ == "__main__":
    main()
