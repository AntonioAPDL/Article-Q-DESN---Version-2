#!/usr/bin/env python3
"""Wait for both Jerez R137 partitions to finish, then exec the R138 controller."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import socket
import sys
import time


DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
ROOT = Path(__file__).resolve().parents[3]
ENTRY = ROOT / 'application/scripts/pricefm/471_run_pricefm_stage_r138_dk1_diverse_driver.py'
OUT = DATA / 'campaigns/pricefm_stage_r138_dk1_diverse_driver_20261016'
PYTHON = DATA / 'runtime_envs/r137_py311/bin/python'
R137_ENTRY = '469_run_pricefm_stage_r137_four_region_pilot.py'
R137_TAG = 'pricefm_stage_r137_four_region_pilot_20261015'


def atomic_write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + f'.tmp.{os.getpid()}')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    os.replace(temporary, path)


def live_r137_processes():
    found = []
    for path in Path('/proc').glob('[0-9]*/cmdline'):
        try:
            command = path.read_bytes().replace(b'\0', b' ').decode(errors='replace')
        except OSError:
            continue
        if R137_ENTRY in command and (' controller ' in command or ' worker ' in command):
            found.append(dict(pid=int(path.parent.name), command=command))
    return found


def completed_regions():
    result = {}
    for region in ('SK', 'IT_NORD'):
        path = DATA / 'campaigns' / f'{R137_TAG}__{region}' / 'terminal.json'
        if not path.is_file():
            result[region] = None
            continue
        value = json.loads(path.read_text())
        result[region] = value.get('status')
    return result


def main(poll_seconds):
    if socket.gethostname().split('.')[0] != 'jerez':
        raise RuntimeError('R138 release gate is restricted to Jerez')
    if not PYTHON.is_file() or not ENTRY.is_file():
        raise RuntimeError('R138 runtime or entrypoint is unavailable')
    while True:
        regions = completed_regions(); live = live_r137_processes()
        ready = all(value == 'R137_REGION_COMPLETE_NOT_PROMOTED' for value in regions.values()) and not live
        atomic_write(OUT / 'launch_gate.json', dict(status='ready' if ready else 'waiting_for_R137',
            regions=regions, live_r137_processes=live, host=socket.gethostname(), epoch=time.time(),
            intended_workers=30, intended_cpus=list(range(1, 31))))
        if ready:
            break
        time.sleep(poll_seconds)
    os.execv(str(PYTHON), [str(PYTHON), '-B', str(ENTRY), 'controller',
        '--workers', '30', '--cpus', ','.join(str(value) for value in range(1, 31))])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--poll-seconds', type=int, default=60)
    args = parser.parse_args()
    if args.poll_seconds < 10:
        raise ValueError('poll interval must be at least 10 seconds')
    main(args.poll_seconds)
