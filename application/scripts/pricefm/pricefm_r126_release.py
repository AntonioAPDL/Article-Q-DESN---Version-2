#!/usr/bin/env python3
"""Inherited scientific regressions plus R126 gates, without model campaigns."""
import argparse
import json
from pathlib import Path
import shutil
import pricefm_r124_release as release
from pricefm_r126_contract import digest, write

ROOT = Path(__file__).resolve().parents[3]
release.ROOT = ROOT
release.TAG = 'pricefm_stage_r126_matched_comparison_20261007'
release.PYTHON_TESTS = (*release.PYTHON_TESTS,
    'test_pricefm_stage_r125_forecast_estimand.py', 'test_pricefm_stage_r126_matched_comparison.py')
HISTORY_SHA256 = '555619512f3e1eba08d43e1430ca17c8bd9ba76d64fb009d33827da6de699f03'
HISTORY_NAME = 'pricefm_stage_r120_explicit_lag_search_master_plan_20260925.md'


def historical_input(source):
    target = ROOT / 'local_trackers' / HISTORY_NAME
    if digest(source) != HISTORY_SHA256:
        raise ValueError('inherited regression plan input differs from frozen history')
    if target.exists():
        if digest(target) != HISTORY_SHA256: raise ValueError('existing historical plan must not be overwritten')
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    return target

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--output', type=Path, required=True); p.add_argument('--cpu', type=int, required=True)
    p.add_argument('--historical-plan', type=Path, required=True)
    args = p.parse_args()
    history = historical_input(args.historical_plan)
    receipt = release.run(args.output, args.cpu)
    receipt['evidence_sha256'][str(history)] = digest(history)
    receipt['historical_ignored_regression_input_sha256'] = HISTORY_SHA256
    write(args.output / 'validation.json', receipt)
    print(json.dumps(receipt), flush=True)
