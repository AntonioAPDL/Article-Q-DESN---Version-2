#!/usr/bin/env python3
"""Read-only PriceFM Stage-R68 authority/comparator reconciliation."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from typing import Any

import pandas as pd

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
ARTICLE_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN---Version-2")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R62 = DATA / "authoritative/pricefm_stage_r62_matched_seven_quantile_authority_20260827"
R48 = DATA / "authoritative/pricefm_stage_r48_frozen_test_audit_closeout_20260808"
R50 = DATA / "authoritative/pricefm_stage_r50_mcmc_confirmation_closeout_20260809"
R54 = DATA / "authoritative/pricefm_stage_r54_exal_m0_closeout_20260812"
R65 = DATA / "authoritative/pricefm_stage_r65_early_stop_closeout_20260829"
R66 = DATA / "authoritative/pricefm_stage_r66_corrected_structured_exal_vb_prep_20260829"
R67 = DATA / "authoritative/pricefm_stage_r67_cran111_rhs_reuse_audit_20260830"
FULL_SURFACE = DATA / "authoritative/pricefm_full_surface_decision_closeout_20260704"
OPERATIONAL = DATA / "benchmarks/pricefm_operational_public_architecture_fullshot_20260812/post_closeout_audit"
OUTPUT = DATA / "authoritative/pricefm_stage_r68_authority_reconciliation_20260831"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--article-repo", type=Path, default=ARTICLE_REPO)
    p.add_argument("--r62-authority", type=Path, default=R62 / "pricefm_stage_r62_matched_seven_quantile_authority.csv")
    p.add_argument("--r62-queues", type=Path, default=R62 / "pricefm_stage_r62_mechanism_queues.csv")
    p.add_argument("--r62-summary", type=Path, default=R62 / "summary.json")
    p.add_argument("--r48-closeout", type=Path, default=R48 / "pricefm_stage_r48_case_closeout.csv")
    p.add_argument("--r48-summary", type=Path, default=R48 / "summary.json")
    p.add_argument("--r50-decision", type=Path, default=R50 / "pricefm_stage_r50_confirmation_decision.csv")
    p.add_argument("--r50-summary", type=Path, default=R50 / "summary.json")
    p.add_argument("--r54-decisions", type=Path, default=R54 / "pricefm_stage_r54_case_decisions.csv")
    p.add_argument("--r54-summary", type=Path, default=R54 / "summary.json")
    p.add_argument("--r65-summary", type=Path, default=R65 / "summary.json")
    p.add_argument("--r66-summary", type=Path, default=R66 / "summary.json")
    p.add_argument("--r67-summary", type=Path, default=R67 / "summary.json")
    p.add_argument("--cached-registry", type=Path, default=FULL_SURFACE / "pricefm_full_surface_decision_registry.csv")
    p.add_argument("--cached-summary", type=Path, default=FULL_SURFACE / "summary.json")
    p.add_argument("--operational-proposal", type=Path, default=OPERATIONAL / "pricefm_operational_comparator_proposal.csv")
    p.add_argument("--operational-summary", type=Path, default=OPERATIONAL / "summary.json")
    p.add_argument("--article-summary", type=Path, default=ARTICLE_REPO / "tables/pricefm_full_article_asset_summary.json")
    p.add_argument("--article-manifest", type=Path, default=ARTICLE_REPO / "tables/pricefm_full_article_asset_manifest.json")
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-cells", type=int, default=114)
    p.add_argument("--near-abs-gap", type=float, default=0.25)
    p.add_argument("--near-rel-gap", type=float, default=0.05)
    p.add_argument("--moderate-abs-gap", type=float, default=0.75)
    p.add_argument("--moderate-rel-gap", type=float, default=0.15)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def git_head(path: Path) -> str | None:
    if not path.exists():
        return None
    try:
        return subprocess.check_output(
            ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
        ).strip()
    except Exception:
        return None


def prepare_output(path: Path, force: bool) -> Path:
    path = path.resolve()
    if path.exists() and any(path.iterdir()):
        if not force:
            raise FileExistsError(path)
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)
    return path


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(Path(path).read_text())


def read_csv_required(path: Path, label: str) -> pd.DataFrame:
    if not Path(path).is_file():
        raise FileNotFoundError(f"Missing {label}: {path}")
    return pd.read_csv(path)


def read_csv_optional(path: Path) -> pd.DataFrame:
    return pd.read_csv(path) if Path(path).is_file() else pd.DataFrame()


def bool_series(frame: pd.DataFrame, column: str) -> pd.Series:
    if column not in frame:
        return pd.Series(False, index=frame.index)
    return frame[column].astype(str).str.strip().str.lower().isin({"1", "true", "yes", "y"})


def to_bool(value: Any) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def require_unique(frame: pd.DataFrame, keys: list[str], label: str) -> None:
    duplicated = frame.duplicated(keys, keep=False)
    if duplicated.any():
        sample = frame.loc[duplicated, keys].head(5).to_dict("records")
        raise RuntimeError(f"{label} has duplicate keys: {sample}")


def add_key(frame: pd.DataFrame) -> pd.DataFrame:
    frame = frame.copy()
    frame["fold"] = frame["fold"].astype(int)
    frame["region"] = frame["region"].astype(str)
    return frame


def validate_inputs(args: argparse.Namespace, frames: dict[str, pd.DataFrame], summaries: dict[str, dict]) -> None:
    r62 = frames["r62"]
    cached = frames["cached"]
    operational = frames["operational"]
    if len(r62) != args.expected_cells or summaries["r62"].get("matched_cells") != args.expected_cells:
        raise RuntimeError("Stage-R62 is not the complete expected authority surface")
    if not r62["selection_split"].astype(str).str.lower().eq("val").all():
        raise RuntimeError("Stage-R62 authority is not validation selected")
    if bool_series(r62, "test_opened").any() or bool(summaries["r62"].get("test_opened")):
        raise RuntimeError("Stage-R62 test firewall is open")
    if len(cached) != args.expected_cells:
        raise RuntimeError("Cached full-surface registry row count changed")
    if len(operational) != args.expected_cells:
        raise RuntimeError("Operational PriceFM comparator proposal row count changed")
    if not bool_series(operational, "whole_surface_included").all():
        raise RuntimeError("Operational PriceFM comparator is not an all-or-none full surface")
    if bool_series(operational, "paper_table_ii_equivalence_claimed").any():
        raise RuntimeError("Operational comparator unexpectedly claims PriceFM paper Table II equivalence")
    if bool_series(operational, "individual_row_promotion_authorized").any():
        raise RuntimeError("Operational comparator contains row-level test-selected promotion flags")
    if summaries["r65"].get("status") != "scientifically_stopped_mechanism_failure":
        raise RuntimeError("Stage-R65 is not frozen as a mechanism failure")
    if summaries["r54"].get("article_promotion_candidates") != 0:
        raise RuntimeError("Stage-R54 article-promotion count changed")
    if summaries["r50"].get("promotion_candidates") != 0:
        raise RuntimeError("Stage-R50 promotion count changed")
    if summaries["r67"].get("new_fit_package_authority") != "exact_CRAN_exdqlm_1.1.1_public_API":
        raise RuntimeError("Stage-R67 future-fit package authority changed")
    if summaries["r67"].get("historical_custom_engine_may_be_relabelled_as_cran111") is not False:
        raise RuntimeError("Historical custom engine relabelling is not blocked")


def family_action(family: str) -> str:
    family = str(family).lower()
    if family == "al":
        return "retain_al_anchor; no version-only refit; consider tau0/spec only if operational gap is targetable"
    if family == "exal":
        return "retain_legacy_exal_authority; future new exal fits must be CRAN_1.1.1_public_API"
    return "unknown_family_manual_review"


def gap_class(delta: float, reference: float, args: argparse.Namespace) -> str:
    if pd.isna(delta):
        return "missing_gap"
    if delta <= 0:
        return "qdesn_harm_guard_current_win"
    rel = delta / reference if reference and reference > 0 else float("inf")
    if delta <= args.near_abs_gap or rel <= args.near_rel_gap:
        return "near_miss_target"
    if delta <= args.moderate_abs_gap or rel <= args.moderate_rel_gap:
        return "moderate_gap_target"
    return "far_gap_hold"


def recommended_axis(row: pd.Series) -> str:
    family = str(row.get("selected_seven_quantile_family", "")).lower()
    cls = str(row.get("operational_gap_class", ""))
    if cls == "qdesn_harm_guard_current_win":
        return "none; preserve current Q-DESN result as harm guard"
    if cls == "far_gap_hold":
        return "none now; requires new mechanism evidence before expensive refit"
    if family == "al":
        return "independent_AL_anchor_plus_tau0_spec_sensitivity"
    if family == "exal":
        return "independent_CRAN111_exAL_anchor_plus_tau0_spec_sensitivity"
    return "manual_review"


def target_reason(row: pd.Series) -> str:
    pieces = []
    pieces.append(f"operational_gap={row.get('qdesn_minus_operational_pricefm_AQL'):.6g}")
    pieces.append(f"gap_class={row.get('operational_gap_class')}")
    pieces.append(f"r62_queue={row.get('mechanism_queue')}")
    if to_bool(row.get("r54_validation_selected", False)):
        pieces.append("r54_validation_selected_but_no_article_promotion")
    if to_bool(row.get("r50_mcmc_checked", False)):
        pieces.append("r50_mcmc_checked_no_promotion")
    return "; ".join(pieces)


def build_reconciliation(args: argparse.Namespace, frames: dict[str, pd.DataFrame]) -> pd.DataFrame:
    r62 = add_key(frames["r62"])
    queues = add_key(frames["queues"])
    cached = add_key(frames["cached"])
    op = add_key(frames["operational"])
    r48 = add_key(frames["r48"]) if not frames["r48"].empty else pd.DataFrame(columns=["region", "fold"])
    r50 = add_key(frames["r50"]) if not frames["r50"].empty else pd.DataFrame(columns=["region", "fold"])
    r54 = add_key(frames["r54"]) if not frames["r54"].empty else pd.DataFrame(columns=["region", "fold"])

    require_unique(r62, ["region", "fold"], "R62 authority")
    require_unique(queues, ["region", "fold"], "R62 queues")
    require_unique(cached, ["region", "fold"], "cached registry")
    require_unique(op, ["region", "fold"], "operational comparator")

    keep_r62 = [
        "case_id", "region", "fold", "selected_seven_quantile_family",
        "selected_method_id", "selected_seven_quantile_validation_AQL",
        "selected_panel_dir", "selected_base_id", "scientific_contract_sha256",
        "feature_semantics_sha256", "selection_split", "selection_metric",
        "test_opened",
    ]
    keep_queues = ["region", "fold", "mechanism_queue", "joint_contract_validation_AQL", "delta_joint_minus_independent"]
    keep_cached = [
        "region", "fold", "qdesn_method_id", "qdesn_AQL", "pricefm_method_id",
        "pricefm_AQL", "decision_label", "feature_policy", "input_scope",
        "spatial_information_set", "experiment_id", "evidence_path", "evidence_sha256",
    ]
    keep_op = [
        "region", "fold", "candidate_id", "canonical_degree", "validation_AQL",
        "test_AQL", "current_qdesn_AQL", "cached_pricefm_AQL",
        "comparison_outcome", "selector_evidence_tier", "whole_surface_included",
        "paper_table_ii_equivalence_claimed", "cached_replay_replacement_claimed",
    ]
    out = r62[keep_r62].merge(queues[keep_queues], on=["region", "fold"], how="left")
    out = out.merge(
        cached[keep_cached].rename(columns={
            "qdesn_AQL": "cached_registry_qdesn_test_AQL",
            "pricefm_AQL": "cached_registry_pricefm_test_AQL",
            "decision_label": "cached_registry_decision_label",
            "feature_policy": "cached_registry_feature_policy",
            "input_scope": "cached_registry_input_scope",
            "spatial_information_set": "cached_registry_spatial_information_set",
            "experiment_id": "cached_registry_experiment_id",
        }),
        on=["region", "fold"],
        how="left",
    )
    out = out.merge(
        op[keep_op].rename(columns={
            "candidate_id": "operational_pricefm_candidate_id",
            "canonical_degree": "operational_pricefm_canonical_degree",
            "validation_AQL": "operational_pricefm_validation_AQL",
            "test_AQL": "operational_pricefm_test_AQL",
            "current_qdesn_AQL": "operational_current_qdesn_test_AQL",
            "cached_pricefm_AQL": "operational_cached_pricefm_test_AQL",
            "comparison_outcome": "operational_comparison_outcome",
            "selector_evidence_tier": "operational_selector_evidence_tier",
        }),
        on=["region", "fold"],
        how="left",
    )
    if not r48.empty:
        r48_keep = [
            "region", "fold", "pooled_test_AQL", "authoritative_qdesn_AQL",
            "cached_pricefm_AQL", "beats_authoritative_qdesn", "beats_cached_pricefm",
            "mcmc_confirmation_eligible", "decision",
        ]
        out = out.merge(
            r48[r48_keep].rename(columns={
                "pooled_test_AQL": "r48_pooled_test_AQL",
                "authoritative_qdesn_AQL": "r48_authoritative_qdesn_AQL",
                "cached_pricefm_AQL": "r48_cached_pricefm_AQL",
                "beats_authoritative_qdesn": "r48_beats_authoritative_qdesn",
                "beats_cached_pricefm": "r48_beats_cached_pricefm",
                "mcmc_confirmation_eligible": "r48_mcmc_confirmation_eligible",
                "decision": "r48_decision",
            }),
            on=["region", "fold"],
            how="left",
        )
    if not r50.empty:
        r50_keep = [
            "region", "fold", "mcmc_pooled_test_AQL", "beats_authoritative_qdesn",
            "beats_cached_pricefm", "hard_convergence_pass", "promotion_eligible",
            "decision",
        ]
        out = out.merge(
            r50[r50_keep].rename(columns={
                "mcmc_pooled_test_AQL": "r50_mcmc_pooled_test_AQL",
                "beats_authoritative_qdesn": "r50_beats_authoritative_qdesn",
                "beats_cached_pricefm": "r50_beats_cached_pricefm",
                "hard_convergence_pass": "r50_hard_convergence_pass",
                "promotion_eligible": "r50_promotion_eligible",
                "decision": "r50_decision",
            }),
            on=["region", "fold"],
            how="left",
        )
    if not r54.empty:
        r54_keep = [
            "region", "fold", "m0_validation_AQL", "m0_test_AQL",
            "validation_selected", "diagnostics_pass", "beats_authoritative_qdesn",
            "beats_cached_pricefm", "internal_registry_promotion_candidate",
            "article_pricefm_promotion_candidate", "decision",
        ]
        out = out.merge(
            r54[r54_keep].rename(columns={
                "m0_validation_AQL": "r54_m0_validation_AQL",
                "m0_test_AQL": "r54_m0_test_AQL",
                "validation_selected": "r54_validation_selected",
                "diagnostics_pass": "r54_diagnostics_pass",
                "beats_authoritative_qdesn": "r54_beats_authoritative_qdesn",
                "beats_cached_pricefm": "r54_beats_cached_pricefm",
                "internal_registry_promotion_candidate": "r54_internal_registry_promotion_candidate",
                "article_pricefm_promotion_candidate": "r54_article_pricefm_promotion_candidate",
                "decision": "r54_decision",
            }),
            on=["region", "fold"],
            how="left",
        )

    numeric = [
        "selected_seven_quantile_validation_AQL", "cached_registry_qdesn_test_AQL",
        "cached_registry_pricefm_test_AQL", "operational_pricefm_test_AQL",
        "operational_current_qdesn_test_AQL", "operational_cached_pricefm_test_AQL",
    ]
    for column in numeric:
        out[column] = pd.to_numeric(out[column], errors="coerce")

    out["qdesn_test_AQL_source"] = "cached_full_surface_registry"
    out["qdesn_test_AQL_vs_operational_reference_abs_diff"] = (
        out["cached_registry_qdesn_test_AQL"] - out["operational_current_qdesn_test_AQL"]
    ).abs()
    out["cached_pricefm_reference_abs_diff"] = (
        out["cached_registry_pricefm_test_AQL"] - out["operational_cached_pricefm_test_AQL"]
    ).abs()
    out["qdesn_minus_cached_pricefm_AQL"] = (
        out["cached_registry_qdesn_test_AQL"] - out["cached_registry_pricefm_test_AQL"]
    )
    out["qdesn_minus_operational_pricefm_AQL"] = (
        out["cached_registry_qdesn_test_AQL"] - out["operational_pricefm_test_AQL"]
    )
    out["operational_pricefm_minus_cached_pricefm_AQL"] = (
        out["operational_pricefm_test_AQL"] - out["cached_registry_pricefm_test_AQL"]
    )
    out["operational_gap_class"] = [
        gap_class(delta, reference, args)
        for delta, reference in zip(
            out["qdesn_minus_operational_pricefm_AQL"],
            out["operational_pricefm_test_AQL"],
        )
    ]
    out["qdesn_beats_cached_pricefm"] = out["qdesn_minus_cached_pricefm_AQL"].lt(0)
    out["qdesn_beats_operational_pricefm"] = out["qdesn_minus_operational_pricefm_AQL"].lt(0)
    out["dual_comparator_current_qdesn_win"] = (
        out["qdesn_beats_cached_pricefm"] & out["qdesn_beats_operational_pricefm"]
    )
    out["r48_test_checked"] = out.get("r48_pooled_test_AQL", pd.Series(index=out.index)).notna()
    out["r50_mcmc_checked"] = out.get("r50_mcmc_pooled_test_AQL", pd.Series(index=out.index)).notna()
    out["family_reuse_action"] = out["selected_seven_quantile_family"].map(family_action)
    out["recommended_refit_axis"] = out.apply(recommended_axis, axis=1)
    out["same_failed_structured_exal_reuse_blocked"] = True
    out["cran111_public_api_required_for_new_fit"] = True
    out["launch_yaml_authorized"] = False
    out["registry_mutation_authorized"] = False
    out["article_mutation_authorized"] = False

    targetable_class = out["operational_gap_class"].isin(["near_miss_target", "moderate_gap_target"])
    out["targeted_refit_candidate"] = targetable_class & ~out["dual_comparator_current_qdesn_win"]
    out["refit_priority"] = "none"
    out.loc[out["operational_gap_class"].eq("near_miss_target"), "refit_priority"] = "priority_0_near_miss"
    out.loc[out["operational_gap_class"].eq("moderate_gap_target"), "refit_priority"] = "priority_1_moderate_gap"
    out.loc[out["operational_gap_class"].eq("far_gap_hold"), "refit_priority"] = "hold_far_gap"
    out.loc[out["operational_gap_class"].eq("qdesn_harm_guard_current_win"), "refit_priority"] = "harm_guard_keep_current"
    out["target_reason"] = out.apply(target_reason, axis=1)
    return out.sort_values(["targeted_refit_candidate", "qdesn_minus_operational_pricefm_AQL"], ascending=[False, True])


def comparator_policy(frames: dict[str, pd.DataFrame], summaries: dict[str, dict]) -> pd.DataFrame:
    cached = frames["cached"]
    op = frames["operational"]
    return pd.DataFrame([
        {
            "comparator": "cached_pricefm_released_checkpoint_replay",
            "role": "secondary_reproducible_comparator",
            "rows": len(cached),
            "mean_AQL": pd.to_numeric(cached["pricefm_AQL"], errors="coerce").mean(),
            "paper_table_equivalence_claimed": False,
            "whole_surface_required": True,
            "row_level_test_selection_allowed": False,
            "status": summaries["cached"].get("status", "completed"),
        },
        {
            "comparator": "operational_pricefm_public_architecture_replay",
            "role": "controlling_pricefm_refit_target",
            "rows": len(op),
            "mean_AQL": pd.to_numeric(op["test_AQL"], errors="coerce").mean(),
            "paper_table_equivalence_claimed": False,
            "whole_surface_required": True,
            "row_level_test_selection_allowed": False,
            "status": summaries["operational"].get("status", "completed"),
        },
        {
            "comparator": "pricefm_paper_table_ii",
            "role": "external_reported_context_only",
            "rows": "",
            "mean_AQL": 5.80,
            "paper_table_equivalence_claimed": True,
            "whole_surface_required": True,
            "row_level_test_selection_allowed": False,
            "status": "not_directly_reproduced_by_current_fold_aligned_artifacts",
        },
    ])


def promotion_gate_ledger(recon: pd.DataFrame) -> pd.DataFrame:
    return pd.DataFrame([
        {
            "region": row.region,
            "fold": int(row.fold),
            "selected_family": row.selected_seven_quantile_family,
            "full_seven_quantile_authority_present": True,
            "validation_selection_only": str(row.selection_split).lower() == "val",
            "current_qdesn_beats_cached_pricefm": bool(row.qdesn_beats_cached_pricefm),
            "current_qdesn_beats_operational_pricefm": bool(row.qdesn_beats_operational_pricefm),
            "dual_comparator_current_qdesn_win": bool(row.dual_comparator_current_qdesn_win),
            "existing_mcmc_confirmation_passed": False,
            "new_candidate_selected_on_test": False,
            "eligible_for_article_promotion_now": False,
            "reason": (
                "current Q-DESN is a harm-guard/reference row, not a new automatically promoted candidate"
                if row.dual_comparator_current_qdesn_win
                else "new promotion requires validation-selected refit beating cached and operational PriceFM"
            ),
        }
        for row in recon.itertuples(index=False)
    ])


def source_manifest(paths: list[Path]) -> pd.DataFrame:
    rows = []
    for path in dict.fromkeys(Path(p).resolve() for p in paths):
        if path.is_file():
            rows.append({"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size})
    return pd.DataFrame(rows)


def report(summary: dict[str, Any]) -> str:
    return f"""# PriceFM Stage-R68 Authority Reconciliation

## Decision

Stage-R68 is a read-only reconciliation stage. It does not launch, fit, mutate
the registry, update manuscript files, or write launch YAML. Its purpose is to
separate already-frozen evidence from genuinely justified future refits.

## Audited state

| Quantity | Value |
|---|---:|
| Region/fold cells | {summary['cells']} |
| R62 AL selections | {summary['r62_selected_family_counts'].get('al', 0)} |
| R62 exAL selections | {summary['r62_selected_family_counts'].get('exal', 0)} |
| Current Q-DESN beats cached PriceFM | {summary['qdesn_beats_cached_pricefm']} |
| Current Q-DESN beats operational PriceFM | {summary['qdesn_beats_operational_pricefm']} |
| Current Q-DESN beats both comparators | {summary['dual_comparator_current_qdesn_wins']} |
| Operational PriceFM beats current Q-DESN | {summary['operational_pricefm_beats_qdesn']} |
| Targeted refit candidates | {summary['targeted_refit_candidates']} |
| Far-gap hold rows | {summary['far_gap_hold_rows']} |

## Comparator policy

The operational fold-aligned PriceFM replay is the controlling PriceFM target
for future refits because it is the stronger full-surface comparator currently
available. The cached PriceFM replay remains a secondary reproducible reference.
The paper Table-II value remains external context only; this audit does not
claim exact Table-II replication.

## Refit policy

Do not refit all 114 rows. Refit only rows classified as near-miss or moderate
operational gaps, keep current Q-DESN winners as harm guards, and hold far-gap
rows until a new mechanism is justified. Any future new fit must use exact CRAN
exdqlm 1.1.1 public API, preserve validation-only selection, and block registry
and manuscript mutation until a separate promotion gate passes.

## Launch decision

`launch_authorized` is `{summary['launch_authorized']}`. Stage-R68 creates the
target queue needed for a future Stage-R69 launch-prep, but it intentionally
does not create a launch manifest or YAML.
"""


def run(args: argparse.Namespace) -> dict[str, Any]:
    output = prepare_output(args.output_dir, args.force)
    frames = {
        "r62": read_csv_required(args.r62_authority, "R62 authority"),
        "queues": read_csv_required(args.r62_queues, "R62 mechanism queues"),
        "r48": read_csv_optional(args.r48_closeout),
        "r50": read_csv_optional(args.r50_decision),
        "r54": read_csv_optional(args.r54_decisions),
        "cached": read_csv_required(args.cached_registry, "cached/full-surface registry"),
        "operational": read_csv_required(args.operational_proposal, "operational comparator proposal"),
    }
    summaries = {
        "r62": read_json(args.r62_summary),
        "r48": read_json(args.r48_summary) if args.r48_summary.is_file() else {},
        "r50": read_json(args.r50_summary),
        "r54": read_json(args.r54_summary),
        "r65": read_json(args.r65_summary),
        "r66": read_json(args.r66_summary),
        "r67": read_json(args.r67_summary),
        "cached": read_json(args.cached_summary),
        "operational": read_json(args.operational_summary),
        "article": read_json(args.article_summary) if args.article_summary.is_file() else {},
        "article_manifest": read_json(args.article_manifest) if args.article_manifest.is_file() else {},
    }
    validate_inputs(args, frames, summaries)
    recon = build_reconciliation(args, frames)
    target_queue = recon.loc[recon["targeted_refit_candidate"]].copy()
    reuse = recon.loc[~recon["targeted_refit_candidate"]].copy()
    policy = comparator_policy(frames, summaries)
    gates = promotion_gate_ledger(recon)
    global_gates = pd.DataFrame([
        {"gate": "r62_complete_validation_authority", "required": True, "passed": len(frames["r62"]) == args.expected_cells},
        {"gate": "operational_comparator_whole_surface", "required": True, "passed": bool_series(frames["operational"], "whole_surface_included").all()},
        {"gate": "paper_table_ii_not_claimed_reproduced", "required": True, "passed": not bool_series(frames["operational"], "paper_table_ii_equivalence_claimed").any()},
        {"gate": "r50_mcmc_has_no_promotion", "required": True, "passed": summaries["r50"].get("promotion_candidates") == 0},
        {"gate": "r54_exal_m0_has_no_article_promotion", "required": True, "passed": summaries["r54"].get("article_promotion_candidates") == 0},
        {"gate": "r65_structured_exal_frozen_negative", "required": True, "passed": summaries["r65"].get("status") == "scientifically_stopped_mechanism_failure"},
        {"gate": "future_new_fit_cran111_public_api", "required": True, "passed": summaries["r67"].get("new_fit_package_authority") == "exact_CRAN_exdqlm_1.1.1_public_API"},
        {"gate": "registry_article_mutation_blocked", "required": True, "passed": True},
        {"gate": "launch_yaml_absent", "required": True, "passed": True},
    ])
    if not global_gates.loc[global_gates.required, "passed"].all():
        failed = global_gates.loc[global_gates.required & ~global_gates.passed].to_dict("records")
        raise RuntimeError(f"Stage-R68 gates failed: {failed}")

    recon.to_csv(output / "pricefm_stage_r68_case_authority_reconciliation.csv", index=False)
    target_queue.to_csv(output / "pricefm_stage_r68_refit_target_queue.csv", index=False)
    reuse.to_csv(output / "pricefm_stage_r68_reuse_no_refit_ledger.csv", index=False)
    policy.to_csv(output / "pricefm_stage_r68_comparator_policy.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r68_promotion_gate_ledger.csv", index=False)
    global_gates.to_csv(output / "pricefm_stage_r68_global_gates.csv", index=False)

    family_counts = recon["selected_seven_quantile_family"].value_counts().to_dict()
    gap_counts = recon["operational_gap_class"].value_counts().to_dict()
    summary = {
        "status": "completed_read_only_authority_reconciliation",
        "recommended_next_action": "prepare_bounded_stage_r69_cran111_independent_vb_refit_only_for_target_queue_after_review",
        "cells": int(len(recon)),
        "r62_selected_family_counts": {str(k): int(v) for k, v in family_counts.items()},
        "operational_gap_class_counts": {str(k): int(v) for k, v in gap_counts.items()},
        "qdesn_beats_cached_pricefm": int(recon["qdesn_beats_cached_pricefm"].sum()),
        "qdesn_beats_operational_pricefm": int(recon["qdesn_beats_operational_pricefm"].sum()),
        "dual_comparator_current_qdesn_wins": int(recon["dual_comparator_current_qdesn_win"].sum()),
        "operational_pricefm_beats_qdesn": int((~recon["qdesn_beats_operational_pricefm"]).sum()),
        "targeted_refit_candidates": int(recon["targeted_refit_candidate"].sum()),
        "far_gap_hold_rows": int(recon["operational_gap_class"].eq("far_gap_hold").sum()),
        "mean_current_qdesn_test_AQL": float(recon["cached_registry_qdesn_test_AQL"].mean()),
        "mean_cached_pricefm_test_AQL": float(recon["cached_registry_pricefm_test_AQL"].mean()),
        "mean_operational_pricefm_test_AQL": float(recon["operational_pricefm_test_AQL"].mean()),
        "future_new_fit_package_authority": summaries["r67"].get("new_fit_package_authority"),
        "existing_authority_refit_required": False,
        "same_failed_structured_exal_reuse_authorized": False,
        "launch_authorized": False,
        "launch_yaml_written": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "test_opened_by_this_stage": False,
        "artifact_repo_head": git_head(args.artifact_repo),
        "article_repo_head": git_head(args.article_repo),
    }
    write_json(output / "summary.json", summary)

    source_paths = [
        args.r62_authority, args.r62_queues, args.r62_summary,
        args.r48_closeout, args.r48_summary,
        args.r50_decision, args.r50_summary,
        args.r54_decisions, args.r54_summary,
        args.r65_summary, args.r66_summary, args.r67_summary,
        args.cached_registry, args.cached_summary,
        args.operational_proposal, args.operational_summary,
        args.article_summary, args.article_manifest,
        Path(__file__).resolve(),
        Path(__file__).resolve().parents[2] / "tests/test_pricefm_stage_r68_authority_reconciliation.py",
        Path(__file__).resolve().parents[3] / "docs/implementation_notes/pricefm_stage_r68_authority_reconciliation_20260831.md",
    ]
    source_manifest(source_paths).to_csv(output / "source_manifest.csv", index=False)
    (output / "pricefm_stage_r68_authority_reconciliation_report.md").write_text(report(summary))
    if any(output.rglob("*.yaml")) or any(output.rglob("*.yml")):
        raise RuntimeError("Stage-R68 must not write launch YAML")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
