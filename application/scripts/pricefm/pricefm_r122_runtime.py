#!/usr/bin/env python3
"""Isolated long-memory runtime adapter for PriceFM Stage R122.

R120 deliberately freezes a 970-row source window and a 730-step maximum
explicit lag.  R122 changes only those two design limits.  Loading the R120
engine under a private module name preserves the historical R120/R121 module
globals while reusing the already-tested reservoir and recursive-scoring
implementation.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
BASE_PATH = SCRIPT_DIR / "pricefm_r120_engine.py"
PRIVATE_MODULE_NAME = "pricefm_r120_engine_for_r122_long_memory"
MAX_EXPLICIT_LAG = 2880
WARMUP_STEPS = 240
SOURCE_WINDOW = MAX_EXPLICIT_LAG + WARMUP_STEPS


def _load_private_base() -> Any:
    existing = sys.modules.get(PRIVATE_MODULE_NAME)
    if existing is not None:
        return existing
    spec = importlib.util.spec_from_file_location(PRIVATE_MODULE_NAME, BASE_PATH)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load R122 runtime base from {BASE_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[PRIVATE_MODULE_NAME] = module
    spec.loader.exec_module(module)
    module.MAX_EXPLICIT_LAG = MAX_EXPLICIT_LAG
    module.WARMUP_STEPS = WARMUP_STEPS
    module.SOURCE_WINDOW = SOURCE_WINDOW
    return module


BASE = _load_private_base()

# Re-export only the tested runtime surface needed by R122.
ExplicitArrays = BASE.ExplicitArrays
QUANTILES = BASE.QUANTILES
active_regions = BASE.active_regions
explicit_arrays = BASE.explicit_arrays
feature_names = BASE.feature_names
fit_scaled_ridge = BASE.fit_scaled_ridge
input_names = BASE.input_names
load_normal_fit = BASE.load_normal_fit
load_quantile_fit = BASE.load_quantile_fit
load_windows = BASE.load_windows
normalize_spec = BASE.normalize_spec
prediction_metrics = BASE.prediction_metrics
recursive_normal_score = BASE.recursive_normal_score
recursive_quantile_forecast = BASE.recursive_quantile_forecast
standardize_from_training_origins = BASE.standardize_from_training_origins
teacher_forced_design = BASE.teacher_forced_design
teacher_forced_statistics = BASE.teacher_forced_statistics
write_stats_packet = BASE.write_stats_packet


def subset_arrays(arrays: Any, indices: Any) -> Any:
    """Return an origin subset without changing its frozen feature contract."""
    import numpy as np

    idx = np.asarray(indices, dtype=int)
    return ExplicitArrays(
        arrays.price_history[idx], arrays.exog_history[idx], arrays.exog_future[idx],
        arrays.response[idx], arrays.anchors[idx], arrays.exog_names,
        arrays.source_manifest,
    )


def internal_splits(n_origins: int) -> list[dict[str, Any]]:
    """Exact inherited R121 boundaries on R122's common 940-origin support."""
    if int(n_origins) != 940:
        raise ValueError(f"R122 requires exactly 940 common origins, got {n_origins}")
    boundaries = ((506, 631), (631, 766), (766, 940))
    import numpy as np

    return [
        {
            "split": split,
            "train": np.arange(train_stop, dtype=int),
            "validation": np.arange(train_stop, validation_stop, dtype=int),
        }
        for split, (train_stop, validation_stop) in enumerate(boundaries, 1)
    ]
