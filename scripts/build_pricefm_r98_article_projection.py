#!/usr/bin/env python3
"""Build the PriceFM R98 article projection from its frozen closeout.

The builder verifies the complete frozen source manifest before writing any
article asset.  It then copies the 114-row authority registry and the supplied
article-safe evidence without changing their bytes, and derives the compact
reader-facing summaries from that registry.  R92 enters only as a historical
sensitivity surface; no case-level fallback is permitted.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import shutil
import tempfile
from collections import Counter, defaultdict
from pathlib import Path


FROZEN_HASHES = {
    "pricefm_stage_r98_authoritative_registry.csv":
        "4cf8ff653c6bd7fc64a2992fbfb6e1df48867d1b7d840cd8544fb30a5c538cb6",
    "pricefm_stage_r98_authority_transition_ledger.csv":
        "35b0f3d55a1e5ac7e489b3cf171c0f9865e07a012e2fbb4a4674302fa5ef53cd",
    "pricefm_stage_r98_global_comparison.csv":
        "e3831615ceefe497d68f72176c4a68437448634868aed4c2fada5029ec2768b4",
    "source_manifest.csv":
        "98e5abd74b46988c1afa014455e8cf457929a6ecab3def39b3eeb74d89218dfa",
    "pricefm_stage_r98_article_asset_manifest.json":
        "707162b84816734a787408e244489e59fa17a27d7cdaab07ae7466994754d476",
}

ARTICLE_ASSET_HASHES = {
    "pricefm_stage_r98_global_aql_comparison.tex":
        "aed9fa10da6383d31f256c108d2530384ec57c275a54bc2d6f55754d287473a2",
    "pricefm_stage_r98_region_aql_comparison.png":
        "155ea1c9cd8efc834615e88cabad5fe5ba2ce9616b3536c8a8c24a63cc6a4181",
    "pricefm_stage_r98_region_aql_comparison.pdf":
        "870f43f594b86e607a93479568deb4943016bb201a870d2a8be9a3388e720413",
    "pricefm_stage_r98_global_comparison.csv":
        "e3831615ceefe497d68f72176c4a68437448634868aed4c2fada5029ec2768b4",
    "pricefm_stage_r98_region_comparison.csv":
        "b4ff02abf4cda266169acdba2c99708c4ff0b088891a2623256df00af99f21e1",
    "pricefm_stage_r98_fold_comparison.csv":
        "b43bb3e933aa6507f00d740ca82884f626b67e9cf3f5c16c953cb489b5032db8",
}

COPIED_OUTPUTS = {
    "pricefm_stage_r98_authoritative_registry.csv":
        "tables/pricefm_r98_authoritative_registry.csv",
    "pricefm_stage_r98_authority_transition_ledger.csv":
        "tables/pricefm_r98_authority_transition_ledger.csv",
    "pricefm_stage_r98_global_comparison.csv":
        "tables/pricefm_r98_global_comparison.csv",
    "pricefm_stage_r98_fold_comparison.csv":
        "tables/pricefm_r98_fold_comparison.csv",
    "pricefm_stage_r98_region_comparison.csv":
        "tables/pricefm_r98_region_comparison.csv",
    "pricefm_stage_r98_global_aql_comparison.tex":
        "tables/pricefm_r98_global_aql_comparison.tex",
    "pricefm_stage_r98_region_aql_comparison.pdf":
        "figures/pricefm_application/pricefm_r98_region_aql_comparison.pdf",
    "pricefm_stage_r98_region_aql_comparison.png":
        "figures/pricefm_application/pricefm_r98_region_aql_comparison.png",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def verify_named_hashes(root: Path) -> None:
    for name, expected in {**FROZEN_HASHES, **ARTICLE_ASSET_HASHES}.items():
        path = root / name
        require(path.is_file(), f"frozen file is absent: {path}")
        require(sha256(path) == expected, f"frozen hash changed: {name}")


def verify_source_manifest(root: Path) -> int:
    rows = read_csv(root / "source_manifest.csv")
    require(len(rows) == 308, "R98 source manifest must contain 308 entries")
    for row in rows:
        path = Path(row["path"])
        require(path.is_absolute(), f"source-manifest path is not absolute: {path}")
        require(path.is_file(), f"source-manifest file is absent: {path}")
        require(path.stat().st_size == int(row["bytes"]), f"source size changed: {path}")
        require(sha256(path) == row["sha256"], f"source hash changed: {path}")
    return len(rows)


def verify_registry(rows: list[dict[str, str]]) -> dict[str, object]:
    require(len(rows) == 114, "R98 registry must contain 114 rows")
    by_region: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        by_region[row["region"]].append(row)
    require(len(by_region) == 38, "R98 registry must contain 38 regions")
    require(all(sorted(int(x["fold"]) for x in group) == [1, 2, 3]
                for group in by_region.values()),
            "each R98 region must contain folds 1--3")

    fixed_fields = (
        "selected_family", "rhs_tau0", "lag_window", "depth", "units",
        "alpha", "rho", "input_scale", "feature_policy", "state_output",
    )
    for region, group in by_region.items():
        for field in fixed_fields:
            require(len({row[field] for row in group}) == 1,
                    f"{field} is not frozen across folds for {region}")

    require(all(row["selection_is_validation_only"] == "True" for row in rows),
            "R98 contains a non-validation-only selection")
    require(all(row["same_desn_tau0_all_folds_within_region"] == "True"
                for row in rows), "R98 changes DESN or tau0 within a region")
    require(all(row["same_likelihood_family_all_folds_within_region"] == "True"
                for row in rows), "R98 changes likelihood family within a region")
    require(all(row["test_driven_case_mixing_used"] == "False" for row in rows),
            "R98 contains test-driven case mixing")
    require(all(row["R92_case_fallback_used"] == "False" for row in rows),
            "R98 contains an R92 case-level fallback")
    require(all(row["selected_on_split"] ==
                "fold1_train_internal_temporal_validation_and_fold1_outer_validation"
                for row in rows), "R98 selection split changed")

    qdesn = [float(row["qdesn_AQL"]) for row in rows]
    pricefm = [float(row["pricefm_AQL"]) for row in rows]
    r92 = [float(row["deprecated_R92_AQL"]) for row in rows]
    delta = [q - p for q, p in zip(qdesn, pricefm)]
    require(all(math.isfinite(x) for x in qdesn + pricefm + r92),
            "R98 contains a non-finite AQL")
    require(math.isclose(sum(qdesn) / 114, 7.217007319836696,
                         rel_tol=0.0, abs_tol=1e-12), "R98 mean AQL changed")
    require(math.isclose(sum(pricefm) / 114, 7.038685346534470,
                         rel_tol=0.0, abs_tol=1e-12), "PriceFM mean AQL changed")
    require(math.isclose(sum(r92) / 114, 6.823677420470439,
                         rel_tol=0.0, abs_tol=1e-12), "historical R92 mean changed")
    require(sum(x < 0 for x in delta) == 54, "R98 case-level win count changed")
    require(sum(x > 0 for x in delta) == 60, "PriceFM case-level win count changed")

    region_means = []
    for region, group in by_region.items():
        q = sum(float(row["qdesn_AQL"]) for row in group) / 3
        p = sum(float(row["pricefm_AQL"]) for row in group) / 3
        region_means.append((region, q, p))
    require(sum(q < p for _, q, p in region_means) == 16,
            "R98 region-level win count changed")

    first_rows = [group[0] for group in by_region.values()]
    family_counts = Counter(row["selected_family"] for row in first_rows)
    require(family_counts == Counter({"al": 11, "exal": 27}),
            "R98 region-level likelihood-family counts changed")

    summaries = []
    for label, subset in [("Overall", rows)] + [
        (f"Fold {fold}", [row for row in rows if int(row["fold"]) == fold])
        for fold in (1, 2, 3)
    ]:
        q = [float(row["qdesn_AQL"]) for row in subset]
        p = [float(row["pricefm_AQL"]) for row in subset]
        d = sorted(a - b for a, b in zip(q, p))
        middle = len(d) // 2
        median = (d[middle - 1] + d[middle]) / 2
        summaries.append({
            "label": label,
            "n": len(subset),
            "qdesn_wins": sum(a < b for a, b in zip(q, p)),
            "pricefm_wins": sum(a > b for a, b in zip(q, p)),
            "qdesn_mean": sum(q) / len(q),
            "pricefm_mean": sum(p) / len(p),
            "delta_mean": sum(a - b for a, b in zip(q, p)) / len(q),
            "delta_median": median,
        })
    return {
        "summaries": summaries,
        "family_counts": dict(family_counts),
        "region_wins": 16,
        "region_losses": 22,
    }


def main_table(summaries: list[dict[str, object]]) -> str:
    lines = [
        r"\begingroup",
        r"\TableStyle",
        r"\scriptsize",
        r"\setlength{\tabcolsep}{3pt}",
        r"\begin{tabular}{@{}lrrrrrrr@{}}",
        r"\toprule",
        (r"Comparison set & $n$ & \shortstack{Q--DESN\\lower} & "
         r"\shortstack{PriceFM\\lower} & \shortstack{Mean\\Q--DESN AQL} & "
         r"\shortstack{Mean\\PriceFM AQL} & \shortstack{Mean\\$\Delta$} & "
         r"\shortstack{Median\\$\Delta$} \\"),
        r"\midrule",
    ]
    for row in summaries:
        lines.append(
            f"{row['label']} & {row['n']} & {row['qdesn_wins']} & "
            f"{row['pricefm_wins']} & {row['qdesn_mean']:.3f} & "
            f"{row['pricefm_mean']:.3f} & {row['delta_mean']:.3f} & "
            f"{row['delta_median']:.3f} \\\\"
        )
    lines.extend([r"\bottomrule", r"\end{tabular}", r"\endgroup", ""])
    return "\n".join(lines)


def aliases(summary: dict[str, object]) -> str:
    overall = summary["summaries"][0]
    return "\n".join([
        r"\newcommand{\PricefmFullRegionFolds}{114}",
        r"\newcommand{\PricefmFullRegions}{38}",
        r"\newcommand{\PricefmFullFolds}{3}",
        rf"\newcommand{{\PricefmFullQdesnWins}}{{{overall['qdesn_wins']}}}",
        rf"\newcommand{{\PricefmFullPricefmWins}}{{{overall['pricefm_wins']}}}",
        rf"\newcommand{{\PricefmFullQdesnWinRate}}{{{100 * overall['qdesn_wins'] / 114:.1f}\%}}",
        rf"\newcommand{{\PricefmCurrentRegionWins}}{{{summary['region_wins']}}}",
        rf"\newcommand{{\PricefmCurrentRegionLosses}}{{{summary['region_losses']}}}",
        rf"\newcommand{{\PricefmCurrentAlRegions}}{{{summary['family_counts']['al']}}}",
        rf"\newcommand{{\PricefmCurrentExalRegions}}{{{summary['family_counts']['exal']}}}",
        rf"\newcommand{{\PricefmFullMeanQdesnAql}}{{{overall['qdesn_mean']:.3f}}}",
        rf"\newcommand{{\PricefmFullMeanPricefmAql}}{{{overall['pricefm_mean']:.3f}}}",
        rf"\newcommand{{\PricefmFullMeanDeltaAql}}{{{overall['delta_mean']:+.3f}}}",
        rf"\newcommand{{\PricefmFullMedianDeltaAql}}{{{overall['delta_median']:+.3f}}}",
        r"\newcommand{\PricefmCurrentHistoricalAql}{6.824}",
        r"\newcommand{\PricefmFullPaperQuantiles}{0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90}",
        r"\newcommand{\PricefmCurrentMainSummaryTable}{tables/pricefm_r98_main_aql_summary.tex}",
        r"\newcommand{\PricefmCurrentGlobalComparisonTable}{tables/pricefm_r98_global_aql_comparison.tex}",
        r"\newcommand{\PricefmCurrentRegionFigure}{figures/pricefm_application/pricefm_r98_region_aql_comparison.pdf}",
        "",
    ])


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def output_record(repo_root: Path, path: Path) -> dict[str, object]:
    return {
        "path": path.relative_to(repo_root).as_posix(),
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
    }


def build(evidence_root: Path, repo_root: Path) -> dict[str, object]:
    verify_named_hashes(evidence_root)
    source_entries = verify_source_manifest(evidence_root)
    asset_manifest = json.loads(
        (evidence_root / "pricefm_stage_r98_article_asset_manifest.json").read_text()
    )
    require(asset_manifest["status"] == "article_safe_assets_ready_for_coordinator_not_published",
            "R98 article-asset status changed")
    require(asset_manifest["article_mutation_authorized"] is False,
            "source lane unexpectedly authorized article mutation")
    rows = read_csv(evidence_root / "pricefm_stage_r98_authoritative_registry.csv")
    summary = verify_registry(rows)

    output_relatives = list(COPIED_OUTPUTS.values()) + [
        "tables/pricefm_r98_main_aql_summary.tex",
        "tables/pricefm_full_current_outputs.tex",
    ]
    # Stage on the repository filesystem so that each final os.replace is an
    # atomic rename rather than a cross-device copy.
    with tempfile.TemporaryDirectory(
        prefix=".pricefm-r98-article-", dir=repo_root
    ) as temporary:
        stage = Path(temporary)
        for source_name, relative in COPIED_OUTPUTS.items():
            destination = stage / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(evidence_root / source_name, destination)
        write_text(stage / "tables/pricefm_r98_main_aql_summary.tex",
                   main_table(summary["summaries"]))
        write_text(stage / "tables/pricefm_full_current_outputs.tex", aliases(summary))

        for source_name, relative in COPIED_OUTPUTS.items():
            require(sha256(stage / relative) == sha256(evidence_root / source_name),
                    f"article-safe copy changed bytes: {relative}")
        for relative in output_relatives:
            destination = repo_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            os.replace(stage / relative, destination)

    outputs = [output_record(repo_root, repo_root / relative)
               for relative in output_relatives]
    manifest = {
        "schema_version": 1,
        "stage": "R98",
        "status": "authoritative_article_projection",
        "authority_rule": "complete_114_case_replacement_without_R92_fallback",
        "scientific_role": {
            "R98": "prospective_region_frozen_primary_comparison",
            "R92": "deprecated_historical_sensitivity_only",
        },
        "frozen_inputs": FROZEN_HASHES,
        "frozen_article_assets": ARTICLE_ASSET_HASHES,
        "source_manifest_entries_verified": source_entries,
        "registry_rows": 114,
        "regions": 38,
        "folds": 3,
        "qdesn_lower_cases": 54,
        "pricefm_lower_cases": 60,
        "qdesn_lower_region_means": 16,
        "mean_AQL": {
            "R98_QDESN": 7.217007319836696,
            "cached_PriceFM": 7.038685346534470,
            "deprecated_R92_QDESN": 6.823677420470439,
        },
        "outputs": outputs,
    }
    manifest_path = repo_root / "tables/pricefm_r98_article_projection_manifest.json"
    write_text(manifest_path, json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    manifest["manifest"] = output_record(repo_root, manifest_path)
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-root", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path,
                        default=Path(__file__).resolve().parents[1])
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    result = build(args.evidence_root.resolve(), args.repo_root.resolve())
    print(
        "PRICEFM_R98_ARTICLE_BUILD=PASS "
        f"registry_rows={result['registry_rows']} "
        f"source_manifest={result['source_manifest_entries_verified']} "
        f"outputs={len(result['outputs']) + 1}"
    )
