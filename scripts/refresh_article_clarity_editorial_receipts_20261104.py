#!/usr/bin/env python3.11
"""Authenticate the C01--C11 general editorial revision, never scientific work.

This successor preserves both historical IND and GloFAS refresh records. Its
only writes are the shared document receipt and the presentation receipt for
one exact m_x -> m_z header change. Retained public source, CSV and PDF bytes
are hashed, not recomputed. No runtime object is deserialized, scientific
calculation is performed, or remote or job is invoked by this helper.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
BASELINE = "e63bce30ab8cf70b9c3fc3d1c56418502c955c38"
RECEIPT = "tables/independent_forecast_300_500_article_manifest_v1.json"
RECEIPT_SHA = "6e1566d6441b2255fefd43563ead0ee74dc49b1c1d3fe9c80585739138035ee9"
PRESENTATION = "tables/qdesn_sections5_7_presentation_manifest.json"
PRESENTATION_SHA = "187e44af42e8daf79ddd7baeb6c26954e6d08acd0f40f37f465758742a75385b"
DISPLAY = "tables/glofas_selected_specifications_display.tex"
GENERATOR = "scripts/build_qdesn_sections5_7_presentation.py"
REFRESHER = "scripts/refresh_article_clarity_editorial_receipts_20261104.py"
FIELD = "general_editorial_source_refresh"
MUTABLE = ("main.tex", "qdesn-supplement.tex")
HISTORICAL = ("editorial_source_refresh", "glofas_article_source_refresh")
SHA256 = re.compile(r"^[a-f0-9]{64}$")
OLD_GENERATOR_LINE = 'line = line.replace("llrrrrrrrl", "lrrrrrrrl").replace("Search slab", "Screening slab")'
NEW_GENERATOR_LINE = OLD_GENERATOR_LINE + '.replace("$m_x$", "$m_z$")'


class EditorialError(Exception):
    pass


def require(value, why):
    if not value:
        raise EditorialError("ARTICLE_CLARITY_EDITORIAL_INVALID: " + why)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()


def decode(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "duplicate JSON key")
            result[key] = value
        return result
    try:
        result = json.loads(raw.decode("utf-8"), object_pairs_hook=unique)
    except (UnicodeDecodeError, ValueError) as error:
        raise EditorialError("ARTICLE_CLARITY_EDITORIAL_INVALID: invalid JSON") from error
    require(isinstance(result, dict), "JSON object required")
    return result


def regular(root, relative, maximum=32 * 1024**2):
    require(isinstance(relative, str) and relative and "\\" not in relative and
            not PurePosixPath(relative).is_absolute() and
            all(p not in ("", ".", "..") for p in relative.split("/")) and
            not any(p in ("local_trackers", "cache", "logs") for p in relative.split("/")) and
            Path(relative).suffix.lower() not in (".rds", ".rda", ".rdata"), "safe public metadata/source role required")
    p = root / relative
    require(p.is_file() and not any(x.is_symlink() for x in (p, *p.parents)) and
            0 < p.stat().st_size <= maximum, "bounded regular public file required: " + relative)
    return p.read_bytes()


def git(root, *args):
    try:
        return subprocess.check_output(["git", "--no-replace-objects", "-C", str(root), *args], stderr=subprocess.PIPE)
    except (OSError, subprocess.CalledProcessError) as error:
        raise EditorialError("ARTICLE_CLARITY_EDITORIAL_INVALID: fixed Git baseline unavailable") from error


def section(text, label):
    marker = "\\label{" + label + "}"
    require(marker in text, "missing section label: " + label)
    value = text.split(marker, 1)[1]
    return value.split("\\section{", 1)[0]


def editorial_checks(main, supplement, display):
    """Source-level checks complement numerical guards and visual PDF review."""
    plain = lambda value: re.sub(r"\s+", " ", value)
    m, s = plain(main), plain(supplement)
    abstract = plain(main.split(r"\begin{abstract}", 1)[1].split(r"\end{abstract}", 1)[0])
    computation = section(main, "sec:inference")
    forecast = section(main, "sec:forecast")
    f = plain(forecast)
    model = section(main, "sec:model")
    before_glofas = main.split(r"\label{eq:glofas-part4-main}", 1)[0]
    glofas_prefix = plain(before_glofas[-5000:])
    checks = {
        "C01": "quantile-specific forecast correction" in abstract and not re.search(
            r"lowest issued-window|reduces quantile forecast loss|best forecast correction|covers 75", abstract, re.I),
        "C02": r"m+q\cdot(m_z+1)" in main.replace("&", "") and
            r"m+q\cdot(m_z+1)" in supplement and "$m_z$" in display and "$m_x$" not in display,
        "C03": "eq:isotonic-projection-main" not in main and
            "equal-weight isotonic projection" in f and
            "raw mean-grid and draw-level crossings" in f and "before projection" in f and
            "eq:supp_monotone_projection" in supplement and r"w_k=1" in supplement,
        "C04": all(phrase not in m for phrase in (
            "It is distinct from a variational quadrature calculation",
            "These are different approximations, not interchangeable names")),
        "C05": "tab:main-computation-map" not in main and "GloFAS" not in computation and
            "PriceFM" not in computation and "Gaussian full conditional" in plain(computation),
        "C06": "tab:main-computation-settings" not in main and
            "20,000" in supplement and "5,000" in supplement and "thinning" in s and
            "scoring" in s,
        "C07": "eq:recursive-posterior-predictive-main" not in main and
            r"\label{eq:forecast-location-main}" in forecast and
            r"\frac{1}{M}\sum_{j=1}^{M}\tilde{\vect x}_{o+h}^{[j]}" in forecast and
            r"\beta_{0k}^{(b)}" in forecast and r"\bar{\vect x}_{o+h}^{\top}\vect\beta_k^{(b)}" in forecast and
            "primary multiquantile comparison" in f and "readout draws" in f and
            "history" in f and "fresh" in f and "fixed" in f and
            "inverse" in f and "endpoint" in f,
        "C08": "Observation times" in main and "observation times" in m and
            not re.search(r"retained(?:-series)? indices", m + " " + s, re.I) and
            "8501--9000" in main and "9001--9300" in main and "9001--9500" in main and
            "11999" in supplement,
        "C09": r"\clearpage" in main and
            r"\input{tables/independent_train500_eval300_mcmc_figures_v1.tex}" in main and
            r"\input{tables/qdesn_multiquantile_forecast_figure_display.tex}" in main and
            r"\begin{figure}[H]" not in main,
        "C10": all(name in main for name in ("Gaussian mixture", "Asymmetric tails", "Persistent heavy tails",
            "Regime shift", "Nonlinear reservoir dynamics")) and
            "Additional structure" in main and "3.5" in main and "tab:multiquantile-generating-mechanisms" in main,
        "C11": "forecast origin" in glofas_prefix and "final historical time" in glofas_prefix and
            r"\(T\)" in glofas_prefix and r"\(H=28\)" in glofas_prefix and
            r"e=1,\ldots,51" in glofas_prefix and
            "future USGS measurements are reserved for scoring" in m,
    }
    require(len(checks) == 11 and all(checks.values()), "approved C01--C11 text contract failed: " +
            ", ".join(key for key, value in checks.items() if not value))
    return checks


def presentation_plan(baseline, current, *, actual_generator_sha, actual_display_sha):
    require(all(SHA256.fullmatch(value or "") for value in (actual_generator_sha, actual_display_sha)),
            "valid generator and display hashes required")
    require(baseline.get("schema") == "qdesn-sections5-7-presentation-v1" and
            baseline.get("generator") == GENERATOR and isinstance(baseline.get("outputs"), list),
            "fixed presentation structure required")
    result = copy.deepcopy(baseline)
    result["generator_sha256"] = actual_generator_sha
    rows = [row for row in result["outputs"] if row.get("role") == "glofas_specifications"]
    require(len(rows) == 1 and rows[0]["file"] == DISPLAY, "one approved weather table role required")
    rows[0]["sha256"] = actual_display_sha
    require(current in (baseline, result), "presentation receipt change exceeds generator/header hashes")
    return result


def provenance(baseline, updated, context):
    return dict(schema="article-clarity-general-editorial-refresh-v1", baseline_commit=BASELINE,
        original_manifest_sha256=RECEIPT_SHA, updated_paths=list(MUTABLE),
        original_source_sha256={p: baseline["sources"][p] for p in MUTABLE},
        updated_source_sha256={p: updated[p] for p in MUTABLE},
        preserved_historical_fields_sha256={p: sha(canonical(baseline[p])) for p in HISTORICAL},
        presentation_manifest=dict(path=PRESENTATION, original_sha256=PRESENTATION_SHA,
            updated_sha256=context["presentation_sha256"], permitted_output=DISPLAY,
            operation="covariate_lag_header_m_x_to_m_z_only", updated_output_sha256=context["display_sha256"],
            generator=GENERATOR, updated_generator_sha256=context["generator_sha256"]),
        refresher=REFRESHER, refresher_sha256=context["refresher_sha256"],
        scientific_outputs_regenerated=False, scientific_values_changed=False,
        fits_launched=0, forecasts_launched=0, scores_recomputed=0)


def receipt_plan(baseline, current, hash_file, context):
    require(baseline.get("schema") == "independent-forecast-300-500-article-v1" and
            baseline.get("authority_id") == "independent_forecast_300_primary_500_sensitivity_v1" and
            all(isinstance(baseline.get(p), dict) for p in HISTORICAL), "fixed shared receipt and historical records required")
    require(set(context) == {"presentation_sha256", "display_sha256", "generator_sha256", "refresher_sha256"} and
            all(SHA256.fullmatch(v or "") for v in context.values()), "exact successor context hashes required")
    restored = copy.deepcopy(current)
    previous = restored.pop(FIELD, None)
    require(set(restored) == set(baseline), "only named general editorial field may be added")
    for p in MUTABLE:
        require(p in restored.get("sources", {}), "document roles missing")
        restored["sources"][p] = baseline["sources"][p]
    require(restored == baseline, "scientific policy, outputs, source pins or historical provenance changed")
    for group in ("sources", "outputs"):
        for p, expected in baseline[group].items():
            if group == "sources" and p in MUTABLE:
                continue
            require(hash_file(p) == expected, "immutable shared source/output changed: " + p)
    if previous is not None:
        require(previous == provenance(baseline, current["sources"], context), "previous general editorial receipt changed")
    actual = {p: hash_file(p) for p in MUTABLE}
    require(all(SHA256.fullmatch(v or "") for v in actual.values()), "complete current document hashes required")
    result = copy.deepcopy(baseline)
    result["sources"].update(actual)
    result[FIELD] = provenance(baseline, actual, context)
    return result


def prepare(root):
    root = Path(root).absolute()
    require(root.is_dir() and not any(p.is_symlink() for p in (root, *root.parents)), "regular repository root required")
    for tip in ("HEAD", "refs/remotes/origin/main"):
        git(root, "merge-base", "--is-ancestor", BASELINE, tip)
    original = git(root, "show", BASELINE + ":" + RECEIPT)
    old_presentation = git(root, "show", BASELINE + ":" + PRESENTATION)
    require(sha(original) == RECEIPT_SHA and sha(old_presentation) == PRESENTATION_SHA, "fixed baseline receipt bytes differ")
    baseline, pbase = decode(original), decode(old_presentation)
    current = decode(regular(root, RECEIPT))
    pcurrent = decode(regular(root, PRESENTATION))
    old_display = git(root, "show", BASELINE + ":" + DISPLAY)
    require(old_display.count(b"$m_x$") == 1, "reviewed original weather header differs")
    require(regular(root, DISPLAY) == old_display.replace(b"$m_x$", b"$m_z$"),
            "weather display change exceeds the exact notation correction")
    old_generator = git(root, "show", BASELINE + ":" + GENERATOR)
    require(old_generator.count(OLD_GENERATOR_LINE.encode()) == 1 and
            regular(root, GENERATOR) == old_generator.replace(OLD_GENERATOR_LINE.encode(), NEW_GENERATOR_LINE.encode()),
            "presentation generator change exceeds exact reproducible header mapping")
    hash_file = lambda p: sha(regular(root, p))
    proposed_presentation = presentation_plan(pbase, pcurrent,
        actual_generator_sha=hash_file(GENERATOR), actual_display_sha=hash_file(DISPLAY))
    # The article-only closure is frozen except its two prose documents, this
    # metadata receipt, and the single declared display/receipt transformation.
    # No blanket freeze of unrelated future scientific-code lanes is imposed.
    allowlist = git(root, "show", BASELINE + ":overleaf/article_files.txt")
    require(regular(root, "overleaf/article_files.txt") == allowlist, "article publication inventory changed")
    article = [p for p in allowlist.decode().splitlines() if p and not p.startswith("#")]
    protected = set(article) - set(MUTABLE) - {RECEIPT, PRESENTATION, DISPLAY}
    for p in protected:
        require(hash_file(p) == sha(git(root, "show", BASELINE + ":" + p)), "immutable article evidence changed: " + p)
    context = dict(presentation_sha256=sha(canonical(proposed_presentation)),
        display_sha256=hash_file(DISPLAY), generator_sha256=hash_file(GENERATOR), refresher_sha256=hash_file(REFRESHER))
    proposed_receipt = receipt_plan(baseline, current, hash_file, context)
    checks = editorial_checks(regular(root, MUTABLE[0]).decode(), regular(root, MUTABLE[1]).decode(), regular(root, DISPLAY).decode())
    # Existing numeric/data checks remain authoritative and read-only.
    helper = root / "scripts/glofas_current_article_authority.py"
    spec = importlib.util.spec_from_file_location("article_clarity_glofas_authority", helper)
    authority = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(authority)
    authority.validate_authority_tree(root)
    watched = protected | set(baseline["sources"]) | set(baseline["outputs"]) | {
        RECEIPT, PRESENTATION, DISPLAY, GENERATOR, REFRESHER, "overleaf/article_files.txt"}
    fingerprints = {p: hash_file(p) for p in watched}
    return root, current, pcurrent, proposed_receipt, proposed_presentation, fingerprints, checks


def refresh(root, write=False):
    root, current, pcurrent, result, presult, pins, checks = prepare(root)
    for p, digest in pins.items():
        require(sha(regular(root, p)) == digest, "source changed during editorial receipt preparation: " + p)
    if write:
        staged = []
        try:
            for p, value in ((PRESENTATION, presult), (RECEIPT, result)):
                with tempfile.NamedTemporaryFile(prefix=".article_clarity_receipt_", dir=root / "tables", delete=False) as f:
                    f.write(canonical(value)); f.flush(); os.fsync(f.fileno())
                    staged.append((f.name, root / p))
            for p, digest in pins.items():
                require(sha(regular(root, p)) == digest, "source changed before editorial receipt publication: " + p)
            # A process interruption after the first metadata replacement is
            # fail-closed and retryable; no scientific input is ever written.
            for temporary, destination in staged:
                os.replace(temporary, destination)
            directory = os.open(root / "tables", os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            for temporary, _ in staged:
                if os.path.exists(temporary):
                    os.unlink(temporary)
        require(decode(regular(root, RECEIPT)) == result and decode(regular(root, PRESENTATION)) == presult,
                "written editorial receipt readback differs")
    else:
        require(current == result and pcurrent == presult, "live editorial metadata requires the explicit successor --refresh")
    print("ARTICLE_CLARITY_EDITORIAL_RECEIPTS_{} checks={} documents=2 presentation_tables=1 scientific_runs=0".format(
        "REFRESHED" if write else "CHECK_PASS", len(checks)))
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    mode = p.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--refresh", action="store_true")
    args = p.parse_args()
    try:
        refresh(args.root, write=args.refresh)
    except Exception as error:
        print("ARTICLE_CLARITY_EDITORIAL_RECEIPTS_ERROR: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
