#!/usr/bin/env python3

import argparse
import csv
import os
import pathlib
import subprocess


def parse_args():
    parser = argparse.ArgumentParser(description="Select physical CPUs not occupied by pinned active work.")
    parser.add_argument("--count", type=int, default=20)
    parser.add_argument("--min-pcpu", type=float, default=10.0)
    parser.add_argument("--report", default="")
    return parser.parse_args()


def cpu_topology():
    output = subprocess.check_output(
        ["lscpu", "-p=CPU,CORE,SOCKET,NODE,ONLINE"],
        universal_newlines=True,
    )
    allowed = set(os.sched_getaffinity(0))
    by_core = {}
    cpu_to_core = {}
    for line in output.splitlines():
        if not line or line.startswith("#"):
            continue
        cpu, core, socket, node, online = line.split(",")
        cpu = int(cpu)
        if online.strip().upper() != "Y" or cpu not in allowed:
            continue
        key = (int(socket), int(node), int(core))
        by_core.setdefault(key, []).append(cpu)
        cpu_to_core[cpu] = key
    representatives = {key: min(cpus) for key, cpus in by_core.items()}
    cpu_to_representative = {
        cpu: representatives[key]
        for cpu, key in cpu_to_core.items()
    }
    return [representatives[key] for key in sorted(representatives)], cpu_to_representative


def pinned_active_cpus(min_pcpu, cpu_to_representative):
    output = subprocess.check_output(
        ["ps", "-eo", "pid=,pcpu=,comm=,args="],
        universal_newlines=True,
    )
    all_allowed = set(os.sched_getaffinity(0))
    occupied = set()
    evidence = []
    for line in output.splitlines():
        fields = line.strip().split(None, 3)
        if len(fields) < 3:
            continue
        try:
            pid = int(fields[0])
            pcpu = float(fields[1])
        except ValueError:
            continue
        if pid == os.getpid() or pcpu < min_pcpu:
            continue
        try:
            affinity = set(os.sched_getaffinity(pid))
        except (ProcessLookupError, PermissionError):
            continue
        if not affinity or affinity == all_allowed or len(affinity) > 4:
            continue
        occupied.update(
            cpu_to_representative[cpu]
            for cpu in affinity
            if cpu in cpu_to_representative
        )
        evidence.append({
            "pid": pid,
            "pcpu": pcpu,
            "command": fields[2],
            "args": fields[3] if len(fields) > 3 else "",
            "affinity": ",".join(str(cpu) for cpu in sorted(affinity)),
        })
    return occupied, evidence


def main():
    args = parse_args()
    if args.count < 1:
        raise ValueError("count must be positive")
    candidates, cpu_to_representative = cpu_topology()
    occupied, evidence = pinned_active_cpus(args.min_pcpu, cpu_to_representative)
    selected = [cpu for cpu in candidates if cpu not in occupied][:args.count]
    if not selected:
        raise RuntimeError("No unoccupied physical CPU was found")
    if args.report:
        path = pathlib.Path(args.report).resolve()
        path.parent.mkdir(parents=True, exist_ok=True)
        rows = evidence or [{"pid": "", "pcpu": "", "command": "", "args": "", "affinity": ""}]
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
            writer.writeheader()
            writer.writerows(rows)
    print(",".join(str(cpu) for cpu in selected))


if __name__ == "__main__":
    main()
