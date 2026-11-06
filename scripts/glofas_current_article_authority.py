#!/usr/bin/env python3
"""Validate committed corrected GloFAS article authority, never runtime data.

Python 3.6 standard library. This checks an explicit recorded scientific review,
asset hashes, and effective TeX aliases. It does not grant scientific approval.
"""
import argparse
import csv
import hashlib
import io
import json
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath


AUTHORITY_PATH = "tables/glofas_same_family_current_authority.json"
PREFIX = "glofas_same_family_20261103"
ALIAS_PATH = "tables/" + PREFIX + "_display_aliases.tex"
MANIFEST_PATH = "tables/" + PREFIX + "_article_asset_manifest.csv"
DECISION_PATH = "tables/" + PREFIX + "_article_assets_decision.json"
PRODUCER_SOURCE = "fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6"
POSTERIOR_TARGET = "72ef0550393106009b100636e1b11e8c21d4da31e77ed01a3dc2663439dbef03"
EXECUTION_SOURCES = {
    "0d111e0c2bf3951378aec2bbfc1f46fd9ecd8437",
    "90309792229f98a6ad372fe6072f850f9b12deed",
}
PROBABILITIES = [.05, .20, .35, .50, .65, .80, .95]
ALIASES = {
    "GlofasApplicationCurrentScoreTable": "tables/" + PREFIX + "_main_scores.tex",
    "GlofasApplicationCurrentForecastWindowFigure": "figures/glofas_application/" + PREFIX + "_main.pdf",
    "GlofasApplicationCurrentCorrectedPathsFigure": "figures/glofas_application/" + PREFIX + "_main.pdf",
    "GlofasApplicationCurrentFullComparisonFigure": "figures/glofas_application/" + PREFIX + "_all_families.pdf",
    "GlofasApplicationCurrentCalibrationTable": "tables/" + PREFIX + "_calibration.tex",
    "GlofasApplicationCurrentCalibrationFigure": "figures/glofas_application/" + PREFIX + "_calibration.pdf",
    "GlofasApplicationCurrentConvergenceTable": "tables/" + PREFIX + "_convergence.tex",
    "GlofasApplicationCurrentConvergenceFigure": "figures/glofas_application/" + PREFIX + "_convergence.pdf",
    "GlofasApplicationCurrentIssuedSupplementScoreTable": "tables/" + PREFIX + "_full_scores.tex",
}
EXPECTED_ASSETS = set(ALIASES.values()) | {ALIAS_PATH, DECISION_PATH} | {
    "tables/" + PREFIX + "_" + name + ".csv" for name in
    ("family_metrics", "date_metrics", "calibration", "convergence", "quantile_paths",
     "fitted_history", "history", "issued_members", "observations")
}
REVIEW_FIELDS = ("all_families_retained", "adverse_results_retained",
                 "scoring_truth_used_only_postfit", "no_refit_or_retuning")
FAMILIES = ("Raw GloFAS", "Normal Ridge", "Normal RHS", "Independent AL", "Independent exAL", "MQ AL", "MQ exAL")
TEX_LABELS = ("Raw GloFAS", "Normal Ridge", "Normal RHS", "Q--DESN (AL)", "Q--DESN (exAL)",
              "MQ--DESN (AL)", "MQ--DESN (exAL)")
PRIVATE = re.compile(rb"/data/|/home/|/tmp/|local_trackers/|application/cache/|file://|"
                     rb"[A-Za-z]:\\|\.rds\b|\.rda\b|\.rdata\b|olp_", re.I)
PRIVATE_PDF_RAW = re.compile(rb"/data/|/home/|/tmp/|local_trackers/|application/cache/|file://|olp_", re.I)
INPUT = re.compile(r"\\(?:input|include)\s*\{([^{}]+)\}")
DEFINE = re.compile(r"\\(newcommand|renewcommand|providecommand)\*?\s*"
                    r"\{\s*\\(GlofasApplicationCurrent[A-Za-z]+)\s*\}\s*"
                    r"(?:\[[^\]]*\]\s*)?\{([^{}]*)\}")
ESSENTIAL_CONTRACT = "tables/appendix_essential_20261106_contract.json"
ESSENTIAL_CONTRACT_SHA = "b0bc20572044955b1fe1937ee3d3e13153c5c0dde35b0ac42c2a2f2874ede0c1"


class AuthorityError(Exception):
    pass


def require(value, message):
    if not value:
        raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: " + message)


def digest(value):
    return hashlib.sha256(value).hexdigest()


def validate_article_privacy(path, data):
    if not path.endswith(".pdf"):
        require(not PRIVATE.search(data), "private path or model payload in article asset")
        return
    # Arbitrary compressed bytes can accidentally contain a drive-letter
    # pattern. Inspect decoded page text and both ordinary and XMP metadata
    # instead; never mistake the binary stream for a textual filename.
    require(data.startswith(b"%PDF-") and not PRIVATE_PDF_RAW.search(data),
            "private path or credential marker in PDF article asset")
    outputs = []
    with tempfile.TemporaryDirectory(prefix="glofas_public_pdf_check_") as temporary:
        # pdfdetach does not support stdin in the supported Poppler release.
        # These are only the already verified public/committed PDF bytes.
        filename = str(Path(temporary) / "article.pdf")
        Path(filename).write_bytes(data)
        for command in (("/usr/bin/pdftotext", "-enc", "UTF-8", "-", "-"),
                        ("/usr/bin/pdfinfo", "-"), ("/usr/bin/pdfinfo", "-meta", "-"),
                        ("/usr/bin/pdfdetach", "-list", filename)):
            try:
                result = subprocess.run(command, input=data, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, timeout=15)
            except (OSError, subprocess.TimeoutExpired):
                raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: PDF privacy parser unavailable")
            require(result.returncode == 0 and len(result.stdout) < 4 * 1024 * 1024,
                    "PDF privacy parsing failed")
            outputs.append(result.stdout)
    require(re.fullmatch(rb"0 embedded files\s*", outputs[-1]) is not None,
            "embedded PDF files are not article-safe")
    require(not PRIVATE.search(b"\n".join(outputs)), "private path or model payload in PDF text or metadata")


def safe_path(value):
    require(isinstance(value, str) and value and "\\" not in value and ":" not in value,
            "relative article path required")
    path = PurePosixPath(value)
    require(not path.is_absolute() and all(part not in (".", "..") for part in value.split("/")) and
            str(path) == value and path.suffix.lower() in (".tex", ".csv", ".json", ".pdf", ".txt") and
            not PRIVATE.search(value.encode("utf-8")), "unsafe article path")
    return value


def strip_comments(text):
    result = []
    for line in text.splitlines():
        for index, char in enumerate(line):
            if char != "%":
                continue
            count = 0
            previous = index - 1
            while previous >= 0 and line[previous] == "\\":
                count += 1
                previous -= 1
            if count % 2 == 0:
                line = line[:index]
                break
        result.append(line)
    return "\n".join(result)


def top_level(text, position):
    depth = 0
    for match in re.finditer(r"\\.|[{}]", text[:position]):
        if match.group() == "{":
            depth += 1
        elif match.group() == "}":
            depth -= 1
            if depth < 0:
                return False
    if depth != 0:
        return False
    conditionals = 0
    for match in re.finditer(r"\\(?:if[A-Za-z@]*|fi)\b", text[:position]):
        if not top_level_braces(text, match.start()):
            continue
        if match.group() == r"\fi":
            conditionals -= 1
        elif not re.search(r"\\newif\s*$", text[:match.start()]):
            conditionals += 1
    return conditionals == 0


def top_level_braces(text, position):
    depth = 0
    for match in re.finditer(r"\\.|[{}]", text[:position]):
        if match.group() == "{":
            depth += 1
        elif match.group() == "}":
            depth -= 1
    return depth == 0


def needs_authority(documents):
    text = "\n".join(strip_comments(t) for t in documents.values())
    return ("GlofasApplicationCurrent" in text or
            (r"\label{sec:data}" in text and re.search(r"glofas", text, re.I) is not None))


class CommittedFiles:
    def __init__(self, source_commit):
        require(re.fullmatch(r"[0-9a-f]{40}", source_commit or "") is not None,
                "full source commit required")
        self.commit = source_commit
        self.cache = {}

    def command(self, args):
        try:
            return subprocess.check_output(["git", "--no-replace-objects"] + args,
                                           stderr=subprocess.PIPE)
        except (OSError, subprocess.CalledProcessError):
            raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: missing committed input")

    def read(self, path, maximum=8 * 1024 * 1024):
        safe_path(path)
        if path not in self.cache:
            entry = self.command(["ls-tree", self.commit, "--", path]).decode("utf-8")
            require(bool(re.fullmatch(r"100(?:644|755) blob [0-9a-f]{40}\t" + re.escape(path) + r"\n", entry)),
                    "committed regular file required: " + path)
            size = int(self.command(["cat-file", "-s", self.commit + ":" + path]).strip())
            require(0 < size <= maximum, "committed input size exceeds scope: " + path)
            self.cache[path] = self.command(["show", self.commit + ":" + path])
        require(0 < len(self.cache[path]) <= maximum, "committed input exceeds role limit")
        return self.cache[path]

    def text(self, path, maximum=1024 * 1024):
        try:
            return self.read(path, maximum).decode("utf-8")
        except UnicodeDecodeError:
            raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: UTF-8 article text required")


class TreeFiles:
    """The same checks for isolated source/test trees, never publication authority."""
    def __init__(self, root):
        candidate = Path(root).absolute()
        require(candidate.is_dir() and not any(path.is_symlink() for path in (candidate, *candidate.parents)),
                "regular source-tree directory required")
        self.root = candidate.resolve()
        self.cache = {}

    def file(self, path):
        safe_path(path)
        file = self.root / path
        require(file.is_file() and not any(part.is_symlink() for part in (file, *file.parents)),
                "regular source-tree file required: " + path)
        return file

    def read(self, path, maximum=8 * 1024 * 1024):
        file = self.file(path)
        require(0 < file.stat().st_size <= maximum, "source-tree input exceeds scope: " + path)
        if path not in self.cache:
            self.cache[path] = file.read_bytes()
        require(0 < len(self.cache[path]) <= maximum, "source-tree input exceeds role limit")
        return self.cache[path]

    def text(self, path, maximum=1024 * 1024):
        try:
            return self.read(path, maximum).decode("utf-8")
        except UnicodeDecodeError:
            raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: UTF-8 source-tree text required")

    def verify_stable(self):
        for path, data in self.cache.items():
            require(self.file(path).read_bytes() == data, "source-tree input changed during validation")


def json_object(raw, label):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "duplicate JSON key: " + label)
            result[key] = value
        return result
    try:
        value = json.loads(raw, object_pairs_hook=unique)
    except (ValueError, TypeError):
        raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: invalid JSON: " + label)
    require(isinstance(value, dict), "JSON object required: " + label)
    return value


def resolved_aliases(store, document, approved):
    values, origins, visits = {}, {}, []
    stack = []

    def visit(path):
        require(path not in stack and len(stack) < 24 and len(visits) < 256, "TeX input cycle or depth")
        stack.append(path)
        text = strip_comments(store.text(path))
        require(re.search(r"\\(?:def|gdef|edef|xdef|let)\s*\\GlofasApplicationCurrent|"
                          r"\\csname\s*GlofasApplicationCurrent|"
                          r"\\(?:newcommand|renewcommand|providecommand)\*?\s*\\GlofasApplicationCurrent", text) is None,
                "unsupported current alias definition")
        visits.append(path)
        events = [(m.start(), "definition", m) for m in DEFINE.finditer(text)]
        events += [(m.start(), "input", m) for m in INPUT.finditer(text)]
        for position, kind, match in sorted(events, key=lambda item: item[0]):
            visible = top_level(text, position)
            if kind == "definition":
                command, name, value = match.groups()
                if name in ALIASES:
                    require(visible, "conditional or nested current alias definition")
                    require(re.search(r"\}\s*\[", match.group()) is None,
                            "current path alias cannot take arguments")
                if visible and (command != "providecommand" or name not in values):
                    values[name] = value.strip()
                    origins[name] = path
            else:
                target = match.group(1).strip()
                if target.startswith("\\"):
                    name = target[1:]
                    if re.fullmatch(r"GlofasApplicationCurrent[A-Za-z]+", name):
                        require(name in values, "unresolved current input alias")
                        target = values[name]
                    else:
                        continue
                safe_path(target)
                if not visible:
                    require(target != approved, "approved alias input is hidden or conditional")
                    nested = strip_comments(store.text(target))
                    require(not any(m.group(2) in ALIASES for m in DEFINE.finditer(nested)),
                            "conditional input can redefine current GloFAS aliases")
                    continue
                visit(target)
        stack.pop()

    visit(document)
    require(visits.count(approved) == 1, "approved alias file must be included exactly once in " + document)
    for name, path in ALIASES.items():
        require(values.get(name) == path and origins.get(name) == approved,
                "stale effective alias in " + document + ": " + name)
    return values


def visible_use(text, pattern):
    return sum(top_level(text, match.start()) for match in re.finditer(pattern, text)) == 1


def validate_score_display(store, values):
    reader = csv.DictReader(io.StringIO(store.text("tables/" + PREFIX + "_family_metrics.csv")))
    rows = list(reader)
    require(len(rows) == 7 and {row.get("family") for row in rows} == set(FAMILIES),
            "seven distinct public family metrics required")
    records = {}
    numeric = ("grid_acrps_log1p", "mean_check_loss", "covered90_count", "coverage90_percent",
               "raw_crossing_pairs", "raw_crossing_percent", "max_positive_adjacent_violation_log1p", "n_horizons")
    for row in rows:
        try:
            record = {name: float(row[name]) for name in numeric}
        except (ValueError, TypeError, KeyError):
            raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: numeric public family metrics required")
        require(all(math.isfinite(value) for value in record.values()) and record["n_horizons"] == 28 and
                record["grid_acrps_log1p"] >= 0 and record["mean_check_loss"] >= 0 and
                record["max_positive_adjacent_violation_log1p"] >= 0 and
                record["covered90_count"] == int(record["covered90_count"]) and 0 <= record["covered90_count"] <= 28 and
                record["raw_crossing_pairs"] == int(record["raw_crossing_pairs"]) and 0 <= record["raw_crossing_pairs"] <= 168 and
                abs(record["coverage90_percent"] - 100 * record["covered90_count"] / 28) < 1e-10 and
                abs(record["raw_crossing_percent"] - 100 * record["raw_crossing_pairs"] / 168) < 1e-10,
                "public metric denominators or finite values differ")
        records[row["family"]] = record
    main_lines = {" ".join(line.split()) for line in store.text(ALIASES["GlofasApplicationCurrentScoreTable"]).splitlines()}
    full_lines = {" ".join(line.split()) for line in store.text(ALIASES["GlofasApplicationCurrentIssuedSupplementScoreTable"]).splitlines()}
    for name in ("GlofasApplicationCurrentScoreTable", "GlofasApplicationCurrentIssuedSupplementScoreTable"):
        data_lines = [line for line in strip_comments(store.text(ALIASES[name])).splitlines()
                      if "&" in line and not line.strip().startswith("Model &")]
        require(len(data_lines) == 7, "score display must contain exactly seven model rows")
    for family, label in zip(FAMILIES, TEX_LABELS):
        r = records[family]
        main_row = ("{} & {:.4f} & {}/28 ({:.1f}\\%) & {:.2f} \\\\".format(label,
            r["grid_acrps_log1p"], int(r["covered90_count"]), r["coverage90_percent"], r["raw_crossing_percent"]))
        full_row = ("{} & {:.4f} & {:.4f} & {}/28 & {:.2f} & {:.4f} \\\\".format(label,
            r["grid_acrps_log1p"], r["mean_check_loss"], int(r["covered90_count"]),
            r["raw_crossing_percent"], r["max_positive_adjacent_violation_log1p"]))
        require(main_row in main_lines and full_row in full_lines, "displayed score row differs from public metrics: " + family)
    for macro, family, field in (
            ("GlofasApplicationCurrentNormalRidgeAcrps", "Normal Ridge", "grid_acrps_log1p"),
            ("GlofasApplicationCurrentNormalRhsAcrps", "Normal RHS", "grid_acrps_log1p"),
            ("GlofasApplicationCurrentQdesnAcrps", "Independent AL", "grid_acrps_log1p"),
            ("GlofasApplicationCurrentRawAcrps", "Raw GloFAS", "grid_acrps_log1p"),
            ("GlofasApplicationCurrentQdesnCheckLoss", "Independent AL", "mean_check_loss"),
            ("GlofasApplicationCurrentRawCheckLoss", "Raw GloFAS", "mean_check_loss")):
        for aliases in values.values():
            try:
                value = float(aliases.get(macro, ""))
            except ValueError:
                raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: numeric current alias required")
            require(math.isfinite(value) and abs(value - records[family][field]) <= .000050000001,
                    "current numerical alias differs from metrics: " + macro)


def validate_compact_supplement_scores(store, supplement):
    """Presentation successor: only duplicate columns leave the reader table.

    Original full-score bytes and every authority/asset check remain required.
    This separate check authenticates the ACTUALLY selected compact values,
    including all seven families, against the approved public metrics.
    Compatible with both committed publication and ordinary source-tree stores.
    """
    path = "tables/appendix_compact_20261106_glofas_diagnostics.tex"
    require(visible_use(supplement, r"\\input\s*\{" + re.escape(path) + r"\}"),
            "supplement must display the corrected full-family scores or exact compact diagnostic successor")
    text = strip_comments(store.text(path))
    require(r"\begin{tabular}{@{}lrr@{}}" in text and
            "Model & Mean check loss & Max. violation" in text,
            "compact score diagnostic schema differs")
    data_lines = [" ".join(line.split()) for line in text.splitlines()
                  if "&" in line and not line.strip().startswith("Model &")]
    rows = list(csv.DictReader(io.StringIO(store.text("tables/" + PREFIX + "_family_metrics.csv"))))
    require(len(data_lines) == 7 and len(rows) == 7 and {r.get("family") for r in rows} == set(FAMILIES),
            "compact diagnostics must retain exactly seven distinct families")
    labels = dict(zip(FAMILIES, ("Raw GloFAS", "Gaussian DESN (ridge)", "Gaussian DESN (RHS)",
        "Q--DESN (AL)", "Q--DESN (exAL)", "MQ--DESN (AL)", "MQ--DESN (exAL)")))
    expected = []
    for row in rows:
        try:
            loss = float(row["mean_check_loss"])
            violation = float(row["max_positive_adjacent_violation_log1p"])
        except (KeyError, TypeError, ValueError):
            raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: numeric compact diagnostic source required")
        require(math.isfinite(loss) and math.isfinite(violation) and loss >= 0 and violation >= 0,
                "finite nonnegative compact diagnostics required")
        expected.append("{} & {:.4f} & {:.4f} \\\\".format(labels[row["family"]], loss, violation))
    require(data_lines == expected, "compact diagnostic values/family order differ from approved metrics")


def essential_requested(supplement):
    # The marker is an actual selected new caption, not an approval comment.
    return "appendix_essential_20261106_" in strip_comments(supplement)


def validate_essential_supplement(store, supplement):
    """Independent Python-3.6 admission of the reduced reader presentation.

    This grants no new scientific approval. All original assets/score values
    still pass _validate_authority. The new branch verifies the actual retained
    seven-family figure and 49 calibration values, and source-keyed adverse
    numerical prose rather than trusting an editorial flag.
    """
    raw = store.read(ESSENTIAL_CONTRACT, 128 * 1024)
    require(digest(raw) == ESSENTIAL_CONTRACT_SHA, "unknown essential-layout contract")
    contract = json_object(raw.decode("utf-8"), "essential layout")
    require(contract.get("schema") == "appendix-essential-v2" and
            contract.get("baseline_commit") == "1b249255018715dd3bdc3c95389c80702d26c8c9" and
            contract.get("variant") == "default-full-32-cell-sensitivity", "partial essential-layout contract")
    require(visible_use(supplement, r"\\input\s*\{\\GlofasApplicationCurrentCalibrationTable\}") and
            visible_use(supplement, r"\\includegraphics(?:\[[^\]]*\])?\s*\{\\GlofasApplicationCurrentFullComparisonFigure\}"),
            "essential appendix must actually retain calibration and all-family figure")
    require(not re.search(r"\\input\s*\{(?:tables/appendix_compact_20261106_glofas_diagnostics\.tex|"
                          r"\\GlofasApplicationCurrentIssuedSupplementScoreTable)\}", supplement),
            "essential appendix unexpectedly selects archived duplicate diagnostics")
    calibration = list(csv.DictReader(io.StringIO(store.text("tables/" + PREFIX + "_calibration.csv"))))
    records = {}
    for row in calibration:
        try:
            key = row["family"], float(row["tau"])
            value = float(row["empirical_coverage"])
            n = int(row["n_horizons"])
        except (KeyError, TypeError, ValueError):
            raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: calibration source schema")
        require(key not in records and key[0] in FAMILIES and key[1] in PROBABILITIES and
                n == 28 and math.isfinite(value) and 0 <= value <= 1,
                "exact distinct family-level calibration keys required")
        records[key] = value
    require(set(records) == {(f,p) for f in FAMILIES for p in PROBABILITIES},
            "all 49 calibration values required")
    text = strip_comments(store.text(ALIASES["GlofasApplicationCurrentCalibrationTable"]))
    rows = [" ".join(line.split()) for line in text.splitlines() if "&" in line and not line.strip().startswith("Model &")]
    expected = [label + " & " + " & ".join("{:.3f}".format(records[(family,p)]) for p in PROBABILITIES) + r" \\"
                for family,label in zip(FAMILIES,TEX_LABELS)]
    require(rows == expected, "actual retained calibration family/level values differ")
    raw_prose = strip_comments(supplement)
    prose = re.sub(r"\s+", " ", raw_prose)
    gain = [re.sub(r"\s+"," ",m.group()) for m in re.finditer(
        r"The\s+reference\s+and\s+discrepancy\s+components\s+use\s+input\s+multipliers.*?with\s+bias\s+multiplier[^.]*\.",
        raw_prose,re.S) if top_level(raw_prose,m.start())]
    expected_gain = "The reference and discrepancy components use input multipliers 0.5 and 0.35, respectively, with bias multiplier one."
    require(gain == [expected_gain],
            "G01 local executed reference/discrepancy/global/bias roles differ")
    metrics = {r["family"]: r for r in csv.DictReader(io.StringIO(store.text("tables/" + PREFIX + "_family_metrics.csv")))}
    paths = list(csv.DictReader(io.StringIO(store.text("tables/" + PREFIX + "_quantile_paths.csv"))))
    negative = {}
    for family in FAMILIES:
        selected = [r for r in paths if r.get("family") == family]
        require(len(selected) == 196 and len({(r.get("horizon"),r.get("tau")) for r in selected}) == 196,
                "complete distinct quantile paths required for support prose")
        try:
            values = [float(r["quantile"]) for r in selected]
        except (ValueError, KeyError, TypeError):
            raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: numerical quantile paths required")
        require(all(math.isfinite(v) for v in values), "finite public quantile paths required")
        negative[family] = sum(v < 0 for v in values)
    def sequence(field):
        try:
            numbers = [int(metrics[f][field]) for f in FAMILIES[3:]]
        except (ValueError, KeyError, TypeError):
            raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: support/crossing source schema")
        return numbers
    def present(numbers, prefix, suffix):
        expression = r"\b" + r",\s*".join(str(v) for v in numbers[:3]) + r"(?:,?\s+and\s+|,\s*)" + str(numbers[3]) + r"\b"
        pattern = prefix.replace(" ",r"\s+") + r"\s*" + expression + r"\s*" + suffix.replace(" ",r"\s+")
        return any(top_level(raw_prose,m.start()) for m in re.finditer(pattern,raw_prose,re.I))
    require(present(sequence("inverted_intervals"),r"inverted on",r"dates") and
            present(sequence("raw_crossing_pairs"),r"crossing counts are",r"among 168 comparisons") and
            present([negative[f] for f in FAMILIES[3:]],r"families have",r"negative flow quantiles among 196"),
            "retained numerical inversion/crossing/support prose differs from sources")
    violation = float(metrics["Independent AL"]["max_positive_adjacent_violation_log1p"])
    require("{:.4f}".format(violation) in prose and "negative" in prose.lower() and
            "no clipping, truncation or ordering repair is applied" in prose.lower() and "respectively" in prose.lower(),
            "retained maximum violation or physical-support interpretation absent")


def _validate_authority(store):
    authority_raw = store.read(AUTHORITY_PATH, 1024 * 1024)
    require(not PRIVATE.search(authority_raw), "private information in authority contract")
    authority = json_object(authority_raw.decode("utf-8"), "authority")
    require(authority.get("schema_version") == "glofas_same_family_current_article_authority_v1" and
            authority.get("status") == "SCIENTIFIC_REVIEW_APPROVED", "explicit scientific review required")
    require(authority.get("producer_source_commit") == PRODUCER_SOURCE and
            authority.get("posterior_target_sha256") == POSTERIOR_TARGET and
            authority.get("execution_source_commit") in EXECUTION_SOURCES,
            "unapproved producer, target or execution source")
    require(authority.get("forecast_rows") == 1372 and authority.get("families") == 7 and
            authority.get("horizons") == 28 and authority.get("probabilities") == PROBABILITIES,
            "complete corrected forecast surface required")
    require(re.fullmatch(r"[0-9a-f]{64}", authority.get("scored_packet_manifest_sha256", "")) is not None,
            "scored-packet manifest hash required")
    review = authority.get("scientific_review", {})
    require(isinstance(review, dict) and all(review.get(key) is True for key in REVIEW_FIELDS),
            "complete-packet scientific review flags required")
    manifest_pin = authority.get("asset_manifest", {})
    require(isinstance(manifest_pin, dict) and manifest_pin.get("relative_path") == MANIFEST_PATH and
            re.fullmatch(r"[0-9a-f]{64}", manifest_pin.get("sha256", "")) is not None,
            "namespaced asset manifest pin required")
    manifest_raw = store.read(MANIFEST_PATH, 1024 * 1024)
    require(digest(manifest_raw) == manifest_pin["sha256"] and not PRIVATE.search(manifest_raw),
            "asset manifest differs from authority")
    reader = csv.DictReader(io.StringIO(manifest_raw.decode("utf-8")))
    require(reader.fieldnames == ["relative_path", "size_bytes", "sha256"], "asset manifest schema")
    entries = list(reader)
    require(len(entries) == len(EXPECTED_ASSETS) and
            {entry.get("relative_path") for entry in entries} == EXPECTED_ASSETS,
            "exact corrected article asset membership required")
    total = 0
    for entry in entries:
        require(set(entry) == {"relative_path", "size_bytes", "sha256"}, "asset manifest row schema")
        path = safe_path(entry["relative_path"])
        require(re.fullmatch(r"[1-9][0-9]*", entry.get("size_bytes", "")) is not None and
                re.fullmatch(r"[0-9a-f]{64}", entry.get("sha256", "")) is not None, "asset pin schema")
        data = store.read(path)
        require(len(data) == int(entry["size_bytes"]) and digest(data) == entry["sha256"], "asset bytes differ: " + path)
        validate_article_privacy(path, data)
        total += len(data)
    require(total < 16 * 1024 * 1024, "article asset surface exceeds budget")
    require(authority.get("alias_file") == ALIAS_PATH and authority.get("active_aliases") == ALIASES,
            "complete approved alias mapping required")
    decision = json_object(store.text(DECISION_PATH), "asset decision")
    lineage = decision.get("lineage", {})
    require(isinstance(lineage, dict), "asset lineage object required")
    science = lineage.get("scientific_source", {}) if isinstance(lineage, dict) else {}
    require(decision.get("schema_version") == "glofas_same_family_article_assets_v1" and
            decision.get("status") == "COMPLETE_ARTICLE_ASSET_CANDIDATE_NOT_AUTHORITY" and
            science.get("source_commit") == PRODUCER_SOURCE and science.get("posterior_target_sha256") == POSTERIOR_TARGET and
            lineage.get("packet_manifest_sha256") == authority["scored_packet_manifest_sha256"],
            "asset decision lineage differs from reviewed packet")
    require(decision.get("forecast_rows") == 1372 and decision.get("models") == 7 and
            decision.get("probabilities") == PROBABILITIES and decision.get("historical_fitted_rows") == 1260 and
            decision.get("issued_member_rows") == 1428 and decision.get("history_rows") == 30 and decision.get("truth_rows") == 28 and
            all(decision.get(key) is False for key in ("isotonic_adjustment", "clipping_or_smoothing",
                "added_credible_ribbons", "extra_response_noise_added", "article_publication_authorized")) and
            decision.get("new_fits") == 0, "asset functional or complete surface differs")
    values = {}
    for document in ("main.tex", "qdesn-supplement.tex"):
        values[document] = resolved_aliases(store, document, ALIAS_PATH)
    main = strip_comments(store.text("main.tex"))
    supp = strip_comments(store.text("qdesn-supplement.tex"))
    require(visible_use(main, r"\\input\s*\{\\GlofasApplicationCurrentScoreTable\}") and
            visible_use(main, r"\\includegraphics(?:\[[^\]]*\])?\s*\{\\GlofasApplicationCurrentForecastWindowFigure\}"),
            "main must display the approved current score table and figure")
    if essential_requested(supp):
        validate_essential_supplement(store, supp)
    elif not visible_use(supp, r"\\input\s*\{\\GlofasApplicationCurrentIssuedSupplementScoreTable\}"):
        validate_compact_supplement_scores(store, supp)
    for name in ("GlofasApplicationCurrentOriginDate", "GlofasApplicationCurrentScoredHorizons"):
        expected = "25 December 2022" if name.endswith("OriginDate") else "28"
        require(all(v.get(name) == expected for v in values.values()), "origin or horizon reporting differs")
    validate_score_display(store, values)
    if hasattr(store, "verify_stable"):
        store.verify_stable()
    return authority


def validate_authority(source_commit):
    """Publication path: all bytes are read from one immutable Git commit."""
    return _validate_authority(CommittedFiles(source_commit))


def validate_authority_tree(root):
    """Source/test-tree verification only; not a replacement for committed checks."""
    return _validate_authority(TreeFiles(root))


def authority_dependency_paths(root):
    """Validated public asset and literal TeX-input closure for isolated tests."""
    store = TreeFiles(root)
    _validate_authority(store)
    return set(store.cache) | {"scripts/glofas_current_article_authority.py"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_commit")
    args = parser.parse_args()
    try:
        validate_authority(args.source_commit)
    except (AuthorityError, ValueError, KeyError, UnicodeDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print("GLOFAS_CURRENT_ARTICLE_AUTHORITY_VERIFIED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
