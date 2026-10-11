from dataclasses import replace
import importlib.util
import json
import os
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'application/scripts/pricefm'
sys.path.insert(0, str(Path(os.environ['PRICEFM_R131_DEPENDENCY']) / 'application/scripts/pricefm'))
sys.path.insert(0, str(HERE))
import pricefm_r123_runtime as RT
from pricefm_r131_seasonal import (seasonal_path, replay, MODES, CACHED, LEVELS,
    validate_protocol, validate_cached, first_step_check, aggregate_packets,
    metrics, choose_physical_cpus, plot_report, closeout, FORBIDDEN)
from pricefm_r126_contract import read, write, seal, verified
from pricefm_r127_contract import common_metrics
from pricefm_r127_forecast import replay as old_replay


@pytest.fixture
def protocol():
    return read(ROOT / 'application/config/pricefm_stage_r131_causal_seasonal_drivers_20261011.json')


@pytest.fixture(scope='module')
def toy():
    rng = np.random.default_rng(73); n = 3; lag = 3120
    y = rng.normal(size=lag + n * 96); x = rng.normal(size=(lag + n * 96, 3))
    arrays = RT.ExplicitArrays(np.array([y[i*96:i*96+lag] for i in range(n)]),
        np.array([x[i*96:i*96+lag] for i in range(n)]),
        np.array([x[i*96+lag:i*96+lag+96] for i in range(n)]),
        np.array([y[i*96+lag:i*96+lag+96] for i in range(n)]),
        np.array([v.isoformat() for v in pd.date_range('2024-01-01', periods=n, freq='D', tz='UTC')]),
        ('load', 'solar', 'wind'), ())
    spec = RT.normalize_spec(dict(region='BG', feature_policy='target_only', calendar='none',
        readout='pure_all_layers', m_y=3, m_x=2, units=[4, 3], alpha=.5, rho=.8,
        input_scale=.15, input_fan_in=2, recurrent_sparsity=.5, seed=17))
    mean = np.arange(8) * .01; cov = np.eye(8) * .001
    normal = dict(beta_mean=mean, beta_cov=cov, omega_shape=5., omega_rate=.5)
    qs = {float(q): dict(beta_mean=mean + q / 10, beta_cov=cov) for q in LEVELS}
    one = RT.subset_arrays(arrays, [1])
    values, audit = replay(RT, one, spec, qs, [12], 4)
    return arrays, spec, normal, qs, values, audit


@pytest.mark.parametrize('key', FORBIDDEN)
def test_forbidden_scope_rejected(protocol, key):
    protocol[key] = True
    with pytest.raises(ValueError): validate_protocol(protocol)


@pytest.mark.parametrize('key,value', [('paths', 100), ('maximum_workers', 31), ('horizon_steps', 95),
    ('step_minutes', 60), ('seasonal_periods_steps', [24, 168]), ('controls', ['previous_day']),
    ('oracle_diagnostic_only', False)])
def test_frozen_geometry_rejected(protocol, key, value):
    protocol[key] = value
    with pytest.raises(ValueError): validate_protocol(protocol)


def test_correct_protocol_and_stage_scope(protocol):
    validate_protocol(protocol)
    script = (HERE / '461_run_pricefm_stage_r131_seasonal.py').read_text()
    assert 'new_fits=0' in script and 'official_test_reforecast=False' in script
    assert 'exalStaticLDVB(' not in script and 'git push' not in script
    assert protocol['parent_head'] == 'cff723f900372bbeee22500e6c917fdd241e7557'


@pytest.mark.parametrize('period', [96, 672])
def test_seasonal_indices_available_strictly_before_origin(period):
    history = np.arange(3120.)[None, :]
    np.testing.assert_array_equal(seasonal_path(history, period), history[:, 3120-period:3120-period+96])
    assert (3120 + np.arange(96) - period).max() < 3120


@pytest.mark.parametrize('shape,period,horizon', [((1, 95), 96, 96), ((1, 671), 672, 96),
    ((1, 3120), 96, 97), ((1, 3120), 24, 96), ((3120,), 96, 96)])
def test_unavailable_or_wrong_units_rejected(shape, period, horizon):
    with pytest.raises(ValueError): seasonal_path(np.zeros(shape), period, horizon)


def test_nonfinite_history_rejected():
    history = np.zeros((1, 3120)); history[0, -1] = np.nan
    with pytest.raises(ValueError): seasonal_path(history, 96)


def test_future_truth_poison_does_not_enter_causal_controls(toy):
    arrays, spec, normal, qs, values, _ = toy
    one = RT.subset_arrays(arrays, [1])
    poisoned, _ = replay(RT, replace(one, response=np.full_like(one.response, np.nan)), spec, qs, [12], 4)
    for mode in MODES:
        np.testing.assert_array_equal(poisoned[mode], values[mode])
    np.testing.assert_array_equal(poisoned['seasonal_driver'], values['seasonal_driver'])


def test_history_changes_causal_predictions(toy):
    arrays, spec, _, qs, values, _ = toy
    one = RT.subset_arrays(arrays, [1]); history = one.price_history.copy(); history[:, -96:-94] += 1
    changed, _ = replay(RT, replace(one, price_history=history), spec, qs, [12], 4)
    assert not np.array_equal(changed['previous_day'], values['previous_day'])


def test_same_draws_and_common_first_step(toy):
    arrays, spec, normal, qs, values, audit = toy
    old, _ = old_replay(RT, RT.subset_arrays(arrays, [1]), spec, qs, [12], 4, normal)
    merged = dict(values, stochastic=old['stochastic'])
    assert first_step_check(merged) < 1e-12
    assert audit['paths'] == 500 and audit['quantile_parameter_draws_common_with_r130']
    merged['previous_day'] = merged['previous_day'].copy(); merged['previous_day'][:, 0] += .1
    with pytest.raises(RuntimeError): first_step_check(merged)


def test_teacher_forcing_and_chunk_determinism(toy):
    arrays, spec, _, qs, _, _ = toy
    together, _ = replay(RT, RT.subset_arrays(arrays, [0, 2]), spec, qs, [3, 70], 4)
    single, _ = replay(RT, RT.subset_arrays(arrays, [2]), spec, qs, [70], 4)
    for mode in MODES:
        np.testing.assert_array_equal(together[mode][1:], single[mode])


def test_one_state_equals_500_duplicated_state_paths(toy):
    from pricefm_r124_covariance import GaussianSampler
    from pricefm_r125_cdf import pooled_quantiles
    arrays, spec, _, qs, values, _ = toy
    one = RT.subset_arrays(arrays, [1]); engine = RT.BASE
    reservoir, config, _ = RT.make_reservoir(spec, len(RT.input_names(spec, arrays.exog_names)))
    states = [np.repeat(s, 500, axis=0) for s in engine.initialize_states(one, spec, reservoir, config, [0])]
    sampler = GaussianSampler()
    bq = {q: sampler(f['beta_mean'], f['beta_cov'], 500, engine.deterministic_seed(4, 'quantile_beta', q))
          for q, f in qs.items()}
    path = np.repeat(seasonal_path(one.price_history, 96), 500, axis=0)
    for h in range(12):
        u = engine.explicit_input(one, spec, np.zeros(500, dtype=int), h, path[:, :h])
        states = engine.reservoir_step(states, u, reservoir, config)
        z = engine.readout_rows(states, u, spec['readout'])
        curves = np.column_stack([np.einsum('sp,sp->s', z, bq[q]) for q in LEVELS])
        expected = pooled_quantiles(curves, 'clipped')[0]
        np.testing.assert_allclose(expected, values['previous_day'][0, h], rtol=1e-12, atol=1e-12)


def test_current_exogenous_not_lagged(toy):
    arrays, spec, _, _, _, _ = toy
    one = RT.subset_arrays(arrays, [1]); exog = one.exog_future.copy(); exog[:, 0] += 3
    altered = replace(one, exog_future=exog)
    engine = RT.BASE
    u = engine.explicit_input(one, spec, [0], 0, np.empty((1, 0)))
    changed_u = engine.explicit_input(altered, spec, [0], 0, np.empty((1, 0)))
    start = spec['m_y']
    np.testing.assert_array_equal(u[0, start:start + 3], one.exog_future[0, 0])
    np.testing.assert_array_equal(changed_u[0, start:start + 3], exog[0, 0])
    np.testing.assert_array_equal(u[:, :start], changed_u[:, :start])
    np.testing.assert_array_equal(u[:, start + 3:], changed_u[:, start + 3:])
    # A sparse random reservoir need not connect each column in this tiny toy.
    connected = dict(spec, input_fan_in=u.shape[1])
    reservoir, config, _ = RT.make_reservoir(connected, u.shape[1])
    initial = engine.initialize_states(one, connected, reservoir, config, [0])
    before = engine.reservoir_step(initial, u, reservoir, config)
    after = engine.reservoir_step(initial, changed_u, reservoir, config)
    assert any(not np.array_equal(a, b) for a, b in zip(before, after))


@pytest.mark.parametrize('readout,calendar', [('final_layer', 'none'), ('pure_all_layers', 'compact3')])
def test_changed_receiver_representation_rejected(toy, readout, calendar):
    arrays, spec, _, qs, _, _ = toy
    with pytest.raises(ValueError): replay(RT, RT.subset_arrays(arrays, [1]), dict(spec, readout=readout, calendar=calendar), qs, [12], 4)


def fake_packet(grid):
    n = len(grid)
    return dict(bank_indices=np.arange(n), positions=np.array([v['position'] for v in grid]),
        anchors_ns=pd.DatetimeIndex(pd.to_datetime([v['anchor'] for v in grid], utc=True)).as_unit('ns').asi8,
        truth=np.ones((n, 96)), **{mode: np.zeros((n, 96, 7)) for mode in (*CACHED, *MODES)},
        seasonal_driver=np.zeros((n, 96, 2)), normal_driver_mean=np.zeros((n, 96)), normal_driver_sd=np.ones((n, 96)))


def test_cached_identity_scaling_and_complete_origins(toy):
    arrays = RT.subset_arrays(toy[0], [1])
    grid = [dict(position=12, offset=0, anchor=arrays.anchors[0])]
    packet = fake_packet(grid); packet['truth'] = arrays.response * 10 + 3
    task = dict(bank_indices=[0], positions=[12]); scaler = dict(price_scale=10, price_mean=3)
    validate_cached(packet, arrays, task, scaler)
    packet['truth'] = packet['truth'] + 1
    with pytest.raises(ValueError): validate_cached(packet, arrays, task, scaler)
    aggregate_packets([packet], grid)
    with pytest.raises(ValueError): aggregate_packets([packet, packet], grid)
    packet['positions'][0] += 1
    with pytest.raises(ValueError): aggregate_packets([packet], grid)


def test_physical_groups_busy_siblings_and_two_reserved():
    topology = {i: (0, i % 4) for i in range(8)}
    busy = {i: 0. for i in range(8)}; busy[4] = .9
    selected = choose_physical_cpus(range(8), topology, busy, 30)
    assert len(selected) == 2 and 0 not in selected and 4 not in selected
    assert len({topology[c] for c in selected}) == len(selected)
    assert all(c in {1, 2, 3} for c in selected)
    with pytest.raises(ValueError): choose_physical_cpus(range(8), topology, busy, 31)
    with pytest.raises(RuntimeError): choose_physical_cpus(range(8), topology, dict.fromkeys(range(8), .9), 10)


def test_busy_sibling_outside_process_affinity_disqualifies_core():
    topology = {0: (0, 0), 1: (0, 1), 2: (0, 2), 3: (0, 0)}
    with pytest.raises(RuntimeError): choose_physical_cpus([0], topology, {0: 0., 1: 0., 2: 0., 3: .8}, 1)


@pytest.mark.parametrize('memory,disk,expected', [(250, 210, True), (199, 210, False), (250, 200.2, False)])
def test_resource_reserves(tmp_path, monkeypatch, protocol, memory, disk, expected):
    from types import SimpleNamespace
    spec = importlib.util.spec_from_file_location('r131_resource_test', HERE / '461_run_pricefm_stage_r131_seasonal.py')
    entry = importlib.util.module_from_spec(spec); spec.loader.exec_module(entry)
    monkeypatch.setattr(entry, 'OUT', tmp_path)
    monkeypatch.setattr(entry.shutil, 'disk_usage', lambda path: SimpleNamespace(free=disk * 2**30))
    original_read = Path.read_text
    def read_text(path, *args, **kwargs):
        if str(path) == '/proc/meminfo':
            return f'MemAvailable: {memory * 2**20} kB\n'
        return original_read(path, *args, **kwargs)
    monkeypatch.setattr(Path, 'read_text', read_text)
    if expected:
        assert entry.resources(protocol)['available_memory_GiB'] == memory
    else:
        with pytest.raises(RuntimeError): entry.resources(protocol)


def test_metrics_quarter_hour_and_driver_units():
    grid = [dict(position=i, offset=i*24, anchor=f'2024-09-01T{i*6:02d}:00:00Z') for i in range(4)]
    rows, leads, drivers = metrics(fake_packet(grid), dict(region='HR', fold=1, grid=grid), common_metrics)
    assert len(rows) == 24 and len(leads) == 2304 and len(drivers) == 1152
    assert all(v['AQL'] == pytest.approx(.5) for v in rows)
    assert {v['target_clock_step'] for v in leads} == set(range(96))
    assert all(v['bias'] == -1 and v['RMSE'] == 1 for v in drivers)


def test_sealed_closeout_resume_and_tamper_rejection(tmp_path, monkeypatch):
    import pricefm_r131_seasonal as helper
    monkeypatch.setattr(helper, 'plot_report', lambda path, *args: path.write_bytes(b'%PDF-test'))
    cells, tasks = [], []
    for region in ('HR', 'DK_1'):
        for fold in (1, 2, 3):
            grid = [dict(position=i, offset=i*24, anchor=f'2024-09-01T{i*6:02d}:00:00Z') for i in range(4)]
            name = f'{region}_{fold}'
            cells.append(dict(region=region, fold=fold, grid=grid))
            tasks.append(dict(name=name, region=region, fold=fold))
            folder = tmp_path / 'tasks_done' / name; folder.mkdir(parents=True)
            np.savez_compressed(folder / 'predictions.npz', **fake_packet(grid)); seal(folder, {})
    prep = dict(cells=cells, tasks=tasks, source={'head': 'test'})
    result = closeout(tmp_path, prep, verified, read, write, seal, common_metrics)
    assert result['new_fits'] == 0 and not result['official_test_reforecast']
    assert len(result['findings']) == 4 and all(not v['selected'] for v in result['findings'])
    assert closeout(tmp_path, prep, verified, read, write, seal, common_metrics) == result
    (tmp_path / 'closeout/validation_metrics.csv').write_text('tampered')
    with pytest.raises(RuntimeError): closeout(tmp_path, prep, verified, read, write, seal, common_metrics)


def test_real_pdf_renderer_all_pages(tmp_path):
    grid = [dict(position=i, offset=i*24, anchor=f'2024-09-01T{i*6:02d}:00:00Z') for i in range(4)]
    rows, leads, drivers, cells = [], [], [], {}
    for region in ('HR', 'DK_1'):
        for fold in (1, 2, 3):
            values = fake_packet(grid); cells[region, fold] = values
            a, b, c = metrics(values, dict(region=region, fold=fold, grid=grid), common_metrics)
            rows += a; leads += b; drivers += c
    frame = pd.DataFrame(rows).groupby(['region', 'operator']).mean(numeric_only=True).reset_index()
    path = tmp_path / 'report.pdf'
    plot_report(path, frame, pd.DataFrame(leads), pd.DataFrame(drivers), cells)
    assert path.read_bytes().startswith(b'%PDF') and path.stat().st_size > 20000
