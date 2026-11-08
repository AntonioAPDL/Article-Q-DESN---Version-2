#!/usr/bin/env python3
"""Authenticate bounded editorial display derivatives without scientific work.

The library entry points ``check(root)`` and ``dependency_paths(root)`` are
import-safe. PDF inspection uses pdftotext; no statistical or PDF Python package
is required. Original scientific/MQ display assets remain separately audited.
"""
from __future__ import annotations

import argparse
from collections import Counter
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys


def corrected_glofas_authority(root: Path):
    """Authenticate the new active projection without weakening frozen assets."""
    authority = root / "tables/glofas_hybrid_current_authority.json"
    marker = r"\\input\s*\{\s*tables/glofas_hybrid_part123_search3_part4_october_20261107_display_aliases\.tex\s*\}"
    selected = any(re.search(marker, re.sub(r"(?<!\\)%.*", "", (root / document).read_text())) is not None
                   for document in ("main.tex", "qdesn-supplement.tex"))
    if not authority.exists():
        assert not selected, "Corrected GloFAS alias selected without its approved authority contract."
        return None, set()
    helper = root / "scripts/glofas_current_article_authority.py"
    assert helper.is_file(), "Corrected GloFAS authority validator is missing."
    spec = importlib.util.spec_from_file_location("glofas_authority_presentation_tree", helper)
    module = importlib.util.module_from_spec(spec)
    sys.dont_write_bytecode = True
    spec.loader.exec_module(module)
    try:
        reviewed = module.validate_authority_tree(root)
        paths = module.authority_dependency_paths(root)
    except (module.AuthorityError, OSError, ValueError) as error:
        raise AssertionError("Corrected GloFAS active projection failed: " + str(error)) from error
    return reviewed, paths


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
    policy = "application/config/independent_forecast_300_500_v1.json"
    if (root / policy).exists():
        receipt_path = "tables/independent_forecast_300_500_article_manifest_v1.json"
        receipt = json.loads((root / receipt_path).read_text())
        files.update((policy, receipt_path))
        for group in ("sources", "outputs"):
            files.update(receipt[group])
        calibration_path = "tables/independent_forecast_calibration_manifest_v1.json"
        if (root / calibration_path).exists():
            calibration = json.loads((root / calibration_path).read_text())
            files.add(calibration_path)
            files.update(calibration["sources"])
            files.update("tables/" + path for path in calibration["outputs"])
    _, corrected_paths = corrected_glofas_authority(root)
    files.update(corrected_paths)
    path = root / "scripts/appendix_compression_validation_20261106.py"
    if path.is_file():
        spec = importlib.util.spec_from_file_location("presentation_compression_paths", path)
        compression = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(compression)
        if compression.active(root):
            files.update(compression.dependency_paths(root))
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


def mapped_source_words(builder, source: str, role: str) -> Counter:
    # Apply only complete, authenticated source-label phrases. Whitespace
    # normalization permits line wraps, but not any numerical/value exemption.
    text = " ".join(source.split())
    for old, new in sorted(builder.labels_for_role(role).items(), key=lambda pair: -len(pair[0])):
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


def check(root: Path, *, effective: bool = True, portable_reader_fixture: bool = False) -> dict:
    root = Path(root).resolve()
    assert isinstance(portable_reader_fixture, bool), "Fixture mode is an explicit Boolean API option, never metadata or environment."
    reader_revision = False
    reader_helper = root / "scripts/refresh_reader_online_appendix_receipts_20261106.py"
    if reader_helper.is_file():
        spec = importlib.util.spec_from_file_location("reader_appendix_current_presentation", reader_helper)
        successor = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(successor)
        reader_revision = successor.active(root)
        if reader_revision:
            # Live sources, every omitted historical inclusion's disposition,
            # scientific blobs and current authority are checked before allowing
            # an intentionally archived panel to leave the reader-facing PDF.
            try:
                if portable_reader_fixture:
                    successor.portable_reader_checks(root)
                else:
                    successor.refresh(root)
            except Exception as error:
                raise AssertionError(str(error)) from error
    assert not portable_reader_fixture or reader_revision, "Explicit copied-fixture mode requires the reviewed reader successor."
    compressed = False
    compression_path = root / "scripts/appendix_compression_validation_20261106.py"
    if compression_path.is_file():
        spec = importlib.util.spec_from_file_location("presentation_compression", compression_path)
        compression = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(compression)
        compressed = compression.active(root)
    # The selected-version summary is available only after the full successor
    # admission above. It changes printed roles, never frozen derivative checks.
    essential = compressed and compression.role_summary(root)["version"] == 2
    def appendix_display(original, compact):
        if essential and compact == "ind_forecast_mae":
            return "tables/appendix_essential_20261106_ind_forecast_mae.tex"
        return "tables/appendix_compact_20261106_" + compact + ".tex" if compressed else original
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
            expected_words = mapped_source_words(builder, pdf_text(root / source), role)
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
    expected_names = ["Q--DESN (AL)", "Q--DESN (exAL)", "Gaussian DESN (ridge)", "MQ--DESN (AL)",
                      "MQ--DESN (exAL)", "Raw GloFAS", "Gaussian DESN (RHS)"]
    assert [row[0] for row in main_rows] == expected_names
    assert len(entries["glofas_components"]["rows"]) == 18
    assert all(row[2:] == ["---", "---", "---"] for row in entries["glofas_components"]["rows"] if row[0] == "Discrepancy")
    assert len(entries["glofas_component_priors"]["rows"]) == 24
    assert len(entries["glofas_specifications"]["rows"]) == 2
    assert len(entries["pricefm_global"]["rows"]) == 3
    builder.retained_pricefm(root)
    frequencies = (root / builder.TABLE_OUTPUTS["glofas_frequencies"][1]).read_text()
    assert "$p=0.05$" in frequencies and "$p=0.95$" in frequencies and "$q_{" not in frequencies
    priors = (root / builder.TABLE_OUTPUTS["glofas_component_priors"][1]).read_text()
    assert "Historical model & Model & Process" in priors
    assert r"$\kappa_\beta^2=10^4$ & ---" in priors and r"$\tau^2=10^4$" not in priors
    assert "Normal Ridge" not in priors and "Normal RHS/VB" not in priors
    discrepancy = pdf_text(root / builder.PDF_OUTPUTS["glofas_discrepancy"][1])
    assert "GloFAS-USGS discrepancy" in discrepancy and "log(1 + flow)" not in discrepancy
    for role in ("glofas_reference", "glofas_discrepancy", "glofas_combined"):
        assert "Normal and raw" not in pdf_text(root / builder.PDF_OUTPUTS[role][1])
    common_window = pdf_text(root / builder.PDF_OUTPUTS["glofas_common_window"][1])
    assert "(b) Q-DESN (AL)" in common_window and "(c) Gaussian DESN (ridge)" in common_window
    for role in builder.TABLE_OUTPUTS:
        if role.startswith("mq_"):
            source, output = builder.TABLE_OUTPUTS[role]
            # Captions may clarify interpretation; the full scientific table
            # body, including every numeric cell and model label, is fixed.
            if role != "mq_design":
                assert builder.table_rows((root / source).read_text()) == builder.table_rows((root / output).read_text())
    if effective:
        corrected_glofas, _ = corrected_glofas_authority(root)
        current_glofas_aliases = corrected_glofas["active_aliases"] if corrected_glofas else {}
        superseded_glofas_paths = set()
        for document, override, aliases in (("main.tex", builder.MAIN_OVERRIDE, builder.MAIN_ALIASES),
                                             ("qdesn-supplement.tex", builder.SUPP_OVERRIDE, builder.SUPP_ALIASES)):
            text = (root / document).read_text()
            assert r"\input{" + override + "}" in text, "Missing document-specific presentation override."
            current = aliases_for_document(root, document)
            for macro, path in aliases.items():
                expected_path = path
                if macro.startswith("GlofasApplicationCurrent") and macro in current_glofas_aliases:
                    expected_path = current_glofas_aliases[macro]
                    if expected_path != path:
                        superseded_glofas_paths.add(path)
                assert current.get(macro) == expected_path, "A stale later alias overrides " + macro
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
                sensitivity = appendix_display("tables/independent_train500_eval500_mcmc_figures_v1.tex", "ind_sensitivity")
                if essential:
                    assert r"\input{" + sensitivity + "}" not in supplement, "Archived sensitivity panels returned to the reader appendix."
                else:
                    assert r"\input{" + sensitivity + "}" in supplement
                main_wrapper = (root / "tables/independent_train500_eval300_mcmc_figures_v1.tex").read_text()
                assert "eval300_mcmc_forecast_check_v1.pdf" in main_wrapper
                assert "eval300_mcmc_forecast_mae_v1.pdf" not in main_wrapper, "Primary MAE must not remain in main."
                assert r"\input{" + appendix_display("tables/independent_train500_eval300_mcmc_mae_figure_v1.tex", "ind_forecast_mae") + "}" in supplement
                assert r"\input{" + appendix_display("tables/independent_forecast_calibration_figure_v1.tex", "ind_frequencies") + "}" in supplement
                assert r"\input{tables/independent_forecast_calibration_figure_v1.tex}" not in main
                calibration = json.loads((root / "tables/independent_forecast_calibration_manifest_v1.json").read_text())
                assert calibration["point_summary"] == "posterior_median"
                assert calibration["specifications"] == 36 and calibration["chains"] == 108
                assert calibration["calibration_rows"] == 72
                assert calibration["fits_launched"] == calibration["forecasts_launched"] == 0
                assert calibration["refinements_launched"] == 0
                assert calibration["uncertainty_bands"] == "none_sampling_calibration_uncertainty_not_estimated"
                for path, expected_hash in calibration["sources"].items():
                    assert digest(root / path) == expected_hash, "Calibration source mismatch: " + path
                for path, expected_hash in calibration["outputs"].items():
                    assert digest(root / "tables" / path) == expected_hash, "Calibration summary mismatch: " + path
                with (root / "tables/independent_forecast_calibration_v1.csv").open(newline="") as stream:
                    frequencies = list(csv.DictReader(stream))
                assert len(frequencies) == 72
                keys = {(r["family"], float(r["tau"]), r["model_variant"], int(r["cutoff"])) for r in frequencies}
                assert len(keys) == 72
                for row in frequencies:
                    n, hits = int(row["n_targets"]), int(row["n_hits"])
                    p, frequency = float(row["tau"]), float(row["empirical_frequency"])
                    assert n == int(row["cutoff"]) and n in (300, 500)
                    assert 0 <= hits <= n and abs(frequency - hits / n) < 1e-12, "Calibration counts/frequency disagree."
                    assert row["point_summary"] == "posterior_median" and int(row["n_chains"]) == 3
                    assert row["source_criterion"] == "forecast_check"
                    assert abs(float(row["nominal_frequency"]) - p) < 1e-12
                    assert abs(float(row["calibration_error_pp"]) - 100 * (frequency - p)) < 1e-10
                assert r"\input{" + builder.WRAPPER_OUTPUTS[role][1] + "}" not in main
                continue
            assert r"\input{" + builder.WRAPPER_OUTPUTS[role][1] + "}" in main, "Stale effective forecast wrapper: " + role
            assert r"\input{" + builder.WRAPPER_OUTPUTS[role][0] + "}" not in main, "Original effective forecast wrapper remains: " + role
        for role in ("independent_mcmc_fit", "independent_vb_fit", "mq_fit"):
            included = r"\input{" + builder.WRAPPER_OUTPUTS[role][1] + "}" in supplement
            assert included or reader_revision, "Stale effective fit wrapper: " + role
            assert r"\input{" + builder.WRAPPER_OUTPUTS[role][0] + "}" not in supplement, "Original effective fit wrapper remains: " + role
        if not compressed:
            assert r"\input{" + builder.TABLE_OUTPUTS["mq_design"][1] + "}" in supplement, "Stale effective multiquantile design table."
        assert r"\input{" + builder.TABLE_OUTPUTS["mq_design"][0] + "}" not in supplement, "Original multiquantile design remains selected."
        upload = set((root / "overleaf/article_files.txt").read_text().splitlines())
        active_entries = (entry for role, entry in entries.items()
                          if not (ind_revision and role == "independent_forecast") and
                          not (role.startswith("glofas_") and entry["file"] in superseded_glofas_paths))
        assert set(entry["file"] for entry in active_entries) | {builder.MANIFEST} <= upload, "An active derivative is absent from the upload inventory."
        if corrected_glofas:
            authority_file = "tables/glofas_hybrid_current_authority.json"
            manifest_path = corrected_glofas["asset_manifest"]["relative_path"]
            with (root / manifest_path).open(newline="") as stream:
                corrected_assets = {row["relative_path"] for row in csv.DictReader(stream)}
            assert corrected_assets | {authority_file, manifest_path} <= upload, "A current GloFAS asset is absent from the upload inventory."
    return {"status": "PASS", "source_files": len(source_rows), "outputs": len(entries),
            "pdf_outputs": len(builder.PDF_OUTPUTS), "table_outputs": len(builder.TABLE_OUTPUTS),
            "caption_wrappers": len(builder.WRAPPER_OUTPUTS), "scientific_runs": 0, "scores_recomputed": 0,
            "source_ancestry_authenticated": reader_revision and not portable_reader_fixture,
            "qualification_scope": "controlled_copied_public_fixture_only" if portable_reader_fixture else "live_source_checks"}


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
