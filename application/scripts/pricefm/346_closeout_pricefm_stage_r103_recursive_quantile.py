#!/usr/bin/env python3
"""Close R103 and freeze one complete AL/exAL family per region."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import shutil
import tempfile
from typing import Any

import pandas as pd

from pricefm_common import sha256_file, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PREP = DATA / "launch_prep/pricefm_stage_r103_recursive_quantile_20260916"
OUTPUT = DATA / "authoritative/pricefm_stage_r103_recursive_quantile_closeout_20260916"


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
        raise RuntimeError("R103 prep is invalid")
    for role, name in summary["output_files"].items():
        if sha256_file(prep / name) != summary["output_sha256"][role]:
            raise RuntimeError("R103 prep hash mismatch: {}".format(role))
    for row in pd.read_csv(prep / "source_manifest.csv").itertuples(index=False):
        path = Path(row.path)
        if not path.is_file() or sha256_file(path) != str(row.sha256):
            raise RuntimeError("R103 source changed: {}".format(path))
    return (
        summary,
        pd.read_csv(prep / "pricefm_stage_r103_case_manifest.csv"),
        pd.read_csv(prep / "pricefm_stage_r103_atom_manifest.csv"),
    )


def select_families(metrics: pd.DataFrame) -> pd.DataFrame:
    decisions = []
    for region, group in metrics.groupby("region", sort=True):
        if len(group) != 6 or set(group.fold.astype(int)) != {1, 2, 3} or set(group.family) != {"al", "exal"}:
            raise RuntimeError("R103 family surface is incomplete: {}".format(region))
        al = group[group.family.eq("al")]
        exal = group[group.family.eq("exal")]
        if not al.numerically_eligible.astype(bool).all():
            raise RuntimeError("R103 AL baseline is numerically ineligible: {}".format(region))
        fold1 = group[group.fold.astype(int).eq(1)].sort_values(["validation_AQL_original", "family"])
        fold1_winner = str(fold1.iloc[0].family)
        fallback = fold1_winner == "exal" and not exal.numerically_eligible.astype(bool).all()
        selected = "al" if fallback else fold1_winner
        decisions.append({
            "region": region,
            "selected_family": selected,
            "fold1_validation_winner_before_numerical_fallback": fold1_winner,
            "numerical_fallback_to_AL": fallback,
            "fold1_AL_AQL": float(al[al.fold.astype(int).eq(1)].iloc[0].validation_AQL_original),
            "fold1_exAL_AQL": float(exal[exal.fold.astype(int).eq(1)].iloc[0].validation_AQL_original),
            "selection_split": "fold1_validation_only",
            "per_fold_or_quantile_family_mixing": False,
            "test_opened": False,
        })
    result = pd.DataFrame(decisions)
    if len(result) != 38:
        raise RuntimeError("R103 must freeze 38 region family decisions")
    return result


def run(args: argparse.Namespace) -> dict[str, Any]:
    prep = args.prep_dir.resolve()
    output = args.output_dir.resolve()
    _, cases, atoms = verify_prep(prep)
    if len(cases) != 114 or len(atoms) != 1596:
        raise RuntimeError("R103 prep cardinality changed")
    metric_frames = []
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
        ):
            raise RuntimeError("invalid R103 case terminal: {}".format(row.case_id))
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
                raise RuntimeError("changed R103 case artifact: {}".format(path))
            paths[record["role"]] = path
            evidence.append({
                "role": record["role"],
                "case_id": row.case_id,
                "path": str(path.resolve()),
                "bytes": path.stat().st_size,
                "sha256": record["sha256"],
            })
        metrics = pd.read_csv(paths["family_validation_metrics"])
        if len(metrics) != 2 or metrics.test_opened.astype(bool).any():
            raise RuntimeError("R103 case metrics are invalid")
        metric_frames.append(metrics)
    metrics = pd.concat(metric_frames, ignore_index=True)
    decisions = select_families(metrics)
    selected_atoms = atoms.merge(decisions[["region", "selected_family"]], on="region", how="inner")
    selected_atoms = selected_atoms[selected_atoms.family.eq(selected_atoms.selected_family)].copy()
    if (
        len(selected_atoms) != 798
        or selected_atoms[["region", "fold", "tau"]].duplicated().any()
        or selected_atoms.region.nunique() != 38
    ):
        raise RuntimeError("R103 selected atom surface is incomplete")
    atom_records = []
    for row in selected_atoms.itertuples(index=False):
        terminal_path = Path(row.output_dir) / "terminal.json"
        terminal = read_json(terminal_path)
        if (
            terminal.get("status") != "completed_recursive_quantile_atom"
            or terminal.get("atom_id") != row.atom_id
            or terminal.get("posterior_target_sha256") != row.posterior_target_sha256
            or terminal.get("test_opened") is not False
        ):
            raise RuntimeError("R103 selected atom is invalid")
        for record in terminal["artifacts"]:
            path = Path(record["path"])
            if not path.is_file() or sha256_file(path) != record["sha256"]:
                raise RuntimeError("R103 selected atom artifact changed: {}".format(path))
        atom_records.append({
            **row._asdict(),
            "terminal_path": str(terminal_path.resolve()),
            "terminal_sha256": sha256_file(terminal_path),
            "numerical_gate_passed": bool(terminal["numerical_gate_passed"]),
            "formal_converged": bool(terminal["formal_converged"]),
        })
    selected_atoms = pd.DataFrame(atom_records).sort_values(["region", "fold", "tau"])
    if not selected_atoms.numerical_gate_passed.all():
        raise RuntimeError("R103 selected family contains an ineligible atom")
    selected_metrics = metrics.merge(decisions[["region", "selected_family"]], on="region")
    selected_metrics = selected_metrics[selected_metrics.family.eq(selected_metrics.selected_family)].copy()
    weight = selected_metrics.n_loss_atoms.astype(float)
    global_aql = float((selected_metrics.validation_AQL_original * weight).sum() / weight.sum())
    gates = pd.DataFrame([
        ("cases_complete", len(terminals) == 114, len(terminals)),
        ("atoms_complete", len(atoms) == 1596, len(atoms)),
        ("region_family_decisions", len(decisions) == 38, len(decisions)),
        ("selected_atoms_complete", len(selected_atoms) == 798, len(selected_atoms)),
        ("selected_atoms_numerically_eligible", selected_atoms.numerical_gate_passed.all(), selected_atoms.numerical_gate_passed.sum()),
        ("one_family_per_region", decisions.region.nunique() == 38, decisions.selected_family.value_counts().to_dict()),
        ("selection_is_fold1_validation_only", decisions.selection_split.eq("fold1_validation_only").all(), "fold1_validation_only"),
        ("test_never_opened", all(value["test_opened"] is False for value in terminals), False),
        ("joint_mcmc_registry_article_blocked", True, "joint;mcmc;registry;article;test"),
    ], columns=["gate", "passed", "observed"])
    if not gates.passed.all():
        raise RuntimeError("R103 G4 closeout gate failed")
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        tables = {
            "family_metrics": metrics.sort_values(["region", "fold", "family"]),
            "family_decisions": decisions,
            "selected_atoms": selected_atoms,
            "selected_metrics": selected_metrics.sort_values(["region", "fold"]),
            "gates": gates,
            "source_manifest": pd.DataFrame(evidence).sort_values(["role", "case_id", "path"]),
        }
        filenames = {
            "family_metrics": "pricefm_stage_r103_family_validation_metrics.csv",
            "family_decisions": "pricefm_stage_r103_region_family_decisions.csv",
            "selected_atoms": "pricefm_stage_r103_selected_atom_manifest.csv",
            "selected_metrics": "pricefm_stage_r103_selected_validation_metrics.csv",
            "gates": "pricefm_stage_r103_g4_gates.csv",
            "source_manifest": "source_manifest.csv",
        }
        for role, table in tables.items():
            table.to_csv(temporary / filenames[role], index=False, quoting=csv.QUOTE_MINIMAL)
        decision = {
            "stage": "R103",
            "status": "completed_recursive_independent_family_frozen",
            "regions": 38,
            "cases": 114,
            "selected_atoms": 798,
            "selected_AL_regions": int(decisions.selected_family.eq("al").sum()),
            "selected_exAL_regions": int(decisions.selected_family.eq("exal").sum()),
            "aggregate_validation_AQL_original": global_aql,
            "selection_rule": "one_whole_family_per_region_from_fold1_validation_with_AL_numerical_fallback",
            "test_opened": False,
        }
        write_json(temporary / "pricefm_stage_r103_frozen_decision.json", decision)
        report = """# PriceFM Stage-R103 recursive independent-quantile closeout

R103 completed all 114 causal region-fold cases and 1,596 independent VB
AL/exAL atoms. One complete seven-quantile family was selected per region from
Fold-1 validation, then frozen across all three folds. The selected surface has
aggregate validation AQL **{aql:.6f}**. Test, joint models, MCMC, registry, and
article mutation remain blocked.
""".format(aql=global_aql)
        (temporary / "pricefm_stage_r103_recursive_quantile_closeout.md").write_text(report)
        outputs = {
            **filenames,
            "decision": "pricefm_stage_r103_frozen_decision.json",
            "report": "pricefm_stage_r103_recursive_quantile_closeout.md",
        }
        summary = {
            **decision,
            "output_files": outputs,
            "output_sha256": {role: sha256_file(temporary / name) for role, name in outputs.items()},
            "next_gate": "R104_path_count_stability_before_any_outer_test",
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
