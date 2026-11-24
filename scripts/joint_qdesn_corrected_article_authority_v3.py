#!/usr/bin/env python3.11
"""Explicit current JOINT projection admission, separate from frozen v1/v2.

Only the reviewed November 23 summary projection and its three reader roles
can advance. Historical numerical inputs, contracts and derivatives remain
authenticated by their existing guards. No runtime payload is read or written.
"""
from __future__ import annotations

import csv
import hashlib
import io
from pathlib import Path, PurePosixPath
import re

PREFIX = "tables/joint_qdesn_corrected_v3_"
MANIFEST = PREFIX + "article_asset_manifest.csv"
MANIFEST_SHA256 = "e2538ade281b8f11ca1c8740a5974d4b5207f8538397c687a74c3ac11c0be8df"
SELECTED = PREFIX + "selected_mcmc_score_summary.csv"
SELECTED_SHA256 = "69aced9bbd37ee506a382ed85a7fe2aba116ed296ae4285890540e572122f5f3"
SOURCE_HEAD = "5ad779121e44330e5a08baee1a44d77ba722b5cd"
HELPER = "scripts/joint_qdesn_corrected_article_authority_v3.py"
CHECKER = "scripts/check_joint_qdesn_corrected_article_projection_v3.R"
TEST = "application/tests/test_joint_qdesn_corrected_article_projection_v3.R"
BUILDER = "scripts/build_joint_qdesn_corrected_article_projection_v3.R"
FORECAST = PREFIX + "forecast_figure.tex"
SCORES = PREFIX + "compact_scores.tex"
CROSSINGS = PREFIX + "compact_crossings.tex"
FORECAST_PDF = "figures/joint_qdesn_simulation/joint_qdesn_corrected_v3_forecast_dgp_acrps.pdf"
ROLE_OVERRIDES = {
    "mq_sensitivity": SCORES + "#tab:joint-qdesn-pure-desn-v2-recursive-policy",
    "mq_crossings": CROSSINGS + "#tab:joint-qdesn-pure-desn-v2-crossings",
}
SCENARIOS = frozenset(("asymmetric_laplace_tail", "gaussian_mixture_bridge", "laplace_bridge",
    "nonlinear_reservoir_friendly", "normal_bridge", "persistent_heavy_tail",
    "regime_shift", "student_t_location_scale"))
MODELS = frozenset(("joint_qdesn_rhs", "independent_qdesn_rhs",
    "joint_exqdesn_rhs", "independent_exqdesn_rhs"))


def require(value, message):
    if not value:
        raise ValueError("JOINT_CORRECTED_V3_AUTHORITY_INVALID: " + message)


def raw(root, relative):
    parts = PurePosixPath(relative)
    require(not parts.is_absolute() and not any(p in ("..", "cache", "local_trackers", "logs") for p in parts.parts),
            "unsafe article dependency")
    path = Path(root) / relative
    require(path.is_file() and not path.is_symlink() and 0 < path.stat().st_size < 32 * 1024**2,
            "bounded article file missing: " + relative)
    return path.read_bytes()


def digest(value):
    return hashlib.sha256(value).hexdigest()


def requested(root):
    root = Path(root)
    selected = any("joint_qdesn_corrected_v3_" in re.sub(r"(?<!\\)%[^\n]*", "", (root / p).read_text())
                   for p in ("main.tex", "qdesn-supplement.tex") if (root / p).is_file())
    return (root / MANIFEST).exists() or selected


def assets(root):
    data = raw(root, MANIFEST)
    require(digest(data) == MANIFEST_SHA256, "reviewed projection manifest changed")
    rows = list(csv.DictReader(io.StringIO(data.decode())))
    names = [r["relative_path"] for r in rows]
    require(len(names) == len(set(names)) and names, "unique nonempty asset manifest required")
    for row in rows:
        name = row["relative_path"]
        require(name.startswith(PREFIX) or name.startswith("figures/joint_qdesn_simulation/joint_qdesn_corrected_v3_"),
                "unreviewed projection path: " + name)
        require(Path(name).suffix in (".csv", ".tex", ".pdf", ".json"), "article-safe suffix required")
        require(row["source_lane_head"] == SOURCE_HEAD, "wrong scientific source head")
        content = raw(root, name)
        require(len(content) == int(row["size_bytes"]) and digest(content) == row["sha256"],
                "projection asset bytes/hash mismatch: " + name)
    require({SELECTED, FORECAST, SCORES, CROSSINGS, FORECAST_PDF} <= set(names),
            "complete current projection missing")
    require(digest(raw(root, SELECTED)) == SELECTED_SHA256, "selected 32-row source identity changed")
    selected = list(csv.DictReader(io.StringIO(raw(root, SELECTED).decode())))
    require(len(selected) == 32 and {(r["scenario_id"], r["model_id"]) for r in selected} ==
            {(s, m) for s in SCENARIOS for m in MODELS}, "exact eight-by-four selected packet required")
    require(all(r["inference_method"] == "mcmc" for r in selected), "selected packet must be MCMC")
    require(len({r["specification_role"] for r in selected if r["scenario_id"] == "persistent_heavy_tail"}) == 1 and
            all(r["specification_role"] == "new_geometry_parity" for r in selected if r["scenario_id"] == "persistent_heavy_tail"),
            "complete persistent-heavy-tail parity fallback required")
    return set(names)


def admit(root):
    names = assets(root)
    return dict(schema="joint-corrected-article-authority-v3", source_head=SOURCE_HEAD,
        selected_packet_sha256=SELECTED_SHA256, manifest=MANIFEST,
        manifest_sha256=MANIFEST_SHA256, roles=ROLE_OVERRIDES,
        scientific_authority_replaced=True, article_scores_replaced=True,
        historical_compression_flags_scope="original_20261106_compression_only_not_successor_numerical_equality",
        projection_only_no_new_fits=True)


def dependency_paths(root):
    return assets(root) | {MANIFEST, HELPER, CHECKER, TEST, BUILDER}
