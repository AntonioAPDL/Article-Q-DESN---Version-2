#!/usr/bin/env python3
"""Report-only R127 recovery: validate frozen forecasts, score exact raw truth."""
import argparse
from pathlib import Path
import subprocess

from pricefm_r126_contract import read, verify_hashes, digest, immutable, verified
from pricefm_r127_report import closeout

ROOT = Path(__file__).resolve().parents[3]
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
TAG = 'pricefm_stage_r127_driver_diagnosis_20261008'


def run(output):
    if not output.resolve().is_relative_to((DATA / 'runtime_audits' / TAG).resolve()):
        raise ValueError('new assigned report-only audit output required')
    branch = subprocess.check_output(['git','branch','--show-current'],cwd=ROOT,text=True).strip()
    if not branch.startswith('work/pricefm-r127-closeout-') or subprocess.check_output(['git','status','--porcelain'],cwd=ROOT):
        raise RuntimeError('clean committed closeout-only task branch required')
    source = dict(branch=branch,head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip())
    prep = read(DATA / 'launch_prep' / TAG / 'preparation.json')
    verify_hashes(prep['source_sha256']); verify_hashes(prep['input_sha256'])
    if digest(prep['release']) != prep['release_sha256']: raise RuntimeError('executed release changed')
    out = DATA / 'campaigns' / TAG
    expected = {t['name']:dict(t,source_head=prep['source']['head']) for t in prep['tasks']}
    actual = {p.stem:read(p) for p in (out/'tasks').glob('*.json')}
    if actual != expected: raise RuntimeError('executed schedule differs')
    for name in expected: verified(out/'tasks_done'/name)
    if output.exists() and not (output/'closeout_contract.json').exists():
        raise RuntimeError('partial unrelated output must not be overwritten')
    output.mkdir(parents=True,exist_ok=True)
    immutable(output/'closeout_contract.json',dict(scientific_source=prep['source'],report_source=source,
        source_sha256={str(p):digest(p) for p in [Path(__file__),Path(__file__).parent/'pricefm_r127_report.py']},
        executed_preparation_sha256=digest(DATA/'launch_prep'/TAG/'preparation.json'),
        no_new_fits=True,no_new_forecasts=True,original_blocked_receipt_preserved=True,
        scoring_correction='exact raw outcomes instead of inverse-scaled float32 stored outcomes'))
    return closeout(out,prep,report=output/'report',terminal=output/'terminal.json',report_source=source)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True)
    print(run(p.parse_args().output),flush=True)
