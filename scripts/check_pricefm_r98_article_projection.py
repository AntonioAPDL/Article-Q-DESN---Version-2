#!/usr/bin/env python3.11
"""Verify frozen PriceFM authority and its effective reader-facing projection.

Historical source IDs and original asset hashes remain unchanged. Descriptive
display derivatives are verified separately; no models are fitted or scored.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
PRESENTATION_CHECKER = "scripts/check_qdesn_sections5_7_presentation.py"
PRESENTATION_MANIFEST = "tables/qdesn_sections5_7_presentation_manifest.json"
PRESENTATION_OVERRIDE = "tables/qdesn_sections5_7_supp_display_overrides.tex"
CURRENT_REGION_FIGURE = "figures/pricefm_application/pricefm_regional_aql_editorial_20261013.pdf"
CURRENT_GLOBAL_TABLE = "tables/pricefm_regional_comparison_display.tex"
FROZEN_PROJECTION_MANIFEST_SHA256 = "1d6ea4f4f5d73617f45e9ca02940114a95d140debdf4c884b1a261999fee89c5"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def presentation_checker(root: Path):
    path = root / PRESENTATION_CHECKER
    require(path.is_file(), "bounded presentation checker is missing")
    spec = importlib.util.spec_from_file_location("pricefm_editorial_presentation_checker", path)
    require(spec is not None and spec.loader is not None, "cannot load presentation checker")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def check(root: Path = ROOT) -> dict[str, int]:
    root = root.resolve()
    manifest_path = root / "tables/pricefm_r98_article_projection_manifest.json"
    require(digest(manifest_path) == FROZEN_PROJECTION_MANIFEST_SHA256,
            "original PriceFM projection manifest changed")
    manifest = json.loads(manifest_path.read_text())
    require(manifest["stage"] == "R98", "article authority is not R98")
    require(manifest["registry_rows"] == 114, "R98 registry row count changed")
    require(manifest["source_manifest_entries_verified"] == 308,
            "source-manifest verification count changed")
    require(manifest["authority_rule"] ==
            "complete_114_case_replacement_without_R92_fallback",
            "R98 authority rule changed")

    # Authenticate original scientific assets, including originals no longer
    # selected for upload. A new display does not change their source identity.
    for row in manifest["outputs"]:
        path = root / row["path"]
        require(path.is_file(), f"article output is absent: {row['path']}")
        require(path.stat().st_size == row["bytes"], f"output size changed: {row['path']}")
        require(digest(path) == row["sha256"], f"output hash changed: {row['path']}")

    registry_path = root / "tables/pricefm_r98_authoritative_registry.csv"
    with registry_path.open(newline="", encoding="utf-8") as stream:
        registry = list(csv.DictReader(stream))
    require(len(registry) == 114, "tracked R98 registry does not contain 114 rows")
    require(len({row["region"] for row in registry}) == 38, "tracked R98 regions changed")
    require(sum(float(row["qdesn_AQL"]) < float(row["pricefm_AQL"])
                for row in registry) == 54, "tracked R98 win count changed")
    require(sum(float(row["qdesn_AQL"]) > float(row["pricefm_AQL"])
                for row in registry) == 60, "tracked PriceFM win count changed")
    require(all(row["R92_case_fallback_used"] == "False" for row in registry),
            "tracked R98 registry contains an R92 fallback")
    require(all(row["selection_is_validation_only"] == "True" and
                row["test_driven_case_mixing_used"] == "False" for row in registry),
            "tracked R98 selection boundaries changed")
    require(math.isclose(sum(float(row["qdesn_AQL"]) for row in registry) / 114,
                         7.217007319836696, rel_tol=0, abs_tol=1e-12) and
            math.isclose(sum(float(row["pricefm_AQL"]) for row in registry) / 114,
                         7.038685346534470, rel_tol=0, abs_tol=1e-12),
            "primary PriceFM/Q-DESN numerical means changed")

    main = (root / "main.tex").read_text()
    supplement = (root / "qdesn-supplement.tex").read_text()
    aliases = (root / "tables/pricefm_full_current_outputs.tex").read_text()
    combined = main + "\n" + supplement + "\n" + aliases
    for forbidden in (
        "PricefmSelection", "pricefm_r91_selective_promotions",
        "tables/pricefm_full_horizon_diagnostic_summary.tex",
        "validation-selected specification in the 12 cases",
    ):
        require(forbidden not in combined, f"deprecated reader-facing term remains: {forbidden}")
    for required in ("7.217", "7.039", "+0.178", "historical sensitivity", "54", "60"):
        require(required in combined, f"required R98 numerical/scope disclosure is absent: {required}")
    pricefm = main.split(r"\label{sec:pricefm-application}", 1)
    require(len(pricefm) == 2, "main PriceFM section identity is missing")
    pricefm = re.split(r"\\section\{", pricefm[1], maxsplit=1)[0]
    pricefm = re.sub(r"\s+", " ", pricefm)
    require("training and validation" in pricefm and "held fixed" in pricefm,
            "PriceFM regional specifications must be selected before assessment and held fixed")
    require("higher" in pricefm and ("aggregate" in pricefm or "mean AQL" in pricefm),
            "the higher Q-DESN aggregate loss must remain explicit")
    require(r"\input{tables/pricefm_r98_main_aql_summary.tex}" in main,
            "main article does not use the R98 table")
    require(r"\PricefmCurrentRegionFigure" in supplement,
            "supplement does not use the current region figure")

    try:
        presentation_checker(root).check(root)
    except AssertionError as error:
        raise RuntimeError(str(error)) from error
    require(r"\input{" + PRESENTATION_OVERRIDE + "}" in supplement,
            "supplement does not select the descriptive presentation override")

    article_files = (root / "overleaf/article_files.txt").read_text().splitlines()
    required_article_files = {
        CURRENT_REGION_FIGURE, CURRENT_GLOBAL_TABLE, PRESENTATION_MANIFEST,
        PRESENTATION_OVERRIDE, "tables/pricefm_full_current_outputs.tex",
        "tables/pricefm_r98_article_projection_manifest.json",
        "tables/pricefm_r98_fold_comparison.csv",
        "tables/pricefm_r98_global_comparison.csv",
        "tables/pricefm_r98_main_aql_summary.tex",
        "tables/pricefm_r98_region_comparison.csv",
    }
    require(required_article_files.issubset(set(article_files)),
            "article-only manifest omits a verified current PriceFM publication dependency")
    # Original artifacts stay in Git and authenticated above, not selected for
    # upload simply because the scientific projection receipt names them.
    superseded_display = {
        "figures/pricefm_application/pricefm_r98_region_aql_comparison.pdf",
        "figures/pricefm_application/pricefm_r98_region_aql_comparison.png",
        "tables/pricefm_r98_global_aql_comparison.tex",
    }
    require(superseded_display.isdisjoint(article_files),
            "article-only manifest retains superseded internal-label PriceFM displays")
    git_only_provenance = {
        "tables/pricefm_r98_authoritative_registry.csv",
        "tables/pricefm_r98_authority_transition_ledger.csv",
    }
    require(git_only_provenance.isdisjoint(article_files),
            "article-only manifest exposes local-path PriceFM provenance")
    require(not any("pricefm_r91_selective" in row for row in article_files),
            "article-only manifest retains an R91 selective-promotion asset")
    require(not any("pricefm_full_horizon" in row for row in article_files),
            "article-only manifest retains the incomplete R92 horizon asset")
    return {"rows": 114, "regions": 38, "outputs": len(manifest["outputs"])}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        result = check(args.repo_root)
    except (RuntimeError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"PRICEFM_R98_ARTICLE_CHECK=FAIL {error}", file=sys.stderr)
        return 1
    print("PRICEFM_R98_ARTICLE_CHECK=PASS " +
          " ".join(f"{name}={value}" for name, value in result.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
