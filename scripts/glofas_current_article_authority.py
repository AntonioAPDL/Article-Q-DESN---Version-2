#!/usr/bin/env python3
"""Validate the committed GloFAS hybrid article authority.

The guard admits Search III Parts 1--3 unchanged and the qualified October
Part 4 target. It validates committed public assets and manuscript wiring;
it never reads model-runtime objects or grants approval to another target.
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
from pathlib import Path, PurePosixPath


PREFIX = "glofas_hybrid_part123_search3_part4_october_20261107"
AUTHORITY_PATH = "tables/glofas_hybrid_current_authority.json"
ALIAS_PATH = "tables/" + PREFIX + "_display_aliases.tex"
MANIFEST_PATH = "tables/" + PREFIX + "_article_asset_manifest.csv"
REJECTED_ALIAS = "tables/glofas_same_family_20261103_display_aliases.tex"
PROBABILITIES = (0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95)
FAMILIES = (
    "Independent AL", "Independent exAL", "MQ AL", "MQ exAL",
    "Normal RHS/VB", "Normal Ridge", "Raw GloFAS",
)
EXPECTED_ASSETS = {
    "figures/glofas_application/" + PREFIX + suffix for suffix in (
        "_part4_all_families.pdf", "_part4_calibration.pdf",
        "_part4_main.pdf", "_part4_numerical_gates.pdf",
    )
} | {
    "tables/" + PREFIX + suffix for suffix in (
        "_display_aliases.tex", "_history.csv", "_issued_members.csv",
        "_observations.csv", "_part4_calibration.csv",
        "_part4_calibration.tex", "_part4_numerical_gate_summary.csv",
        "_part4_numerical_gates.csv", "_part4_numerical_gates.tex",
        "_part4_quantile_paths.csv", "_part4_scores.csv",
        "_part4_scores.tex",
    )
}
ALIASES = {
    "GlofasApplicationCurrentScoreTable": "tables/" + PREFIX + "_part4_scores.tex",
    "GlofasApplicationCurrentForecastWindowFigure":
        "figures/glofas_application/" + PREFIX + "_part4_main.pdf",
    "GlofasApplicationCurrentCorrectedPathsFigure":
        "figures/glofas_application/" + PREFIX + "_part4_main.pdf",
    "GlofasApplicationCurrentFullComparisonFigure":
        "figures/glofas_application/" + PREFIX + "_part4_all_families.pdf",
    "GlofasApplicationCurrentCalibrationTable":
        "tables/" + PREFIX + "_part4_calibration.tex",
    "GlofasApplicationCurrentCalibrationFigure":
        "figures/glofas_application/" + PREFIX + "_part4_calibration.pdf",
    "GlofasApplicationCurrentConvergenceTable":
        "tables/" + PREFIX + "_part4_numerical_gates.tex",
    "GlofasApplicationCurrentConvergenceFigure":
        "figures/glofas_application/" + PREFIX + "_part4_numerical_gates.pdf",
}
REVIEW_FIELDS = (
    "search3_parts123_unchanged", "part4_corrected_target_qualified",
    "scoring_truth_used_only_postfit", "protected_window_not_used_for_selection",
    "no_refit_or_retuning_during_handoff",
    "november_target_excluded_from_active_authority",
)
PRIVATE = re.compile(
    rb"/data/|/home/|/tmp/|local_trackers/|application/cache/|file://|"
    rb"\.rds\b|\.rda\b|\.rdata\b|BEGIN [A-Z ]*PRIVATE KEY", re.I)
DEFINE = re.compile(
    r"\\(?:renewcommand|providecommand|newcommand)\*?\s*"
    r"\{\s*\\(GlofasApplicationCurrent[A-Za-z]+)\s*\}\s*\{([^{}]*)\}")


class AuthorityError(Exception):
    pass


def require(value, message):
    if not value:
        raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: " + message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_path(value):
    require(isinstance(value, str) and value and "\\" not in value and ":" not in value,
            "relative article path required")
    path = PurePosixPath(value)
    require(not path.is_absolute() and str(path) == value and
            all(part not in ("", ".", "..") for part in path.parts),
            "unsafe article path")
    return value


def top_level_braces(text, position):
    depth = 0
    for match in re.finditer(r"\\.|[{}]", text[:position]):
        if match.group() == "{":
            depth += 1
        elif match.group() == "}":
            depth -= 1
    return depth == 0


def top_level(text, position):
    """Return whether a TeX token is visible at document top level."""
    if not top_level_braces(text, position):
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


class CommittedFiles:
    def __init__(self, commit):
        require(re.fullmatch(r"[0-9a-f]{40}", commit or "") is not None,
                "full source commit required")
        self.commit = commit
        self.cache = {}

    def read(self, path, maximum=8 * 1024 * 1024):
        safe_path(path)
        if path not in self.cache:
            try:
                data = subprocess.check_output(
                    ["git", "--no-replace-objects", "show", self.commit + ":" + path],
                    stderr=subprocess.PIPE)
            except (OSError, subprocess.CalledProcessError):
                raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: missing committed input: " + path)
            require(0 < len(data) <= maximum, "committed input exceeds role limit: " + path)
            self.cache[path] = data
        return self.cache[path]

    def text(self, path, maximum=1024 * 1024):
        try:
            return self.read(path, maximum).decode("utf-8")
        except UnicodeDecodeError:
            raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: UTF-8 text required: " + path)


class TreeFiles:
    def __init__(self, root):
        self.root = Path(root).resolve()
        require(self.root.is_dir(), "source-tree directory required")
        self.cache = {}

    def read(self, path, maximum=8 * 1024 * 1024):
        safe_path(path)
        file = self.root / path
        require(file.is_file() and not file.is_symlink(), "regular source-tree file required: " + path)
        data = file.read_bytes()
        require(0 < len(data) <= maximum, "source-tree input exceeds role limit: " + path)
        self.cache[path] = data
        return data

    def text(self, path, maximum=1024 * 1024):
        try:
            return self.read(path, maximum).decode("utf-8")
        except UnicodeDecodeError:
            raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: UTF-8 text required: " + path)


def json_object(text, label):
    try:
        value = json.loads(text)
    except (TypeError, ValueError):
        raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: invalid JSON: " + label)
    require(isinstance(value, dict), "JSON object required: " + label)
    return value


def validate_manifest(store, authority):
    pin = authority.get("asset_manifest", {})
    require(isinstance(pin, dict) and pin.get("relative_path") == MANIFEST_PATH and
            re.fullmatch(r"[0-9a-f]{64}", pin.get("sha256", "")),
            "asset-manifest pin required")
    raw = store.read(MANIFEST_PATH)
    require(digest(raw) == pin["sha256"], "asset manifest hash differs")
    reader = csv.DictReader(io.StringIO(raw.decode("utf-8")))
    require(reader.fieldnames == ["relative_path", "size_bytes", "sha256"],
            "asset manifest schema differs")
    rows = list(reader)
    require(len(rows) == len(EXPECTED_ASSETS) and
            {row.get("relative_path") for row in rows} == EXPECTED_ASSETS,
            "exact hybrid asset membership required")
    for row in rows:
        path = safe_path(row["relative_path"])
        data = store.read(path)
        require(str(len(data)) == row.get("size_bytes") and digest(data) == row.get("sha256"),
                "asset bytes differ: " + path)
        require(not PRIVATE.search(data), "private/runtime payload in article asset: " + path)


def macro_values(text):
    values = {}
    for name, value in DEFINE.findall(text):
        values[name] = value.strip()
    return values


def validate_wiring(store):
    values = macro_values(store.text(ALIAS_PATH))
    for name, expected in ALIASES.items():
        require(values.get(name) == expected, "current alias differs: " + name)
    require(values.get("GlofasApplicationCurrentOriginDate") == "25 December 2022" and
            values.get("GlofasApplicationCurrentScoredHorizons") == "28",
            "origin or horizon alias differs")
    for document in ("main.tex", "qdesn-supplement.tex"):
        text = store.text(document)
        require(text.count(r"\input{" + ALIAS_PATH + "}") == 1,
                "hybrid alias must be active exactly once: " + document)
        require(REJECTED_ALIAS not in text, "rejected November alias remains active: " + document)
    main = store.text("main.tex")
    supplement = store.text("qdesn-supplement.tex")
    for marker in (
            r"\vect y_F\mid D_T&\sim\Normal(\vect m_N,\mat C_N)",
            "500 truth-free recursive trajectories", "It replaces, rather than multiplies",
            "used only for scoring", "did not select the corrected target"):
        require(marker in main, "corrected main-text contract missing: " + marker)
    for marker in (r"R_T(\vect y_{F,k})", r"\mat C_N^{-1}",
                   r"n_Y=12{,}455", "All 18 are marked converged"):
        require(marker in supplement, "corrected supplement contract missing: " + marker)
    rejected = (r"m_{p,h}+\Phi^{-1}(p)\sqrt{V_{p,hh}}",
                "No Gaussian future-path prior replaces this distribution",
                r"n_Y=12{,}455+28=12{,}483")
    require(not any(value in main + supplement for value in rejected),
            "rejected November target language remains active")
    return values


def float_field(row, name):
    try:
        value = float(row[name])
    except (KeyError, TypeError, ValueError):
        raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: numeric field required: " + name)
    require(math.isfinite(value), "finite field required: " + name)
    return value


def validate_scores(store, aliases):
    rows = list(csv.DictReader(io.StringIO(
        store.text("tables/" + PREFIX + "_part4_scores.csv"))))
    require(len(rows) == 7 and tuple(row.get("family") for row in rows) == FAMILIES,
            "seven ordered Part 4 families required")
    records = {}
    for row in rows:
        family = row["family"]
        require(row.get("numerical_status") == "numerical_gate_pass" and
                int(row.get("n_scored_horizons", 0)) == 28,
                "family numerical status or horizon count differs: " + family)
        record = {"loss": float_field(row, "mean_check_loss"),
                  "acrps": float_field(row, "crps_grid_log1p"),
                  "coverage": float_field(row, "coverage90"),
                  "crossings": int(row["crossing_pairs"]),
                  "reduction": float_field(row, "crps_reduction_vs_raw")}
        require(record["loss"] >= 0 and record["acrps"] >= 0 and
                0 <= record["coverage"] <= 1 and 0 <= record["crossings"] <= 168,
                "invalid family metric: " + family)
        records[family] = record
    table = {" ".join(line.split()) for line in
             store.text(ALIASES["GlofasApplicationCurrentScoreTable"]).splitlines()}
    for family in FAMILIES:
        record = records[family]
        reduction = "--" if family == "Raw GloFAS" else \
            "{:.1f}\\%".format(100 * record["reduction"])
        expected = "{} & {:.4f} & {:.4f} & {:.3f} & {} & {} \\\\".format(
            family, record["loss"], record["acrps"], record["coverage"],
            record["crossings"], reduction)
        require(expected in table, "displayed score row differs: " + family)
    numeric_aliases = {
        "GlofasApplicationCurrentQdesnAcrps": ("Independent AL", "acrps"),
        "GlofasApplicationCurrentRawAcrps": ("Raw GloFAS", "acrps"),
        "GlofasApplicationCurrentNormalRidgeAcrps": ("Normal Ridge", "acrps"),
        "GlofasApplicationCurrentNormalRhsAcrps": ("Normal RHS/VB", "acrps"),
    }
    for name, (family, field) in numeric_aliases.items():
        try:
            value = float(aliases[name])
        except (KeyError, ValueError):
            raise AuthorityError("GLOFAS_CURRENT_AUTHORITY_INVALID: numeric alias required: " + name)
        require(abs(value - records[family][field]) <= 0.000050000001,
                "numeric alias differs: " + name)

    path_rows = list(csv.DictReader(io.StringIO(
        store.text("tables/" + PREFIX + "_part4_quantile_paths.csv"))))
    keys = {(row.get("family"), int(row.get("horizon", 0)),
             float_field(row, "quantile_level")) for row in path_rows}
    require(len(path_rows) == 7 * 28 * 7 and len(keys) == len(path_rows) and
            {key[0] for key in keys} == set(FAMILIES) and
            {key[1] for key in keys} == set(range(1, 29)) and
            {key[2] for key in keys} == set(PROBABILITIES),
            "complete distinct 7-family forecast surface required")

    gates = list(csv.DictReader(io.StringIO(
        store.text("tables/" + PREFIX + "_part4_numerical_gates.csv"))))
    require(len(gates) == 18 and all(row.get("recorded_converged") == "TRUE" and
            row.get("strict_numerical_gate") == "TRUE" and
            row.get("quadrature_pass") == "TRUE" for row in gates),
            "all 18 frozen numerical gates must pass")


def _validate_authority(store):
    authority = json_object(store.text(AUTHORITY_PATH), "authority")
    require(authority.get("schema_version") == "glofas_hybrid_current_article_authority_v1" and
            authority.get("status") == "SCIENTIFIC_REVIEW_APPROVED" and
            authority.get("authority_tag") == PREFIX,
            "explicit hybrid scientific review required")
    require(authority.get("reviewed_base_commit") ==
            "82a8e70b1306aa2f36cf67ac8da65e6052df2c91" and
            authority.get("search3_part123_source_commit") ==
            "e2a3be97853b1af9c8cb269a3e065336ca5590f3" and
            authority.get("part4_source_commit") ==
            "60daab261d52eec0ae24060babe186d618303e2b" and
            authority.get("part4_path_prior_sha256") ==
            "0202bc19e26d84d6cbb55c2256a2071695f9c386c9dc64933005bd4d5acbb357",
            "reviewed source lineage differs")
    require(authority.get("families") == 7 and authority.get("part4_fit_units") == 18 and
            authority.get("horizons") == 28 and authority.get("issued_members") == 51 and
            authority.get("issued_member_factors") == 1428 and
            authority.get("driver_paths") == 500 and
            tuple(authority.get("probabilities", ())) == PROBABILITIES,
            "hybrid scientific cardinalities differ")
    review = authority.get("scientific_review", {})
    require(isinstance(review, dict) and all(review.get(field) is True for field in REVIEW_FIELDS),
            "complete hybrid scientific-review flags required")
    validate_manifest(store, authority)
    aliases = validate_wiring(store)
    validate_scores(store, aliases)
    # Editorial adapters historically consume this derived map.  Keep it out
    # of the signed JSON contract while exposing the validated effective
    # aliases to callers.
    authority["active_aliases"] = dict(ALIASES)
    return authority


def validate_authority(source_commit):
    return _validate_authority(CommittedFiles(source_commit))


def validate_authority_tree(root):
    return _validate_authority(TreeFiles(root))


def authority_dependency_paths(root):
    store = TreeFiles(root)
    _validate_authority(store)
    return set(store.cache) | {"scripts/glofas_current_article_authority.py"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_commit")
    args = parser.parse_args()
    try:
        validate_authority(args.source_commit)
    except (AuthorityError, KeyError, TypeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print("GLOFAS_CURRENT_ARTICLE_AUTHORITY_VERIFIED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
