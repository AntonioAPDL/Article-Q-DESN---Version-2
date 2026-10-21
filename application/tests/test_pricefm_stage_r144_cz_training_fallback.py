import importlib.util
import json
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'application/scripts/pricefm'


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


R144 = load('r144', '486_run_pricefm_stage_r144_cz_training_fallback.py')
CLOSEOUT = load('r144_closeout', '487_closeout_pricefm_stage_r144_all_region.py')
CONFIG = json.loads((ROOT / 'application/config/pricefm_stage_r144_cz_training_fallback_20261020.json').read_text())


def test_contract_is_bounded_training_only_and_non_promotional():
    assert CONFIG['fallback_rank'] == 3
    assert CONFIG['fallback_candidate']['candidate_id'] == 'r134_56a8ee2629e2b168'
    assert CONFIG['fallback_candidate']['specification_sha256'].startswith('56a8ee2629e2b168')
    assert CONFIG['fallback_candidate']['spec']['readout'] == 'pure_all_layers'
    assert CONFIG['maximum_workers'] == 15
    assert CONFIG['al_max_iter'] == 300
    assert CONFIG['cpus'] == list(range(15, 30))
    assert len(CONFIG['prerequisites']) == 6
    for key in ('test_data_access_authorized', 'posterior_target_changes_authorized',
                'certificate_limit_changes_authorized', 'registry_mutation_authorized',
                'article_mutation_authorized', 'promotion_authorized'):
        assert CONFIG[key] is False
    source = (HERE / '486_run_pricefm_stage_r144_cz_training_fallback.py').read_text()
    assert 'predetermined_training_only_RHS_rank_3' in source
    assert 'R144_WAITING_FOR_R143_SLOT_B' in source
    assert 'R144_CZ_FALLBACK_COMPLETE_NOT_PROMOTED' in source
    assert "quantile_finalists=1" in source


def test_hardlink_import_is_idempotent_and_detects_changes(tmp_path):
    source = tmp_path / 'source'; source.mkdir()
    (source / 'nested').mkdir(); (source / 'nested/payload.bin').write_bytes(b'frozen')
    destination = tmp_path / 'destination'
    R144.hardlink_tree(source, destination)
    assert R144.tree_hashes(destination) == R144.tree_hashes(source)
    assert (source / 'nested/payload.bin').stat().st_ino == (destination / 'nested/payload.bin').stat().st_ino
    R144.hardlink_tree(source, destination)
    (destination / 'extra').write_text('unexpected')
    try:
        R144.hardlink_tree(source, destination)
    except RuntimeError as error:
        assert 'differs' in str(error)
    else:
        raise AssertionError('changed destination was accepted')


def test_fallback_audit_rejects_noisy_choice_and_accepts_exact_train_only_evidence(tmp_path, monkeypatch):
    config = json.loads(json.dumps(CONFIG))
    old_data = R144.DATA; R144.DATA = tmp_path
    monkeypatch.setattr(R144, 'assert_contract', lambda value: None)
    monkeypatch.setattr(R144, 'git', lambda root, *args: 'test-value')
    monkeypatch.setattr(R144, 'host_health', lambda value: {'healthy': True})
    try:
        source = R144.source_campaign(config); source.mkdir(parents=True)
        prep_path = R144.source_preparation(config); prep_path.parent.mkdir(parents=True)
        candidate = {'candidate_id': config['fallback_candidate']['candidate_id'],
                     'specification_sha256': config['fallback_candidate']['specification_sha256'],
                     'spec': config['fallback_candidate']['spec']}
        prep_path.write_text(json.dumps({'regional': {'CZ': {'candidates': [candidate]}}}))
        ranking = [
            {'candidate_id': 'first', 'tau0': 1.0, 'mean_AQL': 1.0, 'split_AQL': {}},
            {'candidate_id': 'second', 'tau0': 2.0, 'mean_AQL': 2.0, 'split_AQL': {}},
            {key: config['fallback_candidate'][key]
             for key in ('candidate_id', 'tau0', 'mean_AQL', 'split_AQL')},
        ]
        rhs_path = source / 'rhs_closeout.json'
        rhs_path.write_text(json.dumps({'CZ': {'ranking': ranking}}))
        config['source_preparation_sha256'] = R144.sha256(prep_path)
        config['source_rhs_closeout_sha256'] = R144.sha256(rhs_path)
        for name, record in config['prerequisites'].items():
            task = {'name': name, 'kind': record['kind'], 'candidate_id': candidate['candidate_id']}
            result = {'certified': True}
            if record['kind'] == 'stats':
                task['split'] = int(name.rsplit('_s', 1)[1]); result['train_only'] = True
            else:
                task['tau0'] = config['fallback_candidate']['tau0']
            task_path = source / 'tasks' / (name + '.json'); task_path.parent.mkdir(parents=True, exist_ok=True)
            task_path.write_text(json.dumps(task))
            done = source / 'tasks_done' / name; done.mkdir(parents=True)
            (done / 'result.json').write_text(json.dumps(result))
            (done / 'completed_evidence.json').write_text(json.dumps({'sealed': True}))
            record['task_sha256'] = R144.sha256(task_path)
            record['completed_evidence_sha256'] = R144.sha256(done / 'completed_evidence.json')
        report = R144.fallback_audit(config, require_idle=False, require_clean_source=False)
        assert report['status'] == 'R144_AUDIT_PASS'
        assert report['fallback_rank'] == 3
        assert report['official_test_opened'] is False
        config['fallback_candidate']['tau0'] *= 10
        try:
            R144.fallback_audit(config, require_idle=False, require_clean_source=False)
        except RuntimeError as error:
            assert 'tau0 differs' in str(error)
        else:
            raise AssertionError('changed fallback tau0 was accepted')
    finally:
        R144.DATA = old_data


class MemoryReader:
    def __init__(self, values):
        self.values = values

    def bytes(self, host, path):
        return self.values[str(path)]

    def json(self, host, path):
        return json.loads(self.bytes(host, path))


def test_global_closeout_requires_exact_4_plus_33_plus_1_surface():
    r141 = json.loads((ROOT / 'application/config/pricefm_stage_r141_recovery_rollout_20261019.json').read_text())
    r144 = json.loads(json.dumps(CONFIG)); identity = {
        'branch': 'work/pricefm-r144-cz-training-fallback-test', 'head': 'r144-head'}
    values = {}
    rows = []
    for region in r141['regions']:
        root = CLOSEOUT.campaign_path(r141, r144, region)
        frame = pd.DataFrame([{'region': region, 'fold': fold, 'operator': operator,
            'AQL': 5.0, 'qdesn_AQL': 6.0, 'pricefm_AQL': 5.5, 'operational_pricefm_AQL': 5.4}
            for fold in (1, 2, 3)
            for operator in ('cdf_pool_clipped', 'mean_feature', 'path_specific', 'normal_driver')])
        fold_bytes = frame.to_csv(index=False).encode(); values[str(root / 'closeout/fold_comparison.csv')] = fold_bytes
        if region in r141['reuse_regions']:
            source = {'head': r141['reuse_source']['head']}
            status = 'R137_REGION_COMPLETE_NOT_PROMOTED'
        elif region == 'CZ':
            source = identity; status = 'R144_CZ_FALLBACK_COMPLETE_NOT_PROMOTED'
        else:
            source = {'branch': r144['source_branch'], 'head': r144['source_head']}
            status = 'R141_REGION_COMPLETE_NOT_PROMOTED'
        completed = {'artifacts': {'fold_comparison.csv': CLOSEOUT.digest(fold_bytes)},
                     'metadata': {'source': source}}
        completed_bytes = (json.dumps(completed) + '\n').encode()
        values[str(root / 'closeout/completed_evidence.json')] = completed_bytes
        values[str(root / 'terminal.json')] = json.dumps({'status': status, 'source': source}).encode()
        if region in r141['reuse_regions']:
            r141['reuse_source']['regions'][region]['completed_evidence_sha256'] = CLOSEOUT.digest(completed_bytes)
        rows.append(region)
    folds, regions, provenance, summary = CLOSEOUT.collect(r141, r144, MemoryReader(values), identity)
    assert len(folds) == 114 and len(regions) == 38 and len(provenance) == 38
    assert summary['r137_reused_regions'] == 4
    assert summary['r141_regions'] == 33
    assert summary['r144_fallback_regions'] == 1
    assert summary['equal_region_fold_AQL'] == 5.0
    assert summary['promotion_decided'] is False
