"""Build stacked direct-horizon PriceFM design matrices for DESN smoke runs."""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd
import yaml

from pricefm_common import load_config, pricefm_block, repo_path, sha256_file, write_json
from pricefm_graph import graph_scope_manifest, graph_scope_manifest_for_policy


def sha256_array(arr):
    h = hashlib.sha256()
    a = np.ascontiguousarray(arr)
    h.update(str(a.shape).encode("utf-8"))
    h.update(str(a.dtype).encode("utf-8"))
    h.update(a.tobytes())
    return h.hexdigest()


def sha256_arrays(arrays):
    h = hashlib.sha256()
    for name in sorted(arrays):
        arr = np.ascontiguousarray(arrays[name])
        h.update(str(name).encode("utf-8"))
        h.update(str(arr.shape).encode("utf-8"))
        h.update(str(arr.dtype).encode("utf-8"))
        h.update(arr.tobytes())
    return h.hexdigest()


def sha256_json(obj):
    text = json.dumps(obj, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def load_smoke_config(path):
    with open(repo_path(path), "r") as f:
        cfg = yaml.safe_load(f)
    if not isinstance(cfg, dict) or "pricefm_desn_smoke" not in cfg:
        raise ValueError("Config must contain top-level pricefm_desn_smoke")
    return cfg["pricefm_desn_smoke"]


def window_npz_path(data_cfg, fold, region, split):
    spec = pricefm_block(data_cfg)
    mode = (
        spec["windows"]["train_boundary_mode"]
        if split == "train"
        else spec["windows"]["validation_boundary_mode"]
        if split == "val"
        else spec["windows"]["test_boundary_mode"]
    )
    name = "{}_L{}_H{}_{}.npz".format(
        split,
        int(spec["windows"]["lag_window"]),
        int(spec["windows"]["lead_window"]),
        mode,
    )
    return repo_path(Path(spec["processed_dir"]) / "windows" /
                     "fold_{}".format(int(fold)) / "region={}".format(region) / name)


def load_window(data_cfg, fold, region, split):
    path = window_npz_path(data_cfg, fold, region, split)
    if not path.exists():
        raise FileNotFoundError("Missing PriceFM window file: {}".format(path))
    z = np.load(path, allow_pickle=True)
    with open(path.with_suffix(".manifest.json"), "r") as f:
        manifest = json.load(f)
    return {
        "path": path,
        "manifest": manifest,
        "X_lag": z["X_lag"].astype(float),
        "X_lead": z["X_lead"].astype(float),
        "Y": z["Y"].astype(float),
        "anchors": z["anchors"].astype(str),
        "lag_cols": z["lag_cols"].astype(str).tolist(),
        "lead_cols": z["lead_cols"].astype(str).tolist(),
    }


def _feature_policy(smoke):
    return str(smoke.get("feature_policy", "target_only"))


def _spatial_cfg(smoke):
    adapter = smoke.get("adapter", {})
    cfg = adapter.get("spatial", {})
    return dict(cfg or {})


def _source_window_manifest(region, split, window):
    return {
        "region": str(region),
        "split": str(split),
        "window_path": str(window["path"]),
        "window_sha256": sha256_file(window["path"]),
        "manifest_path": str(window["path"].with_suffix(".manifest.json")),
        "manifest_sha256": sha256_file(window["path"].with_suffix(".manifest.json")),
        "n_origins": int(window["Y"].shape[0]),
        "lag_shape": list(window["X_lag"].shape),
        "lead_shape": list(window["X_lead"].shape),
        "response_shape": list(window["Y"].shape),
    }


def _prefix_cols(region, cols):
    return ["{}::{}".format(region, col) for col in cols]


def _feature_name_from_col(col):
    text = str(col)
    if "::" in text:
        text = text.split("::", 1)[1]
    if "-" in text:
        return text.split("-", 1)[1]
    return text


def _as_feature_list(value, default="all"):
    if value is None:
        value = default
    if isinstance(value, str):
        if value.strip().lower() == "all":
            return "all"
        if value.strip() == "":
            return []
        return [x.strip() for x in value.split(",") if x.strip()]
    return [str(x) for x in value]


def _select_feature_indices(cols, selected, label):
    selected = _as_feature_list(selected)
    if selected == "all":
        return list(range(len(cols))), [_feature_name_from_col(col) for col in cols]
    selected = [str(x) for x in selected]
    names = [_feature_name_from_col(col) for col in cols]
    missing = [x for x in selected if x not in names]
    if missing:
        raise ValueError("{} requested unavailable feature(s): {}".format(label, missing))
    idx = [i for i, name in enumerate(names) if name in selected]
    return idx, [names[i] for i in idx]


def _subset_feature_block(window, block, selected, label):
    if block == "lag":
        cols = list(window["lag_cols"])
        arr = window["X_lag"]
    elif block == "lead":
        cols = list(window["lead_cols"])
        arr = window["X_lead"]
    else:
        raise ValueError("Unknown block: {}".format(block))
    idx, names = _select_feature_indices(cols, selected, label)
    if not idx:
        return arr[:, :, :0], [], []
    return arr[:, :, idx], [cols[i] for i in idx], names


def _feature_provenance_rows(region, role, block, cols, selected_names, feature_policy="graph_neighbor_direct"):
    rows = []
    for pos, (col, name) in enumerate(zip(cols, selected_names), start=1):
        rows.append({
            "feature_policy": feature_policy,
            "source_region": str(region),
            "source_role": str(role),
            "input_block": str(block),
            "source_column": str(col),
            "source_feature": str(name),
            "within_block_position": int(pos),
        })
    return rows


def _load_graph_windows(data_cfg, fold, region, split, smoke):
    spec = pricefm_block(data_cfg)
    spatial = _spatial_cfg(smoke)
    degree = int(spatial.get("graph_degree", spatial.get("degree", 1)))
    graph = graph_scope_manifest(region, spec["regions"], degree)
    active_regions = graph["active_regions"]
    windows = [load_window(data_cfg, fold, active_region, split) for active_region in active_regions]
    target = windows[0]

    for active_region, window in zip(active_regions[1:], windows[1:]):
        if not np.array_equal(target["anchors"], window["anchors"]):
            raise ValueError(
                "Anchor mismatch for target {} and graph region {} split {}".format(
                    region, active_region, split
                )
            )
        if target["Y"].shape != window["Y"].shape:
            raise ValueError(
                "Response shape mismatch for target {} and graph region {} split {}".format(
                    region, active_region, split
                )
            )
        if target["X_lag"].shape[:2] != window["X_lag"].shape[:2]:
            raise ValueError(
                "Lag shape mismatch for target {} and graph region {} split {}".format(
                    region, active_region, split
                )
            )
        if target["X_lead"].shape[:2] != window["X_lead"].shape[:2]:
            raise ValueError(
                "Lead shape mismatch for target {} and graph region {} split {}".format(
                    region, active_region, split
                )
            )
    return spatial, degree, graph, active_regions, windows


def _load_graph_policy_windows(data_cfg, fold, region, split, smoke, feature_policy):
    spec = pricefm_block(data_cfg)
    spatial = _spatial_cfg(smoke)
    degree = int(spatial.get("graph_degree", spatial.get("degree", 1)))
    graph = graph_scope_manifest_for_policy(
        region,
        spec["regions"],
        feature_policy,
        spatial=spatial,
    )
    active_regions = graph["active_regions"]
    windows = [load_window(data_cfg, fold, active_region, split) for active_region in active_regions]
    target = windows[0]

    for active_region, window in zip(active_regions[1:], windows[1:]):
        if not np.array_equal(target["anchors"], window["anchors"]):
            raise ValueError(
                "Anchor mismatch for target {} and graph region {} split {}".format(
                    region, active_region, split
                )
            )
        if target["Y"].shape != window["Y"].shape:
            raise ValueError(
                "Response shape mismatch for target {} and graph region {} split {}".format(
                    region, active_region, split
                )
            )
        if target["X_lag"].shape[:2] != window["X_lag"].shape[:2]:
            raise ValueError(
                "Lag shape mismatch for target {} and graph region {} split {}".format(
                    region, active_region, split
                )
            )
        if target["X_lead"].shape[:2] != window["X_lead"].shape[:2]:
            raise ValueError(
                "Lead shape mismatch for target {} and graph region {} split {}".format(
                    region, active_region, split
                )
            )
    return spatial, degree, graph, active_regions, windows


def _graph_source_windows(active_regions, split, windows):
    return [
        _source_window_manifest(active_region, split, window)
        for active_region, window in zip(active_regions, windows)
    ]


def _combine_graph_windows(data_cfg, fold, region, split, smoke):
    spatial, degree, graph, active_regions, windows = _load_graph_windows(
        data_cfg, fold, region, split, smoke
    )
    target = windows[0]

    out = dict(target)
    out["X_lag"] = np.concatenate([window["X_lag"] for window in windows], axis=2)
    out["X_lead"] = np.concatenate([window["X_lead"] for window in windows], axis=2)
    out["lag_cols"] = [
        col
        for active_region, window in zip(active_regions, windows)
        for col in _prefix_cols(active_region, window["lag_cols"])
    ]
    out["lead_cols"] = [
        col
        for active_region, window in zip(active_regions, windows)
        for col in _prefix_cols(active_region, window["lead_cols"])
    ]
    out["feature_policy_manifest"] = {
        "feature_policy": "graph_khop",
        "input_scope": "pricefm_graph_khop",
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "pricefm_released_graph_khop",
        "spatial": dict(spatial, graph_degree=degree),
        "graph": graph,
        "source_windows": _graph_source_windows(active_regions, split, windows),
    }
    return out


def _summary_cols(statistic, cols):
    return ["graph_{}::{}".format(statistic, col) for col in cols]


def _combine_graph_summary_windows(data_cfg, fold, region, split, smoke, statistic_set):
    spatial, degree, graph, active_regions, windows = _load_graph_windows(
        data_cfg, fold, region, split, smoke
    )
    target = windows[0]
    neighbors = windows[1:]
    neighbor_regions = active_regions[1:]

    out = dict(target)
    out["lag_cols"] = list(target["lag_cols"])
    out["lead_cols"] = list(target["lead_cols"])

    if neighbors:
        neighbor_lag = np.stack([window["X_lag"] for window in neighbors], axis=0)
        neighbor_lead = np.stack([window["X_lead"] for window in neighbors], axis=0)
        lag_parts = [target["X_lag"], np.mean(neighbor_lag, axis=0)]
        lead_parts = [target["X_lead"], np.mean(neighbor_lead, axis=0)]
        out["lag_cols"].extend(_summary_cols("neighbor_mean", target["lag_cols"]))
        out["lead_cols"].extend(_summary_cols("neighbor_mean", target["lead_cols"]))
        statistics = ["neighbor_mean"]
        if statistic_set == "mean_std":
            lag_parts.append(np.std(neighbor_lag, axis=0, ddof=0))
            lead_parts.append(np.std(neighbor_lead, axis=0, ddof=0))
            out["lag_cols"].extend(_summary_cols("neighbor_sd", target["lag_cols"]))
            out["lead_cols"].extend(_summary_cols("neighbor_sd", target["lead_cols"]))
            statistics.append("neighbor_sd")
        out["X_lag"] = np.concatenate(lag_parts, axis=2)
        out["X_lead"] = np.concatenate(lead_parts, axis=2)
    else:
        # Degree-zero summary policies intentionally reduce to target-only.
        out["X_lag"] = target["X_lag"].copy()
        out["X_lead"] = target["X_lead"].copy()
        statistics = []

    policy = "graph_summary_{}".format(statistic_set)
    out["feature_policy_manifest"] = {
        "feature_policy": policy,
        "input_scope": "pricefm_{}_degree{}".format(policy, degree),
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "pricefm_released_graph_summary",
        "spatial": dict(spatial, graph_degree=degree),
        "graph": graph,
        "source_windows": _graph_source_windows(active_regions, split, windows),
        "neighbor_summary": {
            "type": statistic_set,
            "target_region_preserved": True,
            "neighbor_regions": list(neighbor_regions),
            "n_neighbor_regions": int(len(neighbor_regions)),
            "statistics": statistics,
            "degree_zero_equals_target_only": bool(len(neighbor_regions) == 0),
        },
    }
    return out


def _combine_graph_neighbor_direct_windows(data_cfg, fold, region, split, smoke):
    spatial, degree, graph, active_regions, windows = _load_graph_policy_windows(
        data_cfg, fold, region, split, smoke, "graph_neighbor_direct"
    )
    target = windows[0]
    neighbor_regions = active_regions[1:]

    target_lag_features = spatial.get("target_lag_features", "all")
    target_lead_features = spatial.get("target_lead_features", "all")
    neighbor_lag_features = spatial.get("neighbor_lag_features", "all")
    neighbor_lead_features = spatial.get("neighbor_lead_features", "all")

    lag_parts = []
    lead_parts = []
    lag_cols = []
    lead_cols = []
    provenance = []

    lag_arr, cols, names = _subset_feature_block(
        target, "lag", target_lag_features, "target_lag_features"
    )
    lag_parts.append(lag_arr)
    lag_cols.extend(_prefix_cols(region, cols))
    provenance.extend(_feature_provenance_rows(region, "target", "lag", cols, names))

    lead_arr, cols, names = _subset_feature_block(
        target, "lead", target_lead_features, "target_lead_features"
    )
    lead_parts.append(lead_arr)
    lead_cols.extend(_prefix_cols(region, cols))
    provenance.extend(_feature_provenance_rows(region, "target", "lead", cols, names))

    for active_region, window in zip(neighbor_regions, windows[1:]):
        lag_arr, cols, names = _subset_feature_block(
            window, "lag", neighbor_lag_features, "neighbor_lag_features"
        )
        if cols:
            lag_parts.append(lag_arr)
            lag_cols.extend(_prefix_cols(active_region, cols))
            provenance.extend(_feature_provenance_rows(active_region, "neighbor", "lag", cols, names))

        lead_arr, cols, names = _subset_feature_block(
            window, "lead", neighbor_lead_features, "neighbor_lead_features"
        )
        if cols:
            lead_parts.append(lead_arr)
            lead_cols.extend(_prefix_cols(active_region, cols))
            provenance.extend(_feature_provenance_rows(active_region, "neighbor", "lead", cols, names))

    if not lag_parts or sum(part.shape[2] for part in lag_parts) <= 0:
        raise ValueError("graph_neighbor_direct must keep at least one lag feature")
    if not lead_parts or sum(part.shape[2] for part in lead_parts) <= 0:
        raise ValueError("graph_neighbor_direct must keep at least one lead feature")

    out = dict(target)
    out["X_lag"] = np.concatenate(lag_parts, axis=2)
    out["X_lead"] = np.concatenate(lead_parts, axis=2)
    out["lag_cols"] = lag_cols
    out["lead_cols"] = lead_cols
    out["feature_policy_manifest"] = {
        "feature_policy": "graph_neighbor_direct",
        "input_scope": "pricefm_graph_neighbor_direct_degree{}_n{}".format(
            degree, len(neighbor_regions)
        ),
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "pricefm_neighbor_augmented_direct",
        "spatial": dict(spatial, graph_degree=degree),
        "graph": graph,
        "source_windows": _graph_source_windows(active_regions, split, windows),
        "neighbor_direct": {
            "target_region_preserved": True,
            "neighbor_regions": list(neighbor_regions),
            "n_neighbor_regions": int(len(neighbor_regions)),
            "target_lag_features": _as_feature_list(target_lag_features),
            "target_lead_features": _as_feature_list(target_lead_features),
            "neighbor_lag_features": _as_feature_list(neighbor_lag_features),
            "neighbor_lead_features": _as_feature_list(neighbor_lead_features),
            "lag_feature_count": int(out["X_lag"].shape[2]),
            "lead_feature_count": int(out["X_lead"].shape[2]),
        },
        "leakage_contract": {
            "response_source": "target_region_Y_only",
            "anchor_alignment": "required_equal_across_active_regions",
            "neighbor_response_used_as_input": False,
            "target_future_price_used_as_input": False,
            "lead_covariate_status": "realized_ex_post",
        },
        "feature_provenance": provenance,
    }
    return out


def _feature_array_map(window, block, selected, label):
    arr, cols, names = _subset_feature_block(window, block, selected, label)
    return arr, cols, names, {name: arr[:, :, i] for i, name in enumerate(names)}


def _summary_stat_list(value):
    if value is None:
        return ["mean_diff", "sd", "min_diff", "max_diff"]
    out = _as_feature_list(value)
    if out == "all":
        out = ["mean_diff", "sd", "min_diff", "max_diff"]
    allowed = {"mean_diff", "sd", "min_diff", "max_diff", "mean"}
    unknown = [x for x in out if x not in allowed]
    if unknown:
        raise ValueError("graph_neighbor_spread_summary unknown summary_stat(s): {}".format(unknown))
    return out


def _summary_provenance_row(policy, block, col, feature, pos):
    return {
        "feature_policy": policy,
        "source_region": "graph_neighbor_summary",
        "source_role": "neighbor_summary",
        "input_block": str(block),
        "source_column": str(col),
        "source_feature": str(feature),
        "within_block_position": int(pos),
    }


def _spread_summary_cols(stat, block, feature):
    return "graph_neighbor_{}::{}-{}".format(stat, block, feature)


def _append_spread_summary_parts(
    *,
    policy,
    block,
    target_map,
    neighbor_maps,
    summary_stats,
    parts,
    cols,
    provenance,
):
    common = sorted(
        set(target_map).intersection(*(set(x) for x in neighbor_maps))
        if neighbor_maps else []
    )
    position = len(cols) + 1
    for feature in common:
        target_values = target_map[feature]
        neighbor_stack = np.stack([mapping[feature] for mapping in neighbor_maps], axis=0)
        summaries = {
            "mean": np.mean(neighbor_stack, axis=0),
            "mean_diff": np.mean(neighbor_stack, axis=0) - target_values,
            "sd": np.std(neighbor_stack, axis=0, ddof=0),
            "min_diff": np.min(neighbor_stack, axis=0) - target_values,
            "max_diff": np.max(neighbor_stack, axis=0) - target_values,
        }
        for stat in summary_stats:
            col = _spread_summary_cols(stat, block, feature)
            parts.append(summaries[stat][:, :, None])
            cols.append(col)
            provenance.append(_summary_provenance_row(policy, block, col, feature, position))
            position += 1
    return common


def _combine_graph_neighbor_spread_summary_windows(data_cfg, fold, region, split, smoke):
    policy = "graph_neighbor_spread_summary"
    spatial, degree, graph, active_regions, windows = _load_graph_policy_windows(
        data_cfg, fold, region, split, smoke, policy
    )
    target = windows[0]
    neighbor_regions = active_regions[1:]

    target_lag_features = spatial.get("target_lag_features", "all")
    target_lead_features = spatial.get("target_lead_features", "all")
    neighbor_lag_features = spatial.get("neighbor_lag_features", "all")
    neighbor_lead_features = spatial.get("neighbor_lead_features", "all")
    summary_stats = _summary_stat_list(spatial.get("summary_stats"))

    lag_parts = []
    lead_parts = []
    lag_cols = []
    lead_cols = []
    provenance = []

    target_lag_arr, target_lag_cols, target_lag_names, target_lag_map = _feature_array_map(
        target, "lag", target_lag_features, "target_lag_features"
    )
    target_lead_arr, target_lead_cols, target_lead_names, target_lead_map = _feature_array_map(
        target, "lead", target_lead_features, "target_lead_features"
    )
    lag_parts.append(target_lag_arr)
    lead_parts.append(target_lead_arr)
    lag_cols.extend(_prefix_cols(region, target_lag_cols))
    lead_cols.extend(_prefix_cols(region, target_lead_cols))
    provenance.extend(_feature_provenance_rows(
        region, "target", "lag", target_lag_cols, target_lag_names, feature_policy=policy
    ))
    provenance.extend(_feature_provenance_rows(
        region, "target", "lead", target_lead_cols, target_lead_names, feature_policy=policy
    ))

    neighbor_lag_maps = []
    neighbor_lead_maps = []
    for active_region, window in zip(neighbor_regions, windows[1:]):
        _, _, _, lag_map = _feature_array_map(
            window, "lag", neighbor_lag_features, "neighbor_lag_features"
        )
        _, _, _, lead_map = _feature_array_map(
            window, "lead", neighbor_lead_features, "neighbor_lead_features"
        )
        neighbor_lag_maps.append(lag_map)
        neighbor_lead_maps.append(lead_map)

    lag_summary_features = _append_spread_summary_parts(
        policy=policy,
        block="lag",
        target_map=target_lag_map,
        neighbor_maps=neighbor_lag_maps,
        summary_stats=summary_stats,
        parts=lag_parts,
        cols=lag_cols,
        provenance=provenance,
    )
    lead_summary_features = _append_spread_summary_parts(
        policy=policy,
        block="lead",
        target_map=target_lead_map,
        neighbor_maps=neighbor_lead_maps,
        summary_stats=summary_stats,
        parts=lead_parts,
        cols=lead_cols,
        provenance=provenance,
    )

    if not lag_parts or sum(part.shape[2] for part in lag_parts) <= 0:
        raise ValueError("{} must keep at least one lag feature".format(policy))
    if not lead_parts or sum(part.shape[2] for part in lead_parts) <= 0:
        raise ValueError("{} must keep at least one lead feature".format(policy))
    if neighbor_regions and not lag_summary_features and not lead_summary_features:
        raise ValueError(
            "{} requires at least one overlapping target/neighbor feature for summaries".format(policy)
        )

    out = dict(target)
    out["X_lag"] = np.concatenate(lag_parts, axis=2)
    out["X_lead"] = np.concatenate(lead_parts, axis=2)
    out["lag_cols"] = lag_cols
    out["lead_cols"] = lead_cols
    out["feature_policy_manifest"] = {
        "feature_policy": policy,
        "input_scope": "pricefm_graph_neighbor_spread_summary_degree{}_n{}".format(
            degree, len(neighbor_regions)
        ),
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "pricefm_neighbor_augmented_spread_summary",
        "spatial": dict(spatial, graph_degree=degree),
        "graph": graph,
        "source_windows": _graph_source_windows(active_regions, split, windows),
        "neighbor_spread_summary": {
            "target_region_preserved": True,
            "neighbor_regions": list(neighbor_regions),
            "n_neighbor_regions": int(len(neighbor_regions)),
            "target_lag_features": _as_feature_list(target_lag_features),
            "target_lead_features": _as_feature_list(target_lead_features),
            "neighbor_lag_features": _as_feature_list(neighbor_lag_features),
            "neighbor_lead_features": _as_feature_list(neighbor_lead_features),
            "summary_stats": list(summary_stats),
            "lag_summary_features": list(lag_summary_features),
            "lead_summary_features": list(lead_summary_features),
            "lag_feature_count": int(out["X_lag"].shape[2]),
            "lead_feature_count": int(out["X_lead"].shape[2]),
        },
        "leakage_contract": {
            "response_source": "target_region_Y_only",
            "anchor_alignment": "required_equal_across_active_regions",
            "neighbor_response_used_as_input": False,
            "target_future_price_used_as_input": False,
            "lead_covariate_status": "realized_ex_post",
        },
        "feature_provenance": provenance,
    }
    return out


def load_feature_window(data_cfg, fold, region, split, smoke):
    policy = _feature_policy(smoke)
    if policy == "target_only":
        window = load_window(data_cfg, fold, region, split)
        window["feature_policy_manifest"] = {
            "feature_policy": "target_only",
            "input_scope": "local_target_only",
            "output_scope": "target_region_path",
            "lead_covariate_status": "realized_ex_post",
            "spatial_information_set": "local_only_not_pricefm_graph",
            "graph": None,
            "source_windows": [_source_window_manifest(region, split, window)],
        }
        return window
    if policy == "graph_khop":
        return _combine_graph_windows(data_cfg, fold, region, split, smoke)
    if policy == "graph_summary_mean":
        return _combine_graph_summary_windows(data_cfg, fold, region, split, smoke, "mean")
    if policy == "graph_summary_mean_std":
        return _combine_graph_summary_windows(data_cfg, fold, region, split, smoke, "mean_std")
    if policy == "graph_neighbor_direct":
        return _combine_graph_neighbor_direct_windows(data_cfg, fold, region, split, smoke)
    if policy == "graph_neighbor_spread_summary":
        return _combine_graph_neighbor_spread_summary_windows(data_cfg, fold, region, split, smoke)
    raise ValueError("Unknown feature_policy: {}".format(policy))


def horizon_features(horizons, selected_horizons):
    h = np.asarray(horizons, dtype=float)
    phase = 2.0 * np.pi * (h - 1.0) / 96.0
    scaled = (h - 1.0) / 95.0
    one_hot = np.zeros((h.size, len(selected_horizons)), dtype=float)
    pos = {int(v): i for i, v in enumerate(selected_horizons)}
    for i, val in enumerate(h.astype(int)):
        one_hot[i, pos[val]] = 1.0
    return np.column_stack([scaled, np.sin(phase), np.cos(phase), one_hot])


def supervised_rows(window, split, horizons):
    horizons = [int(h) for h in horizons]
    if any(h < 1 or h > window["Y"].shape[1] for h in horizons):
        raise ValueError("horizons must be within the available lead window")
    n_orig = window["Y"].shape[0]
    n_rows = n_orig * len(horizons)
    lag = np.empty((n_rows,) + window["X_lag"].shape[1:], dtype=float)
    lead = np.empty((n_rows,) + window["X_lead"].shape[1:], dtype=float)
    y = np.empty(n_rows, dtype=float)
    row_meta = []
    k = 0
    for origin_id, anchor in enumerate(window["anchors"]):
        anchor_ts = pd.Timestamp(str(anchor))
        if anchor_ts.tzinfo is None:
            anchor_ts = anchor_ts.tz_localize("UTC")
        else:
            anchor_ts = anchor_ts.tz_convert("UTC")
        for h in horizons:
            lag[k] = window["X_lag"][origin_id]
            lead[k] = window["X_lead"][origin_id]
            y[k] = window["Y"][origin_id, h - 1]
            response_ts = anchor_ts + pd.Timedelta(minutes=15 * (h - 1))
            row_meta.append({
                "split": split,
                "origin_id": origin_id,
                "horizon": h,
                "origin_market_time": anchor_ts.isoformat(),
                "response_market_time": response_ts.isoformat(),
                "y_scaled": float(y[k]),
            })
            k += 1
    return lag, lead, y, row_meta


def raw_row_features(lag, lead, horizons, selected_horizons):
    n = lag.shape[0]
    flat = np.column_stack([
        lag.reshape(n, -1),
        lead.reshape(n, -1),
        horizon_features(horizons, selected_horizons),
    ])
    return flat


def supervised_response_rows(window, split, horizons):
    horizons = [int(h) for h in horizons]
    if any(h < 1 or h > window["Y"].shape[1] for h in horizons):
        raise ValueError("horizons must be within the available lead window")
    n_orig = window["Y"].shape[0]
    n_rows = n_orig * len(horizons)
    y = np.empty(n_rows, dtype=float)
    origin_index = np.empty(n_rows, dtype=int)
    horizon_index = np.empty(n_rows, dtype=int)
    row_meta = []
    k = 0
    for origin_id, anchor in enumerate(window["anchors"]):
        anchor_ts = pd.Timestamp(str(anchor))
        if anchor_ts.tzinfo is None:
            anchor_ts = anchor_ts.tz_localize("UTC")
        else:
            anchor_ts = anchor_ts.tz_convert("UTC")
        for h_pos, h in enumerate(horizons):
            y[k] = window["Y"][origin_id, h - 1]
            response_ts = anchor_ts + pd.Timedelta(minutes=15 * (h - 1))
            row_meta.append({
                "split": split,
                "origin_id": origin_id,
                "horizon": h,
                "origin_market_time": anchor_ts.isoformat(),
                "response_market_time": response_ts.isoformat(),
                "y_scaled": float(y[k]),
            })
            origin_index[k] = origin_id
            horizon_index[k] = h_pos
            k += 1
    return y, row_meta, origin_index, horizon_index


def raw_feature_dim(window, selected_horizons):
    return (
        int(np.prod(window["X_lag"].shape[1:]))
        + int(np.prod(window["X_lead"].shape[1:]))
        + 3
        + len(selected_horizons)
    )


def make_mapping(raw_dim, feature_dim, seed):
    return np.random.default_rng(int(seed)).normal(
        0.0, 1.0 / np.sqrt(int(raw_dim)), size=(int(raw_dim), int(feature_dim))
    )


def _expand_positive_ints(value, depth, name):
    if isinstance(value, (list, tuple)):
        out = [int(x) for x in value]
    else:
        out = [int(value)] * int(depth)
    if len(out) != int(depth):
        raise ValueError("{} must have length depth={}".format(name, int(depth)))
    if any(x < 1 for x in out):
        raise ValueError("{} entries must be positive integers".format(name))
    return out


def _expand_floats(value, depth, name):
    if isinstance(value, (list, tuple)):
        out = [float(x) for x in value]
    else:
        out = [float(value)] * int(depth)
    if len(out) != int(depth):
        raise ValueError("{} must have length depth={}".format(name, int(depth)))
    if any(not np.isfinite(x) for x in out):
        raise ValueError("{} entries must be finite".format(name))
    return out


def normalize_reservoir_config(adapter_cfg, feature_dim):
    depth = int(adapter_cfg.get("depth", 1))
    if depth < 1:
        raise ValueError("reservoir depth must be positive")
    units = _expand_positive_ints(adapter_cfg.get("units", feature_dim), depth, "reservoir units")
    alpha = _expand_floats(adapter_cfg.get("alpha", 0.7), depth, "reservoir alpha")
    rho = _expand_floats(adapter_cfg.get("rho", 0.9), depth, "reservoir rho")
    input_scale = _expand_floats(adapter_cfg.get("input_scale", 0.5), depth, "reservoir input_scale")
    density = _expand_floats(
        adapter_cfg.get("recurrent_density", adapter_cfg.get("recurrent_sparsity", 0.05)),
        depth,
        "reservoir recurrent_sparsity",
    )
    bias_scale = _expand_floats(adapter_cfg.get("bias_scale", 0.0), depth, "reservoir bias_scale")
    if any(x <= 0.0 or x > 1.0 for x in alpha):
        raise ValueError("reservoir alpha entries must be in (0, 1]")
    if any(x < 0.0 for x in rho):
        raise ValueError("reservoir rho entries must be non-negative")
    if any(x <= 0.0 for x in input_scale):
        raise ValueError("reservoir input_scale entries must be positive")
    if any(x <= 0.0 or x > 1.0 for x in density):
        raise ValueError("reservoir recurrent_sparsity entries must be in (0, 1]")
    if any(x < 0.0 for x in bias_scale):
        raise ValueError("reservoir bias_scale entries must be non-negative")
    activation = str(adapter_cfg.get("reservoir_activation", "tanh"))
    if activation != "tanh":
        raise ValueError("Only reservoir_activation='tanh' is currently supported")
    state_output = str(adapter_cfg.get("state_output", "final_layer"))
    if state_output not in ("final_layer", "concat_layers"):
        raise ValueError("state_output must be 'final_layer' or 'concat_layers'")
    return {
        "version": "window_reservoir_v1",
        "depth": depth,
        "units": units,
        "alpha": alpha,
        "rho": rho,
        "input_scale": input_scale,
        "recurrent_sparsity": density,
        "bias_scale": bias_scale,
        "reservoir_activation": activation,
        "state_output": state_output,
    }


def _scaled_recurrent_matrix(rng, units, density, rho):
    mask = rng.random((units, units)) < float(density)
    if not np.any(mask) or float(rho) == 0.0:
        return np.zeros((units, units), dtype=float)
    sd = 1.0 / np.sqrt(max(1.0, float(units) * float(density)))
    mat = rng.normal(0.0, sd, size=(units, units)) * mask
    radius = float(np.max(np.abs(np.linalg.eigvals(mat))))
    if not np.isfinite(radius) or radius <= 0.0:
        return np.zeros((units, units), dtype=float)
    return mat * (float(rho) / radius)


def make_reservoir_matrices(input_dim, reservoir_config, seed):
    rng = np.random.default_rng(int(seed))
    layers = []
    arrays = {}
    prev_dim = int(input_dim)
    for i, units in enumerate(reservoir_config["units"]):
        input_matrix = rng.normal(
            0.0,
            float(reservoir_config["input_scale"][i]) / np.sqrt(max(1, prev_dim)),
            size=(prev_dim, int(units)),
        )
        recurrent_matrix = _scaled_recurrent_matrix(
            rng,
            int(units),
            float(reservoir_config["recurrent_sparsity"][i]),
            float(reservoir_config["rho"][i]),
        )
        bias = np.zeros(int(units), dtype=float)
        if float(reservoir_config["bias_scale"][i]) > 0.0:
            bias = rng.normal(0.0, float(reservoir_config["bias_scale"][i]), size=int(units))
        layer = {
            "input": input_matrix,
            "recurrent": recurrent_matrix,
            "bias": bias,
        }
        layers.append(layer)
        arrays["layer{}_input".format(i + 1)] = input_matrix
        arrays["layer{}_recurrent".format(i + 1)] = recurrent_matrix
        arrays["layer{}_bias".format(i + 1)] = bias
        prev_dim = int(units)
    return {
        "input_dim": int(input_dim),
        "config": dict(reservoir_config),
        "layers": layers,
        "arrays": arrays,
        "sha256": sha256_arrays(arrays),
    }


def reservoir_state_dim(reservoir_config):
    if reservoir_config["state_output"] == "concat_layers":
        return int(sum(reservoir_config["units"]))
    return int(reservoir_config["units"][-1])


def compute_reservoir_states(x_lag, reservoir, reservoir_config):
    x_lag = np.asarray(x_lag, dtype=float)
    n_origins = int(x_lag.shape[0])
    states = [
        np.zeros((n_origins, int(units)), dtype=float)
        for units in reservoir_config["units"]
    ]
    activation_stats = init_activation_stats()
    for t in range(int(x_lag.shape[1])):
        layer_input = x_lag[:, t, :]
        for layer_id, layer in enumerate(reservoir["layers"]):
            pre = layer_input @ layer["input"] + states[layer_id] @ layer["recurrent"] + layer["bias"]
            update_activation_stats(activation_stats, pre)
            candidate = np.tanh(pre)
            a = float(reservoir_config["alpha"][layer_id])
            states[layer_id] = (1.0 - a) * states[layer_id] + a * candidate
            layer_input = states[layer_id]
    if reservoir_config["state_output"] == "concat_layers":
        return np.column_stack(states), finalize_activation_stats(activation_stats)
    return states[-1], finalize_activation_stats(activation_stats)


def init_activation_stats():
    return {
        "count": 0,
        "sum": 0.0,
        "sumsq": 0.0,
        "min": None,
        "max": None,
        "abs_gt_2": 0,
        "abs_gt_4": 0,
    }


def update_activation_stats(stats, z):
    arr = np.asarray(z, dtype=float)
    if arr.size == 0:
        return stats
    stats["count"] += int(arr.size)
    stats["sum"] += float(np.sum(arr))
    stats["sumsq"] += float(np.sum(arr * arr))
    stats["min"] = float(np.min(arr)) if stats["min"] is None else min(stats["min"], float(np.min(arr)))
    stats["max"] = float(np.max(arr)) if stats["max"] is None else max(stats["max"], float(np.max(arr)))
    stats["abs_gt_2"] += int(np.sum(np.abs(arr) > 2.0))
    stats["abs_gt_4"] += int(np.sum(np.abs(arr) > 4.0))
    return stats


def finalize_activation_stats(stats):
    if stats is None:
        return None
    count = int(stats["count"])
    if count <= 0:
        return None
    mean = stats["sum"] / count
    var = max(0.0, stats["sumsq"] / count - mean * mean)
    return {
        "count": count,
        "mean": float(mean),
        "sd": float(np.sqrt(var)),
        "min": float(stats["min"]),
        "max": float(stats["max"]),
        "frac_abs_gt_2": float(stats["abs_gt_2"] / count),
        "frac_abs_gt_4": float(stats["abs_gt_4"] / count),
    }


def make_design_chunked(window, split, horizons, selected_horizons, feature_map,
                        feature_dim, seed, include_intercept=True,
                        row_chunk_size=2048, mapping=None,
                        projection_scale=1.0, reservoir_config=None):
    feature_map = str(feature_map)
    if feature_map not in ("flat_direct", "window_desn_v1", "window_reservoir_v1"):
        raise ValueError("Unknown feature_map: {}".format(feature_map))
    feature_dim = int(feature_dim)
    if feature_map == "window_desn_v1" and feature_dim < 1:
        raise ValueError("feature_dim must be positive")
    projection_scale = float(projection_scale)
    if not np.isfinite(projection_scale) or projection_scale <= 0.0:
        raise ValueError("projection_scale must be finite and positive")
    row_chunk_size = max(1, int(row_chunk_size))

    y, rows, origin_index, horizon_index = supervised_response_rows(window, split, horizons)
    raw_dim = raw_feature_dim(window, selected_horizons)
    if feature_map == "window_desn_v1" and mapping is None:
        mapping = make_mapping(raw_dim, feature_dim, seed)
    elif feature_map == "window_desn_v1" and tuple(mapping.shape) != (raw_dim, feature_dim):
        raise ValueError(
            "feature mapping shape {} does not match required ({}, {})".format(
                tuple(mapping.shape), raw_dim, feature_dim
            )
        )
    if feature_map == "window_reservoir_v1":
        if reservoir_config is None:
            reservoir_config = normalize_reservoir_config({}, feature_dim)
        input_dim = int(window["X_lag"].shape[2])
        if mapping is None:
            mapping = make_reservoir_matrices(input_dim, reservoir_config, seed)
        elif int(mapping["input_dim"]) != input_dim:
            raise ValueError(
                "reservoir input_dim {} does not match required {}".format(
                    int(mapping["input_dim"]), input_dim
                )
            )

    n_rows = y.size
    lead_dim = int(window["X_lead"].shape[2])
    horizon_dim = 3 + len(selected_horizons)
    if feature_map == "flat_direct":
        n_core_features = raw_dim
    elif feature_map == "window_reservoir_v1":
        n_core_features = reservoir_state_dim(reservoir_config) + lead_dim + horizon_dim
    else:
        n_core_features = feature_dim
    n_features = n_core_features + (1 if include_intercept else 0)
    X = np.empty((n_rows, n_features), dtype=float)
    h_values = np.asarray(horizons, dtype=int)
    activation_stats = init_activation_stats() if feature_map == "window_desn_v1" else None
    reservoir_states = None
    reservoir_activation_summary = None
    if feature_map == "window_reservoir_v1":
        reservoir_states, reservoir_activation_summary = compute_reservoir_states(
            window["X_lag"], mapping, reservoir_config
        )
    for start in range(0, n_rows, row_chunk_size):
        end = min(start + row_chunk_size, n_rows)
        origins = origin_index[start:end]
        h_vec = h_values[horizon_index[start:end]]
        if feature_map == "flat_direct":
            raw = np.column_stack([
                window["X_lag"][origins].reshape(end - start, -1),
                window["X_lead"][origins].reshape(end - start, -1),
                horizon_features(h_vec, selected_horizons),
            ])
            feats = raw
        elif feature_map == "window_reservoir_v1":
            lead_at_h = window["X_lead"][origins, h_vec - 1, :].reshape(end - start, -1)
            feats = np.column_stack([
                projection_scale * reservoir_states[origins],
                lead_at_h,
                horizon_features(h_vec, selected_horizons),
            ])
        else:
            raw = np.column_stack([
                window["X_lag"][origins].reshape(end - start, -1),
                window["X_lead"][origins].reshape(end - start, -1),
                horizon_features(h_vec, selected_horizons),
            ])
            pre_tanh = projection_scale * (raw @ mapping)
            update_activation_stats(activation_stats, pre_tanh)
            feats = np.tanh(pre_tanh)
        if include_intercept:
            X[start:end, 0] = 1.0
            X[start:end, 1:] = feats
        else:
            X[start:end, :] = feats
    if feature_map == "window_reservoir_v1":
        return X, y, rows, mapping, reservoir_activation_summary
    return X, y, rows, mapping, finalize_activation_stats(activation_stats)


def subset_train_origins(window, limit=None, selection="tail"):
    if limit is None:
        return window, None
    limit = int(limit)
    if limit < 1:
        raise ValueError("train_origin_limit must be positive")
    n_orig = int(window["Y"].shape[0])
    keep_n = min(limit, n_orig)
    selection = str(selection or "tail")
    if selection == "tail":
        idx = np.arange(n_orig - keep_n, n_orig)
    elif selection == "head":
        idx = np.arange(0, keep_n)
    else:
        raise ValueError("Unknown train_origin_selection: {}".format(selection))
    out = dict(window)
    out["X_lag"] = window["X_lag"][idx]
    out["X_lead"] = window["X_lead"][idx]
    out["Y"] = window["Y"][idx]
    out["anchors"] = window["anchors"][idx]
    return out, {
        "requested": int(limit),
        "available": n_orig,
        "selected": int(keep_n),
        "selection": selection,
    }


def make_design(raw, feature_map, feature_dim, seed, include_intercept=True,
                projection_scale=1.0):
    feature_map = str(feature_map)
    if feature_map == "flat_direct":
        feats = raw
        mapping = None
    elif feature_map == "window_desn_v1":
        feature_dim = int(feature_dim)
        if feature_dim < 1:
            raise ValueError("feature_dim must be positive")
        projection_scale = float(projection_scale)
        if not np.isfinite(projection_scale) or projection_scale <= 0.0:
            raise ValueError("projection_scale must be finite and positive")
        rng = np.random.default_rng(int(seed))
        mapping = rng.normal(0.0, 1.0 / np.sqrt(raw.shape[1]), size=(raw.shape[1], feature_dim))
        feats = np.tanh(projection_scale * (raw @ mapping))
    else:
        raise ValueError("Unknown feature_map: {}".format(feature_map))

    if include_intercept:
        X = np.column_stack([np.ones(raw.shape[0]), feats])
    else:
        X = feats
    return X.astype(float), mapping


def write_matrix_csv(path, arr):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    np.savetxt(path, np.asarray(arr, dtype=float), delimiter=",", fmt="%.17g")


def write_rows_csv(path, rows):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "split", "origin_id", "horizon",
                "origin_market_time", "response_market_time", "y_scaled",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)


def write_feature_provenance_csv(path, rows):
    if not rows:
        return None
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "feature_policy", "source_region", "source_role", "input_block",
        "source_column", "source_feature", "within_block_position",
    ]
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row.get(k, "") for k in fieldnames})
    return path


def build_adapter(smoke_config_path, force=False):
    smoke = load_smoke_config(smoke_config_path)
    data_cfg = load_config(smoke["data_config"])
    out_dir = repo_path(smoke["adapter"]["output_dir"])
    if out_dir.exists() and not force:
        raise FileExistsError("{} exists; rerun with --force true".format(out_dir))
    out_dir.mkdir(parents=True, exist_ok=True)

    fold = int(smoke["fold"])
    region = smoke["region"]
    horizons = [int(h) for h in smoke["horizons"]]
    feature_map = smoke["adapter"]["feature_map"]
    feature_dim = int(smoke["adapter"]["feature_dim"])
    seed = int(smoke["adapter"]["seed"])
    include_intercept = bool(smoke["adapter"].get("include_intercept", True))
    row_chunk_size = int(smoke["adapter"].get("row_chunk_size", 2048))
    projection_scale = float(smoke["adapter"].get("projection_scale", 1.0))
    reservoir_config = (
        normalize_reservoir_config(smoke["adapter"], feature_dim)
        if str(feature_map) == "window_reservoir_v1"
        else None
    )
    training_cfg = smoke.get("training", {})
    train_origin_limit = training_cfg.get("train_origin_limit")
    train_origin_selection = training_cfg.get("train_origin_selection", "tail")

    combined_rows = []
    split_payload = {}
    mapping_hash = None
    mapping = None
    feature_names = None
    train_origin_subset = None
    for split in smoke.get("splits", ["train", "val", "test"]):
        window = load_feature_window(data_cfg, fold, region, split, smoke)
        if split == "train" and train_origin_limit is not None:
            window, train_origin_subset = subset_train_origins(
                window, train_origin_limit, train_origin_selection
            )
        X, y, rows, mapping, activation_summary = make_design_chunked(
            window,
            split,
            horizons,
            horizons,
            feature_map,
            feature_dim,
            seed,
            include_intercept=include_intercept,
            row_chunk_size=row_chunk_size,
            mapping=mapping,
            projection_scale=projection_scale,
            reservoir_config=reservoir_config,
        )
        if mapping is not None and mapping_hash is None:
            if feature_map == "window_desn_v1":
                mapping_hash = sha256_array(mapping)
                np.save(out_dir / "feature_map_matrix.npy", mapping)
            elif feature_map == "window_reservoir_v1":
                mapping_hash = mapping["sha256"]
                np.savez_compressed(out_dir / "feature_map_matrix.npz", **mapping["arrays"])
        if feature_names is None:
            n_features = X.shape[1]
            feature_names = ["intercept"] + ["feature_{:03d}".format(i) for i in range(1, n_features)]
            if not include_intercept:
                feature_names = ["feature_{:03d}".format(i) for i in range(n_features)]

        write_matrix_csv(out_dir / "X_{}.csv".format(split), X)
        write_matrix_csv(out_dir / "y_{}.csv".format(split), y.reshape(-1, 1))
        write_rows_csv(out_dir / "rows_{}.csv".format(split), rows)
        combined_rows.extend(rows)
        split_payload[split] = {
            "window_path": str(window["path"]),
            "n_rows": int(X.shape[0]),
            "n_origins": int(window["Y"].shape[0]),
            "n_features": int(X.shape[1]),
            "feature_policy_manifest": window.get("feature_policy_manifest"),
            "X_sha256": sha256_file(out_dir / "X_{}.csv".format(split)),
            "y_sha256": sha256_file(out_dir / "y_{}.csv".format(split)),
            "rows_sha256": sha256_file(out_dir / "rows_{}.csv".format(split)),
            "activation_summary": (
                activation_summary
                if feature_map in ("window_desn_v1", "window_reservoir_v1")
                else None
            ),
        }

    write_rows_csv(out_dir / "rows_all.csv", combined_rows)
    feature_manifest = {
        "feature_policy": _feature_policy(smoke),
        "feature_policy_manifest": split_payload.get("train", {}).get("feature_policy_manifest"),
        "feature_map": feature_map,
        "feature_dim": feature_dim,
        "projection_scale": projection_scale,
        "seed": seed,
        "include_intercept": include_intercept,
        "feature_names": feature_names,
        "feature_map_matrix_sha256": mapping_hash,
        "horizon_features": ["scaled_horizon", "sin_phase", "cos_phase", "selected_horizon_one_hot"],
        "row_chunk_size": row_chunk_size,
    }
    if reservoir_config is not None:
        feature_manifest["reservoir"] = dict(reservoir_config)
        feature_manifest["reservoir_config_sha256"] = sha256_json(reservoir_config)
    provenance_rows = (
        (feature_manifest.get("feature_policy_manifest") or {}).get("feature_provenance")
        or []
    )
    provenance_path = write_feature_provenance_csv(
        out_dir / "feature_provenance.csv",
        provenance_rows,
    )
    if provenance_path is not None:
        feature_manifest["feature_provenance_path"] = config_path_value(provenance_path)
        feature_manifest["feature_provenance_sha256"] = sha256_file(provenance_path)
        feature_manifest["feature_provenance_rows"] = int(len(provenance_rows))
    write_json(out_dir / "feature_manifest.json", feature_manifest)
    manifest = {
        "smoke_config_path": smoke_config_path,
        "region": region,
        "fold": fold,
        "horizons": horizons,
        "quantiles": smoke["quantiles"],
        "layout": "stacked_origin_by_horizon",
        "train_origin_subset": train_origin_subset,
        "splits": split_payload,
        "row_manifest_sha256": sha256_file(out_dir / "rows_all.csv"),
        "feature_manifest_sha256": sha256_file(out_dir / "feature_manifest.json"),
        "feature_manifest": feature_manifest,
    }
    write_json(out_dir / "adapter_manifest.json", manifest)
    return manifest
