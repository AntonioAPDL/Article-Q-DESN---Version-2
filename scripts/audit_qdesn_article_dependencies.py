#!/usr/bin/env python3
"""Read-only inventory of the article allowlist and direct/alias TeX inputs.

Uses only the Python standard library. CSV is written to stdout, never to a
repository file. It does not compile, render, fit, score, or inspect fit payloads.
This is a bounded parser of this repository's literal file/alias conventions,
not a general TeX interpreter; final LaTeX recorder closure remains authoritative.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import re
import sys
from collections import defaultdict
from pathlib import Path


FIELDS = ("file", "role", "scientific_authority", "source_contract", "estimator_scope",
          "sha256", "source_inferred_consumers", "direct_or_alias_edges", "closure_status")
TOKEN = re.compile(
    r"\\(?:newcommand|renewcommand|providecommand)\s*\{\\(?P<name>[A-Za-z]+)\}\s*\{(?P<value>[^{}\n]+)\}"
    r"|\\(?P<kind>input|includegraphics|bibliography|bibliographystyle)"
    r"(?:\[[^\]\n]*\])?\s*\{(?P<target>[^{}\n]+)\}")


def uncomment(source: str) -> str:
    return "\n".join(re.split(r"(?<!\\)%", line, maxsplit=1)[0] for line in source.splitlines())


def classification(path: str) -> tuple[str, str, str, str]:
    suffix = Path(path).suffix
    if path in ("main.tex", "qdesn-supplement.tex"):
        return "manuscript", "current editorial source", "main.tex;qdesn-supplement.tex", "not a scientific estimator"
    if suffix in (".bib", ".bst"):
        return "bibliography database/style", "bibliographic and local presentation authority", "refs.bib;tables/qdesn_asa_compatible.bst", "not a scientific estimator; BST is not official journal software"
    if "quantile_initialization/" in path:
        return "initialization diagram component", "declared initialization protocol", "qdesn-supplement.tex:sec:supp_selection_initialization", "initial states distinct from separately declared prior calibration; study-specific branches"
    if path == "tables/qdesn_pro_review_presentation_manifest.json":
        return "presentation provenance companion", "independent v14, expanded pure-DESN and GloFAS Search III presentation derivatives", path, "unchanged scientific summaries; display regeneration only"
    if path == "tables/qdesn_article_presentation_manifest_v2.json":
        return "presentation provenance companion", "versioned Laplace replacement; independent v14 and GloFAS Search III displays unchanged", path, "forecast posterior score intervals; fitting point diagnostics; no numerical application changes"
    if "phase153" in path:
        return "historical sensitivity table", "historical Phase153 replicated VB", "tables/joint_qdesn_article_validation_phase153_replication_summary.tex", "earlier feature/inference design; corrected-current-target equivalence unresolved"
    if "five_chain" in path:
        return "historical sensitivity table", "historical independent five-chain point-path sensitivity", "tables/qdesn_validation_mcmc_five_chain_sensitivity_manifest.txt", "point-path sensitivity; not current draw-wise v14 interval estimator"
    if "glofas" in path:
        review = "review_" in path
        contract = "tables/glofas_review_figure_manifest.json" if review else "tables/glofas_search3_part1234_final_20261007_publication_manifest.csv"
        authority = "GloFAS Search III; presentation-only vector derivative" if review else "GloFAS Search III Parts 1--4"
        estimator = "VB AL/exAL (independent/joint), Normal predictive baselines and raw issued ensemble; Part 2 unscored"
        if "three_panel_review" in path or "main_scores_review" in path:
            contract = "tables/qdesn_article_presentation_manifest_v2.json;tables/glofas_search3_review_plot_input_provenance.json"
            authority = "GloFAS Search III; authenticated plotting-only derivative"
    elif "pricefm" in path:
        contract = "tables/pricefm_r98_article_projection_manifest.json"
        authority = "PriceFM R98 complete region-frozen authority; R92 historical only where labelled"
        estimator = "independent Q--DESN VB versus released PriceFM; equal-case AQL; no joint PriceFM fit"
    elif "joint_qdesn_pure_desn_v2_" in path:
        contract = "tables/joint_qdesn_pure_desn_v2_article_asset_manifest.csv;tables/joint_qdesn_pure_desn_v2_projection_provenance.csv"
        authority = "complete pure-DESN comparison; coherent four-model Laplace replacement; seven scenarios unchanged"
        estimator = "DGP-integrated finite-grid score conditional on averaged recursive features; draw-path sensitivity separate; actual per-cell draw counts; VB intercepts fixed"
    elif "joint_qdesn_pure_desn" in path or "joint_qdesn_pro_review" in path or "joint_qdesn_simulation/" in path:
        contract = "tables/joint_qdesn_pure_desn_v1_article_asset_manifest.csv;tables/joint_qdesn_pure_desn_v1_projection_provenance.csv"
        if "pro_review" in path:
            contract += ";tables/qdesn_article_presentation_manifest_v2.json"
        authority = "expanded pure-DESN 32 MCMC + 32 VB cells"
        estimator = "DGP-integrated finite-grid score conditional on model-specific averaged recursive features; VB intercepts fixed; fit recovery points"
    elif "qdesn_validation" in path or "qdesn_pro_review" in path or "independent_simulation/" in path:
        contract = "tables/qdesn_validation_500obs_metric_intervals_v14_manifest.txt;tables/qdesn_validation_500obs_dgp_oracle_figures_v14_manifest.txt"
        if "pro_review" in path:
            contract += ";tables/qdesn_article_presentation_manifest_v2.json"
        authority = "independent rolling-state v14"
        estimator = "criterion-specific draw-wise posterior/variational metric means and equal-tailed intervals; point paths and inherited roles distinct"
    else:
        return "approved article companion", "current article source contract", "overleaf/article_files.txt", "not identified by filename; inspect source before scientific interpretation"
    if suffix == ".tex":
        role = "alias/presentation override" if "outputs" in path or "overrides" in path else "generated numerical table/figure wrapper"
    elif suffix in (".pdf", ".png"):
        role = "presentation-only display derivative" if "review" in path else "frozen scientific display"
    elif "manifest" in path or "provenance" in path:
        role = "provenance companion"
    else:
        role = "tabulated summary/audit companion"
    return role, authority, contract, estimator


def inventory(repo: Path) -> tuple[str, list[str]]:
    allowlist = repo / "overleaf/article_files.txt"
    allowed = [line.strip() for line in allowlist.read_text().splitlines()
               if line.strip() and not line.lstrip().startswith("#")]
    if len(allowed) != len(set(allowed)) or allowed != sorted(allowed):
        raise ValueError("Article allowlist must be sorted and unique")
    consumers: dict[str, set[str]] = defaultdict(set)
    edges: dict[str, set[str]] = defaultdict(set)
    unresolved: list[str] = []
    for document in ("main.tex", "qdesn-supplement.tex"):
        aliases: dict[str, str] = {}

        def visit(relative: str, active: tuple[str, ...] = ()) -> None:
            if relative in active:
                raise ValueError(f"Recursive TeX input: {relative}")
            source = uncomment((repo / relative).read_text())
            consumers[relative].add(document)
            for match in TOKEN.finditer(source):
                if match.group("name"):
                    aliases[match.group("name")] = match.group("value")
                    continue
                kind, raw = match.group("kind"), match.group("target").strip()
                resolved = aliases.get(raw[1:], "") if raw.startswith("\\") else raw
                if not resolved or "\\" in resolved:
                    unresolved.append(f"{relative}:{kind}:{raw}")
                    continue
                targets = resolved.split(",") if kind == "bibliography" else [resolved]
                for target in targets:
                    extension = {"input": ".tex", "bibliography": ".bib", "bibliographystyle": ".bst"}.get(kind)
                    if extension and not Path(target).suffix:
                        target += extension
                    if not (repo / target).is_file():
                        raise ValueError(f"Missing local dependency: {relative} -> {target}")
                    consumers[target].add(document)
                    line = source.count("\n", 0, match.start()) + 1
                    edge = f"{relative}:{line} {kind} {raw}"
                    if raw != resolved:
                        edge += f" => {target}"
                    edges[target].add(edge)
                    if kind == "input":
                        visit(target, active + (relative,))

        visit(document)
    outside = sorted(set(consumers) - set(allowed))
    if outside:
        raise ValueError("Source-inferred inputs absent from allowlist: " + ";".join(outside))
    if unresolved:
        raise ValueError("Unresolved file-input aliases: " + ";".join(unresolved))
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, FIELDS, lineterminator="\n")
    writer.writeheader()
    for relative in allowed:
        path = repo / relative
        if not path.is_file():
            raise ValueError(f"Missing allowlisted file: {relative}")
        role, authority, contract, estimator = classification(relative)
        writer.writerow(dict(zip(FIELDS, (
            relative, role, authority, contract, estimator,
            hashlib.sha256(path.read_bytes()).hexdigest(),
            ";".join(sorted(consumers[relative])), ";".join(sorted(edges[relative])),
            "source-inferred manuscript input" if consumers[relative] else "approved companion; not a source-inferred TeX input"))))
    return output.getvalue(), allowed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--check", type=Path, help="Compare an existing inventory; no files are written")
    args = parser.parse_args()
    generated, allowed = inventory(args.repo_root.resolve())
    if args.check:
        if args.check.read_text() != generated:
            raise ValueError("Inventory is stale: regenerate after the final manuscript/allowlist/display edit")
        print(f"ARTICLE_DEPENDENCY_INVENTORY=PASS: {len(allowed)} allowlisted files")
    else:
        sys.stdout.write(generated)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"ARTICLE_DEPENDENCY_INVENTORY=FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
