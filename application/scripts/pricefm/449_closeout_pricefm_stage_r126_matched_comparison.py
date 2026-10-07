#!/usr/bin/env python3
"""Automatic bounded Jerez return and Muscat reference comparison, no promotion."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shlex
import subprocess
import tarfile
import time

for key in ('OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS', 'TF_NUM_INTRAOP_THREADS', 'TF_NUM_INTEROP_THREADS'):
    os.environ[key] = '1'

from pricefm_r126_contract import digest, read, write, immutable, verified
from pricefm_r126_compare import compare

ROOT = Path(__file__).resolve().parents[3]
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
TAG = 'pricefm_stage_r126_matched_comparison_20261007'
OUT = DATA / 'campaigns' / TAG
REMOTE_ROOT = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__pricefm_r126_matched_comparison_20261007')
SSH = ['ssh', '-F', '/home/jaguir26/.ssh/config', '-o', 'BatchMode=yes', 'jerez']
PYTHON = DATA / 'venv/bin/python'


def export():
    terminal = read(OUT / 'terminal.json')
    if terminal['status'] != 'R126_FULL_FITS_AND_OFFICIAL_FORECASTS_COMPLETE':
        raise RuntimeError('complete campaign required for export')
    names = ['terminal.json', 'frozen_choice.json', 'internal_selection_metrics.csv', 'allocation.json', 'timing.json']
    for fold in (1, 2, 3):
        verified(OUT / 'official' / f'fold={fold}')
        names += [str(p.relative_to(OUT)) for p in (OUT / 'official' / f'fold={fold}').glob('*') if p.is_file()]
        verified(OUT / 'full' / f'fold={fold}/design')
        names += [f'full/fold={fold}/design/' + n for n in ('training.json', 'scalers.json', 'design.json')]
        for folder in [OUT / 'full' / f'fold={fold}/normal', *(OUT / 'full' / f'fold={fold}/al').glob('tau=*')]:
            verified(folder)
            names += [str(p.relative_to(OUT)) for p in folder.glob('*') if p.suffix in ('.json', '.csv')]
    manifest = {n: digest(OUT / n) for n in names}
    immutable(OUT / 'return_manifest.json', dict(artifacts=manifest, source=terminal['source'], heavy_fits_retained_on_jerez=True))
    archive = OUT / 'comparison_return.tar.gz'
    if not archive.exists():
        with tarfile.open(archive, 'w:gz') as stream:
            for name in [*names, 'return_manifest.json']: stream.add(OUT / name, arcname=name, recursive=False)
    return dict(archive=str(archive), sha256=digest(archive), files=len(names))


def wait_and_compare():
    destination = DATA / 'runtime_audits' / TAG
    destination.mkdir(parents=True, exist_ok=True)
    remote = REMOTE_ROOT / 'application/scripts/pricefm/449_closeout_pricefm_stage_r126_matched_comparison.py'
    while True:
        probe = f"import pathlib,json; p=pathlib.Path({str(OUT)!r}); print(json.dumps({{'done':(p/'terminal.json').exists(),'blocked':(p/'blocked.json').exists()}}))"
        try:
            result = subprocess.check_output([*SSH, shlex.join([str(PYTHON), '-B', '-c', probe])], text=True)
            import json
            status = json.loads(result)
        except subprocess.CalledProcessError as error:
            write(destination / 'watch_status.json', dict(status='temporary_connection_failure', error=str(error), epoch=time.time()))
            time.sleep(120); continue
        if status['blocked'] and not status['done']:
            write(destination / 'watch_status.json', dict(status='JEREZ_STAGE_BLOCKED_COMPARISON_WITHHELD', epoch=time.time()))
            return
        if status['done']: break
        write(destination / 'watch_status.json', dict(status='WAITING_FOR_FROZEN_FULL_FITS', epoch=time.time()))
        time.sleep(120)
    result = subprocess.check_output([*SSH, shlex.join([str(PYTHON), '-B', str(remote), 'export'])], text=True)
    import json
    receipt = json.loads(result)
    archive = destination / 'comparison_return.tar.gz'
    if not archive.exists():
        subprocess.run(['scp', '-F', '/home/jaguir26/.ssh/config', '-o', 'BatchMode=yes',
                        'jerez:' + receipt['archive'], str(archive)], check=True)
    if digest(archive) != receipt['sha256']: raise RuntimeError('return archive hash differs')
    mirror = destination / 'jerez_return'
    if not mirror.exists():
        mirror.mkdir()
        with tarfile.open(archive, 'r:gz') as stream:
            members = stream.getmembers()
            if any(not m.isfile() or Path(m.name).is_absolute() or '..' in Path(m.name).parts for m in members):
                raise RuntimeError('unsafe return archive members')
            stream.extractall(mirror, filter='data')
    manifest = read(mirror / 'return_manifest.json')
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if manifest['source']['head'] != head: raise RuntimeError('returned scientific source differs')
    for name, sha in manifest['artifacts'].items():
        if digest(mirror / name) != sha: raise RuntimeError('returned artifact differs')
    immutable(destination / 'return_receipt.json', receipt)
    protocol = read(ROOT / 'application/config/pricefm_stage_r126_matched_comparison_protocol_20261007.json')
    result = compare(DATA, ROOT, mirror, destination / 'comparison', protocol)
    write(destination / 'watch_status.json', dict(status='MATCHED_COMPARISON_COMPLETE', decision=result, epoch=time.time()))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__); p.add_argument('mode', choices=['export', 'watch'])
    args = p.parse_args()
    if args.mode == 'export':
        import json
        print(json.dumps(export()), flush=True)
    else:
        import fcntl
        directory = DATA / 'runtime_audits' / TAG
        directory.mkdir(parents=True, exist_ok=True)
        with (directory / 'watcher.lock').open('a+') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            try: wait_and_compare()
            except Exception as error:
                write(directory / 'comparison_blocked.json', dict(error=str(error), epoch=time.time()))
                raise
