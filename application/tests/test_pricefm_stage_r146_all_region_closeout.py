"""Global publication gates: source separation, complete matched data and transport errors."""
import copy
import base64
import importlib.util
import io
import json
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / 'application/scripts/pricefm/490_closeout_pricefm_stage_r146_all_region.py'
SPEC = importlib.util.spec_from_file_location('pricefm_r146_closeout', PATH)
CLOSEOUT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLOSEOUT)
IDENTITY = {'branch': 'work/pricefm-r146-at-training-fallback-test', 'head': 'r146-head'}


class MemoryReader:
    def __init__(self):
        self.values = {}

    def bytes(self, host, path):
        return self.values[(host, str(path))]

    def json(self, host, path):
        return json.loads(self.bytes(host, path))

    def exists(self, host, path):
        return (host, str(path)) in self.values

    def write(self, host, path, value):
        self.values[(host, str(path))] = value

    def write_json(self, host, path, value):
        self.write(host, path, (json.dumps(value, sort_keys=True) + '\n').encode())


def region_paths(cohort, region):
    r141, r144, r146, reader = cohort
    return CLOSEOUT.region_host(r141, region), CLOSEOUT.campaign_path(r141, r144, r146, region)


def replace_table(cohort, region, transform):
    host, root = region_paths(cohort, region)
    reader = cohort[3]
    frame = pd.read_csv(io.BytesIO(reader.bytes(host, root / 'closeout/fold_comparison.csv')))
    changed = transform(frame)
    payload = changed.to_csv(index=False).encode()
    reader.write(host, root / 'closeout/fold_comparison.csv', payload)
    seal_path = root / 'closeout/completed_evidence.json'
    seal = reader.json(host, seal_path)
    seal['artifacts']['fold_comparison.csv'] = CLOSEOUT.digest(payload)
    reader.write_json(host, seal_path, seal)


@pytest.fixture
def cohort():
    r141 = json.loads(CLOSEOUT.R141_CONFIG.read_text())
    r144 = json.loads(CLOSEOUT.R144_CONFIG.read_text())
    r146 = {'tag': CLOSEOUT.TAG, 'region': 'AT', 'source_branch': r144['source_branch'],
            'source_head': r144['source_head'], 'fallback_rank': 4,
            'source_rhs_closeout_sha256': 'at-training-ranking-hash',
            'fallback_candidate': {'candidate_id': 'r134_7a422c0c3473f81f',
                                   'tau0': 0.0016320908467640013,
                                   'spec': {'readout': 'pure_all_layers'}}}
    reader = MemoryReader()
    result = r141, r144, r146, reader
    for index, region in enumerate(r141['regions']):
        host, root = region_paths(result, region)
        frame = pd.DataFrame([
            {'region': region, 'fold': fold, 'operator': operator,
             'AQL': 5.0 + index / 100 + fold / 1000 + (100 if operator != 'cdf_pool_clipped' else 0),
             'qdesn_AQL': 6.0, 'pricefm_AQL': 5.5, 'operational_pricefm_AQL': 5.4}
            for fold in (1, 2, 3) for operator in sorted(CLOSEOUT.OPERATORS)])
        payload = frame.to_csv(index=False).encode()
        reader.write(host, root / 'closeout/fold_comparison.csv', payload)
        reader.write_json(host, root / 'closeout/interpretation.json', {'authority_replaced': False})
        if region in r141['reuse_regions']:
            source = {'branch': 'work/pricefm-r137-four-region-pilot-20261015',
                      'head': r141['reuse_source']['head']}
            status = 'R137_REGION_COMPLETE_NOT_PROMOTED'
        elif region == 'CZ':
            source = copy.deepcopy(CLOSEOUT.R144_SOURCE)
            status = 'R144_CZ_FALLBACK_COMPLETE_NOT_PROMOTED'
        elif region == 'AT':
            source = copy.deepcopy(IDENTITY)
            status = 'R146_AT_FALLBACK_COMPLETE_NOT_PROMOTED'
        else:
            source = {'branch': r144['source_branch'], 'head': r144['source_head']}
            status = 'R141_REGION_COMPLETE_NOT_PROMOTED'
        terminal = {'status': status, 'source': source, 'test_used_for_selection': False}
        if region in ('AT', 'CZ'):
            config = r146 if region == 'AT' else r144
            stage = 'R146' if region == 'AT' else 'R144'
            terminal.update(fallback_rank=config['fallback_rank'],
                            fallback_candidate=config['fallback_candidate'])
            if region == 'AT':
                terminal.update(posterior_target_change_scope='within_each_fit',
                                model_choice_changed=True, same_target_resumption=False,
                                fallback_changes_posterior_target_relative_to_failed_model=True)
            reader.write_json(host, root / 'fallback_provenance.json', {
                **terminal, 'status': stage + '_PREDETERMINED_TRAINING_ONLY_FALLBACK_COMPLETED',
                'source_r141_head': config['source_head'],
                'source_rhs_closeout_sha256': config['source_rhs_closeout_sha256'],
                'posterior_target_changed': False, 'certificate_limits_changed': False})
        reader.write_json(host, root / 'terminal.json', terminal)
        seal = {'artifacts': {'fold_comparison.csv': CLOSEOUT.digest(payload),
                              'interpretation.json': CLOSEOUT.digest(
                                  reader.bytes(host, root / 'closeout/interpretation.json'))},
                'metadata': {'source': source, 'complete_regions': 1, 'complete_folds': 3}}
        reader.write_json(host, root / 'closeout/completed_evidence.json', seal)
        if region in r141['reuse_regions']:
            r141['reuse_source']['regions'][region]['completed_evidence_sha256'] = CLOSEOUT.digest(
                reader.bytes(host, root / 'closeout/completed_evidence.json'))
    return result


def test_complete_cohort_keeps_four_sources_and_uses_only_primary_operator(cohort):
    r141, r144, r146, reader = cohort
    folds, regions, provenance, summary = CLOSEOUT.collect(r141, r144, r146, reader, IDENTITY)
    assert len(folds) == 114 and len(regions) == 38 and len(provenance) == 38
    assert folds[['region', 'fold']].duplicated().sum() == 0
    assert set(folds.operator) == {'cdf_pool_clipped'}
    assert summary['source_counts'] == CLOSEOUT.EXPECTED_COUNTS
    assert summary['equal_region_fold_AQL'] == pytest.approx(5.187)
    assert summary['relative_change_vs_current_authority'] == pytest.approx(5.187 / 6 - 1)
    assert summary['r144_source_head'] == CLOSEOUT.R144_SOURCE['head'] != IDENTITY['head']
    assert summary['r146_source_head'] == IDENTITY['head']
    assert not summary['promotion_decided'] and not summary['authority_mutated']
    at = next(row for row in provenance if row['region'] == 'AT')
    assert at['fallback_rank'] == 4
    assert at['fallback_provenance_sha256']
    assert CLOSEOUT.readiness(r141, r144, r146, reader, IDENTITY)['status'] == 'R146_GLOBAL_CLOSEOUT_READY'


def test_old_at_terminal_cannot_stand_in_for_new_fallback(cohort):
    host, root = region_paths(cohort, 'AT'); reader = cohort[3]
    terminal = reader.json(host, root / 'terminal.json')
    terminal['status'] = 'R141_REGION_COMPLETE_NOT_PROMOTED'
    reader.write_json(host, root / 'terminal.json', terminal)
    with pytest.raises(RuntimeError, match='R146 fallback terminal/source'):
        CLOSEOUT.collect(*cohort, IDENTITY)


@pytest.mark.parametrize('region', ['AT', 'CZ'])
def test_fallback_rejects_wrong_source_even_with_self_consistent_terminal(cohort, region):
    host, root = region_paths(cohort, region); reader = cohort[3]
    source = copy.deepcopy(IDENTITY if region == 'CZ' else CLOSEOUT.R144_SOURCE)
    terminal = reader.json(host, root / 'terminal.json'); terminal['source'] = source
    reader.write_json(host, root / 'terminal.json', terminal)
    seal = reader.json(host, root / 'closeout/completed_evidence.json')
    seal['metadata']['source'] = source
    reader.write_json(host, root / 'closeout/completed_evidence.json', seal)
    with pytest.raises(RuntimeError, match='fallback terminal/source identity'):
        CLOSEOUT.collect(*cohort, IDENTITY)


@pytest.mark.parametrize('field,value', [('test_used_for_selection', True),
                                       ('posterior_target_changed', True),
                                       ('certificate_limits_changed', True),
                                       ('source_rhs_closeout_sha256', 'different-ranking')])
def test_fallback_rejects_scientific_or_selection_provenance_changes(cohort, field, value):
    host, root = region_paths(cohort, 'AT'); reader = cohort[3]
    provenance = reader.json(host, root / 'fallback_provenance.json')
    provenance[field] = value
    reader.write_json(host, root / 'fallback_provenance.json', provenance)
    with pytest.raises(RuntimeError, match='train-only fallback provenance'):
        CLOSEOUT.collect(*cohort, IDENTITY)


def test_fallback_rejects_changed_architecture_metadata(cohort):
    host, root = region_paths(cohort, 'AT'); reader = cohort[3]
    terminal = reader.json(host, root / 'terminal.json')
    terminal['fallback_candidate']['spec']['readout'] = 'augmented'
    reader.write_json(host, root / 'terminal.json', terminal)
    with pytest.raises(RuntimeError, match='fallback choice differs'):
        CLOSEOUT.collect(*cohort, IDENTITY)


def test_at_cannot_mislabel_different_candidate_as_same_target_resumption(cohort):
    host, root = region_paths(cohort, 'AT'); reader = cohort[3]
    terminal = reader.json(host, root / 'terminal.json')
    terminal['same_target_resumption'] = True
    reader.write_json(host, root / 'terminal.json', terminal)
    with pytest.raises(RuntimeError, match='declare its new model target'):
        CLOSEOUT.collect(*cohort, IDENTITY)


@pytest.mark.parametrize('artifact', ['fold_comparison.csv', 'interpretation.json'])
def test_every_sealed_regional_artifact_is_checked(cohort, artifact):
    host, root = region_paths(cohort, 'BG'); reader = cohort[3]
    reader.write(host, root / 'closeout' / artifact, b'changed')
    with pytest.raises(RuntimeError, match='does not match its seal'):
        CLOSEOUT.collect(*cohort, IDENTITY)


def test_reused_pilot_seal_is_pinned_even_if_artifact_hashes_still_match(cohort):
    host, root = region_paths(cohort, 'EE'); reader = cohort[3]
    path = root / 'closeout/completed_evidence.json'
    seal = reader.json(host, path); seal['new_metadata'] = 'not-original'
    reader.write_json(host, path, seal)
    with pytest.raises(RuntimeError, match='reused R137'):
        CLOSEOUT.collect(*cohort, IDENTITY)


def test_r141_requires_the_frozen_branch_as_well_as_head(cohort):
    host, root = region_paths(cohort, 'BG'); reader = cohort[3]
    terminal = reader.json(host, root / 'terminal.json')
    terminal['source']['branch'] = 'another-lane'
    reader.write_json(host, root / 'terminal.json', terminal)
    seal = reader.json(host, root / 'closeout/completed_evidence.json')
    seal['metadata']['source'] = terminal['source']
    reader.write_json(host, root / 'closeout/completed_evidence.json', seal)
    with pytest.raises(RuntimeError, match='R141 regional terminal/source'):
        CLOSEOUT.collect(*cohort, IDENTITY)


@pytest.mark.parametrize('change', ['duplicate_secondary', 'missing_operator', 'wrong_region',
                                   'bad_fold', 'missing_score', 'nan', 'infinity', 'negative'])
def test_sealed_but_invalid_matched_surface_is_rejected(cohort, change):
    def transform(frame):
        if change == 'duplicate_secondary':
            row = frame.index[(frame.operator == 'mean_feature') & (frame.fold == 1)][0]
            frame.loc[row, 'fold'] = 2
        elif change == 'missing_operator':
            frame = frame[frame.operator != 'mean_feature']
        elif change == 'wrong_region':
            frame.loc[0, 'region'] = 'AT'
        elif change == 'bad_fold':
            frame.loc[0, 'fold'] = 4
        elif change == 'missing_score':
            frame = frame.drop(columns='operational_pricefm_AQL')
        else:
            frame.loc[0, 'AQL'] = {'nan': np.nan, 'infinity': np.inf, 'negative': -1.0}[change]
        return frame
    replace_table(cohort, 'BG', transform)
    with pytest.raises(RuntimeError):
        CLOSEOUT.collect(*cohort, IDENTITY)


def test_duplicate_cohort_region_is_rejected_before_aggregation(cohort):
    cohort[0]['regions'][0] = cohort[0]['regions'][1]
    with pytest.raises(RuntimeError, match='cohort'):
        CLOSEOUT.collect(*cohort, IDENTITY)


def test_incomplete_regional_seal_cannot_certify_three_folds(cohort):
    host, root = region_paths(cohort, 'BG'); reader = cohort[3]
    seal = reader.json(host, root / 'closeout/completed_evidence.json')
    seal['metadata']['complete_folds'] = 2
    reader.write_json(host, root / 'closeout/completed_evidence.json', seal)
    with pytest.raises(RuntimeError, match='completeness metadata'):
        CLOSEOUT.collect(*cohort, IDENTITY)


def test_seal_cannot_read_an_artifact_outside_its_closeout(cohort):
    host, root = region_paths(cohort, 'BG'); reader = cohort[3]
    seal = reader.json(host, root / 'closeout/completed_evidence.json')
    seal['artifacts']['../external'] = 'not-authorized'
    reader.write_json(host, root / 'closeout/completed_evidence.json', seal)
    with pytest.raises(RuntimeError, match='unsafe regional artifact name'):
        CLOSEOUT.collect(*cohort, IDENTITY)


def test_fallback_rank_is_prespecified_rather_than_accepted_from_terminal(cohort):
    host, root = region_paths(cohort, 'AT'); reader = cohort[3]
    terminal = reader.json(host, root / 'terminal.json')
    terminal['fallback_rank'] = 7
    reader.write_json(host, root / 'terminal.json', terminal)
    with pytest.raises(RuntimeError, match='fallback choice differs'):
        CLOSEOUT.collect(*cohort, IDENTITY)


def test_readiness_distinguishes_missing_terminal_from_invalid_sealed_output(cohort):
    host, root = region_paths(cohort, 'AT'); reader = cohort[3]
    old = reader.values.pop((host, str(root / 'terminal.json')))
    ready = CLOSEOUT.readiness(*cohort, IDENTITY)
    assert ready['status'] == 'R146_GLOBAL_CLOSEOUT_WAITING'
    assert ready['complete_count'] == 37 and ready['pending'] == ['AT']
    reader.write(host, root / 'terminal.json', old)
    reader.write(host, root / 'closeout/interpretation.json', b'changed')
    with pytest.raises(RuntimeError, match='does not match its seal'):
        CLOSEOUT.readiness(*cohort, IDENTITY)


@pytest.mark.parametrize('code', [1, 255])
def test_ssh_failure_is_never_reported_as_missing(monkeypatch, code):
    monkeypatch.setattr(CLOSEOUT.subprocess, 'run', lambda *a, **k: SimpleNamespace(
        returncode=code, stdout=b'', stderr=b'connection failed'))
    with pytest.raises(RuntimeError, match='inspection failed'):
        CLOSEOUT.EvidenceReader().exists('jerez', Path('/evidence'))


def test_remote_absence_requires_explicit_successful_response(monkeypatch):
    responses = iter([b'R146_FILE_ABSENT', b'R146_FILE_PRESENT', b'R146_NOT_FILE'])
    monkeypatch.setattr(CLOSEOUT.subprocess, 'run', lambda *a, **k: SimpleNamespace(
        returncode=0, stdout=next(responses), stderr=b''))
    reader = CLOSEOUT.EvidenceReader()
    assert reader.exists('jerez', Path('/evidence')) is False
    assert reader.exists('jerez', Path('/evidence')) is True
    with pytest.raises(RuntimeError, match='invalid remote evidence'):
        reader.exists('jerez', Path('/evidence'))


def snapshot_payload(cohort):
    values = {}
    for region in cohort[0]['regions']:
        host, root = region_paths(cohort, region)
        if host != 'jerez':
            continue
        names = set(CLOSEOUT.SNAPSHOT_FILES)
        seal_path = root / 'closeout/completed_evidence.json'
        if cohort[3].exists(host, seal_path):
            names.update('closeout/' + name for name in cohort[3].json(host, seal_path)['artifacts'])
        for name in names:
            path = root / name
            values[str(path)] = (base64.b64encode(cohort[3].bytes(host, path)).decode()
                                 if cohort[3].exists(host, path) else None)
    return values


def test_one_ssh_snapshot_per_validation_pass_and_no_cache_across_passes(cohort, monkeypatch):
    reader = CLOSEOUT.EvidenceReader()
    calls = []
    def remote(command, input_bytes=None):
        assert command.startswith('python3 -c ')
        roots = json.loads(input_bytes)
        assert roots and all(Path(root).parent == CLOSEOUT.DATA / 'campaigns' for root in roots)
        calls.append(roots)
        return json.dumps(snapshot_payload(cohort)).encode()
    monkeypatch.setattr(reader, '_remote', remote)
    local_bytes = reader.bytes; local_exists = reader.exists
    monkeypatch.setattr(reader, 'bytes', lambda host, path:
                        cohort[3].bytes(host, path) if host == 'muscat' else local_bytes(host, path))
    monkeypatch.setattr(reader, 'exists', lambda host, path:
                        cohort[3].exists(host, path) if host == 'muscat' else local_exists(host, path))
    assert CLOSEOUT.collect(*cohort[:3], reader, IDENTITY)[3]['folds'] == 114
    assert len(calls) == 1
    host, root = region_paths(cohort, 'CZ')
    del cohort[3].values[(host, str(root / 'terminal.json'))]
    ready = CLOSEOUT.readiness(*cohort[:3], reader, IDENTITY)
    assert len(calls) == 2
    assert ready['pending'] == ['CZ']


@pytest.mark.parametrize('malformation', ['unexpected_path', 'missing_marker', 'bad_base64', 'bad_hash'])
def test_remote_snapshot_is_fully_validated_before_cache_install(cohort, monkeypatch, malformation):
    values = snapshot_payload(cohort)
    host, root = region_paths(cohort, 'CZ')
    if malformation == 'unexpected_path':
        values['/not/allowlisted'] = None
    elif malformation == 'missing_marker':
        del values[str(root / 'terminal.json')]
    elif malformation == 'bad_base64':
        values[str(root / 'terminal.json')] = '%%%'
    else:
        values[str(root / 'closeout/fold_comparison.csv')] = base64.b64encode(b'tampered').decode()
    reader = CLOSEOUT.EvidenceReader()
    monkeypatch.setattr(reader, '_remote', lambda *args: json.dumps(values).encode())
    roots = [region_paths(cohort, region) for region in cohort[0]['regions']]
    with pytest.raises(RuntimeError):
        reader.prefetch(roots)
    assert reader._snapshot is None


def test_snapshot_transport_failure_cannot_use_previous_success(cohort, monkeypatch):
    reader = CLOSEOUT.EvidenceReader()
    roots = [region_paths(cohort, region) for region in cohort[0]['regions']]
    monkeypatch.setattr(reader, '_remote', lambda *args: json.dumps(snapshot_payload(cohort)).encode())
    reader.prefetch(roots)
    assert reader._snapshot is not None
    def failed(*args):
        raise RuntimeError('SSH failed')
    monkeypatch.setattr(reader, '_remote', failed)
    with pytest.raises(RuntimeError, match='SSH failed'):
        reader.prefetch(roots)
    assert reader._snapshot is None


def test_final_outputs_are_sealed_and_cannot_be_overwritten(cohort, monkeypatch, tmp_path):
    monkeypatch.setattr(CLOSEOUT, 'configs', lambda: cohort[:3])
    monkeypatch.setattr(CLOSEOUT, 'source_identity', lambda: IDENTITY)
    monkeypatch.setattr(CLOSEOUT, 'EvidenceReader', lambda host: cohort[3])
    summary = CLOSEOUT.closeout(tmp_path)
    assert summary['status'] == 'R146_ALL_REGION_COMPLETE_NOT_PROMOTED'
    manifest = json.loads((tmp_path / 'completed_evidence.json').read_text())
    for name, expected in manifest['artifacts'].items():
        assert CLOSEOUT.digest((tmp_path / name).read_bytes()) == expected
    assert CLOSEOUT.closeout(tmp_path) == summary
    (tmp_path / 'summary.json').write_text('tampered')
    with pytest.raises(RuntimeError, match='existing sealed R146'):
        CLOSEOUT.closeout(tmp_path)
    assert (tmp_path / 'summary.json').read_text() == 'tampered'
