#!/usr/bin/env python3
"""Pure helpers for causal, synchronous PriceFM panel recursion.

This module does not fit models or read test outcomes.  It normalizes frozen
DESN contracts and reproduces the PriceFM graph feature policies from
per-region lag/lead blocks so future endogenous inputs can be assembled from a
single pre-update panel snapshot.
"""

from __future__ import annotations

import ast
import hashlib
import json
from typing import Any, Mapping, Sequence

import numpy as np

from pricefm_graph import (
    graph_active_regions_for_policy,
    graph_adj_matrix,
    graph_hash,
    graph_scope_manifest_for_policy,
)


SUPPORTED_POLICIES = {
    "target_only",
    "graph_khop",
    "graph_summary_mean",
    "graph_summary_mean_std",
    "graph_neighbor_direct",
    "graph_neighbor_spread_summary",
}
STRUCTURE_FIELDS = (
    "region",
    "feature_policy",
    "lag_window",
    "depth",
    "units",
    "alpha",
    "rho",
    "input_scale",
    "state_output",
    "seed",
    "spatial",
)


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def fingerprint(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def parse_jsonish(value: Any, default: Any = None) -> Any:
    if value is None or (isinstance(value, float) and np.isnan(value)):
        return default
    if not isinstance(value, str):
        return value
    text = value.strip()
    if not text:
        return default
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return ast.literal_eval(text)


def normalize_spec(spec: Mapping[str, Any]) -> dict[str, Any]:
    units = [int(x) for x in parse_jsonish(spec.get("units"), [])]
    if not units:
        raise ValueError("DESN units must be non-empty")
    policy = str(spec.get("feature_policy", ""))
    if policy not in SUPPORTED_POLICIES:
        raise ValueError("unsupported feature_policy: {}".format(policy))
    spatial = dict(parse_jsonish(spec.get("spatial"), {}) or {})
    spatial["graph_degree"] = int(
        spatial.get("graph_degree", spec.get("graph_degree", 0 if policy == "target_only" else 1))
    )
    for key in ("neighbor_regions", "summary_stats"):
        value = spatial.get(key, spec.get(key))
        if value not in (None, ""):
            spatial[key] = [str(x) for x in parse_jsonish(value, [])]
    if spatial.get("max_neighbor_regions") not in (None, ""):
        spatial["max_neighbor_regions"] = int(float(spatial["max_neighbor_regions"]))
    if policy == "target_only":
        spatial = {"graph_degree": 0}
    elif policy in {"graph_khop", "graph_summary_mean", "graph_summary_mean_std"}:
        # These policies always use the complete k-hop scope.  Historical
        # manifests sometimes redundantly stored the derived neighbor list.
        spatial = {"graph_degree": spatial["graph_degree"]}
    out = {
        "region": str(spec["region"]),
        "feature_policy": policy,
        "lag_window": int(spec["lag_window"]),
        "depth": int(spec.get("depth", len(units))),
        "units": units,
        "alpha": float(spec["alpha"]),
        "rho": float(spec["rho"]),
        "input_scale": float(spec["input_scale"]),
        "state_output": str(spec["state_output"]),
        "seed": int(spec["seed"]),
        "spatial": spatial,
        "tau0": float(spec["tau0"]),
    }
    if out["depth"] != len(out["units"]):
        raise ValueError("DESN depth must equal len(units)")
    if out["lag_window"] < 1 or out["tau0"] <= 0:
        raise ValueError("lag_window and tau0 must be positive")
    return out


def structure_payload(spec: Mapping[str, Any]) -> dict[str, Any]:
    normalized = normalize_spec(spec)
    return {key: normalized[key] for key in STRUCTURE_FIELDS}


def contract_payload(spec: Mapping[str, Any]) -> dict[str, Any]:
    payload = structure_payload(spec)
    payload["tau0"] = normalize_spec(spec)["tau0"]
    return payload


def spec_identities(spec: Mapping[str, Any]) -> dict[str, str]:
    return {
        "structure_sha256": fingerprint(structure_payload(spec)),
        "contract_sha256": fingerprint(contract_payload(spec)),
    }


def feature_name(column: Any) -> str:
    text = str(column)
    if "::" in text:
        text = text.split("::", 1)[1]
    return text.split("-", 1)[1] if "-" in text else text


def _as_feature_list(value: Any, default: str = "all") -> str | list[str]:
    if value is None:
        value = default
    if isinstance(value, str):
        if value.strip().lower() == "all":
            return "all"
        return [x.strip() for x in value.split(",") if x.strip()]
    return [str(x) for x in value]


def _block(region_block: Mapping[str, Any], block: str) -> tuple[np.ndarray, list[str]]:
    array_key = "X_{}".format(block)
    cols_key = "{}_cols".format(block)
    arr = np.asarray(region_block[array_key], dtype=float)
    cols = [str(x) for x in region_block[cols_key]]
    if arr.ndim < 2 or arr.shape[-1] != len(cols):
        raise ValueError("{} shape and columns disagree".format(array_key))
    return arr, cols


def _subset(
    region_block: Mapping[str, Any], block: str, selected: Any, label: str
) -> tuple[np.ndarray, list[str], list[str]]:
    arr, cols = _block(region_block, block)
    names = [feature_name(col) for col in cols]
    selected = _as_feature_list(selected)
    if selected == "all":
        return arr, cols, names
    missing = [name for name in selected if name not in names]
    if missing:
        raise ValueError("{} requested unavailable feature(s): {}".format(label, missing))
    indices = [idx for idx, name in enumerate(names) if name in selected]
    return arr[..., indices], [cols[idx] for idx in indices], [names[idx] for idx in indices]


def _prefix(region: str, columns: Sequence[str]) -> list[str]:
    return ["{}::{}".format(region, col) for col in columns]


def _assert_compatible(blocks: Sequence[np.ndarray], label: str) -> None:
    if not blocks:
        raise ValueError("{} cannot be empty".format(label))
    shape = blocks[0].shape[:-1]
    if any(block.shape[:-1] != shape for block in blocks[1:]):
        raise ValueError("{} region blocks must have aligned leading dimensions".format(label))


def _summary_stats(value: Any) -> list[str]:
    stats = _as_feature_list(value, default="mean_diff,sd,min_diff,max_diff")
    if stats == "all":
        stats = ["mean_diff", "sd", "min_diff", "max_diff"]
    allowed = {"mean", "mean_diff", "sd", "min_diff", "max_diff"}
    unknown = [stat for stat in stats if stat not in allowed]
    if unknown:
        raise ValueError("unknown neighbor summary statistic(s): {}".format(unknown))
    return list(stats)


def _spread_summary(
    target_region: str,
    target: Mapping[str, Any],
    neighbors: Sequence[Mapping[str, Any]],
    block: str,
    target_selected: Any,
    neighbor_selected: Any,
    stats: Sequence[str],
) -> tuple[list[np.ndarray], list[str], list[str]]:
    target_arr, target_cols, target_names = _subset(
        target, block, target_selected, "target_{}_features".format(block)
    )
    parts = [target_arr]
    columns = _prefix(target_region, target_cols)
    target_map = {name: target_arr[..., idx] for idx, name in enumerate(target_names)}
    neighbor_maps = []
    for neighbor in neighbors:
        arr, _, names = _subset(
            neighbor, block, neighbor_selected, "neighbor_{}_features".format(block)
        )
        neighbor_maps.append({name: arr[..., idx] for idx, name in enumerate(names)})
    common = sorted(
        set(target_map).intersection(*(set(mapping) for mapping in neighbor_maps))
        if neighbor_maps else []
    )
    for name in common:
        target_values = target_map[name]
        stack = np.stack([mapping[name] for mapping in neighbor_maps], axis=0)
        values = {
            "mean": np.mean(stack, axis=0),
            "mean_diff": np.mean(stack, axis=0) - target_values,
            "sd": np.std(stack, axis=0, ddof=0),
            "min_diff": np.min(stack, axis=0) - target_values,
            "max_diff": np.max(stack, axis=0) - target_values,
        }
        for stat in stats:
            parts.append(values[stat][..., None])
            columns.append("graph_neighbor_{}::{}-{}".format(stat, block, name))
    return parts, columns, common


def build_policy_features(
    target_region: str,
    region_blocks: Mapping[str, Mapping[str, Any]],
    feature_policy: str,
    spatial: Mapping[str, Any] | None = None,
    input_regions: Sequence[str] | None = None,
    adjacency: Mapping[str, Sequence[str]] | None = None,
) -> dict[str, Any]:
    """Build one policy-aligned feature block from a pre-update panel snapshot."""
    target_region = str(target_region)
    feature_policy = str(feature_policy)
    if feature_policy not in SUPPORTED_POLICIES:
        raise ValueError("unsupported feature_policy: {}".format(feature_policy))
    if target_region not in region_blocks:
        raise ValueError("target region block is missing: {}".format(target_region))
    input_regions = list(input_regions or region_blocks.keys())
    spatial = dict(spatial or {})
    adjacency = graph_adj_matrix() if adjacency is None else adjacency
    active = graph_active_regions_for_policy(
        target_region,
        input_regions,
        feature_policy,
        spatial=spatial,
        adjacency=adjacency,
    )
    missing = [region for region in active if region not in region_blocks]
    if missing:
        raise ValueError("active region block(s) missing: {}".format(missing))
    target = region_blocks[target_region]
    neighbors = [region_blocks[region] for region in active[1:]]

    output: dict[str, Any] = {}
    for block in ("lag", "lead"):
        target_arr, target_cols = _block(target, block)
        if feature_policy == "target_only":
            parts, columns = [target_arr], list(target_cols)
        elif feature_policy == "graph_khop":
            parts = []
            columns = []
            for region in active:
                arr, cols = _block(region_blocks[region], block)
                parts.append(arr)
                columns.extend(_prefix(region, cols))
        elif feature_policy in {"graph_summary_mean", "graph_summary_mean_std"}:
            parts = [target_arr]
            columns = list(target_cols)
            if neighbors:
                neighbor_arrays = [_block(neighbor, block)[0] for neighbor in neighbors]
                _assert_compatible([target_arr] + neighbor_arrays, block)
                if any(array.shape[-1] != target_arr.shape[-1] for array in neighbor_arrays):
                    raise ValueError("graph summary requires identical feature dimensions")
                target_names = [feature_name(col) for col in target_cols]
                neighbor_names = [
                    [feature_name(col) for col in _block(neighbor, block)[1]]
                    for neighbor in neighbors
                ]
                if any(names != target_names for names in neighbor_names):
                    raise ValueError("graph summary requires identical feature ordering")
                stack = np.stack(neighbor_arrays, axis=0)
                parts.append(np.mean(stack, axis=0))
                columns.extend(["graph_neighbor_mean::{}".format(col) for col in target_cols])
                if feature_policy == "graph_summary_mean_std":
                    parts.append(np.std(stack, axis=0, ddof=0))
                    columns.extend(["graph_neighbor_sd::{}".format(col) for col in target_cols])
        elif feature_policy == "graph_neighbor_direct":
            target_selected = spatial.get("target_{}_features".format(block), "all")
            neighbor_selected = spatial.get("neighbor_{}_features".format(block), "all")
            arr, cols, _ = _subset(target, block, target_selected, "target_{}_features".format(block))
            parts, columns = [arr], _prefix(target_region, cols)
            for region, neighbor in zip(active[1:], neighbors):
                arr, cols, _ = _subset(
                    neighbor, block, neighbor_selected, "neighbor_{}_features".format(block)
                )
                parts.append(arr)
                columns.extend(_prefix(region, cols))
        else:
            target_selected = spatial.get("target_{}_features".format(block), "all")
            neighbor_selected = spatial.get("neighbor_{}_features".format(block), "all")
            parts, columns, common = _spread_summary(
                target_region,
                target,
                neighbors,
                block,
                target_selected,
                neighbor_selected,
                _summary_stats(spatial.get("summary_stats")),
            )
            if neighbors and not common:
                raise ValueError("spread summary requires overlapping target/neighbor features")
        _assert_compatible(parts, block)
        output["X_{}".format(block)] = np.concatenate(parts, axis=-1)
        output["{}_cols".format(block)] = columns

    graph = graph_scope_manifest_for_policy(
        target_region,
        input_regions,
        feature_policy,
        spatial=spatial,
        adjacency=adjacency,
    )
    output["feature_policy_manifest"] = {
        "feature_policy": feature_policy,
        "target_region": target_region,
        "active_regions": active,
        "neighbor_regions": active[1:],
        "spatial": spatial,
        "graph": graph,
        "graph_hash": graph_hash(adjacency),
        "panel_snapshot_contract": "all_regions_pre_update_h_minus_1",
    }
    return output


def validate_panel_snapshot(
    histories: Mapping[str, Sequence[float]], expected_regions: Sequence[str]
) -> None:
    expected = [str(region) for region in expected_regions]
    if set(histories) != set(expected):
        raise ValueError("panel histories must contain exactly the expected regions")
    lengths = {len(histories[region]) for region in expected}
    if len(lengths) != 1 or next(iter(lengths)) < 1:
        raise ValueError("panel histories must be non-empty and aligned")
    if any(not np.all(np.isfinite(np.asarray(histories[region], dtype=float))) for region in expected):
        raise ValueError("panel histories must be finite")


def scale_values(values: Any, center: Any, scale: Any) -> np.ndarray:
    values = np.asarray(values, dtype=float)
    center = np.asarray(center, dtype=float)
    scale = np.asarray(scale, dtype=float)
    if np.any(~np.isfinite(values)) or np.any(~np.isfinite(center)):
        raise ValueError("values and centers must be finite")
    if np.any(~np.isfinite(scale)) or np.any(scale <= 0):
        raise ValueError("scales must be finite and positive")
    return (values - center) / scale


def inverse_scale_values(values: Any, center: Any, scale: Any) -> np.ndarray:
    values = np.asarray(values, dtype=float)
    center = np.asarray(center, dtype=float)
    scale = np.asarray(scale, dtype=float)
    if np.any(~np.isfinite(values)) or np.any(~np.isfinite(center)):
        raise ValueError("values and centers must be finite")
    if np.any(~np.isfinite(scale)) or np.any(scale <= 0):
        raise ValueError("scales must be finite and positive")
    return values * scale + center
