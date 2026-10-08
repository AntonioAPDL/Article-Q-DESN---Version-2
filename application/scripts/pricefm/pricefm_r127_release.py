#!/usr/bin/env python3
"""Inherited source-matched Python/R regressions plus R127 diagnostic tests."""
import argparse
import json
from pathlib import Path

import pricefm_r126_release as parent
from pricefm_r126_contract import digest, write

parent.release.ROOT = Path(__file__).resolve().parents[3]
parent.release.TAG = 'pricefm_stage_r127_driver_diagnosis_20261008'
parent.release.PYTHON_TESTS = (*parent.release.PYTHON_TESTS, 'test_pricefm_stage_r127_driver_diagnosis.py')

if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('--output', type=Path, required=True)
    p.add_argument('--cpu', type=int, required=True); p.add_argument('--historical-plan', type=Path, required=True)
    args = p.parse_args()
    history = parent.historical_input(args.historical_plan)
    receipt = parent.release.run(args.output, args.cpu)
    receipt['evidence_sha256'][str(history)] = digest(history)
    receipt['historical_ignored_regression_input_sha256'] = parent.HISTORY_SHA256
    write(args.output / 'validation.json', receipt)
    print(json.dumps(receipt), flush=True)
