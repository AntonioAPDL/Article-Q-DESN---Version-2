#!/usr/bin/env python3
"""Validate and aggregate 4 R137 + 32 R141 + R144 CZ + R146 AT results."""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import shlex
import stat
import subprocess
import time

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[3]
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
TAG = 'pricefm_stage_r146_at_training_fallback_20261022'
R141_CONFIG = ROOT / 'application/config/pricefm_stage_r141_recovery_rollout_20261019.json'
R144_CONFIG = ROOT / 'application/config/pricefm_stage_r144_cz_training_fallback_20261020.json'
R146_CONFIG = ROOT / 'application/config' / (TAG + '.json')
R144_SOURCE = {'branch': 'work/pricefm-r144-cz-training-fallback-20261020',
               'head': 'f96fcb0e3dc47da236d656cda2f0e58fb537ee1f'}
OPERATORS = {'cdf_pool_clipped', 'mean_feature', 'path_specific', 'normal_driver'}
SCORES = ['AQL', 'qdesn_AQL', 'pricefm_AQL', 'operational_pricefm_AQL']
EXPECTED_COUNTS = {'R137_reused_exactly': 4, 'R141_recovered_or_new_region': 32,
                   'R144_predetermined_training_only_fallback': 1,
                   'R146_predetermined_training_only_fallback': 1}
SNAPSHOT_FILES = ('terminal.json', 'closeout/completed_evidence.json',
                  'closeout/fold_comparison.csv', 'fallback_provenance.json')
REMOTE_SNAPSHOT = r'''
import base64,json,stat,sys
from pathlib import Path,PurePosixPath
roots=json.load(sys.stdin)
base=Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/campaigns')
values={}
def read(path):
    key=str(path)
    if key in values:return
    try:mode=path.stat().st_mode
    except FileNotFoundError:values[key]=None;return
    if not stat.S_ISREG(mode):raise RuntimeError('evidence is not a regular file: '+key)
    values[key]=base64.b64encode(path.read_bytes()).decode('ascii')
for name in roots:
    root=Path(name)
    if root.parent!=base or root.name in ('.','..'):
        raise RuntimeError('snapshot root is outside allowlisted campaigns')
    for name in ('terminal.json','closeout/completed_evidence.json',
                 'closeout/fold_comparison.csv','fallback_provenance.json'):
        read(root/name)
    seal=values[str(root/'closeout/completed_evidence.json')]
    if seal is not None:
        artifacts=json.loads(base64.b64decode(seal))['artifacts']
        if not isinstance(artifacts,dict):raise RuntimeError('invalid artifact manifest')
        for name in artifacts:
            relative=PurePosixPath(name)
            if relative.is_absolute() or '..' in relative.parts or not relative.parts:
                raise RuntimeError('unsafe artifact name')
            read(root/'closeout'/name)
json.dump(values,sys.stdout,sort_keys=True)
'''


def digest(value):
    return hashlib.sha256(value).hexdigest()


def atomic(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f'.tmp.{os.getpid()}')
    temporary.write_bytes(value)
    os.replace(temporary, path)


def git(*arguments):
    return subprocess.check_output(['git', *arguments], cwd=ROOT, text=True).strip()


def source_identity():
    identity = {'branch': git('branch', '--show-current'), 'head': git('rev-parse', 'HEAD')}
    if not identity['branch'].startswith('work/pricefm-r146-at-training-fallback-'):
        raise RuntimeError('dedicated R146 source branch required for global closeout')
    if git('status', '--porcelain'):
        raise RuntimeError('clean committed R146 source required for global closeout')
    return identity


class EvidenceReader:
    """A failed SSH command is an inspection failure, never missing evidence."""

    def __init__(self, jerez_host='jerez'):
        self.jerez_host = jerez_host
        self._snapshot = None

    def _remote(self, command, input_bytes=None):
        result = subprocess.run(
            ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', self.jerez_host, command],
            input=input_bytes, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=45)
        if result.returncode:
            raise RuntimeError('Jerez evidence inspection failed (exit %s): %s' %
                               (result.returncode, result.stderr.decode(errors='replace').strip()))
        return result.stdout

    def prefetch(self, roots):
        """Replace, never extend, the remote snapshot at each validation pass."""
        self._snapshot = None
        remote_roots = sorted({str(root) for host, root in roots if host == 'jerez'})
        campaign_base = DATA / 'campaigns'
        if any(Path(root).parent != campaign_base for root in remote_roots):
            raise RuntimeError('remote snapshot root is outside allowlisted campaigns')
        if not remote_roots:
            self._snapshot = {}
            return
        encoded = self._remote('python3 -c ' + shlex.quote(REMOTE_SNAPSHOT),
                               json.dumps(remote_roots).encode())
        try:
            values = json.loads(encoded)
        except ValueError as error:
            raise RuntimeError('malformed remote evidence snapshot JSON') from error
        if not isinstance(values, dict):
            raise RuntimeError('remote evidence snapshot is not a mapping')
        decoded = {}
        try:
            for path, value in values.items():
                decoded[path] = None if value is None else base64.b64decode(value, validate=True)
            expected = set()
            for root_text in remote_roots:
                root = Path(root_text)
                expected.update(str(root / name) for name in SNAPSHOT_FILES)
                seal_path = str(root / 'closeout/completed_evidence.json')
                if seal_path not in decoded:
                    raise RuntimeError('remote snapshot omitted a required evidence marker')
                if decoded[seal_path] is not None:
                    artifacts = json.loads(decoded[seal_path])['artifacts']
                    if not isinstance(artifacts, dict):
                        raise RuntimeError('remote snapshot contains an invalid artifact manifest')
                    for name in artifacts:
                        relative = PurePosixPath(name)
                        if relative.is_absolute() or '..' in relative.parts or not relative.parts:
                            raise RuntimeError('remote snapshot contains an unsafe artifact name')
                        expected.add(str(root / 'closeout' / name))
            if set(decoded) != expected:
                raise RuntimeError('remote snapshot paths differ from the complete allowlist')
            for root_text in remote_roots:
                root = Path(root_text)
                seal = decoded[str(root / 'closeout/completed_evidence.json')]
                if seal is None:
                    continue
                for name, expected_hash in json.loads(seal)['artifacts'].items():
                    payload = decoded[str(root / 'closeout' / name)]
                    if payload is None or digest(payload) != expected_hash:
                        raise RuntimeError('remote snapshot artifact does not match its seal: ' + name)
        except (ValueError, TypeError, KeyError) as error:
            raise RuntimeError('malformed remote evidence snapshot') from error
        self._snapshot = decoded

    def _cached(self, path):
        key = str(path)
        if key not in self._snapshot:
            raise RuntimeError('remote evidence was not included in this validation snapshot: ' + key)
        return self._snapshot[key]

    def bytes(self, host, path):
        if host == 'muscat':
            return Path(path).read_bytes()
        if host != 'jerez':
            raise ValueError('unexpected evidence host: ' + str(host))
        if self._snapshot is not None:
            value = self._cached(path)
            if value is None:
                raise FileNotFoundError('remote evidence is missing: ' + str(path))
            return value
        return self._remote('cat -- ' + shlex.quote(str(path)))

    def exists(self, host, path):
        if host == 'muscat':
            try:
                mode = Path(path).stat().st_mode
            except FileNotFoundError:
                return False
            if not stat.S_ISREG(mode):
                raise RuntimeError('evidence path is not a regular file: ' + str(path))
            return True
        if host != 'jerez':
            raise ValueError('unexpected evidence host: ' + str(host))
        if self._snapshot is not None:
            return self._cached(path) is not None
        quoted = shlex.quote(str(path))
        marker = self._remote(
            f"if test -f {quoted}; then printf R146_FILE_PRESENT; "
            f"elif test -e {quoted}; then printf R146_NOT_FILE; "
            'else printf R146_FILE_ABSENT; fi')
        if marker == b'R146_FILE_PRESENT':
            return True
        if marker == b'R146_FILE_ABSENT':
            return False
        raise RuntimeError('invalid remote evidence response: ' + repr(marker))

    def json(self, host, path):
        return json.loads(self.bytes(host, path))


def validate_contract(r141, r144, r146):
    regions = r141['regions']
    reuse = r141['reuse_regions']
    if (len(regions) != 38 or len(set(regions)) != 38 or len(reuse) != 4
            or set(reuse) != set(r141['reuse_source']['regions'])
            or not set(reuse).issubset(regions) or {'AT', 'CZ'} & set(reuse)
            or not {'AT', 'CZ'}.issubset(regions)
            or r144['region'] != 'CZ' or r146['region'] != 'AT'
            or r146['tag'] != TAG
            or r141['primary_quantile_operator'] != 'cdf_pool_clipped'
            or (r146['source_branch'], r146['source_head']) !=
               (r144['source_branch'], r144['source_head'])):
        raise RuntimeError('R146 global cohort or frozen source contract differs')


def region_host(config, region):
    if region in config['reuse_regions']:
        host = config['reuse_source']['regions'][region]['host']
    else:
        matches = [host for host, slots in config['host_queues'].items()
                   if any(region in queue for queue in slots.values())]
        if len(matches) != 1:
            raise RuntimeError('region does not have one frozen evidence host: ' + region)
        host = matches[0]
    if host not in ('muscat', 'jerez'):
        raise RuntimeError('invalid region evidence host: ' + str(host))
    return host


def campaign_path(r141, r144, r146, region):
    if region in r141['reuse_regions']:
        tag = r141['reuse_source']['tag'] + '__' + region
    elif region == 'CZ':
        tag = r144['tag']
    elif region == 'AT':
        tag = r146['tag']
    else:
        tag = r141['tag'] + '__' + region
    return DATA / 'campaigns' / tag


def _fallback_identity(value, config, label):
    candidate = value.get('fallback_candidate', {})
    expected = config['fallback_candidate']
    if value.get('fallback_rank') != config['fallback_rank'] or candidate != expected:
        raise RuntimeError(label + ' frozen fallback choice differs')


def _at_target_scope(value):
    expected = {'posterior_target_change_scope': 'within_each_fit',
                'model_choice_changed': True, 'same_target_resumption': False,
                'fallback_changes_posterior_target_relative_to_failed_model': True}
    if any(value.get(key) != item for key, item in expected.items()):
        raise RuntimeError('R146 AT fallback must declare its new model target separately from within-fit invariance')


def validated_region(r141, r144, r146, reader, identity, region):
    host = region_host(r141, region)
    root = campaign_path(r141, r144, r146, region)
    seal_bytes = reader.bytes(host, root / 'closeout/completed_evidence.json')
    seal = json.loads(seal_bytes)
    terminal_bytes = reader.bytes(host, root / 'terminal.json')
    terminal = json.loads(terminal_bytes)
    metadata = seal.get('metadata', {})
    source = metadata.get('source', {})
    if (metadata.get('complete_regions') != 1 or metadata.get('complete_folds') != 3
            or not isinstance(source, dict) or not source.get('head')
            or terminal.get('source') != source):
        raise RuntimeError('regional source or completeness metadata differs: ' + region)
    if terminal.get('test_used_for_selection') not in (None, False):
        raise RuntimeError('test-selected regional evidence is forbidden: ' + region)
    if region in r141['reuse_regions']:
        expected = r141['reuse_source']['regions'][region]['completed_evidence_sha256']
        if (digest(seal_bytes) != expected or source['head'] != r141['reuse_source']['head']
                or terminal.get('status') != 'R137_REGION_COMPLETE_NOT_PROMOTED'):
            raise RuntimeError('reused R137 source or sealed evidence differs: ' + region)
        source_class = 'R137_reused_exactly'
    elif region in ('CZ', 'AT'):
        config = r144 if region == 'CZ' else r146
        expected_source = R144_SOURCE if region == 'CZ' else identity
        stage = 'R144' if region == 'CZ' else 'R146'
        if (source != expected_source
                or terminal.get('status') != f'{stage}_{region}_FALLBACK_COMPLETE_NOT_PROMOTED'):
            raise RuntimeError(stage + ' fallback terminal/source identity differs')
        _fallback_identity(terminal, config, stage)
        fallback_bytes = reader.bytes(host, root / 'fallback_provenance.json')
        fallback = json.loads(fallback_bytes)
        if (fallback.get('status') != f'{stage}_PREDETERMINED_TRAINING_ONLY_FALLBACK_COMPLETED'
                or fallback.get('source') != expected_source
                or fallback.get('source_r141_head') != config['source_head']
                or fallback.get('source_rhs_closeout_sha256') != config['source_rhs_closeout_sha256']
                or any(fallback.get(key) is not False for key in
                       ('test_used_for_selection', 'posterior_target_changed', 'certificate_limits_changed'))):
            raise RuntimeError(stage + ' train-only fallback provenance differs')
        _fallback_identity(fallback, config, stage)
        if region == 'AT':
            _at_target_scope(terminal)
            _at_target_scope(fallback)
        source_class = stage + '_predetermined_training_only_fallback'
    else:
        expected_source = {'branch': r144['source_branch'], 'head': r144['source_head']}
        if (source != expected_source or terminal.get('status') != 'R141_REGION_COMPLETE_NOT_PROMOTED'):
            raise RuntimeError('R141 regional terminal/source differs: ' + region)
        source_class = 'R141_recovered_or_new_region'
    artifacts = seal.get('artifacts', {})
    if not isinstance(artifacts, dict) or 'fold_comparison.csv' not in artifacts:
        raise RuntimeError('regional artifact seal is incomplete: ' + region)
    payloads = {}
    for name, expected in artifacts.items():
        relative = PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts or not relative.parts:
            raise RuntimeError('unsafe regional artifact name: ' + str(name))
        payload = reader.bytes(host, root / 'closeout' / name)
        if digest(payload) != expected:
            raise RuntimeError('regional artifact does not match its seal: ' + region + '/' + name)
        payloads[name] = payload
    frame = pd.read_csv(io.BytesIO(payloads['fold_comparison.csv']))
    required = {'region', 'fold', 'operator', *SCORES}
    if not required.issubset(frame.columns) or set(frame.region) != {region}:
        raise RuntimeError('malformed regional fold table: ' + region)
    if (len(frame) != 12 or set(frame.operator) != OPERATORS or set(frame.fold) != {1, 2, 3}
            or frame[['region', 'fold', 'operator']].duplicated().any()):
        raise RuntimeError('regional operator/fold surface is incomplete or duplicated: ' + region)
    try:
        scores = frame[SCORES].apply(pd.to_numeric, errors='raise').to_numpy(dtype=float)
    except (TypeError, ValueError) as error:
        raise RuntimeError('regional scores are not numeric: ' + region) from error
    if not np.isfinite(scores).all() or (scores < 0).any():
        raise RuntimeError('regional scores are nonfinite or negative: ' + region)
    frame[SCORES] = scores
    primary = frame[frame.operator.eq(r141['primary_quantile_operator'])].copy()
    primary['evidence_host'] = host
    primary['source_class'] = source_class
    record = {'region': region, 'host': host, 'source_class': source_class,
              'campaign': str(root), 'source': source,
              'completed_evidence_sha256': digest(seal_bytes),
              'terminal_sha256': digest(terminal_bytes), 'artifact_sha256': artifacts}
    if region in ('CZ', 'AT'):
        record['fallback_provenance_sha256'] = digest(fallback_bytes)
        record['fallback_rank'] = config['fallback_rank']
        record['fallback_candidate'] = config['fallback_candidate']
    return primary, record


def readiness(r141, r144, r146, reader, identity):
    validate_contract(r141, r144, r146)
    prefetch = getattr(reader, 'prefetch', None)
    if prefetch is not None:
        prefetch([(region_host(r141, region), campaign_path(r141, r144, r146, region))
                  for region in r141['regions']])
    complete = []; pending = []
    for region in r141['regions']:
        host = region_host(r141, region)
        root = campaign_path(r141, r144, r146, region)
        required = [root / 'terminal.json', root / 'closeout/completed_evidence.json',
                    root / 'closeout/fold_comparison.csv']
        if not all(reader.exists(host, path) for path in required):
            pending.append(region)
            continue
        validated_region(r141, r144, r146, reader, identity, region)
        complete.append(region)
    return {'status': 'R146_GLOBAL_CLOSEOUT_WAITING' if pending else 'R146_GLOBAL_CLOSEOUT_READY',
            'complete': complete, 'pending': pending, 'complete_count': len(complete),
            'remaining_count': len(pending), 'total': 38,
            'source': identity, 'evidence_validated': True, 'expected_source_counts': EXPECTED_COUNTS}


def collect(r141, r144, r146, reader, identity):
    validate_contract(r141, r144, r146)
    prefetch = getattr(reader, 'prefetch', None)
    if prefetch is not None:
        prefetch([(region_host(r141, region), campaign_path(r141, r144, r146, region))
                  for region in r141['regions']])
    frames = []; provenance = []
    for region in r141['regions']:
        frame, record = validated_region(r141, r144, r146, reader, identity, region)
        frames.append(frame); provenance.append(record)
    counts = {name: sum(row['source_class'] == name for row in provenance) for name in EXPECTED_COUNTS}
    if counts != EXPECTED_COUNTS:
        raise RuntimeError('expected exactly 4 R137 + 32 R141 + 1 R144 CZ + 1 R146 AT')
    folds = pd.concat(frames, ignore_index=True).sort_values(['region', 'fold'])
    if (len(folds) != 114 or folds[['region', 'fold']].duplicated().any()
            or set(folds.region) != set(r141['regions'])):
        raise RuntimeError('expected 38 regions by three unique primary folds')
    regions = folds.groupby('region', as_index=False)[SCORES].mean()
    authority = float(folds.qdesn_AQL.mean())
    summary = {'status': 'R146_ALL_REGION_COMPLETE_NOT_PROMOTED', 'regions': 38, 'folds': 114,
               'r137_reused_regions': 4, 'r141_regions': 32,
               'r144_fallback_regions': 1, 'r146_fallback_regions': 1,
               'source_counts': counts, 'r141_source_head': r144['source_head'],
               'r144_source_head': R144_SOURCE['head'], 'r146_source_head': identity['head'],
               'primary_operator': r141['primary_quantile_operator'],
               'equal_region_fold_AQL': float(folds.AQL.mean()),
               'current_authority_AQL': authority,
               'local_pricefm_AQL': float(folds.pricefm_AQL.mean()),
               'operational_pricefm_AQL': float(folds.operational_pricefm_AQL.mean()),
               'relative_change_vs_current_authority':
                   float(folds.AQL.mean() / authority - 1) if authority > 0 else None,
               'authority_mutated': False, 'article_mutated': False, 'promotion_decided': False}
    return folds, regions, provenance, summary


def configs():
    return tuple(json.loads(path.read_text()) for path in (R141_CONFIG, R144_CONFIG, R146_CONFIG))


def closeout(output, jerez_host='jerez'):
    r141, r144, r146 = configs()
    identity = source_identity(); reader = EvidenceReader(jerez_host)
    ready = readiness(r141, r144, r146, reader, identity)
    if ready['pending']:
        raise RuntimeError('regional evidence is incomplete: ' + ','.join(ready['pending']))
    folds, regions, provenance, summary = collect(r141, r144, r146, reader, identity)
    values = {'fold_comparison.csv': folds.to_csv(index=False).encode(),
              'region_comparison.csv': regions.to_csv(index=False).encode(),
              'provenance.json': (json.dumps(provenance, indent=2, sort_keys=True) + '\n').encode(),
              'summary.json': (json.dumps(summary, indent=2, sort_keys=True) + '\n').encode()}
    manifest = {'status': summary['status'], 'source': identity,
                'artifacts': {name: digest(value) for name, value in values.items()}}
    output = Path(output)
    existing = output / 'completed_evidence.json'
    if existing.exists():
        if (json.loads(existing.read_text()) != manifest
                or any(not (output / name).is_file() or digest((output / name).read_bytes()) != digest(value)
                       for name, value in values.items())):
            raise RuntimeError('existing sealed R146 global closeout differs; evidence preserved')
        return summary
    for name, value in values.items():
        atomic(output / name, value)
    atomic(existing, (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode())
    return summary


def wait_closeout(output, runtime, jerez_host='jerez', poll_seconds=60):
    r141, r144, r146 = configs()
    identity = source_identity(); reader = EvidenceReader(jerez_host)
    runtime = Path(runtime); runtime.mkdir(parents=True, exist_ok=True)
    with (runtime / 'supervisor.lock').open('a') as lock:
        fcntl = __import__('fcntl'); fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            while True:
                state = readiness(r141, r144, r146, reader, identity)
                state.update(source=identity, epoch=time.time())
                atomic(runtime / 'progress.json', (json.dumps(state, indent=2, sort_keys=True) + '\n').encode())
                if not state['pending']:
                    break
                time.sleep(poll_seconds)
            summary = closeout(output, jerez_host)
            atomic(runtime / 'terminal.json', (json.dumps(summary, indent=2, sort_keys=True) + '\n').encode())
            return summary
        except Exception as error:
            atomic(runtime / 'blocked.json', (json.dumps({
                'status': 'R146_GLOBAL_CLOSEOUT_BLOCKED', 'error': str(error),
                'source': identity, 'epoch': time.time(), 'evidence_preserved': True,
                'authority_mutated': False}, indent=2, sort_keys=True) + '\n').encode())
            raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('status', 'closeout', 'wait'))
    parser.add_argument('--output', type=Path, default=DATA / 'runtime_audits' / TAG / 'closeout')
    parser.add_argument('--runtime', type=Path, default=DATA / 'launch_prep' / TAG / 'muscat_closeout')
    parser.add_argument('--jerez-host', default='jerez')
    parser.add_argument('--poll-seconds', type=int, default=60)
    arguments = parser.parse_args()
    if arguments.poll_seconds < 1:
        parser.error('--poll-seconds must be positive')
    if arguments.action == 'status':
        result = readiness(*configs(), EvidenceReader(arguments.jerez_host), source_identity())
    elif arguments.action == 'closeout':
        result = closeout(arguments.output, arguments.jerez_host)
    else:
        result = wait_closeout(arguments.output, arguments.runtime, arguments.jerez_host,
                               arguments.poll_seconds)
    print(json.dumps(result, indent=2, sort_keys=True), flush=True)
