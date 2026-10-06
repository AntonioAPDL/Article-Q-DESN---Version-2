"""Strict comparison gate for future aligned, frozen full-fold predictions."""
from __future__ import annotations

import numpy as np
from pricefm_r125_cdf import LEVELS

METHODS = ('candidate', 'current_authority', 'pricefm')


def matched_comparison(records, expected_regions, frozen_specifications, split='test'):
    """Report whole-cohort mean AQL; never authorize promotion from one case."""
    expected_regions = tuple(expected_regions)
    if (not expected_regions or len(set(expected_regions)) != len(expected_regions)
            or set(frozen_specifications) != set(expected_regions)
            or any(not isinstance(v, str) or len(v) != 64 or any(c not in '0123456789abcdef' for c in v)
                   for v in frozen_specifications.values())):
        raise ValueError('nonempty unique cohort and exact frozen specification hashes required')
    expected = {(region, fold, method) for region in expected_regions
                for fold in (1, 2, 3) for method in METHODS}
    by_key = {(r['region'], r['fold'], r['method']): r for r in records}
    if len(records) != len(by_key) or set(by_key) != expected or split not in ('val', 'test'):
        raise ValueError('complete prespecified three-fold cohort with no duplicates required')
    metrics = []
    for region in expected_regions:
        for fold in (1, 2, 3):
            base = by_key[(region, fold, 'current_authority')]
            truth = np.asarray(base['truth'], dtype=float)
            origins = np.asarray(base['origin_utc'], dtype=str)
            if truth.ndim != 2 or truth.shape[1] != 96 or len(truth) != len(origins) or not len(truth):
                raise ValueError('96 quarter-hour horizons and nonempty matched origins required')
            if len(np.unique(origins)) != len(origins):
                raise ValueError('duplicate forecast origins')
            for method in METHODS:
                record = by_key[(region, fold, method)]
                if (record['split'] != split or record['units'] != 'EUR/MWh'
                        or record['horizon_steps'] != 96 or record['step_minutes'] != 15
                        or not np.array_equal(record['quantiles'], LEVELS)
                        or not np.array_equal(record['origin_utc'], origins)
                        or not np.array_equal(record['truth'], truth)):
                    raise ValueError('comparison windows, truth, units, quantiles or origins differ')
                if method == 'candidate' and (
                        record['specification_sha256'] != frozen_specifications[region]
                        or record['selection_uses_test'] is not False
                        or record['operator_frozen_before_scoring'] is not True
                        or record['oracle_inputs'] is not False
                        or record['full_training_fit'] is not True):
                    raise ValueError('candidate selection/scoring separation or full-fit contract failed')
                prediction = np.asarray(record['prediction'], dtype=float)
                if prediction.shape != (*truth.shape, 7) or not np.isfinite(prediction).all() or not np.isfinite(truth).all():
                    raise ValueError('invalid finite forecast geometry')
                error = truth[:, :, None] - prediction
                aql = float(np.maximum(LEVELS * error, (LEVELS - 1) * error).mean())
                metrics.append(dict(region=region, fold=fold, method=method, AQL=aql, origins=len(truth)))
    means = {method: float(np.mean([r['AQL'] for r in metrics if r['method'] == method])) for method in METHODS}
    return dict(cases=metrics, mean_AQL=means,
        candidate_mean_better_than_authority=means['candidate'] < means['current_authority'],
        candidate_mean_better_than_pricefm=means['candidate'] < means['pricefm'],
        comparison_rule='unweighted_complete_region_fold_mean_not_per_case_dual_gate',
        scientific_scope='leakage_firewalled_retrospective_not_pristine_confirmation',
        promotion_authorized=False, all_region_launch_authorized=False)
