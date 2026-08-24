"""Shared contracts for the PriceFM operational full-shot benchmark."""

from __future__ import annotations

import ast
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import time
from typing import Any, Iterable


QUANTILES = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]
RAW_SHA256 = "98f596deba7ffaf0edd21e78e1a779256ab24dda5463d445f081e1ee4ab3a54a"
UPSTREAM_COMMIT = "c72d1228bde80417d5cc782521328e02ab5401c3"
QDESN_REGISTRY_SHA256 = "d45c43b6d2dd3b163ca1d3cd0b140ce0e582797aaea0a3db012a7d74293e4802"
MODEL_PARAMETER_COUNT = 341_044
PHASE1_REPLICATES = 3
PHASE1_EPOCHS = 50
PHASE2_EPOCHS = 20
BATCH_SIZE = 128


def parse_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    value = str(value).strip().lower()
    if value in {"1", "true", "yes", "y", "on"}:
        return True
    if value in {"0", "false", "no", "n", "off"}:
        return False
    raise ValueError(f"Expected true or false, got {value!r}")


def sha256_file(path: str | Path, block_size: int = 2**20) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(block_size), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_payload(payload: Any) -> str:
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def deterministic_seed(*parts: Any) -> int:
    digest = hashlib.sha256("|".join(map(str, parts)).encode("utf-8")).hexdigest()
    return int(digest[:8], 16) % (2**31 - 1) or 1


def atomic_write_text(path: str | Path, text: str) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False, encoding="utf-8") as handle:
        handle.write(text)
        temporary = Path(handle.name)
    os.replace(temporary, path)


def atomic_write_json(path: str | Path, payload: Any) -> None:
    atomic_write_text(path, json.dumps(payload, indent=2, sort_keys=True) + "\n")


def atomic_write_csv(path: str | Path, rows: Iterable[dict[str, Any]], fieldnames: list[str] | None = None) -> None:
    rows = list(rows)
    if fieldnames is None:
        fieldnames = list(rows[0]) if rows else []
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False, newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
        temporary = Path(handle.name)
    os.replace(temporary, path)


def atomic_save_npz(path: str | Path, **arrays: Any) -> None:
    import numpy as np

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("wb", dir=path.parent, delete=False) as handle:
        np.savez_compressed(handle, **arrays)
        temporary = Path(handle.name)
    os.replace(temporary, path)


def read_csv_rows(path: str | Path) -> list[dict[str, str]]:
    with Path(path).open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def read_json(path: str | Path) -> Any:
    with Path(path).open(encoding="utf-8") as handle:
        return json.load(handle)


def verify_file(path: str | Path, expected_sha256: str) -> None:
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(path)
    observed = sha256_file(path)
    if observed != expected_sha256:
        raise RuntimeError(f"SHA-256 mismatch for {path}: expected {expected_sha256}, observed {observed}")


def freeze_file(path: str | Path, payload: str) -> str:
    """Write an immutable text artifact, or verify an identical existing one."""
    path = Path(path)
    if path.exists():
        current = path.read_text(encoding="utf-8")
        if current != payload:
            raise RuntimeError(f"Frozen artifact differs from requested content: {path}")
    else:
        atomic_write_text(path, payload)
    return sha256_file(path)


def extract_public_adjacency(upstream_root: str | Path) -> dict[str, list[str]]:
    data_path = Path(upstream_root) / "PriceFM" / "data.py"
    tree = ast.parse(data_path.read_text(encoding="utf-8"), filename=str(data_path))
    for node in tree.body:
        if not isinstance(node, ast.FunctionDef) or node.name != "graph_adj_matrix":
            continue
        for statement in node.body:
            if not isinstance(statement, ast.Assign):
                continue
            if any(isinstance(target, ast.Name) and target.id == "adjacency_dict" for target in statement.targets):
                adjacency = ast.literal_eval(statement.value)
                return {str(key): [str(value) for value in values] for key, values in adjacency.items()}
    raise RuntimeError(f"Could not extract graph_adj_matrix adjacency from {data_path}")


def validate_adjacency(adjacency: dict[str, list[str]], regions: list[str]) -> None:
    if list(adjacency) != list(regions):
        raise RuntimeError("Public graph node order does not match the configured region order")
    nodes = set(regions)
    for node, neighbors in adjacency.items():
        if node not in neighbors:
            raise RuntimeError(f"Public graph is missing the self loop for {node}")
        if not set(neighbors).issubset(nodes):
            raise RuntimeError(f"Public graph has unknown neighbors for {node}")
        for neighbor in neighbors:
            if node not in adjacency[neighbor]:
                raise RuntimeError(f"Public graph edge is asymmetric: {node}, {neighbor}")
    visited = {regions[0]}
    queue = [regions[0]]
    while queue:
        node = queue.pop(0)
        for neighbor in adjacency[node]:
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(neighbor)
    if visited != nodes:
        raise RuntimeError(f"Public graph is disconnected; missing={sorted(nodes - visited)}")


def graph_mask_rows(adjacency: dict[str, list[str]], regions: list[str], max_degree: int = 10) -> list[dict[str, Any]]:
    validate_adjacency(adjacency, regions)
    rows: list[dict[str, Any]] = []
    for target in regions:
        distances = {target: 0}
        queue = [target]
        while queue:
            node = queue.pop(0)
            for neighbor in adjacency[node]:
                if neighbor not in distances:
                    distances[neighbor] = distances[node] + 1
                    queue.append(neighbor)
        canonical_by_hash: dict[str, int] = {}
        for degree in range(max_degree + 1):
            active = [region for region in regions if distances[region] <= degree]
            mask = [1 if region in active else 0 for region in regions]
            mask_hash = sha256_payload(mask)
            canonical_degree = canonical_by_hash.setdefault(mask_hash, degree)
            rows.append({
                "region": target,
                "degree": degree,
                "canonical_degree": canonical_degree,
                "is_canonical": degree == canonical_degree,
                "mask_hash": mask_hash,
                "n_active_regions": len(active),
                "active_regions_json": json.dumps(active, separators=(",", ":")),
                "mask_json": json.dumps(mask, separators=(",", ":")),
                "eccentricity": max(distances.values()),
            })
    return rows


def model_metrics(y_true: Any, y_pred: Any, quantiles: list[float] = QUANTILES) -> dict[str, float]:
    import numpy as np

    y_true = np.asarray(y_true, dtype=np.float64)
    y_pred = np.asarray(y_pred, dtype=np.float64)
    quantiles_array = np.asarray(quantiles, dtype=np.float64)
    error = y_true[..., None] - y_pred
    pinball = np.maximum(
        quantiles_array.reshape(1, 1, -1) * error,
        (quantiles_array.reshape(1, 1, -1) - 1.0) * error,
    )
    median_index = int(np.argmin(np.abs(quantiles_array - 0.5)))
    median_prediction = y_pred[..., median_index]
    crossing = y_pred[..., :-1] > y_pred[..., 1:]
    return {
        "AQL": float(pinball.mean()),
        "AQCR": float(crossing.mean()) if crossing.size else 0.0,
        "MAE": float(np.mean(np.abs(y_true - median_prediction))),
        "RMSE": float(np.sqrt(np.mean((y_true - median_prediction) ** 2))),
    }


def inverse_scale_y(values: Any, center: float, scale: float) -> Any:
    return values * scale + center


def scaler_path(artifact_root: str | Path, fold: int, region: str) -> Path:
    return Path(artifact_root) / "data" / "scalers" / f"fold_{fold}" / f"region={region}.npz"


def window_path(artifact_root: str | Path, fold: int, region: str, split: str) -> Path:
    return Path(artifact_root) / "data" / "windows" / f"fold_{fold}" / f"region={region}" / f"{split}.npz"


def load_window(artifact_root: str | Path, fold: int, region: str, split: str) -> dict[str, Any]:
    import numpy as np

    path = window_path(artifact_root, fold, region, split)
    with np.load(path, allow_pickle=False) as archive:
        return {name: archive[name] for name in archive.files}


def load_scaler(artifact_root: str | Path, fold: int, region: str) -> dict[str, Any]:
    import numpy as np

    with np.load(scaler_path(artifact_root, fold, region), allow_pickle=False) as archive:
        return {name: archive[name] for name in archive.files}


def stack_regional_inputs(artifact_root: str | Path, fold: int, split: str, regions: list[str]) -> tuple[Any, Any, dict[str, Any], Any]:
    import numpy as np

    windows = {region: load_window(artifact_root, fold, region, split) for region in regions}
    anchors = windows[regions[0]]["anchors_ns"]
    for region in regions[1:]:
        if not np.array_equal(anchors, windows[region]["anchors_ns"]):
            raise RuntimeError(f"Window anchors differ for {region}, fold {fold}, split {split}")
    x_lag = np.stack([windows[region]["X_lag"] for region in regions], axis=1)
    x_lead = np.stack([windows[region]["X_lead"] for region in regions], axis=1)
    y = {region: windows[region]["Y"] for region in regions}
    return x_lag, x_lead, y, anchors


def pack_phase1(x_lag: Any, x_lead: Any, y: dict[str, Any], regions: list[str]) -> tuple[Any, Any, Any, Any]:
    import numpy as np

    n = x_lag.shape[0]
    gate_identity = np.eye(len(regions), dtype=np.float32)
    return (
        np.concatenate([x_lag] * len(regions), axis=0),
        np.concatenate([x_lead] * len(regions), axis=0),
        np.repeat(gate_identity, n, axis=0),
        np.concatenate([y[region] for region in regions], axis=0),
    )


def pack_target(x_lag: Any, x_lead: Any, y: dict[str, Any], region: str, mask: list[int]) -> tuple[Any, Any, Any, Any]:
    import numpy as np

    gate = np.repeat(np.asarray(mask, dtype=np.float32)[None, :], x_lag.shape[0], axis=0)
    return x_lag, x_lead, gate, y[region]


def physical_core_topology(sysfs_root: str | Path = "/sys/devices/system/cpu") -> list[dict[str, Any]]:
    root = Path(sysfs_root)
    groups: dict[tuple[int, int], list[int]] = {}
    for cpu_dir in root.glob("cpu[0-9]*"):
        cpu = int(cpu_dir.name[3:])
        topology = cpu_dir / "topology"
        try:
            package = int((topology / "physical_package_id").read_text().strip())
            core = int((topology / "core_id").read_text().strip())
        except (FileNotFoundError, ValueError):
            continue
        groups.setdefault((package, core), []).append(cpu)
    return [
        {"package": package, "core": core, "logical_cpus": sorted(cpus)}
        for (package, core), cpus in sorted(groups.items())
    ]


def _read_proc_stat(path: str | Path = "/proc/stat") -> dict[int, tuple[int, int]]:
    rows: dict[int, tuple[int, int]] = {}
    for line in Path(path).read_text().splitlines():
        if not line.startswith("cpu") or not line[3:4].isdigit():
            continue
        fields = line.split()
        cpu = int(fields[0][3:])
        values = [int(value) for value in fields[1:]]
        idle = values[3] + (values[4] if len(values) > 4 else 0)
        total = sum(values)
        rows[cpu] = (idle, total)
    return rows


def sample_logical_cpu_utilization(seconds: float = 2.0) -> dict[int, float]:
    before = _read_proc_stat()
    time.sleep(seconds)
    after = _read_proc_stat()
    utilization: dict[int, float] = {}
    for cpu, (idle_before, total_before) in before.items():
        idle_after, total_after = after[cpu]
        total_delta = total_after - total_before
        idle_delta = idle_after - idle_before
        utilization[cpu] = 0.0 if total_delta <= 0 else 1.0 - idle_delta / total_delta
    return utilization


def idle_physical_cores(max_utilization: float = 0.10, sample_seconds: float = 2.0) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    utilization = sample_logical_cpu_utilization(sample_seconds)
    all_cores = physical_core_topology()
    idle: list[dict[str, Any]] = []
    annotated: list[dict[str, Any]] = []
    for item in all_cores:
        logical_values = [utilization.get(cpu, 1.0) for cpu in item["logical_cpus"]]
        record = dict(item)
        record["max_logical_utilization"] = max(logical_values)
        record["mean_logical_utilization"] = sum(logical_values) / len(logical_values)
        annotated.append(record)
        if record["max_logical_utilization"] <= max_utilization:
            idle.append(record)
    return idle, annotated


def available_memory_gib() -> float:
    for line in Path("/proc/meminfo").read_text().splitlines():
        if line.startswith("MemAvailable:"):
            return int(line.split()[1]) / 1024**2
    raise RuntimeError("MemAvailable is absent from /proc/meminfo")


def free_disk_gib(path: str | Path) -> float:
    probe = Path(path)
    while not probe.exists() and probe != probe.parent:
        probe = probe.parent
    return shutil.disk_usage(probe).free / 1024**3


def cpuset_text(core: dict[str, Any]) -> str:
    return ",".join(str(cpu) for cpu in core["logical_cpus"])


def thread_limited_environment(seed: int | None = None) -> dict[str, str]:
    environment = dict(os.environ)
    environment.update({
        "OMP_NUM_THREADS": "1",
        "OPENBLAS_NUM_THREADS": "1",
        "MKL_NUM_THREADS": "1",
        "NUMEXPR_NUM_THREADS": "1",
        "VECLIB_MAXIMUM_THREADS": "1",
        "TF_NUM_INTRAOP_THREADS": "1",
        "TF_NUM_INTEROP_THREADS": "1",
        "TF_ENABLE_ONEDNN_OPTS": "0",
        "TF_DETERMINISTIC_OPS": "1",
        "CUDA_VISIBLE_DEVICES": "-1",
    })
    if seed is not None:
        environment["PYTHONHASHSEED"] = str(seed)
    return environment


def status_is_complete(trial_dir: str | Path) -> bool:
    path = Path(trial_dir) / "status.json"
    if not path.exists():
        return False
    try:
        status = read_json(path)
    except (OSError, json.JSONDecodeError):
        return False
    checkpoint = Path(status.get("checkpoint", ""))
    return (
        status.get("status") == "completed"
        and checkpoint.is_file()
        and sha256_file(checkpoint) == status.get("checkpoint_sha256")
    )


def source_manifest_rows(paths: dict[str, str | Path]) -> list[dict[str, Any]]:
    rows = []
    for label, raw_path in paths.items():
        path = Path(raw_path)
        rows.append({
            "label": label,
            "path": str(path),
            "exists": path.exists(),
            "size_bytes": path.stat().st_size if path.is_file() else 0,
            "sha256": sha256_file(path) if path.is_file() else "",
        })
    return rows
