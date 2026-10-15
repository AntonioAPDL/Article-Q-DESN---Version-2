#!/usr/bin/env python3
"""Authenticate bounded editorial display derivatives without scientific work.

The library entry points ``check(root)`` and ``dependency_paths(root)`` are
import-safe. PDF inspection uses pdftotext; no statistical or PDF Python package
is required. Original scientific/MQ display assets remain separately audited.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess


def load_builder(root: Path):
    path = root / "scripts/build_qdesn_sections5_7_presentation.py"
    spec = importlib.util.spec_from_file_location("sections5_7_display_builder", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dependency_paths(root: Path) -> set[str]:
    builder = load_builder(root)
    files = set(builder.SOURCE_PINS) | {builder.BUILDER, builder.CHECKER, builder.MANIFEST,
                                      "main.tex", "qdesn-supplement.tex", "overleaf/article_files.txt"}
    for source, output in list(builder.TABLE_OUTPUTS.values()) + list(builder.WRAPPER_OUTPUTS.values()) + list(builder.PDF_OUTPUTS.values()):
        files.update((source, output))
    files.update((builder.MAIN_OVERRIDE, builder.SUPP_OVERRIDE))
    return files


def expected_text(root: Path, role: str, source: str) -> str:
    builder = load_builder(root)
    value = (root / source).read_text()
    if role in builder.TABLE_OUTPUTS:
        return builder.display_table(role, value)
    assert role in builder.WRAPPER_OUTPUTS
    return builder.display_wrapper(role, value)


def pdf_text(path: Path) -> str:
    return subprocess.run(["pdftotext", "-layout", str(path), "-"], text=True, check=True, capture_output=True).stdout


def mapped_source_words(builder, source: str) -> Counter:
    # Apply only complete, authenticated source-label phrases. Whitespace
    # normalization permits line wraps, but not any numerical/value exemption.
    text = " ".join(source.split())
    for old, new in sorted(builder.PDF_LABELS.items(), key=lambda pair: -len(pair[0])):
        text = re.sub(r"(?<!\S)" + re.escape(old) + r"(?!\S)", lambda match: new, text)
    return Counter(text.split())


def aliases_for_document(root: Path, path: str) -> dict[str, str]:
    aliases = {}
    active = set()

    def consume(relative: str):
        if relative in active:
            raise AssertionError("Cyclic TeX alias input.")
        file = root / relative
        if not file.exists():
            return  # Full dependency closure is independently checked.
        active.add(relative)
        for line in file.read_text().splitlines():
            line = re.sub(r"(?<!\\)%.*", "", line)
            for match in re.finditer(r"\\(?:re)?newcommand\{\\([^}]+)\}\{([^{}\n]+)\}", line):
                aliases[match[1]] = match[2]
            for match in re.finditer(r"\\input\{([^}]+)\}", line):
                if not match[1].startswith("\\"):
                    consume(match[1])
        active.remove(relative)

    consume(path)
    return aliases


def check(root: Path, *, effective: bool = True) -> dict:
    root = Path(root).resolve()
    builder = load_builder(root)
    manifest = json.loads((root / builder.MANIFEST).read_text())
    assert manifest["schema"] == "qdesn-sections5-7-presentation-v1"
    assert manifest["generator"] == builder.BUILDER
    assert manifest["generator_sha256"] == digest(root / builder.BUILDER), "Editorial renderer changed without a new receipt."
    assert all(manifest[key] == 0 for key in ("scientific_runs", "scores_recomputed", "frozen_sources_modified"))
    source_rows = manifest["sources"]
    assert len(source_rows) == len(builder.SOURCE_PINS)
    assert {row["file"]: row["sha256"] for row in source_rows} == builder.SOURCE_PINS
    for path, sha in builder.SOURCE_PINS.items():
        assert digest(root / path) == sha, "Frozen source changed: " + path
    expected = {}
    for role, (source, path) in list(builder.TABLE_OUTPUTS.items()) + list(builder.WRAPPER_OUTPUTS.items()) + list(builder.PDF_OUTPUTS.items()):
        expected[role] = (source, path)
    expected.update({"main_overrides": (None, builder.MAIN_OVERRIDE), "supp_overrides": (None, builder.SUPP_OVERRIDE)})
    entries = {row["role"]: row for row in manifest["outputs"]}
    assert len(entries) == len(manifest["outputs"]) == len(expected), "Derivative role inventory changed."
    assert set(entries) == set(expected)
    for role, (source, path) in expected.items():
        entry = entries[role]
        assert entry["file"] == path and entry["sha256"] == digest(root / path), "Derivative bytes/hash mismatch: " + path
        if source:
            assert entry["source"] == source and entry["source_sha256"] == builder.SOURCE_PINS[source]
        if role in builder.TABLE_OUTPUTS or role in builder.WRAPPER_OUTPUTS:
            actual = (root / path).read_text()
            assert actual == expected_text(root, role, source), "Unpermitted table/caption transformation: " + role
            assert not re.search(r"\b(?:Part [1-4]|Search III|R9[28])\b", actual), "Campaign label remains in display."
            if role in builder.TABLE_OUTPUTS:
                assert entry["rows"] == builder.table_rows(actual)
            else:
                original = (root / source).read_text()
                for command in (r"\\label\{([^}]+)\}", r"\\includegraphics\[[^]]+\]\{([^}]+)\}"):
                    assert re.findall(command, original) == re.findall(command, actual), "Caption edit changed graphics or label."
        elif role in builder.PDF_OUTPUTS:
            text = pdf_text(root / path)
            expected_words = mapped_source_words(builder, pdf_text(root / source))
            assert Counter(dict(entry["expected_text_tokens"])) == expected_words, "Receipt disagrees with frozen PDF labels: " + role
            assert Counter(text.split()) == expected_words, "PDF labels or numerical tokens changed: " + role
            assert builder.numerical_tokens(text) == Counter(dict(entry["numeric_tokens"])), "Numerical PDF token changed."
            assert not re.search(r"\b(?:Part [1-4]|Search III|R9[28])\b", text)
            assert entry["minimum_effective_label_bp"] >= 8 and entry["raster_images"] == 0
            assert entry["vector_path_count"] > 0
        else:
            aliases = builder.MAIN_ALIASES if role == "main_overrides" else builder.SUPP_ALIASES
            assert (root / path).read_text() == builder.override_text(aliases)
            assert entry["aliases"] == aliases
    main_rows = entries["glofas_main"]["rows"]
    assert len(main_rows) == 7 and all(len(row) == 4 for row in main_rows)
    expected_names = ["Q--DESN (AL)", "Q--DESN (exAL)", "Normal Ridge", "MQ--DESN (AL)",
                      "MQ--DESN (exAL)", "Raw GloFAS", "Normal RHS/VB"]
    assert [row[0] for row in main_rows] == expected_names
    assert len(entries["glofas_components"]["rows"]) == 18
    assert all(row[2:] == ["---", "---", "---"] for row in entries["glofas_components"]["rows"] if row[0] == "Discrepancy")
    assert len(entries["glofas_component_priors"]["rows"]) == 24
    assert len(entries["glofas_specifications"]["rows"]) == 2
    assert len(entries["pricefm_global"]["rows"]) == 3
    if effective:
        for document, override, aliases in (("main.tex", builder.MAIN_OVERRIDE, builder.MAIN_ALIASES),
                                             ("qdesn-supplement.tex", builder.SUPP_OVERRIDE, builder.SUPP_ALIASES)):
            text = (root / document).read_text()
            assert r"\input{" + override + "}" in text, "Missing document-specific presentation override."
            current = aliases_for_document(root, document)
            for macro, path in aliases.items():
                assert current.get(macro) == path, "A stale later alias overrides " + macro
        main = (root / "main.tex").read_text()
        supplement = (root / "qdesn-supplement.tex").read_text()
        ind_revision = (root / "application/config/independent_forecast_300_500_v1.json").exists()
        for role in ("independent_forecast", "mq_forecast"):
            if role == "independent_forecast" and ind_revision:
                receipt = json.loads((root / "tables/independent_forecast_300_500_article_manifest_v1.json").read_text())
                assert receipt["primary_cutoff"] == 300 and receipt["sensitivity_cutoff"] == 500
                assert receipt["retrospective_scope_change"] is True
                for group in ("sources", "outputs"):
                    for path, expected_hash in receipt[group].items():
                        assert digest(root / path) == expected_hash, "IND reporting receipt mismatch: " + path
                assert r"\input{tables/independent_train500_eval300_mcmc_figures_v1.tex}" in main
                assert r"\input{tables/independent_train500_eval500_mcmc_figures_v1.tex}" in supplement
                assert r"\input{" + builder.WRAPPER_OUTPUTS[role][1] + "}" not in main
                continue
            assert r"\input{" + builder.WRAPPER_OUTPUTS[role][1] + "}" in main, "Stale effective forecast wrapper: " + role
            assert r"\input{" + builder.WRAPPER_OUTPUTS[role][0] + "}" not in main, "Original effective forecast wrapper remains: " + role
        for role in ("independent_mcmc_fit", "independent_vb_fit", "mq_fit"):
            assert r"\input{" + builder.WRAPPER_OUTPUTS[role][1] + "}" in supplement, "Stale effective fit wrapper: " + role
            assert r"\input{" + builder.WRAPPER_OUTPUTS[role][0] + "}" not in supplement, "Original effective fit wrapper remains: " + role
        assert r"\input{" + builder.TABLE_OUTPUTS["mq_design"][1] + "}" in supplement, "Stale effective multiquantile design table."
        assert r"\input{" + builder.TABLE_OUTPUTS["mq_design"][0] + "}" not in supplement, "Original multiquantile design remains selected."
        upload = set((root / "overleaf/article_files.txt").read_text().splitlines())
        active_entries = (entry for role, entry in entries.items() if not (ind_revision and role == "independent_forecast"))
        assert set(entry["file"] for entry in active_entries) | {builder.MANIFEST} <= upload, "An active derivative is absent from the upload inventory."
    return {"status": "PASS", "source_files": len(source_rows), "outputs": len(entries),
            "pdf_outputs": len(builder.PDF_OUTPUTS), "table_outputs": len(builder.TABLE_OUTPUTS),
            "caption_wrappers": len(builder.WRAPPER_OUTPUTS), "scientific_runs": 0, "scores_recomputed": 0}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", "--repo-root", dest="root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--assets-only", action="store_true", help="Audit derivatives before document wiring; not a publication gate.")
    args = parser.parse_args()
    result = check(args.root, effective=not args.assets_only)
    print("QDESN_SECTIONS5_7_PRESENTATION_CHECK=PASS")
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
