"""Regression and live-parent gates for the R135 R134 completion campaign."""
import importlib.util
import inspect
import json
import os
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'application/scripts/pricefm'
sys.path.insert(0, str(HERE))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


RUN = load('pricefm_r135_test_runner', HERE / '468_run_pricefm_stage_r135_r134_completion.py')
PROTOCOL = json.loads((ROOT / 'application/config/pricefm_stage_r135_r134_fixedpoint_completion_20261012.json').read_text())


def test_protocol_is_bounded_target_preserving_and_nonpromotional():
    RUN.validate_protocol(PROTOCOL)
    assert PROTOCOL['maximum_workers'] == 30
    assert PROTOCOL['expected_parent_task_counts']['uncertified_median'] == 14
    assert PROTOCOL['expected_parent_task_counts']['pending_internal'] == 98
    assert PROTOCOL['public_cran_version'] == '1.1.1'
    assert not PROTOCOL['screening_authorized']
    assert not PROTOCOL['promotion_authorized']
    assert not PROTOCOL['all_region_launch_authorized']
    assert not PROTOCOL['priors_from_initializers']


@pytest.mark.parametrize('field', ['screening_authorized', 'mcmc_authorized',
    'joint_authorized', 'exal_authorized', 'promotion_authorized',
    'registry_mutation_authorized', 'article_mutation_authorized',
    'priors_from_initializers', 'test_used_for_selection',
    'all_region_launch_authorized'])
def test_forbidden_expansion_fails(field):
    with pytest.raises(ValueError):
        RUN.validate_protocol(dict(PROTOCOL, **{field: True}))


def test_recovery_preserves_original_formal_flag_and_does_not_refit_medians():
    source = inspect.getsource(RUN.certify_median)
    assert "original_formal_converged=False" in source
    assert "no_new_AL_fit=True" in source
    assert "independent_fixedpoint_certified" in source
    assert "shutil.copyfile" in source


def test_iteration_cap_uses_independent_certificate_not_relaxed_tolerance():
    fitter = (HERE / '467_fit_pricefm_stage_r135_certified_al.R').read_text()
    assert "c$max_iter == 1000L" in fitter
    assert "r129_certificate" in fitter
    assert "computationally_certified <- finite &&" in fitter
    assert "formal_converged = isTRUE(fit$converged)" in fitter
    assert "prior_center_from_initializer = FALSE" in fitter
    assert "isTRUE(parent$formal_converged) || isTRUE(parent$independent_fixedpoint_certified)" in fitter
    assert "tol = c$tol" in fitter


def test_scheduler_orders_certificate_internal_and_official_stages():
    source = inspect.getsource(RUN.controller)
    first = source.index("'r134_median_fixedpoint_certification'")
    second = source.index("'r134_remaining_internal_quantile_DAG'")
    third = source.index("'r134_frozen_winner_official_refit_and_forecast'")
    assert first < second < third
    assert "frozen_choices(prep)" in source


def test_live_parent_inventory_matches_frozen_health_audit():
    parent = os.environ.get('PRICEFM_R135_PARENT_CAMPAIGN')
    dependency = os.environ.get('PRICEFM_R134_DEPENDENCY')
    if not parent or not dependency:
        pytest.skip('live R134 parent and pinned dependency were not supplied')
    RUN.PARENT_OUT = Path(parent)
    RUN.setup(Path(dependency))
    tasks = RUN.parent_task_inventory()
    completed = [task for task in tasks if RUN.sealed_result(RUN.PARENT_OUT, task['name']) is not None]
    medians = [task for task in tasks if task['kind'] == 'internal_al' and task['tau'] == .5]
    uncertified = [task for task in medians
                   if not RUN.sealed_result(RUN.PARENT_OUT, task['name']).get('certified', False)]
    pending = [task for task in tasks if task['kind'].startswith('internal_')
               and RUN.sealed_result(RUN.PARENT_OUT, task['name']) is None]
    assert len(completed) == 3112
    assert len(uncertified) == 14
    assert len(pending) == 98
    assert all(task['tau'] == .5 for task in uncertified)


def test_closeout_cannot_promote_or_mutate_article_authority():
    source = inspect.getsource(RUN.closeout)
    assert "authority_replaced=False" in source
    assert "promotion_authorized=False" in source
    assert "all_region_rollout_authorized=False" in source
    assert "R135_COMPLETE_NOT_PROMOTED" in source
