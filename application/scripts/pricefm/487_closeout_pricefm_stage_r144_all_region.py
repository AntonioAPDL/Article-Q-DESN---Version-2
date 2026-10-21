#!/usr/bin/env python3
"""Close out 4 R137 + 33 R141 + repaired R144 CZ regional results."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import time

import pandas as pd

ROOT = Path(__file__).resolve().parents[3]
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
R141_CONFIG = ROOT / 'application/config/pricefm_stage_r141_recovery_rollout_20261019.json'
R144_CONFIG = ROOT / 'application/config/pricefm_stage_r144_cz_training_fallback_20261020.json'


def digest(value):
    return hashlib.sha256(value).hexdigest()


def atomic(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f'.tmp.{os.getpid()}')
    temporary.write_bytes(value); os.replace(temporary, path)


def git(root, *arguments):
    return subprocess.check_output(['git', *arguments], cwd=root, text=True).strip()


def source_identity():
    value = {'branch': git(ROOT, 'branch', '--show-current'), 'head': git(ROOT, 'rev-parse', 'HEAD')}
    if not value['branch'].startswith('work/pricefm-r144-cz-training-fallback-'):
        raise RuntimeError('dedicated clean R144 branch required for closeout')
    if git(ROOT, 'status', '--porcelain'):
        raise RuntimeError('clean committed R144 closeout source required')
    return value


class EvidenceReader:
    def __init__(self, jerez_host='jerez'):
        self.jerez_host = jerez_host

    def bytes(self, host, path):
        if host == 'muscat':
            return Path(path).read_bytes()
        if host != 'jerez':
            raise ValueError('unexpected evidence host: ' + host)
        return subprocess.check_output(['ssh', self.jerez_host, 'cat', str(path)])

    def exists(self, host, path):
        if host == 'muscat':
            return Path(path).is_file()
        return subprocess.run(['ssh', self.jerez_host, 'test', '-f', str(path)]).returncode == 0

    def json(self, host, path):
        return json.loads(self.bytes(host, path))

    def csv(self, host, path):
        return pd.read_csv(io.BytesIO(self.bytes(host, path)))


def region_host(config, region):
    if region in config['reuse_regions']:
        return config['reuse_source']['regions'][region]['host']
    matches = [host for host, slots in config['host_queues'].items()
               if any(region in queue for queue in slots.values())]
    if len(matches) != 1:
        raise RuntimeError('region does not have one frozen host: ' + region)
    return matches[0]


def campaign_path(r141, r144, region):
    if region in r141['reuse_regions']:
        tag = r141['reuse_source']['tag'] + '__' + region
    elif region == r144['region']:
        tag = r144['tag']
    else:
        tag = r141['tag'] + '__' + region
    return DATA / 'campaigns' / tag


def readiness(r141, r144, reader):
    complete = []; pending = []
    for region in r141['regions']:
        host = region_host(r141, region); root = campaign_path(r141, r144, region)
        paths = [root / 'terminal.json', root / 'closeout/completed_evidence.json',
                 root / 'closeout/fold_comparison.csv']
        (complete if all(reader.exists(host, path) for path in paths) else pending).append(region)
    return {'complete': complete, 'pending': pending, 'complete_count': len(complete),
            'remaining_count': len(pending), 'total': len(r141['regions'])}


def collect(r141, r144, reader, identity):
    frames = []; provenance = []; r141_regions = []; r144_regions = []
    for region in r141['regions']:
        host = region_host(r141, region); root = campaign_path(r141, r144, region)
        completed_path = root / 'closeout/completed_evidence.json'
        completed_bytes = reader.bytes(host, completed_path); completed = json.loads(completed_bytes)
        terminal = reader.json(host, root / 'terminal.json')
        fold_bytes = reader.bytes(host, root / 'closeout/fold_comparison.csv')
        frame = pd.read_csv(io.BytesIO(fold_bytes))
        if completed.get('artifacts', {}).get('fold_comparison.csv') != digest(fold_bytes):
            raise RuntimeError('regional fold table does not match its seal: ' + region)
        if region in r141['reuse_regions']:
            expected = r141['reuse_source']['regions'][region]['completed_evidence_sha256']
            if digest(completed_bytes) != expected:
                raise RuntimeError('reused R137 evidence hash differs for ' + region)
            if completed['metadata']['source']['head'] != r141['reuse_source']['head']:
                raise RuntimeError('reused R137 source differs for ' + region)
            if terminal.get('status') != 'R137_REGION_COMPLETE_NOT_PROMOTED':
                raise RuntimeError('reused R137 terminal differs for ' + region)
            source_class = 'R137_reused_exactly'
        elif region == r144['region']:
            source = completed['metadata']['source']
            if (terminal.get('status') != 'R144_CZ_FALLBACK_COMPLETE_NOT_PROMOTED'
                    or terminal.get('source') != source or source != identity):
                raise RuntimeError('R144 CZ terminal/source identity differs')
            source_class = 'R144_predetermined_training_only_fallback'
            r144_regions.append(region)
        else:
            source = completed['metadata']['source']
            if (terminal.get('status') != 'R141_REGION_COMPLETE_NOT_PROMOTED'
                    or terminal.get('source') != source or source.get('head') != r144['source_head']):
                raise RuntimeError('R141 regional terminal/source differs for ' + region)
            source_class = 'R141_recovered_or_new_region'
            r141_regions.append(region)
        required = {'region', 'fold', 'operator', 'AQL', 'qdesn_AQL', 'pricefm_AQL',
                    'operational_pricefm_AQL'}
        if not required.issubset(frame.columns) or set(frame.region) != {region}:
            raise RuntimeError('malformed regional fold table for ' + region)
        if len(frame) != 12 or set(frame.operator) != {
                'cdf_pool_clipped', 'mean_feature', 'path_specific', 'normal_driver'}:
            raise RuntimeError('regional operator surface is incomplete for ' + region)
        primary = frame[frame.operator.eq(r141['primary_quantile_operator'])].copy()
        if len(primary) != 3 or set(primary.fold) != {1, 2, 3}:
            raise RuntimeError('three-fold primary comparison is incomplete for ' + region)
        primary['evidence_host'] = host; primary['source_class'] = source_class
        frames.append(primary)
        provenance.append({'region': region, 'host': host, 'source_class': source_class,
                           'campaign': str(root), 'source': completed['metadata']['source'],
                           'completed_evidence_sha256': digest(completed_bytes)})
    if len(r141_regions) != 33 or r144_regions != ['CZ']:
        raise RuntimeError('expected exactly 33 R141 regions and one R144 CZ region')
    folds = pd.concat(frames, ignore_index=True).sort_values(['region', 'fold'])
    if len(folds) != 114 or folds[['region', 'fold']].duplicated().any():
        raise RuntimeError('expected exactly 38 regions by three unique folds')
    regions = folds.groupby('region', as_index=False).mean(numeric_only=True)
    summary = {
        'status': 'R144_ALL_REGION_COMPLETE_NOT_PROMOTED', 'regions': 38, 'folds': 114,
        'r137_reused_regions': 4, 'r141_regions': 33, 'r144_fallback_regions': 1,
        'r141_source_head': r144['source_head'], 'r144_source_head': identity['head'],
        'primary_operator': r141['primary_quantile_operator'],
        'equal_region_fold_AQL': float(folds.AQL.mean()),
        'current_authority_AQL': float(folds.qdesn_AQL.mean()),
        'local_pricefm_AQL': float(folds.pricefm_AQL.mean()),
        'operational_pricefm_AQL': float(folds.operational_pricefm_AQL.mean()),
        'relative_change_vs_current_authority': float(folds.AQL.mean() / folds.qdesn_AQL.mean() - 1),
        'authority_mutated': False, 'article_mutated': False, 'promotion_decided': False,
    }
    return folds, regions, provenance, summary


def closeout(output, jerez_host):
    r141 = json.loads(R141_CONFIG.read_text()); r144 = json.loads(R144_CONFIG.read_text())
    identity = source_identity(); reader = EvidenceReader(jerez_host)
    ready = readiness(r141, r144, reader)
    if ready['pending']:
        raise RuntimeError('regional evidence is incomplete: ' + ','.join(ready['pending']))
    folds, regions, provenance, summary = collect(r141, r144, reader, identity)
    output.mkdir(parents=True, exist_ok=True)
    values = {
        'fold_comparison.csv': folds.to_csv(index=False).encode(),
        'region_comparison.csv': regions.to_csv(index=False).encode(),
        'provenance.json': (json.dumps(provenance, indent=2, sort_keys=True) + '\n').encode(),
        'summary.json': (json.dumps(summary, indent=2, sort_keys=True) + '\n').encode(),
    }
    for name, value in values.items():
        atomic(output / name, value)
    manifest = {'status': summary['status'], 'source': identity,
                'artifacts': {name: digest(value) for name, value in values.items()}}
    atomic(output / 'completed_evidence.json',
           (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode())
    return summary


def wait_closeout(output, runtime, jerez_host, poll_seconds):
    r141 = json.loads(R141_CONFIG.read_text()); r144 = json.loads(R144_CONFIG.read_text())
    identity = source_identity(); reader = EvidenceReader(jerez_host)
    runtime.mkdir(parents=True, exist_ok=True)
    with (runtime / 'supervisor.lock').open('a') as lock:
        fcntl = __import__('fcntl'); fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        while True:
            state = readiness(r141, r144, reader)
            state.update(status='R144_GLOBAL_CLOSEOUT_WAITING' if state['pending'] else 'R144_GLOBAL_CLOSEOUT_STARTING',
                         source=identity, epoch=time.time())
            atomic(runtime / 'progress.json', (json.dumps(state, indent=2, sort_keys=True) + '\n').encode())
            if not state['pending']:
                break
            time.sleep(poll_seconds)
        summary = closeout(output, jerez_host)
        atomic(runtime / 'terminal.json', (json.dumps(summary, indent=2, sort_keys=True) + '\n').encode())
        return summary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('status', 'closeout', 'wait'))
    parser.add_argument('--output', type=Path,
        default=DATA / 'runtime_audits/pricefm_stage_r144_cz_training_fallback_20261020/closeout')
    parser.add_argument('--runtime', type=Path,
        default=DATA / 'launch_prep/pricefm_stage_r144_cz_training_fallback_20261020/muscat_closeout')
    parser.add_argument('--jerez-host', default='jerez')
    parser.add_argument('--poll-seconds', type=int, default=60)
    arguments = parser.parse_args()
    if arguments.action == 'status':
        value = readiness(json.loads(R141_CONFIG.read_text()), json.loads(R144_CONFIG.read_text()),
                          EvidenceReader(arguments.jerez_host))
    elif arguments.action == 'closeout':
        value = closeout(arguments.output, arguments.jerez_host)
    else:
        value = wait_closeout(arguments.output, arguments.runtime, arguments.jerez_host,
                              arguments.poll_seconds)
    print(json.dumps(value, indent=2, sort_keys=True), flush=True)
