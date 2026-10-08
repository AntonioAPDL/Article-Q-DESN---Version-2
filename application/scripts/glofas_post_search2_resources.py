#!/usr/bin/env python3
"""Physical-core resource contracts for post-Search-II GloFAS runs."""

import csv
import io
import os
import shutil
import subprocess
from collections import Counter


def parse_cpu_pool(spec):
    cpus = []
    for token in str(spec).split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            parts = token.split("-")
            if len(parts) != 2:
                raise ValueError(f"invalid CPU range: {token}")
            start, end = (int(value) for value in parts)
            if start < 0 or end < start:
                raise ValueError(f"invalid CPU range: {token}")
            cpus.extend(range(start, end + 1))
        else:
            value = int(token)
            if value < 0:
                raise ValueError(f"invalid CPU ID: {token}")
            cpus.append(value)
    if not cpus:
        raise ValueError("CPU pool is empty")
    if len(cpus) != len(set(cpus)):
        raise ValueError("CPU pool contains duplicate logical CPUs")
    return cpus


def read_cpu_topology(output=None):
    if output is None:
        output = subprocess.check_output(
            ["lscpu", "-p=CPU,CORE,SOCKET,NODE,ONLINE"],
            universal_newlines=True,
        )
    rows = {}
    data = "\n".join(line for line in output.splitlines() if line and not line.startswith("#"))
    for row in csv.reader(io.StringIO(data)):
        if len(row) != 5:
            raise ValueError(f"invalid lscpu topology row: {row}")
        cpu, core, socket, node = (int(value) for value in row[:4])
        rows[cpu] = {
            "cpu": cpu,
            "core": core,
            "socket": socket,
            "node": node,
            "online": row[4].strip().upper() in {"Y", "YES", "1"},
        }
    if not rows:
        raise ValueError("lscpu returned no CPU topology rows")
    return rows


def validate_worker_resources(workers, cpu_pool_spec, topology=None, allowed_cpus=None):
    workers = int(workers)
    if workers < 1:
        raise ValueError("worker capacity must be positive")
    topology = read_cpu_topology() if topology is None else topology
    cpus = parse_cpu_pool(cpu_pool_spec)
    if workers > len(cpus):
        raise ValueError("worker capacity exceeds the CPU pool")
    if allowed_cpus is None and hasattr(os, "sched_getaffinity"):
        allowed_cpus = os.sched_getaffinity(0)
    if allowed_cpus is not None:
        unavailable = sorted(set(cpus) - set(allowed_cpus))
        if unavailable:
            raise ValueError(f"CPU pool is outside the process affinity mask: {unavailable}")
    selected = []
    physical = set()
    for cpu in cpus:
        if cpu not in topology:
            raise ValueError(f"CPU {cpu} is absent from the host topology")
        row = topology[cpu]
        if not row["online"]:
            raise ValueError(f"CPU {cpu} is offline")
        identity = (row["socket"], row["core"])
        if identity in physical:
            raise ValueError(
                f"CPU pool contains SMT siblings for physical core {identity}"
            )
        physical.add(identity)
        selected.append(dict(row))
    if shutil.which("taskset") is None:
        raise ValueError("taskset is required for physical-core affinity")
    sockets = Counter(row["socket"] for row in selected[:workers])
    return {
        "schema_version": "glofas_post_search2_physical_cpu_pool_v1",
        "worker_capacity": workers,
        "cpu_pool_spec": str(cpu_pool_spec),
        "logical_cpu_pool": cpus,
        "active_cpu_pool": cpus[:workers],
        "pool_physical_core_count": len(physical),
        "active_physical_core_count": workers,
        "socket_distribution": {str(key): sockets[key] for key in sorted(sockets)},
        "topology": selected,
        "thread_policy": "one_process_one_thread_one_physical_core",
        "smt_siblings_used": False,
    }
