#!/usr/bin/env python3
"""Deterministic design and gate helpers for PriceFM Stage R121."""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any, Iterable, Mapping

import numpy as np
import pandas as pd
from scipy.stats import spearmanr

from pricefm_r120_engine import (
    SOURCE_WINDOW, WARMUP_STEPS, ExplicitArrays, active_regions, fingerprint,
    normalize_spec, resource_estimate,
)


TAG = "pricefm_stage_r121_bg_targeted_dense_refinement_20260927"
R120_TAG = "pricefm_stage_r120_bg_explicit_lag_all_layer_search_20260925"
SEEDS = (2026092501, 2026092602, 2026092703)
QUANTILE_ORDER = (0.50, 0.45, 0.55, 0.25, 0.75, 0.10, 0.90)
M_Y = (600, 672, 700, 720, 730)
M_X = (0, 24, 48)
GEOMETRIES = (
    (128,), (160,), (192,), (224,), (256,), (320,),
    (96, 96), (128, 128), (160, 160), (192, 192), (256, 256),
    (192, 128), (256, 128),
    (96, 64, 48), (128, 96, 64), (192, 128, 96),
)
ALPHAS = (0.025, 0.05, 0.075, 0.10, 0.15, 0.20, 0.35)
RHOS = (0.55, 0.65, 0.70, 0.76, 0.82, 0.90, 0.95)
INPUT_SCALES = (0.025, 0.05, 0.075, 0.10, 0.15, 0.25, 0.50)
INPUT_FAN_INS = (8, 16, 24, 32, 64, 128, 256)
SPARSITIES = (0.02, 0.05, 0.075, 0.10, 0.15, 0.20)
CALENDARS = ("none", "compact3")
POLICIES = (
    "target_only", "graph_summary_mean", "graph_neighbor_exogenous",
    "graph_summary_mean_std",
)


def exog_dimension(spec: Mapping[str, Any]) -> int:
    policy = str(spec["feature_policy"])
    if policy == "target_only":
        return 3
    if policy == "graph_summary_mean":
        return 6
    if policy == "graph_summary_mean_std":
        return 9
    return 3 * len(active_regions(spec))


def manifest_row(spec: Mapping[str, Any], role: str, anchor_id: str = "") -> dict[str, Any]:
    value = normalize_spec(spec)
    identity = fingerprint(value)
    resources = resource_estimate(value, exog_dimension(value))
    return {
        "candidate_id": f"r121_{identity[:16]}", "stage": "R121",
        "candidate_role": role, "anchor_id": anchor_id,
        "semantic_sha256": identity,
        "spec_json": json.dumps(value, sort_keys=True, separators=(",", ":")),
        **{key: item for key, item in value.items() if key != "units"},
        "units": json.dumps(value["units"], separators=(",", ":")),
        "exog_dimension": exog_dimension(value), **resources,
        "selection_split": "fold1_train_internal_expanding_validation",
        "test_access_authorized": False,
    }


def collapse_rhs(ranking: pd.DataFrame, specs: pd.DataFrame) -> pd.DataFrame:
    """Collapse tau duplicates and attach complete candidate specifications."""
    ordered = ranking.sort_values(
        ["mean_AQL", "mean_late_AQL", "worst_AQL", "candidate_id", "tau0"],
        kind="mergesort",
    ).drop_duplicates("candidate_id", keep="first")
    keep = specs.drop_duplicates("candidate_id", keep="first")
    result = ordered.merge(keep, on="candidate_id", how="inner", validate="one_to_one")
    if result.empty:
        raise ValueError("R121 found no complete R120 RHS specifications")
    return result.reset_index(drop=True)


def select_bridge_panel(complete: pd.DataFrame) -> pd.DataFrame:
    selected: list[pd.Series] = []
    reasons: list[str] = []

    def add(frame: pd.DataFrame, reason: str, count: int = 1) -> None:
        nonlocal selected, reasons
        used = {str(row.candidate_id) for row in selected}
        for _, row in frame.iterrows():
            if str(row.candidate_id) in used:
                continue
            selected.append(row); reasons.append(reason); used.add(str(row.candidate_id))
            if sum(value == reason for value in reasons) >= count:
                break

    add(complete.iloc[[0]], "rhs_winner")
    add(complete.iloc[1:], "next_best_complete_rhs", 2)
    add(complete[complete.depth.astype(int).eq(2)], "stable_d2")
    d3 = complete[complete.depth.astype(int).eq(3)]
    add(d3 if not d3.empty else complete[complete.depth.astype(int).eq(2)], "stable_d3_or_fallback_d2")
    represented = {str(row.feature_policy) for row in selected}
    sentinel = complete[~complete.feature_policy.astype(str).isin(represented)]
    add(sentinel if not sentinel.empty else complete, "graph_policy_sentinel")
    add(complete, "rank_fill", 6)
    if len(selected) < 6:
        raise ValueError("R121 cannot construct the six-candidate bridge panel")
    panel = pd.DataFrame([row.to_dict() for row in selected[:6]])
    panel.insert(0, "bridge_position", np.arange(1, 7))
    panel.insert(1, "bridge_reason", reasons[:6])
    if panel.candidate_id.duplicated().any():
        raise ValueError("R121 bridge panel contains duplicate candidates")
    return panel


def select_anchors(complete: pd.DataFrame, bridge: pd.DataFrame, maximum: int = 12) -> pd.DataFrame:
    chosen: list[pd.Series] = []
    reasons: list[str] = []

    def add_rows(frame: pd.DataFrame, reason: str) -> None:
        used = {str(row.candidate_id) for row in chosen}
        for _, row in frame.iterrows():
            if len(chosen) >= maximum:
                return
            if str(row.candidate_id) not in used:
                chosen.append(row); reasons.append(reason); used.add(str(row.candidate_id))

    add_rows(complete.iloc[[0]], "r120_rhs_winner")
    add_rows(bridge, "bridge_panel")
    for policy in POLICIES:
        add_rows(complete[complete.feature_policy.astype(str).eq(policy)].head(1), f"policy_diversity_{policy}")
    for depth in (1, 2, 3):
        add_rows(complete[complete.depth.astype(int).eq(depth)].head(1), f"depth_diversity_d{depth}")
    add_rows(complete, "best_remaining_complete_rhs")
    anchors = pd.DataFrame([row.to_dict() for row in chosen])
    anchors.insert(0, "anchor_position", np.arange(1, len(anchors) + 1))
    anchors.insert(1, "inclusion_reason", reasons)
    return anchors


def _nearest(values: tuple[Any, ...], value: Any) -> int:
    if value in values:
        return values.index(value)
    if isinstance(value, (int, float)):
        return int(np.argmin([abs(float(item) - float(value)) for item in values]))
    return 0


def _base_from_row(row: Mapping[str, Any]) -> dict[str, Any]:
    raw = row.get("spec_json")
    if raw is not None and not (isinstance(raw, float) and math.isnan(raw)):
        return normalize_spec(json.loads(str(raw)))
    units = row["units"]
    if isinstance(units, str):
        units = json.loads(units)
    return normalize_spec({
        "region": "BG", "feature_policy": row["feature_policy"],
        "calendar": row["calendar"], "readout": "pure_all_layers",
        "m_y": int(row["m_y"]), "m_x": int(row["m_x"]),
        "units": units, "alpha": float(row["alpha"]), "rho": float(row["rho"]),
        "input_scale": float(row["input_scale"]), "input_fan_in": int(row["input_fan_in"]),
        "recurrent_sparsity": float(row["recurrent_sparsity"]), "seed": int(row["seed"]),
    })


def _proposal(base: Mapping[str, Any], **changes: Any) -> dict[str, Any]:
    value = dict(base); value.update(changes)
    if "units" in value:
        value["depth"] = len(value["units"])
    value.update({"region": "BG", "readout": "pure_all_layers",
                  "source_window": SOURCE_WINDOW, "warmup_steps": WARMUP_STEPS})
    return normalize_spec(value)


def _distance_encoding(spec: Mapping[str, Any]) -> np.ndarray:
    value = normalize_spec(spec); units = tuple(value["units"])
    def rank(items: tuple[Any, ...], item: Any) -> float:
        return _nearest(items, item) / max(1, len(items) - 1)
    taper = min(units) / max(units)
    geometry = np.asarray((rank((1, 2, 3), len(units)), sum(units) / 640.0,
                           max(units) / 320.0, taper, (1 + sum(units)) / 641.0))
    groups = [
        np.asarray((rank(M_Y, value["m_y"]), rank(M_X, value["m_x"]))),
        geometry,
        np.asarray((rank(ALPHAS, value["alpha"]), rank(RHOS, value["rho"]))),
        np.asarray((rank(INPUT_SCALES, value["input_scale"]), rank(INPUT_FAN_INS, value["input_fan_in"]),
                    rank(SPARSITIES, value["recurrent_sparsity"]))),
        np.asarray((rank(POLICIES, value["feature_policy"]), rank(CALENDARS, value["calendar"]))),
    ]
    return np.concatenate([group / len(group) for group in groups])


def _maximin(pool: list[dict[str, Any]], selected: list[dict[str, Any]], count: int) -> list[dict[str, Any]]:
    if count <= 0 or not pool:
        return []
    pool = sorted(pool, key=fingerprint)
    encoded = np.stack([_distance_encoding(value) for value in pool])
    chosen = np.stack([_distance_encoding(value) for value in selected])
    minimum = np.min(np.abs(encoded[:, None] - chosen[None, :]).sum(axis=2) / 5.0, axis=1)
    live = np.ones(len(pool), dtype=bool); output: list[dict[str, Any]] = []
    for _ in range(min(count, len(pool))):
        masked = np.where(live, minimum, -np.inf); index = int(np.argmax(masked))
        output.append(pool[index]); live[index] = False
        distance = np.abs(encoded - encoded[index]).sum(axis=1) / 5.0
        minimum = np.minimum(minimum, distance)
    return output


def candidate_manifest(anchors: pd.DataFrame, maximum: int = 1200) -> tuple[pd.DataFrame, dict[str, Any]]:
    if maximum > 1200 or maximum < 100:
        raise ValueError("R121 candidate ceiling must be in [100, 1200]")
    rows: dict[str, tuple[dict[str, Any], str, str]] = {}
    def add(spec: Mapping[str, Any], role: str, anchor_id: str = "") -> None:
        value = normalize_spec(spec); key = fingerprint(value)
        rows.setdefault(key, (value, role, anchor_id))

    for position, row in anchors.iterrows():
        base = _base_from_row(row); anchor_id = f"anchor_{position + 1:02d}"
        add(base, "exact_r120_anchor", anchor_id)
        fields = {
            "m_y": M_Y, "m_x": M_X, "units": GEOMETRIES, "alpha": ALPHAS, "rho": RHOS,
            "input_scale": INPUT_SCALES, "input_fan_in": INPUT_FAN_INS,
            "recurrent_sparsity": SPARSITIES, "calendar": CALENDARS,
            "feature_policy": POLICIES,
        }
        for field, values in fields.items():
            original = tuple(base["units"]) if field == "units" else base[field]
            center = _nearest(values, original)
            for neighbor in (center - 1, center + 1):
                if 0 <= neighbor < len(values):
                    add(_proposal(base, **{field: values[neighbor]}), "adjacent_one_factor", anchor_id)

    center = _base_from_row(anchors.iloc[0])
    # Boundary sentinels are inserted before the larger pairwise pool so every
    # admissible campaign ceiling retains declared marginal coverage.
    boundary_fields = {
        "m_y": M_Y, "m_x": M_X, "units": GEOMETRIES, "alpha": ALPHAS, "rho": RHOS,
        "input_scale": INPUT_SCALES, "input_fan_in": INPUT_FAN_INS,
        "recurrent_sparsity": SPARSITIES, "calendar": CALENDARS,
        "feature_policy": POLICIES,
    }
    for field, values in boundary_fields.items():
        for value in values:
            add(_proposal(center, **{field: value}), f"boundary_{field}", "anchor_01")
    pair_slices = (
        ("alpha", ALPHAS, "rho", RHOS), ("alpha", ALPHAS, "m_y", M_Y),
        ("input_scale", INPUT_SCALES, "input_fan_in", INPUT_FAN_INS),
        ("units", GEOMETRIES, "recurrent_sparsity", SPARSITIES),
        ("feature_policy", POLICIES, "m_x", M_X),
    )
    for left, left_values, right, right_values in pair_slices:
        for one in left_values:
            for two in right_values:
                add(_proposal(center, **{left: one, right: two}), f"pairwise_{left}_x_{right}", "anchor_01")

    selected = [value[0] for value in rows.values()]
    rng = np.random.default_rng(2026092701); pool_by_hash: dict[str, dict[str, Any]] = {}
    while len(pool_by_hash) < 6000:
        geometry = GEOMETRIES[int(rng.integers(len(GEOMETRIES)))]
        value = _proposal(center, m_y=M_Y[int(rng.integers(len(M_Y)))], m_x=M_X[int(rng.integers(len(M_X)))],
            units=geometry, alpha=ALPHAS[int(rng.integers(len(ALPHAS)))], rho=RHOS[int(rng.integers(len(RHOS)))],
            input_scale=INPUT_SCALES[int(rng.integers(len(INPUT_SCALES)))],
            input_fan_in=INPUT_FAN_INS[int(rng.integers(len(INPUT_FAN_INS)))],
            recurrent_sparsity=SPARSITIES[int(rng.integers(len(SPARSITIES)))],
            calendar=CALENDARS[int(rng.integers(len(CALENDARS)))],
            feature_policy=POLICIES[int(rng.integers(len(POLICIES)))])
        key = fingerprint(value)
        if key not in rows:
            pool_by_hash[key] = value
    fills = _maximin(list(pool_by_hash.values()), selected, maximum - len(rows))
    for value in fills:
        add(value, "deterministic_maximin")
    ordered = list(rows.values())[:maximum]
    frame = pd.DataFrame([manifest_row(spec, role, anchor) for spec, role, anchor in ordered])
    frame = frame.sort_values(["candidate_role", "candidate_id"], kind="mergesort").reset_index(drop=True)
    if frame.semantic_sha256.duplicated().any() or len(frame) > maximum:
        raise ValueError("R121 candidate uniqueness/ceiling gate failed")
    boundaries = {
        "m_y": set(frame.m_y.astype(int)), "m_x": set(frame.m_x.astype(int)),
        "depth": set(frame.depth.astype(int)), "alpha": set(frame.alpha.astype(float)),
        "rho": set(frame.rho.astype(float)), "input_scale": set(frame.input_scale.astype(float)),
        "input_fan_in": set(frame.input_fan_in.astype(int)),
        "recurrent_sparsity": set(frame.recurrent_sparsity.astype(float)),
        "calendar": set(frame.calendar.astype(str)), "feature_policy": set(frame.feature_policy.astype(str)),
    }
    required = {"m_y": set(M_Y), "m_x": set(M_X), "depth": {1, 2, 3}, "alpha": set(ALPHAS),
        "rho": set(RHOS), "input_scale": set(INPUT_SCALES), "input_fan_in": set(INPUT_FAN_INS),
        "recurrent_sparsity": set(SPARSITIES), "calendar": set(CALENDARS), "feature_policy": set(POLICIES)}
    if any(not required[key].issubset(boundaries[key]) for key in required):
        raise ValueError("R121 candidate boundary coverage gate failed")
    summary = {"candidate_count": len(frame), "maximum": maximum,
        "role_counts": frame.candidate_role.value_counts().sort_index().to_dict(),
        "proposal_seed": 2026092701, "algorithm": "r121_rank_hamming_maximin_v1"}
    return frame, summary


def subset_arrays(arrays: ExplicitArrays, indices: Iterable[int]) -> ExplicitArrays:
    idx = np.asarray(list(indices), dtype=int)
    return ExplicitArrays(arrays.price_history[idx], arrays.exog_history[idx], arrays.exog_future[idx],
                          arrays.response[idx], arrays.anchors[idx], arrays.exog_names, arrays.source_manifest)


def tau_center(readout_dimension: int, n_ref: int) -> float:
    r = int(readout_dimension) - 1
    if r <= 5 or n_ref <= 0:
        raise ValueError("R121 tau center requires r>5 and n_ref>0")
    m0 = min(20, max(5, round(math.sqrt(r))))
    return float((m0 / (r - m0)) / math.sqrt(n_ref))


def bridge_decision(metrics: pd.DataFrame) -> dict[str, Any]:
    required = {"candidate_id", "normal_AQL", "al_AQL", "family_eligible", "invalid_quantiles"}
    if not required.issubset(metrics.columns):
        raise ValueError("R121 bridge metrics are incomplete")
    eligible = metrics[metrics.family_eligible.astype(bool) & metrics.invalid_quantiles.astype(int).eq(0)].copy()
    correlation = float(spearmanr(eligible.normal_AQL, eligible.al_AQL).statistic) if len(eligible) >= 2 else float("nan")
    normal = eligible.sort_values(["normal_AQL", "candidate_id"], kind="mergesort").reset_index(drop=True)
    al_best = eligible.sort_values(["al_AQL", "candidate_id"], kind="mergesort").iloc[0].candidate_id if len(eligible) else None
    top_ids = set(normal.head(3).candidate_id)
    top_median = float(normal.head(3).al_AQL.median()) if len(normal) >= 3 else float("nan")
    bottom_median = float(normal.tail(3).al_AQL.median()) if len(normal) >= 3 else float("nan")
    checks = {
        "eligible_families": len(eligible) >= 5,
        "spearman": np.isfinite(correlation) and correlation >= 0.40,
        "best_al_in_normal_top3": al_best in top_ids,
        "top_half_direction": np.isfinite(top_median) and top_median < bottom_median,
        "no_invalid_quantile_lucky_case": not bool(((metrics.invalid_quantiles.astype(int) > 0) & metrics.al_AQL.notna()).any()),
    }
    return {"status": "BRIDGE_PASS" if all(checks.values()) else "NORMAL_PROXY_NOT_VALIDATED",
            "passed": bool(all(checks.values())), "checks": checks, "eligible_count": len(eligible),
            "spearman": correlation, "best_al_candidate_id": al_best,
            "normal_top3_candidate_ids": sorted(top_ids), "top_half_median_al_AQL": top_median,
            "bottom_half_median_al_AQL": bottom_median, "test_opened": False}


def normal_gate(candidate: Mapping[str, float], control: Mapping[str, float]) -> dict[str, Any]:
    checks = {
        "mean_gain": float(candidate["mean_AQL"]) <= 0.99 * float(control["mean_AQL"]),
        "late_harm": float(candidate["mean_late_AQL"]) <= 1.02 * float(control["mean_late_AQL"]),
        "worst_harm": float(candidate["worst_AQL"]) <= 1.03 * float(control["worst_AQL"]),
    }
    return {"passed": all(checks.values()), "checks": checks}


def fold1_gate(metrics: Mapping[str, float], r120_late: float, pricefm_width: float) -> dict[str, Any]:
    checks = {
        "AQL": float(metrics["AQL"]) <= 17.7564,
        "late_AQL": float(metrics["late_AQL"]) <= 1.02 * float(r120_late),
        "coverage": float(metrics["interval_80_coverage"]) >= 0.40,
        "width": float(metrics["interval_80_width"]) <= 1.5 * float(pricefm_width),
    }
    return {"passed": all(checks.values()), "checks": checks}
