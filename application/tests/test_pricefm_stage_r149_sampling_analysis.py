"""Sampling diagnostics must preserve pairing, weights and split-macro meaning."""
import copy
import importlib.util
import math
from pathlib import Path
import random

import pytest

PATH = Path(__file__).resolve().parents[1] / 'scripts/pricefm/pricefm_r149_sampling_analysis.py'
SPEC = importlib.util.spec_from_file_location('r149_sampling', PATH)
M = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(M)


def rows(count=60):
    return [dict(split=split, origin_key=str(i), weekday=i % 7, month=i % 12 + 1,
        control_loss=10 + i / 10, competitor_loss=9 + (i % 13) / 3 + split / 10)
        for split in (1, 2, 3) for i in range(count)]


def summary(analysis, method, size):
    return next(row for row in analysis['samplers'] if row['method'] == method
                and row['daily_origins_per_split'] == size)


def test_unequal_strata_use_population_weights_instead_of_equal_stratum_means():
    population = [dict(split=split, origin_key=i, weekday=0 if i == 0 else 1,
        month=1 if i == 0 else 2, control_loss=0, competitor_loss=100 if i == 0 else 0)
        for split in (1, 2, 3) for i in range(10)]
    analysis = M.analyze_sampling(population)
    assert analysis['reference_macro_contrast'] == 10
    for method in ('weekday_stratified', 'month_stratified'):
        result = summary(analysis, method, 4)
        assert result['macro_estimates'] == [10] * 32
        assert result['MAE'] == 0 and result['bias'] == 0
        assert sorted(s['population_weight'] for s in result['design']['1'].values()) == [.1, .9]
        assert sorted(s['quota'] for s in result['design']['1'].values()) == [1, 3]


def test_analysis_is_exactly_invariant_to_input_row_order_and_does_not_mutate_rows():
    original = rows(); shuffled = copy.deepcopy(original)
    random.Random(123).shuffle(shuffled)
    assert M.analyze_sampling(original) == M.analyze_sampling(shuffled)
    assert original == rows()


def test_equal_split_macro_is_primary_and_pooled_value_only_diagnostic():
    population = []
    for split, count, value in [(1, 4, 1), (2, 8, 2), (3, 12, 9)]:
        population.extend(dict(split=split, origin_key=i, weekday=0, month=1,
            control_loss=0, competitor_loss=value) for i in range(count))
    result = M.analyze_sampling(population)
    assert result['reference_macro_contrast'] == 4
    assert result['pooled_reference_contrast_diagnostic_only'] == pytest.approx(128 / 24)
    assert summary(result, 'uniform', 4)['macro_estimates'] == [4] * 32


def test_quotas_represent_every_stratum_and_never_exceed_population():
    result = M.analyze_sampling(rows())
    for sampler in result['samplers']:
        if sampler['status'] != 'complete':
            continue
        for design in sampler['design'].values():
            assert sum(h['quota'] for h in design.values()) == sampler['daily_origins_per_split']
            assert sum(h['population_weight'] for h in design.values()) == pytest.approx(1)
            assert all(1 <= h['quota'] <= h['population'] for h in design.values())
    assert summary(result, 'weekday_stratified', 4)['status'] == 'infeasible'
    assert summary(result, 'month_stratified', 4)['status'] == 'infeasible'


def test_full_population_sampling_is_exact_and_budget_is_four_clocks_per_day():
    result = M.analyze_sampling(rows(4))
    for method in M.METHODS:
        estimate = summary(result, method, 4)
        assert estimate['MAE'] == pytest.approx(0, abs=1e-14)
        assert estimate['clock_pairs_per_split'] == 16
        assert estimate['total_clock_pairs'] == 48
        assert summary(result, method, 12)['status'] == 'infeasible'


def test_frozen_design_and_no_automatic_choice_or_new_validation():
    result = M.analyze_sampling(rows())
    assert result['sample_sizes'] == [4, 12, 24, 48]
    assert result['resampling_replicates'] == 32 and result['master_seed'] == 2026102303
    assert result['automatic_panel_choice'] is False and result['new_validation_claim'] is False
    assert result['new_forecasts'] == 0
    assert all(0 <= row['sign_agreement'] <= 1 for row in result['samplers'] if row['status'] == 'complete')


@pytest.mark.parametrize('change', [
    lambda p: p.append(dict(p[0])), lambda p: p[0].pop('competitor_loss'),
    lambda p: p[0].update(control_loss=float('nan')),
    lambda p: p[0].update(competitor_loss=float('inf')),
    lambda p: p[0].update(control_loss=True), lambda p: p[0].update(weekday=7),
    lambda p: p[0].update(competitor_loss=-1),
    lambda p: p[0].update(month=0), lambda p: p[0].update(split=4),
])
def test_duplicate_unpaired_or_nonfinite_rows_rejected(change):
    population = rows(); change(population)
    with pytest.raises(ValueError):
        M.analyze_sampling(population)


def test_missing_split_rejected():
    with pytest.raises(ValueError, match='three rolling splits'):
        M.analyze_sampling([row for row in rows() if row['split'] != 3])


def test_legacy_panels_are_fixed_diagnostics_with_strict_pairing():
    panels = {'historical4': {str(split): [0, 1, 2, 3] for split in (1, 2, 3)}}
    result = M.analyze_sampling(rows(), panels)
    assert result['legacy_panels']['historical4']['daily_origins_per_split'] == {'1': 4, '2': 4, '3': 4}
    assert 'nonprobability' in result['legacy_panels']['historical4']['estimator']
    panels['historical4']['1'] = [0, 0]
    with pytest.raises(ValueError, match='duplicated'):
        M.analyze_sampling(rows(), panels)
