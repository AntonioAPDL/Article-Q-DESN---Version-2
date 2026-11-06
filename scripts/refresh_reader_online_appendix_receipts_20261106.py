#!/usr/bin/env python3.11
"""Authenticate one editorial revision; never fit, forecast, rescore or publish.

The actual current documents pass the new semantic checks before dated prose
tests may inspect authenticated historical fixtures. Scientific checks always
inspect live, byte-protected sources. Historical refresh records are retained.
"""
from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
BASELINE = "6370677bf37204dd494db1b7f649d2ceb288f36b"
FIELD = "reader_appendix_20261106"
RECEIPT = "tables/independent_forecast_300_500_article_manifest_v1.json"
PRESENTATION = "tables/qdesn_sections5_7_presentation_manifest.json"
DISPOSITION = "docs/reproducibility/reader_appendix_content_disposition_20261106.csv"
REFRESHER = "scripts/refresh_reader_online_appendix_receipts_20261106.py"
RECEIPT_SHA = "3957d2a54d52fca7df807d81a3bebbbc2d4bbe1d7f352a7e89c40c4b84a1f436"
PRESENTATION_SHA = "35346680aa76c434e459eaa38a40b370a4f7477e30cc842ed934025aaffa7a7f"
HISTORY = ("editorial_source_refresh", "glofas_article_source_refresh", "general_editorial_source_refresh")
DOCUMENTS = ("main.tex", "qdesn-supplement.tex")
CAPTIONS = (
    "tables/qdesn_multiquantile_forecast_figure_display.tex",
    "tables/independent_train500_eval300_mcmc_figures_v1.tex",
    "tables/independent_train500_eval300_mcmc_mae_figure_v1.tex",
    "tables/independent_train500_eval500_mcmc_figures_v1.tex",
)
GENERATORS = ("scripts/build_qdesn_sections5_7_presentation.py", "scripts/build_independent_forecast_300_500_v1.R")
DESCRIPTIONS = ("docs/reproducibility/anonymous_review_README.txt", "overleaf/README.md")
MUTABLE = set(DOCUMENTS + CAPTIONS + GENERATORS + DESCRIPTIONS + ("refs.bib", RECEIPT, PRESENTATION))
LEGACY_TEXT = set(DOCUMENTS + CAPTIONS + ("refs.bib",))
VALIDATION_PATHS = (
    REFRESHER, "scripts/reader_online_appendix_legacy_adapter_20261106.R",
    "scripts/check_qdesn_final_manuscript_revision.R",
    "scripts/check_joint_qdesn_pure_desn_article_projection_v2.R",
    "scripts/check_qdesn_statistical_language_revision.R",
    "scripts/check_forecast_application_exposition_20261031.R",
    "scripts/check_qdesn_sections5_7_presentation.py",
    "scripts/refresh_independent_forecast_editorial_manifest_20261031.R",
    "application/tests/test_reader_online_appendix_receipts_20261106.py",
    "application/tests/test_qdesn_reader_focused_editorial_revision.R",
    "application/tests/test_qdesn_statistical_language_revision.R",
    "application/tests/test_forecast_application_exposition_20261031.R",
    "application/tests/test_rhs_global_scale_reference.R",
    "application/tests/test_article_clarity_editorial_receipts_20261104.py",
    "application/tests/test_independent_forecast_editorial_manifest_20261031.R",
    "application/tests/run_tests.R",
    "scripts/audit_qdesn_article_dependencies.py",
    "scripts/independent_reporting_authority_checks.R",
    "application/tests/test_independent_reporting_authority_checks.R",
    "scripts/check_independent_forecast_300_500_v1.R",
    "scripts/check_qdesn_mq_nomenclature.py",
    "application/tests/test_qdesn_mq_nomenclature.py",
    "application/tests/test_joint_qdesn_pure_desn_article_projection_v2.R",
)
SHA256 = re.compile(r"^[a-f0-9]{64}$")


class EditorialError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise EditorialError("READER_APPENDIX_EDITORIAL_INVALID: " + message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()


def decode(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "duplicate JSON field")
            result[key] = value
        return result
    try:
        result = json.loads(raw.decode(), object_pairs_hook=unique)
    except (UnicodeError, ValueError) as error:
        raise EditorialError("READER_APPENDIX_EDITORIAL_INVALID: invalid JSON") from error
    require(isinstance(result, dict), "object JSON required")
    return result


def regular(root, relative, limit=32 * 1024**2):
    require(isinstance(relative, str) and relative and "\\" not in relative and
            not PurePosixPath(relative).is_absolute() and
            all(p not in ("", ".", "..", "local_trackers", "cache", "logs") for p in relative.split("/")) and
            Path(relative).suffix.lower() not in (".rds", ".rda", ".rdata"), "safe public source path required")
    path = root / relative
    require(path.is_file() and not any(p.is_symlink() for p in (path, *path.parents)) and
            0 < path.stat().st_size <= limit, "bounded regular public file required: " + relative)
    return path.read_bytes()


def git(root, *arguments):
    try:
        return subprocess.check_output(["git", "--no-replace-objects", "-C", str(root), *arguments], stderr=subprocess.PIPE)
    except (OSError, subprocess.CalledProcessError) as error:
        raise EditorialError("READER_APPENDIX_EDITORIAL_INVALID: fixed Git evidence unavailable") from error


def baseline_bytes(root, relative):
    return git(root, "show", BASELINE + ":" + relative)


def public_blob_identity(raw):
    """Git's SHA-1 blob identity, not a reserialization of scientific values."""
    return hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()


def active(root):
    path = Path(root) / RECEIPT
    return path.is_file() and FIELD in decode(path.read_bytes())


def uncomment(text):
    return re.sub(r"(?<!\\)%[^\n]*", "", text)


def plain(text):
    return re.sub(r"\s+", " ", uncomment(text))


def compact_math(text):
    return re.sub(r"\s+|\\[,;! ]", "", uncomment(text))


def section(text, label):
    marker = "\\label{" + label + "}"
    require(text.count(marker) == 1, "one semantic section label required: " + label)
    rest = text.split(marker, 1)[1]
    return rest.split("\\section{", 1)[0]


def equation(text, label):
    marker = "\\label{" + label + "}"
    require(text.count(marker) == 1, "one equation label required: " + label)
    at = text.index(marker)
    start = text.rfind("\\begin{equation}", 0, at)
    end = text.find("\\end{equation}", at)
    require(start >= 0 and end > at, "complete numbered equation required: " + label)
    return text[start:end]


def semantic_checks(main, supplement, bibliography):
    """Current actual document invariants, independent of legacy prose fixtures."""
    m, s = plain(main), plain(supplement)
    main_math = compact_math(main)
    combined = m + " " + s
    forecast = plain(section(main, "sec:forecast"))
    scoring = plain(section(supplement, "sec:forecast_synthesis"))
    mq = plain(section(supplement, "sec:joint_qdesn_supp"))
    mq_math, scoring_math = compact_math(mq), compact_math(scoring)
    full_covariance = (r"\mat H\mat\Sigma\mat H^\top".replace(" ", "") in mq_math or
                       r"\operatorname{Cov}_q(\beta_{k,j},\beta_{k-1,j})" in mq_math)
    glofas = plain(section(main, "sec:data"))
    pricefm = plain(section(main, "sec:pricefm-application"))
    checks = {}
    checks["feature_scope"] = ("m+q\\cdot(m_z+1)" in m.replace("&", "") and
        "n_D+\\sum_{d<D}\\tilde n_d" in m and
        "direct input" in m.lower() and "reservoir" in forecast.lower())
    checks["full_ns_target"] = ("eq:rhs-product-main" in main and
        all(value in main_math for value in (
            r"\Normal(0\mid\beta_j,\zeta^2)",
            r"\Normal(\beta_j\mid0,\tau^2\lambda_j^2)",
            r"\Normal(\beta_0\midb_0,V_0)",
            r"\lambda_j^2\mid\nu_j\sim\IG(1/2,1/\nu_j)",
            r"\nu_j\sim\IG(1/2,1)",
            r"\tau^2\mid\xi\sim\IG(1/2,1/\xi)",
            r"\xi\sim\IG(1/2,1/\tau_0^2)")) and
        "eq:supp_ns_product_factor" in supplement and
        "scale-dependent" in s and "\\frac{r+1}{2}" in supplement)
    checks["proper_likelihood_priors"] = (r"\sigma\sim\IG(a_\sigma,b_\sigma)" in main_math and
        "proper shape-prior density" in m and "supported on" in m and
        (r"\gamma^{(b)}=0" in main_math or "shape at zero" in m))
    checks["centering_answer"] = ("center" in s.lower() and
        "intercept" in s.lower() and "Jacobian" in s and
        ("transformed prior" in s.lower() or "transformed joint prior" in s.lower() or "prior transformation" in s.lower() or
         "transforms" in s.lower() or "prior becomes" in s.lower()))
    checks["mq_anchor_covariance"] = ("\\vect\\Delta_1=\\vect\\beta_1" in supplement and
        "C_\\Delta(\\Theta_\\Delta)p(\\Theta_\\Delta)" in supplement and
        full_covariance and
        "\\beta_{\\mathrm{base}}" not in mq)
    checks["composite_target"] = ("Composite likelihood:" in main and
        "\\propto\\exp\\!\\left\\{-\\ell_c" in main and
        "composite" in m.lower() and "Kohns" in main)
    checks["trajectory_recursion"] = ("parameter draw" in forecast and
        "trajectory" in forecast and "history" in forecast and
        "covariate" in forecast and "fitting endpoint" in forecast and
        "\\tilde" in forecast and "\\beta" in forecast and "\\sigma" in forecast and
        ("same parameter draw" in forecast or "fixed along" in forecast) and
        re.search(r"(?:\\tilde\s*Y|\\tilde\{Y\})[^;]{0,120}\\sim\\exAL_\{p_0\}", forecast) is not None and
        "AL" in forecast and "exAL" in forecast)
    checks["actual_mean_feature_scores"] = ("primary" in m and
        re.search(r"features averaged over (?:the |its )?simulated trajectories", m) is not None and
        "averaged" in scoring and "\\bar{" in scoring and
        (("readout uncertainty" in scoring and "conditional" in scoring) or
         re.search(r"intervals[^.]{0,80}condition[^.]{0,90}averaged[^.]{0,30}design", scoring, re.I) is not None) and
        "integrat" in scoring and "histories" in scoring)
    checks["ordering_and_tails"] = ("equal-weight isotonic" in m and
        re.search(r"crossing rates[^.]{0,130}before", m) is not None and
        "eq:supp_monotone_projection" in supplement and "w_k=1" in supplement and
        ("not sorting" in scoring or "differs from sorting" in scoring) and
        ("endpoint clamp" in scoring.lower() or
         ("Outside" in scoring and "outermost fitted value is retained" in scoring)) and
        "interpolation" in scoring.lower())
    weight_vectors = re.findall(r"(?:\d*\.\d+)(?:,\d*\.\d+){6}", scoring_math)
    actual_weights = any([float(x) for x in value.split(",")] == [.025,.1,.2,.25,.2,.1,.025] for value in weight_vectors)
    checks["score_weights"] = ("p_K-p_1" in scoring_math and "weights sum" in scoring and actual_weights and
        "eq:acrps-main" in main and "eq:crps-integrated-check-main" in main and
        "S_{\\mathrm{DGP}}^{(b)}" in main and
        not re.search(r"(?:aCRPS|trapezoid)[^.]{0,120}(?:exactly equivalent|identical) to[^.]{0,30}WIS", combined, re.I))
    checks["mq_crossing_results"] = all(value in m for value in (
        "47,520 adjacent-level", "0.021\\%", "5.488\\%", "0.606\\%"))
    checks["vb_scope_and_jacobian"] = (full_covariance and
        "J(\\vect\\eta)=\\sigma(U-L)\\expit(\\eta_2)" in supplement and
        "eq:supp_generic_elbo" in supplement and "eq:supp_elbo_transformed_coordinates" in supplement and
        "point" in mq and "intercept" in mq and "uncertainty" in combined)
    checks["glofas_current_target"] = ("glofas_same_family_20261103_display_aliases.tex" in main and
        "glofas_same_family_20261103_display_aliases.tex" in supplement and
        "\\prod_{h=1}^{28}\\prod_{e=1}^{51}" in supplement and
        "\\prod_{h=1}^{28}f_{p_k}" in supplement and
        "Each level retains its own path" in s and
        "future USGS measurements are reserved for scoring" in m and
        "Both use realized values during the forecast window" in m and
        "\\Phi^{-1}(p)\\sqrt{V_{p,hh}}" in main and
        "No additional observation error is added" in s and
        "no post-hoc crossing correction is applied" in s)
    unit_target = equation(supplement, "eq:supp_glofas_unit_member_target")
    checks["unit_member_not_fractional"] = (r"\prod_{h=1}^{28}\prod_{e=1}^{51}" in compact_math(unit_target) and
        "1/51" not in unit_target and r"\frac{1}{51}" not in compact_math(unit_target))
    checks["glofas_complete_findings"] = ("all four AL and exAL regressions score above the raw ensemble" in glofas and
        "each cover only 2 of 28" in glofas and "inverted on eight dates" in glofas and
        "23.2--27.4\\%" in glofas)
    checks["pricefm_actual_design"] = ("direct" in pricefm and "horizon" in pricefm and
        "variational" in pricefm and "not independently verified" in pricefm and
        "future prices are simulated recursively" not in pricefm and
        "[PriceFM findings to be updated.]" in main)
    checks["selection_history"] = ("historical" in combined and
        "forecast performance on the evaluation series" in combined and
        ("shorter primary period was selected after inspecting" in s or
         "revised after inspecting" in s) and
        ("same posterior target" in combined or re.search(r"same data, likelihood,? and prior", combined) is not None))
    checks["bracher_and_appendix"] = ("BracherEtAl2021WIS" in main and
        "10.1371/journal.pcbi.1008618" in bibliography and
        "Online Appendix" in supplement and
        "absolute error of the median forecast" in m)
    require(all(checks.values()), "current scientific/editorial semantics: " +
            ", ".join(k for k, value in checks.items() if not value))
    return checks


def verify_bibliography(before, after):
    pattern = re.compile(rb"@article\{BracherEtAl2021WIS,.*?\n\}\n(?:\n)?", re.S)
    entries = pattern.findall(after)
    require(len(entries) == 1, "exactly one Bracher article entry required")
    entry = entries[0].lower()
    require(entry.count(b"@") == 1, "one new bibliography entry only")
    for value in (b"bracher", b"ray", b"gneiting", b"reich", b"2021", b"1008618", b"10.1371/journal.pcbi.1008618"):
        require(value in entry, "verified Bracher metadata missing")
    restored = pattern.sub(b"", after, count=1)
    require(restored.rstrip() == before.rstrip(), "bibliography differs beyond the sole Bracher addition")


def verify_caption(before, after, path):
    if path == CAPTIONS[0]:
        expected = before.replace(b"specified in the supplement", b"specified in online Appendix C")
    else:
        expected = before.replace(b"The supplement documents", b"Online Appendix D documents")
    require(after == expected, "caption change exceeds approved appendix navigation: " + path)


def verify_generator(before, after, path):
    if path == GENERATORS[0]:
        expected = before.replace(b"specified in the supplement", b"specified in online Appendix C")
    else:
        expected = before.replace(b"The supplement documents criterion-specific selection and model-specific forecast-draw dependence.",
                                  b"Online Appendix D documents criterion-specific selection and model-specific forecast-draw dependence.")
    require(after == expected, "generator change exceeds approved caption-only substitution: " + path)


def disposition_checks(root, raw, main, supplement):
    fields = ("role_id", "baseline_commit", "baseline_path", "baseline_start_line", "baseline_end_line",
              "baseline_labels", "disposition", "destination", "asset_paths", "retained_summary", "reason")
    rows = list(csv.DictReader(io.StringIO(raw.decode())))
    require(rows and tuple(rows[0]) == fields and len({r["role_id"] for r in rows}) == len(rows), "complete unique disposition schema required")
    for row in rows:
        require(all(row[k] for k in fields if k not in {"baseline_labels", "asset_paths"}) and row["baseline_commit"] == BASELINE and
                row["baseline_path"] == "qdesn-supplement.tex" and
                row["disposition"] in {"retained", "consolidated", "public_archive"}, "bounded disposition role required")
        start, end = int(row["baseline_start_line"]), int(row["baseline_end_line"])
        require(1 <= start <= end <= 3279, "valid frozen source range required")
        if row["disposition"] == "public_archive":
            if row["destination"].startswith("Git baseline:"):
                require("qdesn-supplement.tex" in row["destination"], "frozen public source destination required")
            else:
                assets = row["asset_paths"].split(";")
                require(row["destination"] in assets, "public archive must name its retained asset")
                for path in assets:
                    require(sha(regular(root, path)) == sha(baseline_bytes(root, path)),
                            "archived public asset differs from frozen baseline: " + path)
    # Every old direct inclusion is retained, or its omitted role is recorded.
    old = baseline_bytes(root, "qdesn-supplement.tex").decode()
    pattern = re.compile(r"\\input\{([^}]+)\}")
    live = set(pattern.findall(main + supplement))
    for match in pattern.finditer(uncomment(old)):
        if match.group(1) in live:
            continue
        line = old[:old.find(match.group(0))].count("\n") + 1
        require(any(int(r["baseline_start_line"]) <= line <= int(r["baseline_end_line"]) and
                    r["disposition"] in {"consolidated", "public_archive"} for r in rows),
                "omitted public inclusion lacks a reviewed disposition: " + match.group(1))
    return rows


def current_route_checks(root, rows):
    """Validate ACTUAL alias-aware selection, not merely an archive declaration."""
    spec = importlib.util.spec_from_file_location("reader_appendix_dependency_closure", root / "scripts/audit_qdesn_article_dependencies.py")
    dependency = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dependency)
    encoded, _ = dependency.inventory(root)
    inventory = list(csv.DictReader(io.StringIO(encoded)))
    consumers = {r["file"]: set(filter(None, r["source_inferred_consumers"].split(";"))) for r in inventory}
    mandatory = (
        "tables/independent_train500_eval300_mcmc_mae_figure_v1.tex",
        "tables/independent_train500_eval500_mcmc_figures_v1.tex",
        "tables/independent_forecast_calibration_figure_v1.tex",
        "tables/qdesn_single_quantile_mcmc_fit_figure_display.tex",
        "tables/qdesn_multiquantile_fit_figure_display.tex",
        "tables/qdesn_multiquantile_design_display.tex",
        "tables/qdesn_multiquantile_score_display.tex",
        "tables/qdesn_multiquantile_recursive_policy_display.tex",
        "tables/qdesn_multiquantile_crossing_display.tex",
        "figures/quantile_initialization/quantile_initialization_picture.tex",
        "tables/glofas_same_family_20261103_full_scores.tex",
        "tables/glofas_same_family_20261103_calibration.tex",
        "tables/glofas_same_family_20261103_convergence.tex",
    )
    for path in mandatory:
        require("qdesn-supplement.tex" in consumers.get(path, set()), "mandatory appendix evidence is not selected: " + path)
    for path in mandatory[:3]:
        require("main.tex" not in consumers.get(path, set()), "supplementary recovery/sensitivity/calibration must not move into main: " + path)
    reachable_tex = [p for p, docs in consumers.items() if docs and p.endswith(".tex")]
    labels = set()
    for path in reachable_tex:
        labels.update(re.findall(r"\\label\{([^}]+)\}", uncomment(regular(root, path).decode())))
    for row in rows:
        if row["disposition"] != "retained":
            continue
        for label in filter(None, row["baseline_labels"].split(";")):
            require(label in labels, "retained role label is absent from selected sources: " + label)
        for path in filter(None, row["asset_paths"].split(";")):
            if path.endswith((".tex", ".pdf")):
                require("qdesn-supplement.tex" in consumers.get(path, set()), "retained public display is not selected: " + path)
    return {p: sorted(consumers[p]) for p in mandatory}


def receipt_plan(baseline, current, source_hashes, context):
    require(all(k in baseline for k in HISTORY), "all historical refresh records required")
    require(set(source_hashes) == MUTABLE - {RECEIPT, PRESENTATION} and
            all(SHA256.fullmatch(v or "") for v in source_hashes.values()), "exact mutable-source inventory required")
    context_keys = {"refresher", "refresher_sha256", "disposition_map", "disposition_sha256",
        "presentation_manifest_sha256", "protected_inventory_sha256", "protected_files",
        "semantic_checks", "disposition_roles", "publication_inventory_changed", "legacy_fixture_policy", "validation_source_sha256", "role_routing_sha256"}
    require(set(context) == context_keys and context["refresher"] == REFRESHER and
            context["disposition_map"] == DISPOSITION and context["publication_inventory_changed"] is False and
            context["legacy_fixture_policy"] == "validated_live_semantics_then_637_prose_only_never_scientific_inputs" and
            all(SHA256.fullmatch(context[k] or "") for k in context if k.endswith("sha256") and k != "validation_source_sha256") and
            set(context["validation_source_sha256"]) == set(VALIDATION_PATHS) and
            all(SHA256.fullmatch(v or "") for v in context["validation_source_sha256"].values()) and
            isinstance(context["protected_files"], int) and context["protected_files"] > 0 and
            isinstance(context["disposition_roles"], int) and context["disposition_roles"] > 0 and
            isinstance(context["semantic_checks"], list) and context["semantic_checks"] == sorted(set(context["semantic_checks"])),
            "exact successor context and no scientific/publication expansion required")
    restored = copy.deepcopy(current)
    previous = restored.pop(FIELD, None)
    for group in ("sources", "outputs"):
        for path in source_hashes:
            if path in restored.get(group, {}):
                restored[group][path] = baseline[group][path]
    require(restored == baseline, "historical records, scientific pins or reporting policy changed")
    result = copy.deepcopy(baseline)
    for group in ("sources", "outputs"):
        for path, value in source_hashes.items():
            if path in result[group]:
                result[group][path] = value
    result[FIELD] = dict(schema="reader-online-appendix-editorial-v1", baseline_commit=BASELINE,
        original_manifest_sha256=RECEIPT_SHA, original_presentation_manifest_sha256=PRESENTATION_SHA,
        updated_paths=sorted(source_hashes), updated_source_sha256=source_hashes,
        historical_refresh_sha256={k: sha(canonical(baseline[k])) for k in HISTORY},
        scientific_values_changed=False, scientific_outputs_regenerated=False,
        fits_launched=0, forecasts_launched=0, scores_recomputed=0, **context)
    if previous is not None:
        # A legitimate subsequent prose revision may refresh its current pins,
        # but may not alter the named baseline or its protected historical data.
        expected = result[FIELD]
        changing = {"updated_source_sha256", "refresher_sha256", "disposition_sha256",
                    "presentation_manifest_sha256", "disposition_roles", "semantic_checks", "validation_source_sha256"}
        require(set(previous) == set(expected) and
                all(previous[k] == expected[k] for k in expected if k not in changing) and
                set(previous.get("updated_source_sha256", {})) == set(source_hashes) and
                all(SHA256.fullmatch(v or "") for v in previous["updated_source_sha256"].values()) and
                set(previous.get("validation_source_sha256", {})) == set(VALIDATION_PATHS) and
                all(SHA256.fullmatch(v or "") for v in previous["validation_source_sha256"].values()) and
                all(isinstance(previous[k], str) and SHA256.fullmatch(previous[k])
                    for k in changing if k.endswith("sha256") and k not in {"updated_source_sha256", "validation_source_sha256"}),
                "previous successor scope, scientific counters or authorization changed")
    return result


def prepare(root):
    root = Path(root).absolute()
    require(root.is_dir() and not any(p.is_symlink() for p in (root, *root.parents)), "regular repository root required")
    git(root, "merge-base", "--is-ancestor", BASELINE, "HEAD")
    original = baseline_bytes(root, RECEIPT)
    old_presentation = baseline_bytes(root, PRESENTATION)
    require(sha(original) == RECEIPT_SHA and sha(old_presentation) == PRESENTATION_SHA, "fixed baseline receipt identity differs")
    baseline = decode(original)
    current = decode(regular(root, RECEIPT))
    presentation = decode(regular(root, PRESENTATION))
    allowlist = baseline_bytes(root, "overleaf/article_files.txt")
    require(regular(root, "overleaf/article_files.txt") == allowlist, "article publication inventory changed")
    blobs = {}
    for entry in git(root, "ls-tree", "-r", "-z", BASELINE).split(b"\0"):
        if not entry:
            continue
        header, path = entry.split(b"\t", 1)
        mode, kind, identity = header.split()
        require(kind == b"blob" and len(identity) == 40, "fixed SHA-1 public Git blob inventory required")
        blobs[path.decode()] = identity.decode()
    paths = set(blobs)
    article = {p for p in allowlist.decode().splitlines() if p and not p.startswith("#")}
    protected = (article | {p for p in paths if p.startswith(("application/R/", "application/config/")) or
                 p.startswith("tables/") and p.endswith(".csv") or p.startswith("figures/") and p.endswith(".pdf")}) - MUTABLE
    pins = {}
    for path in sorted(protected):
        actual = regular(root, path)
        require(public_blob_identity(actual) == blobs[path], "immutable scientific/article source changed: " + path)
        pins[path] = sha(actual)
    bibliography = regular(root, "refs.bib")
    verify_bibliography(baseline_bytes(root, "refs.bib"), bibliography)
    for path in CAPTIONS:
        verify_caption(baseline_bytes(root, path), regular(root, path), path)
    for path in GENERATORS:
        verify_generator(baseline_bytes(root, path), regular(root, path), path)
    oldp = decode(old_presentation)
    require(presentation.keys() == oldp.keys(), "presentation schema changed")
    expected_p = copy.deepcopy(oldp)
    expected_p["generator_sha256"] = sha(regular(root, GENERATORS[0]))
    for row in expected_p["outputs"]:
        if row["file"] == CAPTIONS[0]:
            row["sha256"] = sha(regular(root, CAPTIONS[0]))
    require(presentation in (oldp, expected_p), "presentation receipt change exceeds one caption/generator pin")
    main = regular(root, DOCUMENTS[0]).decode()
    supplement = regular(root, DOCUMENTS[1]).decode()
    checks = semantic_checks(main, supplement, bibliography.decode())
    roles = disposition_checks(root, regular(root, DISPOSITION), main, supplement)
    routing = current_route_checks(root, roles)
    # The current GloFAS authority is independently verified against actual,
    # live documents and public assets, not historical prose fixtures.
    spec = importlib.util.spec_from_file_location("reader_appendix_current_authority", root / "scripts/glofas_current_article_authority.py")
    authority = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(authority)
    authority.validate_authority_tree(root)
    edited = sorted(MUTABLE - {RECEIPT, PRESENTATION})
    hashes = {p: sha(regular(root, p)) for p in edited}
    context = dict(refresher=REFRESHER, refresher_sha256=sha(regular(root, REFRESHER)),
        disposition_map=DISPOSITION, disposition_sha256=sha(regular(root, DISPOSITION)),
        presentation_manifest_sha256=sha(canonical(expected_p)),
        protected_inventory_sha256=sha(canonical(pins)), protected_files=len(pins),
        semantic_checks=sorted(checks), disposition_roles=len(roles), publication_inventory_changed=False,
        role_routing_sha256=sha(canonical(routing)),
        validation_source_sha256={p: sha(regular(root, p)) for p in VALIDATION_PATHS},
        legacy_fixture_policy="validated_live_semantics_then_637_prose_only_never_scientific_inputs")
    result = receipt_plan(baseline, current, hashes, context)
    watched = set(pins) | MUTABLE | set(VALIDATION_PATHS) | {REFRESHER, DISPOSITION}
    stability = {p: sha(regular(root, p)) for p in watched}
    return root, current, presentation, result, expected_p, stability


def refresh(root, write=False):
    root, current, presentation, result, expected_p, pins = prepare(root)
    def stable(exclude=()):
        for path, digest in pins.items():
            if path not in exclude:
                require(sha(regular(root, path)) == digest, "source changed during editorial validation: " + path)
    stable()
    if write:
        staged = []
        try:
            for path, value in ((PRESENTATION, expected_p), (RECEIPT, result)):
                with tempfile.NamedTemporaryFile(prefix=".reader_appendix_receipt_", dir=root / "tables", delete=False) as stream:
                    stream.write(canonical(value)); stream.flush(); os.fsync(stream.fileno())
                    staged.append((Path(stream.name), root / path))
            stable()
            for temporary, destination in staged:
                os.replace(temporary, destination)
            descriptor = os.open(root / "tables", os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
        finally:
            for temporary, _ in staged:
                if temporary.exists():
                    temporary.unlink()
        require(decode(regular(root, RECEIPT)) == result and decode(regular(root, PRESENTATION)) == expected_p, "metadata readback differs")
        stable(exclude={RECEIPT, PRESENTATION})
    else:
        require(current == result and presentation == expected_p, "explicit new --refresh is required for current editorial pins")
    return result


def historical_text(root, relative):
    require(relative in LEGACY_TEXT, "historical fixture is prose only, never a scientific input")
    return baseline_bytes(Path(root), relative).decode()


def portable_reader_checks(root):
    """TEST-ONLY copied-public-fixture checks; no ancestry or full-source claim.

    Callers must first admit their actual source ROOT with refresh(write=False),
    then copy its public fixture. This mode is never selected by a receipt,
    environment variable or this module's CLI, and never writes metadata.
    Frozen scientific/public manifest checks remain the caller's responsibility.
    """
    root = Path(root).absolute()
    current = decode(regular(root, RECEIPT))
    declared = current.get(FIELD, {})
    require(declared.get("schema") == "reader-online-appendix-editorial-v1" and
            declared.get("baseline_commit") == BASELINE and
            declared.get("original_manifest_sha256") == RECEIPT_SHA and
            declared.get("original_presentation_manifest_sha256") == PRESENTATION_SHA and
            declared.get("updated_paths") == sorted(MUTABLE - {RECEIPT, PRESENTATION}) and
            set(declared.get("updated_source_sha256", {})) == MUTABLE - {RECEIPT, PRESENTATION} and
            declared.get("publication_inventory_changed") is False and
            declared.get("scientific_values_changed") is False and
            declared.get("scientific_outputs_regenerated") is False and
            all(declared.get(k) == 0 for k in ("fits_launched", "forecasts_launched", "scores_recomputed")) and
            all(sha(canonical(current[k])) == declared.get("historical_refresh_sha256", {}).get(k) for k in HISTORY),
            "copied fixture must retain the exact approved baseline/scope/historical records")
    for path in DOCUMENTS + ("refs.bib",):
        require(sha(regular(root, path)) == declared["updated_source_sha256"][path],
                "copied current document differs from admitted fixture: " + path)
    require(sha(regular(root, DISPOSITION)) == declared.get("disposition_sha256"),
            "copied disposition differs from admitted fixture")
    for path in (REFRESHER, "scripts/audit_qdesn_article_dependencies.py"):
        require(sha(regular(root, path)) == declared.get("validation_source_sha256", {}).get(path),
                "copied fixture checker source differs: " + path)
    checks = semantic_checks(regular(root, DOCUMENTS[0]).decode(),
        regular(root, DOCUMENTS[1]).decode(), regular(root, "refs.bib").decode())
    rows = list(csv.DictReader(io.StringIO(regular(root, DISPOSITION).decode())))
    require(rows and len({r["role_id"] for r in rows}) == len(rows) and
            len(rows) == declared.get("disposition_roles") and
            all(r["baseline_commit"] == BASELINE and r["baseline_path"] == "qdesn-supplement.tex" and
                r["disposition"] in {"retained", "consolidated", "public_archive"} for r in rows),
            "copied fixture disposition identities differ")
    routing = current_route_checks(root, rows)
    require(sha(canonical(routing)) == declared.get("role_routing_sha256"),
            "copied fixture current role routes differ")
    return dict(scope="controlled_copied_public_fixture_only", source_ancestry_authenticated=False,
        full_scientific_inventory_authenticated=False, semantic_checks=len(checks), metadata_written=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--refresh", action="store_true")
    parser.add_argument("--legacy-text", choices=sorted(LEGACY_TEXT))
    args = parser.parse_args()
    try:
        refresh(args.root, write=args.refresh)
        if args.legacy_text:
            sys.stdout.write(historical_text(args.root, args.legacy_text))
        else:
            print("READER_ONLINE_APPENDIX_RECEIPTS_{} scientific_runs=0 legacy_fixture_scope=prose_only".format("REFRESHED" if args.refresh else "CHECK_PASS"))
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
