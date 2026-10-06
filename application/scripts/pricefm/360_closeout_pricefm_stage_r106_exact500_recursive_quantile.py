#!/usr/bin/env python3
"""Close R106 and freeze one complete AL/exAL family per region."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import shutil
import tempfile
from typing import Any

import numpy as np
import pandas as pd

from pricefm_common import sha256_file, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PREP = DATA / "launch_prep/pricefm_stage_r106_exact500_recursive_quantile_20260918"
OUTPUT = DATA / "authoritative/pricefm_stage_r106_exact500_recursive_quantile_closeout_20260918"
R104_METRICS = (
    DATA / "authoritative/pricefm_stage_r104_forecast_operator_diagnosis_20260918"
    / "pricefm_stage_r104_operator_metrics.csv"
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--prep-dir", type=Path, default=PREP)
    value.add_argument("--output-dir", type=Path, default=OUTPUT)
    value.add_argument("--force", action="store_true")
    return value


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def verify_prep(prep: Path) -> tuple[dict[str, Any], pd.DataFrame, pd.DataFrame]:
    summary = read_json(prep / "summary.json")
    if summary.get("status") != "prepared_validation_only_campaign" or summary.get("test_opened") is not False:
        raise RuntimeError("R106 prep is invalid")
    for role, name in summary["output_files"].items():
        if sha256_file(prep / name) != summary["output_sha256"][role]:
            raise RuntimeError("R106 prep hash mismatch: {}".format(role))
    for row in pd.read_csv(prep / "source_manifest.csv").itertuples(index=False):
        path = Path(row.path)
        if not path.is_file() or sha256_file(path) != str(row.sha256):
            raise RuntimeError("R106 source changed: {}".format(path))
    return (
        summary,
        pd.read_csv(prep / "pricefm_stage_r106_case_manifest.csv"),
        pd.read_csv(prep / "pricefm_stage_r106_atom_manifest.csv"),
    )


def select_combinations(metrics: pd.DataFrame) -> pd.DataFrame:
    decisions = []
    for region, group in metrics.groupby("region", sort=True):
        combinations = group[["family", "policy"]].drop_duplicates()
        expected_rows = len(combinations) * 3
        if (
            len(group) != expected_rows
            or set(group.fold.astype(int)) != {1, 2, 3}
            or group[["fold", "family", "policy"]].duplicated().any()
            or not group.all_atoms_exact_500.astype(bool).all()
        ):
            raise RuntimeError("R106 family-policy surface is incomplete: {}".format(region))
        eligible = []
        for candidate in combinations.itertuples(index=False):
            subset = group[
                group.family.eq(candidate.family) & group.policy.eq(candidate.policy)
            ]
            if subset.numerically_eligible.astype(bool).all():
                eligible.append((str(candidate.family), str(candidate.policy)))
        fold1 = group[group.fold.astype(int).eq(1)].copy()
        fold1["eligible_all_folds"] = [
            (str(row.family), str(row.policy)) in eligible
            for row in fold1.itertuples(index=False)
        ]
        ranked = fold1[fold1.eligible_all_folds].sort_values(
            ["validation_AQL_original", "family", "policy"]
        )
        selected_family = None if ranked.empty else str(ranked.iloc[0].family)
        selected_policy = None if ranked.empty else str(ranked.iloc[0].policy)
        decisions.append({
            "region": region,
            "selected_family": selected_family,
            "selected_policy": selected_policy,
            "decision_status": "selected" if selected_family is not None else "no_numerically_eligible_combination",
            "candidate_combinations": int(len(combinations)),
            "eligible_combinations": int(len(eligible)),
            "fold1_selected_AQL": None if ranked.empty else float(ranked.iloc[0].validation_AQL_original),
            "selection_split": "fold1_validation_only",
            "per_fold_or_quantile_mixing": False,
            "test_opened": False,
        })
    result = pd.DataFrame(decisions)
    return result


def summarize_trace(trace: pd.DataFrame) -> dict[str, Any]:
    required = {"iter", "elbo", "delta_elbo"}
    if not required.issubset(trace.columns):
        raise RuntimeError("R106 VB trace lacks raw ELBO columns")
    iteration = trace["iter"].to_numpy(dtype=int)
    elbo = trace["elbo"].to_numpy(dtype=float)
    if len(elbo) != 500 or not np.isfinite(elbo).all():
        raise RuntimeError("R106 raw ELBO trace violates the exact-500 contract")
    def tail_change(window: int) -> float:
        start = max(0, len(elbo) - window - 1)
        return float(elbo[-1] - elbo[start])
    differences = np.diff(elbo)
    return {
        "trace_rows": int(len(elbo)),
        "initial_elbo": float(elbo[0]),
        "final_elbo": float(elbo[-1]),
        "last_10_change": tail_change(10),
        "last_25_change": tail_change(25),
        "last_50_change": tail_change(50),
        "final_delta_elbo": float(trace["delta_elbo"].iloc[-1]),
        "maximum_elbo": float(np.max(elbo)),
        "final_minus_maximum": float(elbo[-1] - np.max(elbo)),
        "decrease_count": int(np.sum(differences < -1e-10)),
    }


def compare_early_stop(metrics: pd.DataFrame, source: Path = R104_METRICS) -> pd.DataFrame:
    columns = [
        "region", "fold", "family", "policy", "validation_AQL_original",
        "early_stop_AQL", "exact500_minus_early_stop_AQL",
    ]
    if not source.is_file():
        return pd.DataFrame(columns=columns)
    early = pd.read_csv(source)
    early = early[early.policy.astype(str).str.startswith("quantile_curve_self")].copy()
    early = early.rename(columns={"AQL": "early_stop_AQL"})
    current = metrics[[
        "region", "fold", "family", "policy", "validation_AQL_original"
    ]].copy()
    result = current.merge(
        early[["region", "fold", "family", "policy", "early_stop_AQL"]],
        on=["region", "fold", "family", "policy"], how="inner",
    )
    result["exact500_minus_early_stop_AQL"] = (
        result.validation_AQL_original - result.early_stop_AQL
    )
    return result.sort_values(["region", "fold", "family", "policy"])


def run(args: argparse.Namespace) -> dict[str, Any]:
    prep = args.prep_dir.resolve()
    output = args.output_dir.resolve()
    _, cases, atoms = verify_prep(prep)
    if len(cases) != 114 or len(atoms) != 1596:
        raise RuntimeError("R106 prep cardinality changed")
    metric_frames = []
    horizon_frames = []
    evidence = []
    terminals = []
    for row in cases.sort_values(["region", "fold"]).itertuples(index=False):
        case_output = Path(row.output_dir)
        terminal_path = case_output / "terminal.json"
        terminal = read_json(terminal_path)
        if (
            terminal.get("status") != "completed_recursive_quantile_case"
            or terminal.get("case_id") != str(row.case_id)
            or terminal.get("test_opened") is not False
            or int(terminal.get("atoms_complete", -1)) != 14
            or int(terminal.get("posterior_paths", -1)) != 500
            or terminal.get("all_atoms_exact_500") is not True
        ):
            raise RuntimeError("invalid R106 case terminal: {}".format(row.case_id))
        terminals.append(terminal)
        evidence.append({
            "role": "case_terminal",
            "case_id": row.case_id,
            "path": str(terminal_path.resolve()),
            "bytes": terminal_path.stat().st_size,
            "sha256": sha256_file(terminal_path),
        })
        paths = {}
        for record in terminal["artifacts"]:
            path = Path(record["path"])
            if not path.is_file() or sha256_file(path) != record["sha256"]:
                raise RuntimeError("changed R106 case artifact: {}".format(path))
            paths[record["role"]] = path
            evidence.append({
                "role": record["role"],
                "case_id": row.case_id,
                "path": str(path.resolve()),
                "bytes": path.stat().st_size,
                "sha256": record["sha256"],
            })
        metrics = pd.read_csv(paths["family_validation_metrics"])
        if (
            len(metrics) != int(terminal["family_policy_rows"])
            or metrics.test_opened.astype(bool).any()
            or not metrics.all_atoms_exact_500.astype(bool).all()
        ):
            raise RuntimeError("R106 case metrics are invalid")
        metric_frames.append(metrics)
        horizon_frames.append(pd.read_csv(paths["family_policy_horizon_metrics"]))
    metrics = pd.concat(metric_frames, ignore_index=True)
    horizons = pd.concat(horizon_frames, ignore_index=True)
    early_stop_comparison = compare_early_stop(metrics)
    if R104_METRICS.is_file():
        evidence.append({
            "role": "R104_early_stop_operator_metrics",
            "case_id": "comparison",
            "path": str(R104_METRICS.resolve()),
            "bytes": R104_METRICS.stat().st_size,
            "sha256": sha256_file(R104_METRICS),
        })
    decisions = select_combinations(metrics)
    if len(decisions) != 38:
        raise RuntimeError("R106 must record 38 region family-policy decisions")
    selected_decisions = decisions[decisions.decision_status.eq("selected")].copy()
    selected_atoms = atoms.merge(selected_decisions[["region", "selected_family"]], on="region", how="inner")
    selected_atoms = selected_atoms[selected_atoms.family.eq(selected_atoms.selected_family)].copy()
    if (
        len(selected_atoms) != 21 * len(selected_decisions)
        or selected_atoms[["region", "fold", "tau"]].duplicated().any()
        or selected_atoms.region.nunique() != len(selected_decisions)
    ):
        raise RuntimeError("R106 selected atom surface is incomplete")
    atom_records = []
    for row in atoms.itertuples(index=False):
        terminal_path = Path(row.output_dir) / "terminal.json"
        terminal = read_json(terminal_path)
        if (
            terminal.get("status") != "completed_recursive_quantile_atom"
            or terminal.get("atom_id") != row.atom_id
            or terminal.get("posterior_target_sha256") != row.posterior_target_sha256
            or terminal.get("test_opened") is not False
        ):
            raise RuntimeError("R106 selected atom is invalid")
        for record in terminal["artifacts"]:
            path = Path(record["path"])
            if not path.is_file() or sha256_file(path) != record["sha256"]:
                raise RuntimeError("R106 selected atom artifact changed: {}".format(path))
        atom_records.append({
            **row._asdict(),
            "terminal_path": str(terminal_path.resolve()),
            "terminal_sha256": sha256_file(terminal_path),
            "numerical_gate_passed": bool(terminal["numerical_gate_passed"]),
            "formal_converged": bool(terminal["formal_converged"]),
            "iterations": int(terminal["iterations"]),
            **summarize_trace(pd.read_csv(Path(row.output_dir) / "vb_trace.csv")),
        })
    atom_status = pd.DataFrame(atom_records).sort_values(["region", "fold", "family", "tau"])
    if len(atom_status) != 1596 or not atom_status.iterations.eq(500).all():
        raise RuntimeError("R106 atom status violates the exact-500 contract")
    selected_atoms = atom_status.merge(
        selected_decisions[["region", "selected_family"]], on="region", how="inner"
    )
    selected_atoms = selected_atoms[selected_atoms.family.eq(selected_atoms.selected_family)].copy()
    selected_metrics = metrics.merge(
        selected_decisions[["region", "selected_family", "selected_policy"]],
        on="region", how="inner",
    )
    selected_metrics = selected_metrics[
        selected_metrics.family.eq(selected_metrics.selected_family)
        & selected_metrics.policy.eq(selected_metrics.selected_policy)
    ].copy()
    weight = selected_metrics.n_loss_atoms.astype(float)
    global_aql = (
        float((selected_metrics.validation_AQL_original * weight).sum() / weight.sum())
        if len(selected_metrics) else None
    )
    gates = pd.DataFrame([
        ("cases_complete", len(terminals) == 114, len(terminals)),
        ("atoms_complete", len(atom_status) == 1596, len(atom_status)),
        ("all_atoms_exact_500", atom_status.iterations.eq(500).all(), int(atom_status.iterations.eq(500).sum())),
        ("region_decisions_recorded", len(decisions) == 38, len(decisions)),
        ("selected_atoms_match_selected_regions", len(selected_atoms) == 21 * len(selected_decisions), len(selected_atoms)),
        ("selected_atoms_numerically_eligible", selected_atoms.numerical_gate_passed.all() if len(selected_atoms) else True, int(selected_atoms.numerical_gate_passed.sum()) if len(selected_atoms) else 0),
        ("one_combination_per_selected_region", not selected_metrics[["region", "fold"]].duplicated().any(), len(selected_decisions)),
        ("selection_is_fold1_validation_only", decisions.selection_split.eq("fold1_validation_only").all(), "fold1_validation_only"),
        ("test_never_opened", all(value["test_opened"] is False for value in terminals), False),
        ("joint_mcmc_registry_article_blocked", True, "joint;mcmc;registry;article;test"),
    ], columns=["gate", "passed", "observed"])
    if not gates.passed.all():
        raise RuntimeError("R106 G4 closeout gate failed")
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        tables = {
            "family_policy_metrics": metrics.sort_values(["region", "fold", "family", "policy"]),
            "family_policy_horizon_metrics": horizons.sort_values(["region", "fold", "family", "policy", "horizon"]),
            "region_decisions": decisions,
            "atom_status": atom_status,
            "selected_atoms": selected_atoms,
            "selected_metrics": selected_metrics.sort_values(["region", "fold"]),
            "early_stop_comparison": early_stop_comparison,
            "gates": gates,
            "source_manifest": pd.DataFrame(evidence).sort_values(["role", "case_id", "path"]),
        }
        filenames = {
            "family_policy_metrics": "pricefm_stage_r106_family_policy_validation_metrics.csv",
            "family_policy_horizon_metrics": "pricefm_stage_r106_family_policy_horizon_metrics.csv",
            "region_decisions": "pricefm_stage_r106_region_family_policy_decisions.csv",
            "atom_status": "pricefm_stage_r106_atom_status.csv",
            "selected_atoms": "pricefm_stage_r106_selected_atom_manifest.csv",
            "selected_metrics": "pricefm_stage_r106_selected_validation_metrics.csv",
            "early_stop_comparison": "pricefm_stage_r106_exact500_vs_early_stop_overlap.csv",
            "gates": "pricefm_stage_r106_g4_gates.csv",
            "source_manifest": "source_manifest.csv",
        }
        for role, table in tables.items():
            table.to_csv(temporary / filenames[role], index=False, quoting=csv.QUOTE_MINIMAL)
        decision = {
            "stage": "R106",
            "status": "completed_exact500_recursive_closeout",
            "regions": 38,
            "cases": 114,
            "atoms": 1596,
            "atoms_exact_500": int(atom_status.iterations.eq(500).sum()),
            "atoms_formally_converged": int(atom_status.formal_converged.sum()),
            "atoms_numerically_eligible": int(atom_status.numerical_gate_passed.sum()),
            "selected_regions": int(len(selected_decisions)),
            "unresolved_regions": int(38 - len(selected_decisions)),
            "selected_atoms": int(len(selected_atoms)),
            "selected_AL_regions": int(selected_decisions.selected_family.eq("al").sum()),
            "selected_exAL_regions": int(selected_decisions.selected_family.eq("exal").sum()),
            "aggregate_validation_AQL_original": global_aql,
            "early_stop_overlap_rows": int(len(early_stop_comparison)),
            "exact500_better_overlap_rows": int((early_stop_comparison.exact500_minus_early_stop_AQL < 0).sum()),
            "selection_rule": "one_complete_family_policy_per_region_from_fold1_validation_frozen_across_folds",
            "test_opened": False,
        }
        write_json(temporary / "pricefm_stage_r106_frozen_decision.json", decision)
        report = """# PriceFM Stage-R106 recursive independent-quantile closeout

R106 completed all 114 causal region-fold cases and 1,596 independent VB
AL/exAL atoms at exactly 500 iterations. A complete family/operator combination
was selected for **{selected}/38** regions from Fold-1 validation and frozen
across folds. The selected surface has aggregate validation AQL **{aql}**.
Unresolved numerical combinations remain evidence, not automatic retries. Test,
joint models, MCMC, registry, and article mutation remain blocked.
""".format(selected=len(selected_decisions), aql="NA" if global_aql is None else "{:.6f}".format(global_aql))
        (temporary / "pricefm_stage_r106_recursive_quantile_closeout.md").write_text(report)
        outputs = {
            **filenames,
            "decision": "pricefm_stage_r106_frozen_decision.json",
            "report": "pricefm_stage_r106_recursive_quantile_closeout.md",
        }
        summary = {
            **decision,
            "output_files": outputs,
            "output_sha256": {role: sha256_file(temporary / name) for role, name in outputs.items()},
            "next_gate": "manual_R106_exact500_effect_and_ELBO_review_before_any_test",
            "registry_mutated": False,
            "article_mutated": False,
            "joint_model_fitted": False,
            "mcmc_fitted": False,
        }
        write_json(temporary / "summary.json", summary)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> int:
    run(parser().parse_args())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
