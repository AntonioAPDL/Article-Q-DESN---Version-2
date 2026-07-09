#!/usr/bin/env python3
"""Build the PriceFM stacked direct-horizon DESN adapter."""

from __future__ import print_function

from pricefm_common import parse_bool, parser, summarize, repo_path
from pricefm_desn_adapter import build_adapter


def main():
    p = parser(__doc__)
    p.add_argument("--smoke-config", default="application/config/pricefm_desn_model_smoke.yaml")
    args = p.parse_args()
    manifest = build_adapter(args.smoke_config, force=args.force)
    summarize(repo_path(manifest["smoke_config_path"]), manifest)


if __name__ == "__main__":
    main()
