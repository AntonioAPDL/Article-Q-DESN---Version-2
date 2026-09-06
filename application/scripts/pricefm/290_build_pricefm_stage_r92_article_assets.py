#!/usr/bin/env python3
"""Build the PriceFM article tables from the frozen R92 selective update."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd


REPO_ROOT = Path(__file__).resolve().parents[3]
EVIDENCE_REPO_ROOT = Path("/data/jaguir26/local/src/Article-Q-DESN")
DEFAULT_R92 = (
    REPO_ROOT
    / "application/data_local/pricefm/authoritative/pricefm_stage_r92_selective_promotion_20260905"
)
DEFAULT_CONTEXT = REPO_ROOT / "tables/pricefm_paper_aligned_main_comparison.csv"
DEFAULT_TABLE_DIR = REPO_ROOT / "tables"
PROTECTED_CONTEXT_SHA256 = "9152364cf66f5bb2bef0e37c7e3747ac797d12784367671ae4686448f05a3f25"
PROTECTED_DIRECT_PRICEFM_SHA256 = "82fe5b4cddaf743aa1194dac69b7dbcce052dbee2d84013b704c7204733adde6"
PROTECTED_DIRECT_QDESN_STATIC_SHA256 = "bb2c8ca21525de2041b1fb843d65c6ff76170feecb6f04a77649fd12e04c9997"
EXPECTED_R92_SUMMARY_SHA256 = "ec878a5689273bd1f07c2e7cc2542105c0b71611f1f87e942b72b428afd7ac68"
EXPECTED_R92_OUTPUTS = {
    "decision_registry": (
        "pricefm_full_surface_decision_registry.csv",
        "3922a06a965e8eac6320edbc2cb38464c007c51698814b419271690f9a4c9f87",
    ),
    "promoted_case_metrics": (
        "pricefm_stage_r92_promoted_case_metrics.csv",
        "e3cd2649809df6befd950283c5c2813506ed87747cf39a84db3f6456ad94c3fc",
    ),
    "method_summary": (
        "pricefm_full_surface_method_summary.csv",
        "e9360aba0f606038441d1ae5e442ccacd4b6e09c43c8bf11a4b1153083de254b",
    ),
    "horizon_diagnostics": (
        "pricefm_full_surface_horizon_diagnostics.csv",
        "a7e9bd5de2de4900225c37e62c9bddc7d04e89223074630c3562de39fa92342b",
    ),
    "horizon_summary": (
        "pricefm_full_surface_horizon_summary.csv",
        "40f0c66fb1f9b10ed789b7f23561aafe1ad8b025f0b04bd738a3e3b623be4f44",
    ),
    "promotion_ledger": (
        "pricefm_stage_r92_promotion_ledger.csv",
        "ab6e0238450ac9bca9674ccd28517a87f2266837c594a84b3d5be4e74a96dde7",
    ),
    "source_manifest": (
        "source_manifest.csv",
        "acd44652d53788ecd337bf0b3fe388e9a368ff3ccb7b567015f6e030ec116b63",
    ),
    "report": (
        "pricefm_stage_r92_selective_promotion_report.md",
        "7ddde06d8ddcc4887669c187e55e913e0a453c1eb036b7b08e11473b98e1a1f3",
    ),
}
EXPECTED_PROMOTIONS = {
    ("AT", 1): "exal",
    ("BE", 2): "exal",
    ("DK_1", 3): "exal",
    ("DK_2", 2): "exal",
    ("DK_2", 3): "exal",
    ("ES", 1): "al",
    ("FR", 3): "exal",
    ("HU", 1): "exal",
    ("IT_CNOR", 1): "exal",
    ("IT_NORD", 3): "exal",
    ("LV", 3): "exal",
    ("SE_3", 1): "exal",
}
PROMOTED_COLUMNS = [
    "case_id", "region", "fold", "selected_family", "selected_validation_AQL",
    "candidate_test_AQL", "candidate_test_AQCR", "candidate_test_AQCR_percent",
    "candidate_test_MAE", "candidate_test_RMSE", "test_rows", "row_any_crossing_rate",
    "feature_policy", "input_scope", "spatial_information_set", "source_case_config",
    "source_case_config_sha256", "scaler_path", "scaler_sha256", "r90_terminal_path",
    "r90_terminal_sha256", "r90_model_fitted", "r90_selection_changed",
]
LEDGER_COLUMNS = [
    "region", "fold", "selected_family", "old_qdesn_method_id",
    "promoted_qdesn_method_id", "likelihood_family_changed", "selected_validation_AQL",
    "old_qdesn_AQL", "promoted_qdesn_AQL", "AQL_gain",
    "old_qdesn_AQCR_percent", "promoted_qdesn_AQCR_percent", "old_qdesn_MAE",
    "promoted_qdesn_MAE", "old_qdesn_RMSE", "promoted_qdesn_RMSE", "pricefm_AQL",
    "feature_policy", "input_scope", "spatial_information_set", "experiment_id",
    "source_case_config", "source_case_config_sha256", "r91_decision_path",
    "r91_decision_sha256",
]
REGISTRY_COLUMNS = [
    "region", "fold", "source_class", "qdesn_method_id", "qdesn_AQL",
    "pricefm_method_id", "pricefm_AQL", "delta_AQL_qdesn_minus_pricefm",
    "delta_rel_qdesn_minus_pricefm", "decision_label", "article_recommendation",
    "rescue_tier", "feature_policy", "input_scope", "spatial_information_set",
    "experiment_id", "selected_method_id", "selected_on_split", "selection_metric",
    "selection_metric_value", "selection_is_validation_only", "test_metrics_role",
    "paper_quantiles", "evidence_path", "evidence_sha256", "comparison_metric_root",
    "registry_source_path", "registry_source_sha256", "qdesn_beats_pricefm",
    "qdesn_beats_normal", "qdesn_beats_naive", "normal_AQL", "naive_AQL",
    "horizon_diagnostics_available",
]
EXPECTED_QDESN = {
    "AQL": 6.823677420470439,
    "AQCR_percent": 2.579293032015585,
    "MAE": 16.721997707630997,
    "RMSE": 25.449231419703835,
}
EXPECTED_PRICEFM = {
    "AQL": 7.038685346534470,
    "AQCR_percent": 0.0,
    "MAE": 17.27366671978033,
    "RMSE": 26.335538393719123,
}
EXPECTED_FULL56 = {
    "candidate": 6.704209343364271,
    "authoritative": 6.60763711322849,
    "pricefm": 6.897055829293184,
}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r92-dir", type=Path, default=DEFAULT_R92)
    p.add_argument("--context-csv", type=Path, default=DEFAULT_CONTEXT)
    p.add_argument("--table-dir", type=Path, default=DEFAULT_TABLE_DIR)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPO_ROOT.resolve()))
    except ValueError:
        return str(path.resolve())


def canonical_records_hash(frame: pd.DataFrame) -> str:
    payload = json.dumps(frame.to_dict("records"), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode()).hexdigest()


def require_close(observed: float, expected: float, label: str, tolerance: float = 1e-10) -> None:
    if not np.isclose(float(observed), float(expected), atol=tolerance, rtol=0.0):
        raise RuntimeError(f"{label} changed: {observed} != {expected}")


def bool_value(value: Any) -> bool:
    if isinstance(value, (bool, np.bool_)):
        return bool(value)
    text = str(value).strip().lower()
    if text in {"true", "1", "yes"}:
        return True
    if text in {"false", "0", "no"}:
        return False
    raise RuntimeError(f"Invalid Boolean value in R92 evidence: {value!r}")


def require_exact_columns(frame: pd.DataFrame, expected: list[str], label: str) -> None:
    if list(frame.columns) != expected:
        raise RuntimeError(f"{label} schema changed: {list(frame.columns)}")


def require_unique_keys(frame: pd.DataFrame, columns: list[str], label: str) -> None:
    if frame[columns].isna().any().any() or frame.duplicated(columns).any():
        raise RuntimeError(f"{label} contains missing or duplicate keys: {columns}")


def require_finite(frame: pd.DataFrame, columns: list[str], label: str) -> None:
    numeric = frame[columns].apply(pd.to_numeric, errors="coerce")
    if not np.isfinite(numeric.to_numpy()).all():
        raise RuntimeError(f"{label} contains a nonfinite numeric value")


def verify_r92_container(summary_path: Path, summary: dict[str, Any], paths: dict[str, Path]) -> None:
    observed_summary = sha256(summary_path)
    if observed_summary != EXPECTED_R92_SUMMARY_SHA256:
        raise RuntimeError(f"R92 summary hash changed: {observed_summary}")
    declared_hashes = summary.get("output_sha256", {})
    declared_outputs = summary.get("outputs", {})
    for role, (filename, expected_hash) in EXPECTED_R92_OUTPUTS.items():
        path = paths[role]
        if path.name != filename:
            raise RuntimeError(f"R92 {role} filename changed: {path.name}")
        expected_path = f"application/data_local/pricefm/authoritative/pricefm_stage_r92_selective_promotion_20260905/{filename}"
        declared_path = str(declared_outputs.get(role, ""))
        if declared_path != expected_path:
            raise RuntimeError(f"R92 summary assigns an unexpected file to {role}")
        declared_hash = str(declared_hashes.get(role, ""))
        if declared_hash != expected_hash:
            raise RuntimeError(f"R92 summary hash declaration changed for {role}")
        observed_hash = sha256(path)
        if observed_hash != expected_hash:
            raise RuntimeError(f"R92 {role} hash changed: {observed_hash}")


def resolve_manifest_source(source_root: str, recorded: str) -> Path:
    path = Path(recorded)
    if path.is_absolute():
        raise RuntimeError(f"R92 source manifest contains an absolute path: {path}")
    if source_root == "article_repository":
        root = REPO_ROOT.resolve()
    elif source_root == "protected_pricefm_evidence_repository":
        root = EVIDENCE_REPO_ROOT.resolve()
    else:
        raise RuntimeError(f"Unknown R92 source root: {source_root}")
    resolved = (root / path).resolve()
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise RuntimeError(f"R92 source path escapes its declared root: {recorded}") from exc
    return resolved


def verify_source_manifest(frame: pd.DataFrame) -> None:
    require_exact_columns(frame, ["label", "source_root", "path", "sha256", "bytes"], "R92 source manifest")
    require_unique_keys(frame, ["label"], "R92 source manifest labels")
    require_unique_keys(frame, ["path"], "R92 source manifest paths")
    if len(frame) != 94:
        raise RuntimeError(f"R92 source manifest row count changed: {len(frame)}")
    if set(frame.source_root.astype(str)) != {
        "article_repository", "protected_pricefm_evidence_repository"
    }:
        raise RuntimeError("R92 source manifest contains an unauthorized source root")
    if not frame.label.astype(str).str.strip().ne("").all() or not frame.path.astype(str).str.strip().ne("").all():
        raise RuntimeError("R92 source manifest contains a blank label or path")
    if not frame.sha256.astype(str).map(lambda value: bool(re.fullmatch(r"[0-9a-f]{64}", value))).all():
        raise RuntimeError("R92 source manifest contains an invalid SHA-256 value")
    byte_values = pd.to_numeric(frame.bytes, errors="coerce")
    if not np.isfinite(byte_values).all() or (byte_values < 0).any() or not np.equal(byte_values, np.floor(byte_values)).all():
        raise RuntimeError("R92 source manifest contains an invalid byte count")
    for row in frame.itertuples(index=False):
        path = resolve_manifest_source(str(row.source_root), str(row.path))
        if not path.is_file():
            raise FileNotFoundError(f"R92 source is unavailable: {path}")
        if path.stat().st_size != int(row.bytes):
            raise RuntimeError(f"R92 source byte count changed: {path}")
        observed = sha256(path)
        if observed != str(row.sha256):
            raise RuntimeError(f"R92 source hash changed: {path}")
    materializer = frame[frame.label.astype(str).eq("r92_materializer")]
    if len(materializer) != 1:
        raise RuntimeError("R92 source manifest does not identify one materializer")
    row = materializer.iloc[0]
    if (
        str(row.source_root) != "article_repository"
        or resolve_manifest_source(str(row.source_root), str(row.path)).resolve() != Path(__file__).with_name(
            "289_materialize_pricefm_stage_r92_selective_promotion.py"
        ).resolve()
    ):
        raise RuntimeError("R92 materializer provenance changed")


def verify_r92_relations(registry: pd.DataFrame, promoted: pd.DataFrame, ledger: pd.DataFrame) -> None:
    require_exact_columns(registry, REGISTRY_COLUMNS, "R92 registry")
    require_exact_columns(promoted, PROMOTED_COLUMNS, "R92 promoted-case metrics")
    require_exact_columns(ledger, LEDGER_COLUMNS, "R92 selective-update ledger")
    require_unique_keys(registry, ["region", "fold"], "R92 registry")
    require_unique_keys(promoted, ["region", "fold"], "R92 promoted-case metrics")
    require_unique_keys(promoted, ["case_id"], "R92 promoted-case identifiers")
    require_unique_keys(ledger, ["region", "fold"], "R92 selective-update ledger")
    observed = {
        (str(row.region), int(row.fold)): str(row.selected_family)
        for row in promoted.itertuples(index=False)
    }
    if observed != EXPECTED_PROMOTIONS:
        raise RuntimeError(f"R92 promotion set changed: {observed}")
    ledger_map = {
        (str(row.region), int(row.fold)): str(row.selected_family)
        for row in ledger.itertuples(index=False)
    }
    if ledger_map != EXPECTED_PROMOTIONS:
        raise RuntimeError(f"R92 ledger promotion set changed: {ledger_map}")
    require_finite(
        promoted,
        [
            "selected_validation_AQL", "candidate_test_AQL", "candidate_test_AQCR",
            "candidate_test_AQCR_percent", "candidate_test_MAE", "candidate_test_RMSE",
            "test_rows", "row_any_crossing_rate",
        ],
        "R92 promoted-case metrics",
    )
    require_finite(
        ledger,
        [
            "selected_validation_AQL", "old_qdesn_AQL", "promoted_qdesn_AQL",
            "AQL_gain", "old_qdesn_AQCR_percent", "promoted_qdesn_AQCR_percent",
            "old_qdesn_MAE", "promoted_qdesn_MAE", "old_qdesn_RMSE",
            "promoted_qdesn_RMSE", "pricefm_AQL",
        ],
        "R92 selective-update ledger",
    )
    if promoted.r90_model_fitted.map(bool_value).any() or promoted.r90_selection_changed.map(bool_value).any():
        raise RuntimeError("R92 promoted evidence unexpectedly records fitting or selection changes")
    if ledger.selected_family.value_counts().to_dict() != {"exal": 11, "al": 1}:
        raise RuntimeError("R92 likelihood-family counts changed")
    if int(ledger.likelihood_family_changed.map(bool_value).sum()) != 1:
        raise RuntimeError("R92 likelihood-family transition count changed")
    expected_methods = ledger.selected_family.map({
        "al": "qdesn_al_rhs_ns_exact_chunked",
        "exal": "qdesn_exal_rhs_ns_exact_chunked",
    })
    if not ledger.promoted_qdesn_method_id.astype(str).eq(expected_methods).all():
        raise RuntimeError("R92 selected family and method identifier disagree")

    joined = ledger.merge(
        promoted,
        on=["region", "fold"],
        suffixes=("_ledger", "_promoted"),
        validate="one_to_one",
    )
    equality_pairs = [
        ("selected_family_ledger", "selected_family_promoted"),
        ("feature_policy_ledger", "feature_policy_promoted"),
        ("input_scope_ledger", "input_scope_promoted"),
        ("spatial_information_set_ledger", "spatial_information_set_promoted"),
        ("source_case_config_ledger", "source_case_config_promoted"),
        ("source_case_config_sha256_ledger", "source_case_config_sha256_promoted"),
    ]
    for left, right in equality_pairs:
        if not joined[left].astype(str).eq(joined[right].astype(str)).all():
            raise RuntimeError(f"R92 promoted and ledger fields disagree: {left}, {right}")
    numeric_pairs = [
        ("selected_validation_AQL_ledger", "selected_validation_AQL_promoted"),
        ("promoted_qdesn_AQL", "candidate_test_AQL"),
        ("promoted_qdesn_AQCR_percent", "candidate_test_AQCR_percent"),
        ("promoted_qdesn_MAE", "candidate_test_MAE"),
        ("promoted_qdesn_RMSE", "candidate_test_RMSE"),
    ]
    for left, right in numeric_pairs:
        if not np.allclose(joined[left], joined[right], atol=1e-12, rtol=0.0):
            raise RuntimeError(f"R92 promoted and ledger metrics disagree: {left}, {right}")
    if not np.allclose(
        ledger.AQL_gain,
        ledger.old_qdesn_AQL - ledger.promoted_qdesn_AQL,
        atol=1e-12,
        rtol=0.0,
    ):
        raise RuntimeError("R92 AQL reductions do not reproduce")
    if not (ledger.promoted_qdesn_AQL < ledger.old_qdesn_AQL).all() or not (
        ledger.promoted_qdesn_AQL < ledger.pricefm_AQL
    ).all():
        raise RuntimeError("R92 ledger contains a non-dual improvement")

    registry_numeric = [
        "qdesn_AQL", "pricefm_AQL", "delta_AQL_qdesn_minus_pricefm",
        "delta_rel_qdesn_minus_pricefm", "selection_metric_value",
    ]
    require_finite(registry, registry_numeric, "R92 registry")
    if not np.allclose(
        registry.delta_AQL_qdesn_minus_pricefm,
        registry.qdesn_AQL - registry.pricefm_AQL,
        atol=1e-12,
        rtol=0.0,
    ):
        raise RuntimeError("R92 registry AQL differences do not reproduce")
    if not np.allclose(
        registry.delta_rel_qdesn_minus_pricefm,
        (registry.qdesn_AQL - registry.pricefm_AQL) / registry.pricefm_AQL,
        atol=1e-12,
        rtol=0.0,
    ):
        raise RuntimeError("R92 registry relative AQL differences do not reproduce")
    selected = registry.merge(ledger, on=["region", "fold"], suffixes=("_registry", "_ledger"), validate="many_to_one")
    if len(selected) != 12:
        raise RuntimeError("R92 registry-to-ledger join changed cardinality")
    string_pairs = [
        ("qdesn_method_id", "promoted_qdesn_method_id"),
        ("selected_method_id", "promoted_qdesn_method_id"),
        ("feature_policy_registry", "feature_policy_ledger"),
        ("input_scope_registry", "input_scope_ledger"),
        ("spatial_information_set_registry", "spatial_information_set_ledger"),
        ("experiment_id_registry", "experiment_id_ledger"),
    ]
    for left, right in string_pairs:
        if not selected[left].astype(str).eq(selected[right].astype(str)).all():
            raise RuntimeError(f"R92 registry and ledger fields disagree: {left}, {right}")
    metric_pairs = [
        ("qdesn_AQL", "promoted_qdesn_AQL"),
        ("pricefm_AQL_registry", "pricefm_AQL_ledger"),
        ("selection_metric_value", "selected_validation_AQL"),
    ]
    for left, right in metric_pairs:
        if not np.allclose(selected[left], selected[right], atol=1e-12, rtol=0.0):
            raise RuntimeError(f"R92 registry and ledger metrics disagree: {left}, {right}")
    if not selected.decision_label.astype(str).eq("qdesn_wins").all():
        raise RuntimeError("R92 updated registry rows changed decision")
    if not selected.article_recommendation.astype(str).eq("promote_qdesn").all():
        raise RuntimeError("R92 updated registry rows changed recommendation")
    if not selected.selected_on_split.astype(str).eq("val").all() or not selected.selection_metric.astype(str).eq("AQL").all():
        raise RuntimeError("R92 validation selection fields changed")
    if not selected.selection_is_validation_only.map(bool_value).all() or not selected.test_metrics_role.astype(str).eq("audit_only").all():
        raise RuntimeError("R92 validation/test roles changed")
    if not selected.qdesn_beats_pricefm.map(bool_value).all():
        raise RuntimeError("R92 updated rows no longer beat PriceFM")


def latex_escape(value: Any) -> str:
    text = str(value)
    replacements = {
        "\\": r"\textbackslash{}", "&": r"\&", "%": r"\%", "$": r"\$",
        "#": r"\#", "_": r"\_", "{": r"\{", "}": r"\}",
    }
    return "".join(replacements.get(char, char) for char in text)


def context_model_label(value: str) -> str:
    labels = {"Naive1": r"Na\"ive$^{1}$", "Naive2": r"Na\"ive$^{2}$", "Naive3": r"Na\"ive$^{3}$"}
    return labels.get(value, latex_escape(value))


def build_comparison_tex(frame: pd.DataFrame) -> str:
    direct = frame[frame.panel.eq("direct_replay")].reset_index(drop=True)
    context = frame[frame.panel.eq("paper_table_ii")].reset_index(drop=True)
    qdesn = direct[direct.model_family.eq("qdesn_case_specific")].iloc[0]
    pricefm = direct[direct.model_family.eq("pricefm_phase1_released_checkpoint")].iloc[0]
    lines = [
        r"\begingroup", r"\TableStyle", r"\scriptsize", r"\setlength{\tabcolsep}{5pt}",
        r"\begin{tabular}{@{}lrrrrr@{}}", r"\toprule",
        r"& \multicolumn{2}{c}{Probabilistic} & \multicolumn{2}{c}{Pointwise} & \\",
        r"\cmidrule(lr){2-3}\cmidrule(lr){4-5}",
        r"Model & AQL & AQCR (\%) & MAE & RMSE & Rank \\", r"\midrule",
        r"\multicolumn{6}{@{}l}{\textit{Direct fold-aligned comparison (this article; 114 region/fold evaluations)}} \\",
        f"Reported Q--DESN & \\textbf{{{float(qdesn.AQL):.2f}}} & {float(qdesn.AQCR_percent):.2f} & "
        f"\\textbf{{{float(qdesn.MAE):.2f}}} & \\textbf{{{float(qdesn.RMSE):.2f}}} & -- " + r"\\",
        f"Fixed PriceFM predictions & {float(pricefm.AQL):.2f} & \\textbf{{{float(pricefm.AQCR_percent):.2f}}} & "
        f"{float(pricefm.MAE):.2f} & {float(pricefm.RMSE):.2f} & -- " + r"\\",
        r"\addlinespace[3pt]",
        r"\multicolumn{6}{@{}l}{\textit{PriceFM v4 Table II (paper-reported all-region fitted evaluation)}} \\",
    ]
    group_breaks = {3, 8, 13}
    for index, row in context.iterrows():
        if index in group_breaks:
            lines.append(r"\addlinespace[1pt]")
        values = [f"{float(row[name]):.2f}" for name in ("AQL", "AQCR_percent", "MAE", "RMSE")]
        rank = str(row.paper_rank)
        if str(row.model) == "PriceFM":
            values = [rf"\textbf{{{value}}}" for value in values]
            rank = rf"\textbf{{{rank}}}"
        lines.append(f"{context_model_label(str(row.model))} & " + " & ".join(values + [rank]) + " " + r"\\")
    lines.extend([r"\bottomrule", r"\end{tabular}", r"\endgroup"])
    return "\n".join(lines) + "\n"


def build_promotion_tex(ledger: pd.DataFrame) -> str:
    lines = [
        r"\begingroup", r"\TableStyle", r"\scriptsize", r"\setlength{\tabcolsep}{4pt}",
        r"\begin{tabular}{@{}llrrrr@{}}", r"\toprule",
        r"Region--fold & Working likelihood & Updated Q--DESN AQL & Reference Q--DESN AQL & PriceFM AQL & AQL reduction \\",
        r"\midrule",
    ]
    for row in ledger.itertuples(index=False):
        family = r"\(\exAL\)" if str(row.selected_family) == "exal" else r"\(\AL\)"
        lines.append(
            f"{latex_escape(row.region)}--{int(row.fold)} & {family} & "
            f"{float(row.promoted_qdesn_AQL):.6f} & {float(row.old_qdesn_AQL):.6f} & "
            f"{float(row.pricefm_AQL):.6f} & {float(row.AQL_gain):.6f} " + r"\\"
        )
    lines.extend([r"\bottomrule", r"\end{tabular}", r"\endgroup"])
    return "\n".join(lines) + "\n"


def write_current_outputs(path: Path, qdesn: dict[str, float], pricefm: dict[str, float]) -> dict[str, float]:
    reductions = {
        "AQL": 100.0 * (pricefm["AQL"] - qdesn["AQL"]) / pricefm["AQL"],
        "MAE": 100.0 * (pricefm["MAE"] - qdesn["MAE"]) / pricefm["MAE"],
        "RMSE": 100.0 * (pricefm["RMSE"] - qdesn["RMSE"]) / pricefm["RMSE"],
    }
    text = "\n".join([
        r"\newcommand{\PricefmPaperAlignedMainComparisonTable}{tables/pricefm_paper_aligned_main_comparison.tex}",
        rf"\newcommand{{\PricefmAlignedQdesnAqcr}}{{{qdesn['AQCR_percent']:.2f}\%}}",
        rf"\newcommand{{\PricefmAlignedPricefmAqcr}}{{{pricefm['AQCR_percent']:.2f}\%}}",
        rf"\newcommand{{\PricefmAlignedQdesnMae}}{{{qdesn['MAE']:.3f}}}",
        rf"\newcommand{{\PricefmAlignedPricefmMae}}{{{pricefm['MAE']:.3f}}}",
        rf"\newcommand{{\PricefmAlignedQdesnRmse}}{{{qdesn['RMSE']:.3f}}}",
        rf"\newcommand{{\PricefmAlignedPricefmRmse}}{{{pricefm['RMSE']:.3f}}}",
        rf"\newcommand{{\PricefmAlignedAqlReduction}}{{{reductions['AQL']:.1f}\%}}",
        rf"\newcommand{{\PricefmAlignedMaeReduction}}{{{reductions['MAE']:.1f}\%}}",
        rf"\newcommand{{\PricefmAlignedRmseReduction}}{{{reductions['RMSE']:.1f}\%}}",
    ]) + "\n"
    path.write_text(text)
    return reductions


def run(args: argparse.Namespace) -> dict[str, Any]:
    r92 = args.r92_dir.resolve()
    context_path = args.context_csv.resolve()
    table_dir = args.table_dir.resolve()
    table_dir.mkdir(parents=True, exist_ok=True)
    required = {
        "summary": r92 / "summary.json",
        "decision_registry": r92 / "pricefm_full_surface_decision_registry.csv",
        "method_summary": r92 / "pricefm_full_surface_method_summary.csv",
        "horizon_diagnostics": r92 / "pricefm_full_surface_horizon_diagnostics.csv",
        "horizon_summary": r92 / "pricefm_full_surface_horizon_summary.csv",
        "promoted_case_metrics": r92 / "pricefm_stage_r92_promoted_case_metrics.csv",
        "promotion_ledger": r92 / "pricefm_stage_r92_promotion_ledger.csv",
        "source_manifest": r92 / "source_manifest.csv",
        "report": r92 / "pricefm_stage_r92_selective_promotion_report.md",
    }
    if any(not path.is_file() for path in required.values()):
        missing = [str(path) for path in required.values() if not path.is_file()]
        raise FileNotFoundError(f"Incomplete R92 source: {missing}")
    summary = json.loads(required["summary"].read_text())
    verify_r92_container(required["summary"], summary, required)
    registry = pd.read_csv(required["decision_registry"])
    promoted = pd.read_csv(required["promoted_case_metrics"])
    ledger = pd.read_csv(required["promotion_ledger"])
    sources = pd.read_csv(required["source_manifest"])
    verify_source_manifest(sources)
    verify_r92_relations(registry, promoted, ledger)
    context = pd.read_csv(context_path, dtype=str, keep_default_na=False)
    if summary.get("status") != "completed" or summary.get("stage") != "pricefm_stage_r92_selective_promotion":
        raise RuntimeError("R92 summary is not final")
    exact_summary = {
        "comparison_status_completed": True,
        "row_alignment_complete": True,
        "authorization_flag_present": True,
        "n_region_folds": 114,
        "n_regions": 38,
        "n_folds": 3,
        "cases": 56,
        "promoted_rows": 12,
        "unchanged_rows": 102,
        "promoted_exal_rows": 11,
        "promoted_al_rows": 1,
        "likelihood_family_changes": 1,
        "full_candidate_surface_promoted": False,
        "fits_models": False,
        "launches_models": False,
        "mutates_manuscript": False,
        "models_fitted": False,
        "selection_changed_after_test": False,
        "validation_selected_family_changed_during_test_scoring": False,
    }
    for name, expected in exact_summary.items():
        if summary.get(name) != expected:
            raise RuntimeError(f"R92 summary field changed: {name}={summary.get(name)!r}")
    if [float(value) for value in summary.get("expected_quantiles", [])] != [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]:
        raise RuntimeError("R92 quantile grid changed")
    for name, expected in EXPECTED_FULL56.items():
        require_close(float(summary[f"full_56_{name}_mean_AQL"]), expected, f"R92 56-case {name} AQL")
    if len(registry) != 114 or registry[["region", "fold"]].drop_duplicates().shape[0] != 114:
        raise RuntimeError("R92 registry is not 114 unique cases")
    if len(promoted) != 12 or len(ledger) != 12 or int(summary.get("unchanged_rows", -1)) != 102:
        raise RuntimeError("R92 selective-update counts changed")
    if registry.decision_label.value_counts().to_dict() != {
        "qdesn_wins": 66, "pricefm_wins": 36, "qdesn_close": 12,
    }:
        raise RuntimeError("R92 decision counts changed")
    if not (ledger.promoted_qdesn_AQL < ledger.old_qdesn_AQL).all() or not (ledger.promoted_qdesn_AQL < ledger.pricefm_AQL).all():
        raise RuntimeError("R92 ledger contains a non-dual improvement")
    if int(summary.get("replaced_horizon_rows", -1)) != 20 or int(summary.get("replaced_horizon_cases", -1)) != 5:
        raise RuntimeError("R92 horizon replacement boundary changed")
    if len(context) != 16 or (context.panel == "direct_replay").sum() != 2 or (context.panel == "paper_table_ii").sum() != 14:
        raise RuntimeError("Paper-aligned context changed dimensions")
    protected = context[context.panel.eq("paper_table_ii")].copy()
    protected_hash = canonical_records_hash(protected)
    if protected_hash != PROTECTED_CONTEXT_SHA256:
        raise RuntimeError(f"Protected PriceFM Table II context changed: {protected_hash}")

    qdesn = {name: float(summary["direct_comparison_metrics"]["qdesn"][name]) for name in EXPECTED_QDESN}
    pricefm = {name: float(summary["direct_comparison_metrics"]["pricefm"][name]) for name in EXPECTED_PRICEFM}
    historical = summary["historical_direct_comparison_metrics"]["qdesn"]
    for name, expected in EXPECTED_QDESN.items():
        require_close(qdesn[name], expected, f"R92 Q-DESN {name}")
        ledger_old = "old_qdesn_AQCR_percent" if name == "AQCR_percent" else f"old_qdesn_{name}"
        ledger_new = "promoted_qdesn_AQCR_percent" if name == "AQCR_percent" else f"promoted_qdesn_{name}"
        reconstructed = float(historical[name]) + float((ledger[ledger_new] - ledger[ledger_old]).sum()) / 114.0
        require_close(reconstructed, qdesn[name], f"R92 reconstructed Q-DESN {name}")
    for name, expected in EXPECTED_PRICEFM.items():
        require_close(pricefm[name], expected, f"R92 PriceFM {name}")
    require_close(registry.qdesn_AQL.mean(), qdesn["AQL"], "R92 registry mean Q-DESN AQL")
    require_close(registry.pricefm_AQL.mean(), pricefm["AQL"], "R92 registry mean PriceFM AQL")
    require_close(
        registry.delta_AQL_qdesn_minus_pricefm.mean(),
        float(summary["mean_delta_AQL_qdesn_minus_pricefm"]),
        "R92 registry mean AQL difference",
    )
    require_close(
        registry.delta_AQL_qdesn_minus_pricefm.median(),
        float(summary["median_delta_AQL_qdesn_minus_pricefm"]),
        "R92 registry median AQL difference",
    )

    direct_q = context[context.model_family.eq("qdesn_case_specific")]
    direct_p = context[context.model_family.eq("pricefm_phase1_released_checkpoint")]
    if len(direct_q) != 1 or len(direct_p) != 1:
        raise RuntimeError("Direct comparison rows changed identity")
    direct_pricefm_hash = canonical_records_hash(direct_p)
    if direct_pricefm_hash != PROTECTED_DIRECT_PRICEFM_SHA256:
        raise RuntimeError(f"Protected direct PriceFM row changed: {direct_pricefm_hash}")
    direct_q_static_hash = canonical_records_hash(
        direct_q.drop(columns=["AQL", "AQCR_percent", "MAE", "RMSE", "value_source"])
    )
    if direct_q_static_hash != PROTECTED_DIRECT_QDESN_STATIC_SHA256:
        raise RuntimeError(f"Protected direct Q-DESN metadata changed: {direct_q_static_hash}")
    for name, expected in pricefm.items():
        require_close(float(direct_p.iloc[0][name]), expected, f"Protected direct PriceFM {name}")
    metric_names = list(EXPECTED_QDESN)
    observed_vector = np.array([float(direct_q.iloc[0][name]) for name in metric_names])
    historical_vector = np.array([float(historical[name]) for name in metric_names])
    r92_vector = np.array([qdesn[name] for name in metric_names])
    if not (
        np.allclose(observed_vector, historical_vector, atol=1e-10, rtol=0.0)
        or np.allclose(observed_vector, r92_vector, atol=1e-10, rtol=0.0)
    ):
        raise RuntimeError("Direct Q-DESN context mixes or changes metric generations")

    updated = context.copy()
    qindex = updated.index[updated.model_family.eq("qdesn_case_specific")][0]
    for name, value in qdesn.items():
        updated.loc[qindex, name] = repr(value)
    updated.loc[qindex, "value_source"] = "r92_selective_promotion_reconstruction"
    comparison_csv = table_dir / "pricefm_paper_aligned_main_comparison.csv"
    comparison_tex = table_dir / "pricefm_paper_aligned_main_comparison.tex"
    current_outputs = table_dir / "pricefm_paper_aligned_current_outputs.tex"
    promotion_csv = table_dir / "pricefm_r91_selective_promotions.csv"
    promotion_tex = table_dir / "pricefm_r91_selective_promotions.tex"
    updated.to_csv(comparison_csv, index=False, lineterminator="\n")
    comparison_tex.write_text(build_comparison_tex(updated))
    ledger = ledger.sort_values(["AQL_gain", "region", "fold"], ascending=[False, True, True], kind="mergesort").reset_index(drop=True)
    ledger.to_csv(promotion_csv, index=False, lineterminator="\n")
    promotion_tex.write_text(build_promotion_tex(ledger))
    reductions = write_current_outputs(current_outputs, qdesn, pricefm)

    outputs = [comparison_csv, comparison_tex, current_outputs, promotion_csv, promotion_tex]
    output_records = [
        {"path": f"tables/{path.name}", "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in outputs
    ]
    manifest = {
        "stage": "pricefm_stage_r92_article_assets",
        "status": "completed",
        "paper_source": {
            "arxiv_id": "2508.04875",
            "arxiv_version": 4,
            "revision_date": "2026-05-08",
            "source_url": "https://arxiv.org/abs/2508.04875v4",
            "source_table": "Experiment.tex, Table II (full-shot evaluation)",
            "source_archive_sha256": "76fa40e20bb07ccf556eca3ba92fc7e1720fd31ab554151466b546086872be6e",
            "upstream_git_commit": "c72d1228bde80417d5cc782521328e02ab5401c3",
        },
        "applicability": {
            "primary_pricefm_table": "Table II: full-shot evaluation",
            "reason": (
                "The article fits and validation-selects a region/fold-specific Q-DESN "
                "using observations from each target region."
            ),
            "not_primary": "Table III: leave-one-region-out zero-shot evaluation",
            "cross_panel_comparison": "context_only_not_head_to_head",
        },
        "source": {
            name: {"path": relative(path), "sha256": sha256(path)}
            for name, path in required.items()
        },
        "generator": {
            "path": relative(Path(__file__)),
            "sha256": sha256(Path(__file__)),
        },
        "protected_context": {
            "rows": 14,
            "canonical_sha256": protected_hash,
            "role": "PriceFM version 4 Table II context",
        },
        "direct_comparison_metrics": {"qdesn": qdesn, "pricefm": pricefm},
        "relative_reductions_percent": reductions,
        "outputs": output_records,
    }
    manifest_path = table_dir / "pricefm_paper_aligned_main_comparison_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    if any(Path(row["path"]).name == manifest_path.name for row in manifest["outputs"]):
        raise RuntimeError("PriceFM article manifest cannot hash itself")
    for row, path in zip(manifest["outputs"], outputs):
        if sha256(path) != row["sha256"] or path.stat().st_size != int(row["bytes"]):
            raise RuntimeError(f"Generated PriceFM article asset changed: {path}")
    verify_source_manifest(pd.read_csv(required["source_manifest"]))
    result = {
        "status": "completed",
        "context_rows_preserved": 14,
        "promotion_rows": 12,
        "qdesn": qdesn,
        "pricefm": pricefm,
        "relative_reductions_percent": reductions,
        "manifest": relative(manifest_path),
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return result


def main() -> int:
    run(parser().parse_args())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
