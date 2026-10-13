#!/usr/bin/env python3
"""Deterministic MQ–DESN display overlays for the frozen GloFAS authority.

Only model names change. Original scientific PDFs, tables, numerical summaries,
historical review assets, fonts, and the common-window main figure are retained.
The frozen renderer supplies vector composition; exact label mappings are read
from the shared display registry. No model, forecast, score, or runtime is built.

Build: python scripts/build_glofas_mq_review_figures.py
Check: python scripts/build_glofas_mq_review_figures.py --check
Use the existing Python 3.11 / PyMuPDF 1.26.5 proof environment.
"""
from __future__ import annotations

import argparse
from collections import Counter
from contextlib import contextmanager
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile

import fitz


REGISTRY = Path("tables/qdesn_model_display_names.csv")
MANIFEST = Path("tables/glofas_mq_presentation_manifest.json")
OVERRIDES = Path("tables/glofas_mq_display_overrides.tex")
FROZEN_RENDERER = Path("scripts/build_glofas_review_figures.py")
FROZEN_MANIFEST = Path("tables/glofas_search3_part1234_final_20261007_publication_manifest.csv")
HISTORICAL_MANIFEST = Path("tables/glofas_review_figure_manifest.json")
FIGURE_DIR = Path("figures/glofas_application")
ROLES = ("part1", "part2", "part3", "part4", "convergence", "calibration")
FIXED_PINS = {
    FROZEN_RENDERER.as_posix(): "e55d0d93563e0f6f01fea9237be65b1c47fa046994be5a987e8b09877753df73",
    FROZEN_MANIFEST.as_posix(): "5a7ac4fc1b35f3e7b19c4535e5e5c1cc56c4dfe87927b42f6f66122d49a01335",
    HISTORICAL_MANIFEST.as_posix(): "d94628b473cf8481e61a62273b83b126c5e0a4017003cc05bb423d5ea55c25c5",
    "tables/glofas_review_figure_overrides.tex": "427386e5551fe52579846059886cc8fb5dd4064119777ca6f73627460e557f28",
    "tables/glofas_figure4_common_window_outputs.tex": "9f6e8b3fe9b70daff6ee63ee355ca346c6cca5d714d2cd9f4b9eae30562bea38",
    "tables/glofas_figure4_common_window_manifest.json": "af9ef008903f5fc571803d75c322ada07ca3d691a2ff9cc83a3b5041012992f8",
    "figures/glofas_application/glofas_search3_part4_common_window_three_panel_review.pdf": "ff6e818e317a31b211be6ee247e45aa0826d42cbaee141cfae6902d8143f021f",
    "tables/glofas_search3_part4_main_scores_review.tex": "8ac73bdaee93bcc51246d139e9a430e72dbb834db1ae3ab292e1ebae5209753a",
}
TABLE_SOURCES = {
    "calibration": "tables/glofas_search3_part1234_final_20261007_calibration.tex",
    "convergence": "tables/glofas_search3_part1234_final_20261007_convergence.tex",
    "part123_prior_settings": "tables/glofas_search3_part1234_final_20261007_part123_prior_settings.tex",
    "part123_scores": "tables/glofas_search3_part1234_final_20261007_part123_scores.tex",
    "prior_settings": "tables/glofas_search3_part1234_final_20261007_prior_settings.tex",
    "main_scores": "tables/glofas_search3_part4_main_scores_review.tex",
}
TABLE_ROW_COUNTS = dict(calibration=7, convergence=2, part123_prior_settings=24,
                        part123_scores=18, prior_settings=7, main_scores=7)
FIGURE_MACROS = {
    "GlofasApplicationCurrentFullComparisonFigure": "part4",
    "GlofasApplicationCurrentPartOneFigure": "part1",
    "GlofasApplicationCurrentPartTwoFigure": "part2",
    "GlofasApplicationCurrentPartThreeFigure": "part3",
    "GlofasApplicationCurrentConvergenceFigure": "convergence",
    "GlofasApplicationCurrentCalibrationFigure": "calibration",
}
TABLE_MACROS = {
    "GlofasApplicationCurrentScoreTable": "main_scores",
    "GlofasApplicationCurrentSupplementScoreTable": "part123_scores",
    "GlofasApplicationCurrentCalibrationTable": "calibration",
    "GlofasApplicationCurrentConvergenceTable": "convergence",
    "GlofasApplicationCurrentPriorSettingsTable": "prior_settings",
    "GlofasApplicationCurrentPartOneTwoThreePriorSettingsTable": "part123_prior_settings",
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def registry_rows(path: Path) -> dict[str, dict[str, str]]:
    with path.open(newline="") as stream:
        rows = [row for row in csv.DictReader(stream) if row["context"] == "glofas"]
    expected = {
        "Joint AL": ("MQ-DESN", "joint", "AL"),
        "Joint exAL": ("MQ-DESN", "joint", "exAL"),
        "Independent AL": ("Q-DESN", "independent", "AL"),
        "Independent exAL": ("Q-DESN", "independent", "exAL"),
    }
    assert len(rows) == 4 and {row["source_key"] for row in rows} == set(expected), \
        "Require each of the four authentic GloFAS quantile-family keys exactly once."
    result = {row["source_key"]: row for row in rows}
    for key, (model, structure, family) in expected.items():
        row = result[key]
        assert (row["model_family"], row["fit_structure"], row["likelihood_family"]) == \
            (model, structure, family), "Display registry changes the model/family assignment."
        assert row["display_text"] == f"{model} ({family})", "Unexpected plain-text model name."
        assert row["display_tex"] == f"{model.replace('-', '--')} ({family})", \
            "Unexpected TeX model name."
    return result


def label_mapping(rows: dict[str, dict[str, str]]) -> dict[str, str]:
    mapping = {key: row["display_text"] for key, row in rows.items()}
    mapping.update({
        "Independent quantiles": rows["Independent AL"]["model_family"] + " quantiles",
        "Joint quantiles": rows["Joint AL"]["model_family"] + " quantiles",
        "Part 4 corrected joint-model convergence": "Part 4 corrected " +
            rows["Joint AL"]["model_family"] + " convergence",
        "Last 30 observed dates and 28 issued horizons. Joint AL and exAL use the strict corrected terminal fits.":
            "Last 30 observed dates and 28 issued horizons. " +
            rows["Joint AL"]["display_text"] + " and " + rows["Joint exAL"]["display_text"] +
            " use the strict corrected terminal fits.",
    })
    return mapping


def replace_tex_labels(source: str, rows: dict[str, dict[str, str]]) -> str:
    pattern = r"(?<![\w])(?:" + "|".join(re.escape(key) for key in sorted(rows, key=len, reverse=True)) + r")(?![\w])"
    return re.sub(pattern, lambda match: rows[match[0]]["display_tex"], source)


def restore_tex_labels(source: str, rows: dict[str, dict[str, str]]) -> str:
    reverse = {row["display_tex"]: key for key, row in rows.items()}
    pattern = "|".join(re.escape(key) for key in sorted(reverse, key=len, reverse=True))
    return re.sub(pattern, lambda match: reverse[match[0]], source)


def numeric_tokens(spans: list[dict]) -> Counter:
    return Counter(re.findall(r"(?<![A-Za-z])[+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?",
                              " ".join(span["text"] for span in spans)))


def token_hash(counter: Counter) -> str:
    return hashlib.sha256(json.dumps(sorted(counter.items())).encode()).hexdigest()


def figure_output(role: str) -> Path:
    return FIGURE_DIR / f"glofas_search3_mq_review_20261013_{role}.pdf"


def table_output(role: str) -> Path:
    return Path("tables") / f"glofas_search3_mq_{role}.tex"


def load_renderer(root: Path):
    path = root / FROZEN_RENDERER
    assert sha(path) == FIXED_PINS[FROZEN_RENDERER.as_posix()], "Frozen renderer changed."
    spec = importlib.util.spec_from_file_location("glofas_frozen_vector_renderer", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.verify_environment()
    return module


def protected_sources(root: Path) -> list[dict[str, str]]:
    pins = dict(FIXED_PINS)
    for relative, expected in FIXED_PINS.items():
        assert sha(root / relative) == expected, "Protected source changed: " + relative
    with (root / FROZEN_MANIFEST).open(newline="") as stream:
        for row in csv.DictReader(stream):
            relative = row["relative_path"]
            assert relative not in pins or pins[relative] == row["sha256"]
            pins[relative] = row["sha256"]
            assert (root / relative).stat().st_size == int(row["size_bytes"]), \
                "Frozen source size changed: " + relative
    historical = json.loads((root / HISTORICAL_MANIFEST).read_text())
    for asset in historical["assets"]:
        pins[asset["output"]] = asset["output_sha256"]
    for relative, expected in sorted(pins.items()):
        assert sha(root / relative) == expected, "Protected source changed: " + relative
    return [{"file": relative, "sha256": expected} for relative, expected in sorted(pins.items())]


@contextmanager
def mapped_renderer(renderer, mapping: dict[str, str]):
    original_text = renderer.text
    original_header = renderer.single_header

    def mapped_text(page, value, *args, **kwargs):
        return original_text(page, mapping.get(value, value), *args, **kwargs)

    def mapped_header(page, spans):
        title = next(span for span in spans if span["size"] >= 12 and span["bbox"][1] < 20)
        mapped_text(page, title["text"], 8, 14, size=11, bold=True)
        subtitle = next(span for span in spans if 18 < span["bbox"][1] < 33)
        ret = page.insert_textbox(fitz.Rect(8, 20, renderer.WIDTH - 8, 50),
                                 mapping.get(subtitle["text"], subtitle["text"]),
                                 fontname="regular", fontsize=renderer.SIZE)
        assert ret >= 0, "Mapped subtitle exceeds the unchanged reserved space."

    renderer.text = mapped_text
    renderer.single_header = mapped_header
    try:
        yield
    finally:
        renderer.text = original_text
        renderer.single_header = original_header


def render_figures(root: Path, output_root: Path, renderer, rows) -> list[dict]:
    mapping = label_mapping(rows)
    reports = []
    with mapped_renderer(renderer, mapping):
        for role in ROLES:
            source_relative = FIGURE_DIR / f"glofas_search3_part1234_final_20261007_{role}.pdf"
            source = root / source_relative
            assert sha(source) == renderer.PINS[role], "Original scientific PDF hash mismatch."
            with fitz.open(source) as doc:
                assert len(doc) == 1, "Unexpected original page count."
                spans, path_hash = renderer.strip_text(doc)
                # These are exact whole-span mappings. A new unclassified label
                # must be reviewed, not silently omitted or broadly replaced.
                for span in spans:
                    assert not re.search(r"(?:Joint|Independent) (?:exAL|AL|quantiles)", span["text"]) or \
                        span["text"] in mapping, "Unclassified source model-label span."
                expected_spans = [{**span, "text": mapping.get(span["text"], span["text"])} for span in spans]
                renderer.FRAGMENTS.clear()
                out = renderer.three_panels(doc, spans) if role.startswith("part") else \
                    renderer.single_chart(doc, spans, role)
                covered = renderer.vector_coverage(doc[0])
                relative = figure_output(role)
                destination = output_root / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                out.save(destination, garbage=4, deflate=True, no_new_id=True)
                out.close()
                with fitz.open(destination) as proof:
                    output_spans = renderer.texts(proof[0])
                    expected_tokens = renderer.tokens(expected_spans)
                    observed_tokens = renderer.tokens(output_spans)
                    assert expected_tokens == observed_tokens, \
                        f"Exact mapped token multiset differs: {role}; missing={expected_tokens-observed_tokens}, extra={observed_tokens-expected_tokens}."
                    assert numeric_tokens(spans) == numeric_tokens(output_spans), "Numerical PDF text changed."
                    bounds = fitz.Rect(-.1, -.1, proof[0].rect.width + .1, proof[0].rect.height + .1)
                    assert all(bounds.contains(fitz.Rect(span["bbox"])) for span in output_spans), "Mapped text is clipped."
                    assert not proof[0].get_images(), "Raster content entered the vector derivative."
                    minimum_native = min(span["size"] for span in output_spans)
                    effective = minimum_native * renderer.DISPLAY_WIDTH_BP / proof[0].rect.width
                    assert minimum_native >= renderer.SIZE - 1e-4 and effective >= renderer.MINIMUM_EFFECTIVE_POINTS
                    historical_relative = renderer.output_path(role)
                    with fitz.open(root / historical_relative) as historical:
                        historical_hash = renderer.drawing_hash(historical[0])
                    output_hash = renderer.drawing_hash(proof[0])
                    assert output_hash == historical_hash, "Numerical vector geometry/style changed relative to historical review."
                    if role == "part3":
                        assert "Part 3: joint historical USGS forecast" in proof[0].get_text(), \
                            "Historical source-coupling title was incorrectly renamed."
                    reports.append({
                        "role": role, "source": source_relative.as_posix(), "source_sha256": renderer.PINS[role],
                        "historical_review": historical_relative.as_posix(), "historical_review_sha256": sha(root / historical_relative),
                        "output": relative.as_posix(), "output_sha256": sha(destination),
                        "original_vector_path_hash": path_hash, "output_vector_path_hash": output_hash,
                        "historical_review_vector_path_hash": historical_hash,
                        "vector_paths_identical_after_text_removal": True,
                        "visible_nonwhite_source_paths_covered": covered,
                        "composition_fragments": renderer.FRAGMENTS.copy(),
                        "exact_mapped_text_tokens_retained": True,
                        "source_text_token_multiset_sha256": token_hash(renderer.tokens(spans)),
                        "mapped_text_token_multiset_sha256": token_hash(expected_tokens),
                        "numeric_token_multiset_unchanged": True,
                        "minimum_native_label_bp": minimum_native, "minimum_effective_label_bp": effective,
                        "dimensions_bp": list(proof[0].rect), "raster_images": 0, "all_labels_inside_page": True,
                    })
    return reports


def render_tables(root: Path, output_root: Path, rows) -> list[dict]:
    reports = []
    for role, source_relative in TABLE_SOURCES.items():
        source = (root / source_relative).read_text()
        derivative = replace_tex_labels(source, rows)
        assert restore_tex_labels(derivative, rows) == source, "Non-label TeX content changed."
        body = source.split("\\midrule", 1)[1].split("\\bottomrule", 1)[0]
        data_rows = [line for line in body.splitlines() if " & " in line]
        assert len(data_rows) == TABLE_ROW_COUNTS[role], "Authentic table row count changed."
        relative = table_output(role)
        destination = output_root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(derivative)
        reports.append({"role": role, "source": source_relative, "source_sha256": sha(root / source_relative),
                        "output": relative.as_posix(), "output_sha256": sha(destination),
                        "numeric_cells_unchanged": True, "all_non_label_bytes_unchanged": True,
                        "source_row_count": len(data_rows)})
    return reports


def override_text(root: Path, rows) -> str:
    lines = ["% MQ-DESN display-only overrides; load after the existing GloFAS overrides.",
             "% Scientific aliases and the common-window main figure are preserved."]
    for macro, role in FIGURE_MACROS.items():
        lines.append("\\renewcommand{\\" + macro + "}{" + figure_output(role).as_posix() + "}")
    for macro, role in TABLE_MACROS.items():
        lines.append("\\renewcommand{\\" + macro + "}{" + table_output(role).as_posix() + "}")
    original_aliases = (root / "tables/glofas_application_current_outputs.tex").read_text()
    for macro in ("GlofasApplicationCurrentNumericalStatus", "GlofasApplicationCurrentVbIterations"):
        match = re.search(r"\\newcommand\{\\" + re.escape(macro) + r"\}\{([^\n]*)\}", original_aliases)
        assert match, "Required combined text macro missing."
        lines.append("\\renewcommand{\\" + macro + "}{" + replace_tex_labels(match[1], rows) + "}")
    result = "\n".join(lines) + "\n"
    assert "GlofasApplicationCurrentForecastWindowFigure" not in result, "Main common-window figure must not be overridden."
    return result


def build(root: Path, output_root: Path) -> dict:
    before = protected_sources(root)
    renderer = load_renderer(root)
    rows = registry_rows(root / REGISTRY)
    assets = render_figures(root, output_root, renderer, rows)
    tables = render_tables(root, output_root, rows)
    overrides = output_root / OVERRIDES
    overrides.parent.mkdir(parents=True, exist_ok=True)
    overrides.write_text(override_text(root, rows))
    assert protected_sources(root) == before, "An original or unrelated figure/table changed during generation."
    manifest = {
        "schema": "glofas-mq-presentation-overlay-v1",
        "purpose": "Model-name presentation derivatives only; scientific targets, fits, scores and source assets unchanged.",
        "generator": "scripts/build_glofas_mq_review_figures.py", "generator_sha256": sha(Path(__file__)),
        "registry": REGISTRY.as_posix(), "registry_sha256": sha(root / REGISTRY),
        "frozen_renderer": FROZEN_RENDERER.as_posix(), "frozen_renderer_sha256": FIXED_PINS[FROZEN_RENDERER.as_posix()],
        "pymupdf_version": renderer.PYMUPDF_VERSION,
        "fonts": {Path(path).name: expected for path, expected in renderer.FONT_PINS.items()},
        "effective_width_tex_pt": renderer.DISPLAY_WIDTH_TEX_PT, "effective_width_bp": renderer.DISPLAY_WIDTH_BP,
        "required_minimum_effective_label_bp": renderer.MINIMUM_EFFECTIVE_POINTS,
        "exact_span_label_mapping": label_mapping(rows), "protected_sources": before,
        "assets": assets, "table_assets": tables,
        "overrides": {"file": OVERRIDES.as_posix(), "sha256": sha(overrides)},
        "scientific_computation": {"new_model_runs": 0, "scores_recomputed": 0, "runtime_payloads_read": 0},
    }
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="Rebuild temporary derivatives and verify without repository writes.")
    args = parser.parse_args()
    root = args.root.resolve()
    if args.check:
        with tempfile.TemporaryDirectory(prefix="qdesn-glofas-mq-proof-") as temporary:
            manifest = build(root, Path(temporary))
            assert (root / MANIFEST).read_bytes() == json_bytes(manifest), "MQ presentation manifest differs from deterministic proof."
            relatives = [Path(asset["output"]) for asset in manifest["assets"] + manifest["table_assets"]] + [OVERRIDES]
            for relative in relatives:
                assert (root / relative).read_bytes() == (Path(temporary) / relative).read_bytes(), \
                    "MQ derivative does not reproduce byte-for-byte: " + relative.as_posix()
        status = "PASS"
    else:
        manifest = build(root, root)
        (root / MANIFEST).write_bytes(json_bytes(manifest))
        status = "BUILT"
    print("GLOFAS_MQ_PRESENTATION_CHECK=" + status)
    print(json.dumps({"status": status, "figures": len(manifest["assets"]), "tables": len(manifest["table_assets"]),
                      "protected_sources": len(manifest["protected_sources"]),
                      "minimum_effective_label_bp": min(asset["minimum_effective_label_bp"] for asset in manifest["assets"]),
                      "new_model_runs": 0, "scores_recomputed": 0}, sort_keys=True))


if __name__ == "__main__":
    main()
