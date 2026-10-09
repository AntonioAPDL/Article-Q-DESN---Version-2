#!/usr/bin/env python3
"""Build and check presentation-only derivatives of six frozen GloFAS PDFs.

No model, design matrix, runtime object, or scoring source is read. Original
PDF graphics are composed without redrawing scientific marks; the complete
original wording is reset at readable sizes. Original assets remain untouched.

Reproduction environment: Python >= 3.9, PyMuPDF == 1.26.5, and the two pinned
URW NimbusSans OpenType fonts listed below (Debian/Ubuntu fonts-urw-base35).
Install PyMuPDF in an isolated environment with:
    python -m pip install PyMuPDF==1.26.5
Build: python scripts/build_glofas_review_figures.py
Check: python scripts/build_glofas_review_figures.py --check

The checker rebuilds all PDFs in a fresh temporary directory, verifies frozen
source hashes, vector coverage, complete wording, absence of raster/clipping,
minimum effective font size, deterministic bytes, manifest, and TeX overrides.
It never refreshes scientific fits or replaces the frozen publication manifest.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import tempfile

import fitz

PINS = {
    "part1": "6adbb89c9a6be85db3343028d5a9574d728e259c2238f7a659f09b39af7d9676",
    "part2": "2da731c935784a59d37778cbd654a937f0e80a248fe71570d0c3fa6cfc219ec9",
    "part3": "12d9ec7ee4fdbcf191ec18b942af525d723f37da9337fd85c6e9ba723a3646bb",
    "part4": "1c6b2421ecb05b455a75d00852fc638f2325156e5aa440cb32ea1bf5d5f99de9",
    "convergence": "9891d8917571b5ade6cf7b5069c2f56054b88e4c5024a3e551c2ce56b595b064",
    "calibration": "7474879101d262b8e10079e0f310dcda259f2316a66fc8ef006c061527b38b2f",
}
FONT = "/usr/share/fonts/urw-base35/NimbusSans-Regular.otf"
BOLD = "/usr/share/fonts/urw-base35/NimbusSans-Bold.otf"
SIZE = 9.0
WIDTH = 468.0
FRAGMENTS = []
PYMUPDF_VERSION = "1.26.5"
FONT_PINS = {
    FONT: "7c25be4d78155523080ab85b10277150657ff7dabbcad7037bdd536c9b6d0d08",
    BOLD: "7f33328e6b4d4cd21b45fa625791928c9407dc702db6780e56b09ca9a3ecaa67",
}
ROLES = tuple(PINS)
DISPLAY_WIDTH_TEX_PT = .94 * 468.0
DISPLAY_WIDTH_BP = DISPLAY_WIDTH_TEX_PT * 72.0 / 72.27
MINIMUM_EFFECTIVE_POINTS = 8.0
MANIFEST = Path("tables/glofas_review_figure_manifest.json")
OVERRIDES = Path("tables/glofas_review_figure_overrides.tex")
FIGURE_DIR = Path("figures/glofas_application")
MACRO_ROLES = {
    "GlofasApplicationCurrentForecastWindowFigure": "part4",
    "GlofasApplicationCurrentCorrectedPathsFigure": "part4",
    "GlofasApplicationCurrentPartOneFigure": "part1",
    "GlofasApplicationCurrentPartTwoFigure": "part2",
    "GlofasApplicationCurrentPartThreeFigure": "part3",
    "GlofasApplicationCurrentConvergenceFigure": "convergence",
    "GlofasApplicationCurrentCalibrationFigure": "calibration",
}


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def canon(x):
    if isinstance(x, (fitz.Point, fitz.Rect)):
        return [round(float(v), 5) for v in x]
    if isinstance(x, float):
        return round(x, 5)
    if isinstance(x, dict):
        return {k: canon(v) for k, v in x.items() if k not in {"seqno", "level"}}
    if isinstance(x, (tuple, list)):
        return [canon(v) for v in x]
    return x


def drawing_hash(p):
    return hashlib.sha256(json.dumps(canon(p.get_drawings()), sort_keys=True).encode()).hexdigest()


def texts(p):
    result = []
    for block in p.get_text("dict")["blocks"]:
        for line in block.get("lines", []):
            for span in line["spans"]:
                result.append({**span, "dir": line["dir"]})
    return result


def strip_text(doc):
    page = doc[0]
    before = drawing_hash(page)
    spans = texts(page)
    for span in spans:
        page.add_redact_annot(fitz.Rect(span["bbox"]), fill=False, cross_out=False)
    page.apply_redactions(images=0, graphics=0, text=0)
    after = drawing_hash(page)
    assert before == after, "Text removal changed a vector path/style."
    assert not page.get_text().strip(), "Text removal was incomplete."
    return spans, before


def install_fonts(page):
    page.insert_font(fontname="regular", fontfile=FONT)
    page.insert_font(fontname="bold", fontfile=BOLD)


def text(page, value, x, y, size=SIZE, align="left", bold=False, bounds=None):
    name = "bold" if bold else "regular"
    font = fitz.Font(fontfile=BOLD if bold else FONT)
    w = font.text_length(value, fontsize=size)
    if align == "center":
        x -= w / 2
    elif align == "right":
        x -= w
    if bounds:
        x = max(bounds[0], min(x, bounds[1] - w))
    page.insert_text((x, y), value, fontsize=size, fontname=name, color=(0, 0, 0))


def single_header(page, spans):
    title = next(s for s in spans if s["size"] >= 12 and s["bbox"][1] < 20)
    text(page, title["text"], 8, 14, size=11, bold=True)
    subtitle = next(s for s in spans if 18 < s["bbox"][1] < 33)
    ret = page.insert_textbox(fitz.Rect(8, 20, WIDTH - 8, 50), subtitle["text"], fontname="regular", fontsize=SIZE)
    assert ret >= 0, "Subtitle exceeds reserved space."


def show_fragment(page, doc, clip, dest):
    FRAGMENTS.append({"source_clip": list(fitz.Rect(clip)), "destination": list(fitz.Rect(dest))})
    page.show_pdf_page(fitz.Rect(dest), doc, 0, clip=fitz.Rect(clip), keep_proportion=True)


def three_panels(doc, spans):
    output = fitz.open()
    page = output.new_page(width=WIDTH, height=423)
    install_fonts(page)
    single_header(page, spans)
    # Each entire plotting panel is affine-composed, preserving original curves.
    clips = [fitz.Rect(0, 33, 373, 310), fitz.Rect(373, 33, 732, 310), fitz.Rect(732, 33, 1120, 310)]
    positions = [(12, 55), (250, 55), (12, 245)]
    common_scale = .56
    for i, (clip, position) in enumerate(zip(clips, positions)):
        scale = common_scale
        dest = fitz.Rect(position[0], position[1], position[0] + clip.width * scale, position[1] + clip.height * scale)
        show_fragment(page, doc, clip, dest)
        for s in spans:
            box = fitz.Rect(s["bbox"])
            cx, cy = (box.x0 + box.x1) / 2, (box.y0 + box.y1) / 2
            if not (33 <= cy <= 310) or s["dir"] != (1.0, 0.0):
                continue
            is_tick_x = box.y0 > 290
            # The last x-label extends into the next source panel. Assign by its
            # tick centre, not by the full text box, then align edge labels inward.
            owner = 0 if cx < 373 else 1 if cx < 732 else 2
            if owner != i:
                continue
            x = dest.x0 + (cx - clip.x0) * scale
            y = dest.y0 + (cy - clip.y0) * scale + SIZE * .35
            if is_tick_x:
                y += 5
            right = min(WIDTH - 1, dest.x1 + (15 if is_tick_x else 0))
            text(page, s["text"], x, y, bold="quantiles" in s["text"] or s["text"] == "Normal and raw", align="center", bounds=(dest.x0, right))
        if i == 0:
            label = next(s for s in spans if s["dir"] == (0.0, -1.0))["text"]
            length = fitz.Font(fontfile=FONT).text_length(label, fontsize=SIZE)
            center_y = dest.y0 + (171 - clip.y0) * scale
            page.insert_text((14, center_y + length / 2), label, fontname="regular", fontsize=SIZE, rotate=90)
    legend(page, doc, spans, x=250, y=250)
    return output


def legend(page, doc, spans, x, y):
    quantile = [s for s in spans if s["bbox"][1] > 310 and re.fullmatch(r"0\.\d\d", s["text"])]
    model_names = {"Independent AL", "Independent exAL", "Joint AL", "Joint exAL", "Normal RHS/VB", "Normal Ridge", "Raw GloFAS"}
    models = [s for s in spans if s["bbox"][1] > 310 and s["text"] in model_names]
    text(page, "Quantile", x, y + 9, bold=True)
    quantile = sorted(quantile, key=lambda s: float(s["text"]))
    for j, s in enumerate(quantile):
        lx = x + (j % 4) * 50
        ly = y + 25 + (j // 4) * 18
        b = fitz.Rect(s["bbox"])
        # Preserve the exact existing vector legend swatch, including color.
        key = fitz.Rect(b.x0 - 21, b.y0 - 3, b.x0 - 4.5, b.y1 + 3)
        show_fragment(page, doc, key, fitz.Rect(lx, ly - 8, lx + 16.5, ly + 6))
        text(page, s["text"], lx + 20, ly + 2)
    text(page, "Model", x, y + 73, bold=True)
    # Keep the existing model labels and exact original dash swatches.
    models = sorted(models, key=lambda s: (s["bbox"][0], s["bbox"][1]))
    for j, s in enumerate(models):
        lx = x + (j % 2) * 103
        ly = y + 90 + (j // 2) * 19
        b = fitz.Rect(s["bbox"])
        key = fitz.Rect(b.x0 - 21, b.y0 - 3, b.x0 - 4.5, b.y1 + 3)
        show_fragment(page, doc, key, fitz.Rect(lx, ly - 8, lx + 16.5, ly + 6))
        text(page, s["text"], lx + 20, ly + 2)


def single_chart(doc, spans, role):
    output = fitz.open()
    page = output.new_page(width=WIDTH, height=281 if role == "convergence" else 277)
    install_fonts(page)
    single_header(page, spans)
    clip = fitz.Rect(40, 37, 1094, 357) if role == "convergence" else fitz.Rect(29, 37, 1094, 337)
    scale = (WIDTH - 57) / clip.width
    dest = fitz.Rect(57, 60, WIDTH, 60 + clip.height * scale)
    show_fragment(page, doc, clip, dest)
    for s in spans:
        box = fitz.Rect(s["bbox"])
        cx, cy = (box.x0 + box.x1) / 2, (box.y0 + box.y1) / 2
        if s["dir"] != (1., 0.) or not re.fullmatch(r"(?:[0-9.]+|[0-9]e-[0-9]+)", s["text"]):
            continue
        if box.x0 < clip.x0:
            text(page, s["text"], 50, dest.y0 + (cy - clip.y0) * scale + SIZE * .35, align="right")
        elif box.y0 > clip.y1 - 2:
            x = dest.x0 + (cx - clip.x0) * scale
            text(page, s["text"], x, dest.y1 + 13, align="center", bounds=(57, WIDTH - 2))
    ylabel = next(s for s in spans if s["dir"] == (0., -1.))["text"]
    # A two-line axis title preserves the complete wording while avoiding a
    # cramped vertical label in the compact convergence panel.
    labels = ["Maximum relative", "parameter change"] if role == "convergence" else [ylabel]
    for i, label in enumerate(labels):
        length = fitz.Font(fontfile=FONT).text_length(label, fontsize=SIZE)
        page.insert_text((10 + i * 11, (dest.y0 + dest.y1) / 2 + length / 2), label, fontname="regular", fontsize=SIZE, rotate=90)
    xlabel = next(s for s in spans if s["text"] in {"Cumulative outer iteration", "Nominal quantile"})["text"]
    text(page, xlabel, (57 + WIDTH) / 2, dest.y1 + 31, align="center")
    if role == "calibration":
        text(page, "Model", 30, 228, bold=True)
        names = {"Independent AL", "Independent exAL", "Joint AL", "Joint exAL", "Normal RHS/VB", "Normal Ridge", "Raw GloFAS"}
        entries = sorted([s for s in spans if s["text"] in names], key=lambda s: (s["bbox"][0], s["bbox"][1]))
        for j, s in enumerate(entries):
            x, y = 30 + (j % 4) * 108, 244 + (j // 4) * 19
            b = fitz.Rect(s["bbox"])
            key = fitz.Rect(b.x0 - 24, b.y0 - 4, b.x0 - 4, b.y1 + 4)
            show_fragment(page, doc, key, fitz.Rect(x, y - 8, x + 17, y + 8))
            text(page, s["text"], x + 21, y + 2)
    else:
        for j, name in enumerate(["Joint AL", "Joint exAL"]):
            s = next(s for s in spans if s["text"] == name)
            b = fitz.Rect(s["bbox"])
            x, y = 120 + j * 110, 244
            key = fitz.Rect(b.x0 - 24, b.y0 - 4, b.x0 - 4, b.y1 + 4)
            show_fragment(page, doc, key, fitz.Rect(x, y - 8, x + 17, y + 8))
            text(page, name, x + 21, y + 2)
        text(page, "Full-state pass", 112, 267)
        for j, name in enumerate(["FALSE", "TRUE"]):
            s = next(s for s in spans if s["text"] == name)
            b = fitz.Rect(s["bbox"])
            x, y = 200 + j * 81, 265
            key = fitz.Rect(b.x0 - 24, b.y0 - 4, b.x0 - 4, b.y1 + 4)
            show_fragment(page, doc, key, fitz.Rect(x, y - 8, x + 17, y + 8))
            text(page, name, x + 21, y + 2)
    return output


def tokens(spans):
    return Counter(re.findall(r"\S+", " ".join(s["text"] for s in spans)))


def vector_coverage(page):
    """Every visible nonwhite source path must lie in a composed source clip.

    Original PDF clipping is taken into account, e.g. the calibration diagonal
    extends mathematically outside the panel but is clipped there in the source.
    The only omitted vectors are redundant white page/legend backgrounds.
    """
    active = {}
    count = 0
    for drawing in page.get_drawings(extended=True):
        level = drawing.get("level", 0)
        active = {k: v for k, v in active.items() if k < level}
        if drawing["type"] == "clip":
            active[level] = fitz.Rect(drawing["scissor"])
            continue
        if drawing["type"] == "group":
            continue
        colors = [c for c in (drawing.get("color"), drawing.get("fill")) if c is not None]
        if all(all(v > .999 for v in c) for c in colors):
            continue
        r = fitz.Rect(drawing["rect"])
        # Thin straight paths have zero-width/height bounding rectangles.
        r = fitz.Rect(r.x0 - .001, r.y0 - .001, r.x1 + .001, r.y1 + .001)
        for clip in active.values():
            r.intersect(clip)
        if r.is_empty:
            continue
        matching = []
        for j, fragment in enumerate(FRAGMENTS):
            c = fitz.Rect(fragment["source_clip"])
            c = fitz.Rect(c.x0 - .02, c.y0 - .02, c.x1 + .02, c.y1 + .02)
            if c.contains(r):
                matching.append(j)
        assert matching, f"Visible vector not covered by a composition: {r}, {drawing}"
        count += 1
    return count


def output_path(role):
    return FIGURE_DIR / f"glofas_search3_review_20261008_{role}.pdf"


def override_text(root=None):
    lines = [
        "% Presentation-only overrides; load after glofas_application_current_outputs.tex.",
        "% Frozen scientific outputs, scores, and original figure hashes remain unchanged.",
    ]
    for macro, role in MACRO_ROLES.items():
        lines.append("\\renewcommand{\\" + macro + "}{" + output_path(role).as_posix() + "}")
    # The later PRO-review main figure has new authenticated plotting inputs.
    # Keep the original full-family derivative separately available; do not
    # replace scientific source files or the CorrectedPaths alias globally.
    root = Path(root or Path(__file__).resolve().parents[1])
    if (root / "tables/qdesn_pro_review_presentation_manifest.json").is_file():
        lines.extend([
            "\\renewcommand{\\GlofasApplicationCurrentForecastWindowFigure}{figures/glofas_application/glofas_search3_part4_three_panel_review.pdf}",
            "\\providecommand{\\GlofasApplicationCurrentFullComparisonFigure}{figures/glofas_application/glofas_search3_review_20261008_part4.pdf}",
            "\\renewcommand{\\GlofasApplicationCurrentScoreTable}{tables/glofas_search3_part4_main_scores_review.tex}",
        ])
    return "\n".join(lines) + "\n"


def manifest_bytes(manifest):
    return (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()


def verify_environment():
    assert fitz.VersionBind == PYMUPDF_VERSION, f"Requires PyMuPDF {PYMUPDF_VERSION}; found {fitz.VersionBind}."
    for font, expected in FONT_PINS.items():
        assert Path(font).is_file(), f"Required URW NimbusSans font missing: {Path(font).name}."
        assert sha(font) == expected, f"Pinned font hash mismatch: {Path(font).name}."


def render_figures(root, output_root):
    reports = []
    for role in ROLES:
        source_relative = FIGURE_DIR / f"glofas_search3_part1234_final_20261007_{role}.pdf"
        source = root / source_relative
        assert sha(source) == PINS[role], "Original PDF hash mismatch."
        doc = fitz.open(source)
        assert len(doc) == 1, "Unexpected source page count."
        spans, path_hash = strip_text(doc)
        FRAGMENTS.clear()
        out = three_panels(doc, spans) if role.startswith("part") else single_chart(doc, spans, role)
        preserved_count = vector_coverage(doc[0])
        relative = output_path(role)
        dest = output_root / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        out.save(dest, garbage=4, deflate=True, no_new_id=True)
        proof = fitz.open(dest)
        output_spans = texts(proof[0])
        missing = tokens(spans) - tokens(output_spans)
        extra = tokens(output_spans) - tokens(spans)
        assert not missing and not extra, f"Text mismatch: missing{missing},extra{extra}"
        assert min(s["size"] for s in output_spans) >= SIZE - 1e-4
        expanded_page = fitz.Rect(-.1, -.1, proof[0].rect.width + .1, proof[0].rect.height + .1)
        assert all(expanded_page.contains(fitz.Rect(s["bbox"])) for s in output_spans), "A retyped label is clipped."
        assert not proof[0].get_images(), "The display derivative contains raster images."
        minimum_native = min(s["size"] for s in output_spans)
        minimum_effective = minimum_native * DISPLAY_WIDTH_BP / proof[0].rect.width
        assert minimum_effective >= MINIMUM_EFFECTIVE_POINTS, "An effective manuscript label is below 8 bp."
        text_hash = hashlib.sha256(json.dumps(sorted(tokens(spans).items())).encode()).hexdigest()
        reports.append({
            "role": role,
            "source": source_relative.as_posix(),
            "source_sha256": PINS[role],
            "original_vector_path_hash": path_hash,
            "vector_paths_identical_after_text_removal": True,
            "visible_nonwhite_source_paths_covered": preserved_count,
            "composition_fragments": FRAGMENTS.copy(),
            "output": relative.as_posix(),
            "output_sha256": sha(dest),
            "minimum_native_label_bp": minimum_native,
            "minimum_effective_label_bp": minimum_effective,
            "dimensions_bp": list(proof[0].rect),
            "all_source_text_tokens_retained": True,
            "source_text_token_multiset_sha256": text_hash,
            "all_labels_inside_page": True,
            "raster_images": 0,
        })
        proof.close()
        out.close()
        doc.close()
        assert sha(source) == PINS[role], "Original PDF was altered."
    return {
        "schema": "glofas-presentation-only-vector-derivatives-v1",
        "purpose": "Readable manuscript presentation; no scientific authority or score changes.",
        "generator": "scripts/build_glofas_review_figures.py",
        "generator_sha256": sha(Path(__file__)),
        "pymupdf_version": PYMUPDF_VERSION,
        "fonts": {Path(path).name: expected for path, expected in FONT_PINS.items()},
        "effective_width_tex_pt": DISPLAY_WIDTH_TEX_PT,
        "effective_width_bp": DISPLAY_WIDTH_BP,
        "required_minimum_effective_label_bp": MINIMUM_EFFECTIVE_POINTS,
        "omitted_graphics": "Redundant pure-white backgrounds only; all visible nonwhite source paths retained.",
        "assets": reports,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="Rebuild in a fresh temporary directory and verify, without repository writes.")
    args = parser.parse_args()
    root = args.root.resolve()
    verify_environment()
    if args.check:
        with tempfile.TemporaryDirectory(prefix="qdesn-glofas-vector-check-") as temporary:
            temporary_root = Path(temporary)
            manifest = render_figures(root, temporary_root)
            assert (root / MANIFEST).read_bytes() == manifest_bytes(manifest), "Presentation manifest differs from a fresh deterministic rebuild."
            assert (root / OVERRIDES).read_text() == override_text(root), "TeX presentation overrides differ from the generated contract."
            for asset in manifest["assets"]:
                relative = Path(asset["output"])
                assert sha(root / relative) == asset["output_sha256"], "Published derivative hash differs from manifest."
                assert (root / relative).read_bytes() == (temporary_root / relative).read_bytes(), "Derivative does not reproduce byte-for-byte."
        status = "PASS"
    else:
        manifest = render_figures(root, root)
        (root / MANIFEST).write_bytes(manifest_bytes(manifest))
        (root / OVERRIDES).write_text(override_text(root))
        status = "BUILT"
    print(json.dumps({"status": status, "figures": len(manifest["assets"]), "minimum_effective_label_bp": min(asset["minimum_effective_label_bp"] for asset in manifest["assets"]), "runtime_or_model_inputs_read": 0}, sort_keys=True))


if __name__ == "__main__":
    main()
