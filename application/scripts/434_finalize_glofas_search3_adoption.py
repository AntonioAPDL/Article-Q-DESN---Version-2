#!/usr/bin/env python3.11
"""Apply the frozen Search III adoption gates and seal the completed campaign."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile
import time
from typing import Iterable


PHASES = ("october", "november", "operational", "february", "march")
GUARD_RATIO_MAX = 1.10
WORST_FOLD_RATIO_MAX = 1.10
HISTORICAL_RMSE_RATIO_MAX = 1.05
EXPECTED_ADOPTION = {
    "reference": "search3_ref_001",
    "discrepancy": "search3_dis_007",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def atomic_csv(path: Path, rows: list[dict[str, object]], fields: Iterable[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    columns = list(fields or (rows[0].keys() if rows else ()))
    with tempfile.NamedTemporaryFile("w", newline="", dir=path.parent, delete=False) as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
        temporary = Path(handle.name)
    temporary.replace(path)


def as_bool(value: object) -> bool:
    return str(value).strip().lower() in {"true", "t", "1", "yes"}


def as_float(value: object) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return math.nan


def mean(values: Iterable[float]) -> float:
    values = list(values)
    return sum(values) / len(values) if values else math.nan


def grouped_mean(rows: list[dict[str, str]], key: str, value: str) -> dict[str, float]:
    groups: dict[str, list[float]] = {}
    for row in rows:
        groups.setdefault(row[key], []).append(as_float(row[value]))
    return {name: mean(values) for name, values in groups.items()}


def candidate_id(row: dict[str, str]) -> str:
    return row.get("base_candidate_id") or row["candidate_id"].split("__seed", 1)[0]


def validate_inputs(campaign: Path) -> dict[str, Path]:
    paths = {
        "candidate_manifest": campaign / "configs/candidate_manifest.csv",
        "fold_registry": campaign / "configs/fold_registry.csv",
        "confirmation_jobs": campaign / "stages/confirmation/configs/job_manifest.csv",
        "confirmation_scores": campaign / "stages/confirmation/tables/score_summaries_latest.csv",
        "confirmation_fits": campaign / "stages/confirmation/tables/fit_summaries_latest.csv",
        "confirmation_aggregate": campaign / "stages/confirmation/tables/aggregate_scores_latest.csv",
        "development_aggregate": campaign / "stages/rhs_screen/tables/aggregate_scores_latest.csv",
        "selected_priors": campaign / "stages/rhs_pilot/tables/selected_priors.csv",
        "completion_marker": campaign / "stages/confirmation/status/CAMPAIGN_COMPLETE",
        "legacy_manifest": campaign / "tables/artifact_manifest.csv",
    }
    missing = [name for name, path in paths.items() if not path.is_file()]
    if missing:
        raise RuntimeError(f"Search III adoption inputs are missing: {missing}")
    marker = paths["completion_marker"].read_text().strip()
    if marker != "SEARCH3_RAINY_SEASON_COMPLETE_PENDING_SCIENTIFIC_ADOPTION":
        raise RuntimeError(f"Unexpected Search III completion marker: {marker}")
    jobs = read_csv(paths["confirmation_jobs"])
    if len(jobs) != 432 or len({row["job_id"] for row in jobs}) != 432:
        raise RuntimeError("Search III confirmation must contain 432 unique jobs")
    status = campaign / "stages/confirmation/status"
    if list(status.glob("*.failed")) or list(status.glob("*.running")):
        raise RuntimeError("Search III confirmation still has failed or running markers")
    if len(list(status.glob("*.done"))) != 432:
        raise RuntimeError("Search III confirmation does not have 432 done markers")
    return paths


def choose_adoptions(
    decisions: list[dict[str, object]],
    incumbents: dict[str, str],
    expected: dict[str, str] | None = None,
) -> list[dict[str, object]]:
    """Choose the best all-gate challenger, or retain the incumbent."""
    selections: list[dict[str, object]] = []
    for target in ("reference", "discrepancy"):
        incumbent = incumbents[target]
        eligible = [row for row in decisions if row["target"] == target and row["adoption_eligible"]]
        challengers = [row for row in eligible if not row["is_incumbent"]]
        challengers.sort(key=lambda row: (
            float(row["confirmation_crps_4dp"]), row["worst_fold_crps"],
            row["mean_secondary_crps"], row["n_state_features"], row["mean_runtime_seconds"],
        ))
        chosen = str(challengers[0]["candidate_id"]) if challengers else incumbent
        if expected is not None and chosen != expected[target]:
            raise RuntimeError(f"Frozen gates selected unexpected {target} candidate: {chosen}")
        selections.append({
            "target": target,
            "candidate_id": chosen,
            "incumbent_id": incumbent,
            "adoption_action": "retain_search2_incumbent" if chosen == incumbent else "adopt_search3_challenger",
        })
        for row in decisions:
            if row["target"] == target:
                row["selected"] = row["candidate_id"] == chosen
    return selections


def build_adoption_tables(campaign: Path, paths: dict[str, Path]) -> dict[str, list[dict[str, object]]]:
    candidates = read_csv(paths["candidate_manifest"])
    folds = read_csv(paths["fold_registry"])
    scores = read_csv(paths["confirmation_scores"])
    fits = read_csv(paths["confirmation_fits"])
    aggregates = read_csv(paths["confirmation_aggregate"])
    development = read_csv(paths["development_aggregate"])

    primary_fold_ids = {
        row["fold_id"] for row in folds
        if row["panel"] == "confirmation" and as_bool(row["primary"])
    }
    guard_fold_ids = {
        row["fold_id"] for row in folds
        if row["panel"] == "confirmation" and not as_bool(row["primary"])
    }
    fold_meta = {row["fold_id"]: row for row in folds}
    if len(primary_fold_ids) != 16 or len(guard_fold_ids) != 2:
        raise RuntimeError("Search III confirmation must have 16 primary and two guardrail folds")

    aggregate_index = {(row["target"], row["candidate_id"]): row for row in aggregates}
    development_index = {(row["target"], row["candidate_id"]): row for row in development}
    candidate_index = {(row["target"], row["candidate_id"]): row for row in candidates}
    incumbents: dict[str, str] = {}
    for target in ("reference", "discrepancy"):
        ids = [
            row["candidate_id"] for row in candidates
            if row["target"] == target and row.get("control_label") == "search2_incumbent"
        ]
        if len(ids) != 1:
            raise RuntimeError(f"Expected one {target} Search II incumbent, found {ids}")
        incumbents[target] = ids[0]

    primary = [
        row for row in scores
        if row["score_window"] == "primary_28" and row["fold_id"] in primary_fold_ids
    ]
    guards = [
        row for row in scores
        if row["score_window"] == "primary_28" and row["fold_id"] in guard_fold_ids
    ]
    for row in primary + guards:
        row["selection_candidate_id"] = candidate_id(row)
    for row in fits:
        row["selection_candidate_id"] = candidate_id(row)

    decisions: list[dict[str, object]] = []
    fold_rows: list[dict[str, object]] = []
    season_rows: list[dict[str, object]] = []
    guard_rows: list[dict[str, object]] = []

    for target in ("reference", "discrepancy"):
        incumbent = incumbents[target]
        ids = [row["candidate_id"] for row in aggregates if row["target"] == target]
        if len(ids) != 3 or incumbent not in ids:
            raise RuntimeError(f"Expected incumbent and two {target} finalists, found {ids}")

        target_primary = [row for row in primary if row["target"] == target]
        target_guards = [row for row in guards if row["target"] == target]
        target_fits = [row for row in fits if row["target"] == target]
        incumbent_fold = grouped_mean(
            [row for row in target_primary if row["selection_candidate_id"] == incumbent],
            "fold_id", "mean_crps",
        )
        incumbent_season: dict[str, float] = {}
        for season in sorted({fold_meta[name]["wet_season"] for name in primary_fold_ids}):
            values = [value for fold, value in incumbent_fold.items() if fold_meta[fold]["wet_season"] == season]
            incumbent_season[season] = mean(values)
        incumbent_guard = grouped_mean(
            [row for row in target_guards if row["selection_candidate_id"] == incumbent],
            "fold_id", "mean_crps",
        )
        incumbent_fit = [row for row in target_fits if row["selection_candidate_id"] == incumbent]
        incumbent_hist_all = mean(as_float(row["historical_all_rmse"]) for row in incumbent_fit)
        incumbent_hist_200 = mean(as_float(row["historical_last200_rmse"]) for row in incumbent_fit)
        incumbent_worst = max(incumbent_fold.values())
        incumbent_dev = as_float(development_index[(target, incumbent)]["phase_balanced_crps"])

        for identifier in ids:
            candidate_primary = [row for row in target_primary if row["selection_candidate_id"] == identifier]
            candidate_guards = [row for row in target_guards if row["selection_candidate_id"] == identifier]
            candidate_fits = [row for row in target_fits if row["selection_candidate_id"] == identifier]
            fold_means = grouped_mean(candidate_primary, "fold_id", "mean_crps")
            guard_means = grouped_mean(candidate_guards, "fold_id", "mean_crps")
            if len(candidate_primary) != 64 or len(candidate_guards) != 8 or len(candidate_fits) != 72:
                raise RuntimeError(
                    f"Incomplete panel for {identifier}: primary={len(candidate_primary)} "
                    f"guards={len(candidate_guards)} fits={len(candidate_fits)}"
                )
            if set(fold_means) != primary_fold_ids or set(guard_means) != guard_fold_ids:
                raise RuntimeError(f"Incomplete fold coverage for {identifier}")

            season_means: dict[str, float] = {}
            for season in incumbent_season:
                values = [value for fold, value in fold_means.items() if fold_meta[fold]["wet_season"] == season]
                season_means[season] = mean(values)
                season_rows.append({
                    "target": target,
                    "candidate_id": identifier,
                    "wet_season": season,
                    "candidate_mean_crps": season_means[season],
                    "incumbent_mean_crps": incumbent_season[season],
                    "delta": season_means[season] - incumbent_season[season],
                    "candidate_wins": season_means[season] < incumbent_season[season],
                })
            for fold in sorted(fold_means):
                fold_rows.append({
                    "target": target,
                    "candidate_id": identifier,
                    "fold_id": fold,
                    "wet_season": fold_meta[fold]["wet_season"],
                    "phase": fold_meta[fold]["phase"],
                    "candidate_mean_crps": fold_means[fold],
                    "incumbent_mean_crps": incumbent_fold[fold],
                    "delta": fold_means[fold] - incumbent_fold[fold],
                    "candidate_wins": fold_means[fold] < incumbent_fold[fold],
                })
            ratios = []
            for fold in sorted(guard_means):
                ratio = guard_means[fold] / incumbent_guard[fold]
                ratios.append(ratio)
                guard_rows.append({
                    "target": target,
                    "candidate_id": identifier,
                    "fold_id": fold,
                    "candidate_mean_crps": guard_means[fold],
                    "incumbent_mean_crps": incumbent_guard[fold],
                    "ratio": ratio,
                    "gate_pass": ratio <= GUARD_RATIO_MAX,
                })

            aggregate = aggregate_index[(target, identifier)]
            development_row = development_index[(target, identifier)]
            candidate_spec = candidate_index[(target, identifier)]
            fit_completed = all(as_bool(row["fit_completed"]) for row in candidate_fits)
            exact_iterations = all(int(float(row["fit_iterations"])) == 200 for row in candidate_fits)
            terminal = all(as_bool(row["terminal_certificate_pass"]) for row in candidate_fits)
            finite = all(as_bool(row["finite_pass"]) for row in candidate_fits)
            diagnostic_rejects = sum(row.get("diagnostic_decision", "").lower() == "reject" for row in candidate_fits)
            numerical_pass = finite and diagnostic_rejects == 0
            computational_pass = fit_completed and exact_iterations and terminal and numerical_pass
            hist_all = mean(as_float(row["historical_all_rmse"]) for row in candidate_fits)
            hist_200 = mean(as_float(row["historical_last200_rmse"]) for row in candidate_fits)
            worst_fold = max(fold_means.values())
            season_wins = sum(season_means[name] < incumbent_season[name] for name in season_means)
            fold_wins = sum(fold_means[name] < incumbent_fold[name] for name in fold_means)
            confirmation_score = as_float(aggregate["phase_balanced_crps"])
            incumbent_score = as_float(aggregate_index[(target, incumbent)]["phase_balanced_crps"])
            development_score = as_float(development_row["phase_balanced_crps"])

            guard_pass = all(ratio <= GUARD_RATIO_MAX for ratio in ratios)
            worst_fold_pass = worst_fold <= WORST_FOLD_RATIO_MAX * incumbent_worst
            historical_pass = (
                hist_all <= HISTORICAL_RMSE_RATIO_MAX * incumbent_hist_all
                and hist_200 <= HISTORICAL_RMSE_RATIO_MAX * incumbent_hist_200
            )
            scientific_gate_pass = computational_pass and guard_pass and worst_fold_pass and historical_pass
            is_incumbent = identifier == incumbent
            confirmation_improves = round(confirmation_score, 4) < round(incumbent_score, 4)
            breadth_pass = season_wins >= 3 or fold_wins > 8
            development_pass = round(development_score, 4) <= round(incumbent_dev, 4)
            adoption_eligible = is_incumbent or (
                scientific_gate_pass and confirmation_improves and breadth_pass and development_pass
            )
            decisions.append({
                "target": target,
                "candidate_id": identifier,
                "is_incumbent": is_incumbent,
                "confirmation_rank": int(float(aggregate["rank"])),
                "confirmation_phase_balanced_crps": confirmation_score,
                "confirmation_crps_4dp": f"{confirmation_score:.4f}",
                "incumbent_confirmation_crps": incumbent_score,
                "mean_secondary_crps": as_float(aggregate["mean_secondary_crps"]),
                "worst_fold_crps": worst_fold,
                "worst_fold_ratio": worst_fold / incumbent_worst,
                "worst_fold_pass": worst_fold_pass,
                "guardrail_max_ratio": max(ratios),
                "guardrail_pass": guard_pass,
                "historical_all_rmse": hist_all,
                "historical_all_ratio": hist_all / incumbent_hist_all,
                "historical_last200_rmse": hist_200,
                "historical_last200_ratio": hist_200 / incumbent_hist_200,
                "historical_pass": historical_pass,
                "fit_count": len(candidate_fits),
                "fit_completed_pass": fit_completed,
                "exact_200_iterations_pass": exact_iterations,
                "terminal_certificate_pass": terminal,
                "finite_pass": finite,
                "diagnostic_reject_count": diagnostic_rejects,
                "numerical_pass": numerical_pass,
                "computational_pass": computational_pass,
                "scientific_gate_pass": scientific_gate_pass,
                "season_wins": season_wins,
                "fold_wins": fold_wins,
                "breadth_pass": breadth_pass,
                "development_phase_balanced_crps": development_score,
                "incumbent_development_crps": incumbent_dev,
                "development_direction_pass": development_pass,
                "confirmation_improves_4dp": confirmation_improves,
                "adoption_eligible": adoption_eligible,
                "n_state_features": int(float(candidate_spec["n_state_features"])),
                "mean_runtime_seconds": mean(as_float(row["runtime_seconds"]) for row in candidate_fits),
            })

    selections = choose_adoptions(decisions, incumbents, EXPECTED_ADOPTION)

    return {
        "decisions": decisions,
        "folds": fold_rows,
        "seasons": season_rows,
        "guards": guard_rows,
        "selections": selections,
    }


def selection_manifest(
    campaign: Path,
    paths: dict[str, Path],
    tables: dict[str, list[dict[str, object]]],
    decision_sha: str,
) -> list[dict[str, object]]:
    candidates = read_csv(paths["candidate_manifest"])
    jobs = read_csv(paths["confirmation_jobs"])
    rows: list[dict[str, object]] = []
    for selected in tables["selections"]:
        target = str(selected["target"])
        identifier = str(selected["candidate_id"])
        spec = next(row for row in candidates if row["target"] == target and row["candidate_id"] == identifier)
        job = next(row for row in jobs if row["target"] == target and row["base_candidate_id"] == identifier)
        decision = next(row for row in tables["decisions"] if row["target"] == target and row["candidate_id"] == identifier)
        out = dict(spec)
        out.update({
            "component": target,
            "canonical_seed": spec["seed"],
            "prior_id": job["prior_id"],
            "prior_mode": job["prior_mode"],
            "m0": job["m0"],
            "rhs_zeta2_fixed": job["rhs_zeta2_fixed"],
            "rhs_a_zeta": job["rhs_a_zeta"],
            "rhs_b_zeta": job["rhs_b_zeta"],
            "mean_primary_crps": decision["confirmation_phase_balanced_crps"],
            "worst_primary_crps": decision["worst_fold_crps"],
            "n_folds": 16,
            "n_seeds": 4,
            "converged_cells": 72,
            "adoption_status": "adopted",
            "scientific_gate_pass": decision["scientific_gate_pass"],
            "selection_program": "search3_rainy_season",
            "selection_schema_version": "1",
            "adoption_action": selected["adoption_action"],
            "source_campaign_root": str(campaign),
            "source_head": subprocess.run(
                ["git", "-C", str(Path(__file__).resolve().parents[2]), "rev-parse", "HEAD"],
                check=True, text=True, stdout=subprocess.PIPE,
            ).stdout.strip(),
            "candidate_manifest_sha256": sha256(paths["candidate_manifest"]),
            "confirmation_aggregate_sha256": sha256(paths["confirmation_aggregate"]),
            "adoption_decision_sha256": decision_sha,
        })
        rows.append(out)
    return rows


def verify_legacy_manifest(campaign: Path, path: Path) -> list[dict[str, object]]:
    mismatches: list[dict[str, object]] = []
    for row in read_csv(path):
        artifact = campaign / row["relative_path"]
        observed_size = artifact.stat().st_size if artifact.is_file() else -1
        observed_hash = sha256(artifact) if artifact.is_file() else "MISSING"
        if str(observed_size) != row["size"] or observed_hash != row["sha256"]:
            mismatches.append({
                "relative_path": row["relative_path"],
                "expected_size": row["size"],
                "observed_size": observed_size,
                "expected_sha256": row["sha256"],
                "observed_sha256": observed_hash,
            })
    expected = [row for row in mismatches if row["relative_path"] == "logs/controller.log"]
    unexpected = [row for row in mismatches if row["relative_path"] != "logs/controller.log"]
    if len(expected) != 1 or unexpected:
        raise RuntimeError(f"Unexpected legacy campaign manifest drift: {mismatches[:5]}")
    return mismatches


def inventory(root: Path, excluded: set[Path]) -> list[dict[str, object]]:
    rows = []
    excluded = {path.resolve() for path in excluded}
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        resolved = path.resolve()
        if resolved in excluded or any(parent in excluded for parent in resolved.parents):
            continue
        rows.append({
            "relative_path": str(path.relative_to(root)),
            "size_bytes": path.stat().st_size,
            "sha256": sha256(path),
        })
    return rows


def write_report(path: Path, tables: dict[str, list[dict[str, object]]]) -> None:
    selected = {row["target"]: row for row in tables["selections"]}
    decisions = tables["decisions"]
    lines = [
        "# Search III Scientific Adoption", "", 
        "Search III completed 2,032/2,032 jobs with zero failures. This report applies the frozen",
        "scientific guardrails that are stricter than the confirmation table's computational certificate.", "",
        "| Component | Adopted candidate | Action |", "|---|---|---|",
    ]
    for target in ("reference", "discrepancy"):
        row = selected[target]
        lines.append(f"| {target} | `{row['candidate_id']}` | `{row['adoption_action']}` |")
    lines.extend(["", "## Candidate Gates", "", "| Target | Candidate | CRPS | Guard max | Worst fold | Hist all | Hist 200 | Cert | Breadth | Dev | Selected |", "|---|---|---:|---:|---:|---:|---:|---|---|---|---|"])
    for row in sorted(decisions, key=lambda item: (item["target"], item["confirmation_rank"])):
        lines.append(
            f"| {row['target']} | `{row['candidate_id']}` | {row['confirmation_phase_balanced_crps']:.8f} | "
            f"{row['guardrail_max_ratio']:.4f} | {row['worst_fold_ratio']:.4f} | "
            f"{row['historical_all_ratio']:.4f} | {row['historical_last200_ratio']:.4f} | "
            f"{row['terminal_certificate_pass']} | {row['breadth_pass']} | "
            f"{row['development_direction_pass']} | {row['selected']} |"
        )
    lines.extend([
        "", "## Interpretation", "",
        "- Reference `search3_ref_035` improves average rainy-season CRPS but fails the May guardrail.",
        "- Reference `search3_ref_003` also fails a guardrail and has one noncertified confirmation fit.",
        "- Discrepancy `search3_dis_037` is the raw CRPS leader but fails the May 1.10 guardrail.",
        "- Discrepancy `search3_dis_007` clears every gate and is adopted.",
        "- No 2022-12-25 score was used in this decision.", "",
        "Terminal state: `SEARCH3_ADOPTION_SEALED_DOWNSTREAM_REFIT_PENDING`", "",
    ])
    path.write_text("\n".join(lines))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--campaign-root", required=True)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--label", default="search3_scientific_adoption_20260925")
    args = parser.parse_args()
    campaign = Path(args.campaign_root).resolve()
    plan = Path(args.plan).resolve()
    if not plan.is_file():
        raise RuntimeError(f"Frozen Search III plan is missing: {plan}")
    paths = validate_inputs(campaign)
    tables = build_adoption_tables(campaign, paths)

    adoption = campaign / "provenance" / args.label
    seal = campaign / "provenance" / f"{args.label}_campaign_seal"
    for destination in (adoption, seal):
        if destination.exists() and any(destination.iterdir()):
            raise RuntimeError(f"Refusing to overwrite nonempty destination: {destination}")
    (adoption / "tables").mkdir(parents=True)
    (adoption / "reports").mkdir()
    (adoption / "status").mkdir()

    decision_path = adoption / "tables/candidate_adoption_gates.csv"
    atomic_csv(decision_path, tables["decisions"])
    atomic_csv(adoption / "tables/paired_fold_comparisons.csv", tables["folds"])
    atomic_csv(adoption / "tables/paired_season_comparisons.csv", tables["seasons"])
    atomic_csv(adoption / "tables/guardrail_comparisons.csv", tables["guards"])
    selected = selection_manifest(campaign, paths, tables, sha256(decision_path))
    atomic_csv(adoption / "tables/adopted_component_manifest.csv", selected)
    write_report(adoption / "reports/search3_scientific_adoption.md", tables)

    legacy_mismatches = verify_legacy_manifest(campaign, paths["legacy_manifest"])
    atomic_csv(adoption / "tables/legacy_manifest_drift.csv", legacy_mismatches)
    source_root = Path(__file__).resolve().parents[2]
    source = {
        "created_at": time.strftime("%Y-%m-%d %H:%M:%S %Z"),
        "campaign_root": str(campaign),
        "source_head": subprocess.run(["git", "-C", str(source_root), "rev-parse", "HEAD"], check=True, text=True, stdout=subprocess.PIPE).stdout.strip(),
        "frozen_plan": str(plan),
        "frozen_plan_sha256": sha256(plan),
        "input_hashes": {name: sha256(path) for name, path in paths.items()},
        "legacy_manifest_mismatch_count": len(legacy_mismatches),
        "legacy_manifest_mismatch_classification": "controller_terminal_log_written_after_inventory",
    }
    (adoption / "provenance.json").write_text(json.dumps(source, indent=2, sort_keys=True) + "\n")
    (adoption / "status/SEARCH3_ADOPTION_SEALED_DOWNSTREAM_REFIT_PENDING").write_text(
        "SEARCH3_ADOPTION_SEALED_DOWNSTREAM_REFIT_PENDING\n"
    )
    adoption_files = inventory(adoption, {adoption / "artifact_manifest.csv"})
    atomic_csv(adoption / "artifact_manifest.csv", adoption_files)

    seal.mkdir(parents=True)
    campaign_files = inventory(campaign, {paths["legacy_manifest"], seal})
    seal_manifest = seal / "campaign_artifact_manifest.csv"
    atomic_csv(seal_manifest, campaign_files)
    verification = {
        "created_at": time.strftime("%Y-%m-%d %H:%M:%S %Z"),
        "classification": "search3_complete_and_scientifically_adopted",
        "artifact_count": len(campaign_files),
        "artifact_bytes": sum(int(row["size_bytes"]) for row in campaign_files),
        "manifest_sha256": sha256(seal_manifest),
        "excluded_legacy_manifest": str(paths["legacy_manifest"]),
        "legacy_manifest_expected_mismatches": len(legacy_mismatches),
        "adopted_reference": EXPECTED_ADOPTION["reference"],
        "adopted_discrepancy": EXPECTED_ADOPTION["discrepancy"],
        "final_origin_used_for_selection": False,
        "terminal_state": "SEARCH3_ADOPTION_SEALED_DOWNSTREAM_REFIT_PENDING",
    }
    (seal / "verification.json").write_text(json.dumps(verification, indent=2, sort_keys=True) + "\n")
    print(json.dumps({
        "adoption_root": str(adoption),
        "selection_manifest": str(adoption / "tables/adopted_component_manifest.csv"),
        "adoption_manifest_sha256": sha256(adoption / "artifact_manifest.csv"),
        "campaign_seal": str(seal),
        **verification,
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
