#!/usr/bin/env python3
"""Verify the tracked PriceFM R98 article authority and reader-facing text."""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


manifest_path = ROOT / "tables/pricefm_r98_article_projection_manifest.json"
manifest = json.loads(manifest_path.read_text())
require(manifest["stage"] == "R98", "article authority is not R98")
require(manifest["registry_rows"] == 114, "R98 registry row count changed")
require(manifest["source_manifest_entries_verified"] == 308,
        "source-manifest verification count changed")
require(manifest["authority_rule"] ==
        "complete_114_case_replacement_without_R92_fallback",
        "R98 authority rule changed")

for row in manifest["outputs"]:
    path = ROOT / row["path"]
    require(path.is_file(), f"article output is absent: {row['path']}")
    require(path.stat().st_size == row["bytes"], f"output size changed: {row['path']}")
    require(digest(path) == row["sha256"], f"output hash changed: {row['path']}")

registry_path = ROOT / "tables/pricefm_r98_authoritative_registry.csv"
with registry_path.open(newline="", encoding="utf-8") as stream:
    registry = list(csv.DictReader(stream))
require(len(registry) == 114, "tracked R98 registry does not contain 114 rows")
require(len({row["region"] for row in registry}) == 38, "tracked R98 regions changed")
require(sum(float(row["qdesn_AQL"]) < float(row["pricefm_AQL"])
            for row in registry) == 54, "tracked R98 win count changed")
require(all(row["R92_case_fallback_used"] == "False" for row in registry),
        "tracked R98 registry contains an R92 fallback")

main = (ROOT / "main.tex").read_text()
supplement = (ROOT / "qdesn-supplement.tex").read_text()
aliases = (ROOT / "tables/pricefm_full_current_outputs.tex").read_text()
combined = main + "\n" + supplement + "\n" + aliases
for forbidden in (
    "PricefmSelection", "pricefm_r91_selective_promotions",
    "tables/pricefm_full_horizon_diagnostic_summary.tex",
    "validation-selected specification in the 12 cases",
):
    require(forbidden not in combined, f"deprecated reader-facing term remains: {forbidden}")
for required in (
    "prospectively frozen", "7.217", "7.039", "+0.178",
    "historical sensitivity", "54", "60",
):
    require(required in combined, f"required R98 disclosure is absent: {required}")
require("\\input{tables/pricefm_r98_main_aql_summary.tex}" in main,
        "main article does not use the R98 table")
require("\\PricefmCurrentRegionFigure" in supplement,
        "supplement does not use the R98 region figure")

article_files = (ROOT / "overleaf/article_files.txt").read_text().splitlines()
required_article_files = {
    "figures/pricefm_application/pricefm_r98_region_aql_comparison.pdf",
    "tables/pricefm_full_current_outputs.tex",
    "tables/pricefm_r98_article_projection_manifest.json",
    "tables/pricefm_r98_authoritative_registry.csv",
    "tables/pricefm_r98_authority_transition_ledger.csv",
    "tables/pricefm_r98_fold_comparison.csv",
    "tables/pricefm_r98_global_aql_comparison.tex",
    "tables/pricefm_r98_global_comparison.csv",
    "tables/pricefm_r98_main_aql_summary.tex",
    "tables/pricefm_r98_region_comparison.csv",
}
require(required_article_files.issubset(set(article_files)),
        "article-only manifest omits an R98 authority file")
require(not any("pricefm_r91_selective" in row for row in article_files),
        "article-only manifest retains an R91 selective-promotion asset")
require(not any("pricefm_full_horizon" in row for row in article_files),
        "article-only manifest retains the incomplete R92 horizon asset")

print("PRICEFM_R98_ARTICLE_CHECK=PASS rows=114 regions=38 outputs="
      f"{len(manifest['outputs'])}")
