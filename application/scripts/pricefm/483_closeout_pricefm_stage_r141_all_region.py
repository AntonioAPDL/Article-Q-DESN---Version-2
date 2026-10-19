#!/usr/bin/env python3
"""Aggregate frozen R137 reuse evidence and all completed R141 regions."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess

import pandas as pd

ROOT = Path(__file__).resolve().parents[3]
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
CONFIG = ROOT / 'application/config/pricefm_stage_r141_recovery_rollout_20261019.json'


def digest(value):
    return hashlib.sha256(value).hexdigest()


def atomic(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_bytes(value); temporary.replace(path)


class EvidenceReader:
    def __init__(self, jerez_host='jerez'):
        self.jerez_host = jerez_host

    def bytes(self, host, path):
        if host == 'muscat':
            return Path(path).read_bytes()
        if host != 'jerez':
            raise ValueError('unexpected evidence host: ' + host)
        return subprocess.check_output(['ssh', self.jerez_host, 'cat', str(path)])

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
        raise RuntimeError('region does not have one host: ' + region)
    return matches[0]


def campaign_path(config, region):
    tag = config['reuse_source']['tag'] if region in config['reuse_regions'] else config['tag']
    return DATA / 'campaigns' / (tag + '__' + region)


def collect(config, reader):
    frames = []; provenance = []; r141_heads = set()
    for region in config['regions']:
        host = region_host(config, region); root = campaign_path(config, region)
        completed_path = root / 'closeout/completed_evidence.json'
        completed_bytes = reader.bytes(host, completed_path)
        completed = json.loads(completed_bytes)
        terminal = reader.json(host, root / 'terminal.json')
        frame = reader.csv(host, root / 'closeout/fold_comparison.csv')
        if region in config['reuse_regions']:
            expected = config['reuse_source']['regions'][region]['completed_evidence_sha256']
            if digest(completed_bytes) != expected:
                raise RuntimeError('reused R137 evidence hash differs for ' + region)
            if completed['metadata']['source']['head'] != config['reuse_source']['head']:
                raise RuntimeError('reused R137 source differs for ' + region)
            if terminal.get('status') != 'R137_REGION_COMPLETE_NOT_PROMOTED':
                raise RuntimeError('reused R137 terminal differs for ' + region)
            source_class = 'R137_reused_exactly'
        else:
            head = completed['metadata']['source']['head']; r141_heads.add(head)
            if terminal.get('status') != 'R141_REGION_COMPLETE_NOT_PROMOTED':
                raise RuntimeError('R141 terminal differs for ' + region)
            if terminal.get('source', {}).get('head') != head:
                raise RuntimeError('R141 terminal/source mismatch for ' + region)
            source_class = 'R141_recovered_or_new_region'
        required = {'region', 'fold', 'operator', 'AQL', 'qdesn_AQL', 'pricefm_AQL',
                    'operational_pricefm_AQL'}
        if not required.issubset(frame.columns) or set(frame.region) != {region}:
            raise RuntimeError('malformed regional fold table for ' + region)
        if len(frame) != 12 or set(frame['operator']) != {
                'cdf_pool_clipped', 'mean_feature', 'path_specific', 'normal_driver'}:
            raise RuntimeError('regional operator surface is incomplete for ' + region)
        primary = frame[frame.operator.eq(config['primary_quantile_operator'])].copy()
        if len(primary) != 3 or set(primary.fold) != {1, 2, 3}:
            raise RuntimeError('three-fold primary comparison is incomplete for ' + region)
        primary['evidence_host'] = host; primary['source_class'] = source_class
        frames.append(primary)
        provenance.append({'region': region, 'host': host, 'source_class': source_class,
                           'campaign': str(root), 'source': completed['metadata']['source'],
                           'completed_evidence_sha256': digest(completed_bytes)})
    if len(r141_heads) != 1:
        raise RuntimeError('all 34 new regions must share one R141 source HEAD')
    folds = pd.concat(frames, ignore_index=True).sort_values(['region', 'fold'])
    if len(folds) != 114:
        raise RuntimeError('expected exactly 38 regions by three folds')
    regions = folds.groupby('region', as_index=False).mean(numeric_only=True)
    summary = {
        'status': 'R141_ALL_REGION_COMPLETE_NOT_PROMOTED',
        'regions': 38,
        'folds': 114,
        'new_regions': 34,
        'reused_regions': 4,
        'r141_source_head': next(iter(r141_heads)),
        'primary_operator': config['primary_quantile_operator'],
        'equal_region_fold_AQL': float(folds.AQL.mean()),
        'current_authority_AQL': float(folds.qdesn_AQL.mean()),
        'local_pricefm_AQL': float(folds.pricefm_AQL.mean()),
        'operational_pricefm_AQL': float(folds.operational_pricefm_AQL.mean()),
        'relative_change_vs_current_authority': float(folds.AQL.mean() / folds.qdesn_AQL.mean() - 1),
        'authority_mutated': False,
        'article_mutated': False,
        'promotion_decided': False,
    }
    return folds, regions, provenance, summary


def main(output, jerez_host):
    config = json.loads(CONFIG.read_text())
    folds, regions, provenance, summary = collect(config, EvidenceReader(jerez_host))
    output.mkdir(parents=True, exist_ok=True)
    fold_bytes = folds.to_csv(index=False).encode()
    region_bytes = regions.to_csv(index=False).encode()
    provenance_bytes = (json.dumps(provenance, indent=2, sort_keys=True) + '\n').encode()
    summary_bytes = (json.dumps(summary, indent=2, sort_keys=True) + '\n').encode()
    atomic(output / 'fold_comparison.csv', fold_bytes)
    atomic(output / 'region_comparison.csv', region_bytes)
    atomic(output / 'provenance.json', provenance_bytes)
    atomic(output / 'summary.json', summary_bytes)
    manifest = {'status': summary['status'], 'artifacts': {
        'fold_comparison.csv': digest(fold_bytes), 'region_comparison.csv': digest(region_bytes),
        'provenance.json': digest(provenance_bytes), 'summary.json': digest(summary_bytes)}}
    atomic(output / 'completed_evidence.json',
           (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode())
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path,
        default=DATA / 'runtime_audits/pricefm_stage_r141_recovery_rollout_20261019/closeout')
    parser.add_argument('--jerez-host', default='jerez')
    args = parser.parse_args(); main(args.output, args.jerez_host)
