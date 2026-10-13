#!/usr/bin/env python3.11
"""Read-only, fail-closed checks for the MQ presentation overlay.

The display registry is not a model registry. Original model IDs, scientific
CSV files, posterior targets, and historical article assets remain immutable.
Only effective TeX consumers and the eight selected MQ PDF derivatives are
audited for current display names. No fitting or asset generation is performed.
"""
from __future__ import annotations

import argparse
from collections import Counter
import csv
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys


REGISTRY = "tables/qdesn_model_display_names.csv"
JOINT_MANIFEST = "tables/joint_qdesn_mq_presentation_manifest.json"
GLOFAS_MANIFEST = "tables/glofas_mq_presentation_manifest.json"
HISTORICAL_MANIFEST = "tables/qdesn_historical_display_manifest.json"
HISTORICAL_ASSETS = {
    "tables/qdesn_validation_500obs_metric_dependence_sensitivity.tex": (
        "74c165ad4b29f00808e058750d8f6a320b5454f97ae7133d1260ae9794d5ee2b",
        "tables/qdesn_validation_500obs_metric_dependence_sensitivity_display.tex",
        (("For Q--DESN and exQ--DESN", "For Q--DESN under AL and exAL", 1),), 0),
    "tables/joint_qdesn_article_validation_phase153_replication_summary.tex": (
        "f2768de0639f82bbdfdc805ef068e68621e44f01c3c24711a92f25e2e155a19d",
        "tables/joint_qdesn_article_validation_phase153_replication_summary_mq_display.tex",
        (("Joint: AL-exAL", r"\shortstack{Historical multiquantile\\AL--exAL}", 1),
         (r"\caption{Replicated VB comparison", r"\caption{Historical replicated VB comparison", 1)), 8),
}
REGISTRY_FIELDS = ("context", "source_key", "model_family", "fit_structure",
                   "likelihood_family", "display_tex", "display_text")
SIMULATION_KEYS = (
    "joint_qdesn_rhs_vb", "joint_qdesn_rhs_mcmc",
    "qdesn_rhs_independent_vb", "qdesn_rhs_independent_mcmc",
    "joint_exqdesn_rhs_vb", "joint_exqdesn_rhs_mcmc",
    "exqdesn_rhs_independent_vb", "exqdesn_rhs_independent_mcmc",
)
OLD_LABELS = ("Joint AL", "Joint exAL", "Independent AL", "Independent exAL")
JOINT_SUFFIXES = ("protocol", "score_table", "secondary_score_table", "vb_score_table",
                  "recursive_policy_table", "contrast_table", "crossing_table",
                  "oracle_recovery_table", "forecast_figure", "fit_figure")
JOINT_TABLES = {f"tables/joint_qdesn_pure_desn_v2_mq_{s}.tex" for s in JOINT_SUFFIXES}
JOINT_PDFS = {f"figures/joint_qdesn_simulation/joint_qdesn_pure_desn_v2_mq_{s}.pdf"
              for s in ("forecast_dgp_acrps", "fit_oracle_rmse")}
GLOFAS_ROLES = ("part1", "part2", "part3", "part4", "convergence", "calibration")
GLOFAS_PDFS = {f"figures/glofas_application/glofas_search3_mq_review_20261013_{s}.pdf"
               for s in GLOFAS_ROLES}
GLOFAS_TABLES = {f"tables/glofas_search3_mq_{s}.tex" for s in
                 ("calibration", "convergence", "part123_prior_settings", "part123_scores",
                  "prior_settings", "main_scores")}
GLOFAS_OVERRIDE = "tables/glofas_mq_display_overrides.tex"
GLOFAS_ALIASES = {
    "FullComparisonFigure": "part4", "PartOneFigure": "part1", "PartTwoFigure": "part2",
    "PartThreeFigure": "part3", "ConvergenceFigure": "convergence", "CalibrationFigure": "calibration",
}
FROZEN_MANIFESTS = {
    "tables/joint_qdesn_pure_desn_v2_article_asset_manifest.csv":
        "cc50ea11fed8bbb3bbe9b7f1d66c2c99c570423853f0d30dd3fe6ffa42c6f473",
    "tables/glofas_search3_part1234_final_20261007_publication_manifest.csv":
        "5a7ac4fc1b35f3e7b19c4535e5e5c1cc56c4dfe87927b42f6f66122d49a01335",
}
TARGET_AUDIT = "tables/joint_qdesn_pure_desn_v2_mcmc_posterior_target_hash_audit.csv"
FORECAST_SCORES = "tables/joint_qdesn_pure_desn_v2_forecast_score_summary.csv"
FIT_DIAGNOSTICS = "tables/joint_qdesn_pure_desn_v2_fit_oracle_diagnostics.csv"
LEGACY = re.compile(
    r"\bJoint\s+(?:AL|exAL)\b|\b(?i:joint\s+(?:(?:AL|exAL)\s+)?Q\s*[-–—]*\s*DESN)\b"
    r"|\b(?i:exQ\s*[-–—]*\s*DESN)\b"
)


class CheckError(RuntimeError):
    """A missing dependency or a violated presentation contract."""


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise CheckError(message)


def local_path(root: Path, relative: str) -> Path:
    expect(isinstance(relative, str) and bool(relative), "Missing relative artifact path")
    path = Path(relative)
    expect(not path.is_absolute() and ".." not in path.parts, f"Unsafe artifact path: {relative}")
    resolved = (root / path).resolve()
    expect(resolved.is_relative_to(root.resolve()), f"Artifact escapes repository: {relative}")
    expect(resolved.is_file(), f"Missing dependency: {relative}")
    return resolved


def read(root: Path, relative: str) -> str:
    return local_path(root, relative).read_text(encoding="utf-8")


def sha(root: Path, relative: str) -> str:
    return hashlib.sha256(local_path(root, relative).read_bytes()).hexdigest()


def verify_hash(root: Path, relative: str, expected: str) -> None:
    expect(isinstance(expected, str) and re.fullmatch(r"[a-f0-9]{64}", expected) is not None,
           f"Invalid SHA-256 receipt: {relative}")
    expect(sha(root, relative) == expected, f"Hash mismatch: {relative}")


def csv_rows(root: Path, relative: str) -> list[dict[str, str]]:
    with local_path(root, relative).open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def load_json(root: Path, relative: str) -> dict:
    result = json.loads(read(root, relative))
    expect(isinstance(result, dict), f"Manifest is not an object: {relative}")
    return result


def registry_rows(root: Path) -> list[dict[str, str]]:
    rows = csv_rows(root, REGISTRY)
    expect(len(rows) == 12 and all(tuple(row) == REGISTRY_FIELDS for row in rows),
           "Display registry must contain the exact seven-column, twelve-row schema")
    expected_keys = {("simulation", k) for k in SIMULATION_KEYS} | {("glofas", k) for k in OLD_LABELS}
    keys = [(row["context"], row["source_key"]) for row in rows]
    expect(len(set(keys)) == 12 and set(keys) == expected_keys, "Display registry namespace/key mismatch")
    for row in rows:
        key = row["source_key"]
        joint = key.startswith(("joint_", "Joint "))
        likelihood = "exAL" if "exqdesn" in key or "exAL" in key else "AL"
        family = "MQ-DESN" if joint else "Q-DESN"
        expected = {"model_family": family, "fit_structure": "joint" if joint else "independent",
                    "likelihood_family": likelihood, "display_text": f"{family} ({likelihood})",
                    "display_tex": f"{family.replace('-', '--')} ({likelihood})"}
        expect(all(row[field] == value for field, value in expected.items()),
               f"Display registry semantic mapping changed: {row['context']}:{key}")
    return rows


def immutable_sources(root: Path) -> set[str]:
    paths = set(FROZEN_MANIFESTS)
    for manifest, fingerprint in FROZEN_MANIFESTS.items():
        verify_hash(root, manifest, fingerprint)
        rows = csv_rows(root, manifest)
        expect(bool(rows), f"Empty frozen source manifest: {manifest}")
        for row in rows:
            relative = row["relative_path"]
            verify_hash(root, relative, row["sha256"])
            expect(local_path(root, relative).stat().st_size == int(row["size_bytes"]),
                   f"Frozen source size changed: {relative}")
            paths.add(relative)
    audit = csv_rows(root, TARGET_AUDIT)
    expect(len(audit) == 32 and len({r["model_cell_id"] for r in audit}) == 32 and
           all(r["n_chains"] == "5" and r["verified"].upper() == "TRUE" and
               re.fullmatch(r"[a-f0-9]{64}", r["posterior_target_sha256"]) for r in audit),
           "The unchanged 32-cell, five-chain posterior-target surface is incomplete")
    surfaces = []
    for relative in (FORECAST_SCORES, FIT_DIAGNOSTICS):
        rows = [r for r in csv_rows(root, relative) if r["inference_method"] == "mcmc"]
        expect(len(rows) == 32 and len({r["model_cell_id"] for r in rows}) == 32,
               f"Current MCMC scientific surface is not 32 unique cells: {relative}")
        surfaces.append({r["model_cell_id"] for r in rows})
    expect(surfaces[0] == surfaces[1] == {r["model_cell_id"] for r in audit},
           "Forecast, fit, and posterior-target cell IDs differ")
    return paths


def module_manifests(root: Path) -> tuple[dict, dict, set[str]]:
    joint = load_json(root, JOINT_MANIFEST)
    glofas = load_json(root, GLOFAS_MANIFEST)
    dependencies = {REGISTRY, JOINT_MANIFEST, GLOFAS_MANIFEST}
    for manifest, schema in ((joint, "joint-qdesn-mq-presentation-v1"),
                             (glofas, "glofas-mq-presentation-overlay-v1")):
        expect(manifest.get("schema") == schema, f"Wrong MQ manifest schema: {schema}")
        expect(manifest.get("registry") == REGISTRY, f"Wrong registry in {schema}")
        verify_hash(root, REGISTRY, manifest.get("registry_sha256"))
        verify_hash(root, manifest.get("generator"), manifest.get("generator_sha256"))
        dependencies.add(manifest["generator"])
    sources = joint.get("sources")
    expect(isinstance(sources, dict) and bool(sources), "JOINT source receipts are missing")
    for relative, fingerprint in sources.items():
        verify_hash(root, relative, fingerprint)
        dependencies.add(relative)
    outputs = joint.get("outputs", [])
    expect(len(outputs) == 12 and {r["file"] for r in outputs} == JOINT_TABLES | JOINT_PDFS,
           "JOINT MQ output set must be the ten TeX derivatives and two PDFs")
    for asset in outputs:
        verify_hash(root, asset["file"], asset["sha256"])
        expect(asset["source"] in sources, f"JOINT derivative has unauthenticated source: {asset['file']}")
        expect(local_path(root, asset["file"]).stat().st_size == asset["size_bytes"],
               f"JOINT MQ derivative size changed: {asset['file']}")
        dependencies.add(asset["file"])
    verify_hash(root, glofas.get("frozen_renderer"), glofas.get("frozen_renderer_sha256"))
    dependencies.add(glofas["frozen_renderer"])
    protected = glofas.get("protected_sources", [])
    expect(bool(protected), "GloFAS protected source receipts are missing")
    for asset in protected:
        verify_hash(root, asset["file"], asset["sha256"])
        dependencies.add(asset["file"])
    for field, expected_paths in (("assets", GLOFAS_PDFS), ("table_assets", GLOFAS_TABLES)):
        assets = glofas.get(field, [])
        expect(len(assets) == 6 and {r["output"] for r in assets} == expected_paths,
               f"GloFAS MQ {field} set changed")
        for asset in assets:
            for name in ("source", "output"):
                verify_hash(root, asset[name], asset[f"{name}_sha256"])
                dependencies.add(asset[name])
            if field == "assets":
                expect(asset.get("raster_images") == 0 and asset.get("all_labels_inside_page") is True and
                       asset.get("numeric_token_multiset_unchanged") is True and
                       asset.get("exact_mapped_text_tokens_retained") is True and
                       asset.get("minimum_effective_label_bp", 0) >= 8,
                       f"GloFAS vector/readability/text contract failed: {asset['output']}")
            else:
                expect(asset.get("numeric_cells_unchanged") is True,
                       f"GloFAS numerical table contract failed: {asset['output']}")
    override = glofas.get("overrides", {})
    expect(override.get("file") == GLOFAS_OVERRIDE, "Wrong GloFAS MQ override file")
    verify_hash(root, GLOFAS_OVERRIDE, override.get("sha256"))
    dependencies.add(GLOFAS_OVERRIDE)
    return joint, glofas, dependencies


def historical_manifest(root: Path) -> set[str]:
    manifest = load_json(root, HISTORICAL_MANIFEST)
    expect(manifest.get("schema") == "qdesn-historical-display-overlay-v1",
           "Wrong historical display manifest schema")
    generator = "scripts/build_qdesn_historical_display_overlays.py"
    expect(manifest.get("generator") == generator, "Wrong historical display generator")
    verify_hash(root, generator, manifest.get("generator_sha256"))
    assets = manifest.get("assets", [])
    expect(len(assets) == 2 and {r["source"] for r in assets} == set(HISTORICAL_ASSETS),
           "Historical display manifest must contain exactly the two approved source/output pairs")
    dependencies = {HISTORICAL_MANIFEST, generator}
    for asset in assets:
        source = asset["source"]
        fingerprint, output, replacements, rows = HISTORICAL_ASSETS[source]
        verify_hash(root, source, fingerprint)
        verify_hash(root, source, asset.get("source_sha256"))
        expect(asset.get("output") == output, f"Wrong historical display output: {source}")
        verify_hash(root, output, asset.get("output_sha256"))
        declared = tuple((r["old"], r["new"], r["occurrences"]) for r in asset.get("replacements", []))
        expect(declared == replacements, f"Historical display replacement scope changed: {source}")
        expected = local_path(root, source).read_bytes()
        for old, new, occurrences in replacements:
            expect(expected.count(old.encode()) == occurrences, f"Historical replacement cardinality changed: {source}")
            expected = expected.replace(old.encode(), new.encode())
        observed = local_path(root, output).read_bytes()
        expect(observed == expected, f"Historical display changed bytes outside the approved replacements: {output}")
        numbers = rb"(?<![A-Za-z])[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?"
        expect(re.findall(numbers, local_path(root, source).read_bytes()) == re.findall(numbers, observed),
               f"Historical display numeric tokens changed: {output}")
        expect(asset.get("all_non_replacement_bytes_unchanged") is True and
               asset.get("numeric_tokens_unchanged") is True and asset.get("source_data_rows") == rows,
               f"Historical display invariance receipt failed: {output}")
        expect("MQ--DESN" not in observed.decode(), "Historical Phase153 must not be branded as a current MQ fit")
        dependencies.update((source, output))
    return dependencies


def uncomment(text: str) -> str:
    return re.sub(r"(?<!\\)%[^\n]*", "", text)


def braced(text: str, pos: int) -> tuple[str, int]:
    while pos < len(text) and text[pos].isspace():
        pos += 1
    expect(pos < len(text) and text[pos] == "{",
           f"Unsupported/unbraced selected TeX argument near {text[pos:pos + 70]!r}")
    start = pos + 1
    depth = 1
    pos = start
    while pos < len(text):
        if text[pos] in "{}" and (pos == 0 or text[pos - 1] != "\\"):
            depth += 1 if text[pos] == "{" else -1
            if depth == 0:
                return text[start:pos], pos + 1
        pos += 1
    raise CheckError("Unbalanced selected TeX argument")


class TexConsumers:
    """Resolve zero-argument aliases and inputs in their actual source order."""

    def __init__(self, root: Path):
        self.root = root
        self.macros: dict[str, str] = {}
        self.files: set[str] = set()
        self.figures: set[str] = set()
        self.alias_uses: dict[str, list[str]] = {}

    def expand(self, text: str) -> str:
        for _ in range(30):
            result = re.sub(r"\\([A-Za-z]+)\b", lambda m: self.macros.get(m[1], m[0]), text)
            if result == text:
                return result
            text = result
        raise CheckError("Cyclic selected TeX macro expansion")

    def visit(self, relative: str, ancestors: tuple[str, ...] = ()) -> str:
        expect(relative not in ancestors, f"Cyclic TeX input: {relative}")
        self.files.add(relative)
        source = uncomment(read(self.root, relative))
        pattern = re.compile(r"\\(input|includegraphics|newcommand|renewcommand|providecommand)\b\*?")
        visible = []
        cursor = 0
        for_match = pattern.search(source, cursor)
        while for_match:
            visible.append(self.expand(source[cursor:for_match.start()]))
            command = for_match[1]
            pos = for_match.end()
            if command in ("newcommand", "renewcommand", "providecommand"):
                name, pos = braced(source, pos)
                count = re.match(r"\s*\[([^]]*)\]", source[pos:])
                if count:
                    pos += count.end()
                    default = re.match(r"\s*\[[^]]*\]", source[pos:])
                    if default:
                        pos += default.end()
                body, pos = braced(source, pos)
                name = name.removeprefix("\\")
                if not count and (command != "providecommand" or name not in self.macros):
                    self.macros[name] = body
            else:
                option = re.match(r"\s*\[[^]]*\]", source[pos:])
                if option:
                    pos += option.end()
                raw, pos = braced(source, pos)
                target = self.expand(raw).strip()
                expect("\\" not in target, f"Unresolved selected TeX path: {raw}")
                if command == "input":
                    if not Path(target).suffix:
                        target += ".tex"
                    visible.append(self.visit(target, ancestors + (relative,)))
                else:
                    if not Path(target).suffix:
                        target += ".pdf"
                    local_path(self.root, target)
                    self.figures.add(target)
                    alias = re.fullmatch(r"\\([A-Za-z]+)", raw.strip())
                    if alias:
                        self.alias_uses.setdefault(alias[1], []).append(target)
            cursor = pos
            for_match = pattern.search(source, cursor)
        visible.append(self.expand(source[cursor:]))
        result = "".join(visible)
        # Internal IDs, citations, and alternative text are not typeset prose.
        result = re.sub(r"\\(?:label|ref|eqref|cite\w*|figalt)\s*(?:\[[^]]*\])?\{[^{}]*\}", "", result)
        return result


def normalized(text: str) -> str:
    return re.sub(r"\s+", " ", text.replace("--", "-").replace("–", "-").replace("−", "-"))


def label_counts(text: str, labels: list[str] | tuple[str, ...]) -> Counter:
    text = normalized(text)
    return Counter({label: len(re.findall(r"(?<![A-Za-z])" + re.escape(label) + r"(?![A-Za-z])", text))
                    for label in labels})


def verify_label_mapping(source: str, output: str, rows: list[dict[str, str]], relative: str) -> None:
    mapping = {r["source_key"]: r["display_text"] for r in rows if r["context"] == "glofas"}
    # The frozen Part 4 subtitle names the two joint likelihoods in shorthand.
    # Count both named models without requiring that historical commentary stay
    # verbatim in current prose or trusting an editable manifest label mapping.
    source = re.sub(r"\bJoint AL and exAL\b", "Joint AL and Joint exAL", normalized(source))
    old_counts = label_counts(source, OLD_LABELS)
    expected = Counter({mapping[k]: n for k, n in old_counts.items()})
    observed = label_counts(output, list(mapping.values()))
    expect(expected == observed, f"Independent/MQ or AL/exAL display-label counts changed: {relative}")
    expect(not LEGACY.search(normalized(output)), f"Legacy current display name: {relative}")


def pdf_text(root: Path, relative: str) -> str:
    for utility in ("pdftotext", "pdfinfo"):
        expect(shutil.which(utility) is not None, f"Required PDF audit utility missing: {utility}")
    path = local_path(root, relative)
    info = subprocess.run(["pdfinfo", str(path)], check=True, capture_output=True, text=True).stdout
    expect(re.search(r"^Pages:\s+1\s*$", info, re.M) is not None, f"Current presentation PDF is not one page: {relative}")
    text = subprocess.run(["pdftotext", "-layout", str(path), "-"], check=True,
                          capture_output=True, text=True).stdout
    expect(bool(text.strip()), f"Current presentation PDF has no extractable text: {relative}")
    return text


def manuscript_consumers(root: Path) -> tuple[dict[str, TexConsumers], dict[str, str]]:
    graphs, visible = {}, {}
    for document in ("main.tex", "qdesn-supplement.tex"):
        graph = TexConsumers(root)
        visible[document] = graph.visit(document)
        graphs[document] = graph
    return graphs, visible


def check_definitions(root: Path, visible: dict[str, str]) -> None:
    main, supplement = (uncomment(read(root, p)) for p in ("main.tex", "qdesn-supplement.tex"))
    abstract = re.search(r"\\begin\{abstract\}(.*?)\\end\{abstract\}", main, re.S)
    intro = re.search(r"\\section\{Introduction\}(.*?)(?=\\section\{)", main, re.S)
    expect(abstract is not None and intro is not None, "Main abstract/introduction missing")
    windows = {"main abstract": abstract[1], "main introduction": intro[1],
               "supplement opening": supplement[:supplement.find(r"\section{Distributional Conventions}")]}
    for name, window in windows.items():
        text = normalized(window)
        q_definition = re.search(r"quantile\s+deep\s+echo\s+state\s+networks?\s*\(\s*Q-DESN\s*\)", text, re.I)
        mq_definition = re.search(r"multi[ -]?quantile\s+deep\s+echo\s+state\s+networks?\s*\(\s*MQ-DESN\s*\)", text, re.I)
        expect(q_definition is not None and mq_definition is not None,
               f"Q-DESN and multiquantile MQ-DESN need standalone definitions in {name}")
    for document in visible.values():
        headings = list(re.finditer(r"\\(section|subsection)\{([^{}]*)\}", document))
        for index, heading in enumerate(headings):
            if "PriceFM" not in heading[2]:
                continue
            rank = 1 if heading[1] == "section" else 2
            end = next((h.start() for h in headings[index + 1:]
                        if (1 if h[1] == "section" else 2) <= rank), len(document))
            expect("MQ-DESN" not in normalized(document[heading.end():end]),
                   "PriceFM must not be presented as an MQ-DESN fit")


def dependency_paths(root: Path) -> set[str]:
    """Exact dependency closure for isolated tests; never discover via a glob."""
    paths = {REGISTRY, JOINT_MANIFEST, GLOFAS_MANIFEST, GLOFAS_OVERRIDE, HISTORICAL_MANIFEST,
             TARGET_AUDIT, FORECAST_SCORES, FIT_DIAGNOSTICS}
    for manifest in FROZEN_MANIFESTS:
        paths.add(manifest)
        paths.update(row["relative_path"] for row in csv_rows(root, manifest))
    joint, glofas = load_json(root, JOINT_MANIFEST), load_json(root, GLOFAS_MANIFEST)
    paths.update(joint["sources"])
    paths.update(row["file"] for row in joint["outputs"])
    for manifest in (joint, glofas):
        paths.add(manifest["generator"])
    paths.add(glofas["frozen_renderer"])
    paths.update(row["file"] for row in glofas["protected_sources"])
    for field in ("assets", "table_assets"):
        for row in glofas[field]:
            paths.update((row["source"], row["output"]))
    historical = load_json(root, HISTORICAL_MANIFEST)
    paths.add(historical["generator"])
    for asset in historical["assets"]:
        paths.update((asset["source"], asset["output"]))
    graphs, _ = manuscript_consumers(root)
    for graph in graphs.values():
        paths.update(graph.files | graph.figures)
    return paths


def check(root: Path) -> dict[str, int]:
    rows = registry_rows(root)
    immutable_sources(root)
    joint, glofas, _ = module_manifests(root)
    historical_manifest(root)
    graphs, visible = manuscript_consumers(root)
    files = set().union(*(g.files for g in graphs.values()))
    figures = set().union(*(g.figures for g in graphs.values()))
    expect(JOINT_TABLES | GLOFAS_TABLES <= files, "Current manuscript omits an MQ TeX derivative")
    expect({entry[1] for entry in HISTORICAL_ASSETS.values()} <= files,
           "Current manuscript omits an authenticated historical display derivative")
    expect(JOINT_PDFS | GLOFAS_PDFS <= figures, "Effective selected aliases/wrappers do not select all eight MQ PDFs")
    expect("tables/joint_qdesn_pure_desn_v2_mq_forecast_figure.tex" in graphs["main.tex"].files and
           "tables/joint_qdesn_pure_desn_v2_mq_fit_figure.tex" in graphs["qdesn-supplement.tex"].files,
           "JOINT forecast belongs in main; JOINT fit belongs in supplement")
    for document, graph in graphs.items():
        expect(GLOFAS_OVERRIDE in graph.files, f"MQ overrides missing from {document}")
        expect(not any(re.match(r"tables/joint_qdesn_pure_desn_v2_(?!mq_).*\.tex$", p) for p in graph.files),
               f"Stale JOINT TeX derivative remains selected in {document}")
        for suffix, role in GLOFAS_ALIASES.items():
            name = "GlofasApplicationCurrent" + suffix
            expected_path = f"figures/glofas_application/glofas_search3_mq_review_20261013_{role}.pdf"
            if name in graph.alias_uses:
                expect(all(p == expected_path for p in graph.alias_uses[name]),
                       f"Stale effective selected alias: {name}")
        legacy = LEGACY.search(normalized(visible[document]))
        expect(legacy is None, f"Legacy current display name {legacy[0] if legacy else ''!r} in {document}")
    check_definitions(root, visible)
    for asset in joint["outputs"]:
        if asset["file"].endswith(".pdf"):
            verify_label_mapping(pdf_text(root, asset["source"]), pdf_text(root, asset["file"]), rows, asset["file"])
        elif asset["role"] == "table":
            verify_label_mapping(read(root, asset["source"]), read(root, asset["file"]), rows, asset["file"])
    for field in ("assets", "table_assets"):
        for asset in glofas[field]:
            source, output = asset["source"], asset["output"]
            extractor = pdf_text if field == "assets" else read
            verify_label_mapping(extractor(root, source), extractor(root, output), rows, output)
    return {"registry_rows": 12, "posterior_cells": 32, "selected_mq_pdfs": 8,
            "selected_mq_tex": len(JOINT_TABLES | GLOFAS_TABLES), "historical_displays": 2}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        result = check(args.repo_root.resolve())
    except (CheckError, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f"QDESN_MQ_NOMENCLATURE_CHECK=FAIL {error}", file=sys.stderr)
        return 1
    print("QDESN_MQ_NOMENCLATURE_CHECK=PASS " + " ".join(f"{k}={v}" for k, v in result.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
