#!/usr/bin/env python3
"""Run staged PriceFM data-pipeline commands."""

from __future__ import print_function

import subprocess
import sys
from pathlib import Path

from pricefm_common import parse_bool, parser


STAGE_TO_SCRIPT = {
    "download": "00_download_pricefm.py",
    "convert": "01_convert_raw_to_parquet.py",
    "audit": "02_audit_pricefm.py",
    "splits": "03_make_splits.py",
    "scalers": "04_fit_scalers.py",
    "windows": "05_build_windows.py",
    "eda_figures": "06_make_region_feature_figures.py",
}

ORDER = ["download", "convert", "audit", "splits", "scalers", "windows"]


def main():
    p = parser(__doc__)
    p.add_argument("--stage", default="all", choices=["all", "eda_figures"] + ORDER)
    p.add_argument("--pilot-only", type=parse_bool, default=True)
    args = p.parse_args()

    script_dir = Path(__file__).resolve().parent
    stages = ORDER if args.stage == "all" else [args.stage]
    for stage in stages:
        cmd = [
            sys.executable,
            str(script_dir / STAGE_TO_SCRIPT[stage]),
            "--config",
            args.config,
            "--force",
            str(args.force).lower(),
        ]
        if stage == "windows":
            cmd.extend(["--pilot-only", str(args.pilot_only).lower()])
        print("Running:", " ".join(cmd), flush=True)
        subprocess.check_call(cmd)


if __name__ == "__main__":
    main()
