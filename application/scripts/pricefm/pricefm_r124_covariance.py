"""Covariance-preserving Gaussian draws; no additive statistical regularization."""
from __future__ import annotations

import hashlib

import numpy as np


POLICY = "r124_equilibrated_exact_covariance_v1"


def covariance_factor(covariance):
    value = np.asarray(covariance, dtype=float)
    if value.ndim != 2 or value.shape[0] != value.shape[1] or not value.size:
        raise ValueError("nonempty square covariance required")
    if not np.isfinite(value).all() or np.any(np.diag(value) <= 0):
        raise ValueError("finite covariance with positive diagonal required")
    scale = float(np.max(np.abs(value)))
    asymmetry = float(np.max(np.abs(value - value.T)) / scale)
    if asymmetry > 1e-12:
        raise ValueError("asymmetric saved covariance")
    symmetric = (value + value.T) * .5
    diagonal = np.sqrt(np.diag(symmetric))
    correlation = (symmetric / diagonal[:, None]) / diagonal[None, :]
    try:
        factor = diagonal[:, None] * np.linalg.cholesky((correlation + correlation.T) * .5)
    except np.linalg.LinAlgError as error:
        raise ValueError("saved covariance is not positive definite; no inflation permitted") from error
    residual = float(np.max(np.abs(factor @ factor.T - symmetric)) / scale)
    if not np.isfinite(factor).all() or residual > 1e-10:
        raise ValueError("inaccurate covariance factor")
    return factor, dict(policy=POLICY, dimension=len(value), covariance_sha256=
        hashlib.sha256(np.ascontiguousarray(value, dtype="<f8").tobytes()).hexdigest(),
        relative_asymmetry=asymmetry, relative_reconstruction_error=residual,
        covariance_inflation=0.0, eigenvalue_clipping=False)


def projected_audit(covariance, readouts, residual_variance=None):
    factor, audit = covariance_factor(covariance)
    value = (np.asarray(covariance, dtype=float) + np.asarray(covariance, dtype=float).T) * .5
    rows = np.asarray(readouts, dtype=float)
    if rows.ndim != 2 or not len(rows) or rows.shape[1] != len(value) or not np.isfinite(rows).all():
        raise ValueError("finite matching readout rows required")
    reference = np.einsum("ij,jk,ik->i", rows.astype(np.longdouble),
        value.astype(np.longdouble), rows.astype(np.longdouble))
    actual = np.sum((rows @ factor) ** 2, axis=1, dtype=np.longdouble)
    if np.any(reference <= 0):
        raise ValueError("nonpositive reference projected variance")
    error = float(np.max(np.abs(actual - reference) / reference))
    if error > 1e-6:
        raise ValueError("inaccurate prediction-relevant covariance factor")
    legacy_jitter = np.sqrt(np.finfo(float).eps) * max(1.0, float(np.diag(value).mean()))
    added = legacy_jitter * np.sum(rows * rows, axis=1)
    audit.update(projected_rows=len(rows), relative_projected_variance_error=error,
        legacy_added_covariance=float(legacy_jitter),
        median_saved_projected_variance=float(np.median(reference)),
        median_legacy_added_projected_variance=float(np.median(added)),
        median_legacy_added_over_coefficient_variance=float(np.median(added / reference)))
    if residual_variance is not None:
        if not np.isfinite(residual_variance) or residual_variance <= 0:
            raise ValueError("positive residual variance required")
        audit["median_legacy_added_over_total_one_step_variance"] = float(
            np.median(added / (reference + residual_variance)))
    return audit


class GaussianSampler:
    def __init__(self):
        self.audit = []

    def __call__(self, mean, covariance, paths, seed):
        center = np.asarray(mean, dtype=float)
        factor, audit = covariance_factor(covariance)
        if center.shape != (len(factor),) or not np.isfinite(center).all():
            raise ValueError("finite matching Gaussian mean required")
        if isinstance(paths, bool) or int(paths) != paths or paths < 1:
            raise ValueError("positive integer draw count required")
        result = center[None, :] + np.random.default_rng(seed).standard_normal(
            (int(paths), len(center))) @ factor.T
        audit.update(paths=int(paths), seed=int(seed))
        self.audit.append(audit)
        return result
