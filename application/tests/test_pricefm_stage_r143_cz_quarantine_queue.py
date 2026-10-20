import importlib.util
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'application/scripts/pricefm'
SPEC = importlib.util.spec_from_file_location(
    'r143', HERE / '485_run_pricefm_stage_r143_cz_quarantine_queue.py')
R143 = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(R143)
CONFIG = json.loads((ROOT / 'application/config/pricefm_stage_r143_cz_quarantine_queue_recovery_20261020.json').read_text())


def test_contract_quarantines_cz_and_preserves_scientific_target():
    assert CONFIG['quarantined_region'] == 'CZ'
    assert 'CZ' not in CONFIG['continuation_regions']
    assert CONFIG['continuation_regions'] == ['ES', 'HR', 'IT_SARD', 'LV', 'NO_3', 'PT', 'SE_3']
    assert len(CONFIG['cpus']) == len(set(CONFIG['cpus'])) == 15
    for key in ('test_data_access_authorized', 'posterior_target_changes_authorized',
                'certificate_limit_changes_authorized', 'registry_mutation_authorized',
                'article_mutation_authorized', 'promotion_authorized'):
        assert CONFIG[key] is False
    source = (HERE / '485_run_pricefm_stage_r143_cz_quarantine_queue.py').read_text()
    assert "source_controller(config)), 'prepare'" in source
    assert "source_controller(config)), 'controller'" in source
    assert "R143_QUEUE_DRAINED_WITH_QUARANTINED_FAILURES" in source


def test_cz_diagnosis_distinguishes_solve_accuracy_from_stationarity(tmp_path):
    old_data = R143.DATA; R143.DATA = tmp_path
    try:
        config = dict(CONFIG, cz_rescue_tag='r142')
        root = tmp_path / 'campaigns/r142/CZ/tasks'
        source = tmp_path / f"campaigns/{config['source_tag']}__CZ"
        source.mkdir(parents=True)
        R143.atomic_json(source / 'rhs_closeout.json', {'CZ': {'ranking': [
            {'candidate_id': 'r134_7edce5349892e5a7', 'tau0': 1e-3, 'mean_AQL': 1.0},
            {'candidate_id': 'r134_fallback', 'tau0': 1e-4, 'mean_AQL': 1.1},
        ]}})
        failed = []
        for index, name in enumerate(config['cz_expected_failed_tasks']):
            failed.append(name)
            path = root / name / 'attempt_02/fit'; path.mkdir(parents=True)
            R143.atomic_json(path / 'fixedpoint_certificate.json', {
                'certified': False,
                'measures': {'beta_posterior_sd_rms': 1.5e-4,
                             'covariance_whitened_rms': 8e-5},
                'limits': {'beta_posterior_sd_rms': 1e-4,
                           'covariance_whitened_rms': 1e-4},
                'mean_solve_relative_residual': 4e-14,
                'precision_condition': 1e14,
            })
        for name in config['cz_expected_certified_tasks']:
            path = root / name / 'promoted_task/fit'; path.mkdir(parents=True)
            R143.atomic_json(path / 'terminal.json', {'computationally_certified': True})
        result = R143.cz_diagnosis(config)
        assert result['classification'] == 'coefficient_block_nonstationarity_not_linear_solve_failure'
        assert all(item['accurate_linear_solve'] for item in result['failed_attempt_2'])
        assert not any(item['coefficient_block_stationary'] for item in result['failed_attempt_2'])
        assert result['more_blind_iterations_authorized'] is False
        assert result['training_only_fallback_candidate']['candidate_id'] == 'r134_fallback'
        assert result['training_only_fallback_launched'] is False
        assert result['test_opened'] is False
    finally:
        R143.DATA = old_data


def test_progress_is_region_counted_and_failure_isolated(tmp_path):
    old_data = R143.DATA; R143.DATA = tmp_path
    old_health = R143.health
    try:
        config = dict(CONFIG, source_tag='r141', continuation_regions=['ES', 'HR'])
        for region in ['ES']:
            campaign = tmp_path / f'campaigns/r141__{region}'
            (campaign / 'closeout').mkdir(parents=True)
            R143.atomic_json(campaign / 'terminal.json', {
                'status': 'R141_REGION_COMPLETE_NOT_PROMOTED',
                'source': {'head': config['source_head']},
            })
            R143.atomic_json(campaign / 'closeout/completed_evidence.json', {
                'metadata': {'source': {'head': config['source_head']}}
            })
        R143.health = lambda _: {'healthy': True}
        report = R143.progress(config, {'source': {'head': config['source_head']}}, None,
                               [{'region': 'HR', 'reason': 'test'}])
        assert report['completed'] == ['ES']
        assert report['remaining_count'] == 1
        assert report['failures'][0]['region'] == 'HR'
        assert report['pending'] == []
    finally:
        R143.DATA = old_data; R143.health = old_health
