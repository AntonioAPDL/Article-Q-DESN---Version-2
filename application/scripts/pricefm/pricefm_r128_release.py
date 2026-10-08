"""Source-matched launch-prep release with real compact CRAN AL smoke fits."""
import argparse
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

if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--dependency', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True); args = parser.parse_args()
    branch = subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip()
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if not branch.startswith('work/pricefm-r128-') or subprocess.check_output(
            ['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip():
        raise RuntimeError('clean committed source required before release')
    args.output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, PRICEFM_R128_DEPENDENCY=str(args.dependency))
    xml = args.output / 'pytest.xml'
    proc = subprocess.run([sys.executable, '-B', '-m', 'pytest', '-q', '-p', 'no:cacheprovider',
        str(ROOT / 'application/tests/test_pricefm_stage_r128_stochastic_pilots.py'), '--junitxml=' + str(xml)], env=env)
    suite = ET.parse(xml).getroot(); cases = list(suite.iter('testcase'))
    failures = sum(len(list(s.iter(tag))) for s in cases for tag in ('failure', 'error', 'skipped'))
    receipt = dict(source=dict(branch=branch, head=head), tests=len(cases), failures=failures,
        passed=proc.returncode == 0 and failures == 0 and len(cases) >= 20,
        real_cran_AL_smoke_levels=[.5, .45, .25], dependency=str(args.dependency))
    (args.output / 'validation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt), flush=True)
    if not receipt['passed']: sys.exit(1)
