#!/usr/bin/env python3
"""Focused tests for physical-core post-Search-II worker allocation."""

import importlib.util
import json
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


resources = load(
    "glofas_post_search2_resources_test",
    ROOT / "application/scripts/glofas_post_search2_resources.py",
)
launcher = load(
    "glofas_post_search2_launcher_resources_test",
    ROOT / "application/scripts/405_launch_glofas_post_search2_dag.py",
)


topology = {}
for cpu in range(64):
    base = cpu % 32
    socket = base // 8
    topology[cpu] = {
        "cpu": cpu,
        "core": base,
        "socket": socket,
        "node": socket,
        "online": True,
    }

assert resources.parse_cpu_pool("0-2,4,6-7") == [0, 1, 2, 4, 6, 7]
contract = resources.validate_worker_resources(
    25, "0-24", topology=topology, allowed_cpus=set(range(64))
)
assert contract["active_cpu_pool"] == list(range(25))
assert contract["active_physical_core_count"] == 25
assert contract["pool_physical_core_count"] == 25
assert contract["socket_distribution"] == {"0": 8, "1": 8, "2": 8, "3": 1}
assert contract["smt_siblings_used"] is False

for workers, pool, phrase in (
    (3, "0-1", "exceeds"),
    (2, "0,0", "duplicate"),
    (2, "0,32", "SMT siblings"),
):
    try:
        resources.validate_worker_resources(
            workers, pool, topology=topology, allowed_cpus=set(range(64))
        )
    except ValueError as exc:
        assert phrase in str(exc)
    else:
        raise AssertionError(f"invalid resource contract was accepted: {workers}, {pool}")

try:
    resources.validate_worker_resources(
        1, "7", topology=topology, allowed_cpus={0, 1, 2}
    )
except ValueError as exc:
    assert "affinity mask" in str(exc)
else:
    raise AssertionError("CPU outside the process affinity mask was accepted")

with tempfile.TemporaryDirectory(prefix="glofas_post_search2_resources_") as tmp:
    runtime = Path(tmp)
    (runtime / "scripts").mkdir()
    for job_id, cpu in (("job_a", 0), ("job_b", 1)):
        (runtime / "scripts" / f"{job_id}.resource.json").write_text(
            json.dumps({"job_id": job_id, "cpu": cpu}), encoding="utf-8"
        )
    assigned = launcher.read_active_assignments(
        runtime, {"job_a", "job_b"}, contract
    )
    assert assigned == {0: "job_a", 1: "job_b"}

    (runtime / "scripts" / "job_b.resource.json").write_text(
        json.dumps({"job_id": "job_b", "cpu": 0}), encoding="utf-8"
    )
    try:
        launcher.read_active_assignments(runtime, {"job_a", "job_b"}, contract)
    except SystemExit as exc:
        assert "share CPU" in str(exc)
    else:
        raise AssertionError("duplicate active CPU assignment was accepted")

print("GLOFAS_POST_SEARCH2_RESOURCES_TEST_PASS")
