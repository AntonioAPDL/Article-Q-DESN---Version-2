#!/usr/bin/env python3.11
"""Authenticate the presentation-only appendix compression; never run science.

Normal admission requires the fixed Git ancestor and verifies original bytes
before current semantics, routes and derivative values. The explicit Python
``portable_checks`` API is only for copied public test fixtures: it cannot
refresh receipts or authenticate Git ancestry. Missing Git never selects it.
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
BASELINE = "a9220a25e978b50180beabe3e243bcab963f2ca1"
SCHEMA = "appendix-compression-editorial-v1"
FIELD = "appendix_compression_20261106"
MANIFEST = "tables/appendix_compression_20261106_manifest.json"
LEGACY_RECEIPT = "tables/independent_forecast_300_500_article_manifest_v1.json"
LEGACY_SHA = "8b85532496805dd1ff6c282c8f373a634d4ac3dc2a384b218ed18e313b248ff0"
PRESENTATION = "tables/qdesn_sections5_7_presentation_manifest.json"
PRESENTATION_SHA = "16e654c4c7c129f959a7492d33b3f0ad1ffe9bf7de381641c0a36a4936360305"
SCRIPT = "scripts/appendix_compression_validation_20261106.py"
BUILDER = "scripts/build_appendix_compact_tables_20261106.py"
DISPOSITION = "docs/reproducibility/appendix_compression_disposition_20261106.csv"
ARCHIVE = "docs/reproducibility/appendix_compression_archive_20261106.md"
ROLE_IDENTITIES_SHA = "090f4e16b8fadc5efdbda4bca0da9a3892c8e06e6d74430962d6775409c0e738"
PUBLIC_BASE = "https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/" + BASELINE + "/"
OUTER_MUTABLE = {"main.tex", "qdesn-supplement.tex", "overleaf/article_files.txt"}
VALIDATORS = (
    SCRIPT, BUILDER, "scripts/refresh_reader_online_appendix_receipts_20261106.py",
    "scripts/audit_qdesn_article_dependencies.py", "scripts/glofas_current_article_authority.py",
    "scripts/check_qdesn_mq_nomenclature.py", "scripts/check_qdesn_sections5_7_presentation.py",
    "application/tests/test_appendix_compression_20261106.py",
    "application/tests/test_reader_online_appendix_receipts_20261106.py",
    "scripts/independent_reporting_authority_checks.R",
    "scripts/check_independent_forecast_300_500_v1.R",
    "application/tests/test_independent_reporting_authority_checks.R",
    "application/tests/test_qdesn_mq_nomenclature.py",
    "application/tests/test_qdesn_sections5_7_presentation.py",
    "scripts/check_joint_qdesn_pure_desn_article_projection_v2.R",
    "application/tests/test_joint_qdesn_pure_desn_article_projection_v2.R",
    "application/tests/test_glofas_current_article_authority.py",
    "docs/reproducibility/appendix_compression_revision_20261106.md",
)
PREFIX = "tables/appendix_compact_20261106_"
TABLE_ROLES = ("glofas_specifications", "glofas_diagnostics", "glofas_convergence",
               "glofas_historical_scores", "mq_scores", "score_diagnostics")
FIGURE_ROLES = ("ind_forecast_mae", "ind_fit_rmse", "ind_sensitivity", "ind_frequencies", "mq_fit_rmse")
REQUIRED_DISPLAYS = tuple(PREFIX + name + ".tex" for name in TABLE_ROLES + FIGURE_ROLES)
REQUIRED_FIGURES = (
    "figures/quantile_initialization/quantile_initialization_picture.tex",
    "figures/independent_simulation/independent_train500_eval300_mcmc_forecast_mae_v1.pdf",
    "figures/independent_simulation/independent_train500_eval500_mcmc_forecast_mae_v1.pdf",
    "figures/independent_simulation/independent_train500_eval500_mcmc_forecast_check_v1.pdf",
    "figures/independent_simulation/independent_forecast_calibration_v1.pdf",
    "figures/independent_simulation/qdesn_pro_review_mcmc_fit_rmse.pdf",
    "figures/joint_qdesn_simulation/joint_qdesn_pure_desn_v2_mq_fit_oracle_rmse.pdf",
    "figures/glofas_application/glofas_same_family_20261103_all_families.pdf",
)
REQUIRED_EXTRA_EVIDENCE = (
    "tables/qdesn_multiquantile_crossing_display.tex",
    "tables/glofas_same_family_20261103_calibration.tex",
)
STALE_DISPLAYS = (
    "tables/qdesn_multiquantile_design_display.tex", "tables/qdesn_multiquantile_score_display.tex",
    "tables/qdesn_multiquantile_recursive_policy_display.tex",
    "tables/glofas_same_family_20261103_full_scores.tex",
    "tables/glofas_same_family_20261103_convergence.tex",
    "tables/glofas_reference_discrepancy_scores_display.tex",
    "tables/glofas_reference_discrepancy_priors_display.tex",
    "tables/glofas_selected_specifications_display.tex",
)


class CompressionError(Exception):
    pass


def require(value, message):
    if not value:
        raise CompressionError("APPENDIX_COMPRESSION_INVALID: " + message)


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
        value = json.loads(raw.decode(), object_pairs_hook=unique)
    except (UnicodeError, ValueError) as error:
        raise CompressionError("APPENDIX_COMPRESSION_INVALID: invalid JSON") from error
    require(isinstance(value, dict), "JSON object required")
    return value


def regular(root, relative, limit=32 * 1024**2):
    require(isinstance(relative, str) and relative and "\\" not in relative and
            not PurePosixPath(relative).is_absolute() and
            all(p not in ("", ".", "..", "local_trackers", "cache", "logs") for p in relative.split("/")) and
            Path(relative).suffix.lower() not in (".rds", ".rda", ".rdata"), "safe public source path required")
    path = Path(root) / relative
    require(path.is_file() and not any(p.is_symlink() for p in (path, *path.parents)) and
            0 < path.stat().st_size <= limit, "bounded regular public file required: " + relative)
    return path.read_bytes()


def git(root, *arguments):
    try:
        return subprocess.check_output(["git", "--no-replace-objects", "-C", str(root), *arguments], stderr=subprocess.PIPE)
    except (OSError, subprocess.CalledProcessError) as error:
        raise CompressionError("APPENDIX_COMPRESSION_INVALID: fixed Git ancestry/evidence unavailable") from error


def baseline_bytes(root, path):
    return git(root, "show", BASELINE + ":" + path)


def module(root, path, name):
    spec = importlib.util.spec_from_file_location(name, Path(root) / path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def active(root):
    # A namespace without its manifest must fail closed, not choose old checks.
    path = Path(root) / LEGACY_RECEIPT
    return (Path(root) / MANIFEST).is_file() or (path.is_file() and FIELD in decode(path.read_bytes()))


def uncomment(text):
    return re.sub(r"(?<!\\)%[^\n]*", "", text)


def plain(text):
    return re.sub(r"\s+", " ", uncomment(text))


def math(text):
    return re.sub(r"\s+|\\[,;! ]", "", uncomment(text))


def section(text, label):
    marker = "\\label{" + label + "}"
    require(text.count(marker) == 1, "one semantic section label required: " + label)
    return text.split(marker, 1)[1].split("\\section{", 1)[0]


def equation(text, label):
    """Find the defining equation/align, never a distant phrase elsewhere."""
    text = uncomment(text)
    marker = "\\label{" + label + "}"
    require(text.count(marker) == 1, "one defining mathematical label required: " + label)
    at = text.index(marker)
    begins = list(re.finditer(r"\\begin\{(equation\*?|align\*?)\}", text[:at]))
    require(begins, "display required for " + label)
    begin = begins[-1]
    end_marker = "\\end{" + begin.group(1) + "}"
    end = text.find(end_marker, at)
    require(end > at and end_marker not in text[begin.end():at], "complete defining display required: " + label)
    return math(text[begin.start():end])


def semantic_checks(main, supplement, bibliography):
    """Scoped mathematical and reporting obligations, not frozen prose."""
    m, s = plain(main), plain(supplement)
    a = math(section(supplement, "sec:dist_conventions"))
    b = plain(section(supplement, "sec:joint_qdesn_supp"))
    c = plain(section(supplement, "sec:forecast_synthesis"))
    glofas = plain(section(main, "sec:data") + " " + section(supplement, "sec:glofas_discrepancy")).lower()
    pricefm = plain(section(main, "sec:pricefm-application")).lower()
    bm, cm = math(b), math(c)
    all_text = (m + " " + s).lower()
    ns = equation(supplement, "eq:supp_ns_product_factor")
    full_ns = equation(supplement, "eq:supp_ns_full_prior")
    rhs = equation(supplement, "eq:supp_rhs_mcmc")
    moments = equation(supplement, "eq:supp_joint_increment_moments")
    forecast = equation(supplement, "eq:supp-forecast-mean-design")
    exal = equation(supplement, "eq:supp_glofas_unit_exal_updates")
    unit = equation(supplement, "eq:supp_glofas_unit_member_target")
    checks = {}
    checks["ns_scale_mass"] = all(x in ns for x in (
        r"\Normal(0\mid0,a+b)", r"\Normal(\beta_j\mid0,ab/(a+b))")) and all(x in full_ns for x in (
        r"\phi_1(\beta_0;b_0,V_0)", r"\phi_1(\beta_j;0,\tau^2\lambda_j^2)",
        r"\phi_1(0;\beta_j,\zeta^2)", r"p(\lambda_j^2\mid\nu_j)p(\nu_j)", r"p(\tau^2\mid\xi)p(\xi)p(\zeta^2)"))
    checks["ns_global_and_slab_shapes"] = (r"\IG\left(\frac{r+1}{2}," in rhs and
        r"\IG\left(a_\zeta+\frac{r}{2}," in rhs and r"\frac{1}{\tau_0^2}" in rhs)
    checks["ns_cavi_moments_and_shapes"] = ("eq:supp_generic_vb_rhs" in supplement and
        r"m_{\beta,j}^2+(\mat\Sigma_\beta)_{jj}" in a and
        (r"\frac{r+1}{2}" in a or "(r+1)/2" in a) and
        (r"a_\zeta+\frac{r}{2}" in a or r"a_\zeta+\fracr2" in a or r"a_\zeta+r/2" in a))
    checks["mq_full_target_and_covariance"] = (r"C_\Delta(\Theta_\Delta)p(\Theta_\Delta)" in bm and
        r"\vect\Delta_1=\vect\beta_1" in bm and
        r"\operatorname{diag}(\matH\mat\Sigma\matH^\top)" in moments and
        "point" in b and "intercept" in b and "uncertainty" in b)
    checks["glofas_exal_B_gamma"] = (r"\psi_c&=\frac{D_\gamma^2}{B_\gamma}\sum_i" in exal or
        r"\psi_c&=\frac{D_\gamma^2\sum_i" in exal and r"{B_\gamma}" in exal)
    checks["glofas_unit_member_target"] = (r"\prod_{h=1}^{28}\prod_{e=1}^{51}" in unit and
        r"\prod_{h=1}^{28}f_{p_k}" in unit and "1/51" not in unit and r"\frac{1}{51}" not in unit)
    checks["mean_feature_scored_functional"] = all(x in forecast for x in (
        r"\bar{\vectx}_{o+h}", r"\frac1M\sum_{j=1}^M", r"\beta_{0k}^{(b)}",
        r"\bar{\vectx}_{o+h}^{\top}\vect\beta_k^{(b)}")) and all(x in c.lower() for x in (
            "averaged design", "trajectory", "mixture", "histories")) and "neither" in c.lower()
    checks["trajectory_and_ordering"] = ("parameter draw" in c and "trajectory" in c and
        ("interpolation" in c or "interpolate" in c) and "outermost" in c and
        r"w_k=1" in cm and "sorting" in c and "before" in c.lower())
    weights = re.findall(r"(?:\d*\.\d+)(?:,\d*\.\d+){6}", cm)
    checks["score_weights_and_uncertainty"] = (any([float(x) for x in w.split(",")] ==
        [.025, .1, .2, .25, .2, .1, .025] for w in weights) and "0.90" in c and
        "95" in c and "descriptive" in c and "posterior-mean" in c)
    checks["structured_exal_and_ld"] = (all(x in supplement for x in (
        "eq:supp_structured_scale_integral", "eq:supp_generic_elbo", "eq:supp_elbo_transformed_coordinates")) and
        all(x in s.lower() for x in ("jacobian", "quadrature", "mixed moment")) and
        ("hessian" in s.lower() or r"-\nabla^2" in math(supplement)))
    checks["mixing_is_not_score_stability"] = ("mixing" in s.lower() and "score" in s.lower() and
        ("imperfect scale--shape mixing" in s.lower() or "imperfect scale–shape mixing" in s.lower()) and
        re.search(r"(?:score[^.]{0,260}(?:not|does not|do not)[^.]{0,160}(?:mixing|convergence)|"
                  r"(?:not|does not|do not)[^.]{0,220}mixing)", s, re.I) is not None and
        not re.search(r"(?:all|every)\s+(?:scalar[- ]parameter\s+|parameter\s+)?chains?[^.]{0,70}(?:mixed well|well[- ]mixed|converged)", all_text))
    checks["calibration_and_support_adverse_findings"] = (all(x in glofas for x in (
        "negative", "inver", "crossing", "calibration", "2 of 28", "raw ensemble")) and
        ("23.2--27.4" in glofas or "23.2" in glofas and "27.4" in glofas) and
        ("physical-support" in glofas or "physical support" in glofas))
    checks["adverse_quantile_model_comparison"] = re.search(
        r"all four[^.]{0,100}regressions[^.]{0,80}(?:above|higher than)[^.]{0,40}raw ensemble", glofas) is not None
    checks["selection_and_no_score_boundaries"] = ("inspecting" in s and "forecast" in s and
        "discrepancy" in s.lower() and ("unscored" in s.lower() or "not scored" in s.lower()) and
        "retrospective" in s.lower() and ("truth" in s.lower() or "unavailable" in s.lower() or
            "no future retrospective GloFAS is available" in s))
    checks["pricefm_direct_design"] = ("direct" in pricefm and "horizon" in pricefm and
        "not independently verified" in pricefm and "[PriceFM findings to be updated.]" in main)
    checks["main_model_targets_unchanged"] = all(x in math(main) for x in (
        r"\Normal(0\mid\beta_j,\zeta^2)", r"\Normal(\beta_j\mid0,\tau^2\lambda_j^2)",
        r"\sigma\sim\IG(a_\sigma,b_\sigma)", r"\xi\sim\IG(1/2,1/\tau_0^2)"))
    checks["proper_shape_and_forecast_scope"] = ("proper shape-prior density" in m and
        "supported on" in m and "shape at zero" in m and
        re.search(r"features averaged over (?:the |its )?simulated trajectories", m) is not None and
        "future USGS measurements are reserved for scoring" in m and
        "Both use realized values during the forecast window" in m and
        "Each level retains its own path" in s and
        "No additional observation error is added" in s and
        "no post-hoc crossing correction is applied" in s)
    checks["archive_and_citations"] = ((ARCHIVE in main + supplement or "appendix_compression_archive_20261106" in main + supplement) and
        "BracherEtAl2021WIS" in main and "10.1371/journal.pcbi.1008618" in bibliography)
    require(all(checks.values()), "current mathematical/reporting semantics: " +
            ", ".join(name for name, value in checks.items() if not value))
    return checks


def route_inventory(root):
    dependency = module(root, "scripts/audit_qdesn_article_dependencies.py", "compression_dependencies")
    encoded, _ = dependency.inventory(Path(root))
    return {r["file"]: sorted(filter(None, r["source_inferred_consumers"].split(";")))
            for r in csv.DictReader(io.StringIO(encoded))}


def visible_routes(root):
    """Exclude dormant macros and conditionals from mandatory evidence routes."""
    dependency = module(root, "scripts/audit_qdesn_article_dependencies.py", "compression_visible_dependencies")
    authority = module(root, "scripts/glofas_current_article_authority.py", "compression_visible_authority")
    consumers = {}
    for document in ("main.tex", "qdesn-supplement.tex"):
        aliases = {}
        def visit(path, stack=()):
            require(path not in stack and len(stack) < 32, "bounded visible TeX input graph required")
            text = uncomment(regular(root, path).decode())
            consumers.setdefault(path, set()).add(document)
            for match in dependency.TOKEN.finditer(text):
                if not authority.top_level(text, match.start()):
                    continue
                if match.group("name"):
                    aliases[match.group("name")] = match.group("value")
                    continue
                kind, target = match.group("kind"), match.group("target").strip()
                target = aliases.get(target[1:], "") if target.startswith("\\") else target
                if not target:
                    continue
                for relative in target.split(","):
                    extension = {"input": ".tex", "bibliography": ".bib", "bibliographystyle": ".bst"}.get(kind)
                    if extension and not Path(relative).suffix:
                        relative += extension
                    consumers.setdefault(relative, set()).add(document)
                    if kind == "input":
                        visit(relative, stack + (path,))
        visit(document)
    return {path: sorted(docs) for path, docs in consumers.items()}


def current_route_checks(root, rows=None):
    routes = route_inventory(root)
    visible = visible_routes(root)
    for path in REQUIRED_DISPLAYS + REQUIRED_FIGURES + REQUIRED_EXTRA_EVIDENCE:
        require("qdesn-supplement.tex" in routes.get(path, []) and
                "qdesn-supplement.tex" in visible.get(path, []), "mandatory appendix evidence is not selected: " + path)
    for path in REQUIRED_FIGURES[:-1]:
        require("main.tex" not in routes.get(path, []), "appendix figure must not move into main: " + path)
    for path in STALE_DISPLAYS:
        require("qdesn-supplement.tex" not in routes.get(path, []), "stale duplicate presentation selected: " + path)
    labels = set()
    for path, documents in routes.items():
        if "qdesn-supplement.tex" in documents and path.endswith(".tex"):
            labels.update(re.findall(r"\\label\{([^}]+)\}", uncomment(regular(root, path).decode())))
    for label in ("tab:joint-qdesn-pure-desn-v2-score", "tab:joint-qdesn-pure-desn-v2-recursive-policy"):
        require(label in labels, "combined primary/trajectory table label is not selected: " + label)
    return {path: docs for path, docs in routes.items() if docs}


def validate_archive_destination(row):
    """A frozen role determines its URL, including the exact first line range.

    The surrounding 92-role identity digest authenticates source and ranges.
    No network request or missing-Git fallback is needed in copied fixtures.
    """
    source = row["source"].split(";", 1)[0].strip()
    first_range = row["baseline_lines"].split(";", 1)[0].strip()
    match = re.fullmatch(r"([1-9][0-9]*)(?:-([1-9][0-9]*))?", first_range)
    require(match is not None and not PurePosixPath(source).is_absolute() and
            "\\" not in source and all(p not in ("", ".", "..") for p in source.split("/")),
            "frozen public source and numerical line range required: " + row["id"])
    start, end = match.groups()
    require(end is None or int(start) <= int(end), "ordered frozen archive line range required: " + row["id"])
    expected = PUBLIC_BASE + source + "#L" + start + ("-L" + end if end is not None else "")
    require(row["actual_destination"] == expected,
            "archive URL/path/line range differs from frozen role source: " + row["id"])
    return expected


def disposition_checks(root, routes):
    rows = list(csv.DictReader(io.StringIO(regular(root, DISPOSITION).decode())))
    identity_fields = ("id", "source", "baseline_lines", "labels")
    require(len(rows) == 92 and len({row["id"] for row in rows}) == 92 and
            sha(canonical([{k: row[k] for k in identity_fields} for row in rows])) == ROLE_IDENTITIES_SHA,
            "all 92 frozen role identities/ranges required, exactly once")
    for row in rows:
        disposition, target = row.get("semantic_disposition"), row.get("actual_destination", "")
        require(disposition in {"retained", "consolidated", "public_archive"} and target,
                "one explicit retained, consolidated or public-archive destination required: " + row["id"])
        if disposition == "public_archive":
            validate_archive_destination(row)
        else:
            path, separator, label = target.partition("#")
            require(path in routes and "qdesn-supplement.tex" in routes[path] or
                    path == "main.tex" and row["id"].startswith("F"),
                    "role destination is not an actual selected input: " + row["id"])
            if separator:
                require("\\label{" + label + "}" in uncomment(regular(root, path).decode()),
                        "role destination label missing: " + row["id"])
    archive = regular(root, ARCHIVE).decode()
    require(PUBLIC_BASE + "qdesn-supplement.tex" in archive and
            ("M01" in archive or "Known written correction" in archive) and
            "B_gamma" in archive and "rebuild" in archive.lower(), "archive must identify frozen source, M01 correction and rebuild procedure")
    return rows


def protected_inventory(root):
    """Pins come from the fixed ancestor, NEVER from current --refresh bytes."""
    entries = {}
    for record in git(root, "ls-tree", "-r", "-z", BASELINE).split(b"\0"):
        if not record:
            continue
        header, raw_path = record.split(b"\t", 1)
        mode, kind, identity = header.split()
        path = raw_path.decode()
        selected = (path.startswith(("application/R/", "application/config/")) or
            path.endswith((".csv", ".pdf")) or
            path.startswith("tables/") and path.endswith((".tex", ".json")) or
            path == "figures/quantile_initialization/quantile_initialization_picture.tex")
        if not selected or path in {LEGACY_RECEIPT, "docs/reproducibility/article_dependency_inventory.csv"}:
            continue
        require(kind == b"blob" and mode in (b"100644", b"100755"), "regular baseline public asset required: " + path)
        raw = regular(root, path)
        blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
        require(blob == identity.decode(), "frozen original scientific/presentation asset changed: " + path)
        entries[path] = sha(raw)
    require(entries, "nonempty fixed scientific inventory required")
    return entries


def expected_legacy(baseline, hashes):
    result = copy.deepcopy(baseline)
    for group in ("sources", "outputs"):
        for path in OUTER_MUTABLE:
            if path in result[group]:
                result[group][path] = hashes[path]
    result[FIELD] = dict(schema=SCHEMA, baseline_commit=BASELINE, manifest=MANIFEST)
    return result


def verify_legacy(current, baseline):
    restored = copy.deepcopy(current)
    namespace = restored.pop(FIELD, None)
    require(namespace is None or namespace == dict(schema=SCHEMA, baseline_commit=BASELINE, manifest=MANIFEST),
            "legacy successor namespace/scope changed")
    for group in ("sources", "outputs"):
        for path in OUTER_MUTABLE:
            if path in restored.get(group, {}):
                restored[group][path] = baseline[group][path]
    require(restored == baseline, "historical reader receipt or immutable outer scientific pins changed")


def dependency_paths(root):
    """Public copied-fixture closure, never application objects/runtime."""
    paths = {p for p in regular(root, "overleaf/article_files.txt").decode().splitlines() if p and not p.startswith("#")}
    paths.update(VALIDATORS + (DISPOSITION, ARCHIVE, "overleaf/article_files.txt", LEGACY_RECEIPT, PRESENTATION))
    builder = module(root, BUILDER, "compression_fixture_builder_dependencies")
    paths.update(builder.SOURCE_SHA256)
    if (Path(root) / MANIFEST).is_file():
        paths.add(MANIFEST)
    return paths


def derivative_checks(root):
    builder = module(root, BUILDER, "compression_compact_builder")
    # The producer's deterministic check must compare all generated text with
    # exact CSV-keyed renderings, not merely test that files exist.
    outputs = builder.build_outputs(Path(root))
    require(set(outputs) == set(REQUIRED_DISPLAYS), "exact compact derivative membership required")
    for path, text in outputs.items():
        require(regular(root, path) == text.encode(), "compact display differs from exact frozen-CSV rendering: " + path)
    return {"exact_derivatives": len(outputs), "mq_cell_keys": 32}


def prepare(root):
    root = Path(root).absolute()
    require(root.is_dir() and not any(p.is_symlink() for p in (root, *root.parents)), "regular repository root required")
    git(root, "merge-base", "--is-ancestor", BASELINE, "HEAD")
    original = baseline_bytes(root, LEGACY_RECEIPT)
    require(sha(original) == LEGACY_SHA and sha(baseline_bytes(root, PRESENTATION)) == PRESENTATION_SHA,
            "fixed baseline historical receipt identity differs")
    baseline, current = decode(original), decode(regular(root, LEGACY_RECEIPT))
    verify_legacy(current, baseline)
    protected = protected_inventory(root)
    require(sha(regular(root, PRESENTATION)) == PRESENTATION_SHA, "original presentation receipt changed")
    checks = semantic_checks(*(regular(root, p).decode() for p in ("main.tex", "qdesn-supplement.tex", "refs.bib")))
    routes = current_route_checks(root)
    roles = disposition_checks(root, routes)
    derivative_checks(root)
    authority = module(root, "scripts/glofas_current_article_authority.py", "compression_current_authority")
    authority.validate_authority_tree(root)
    paths = dependency_paths(root) - {MANIFEST, LEGACY_RECEIPT}
    hashes = {p: sha(regular(root, p)) for p in sorted(paths)}
    result = dict(schema=SCHEMA, baseline_commit=BASELINE, original_legacy_receipt_sha256=LEGACY_SHA,
        original_legacy_receipt=baseline,
        original_presentation_manifest_sha256=PRESENTATION_SHA,
        legacy_namespace=dict(field=FIELD, manifest=MANIFEST, mutable_outer_paths=sorted(OUTER_MUTABLE)),
        current_source_sha256=hashes, protected_source_sha256=protected,
        role_identities_sha256=ROLE_IDENTITIES_SHA, disposition_roles=len(roles),
        semantic_checks=sorted(checks), actual_input_routes=routes,
        scientific_values_changed=False, scientific_outputs_regenerated=False,
        fits_launched=0, forecasts_launched=0, scores_recomputed=0,
        source_ancestry_authenticated=True,
        fixture_policy="explicit_python_api_only_not_publication_no_missing_git_fallback")
    if (root / MANIFEST).exists():
        previous = decode(regular(root, MANIFEST))
        changing = {"current_source_sha256", "semantic_checks", "actual_input_routes"}
        require(previous.keys() == result.keys() and
                all(previous[k] == result[k] for k in result if k not in changing),
                "previous successor baseline, immutable scope, historical receipt or zero-run counters changed")
    legacy = expected_legacy(baseline, hashes)
    pins = dict(protected, **hashes)
    pins[LEGACY_RECEIPT] = sha(regular(root, LEGACY_RECEIPT))
    return root, result, legacy, pins


def refresh(root, write=False):
    root, result, legacy, pins = prepare(root)
    def stable(exclude=()):
        for path, digest in pins.items():
            if path not in exclude:
                require(sha(regular(root, path)) == digest, "source changed during validation: " + path)
    stable()
    if write:
        staged = []
        try:
            for path, value in ((MANIFEST, result), (LEGACY_RECEIPT, legacy)):
                with tempfile.NamedTemporaryFile(prefix=".appendix_compression_", dir=root / "tables", delete=False) as stream:
                    stream.write(canonical(value)); stream.flush(); os.fsync(stream.fileno())
                    staged.append((Path(stream.name), root / path))
            stable()
            for temporary, target in staged:
                os.replace(temporary, target)
            descriptor = os.open(root / "tables", os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
        finally:
            for temporary, _ in staged:
                if temporary.exists():
                    temporary.unlink()
        require(decode(regular(root, MANIFEST)) == result and decode(regular(root, LEGACY_RECEIPT)) == legacy,
                "receipt metadata readback differs")
        stable(exclude={LEGACY_RECEIPT})
    else:
        require(decode(regular(root, MANIFEST)) == result and decode(regular(root, LEGACY_RECEIPT)) == legacy,
                "explicit --refresh required for current compression sources/routes")
    return legacy


def portable_checks(root):
    """Explicit read-only copied fixture API; never full scientific admission."""
    root = Path(root).absolute()
    manifest = decode(regular(root, MANIFEST))
    require(manifest.get("schema") == SCHEMA and manifest.get("baseline_commit") == BASELINE and
        manifest.get("original_legacy_receipt_sha256") == LEGACY_SHA and
        manifest.get("source_ancestry_authenticated") is True and
        manifest.get("scientific_values_changed") is False and
        manifest.get("scientific_outputs_regenerated") is False and
        all(manifest.get(k) == 0 for k in ("fits_launched", "forecasts_launched", "scores_recomputed")),
        "copied fixture requires admitted compression metadata")
    for path, digest in manifest.get("current_source_sha256", {}).items():
        require(sha(regular(root, path)) == digest, "copied fixture current source differs: " + path)
    require(manifest.get("current_source_sha256"), "nonempty copied-fixture inventory required")
    baseline = manifest.get("original_legacy_receipt", {})
    require(sha(canonical(baseline)) == LEGACY_SHA, "copied fixture original receipt identity differs")
    current = decode(regular(root, LEGACY_RECEIPT))
    verify_legacy(current, baseline)
    require(current == expected_legacy(baseline, manifest["current_source_sha256"]),
            "copied fixture current outer receipt differs")
    semantic_checks(*(regular(root, p).decode() for p in ("main.tex", "qdesn-supplement.tex", "refs.bib")))
    require(current_route_checks(root) == manifest.get("actual_input_routes"), "copied fixture actual routes differ")
    disposition_checks(root, manifest["actual_input_routes"])
    derivative_checks(root)
    return dict(scope="controlled_copied_public_fixture_only", source_ancestry_authenticated=False,
                full_scientific_inventory_authenticated=False, metadata_written=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--refresh", action="store_true")
    args = parser.parse_args()
    try:
        refresh(args.root, write=args.refresh)
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 1
    print("APPENDIX_COMPRESSION_{} scientific_runs=0".format("REFRESHED" if args.refresh else "CHECK_PASS"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
