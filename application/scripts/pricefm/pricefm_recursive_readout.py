"""Shared readout construction for causal PriceFM DESN rollouts."""

from __future__ import annotations

from typing import Sequence

import numpy as np


READOUT_MODES = ("state_lead_horizon", "state_horizon", "state_only")


def readout_dimension(
    state_dimension: int,
    lead_dimension: int,
    horizon_dimension: int,
    mode: str,
) -> int:
    """Return the exact coefficient dimension for a supported readout."""

    mode = str(mode)
    if mode not in READOUT_MODES:
        raise ValueError(f"unsupported PriceFM readout mode: {mode}")
    result = 1 + int(state_dimension)
    if mode == "state_lead_horizon":
        result += int(lead_dimension) + int(horizon_dimension)
    elif mode == "state_horizon":
        result += int(horizon_dimension)
    return result


def readout_feature_names(
    state_dimension: int,
    lead_names: Sequence[str],
    horizon_dimension: int,
    mode: str,
) -> list[str]:
    """Return stable feature names in the same order as ``build_readout_rows``."""

    mode = str(mode)
    readout_dimension(state_dimension, len(lead_names), horizon_dimension, mode)
    names = ["intercept"] + [
        "state_{:04d}".format(index + 1) for index in range(int(state_dimension))
    ]
    if mode == "state_lead_horizon":
        names.extend("lead::{}".format(name) for name in lead_names)
    if mode in {"state_lead_horizon", "state_horizon"}:
        names.extend(
            "horizon_{:03d}".format(index + 1)
            for index in range(int(horizon_dimension))
        )
    return names


def build_readout_rows(
    state: np.ndarray,
    lead: np.ndarray,
    horizon_basis: np.ndarray,
    mode: str,
) -> np.ndarray:
    """Build one horizon's readout without changing the rolled DESN state.

    Future exogenous values may still enter the state transition upstream.
    ``state_horizon`` and ``state_only`` merely prevent those values from
    bypassing the reservoir through the linear readout.
    """

    state = np.asarray(state, dtype=float)
    lead = np.asarray(lead, dtype=float)
    horizon_basis = np.asarray(horizon_basis, dtype=float)
    mode = str(mode)
    if state.ndim != 2 or lead.ndim != 2 or horizon_basis.ndim != 2:
        raise ValueError("readout inputs must be two-dimensional")
    if len({state.shape[0], lead.shape[0], horizon_basis.shape[0]}) != 1:
        raise ValueError("readout inputs must have the same row count")
    readout_dimension(state.shape[1], lead.shape[1], horizon_basis.shape[1], mode)
    parts = [np.ones((state.shape[0], 1), dtype=float), state]
    if mode == "state_lead_horizon":
        parts.extend([lead, horizon_basis])
    elif mode == "state_horizon":
        parts.append(horizon_basis)
    result = np.column_stack(parts)
    if not np.isfinite(result).all():
        raise ValueError("readout contains non-finite values")
    return result
