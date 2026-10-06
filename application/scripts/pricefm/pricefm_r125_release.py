#!/usr/bin/env python3
"""R125 regression plus unchanged R124/parent and pinned R release checks."""
import argparse
import json
from pathlib import Path

import pricefm_r124_release as RELEASE

ROOT = Path(__file__).resolve().parents[3]
TAG = 'pricefm_stage_r125_forecast_estimand_diagnosis_20261006'
RELEASE.ROOT = ROOT
RELEASE.TAG = TAG
RELEASE.PYTHON_TESTS = (*RELEASE.PYTHON_TESTS[:-1], 'test_pricefm_stage_r125_forecast_estimand.py', RELEASE.PYTHON_TESTS[-1])

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cpu', type=int, required=True)
    args = parser.parse_args()
    print(json.dumps(RELEASE.run(args.output, args.cpu)), flush=True)
