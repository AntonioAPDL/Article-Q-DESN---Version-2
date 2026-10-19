#!/usr/bin/env python3
"""Create a source-matched R141 release after parity and recovery tests."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

for name in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS', 'BLIS_NUM_THREADS'):
    os.environ[name] = '1'
os.environ['PYTHONDONTWRITEBYTECODE'] = '1'

ROOT = Path(__file__).resolve().parents[3]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dependency', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    branch = subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip()
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    dirty = subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()
    if not branch.startswith('work/pricefm-r141-') or dirty:
        raise RuntimeError('clean committed dedicated R141 source required before release')
    if subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=args.dependency, text=True).strip() != \
            '1e24342e1ecd2dd7a99d8df2445f29be7f7a03d2':
        raise RuntimeError('frozen R127 dependency differs')
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=args.dependency, text=True).strip():
        raise RuntimeError('frozen R127 dependency is dirty')
    args.output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, PRICEFM_R137_DEPENDENCY=str(args.dependency), PRICEFM_R137_REGION='SK',
               PRICEFM_R140_DEPENDENCY=str(args.dependency), PRICEFM_R140_REGION='AT',
               PRICEFM_R141_DEPENDENCY=str(args.dependency), PRICEFM_R141_REGION='AT')
    xml = args.output / 'pytest.xml'
    tests = [
        ROOT / 'application/tests/test_pricefm_stage_r137_four_region_pilot.py',
        ROOT / 'application/tests/test_pricefm_stage_r140_all_region_rollout.py',
        ROOT / 'application/tests/test_pricefm_stage_r141_recovery_rollout.py',
    ]
    proc = subprocess.run([sys.executable, '-B', '-m', 'pytest', '-q', '-p', 'no:cacheprovider',
        *map(str, tests), '--junitxml=' + str(xml)], env=env)
    suite = ET.parse(xml).getroot(); cases = list(suite.iter('testcase'))
    failures = sum(len(list(case.iter(tag))) for case in cases
                   for tag in ('failure', 'error', 'skipped'))
    files = [
        ROOT / 'application/config/pricefm_stage_r141_recovery_rollout_20261019.json',
        ROOT / 'application/scripts/pricefm/480_run_pricefm_stage_r141_region.py',
        ROOT / 'application/scripts/pricefm/481_release_pricefm_stage_r141.py',
        ROOT / 'application/scripts/pricefm/482_schedule_pricefm_stage_r141_host.py',
        ROOT / 'application/scripts/pricefm/483_closeout_pricefm_stage_r141_all_region.py',
        ROOT / 'application/tests/test_pricefm_stage_r141_recovery_rollout.py',
    ]
    receipt = {
        'source': {'branch': branch, 'head': head},
        'tests': len(cases),
        'failures': failures,
        'passed': proc.returncode == 0 and failures == 0 and len(cases) >= 45,
        'r137_parity_suite_included': True,
        'r140_regression_suite_included': True,
        'r141_design_to_al_boundary_test_included': True,
        'r141_recovery_import_test_included': True,
        'real_cran_AL_smoke_levels': [.5],
        'exact_al_max_iter': 300,
        'exact_cran_exdqlm': '1.1.1',
        'dependency': str(args.dependency),
        'source_sha256': {str(path): digest(path) for path in files},
    }
    (args.output / 'validation.json').write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
    print(json.dumps(receipt, indent=2), flush=True)
    if not receipt['passed']:
        sys.exit(1)
