#!/usr/bin/env python3
"""Inherited scientific regressions plus R126 gates, without model campaigns."""
import argparse
import json
from pathlib import Path
import pricefm_r124_release as release

ROOT = Path(__file__).resolve().parents[3]
release.ROOT = ROOT
release.TAG = 'pricefm_stage_r126_matched_comparison_20261007'
release.PYTHON_TESTS = (*release.PYTHON_TESTS,
    'test_pricefm_stage_r125_forecast_estimand.py', 'test_pricefm_stage_r126_matched_comparison.py')

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--output', type=Path, required=True); p.add_argument('--cpu', type=int, required=True)
    args = p.parse_args()
    print(json.dumps(release.run(args.output, args.cpu)), flush=True)
