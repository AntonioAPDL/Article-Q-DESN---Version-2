#!/usr/bin/env python3
"""Deterministic design and Stage-0 gates for PriceFM Stage R122.

R122 is deliberately isolated from the executed R120/R121 engines.  This
module contains no fitting or outer-fold access.  It builds the training-only
long-memory surface and classifies whether R121B supplied enough complete AL
evidence to authorize a Normal-proxy screen.
"""

from __future__ import annotations

import hashlib
import itertools
import json
import math
from typing import Any, Iterable, Mapping, Sequence

import numpy as np
import pandas as pd
from scipy.optimize import Bounds, LinearConstraint, milp
from scipy import sparse

from pricefm_graph import graph_adj_matrix


M_Y = (672, 730, 960, 1080, 1152, 1344, 1440, 1560, 2016, 2688, 2880)
M_X = (0, 24, 48, 96)
POLICIES = (
    "target_only",
    "graph_summary_mean",
    "graph_summary_mean_std",
    "graph_neighbor_exogenous",
)
FAN_INS = (8, 16, 32, 64, 128, 256)
RESERVOIR_SEEDS = (2026092501, 2026092502, 2026092503)
MAX_EXPLICIT_LAG = 2880
WARMUP_STEPS = 240
SOURCE_WINDOW = MAX_EXPLICIT_LAG + WARMUP_STEPS
SEARCH_PANEL_SIZE = 3199

BASINS: dict[str, dict[str, Any]] = {
    "A": {"units": [128, 96, 64], "alpha": .20, "rho": .55,
          "input_scale": .025, "recurrent_sparsity": .02,
          "native_m_x": 24, "native_policy": "target_only", "native_fan_in": 8},
    "B": {"units": [128, 96, 64], "alpha": .35, "rho": .65,
          "input_scale": .025, "recurrent_sparsity": .05,
          "native_m_x": 24, "native_policy": "graph_summary_mean_std", "native_fan_in": 8},
    "C": {"units": [128, 128], "alpha": .10, "rho": .82,
          "input_scale": .050, "recurrent_sparsity": .02,
          "native_m_x": 0, "native_policy": "target_only", "native_fan_in": 32},
    "D": {"units": [128, 128], "alpha": .10, "rho": .70,
          "input_scale": .050, "recurrent_sparsity": .05,
          "native_m_x": 0, "native_policy": "graph_summary_mean", "native_fan_in": 16},
    "E": {"units": [96, 96], "alpha": .10, "rho": .82,
          "input_scale": .050, "recurrent_sparsity": .02,
          "native_m_x": 0, "native_policy": "target_only", "native_fan_in": 64},
}


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def fingerprint(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def exogenous_dimension(policy: str, region: str = "BG") -> int:
    if policy == "target_only":
        return 3
    if policy == "graph_summary_mean":
        return 6
    if policy == "graph_summary_mean_std":
        return 9
    if policy == "graph_neighbor_exogenous":
        adjacency = graph_adj_matrix()
        neighbor_count = sum(str(item) != region for item in adjacency[region])
        return 3 * (1 + neighbor_count)
    raise ValueError(f"unsupported R122 feature policy: {policy}")


def structural_spec(m_y: int, m_x: int, basin: str, policy: str, fan_in: int) -> dict[str, Any]:
    if m_y not in M_Y or m_x not in M_X or basin not in BASINS or policy not in POLICIES or fan_in not in FAN_INS:
        raise ValueError("R122 structural factor outside the frozen surface")
    values = BASINS[basin]
    return {
        "region": "BG", "feature_policy": policy, "calendar": "none",
        "readout": "pure_all_layers", "m_y": int(m_y), "m_x": int(m_x),
        "source_window": SOURCE_WINDOW, "warmup_steps": WARMUP_STEPS,
        "basin": basin, "depth": len(values["units"]), "units": list(values["units"]),
        "alpha": values["alpha"], "rho": values["rho"],
        "input_scale": values["input_scale"], "input_fan_in": int(fan_in),
        "recurrent_sparsity": values["recurrent_sparsity"],
    }


def _row(spec: Mapping[str, Any]) -> dict[str, Any]:
    identity = fingerprint(dict(spec))
    dimension = int(spec["m_y"]) + (int(spec["m_x"]) + 1) * exogenous_dimension(str(spec["feature_policy"]))
    width = int(spec["units"][0])
    fan_in = min(int(spec["input_fan_in"]), dimension)
    exposure = 1 - (1 - fan_in / dimension) ** width
    return {
        "candidate_id": f"r122_{identity[:16]}", "structural_sha256": identity,
        "spec_json": canonical_json(dict(spec)), "region": "BG",
        "m_y": int(spec["m_y"]), "m_x": int(spec["m_x"]), "basin": str(spec["basin"]),
        "feature_policy": str(spec["feature_policy"]), "input_fan_in": int(spec["input_fan_in"]),
        "depth": int(spec["depth"]), "units": canonical_json(spec["units"]),
        "alpha": float(spec["alpha"]), "rho": float(spec["rho"]),
        "input_scale": float(spec["input_scale"]),
        "recurrent_sparsity": float(spec["recurrent_sparsity"]),
        "source_window": SOURCE_WINDOW, "warmup_steps": WARMUP_STEPS,
        "calendar": "none", "readout": "pure_all_layers",
        "input_dimension": dimension, "readout_dimension": 1 + sum(spec["units"]),
        "expected_input_feature_exposure": exposure,
        "test_access_authorized": False,
    }


def candidate_universe() -> pd.DataFrame:
    rows = [_row(structural_spec(*values)) for values in itertools.product(M_Y, M_X, BASINS, POLICIES, FAN_INS)]
    frame = pd.DataFrame(rows).sort_values("structural_sha256", kind="mergesort").reset_index(drop=True)
    if len(frame) != 5280 or frame.structural_sha256.duplicated().any():
        raise RuntimeError("R122 universe identity contract failed")
    return frame


def mandatory_identities(universe: pd.DataFrame) -> set[str]:
    selected: set[str] = set()
    for basin, values in BASINS.items():
        native = universe[
            universe.basin.eq(basin)
            & universe.m_x.eq(values["native_m_x"])
            & universe.feature_policy.eq(values["native_policy"])
        ]
        selected.update(native.structural_sha256)
    for basin in ("A", "B", "C"):
        values = BASINS[basin]
        cross = universe[universe.basin.eq(basin) & universe.input_fan_in.eq(values["native_fan_in"])]
        selected.update(cross.structural_sha256)
    for basin in ("A", "B", "C"):
        values = BASINS[basin]
        control = universe[
            universe.basin.eq(basin) & universe.m_y.eq(730)
            & universe.m_x.eq(values["native_m_x"])
            & universe.feature_policy.eq(values["native_policy"])
            & universe.input_fan_in.eq(values["native_fan_in"])
        ]
        selected.update(control.structural_sha256)
    return selected


def _balanced_panel_indices(universe: pd.DataFrame, target: int) -> np.ndarray:
    mandatory = mandatory_identities(universe)
    if len(mandatory) > target:
        raise RuntimeError("mandatory R122 panel exceeds target")
    n = len(universe)
    rows: list[np.ndarray] = [np.ones(n)]
    lower: list[float] = [target]
    upper: list[float] = [target]
    for factor in ("m_y", "m_x", "basin", "feature_policy", "input_fan_in"):
        levels = sorted(universe[factor].unique(), key=lambda value: str(value))
        floor = target // len(levels); ceiling = math.ceil(target / len(levels))
        for level in levels:
            rows.append(universe[factor].eq(level).to_numpy(dtype=float))
            lower.append(floor); upper.append(ceiling)
    matrix = sparse.csr_matrix(np.vstack(rows))
    fixed = universe.structural_sha256.isin(mandatory).to_numpy(dtype=float)
    bounds = Bounds(fixed, np.ones(n))
    order = universe.structural_sha256.rank(method="first").to_numpy(dtype=float)
    objective = order + (order / (n + 1)) ** 2
    result = milp(objective, integrality=np.ones(n), bounds=bounds,
                  constraints=LinearConstraint(matrix, np.asarray(lower), np.asarray(upper)),
                  options={"presolve": True, "time_limit": 120})
    if not result.success or result.x is None:
        raise RuntimeError(f"R122 exact-balance design failed: {result.message}")
    indices = np.flatnonzero(result.x > .5)
    if len(indices) != target:
        raise RuntimeError("R122 exact-balance solver returned the wrong panel size")
    return indices


def selected_panel(universe: pd.DataFrame | None = None, target: int = SEARCH_PANEL_SIZE) -> pd.DataFrame:
    values = candidate_universe() if universe is None else universe.copy()
    # Solver variable order is part of the deterministic contract.  Normalize
    # it before constructing constraints so a permuted manifest is identical.
    values = values.sort_values("structural_sha256", kind="mergesort").reset_index(drop=True)
    indices = _balanced_panel_indices(values, target)
    panel = values.iloc[indices].copy()
    mandatory = mandatory_identities(values)
    panel["selection_tier"] = np.where(panel.structural_sha256.isin(mandatory), "mandatory_cross", "exact_balance_fill")
    panel = panel.sort_values(["selection_tier", "structural_sha256"], kind="mergesort").reset_index(drop=True)
    if len(panel) != target or panel.structural_sha256.duplicated().any():
        raise RuntimeError("R122 selected-panel identity contract failed")
    for factor in ("m_y", "m_x", "basin", "feature_policy", "input_fan_in"):
        counts = panel[factor].value_counts()
        if counts.max() - counts.min() > 1:
            raise RuntimeError(f"R122 selected panel is not exactly balanced for {factor}")
    if not mandatory.issubset(set(panel.structural_sha256)):
        raise RuntimeError("R122 selected panel omitted a mandatory cross")
    return panel


def fit_manifest(panel: pd.DataFrame, seeds: Sequence[int] = RESERVOIR_SEEDS[:2]) -> pd.DataFrame:
    rows = []
    for row in panel.itertuples(index=False):
        for seed in seeds:
            fit_hash = fingerprint({"structural_sha256": row.structural_sha256, "reservoir_seed": int(seed)})
            rows.append({"candidate_id": row.candidate_id, "structural_sha256": row.structural_sha256,
                         "reservoir_seed": int(seed), "fit_sha256": fit_hash,
                         "canonical_seed": int(seed) == RESERVOIR_SEEDS[0],
                         "test_access_authorized": False})
    result = pd.DataFrame(rows).sort_values(["structural_sha256", "reservoir_seed"], kind="mergesort")
    if result.fit_sha256.duplicated().any() or len(result) != len(panel) * len(seeds):
        raise RuntimeError("R122 fit-manifest identity contract failed")
    return result.reset_index(drop=True)


def stage0_proxy_decision(normal_shortlist: pd.DataFrame, al_cells: pd.DataFrame) -> dict[str, Any]:
    """Classify proxy readiness without opening any outer-fold result."""
    required = {"candidate_id", "mean_AQL", "mean_late_AQL", "worst_AQL"}
    if not required.issubset(normal_shortlist.columns):
        raise ValueError("R122 Stage-0 decision requires frozen Normal rankings")
    complete = al_cells[al_cells.eligible.astype(bool)].groupby("candidate_id").filter(lambda group: len(group) == 3)
    aggregate = complete.groupby("candidate_id", as_index=False).agg(
        mean_AQL=("AQL", "mean"), mean_late_AQL=("late_AQL", "mean"), worst_AQL=("AQL", "max"))
    ordered = normal_shortlist.sort_values(["mean_AQL", "candidate_id"], kind="mergesort")
    candidate_a = str(ordered.iloc[0].candidate_id)
    complete_ids = set(aggregate.candidate_id)
    lower_ids = [str(value) for value in ordered.candidate_id.iloc[1:] if str(value) in complete_ids]
    checks = {
        "candidate_a_complete": candidate_a in complete_ids,
        "lower_ranked_comparator_complete": bool(lower_ids),
        "at_least_two_complete_families": len(complete_ids) >= 2,
    }
    relation: dict[str, Any] = {"evaluated": False, "passed": False}
    if all(checks.values()):
        comparator = lower_ids[0]
        a = aggregate[aggregate.candidate_id.eq(candidate_a)].iloc[0]
        b = aggregate[aggregate.candidate_id.eq(comparator)].iloc[0]
        same_direction_or_tie = float(a.mean_AQL) <= 1.02 * float(b.mean_AQL)
        late_ok = float(a.mean_late_AQL) <= 1.02 * float(b.mean_late_AQL)
        worst_ok = float(a.worst_AQL) <= 1.02 * float(b.worst_AQL)
        relation = {"evaluated": True, "candidate_a": candidate_a, "comparator": comparator,
                    "same_direction_or_practical_tie": same_direction_or_tie,
                    "late_harm_ok": late_ok, "worst_harm_ok": worst_ok,
                    "passed": same_direction_or_tie and (late_ok or worst_ok)}
    passed = all(checks.values()) and bool(relation["passed"])
    return {
        "status": "R122_PROXY_BRANCH_AUTHORIZED" if passed else "R122_STAGE0_REPAIR_REQUIRED",
        "passed": passed, "checks": checks, "relation": relation,
        "candidate_a": candidate_a, "complete_candidate_ids": sorted(complete_ids),
        "test_opened": False,
    }


def factor_coverage(panel: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for factor in ("m_y", "m_x", "basin", "feature_policy", "input_fan_in"):
        for level, count in panel[factor].value_counts(dropna=False).sort_index().items():
            rows.append({"factor": factor, "level": str(level), "count": int(count)})
    return pd.DataFrame(rows)
