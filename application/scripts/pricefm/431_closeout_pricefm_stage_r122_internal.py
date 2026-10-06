#!/usr/bin/env python3
"""Freeze a separate audit of completed R122 internal results without refitting."""

from __future__ import annotations

import argparse
import fcntl
import json
from pathlib import Path
import shutil
from typing import Any

import numpy as np
import pandas as pd

from pricefm_common import now_utc, sha256_file, write_json


SCRIPTS = Path(__file__).resolve().parent
DEFAULT_PROTOCOL = SCRIPTS.parents[1] / "config/pricefm_stage_r122_internal_closeout_protocol_20261003.json"
DEFAULT_DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
QUANTILES = (.10, .25, .45, .50, .55, .75, .90)
FORBIDDEN = ("test_opened", "article_mutated", "registry_mutated", "joint_model_fitted", "mcmc_fitted", "exal_fitted")


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def read_csv(path: Path) -> pd.DataFrame:
    return pd.read_csv(path, float_precision="round_trip")


def require_closed(value: dict[str, Any], *, terminal: bool = False) -> None:
    require(value.get("test_opened") is False, "test boundary not explicitly closed")
    for key in FORBIDDEN[1:]:
        if terminal or key in value:
            require(value.get(key) is False, f"forbidden mutation or family: {key}")


def validate_output_root(output: Path, *inputs: Path) -> None:
    for source in inputs:
        require(not output.is_relative_to(source) and not source.is_relative_to(output),
                "diagnostic output must be separate from its frozen inputs")


def contract_hash(path: Path, expected: str) -> None:
    require(path.is_file() and sha256_file(path) == expected, f"frozen hash mismatch: {path}")


def trace_gate(trace: pd.DataFrame, beta: np.ndarray, sigma: float) -> dict[str, Any]:
    required = {"elbo", "delta_state", "delta_sigma", "delta_elbo"}
    require(required.issubset(trace.columns), "VB trace is missing numerical gate columns")
    require(len(trace) >= 35 and np.isfinite(trace.elbo.to_numpy()).all(), "invalid VB ELBO trace")
    tail = trace.tail(25)
    require(np.isfinite(tail[list(required)].to_numpy()).all(), "non-finite VB tail")
    require(np.isfinite(beta).all() and np.isfinite(sigma) and 0 < sigma < 100,
            "invalid quantile posterior scale or coefficients")
    scale = max(1., float(np.max(np.abs(beta))))
    values = {
        "absolute_state_tail_max": float(tail.delta_state.abs().max()),
        "relative_state_tail_max": float(tail.delta_state.abs().max() / scale),
        "relative_sigma_tail_max": float(tail.delta_sigma.abs().max() / sigma),
        "relative_elbo_tail_max": float(tail.delta_elbo.abs().max() / max(1., tail.elbo.abs().max())),
        "elbo_tail_range": float(tail.elbo.max() - tail.elbo.min()),
        "elbo_tail_relative_range": float((tail.elbo.max() - tail.elbo.min()) / max(1., tail.elbo.abs().max())),
    }
    values["external_gate_passed"] = bool(
        values["absolute_state_tail_max"] <= .01 and values["relative_state_tail_max"] <= .001
        and values["relative_sigma_tail_max"] <= .001 and values["relative_elbo_tail_max"] <= 1e-5
    )
    return values


def reconstruct_ranking(cells: pd.DataFrame) -> pd.DataFrame:
    require(len(cells) == 9 and not cells[["candidate_id", "split"]].duplicated().any(),
            "nine unique complete AL ladders are required")
    for _, rows in cells.groupby("candidate_id"):
        require(set(rows.split.astype(int)) == {1, 2, 3} and rows.eligible.eq(True).all(),
                "incomplete internal AL family")
    ranking = cells.groupby(["candidate_id", "tau0"], as_index=False).agg(
        mean_AQL=("AQL", "mean"), mean_late_AQL=("late_AQL", "mean"),
        worst_AQL=("AQL", "max"), mean_coverage=("interval_80_coverage", "mean"),
        mean_width=("interval_80_width", "mean"), mean_crossing=("crossing_rate", "mean"),
    ).sort_values(["mean_AQL", "mean_late_AQL", "worst_AQL", "mean_crossing", "candidate_id"], kind="mergesort")
    require(len(ranking) == 3, "three distinct complete AL families are required")
    return ranking.reset_index(drop=True)


def audit_campaign(campaign: Path, prep: Path, protocol: dict[str, Any]) -> dict[str, Any]:
    require(campaign.name == protocol["campaign_tag"], "wrong campaign tag")
    require(all(value is False for key, value in protocol.items() if key.endswith("_authorized")),
            "closeout protocol must keep all fitting and publication access closed")
    contract_hash(campaign / "terminal.json", protocol["campaign_terminal_sha256"])
    contract_hash(campaign / "frozen_internal_choice.json", protocol["frozen_choice_sha256"])
    contract_hash(prep / "summary.json", protocol["preparation_sha256"])
    terminal = read_json(campaign / "terminal.json"); control = read_json(prep / "launch_control.json")
    require_closed(terminal, terminal=True)
    require(terminal["status"] == "R122_INTERNAL_SPECIFICATION_FROZEN_TEST_BLOCKED", "campaign is not complete")
    require(control["code_head"] == protocol["executed_head"], "executed source revision changed")
    require(control["official_test_scoring_authorized"] is False, "official test authorization changed")
    evaluation = read_json(prep / "evaluation_contract.json")
    require(evaluation["selection_protocol"]["test_selection_access"] is False,
            "evaluation contract allows test selection")
    lock_path = campaign / "controller.lock"
    if lock_path.exists():
        with lock_path.open("r") as handle:
            try:
                fcntl.flock(handle, fcntl.LOCK_SH | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise RuntimeError("an active controller still owns the campaign") from error
    ledger: dict[str, dict[str, Any]] = {}

    def record(path: Path) -> None:
        require(path.is_file(), f"missing frozen evidence: {path}")
        ledger[str(path.resolve())] = {"path": str(path.resolve()), "bytes": path.stat().st_size,
                                     "sha256": sha256_file(path)}

    for name in ("terminal.json", "frozen_internal_choice.json", "al_internal/closeout/ranking.csv",
                 "al_internal/closeout/cell_metrics.csv", "rhs/manifest.csv"):
        record(campaign / name)
    for name in ("summary.json", "launch_control.json", "evaluation_contract.json", "target_contract.json",
                 "source_manifest.csv", "candidate_manifest.csv", "execution_manifest.csv"):
        record(prep / name)
    for row in read_csv(prep / "source_manifest.csv").itertuples(index=False):
        path = Path(row.path); contract_hash(path, str(row.sha256)); record(path)
    inputs = prep / "reused_input_inventory.csv"
    summary = read_json(prep / "summary.json")
    contract_hash(inputs, summary["continuation"]["input_inventory_sha256"])
    record(inputs)
    for row in read_csv(inputs).itertuples(index=False):
        path = (campaign / row.path).resolve()
        require(path.is_relative_to(campaign / "processed/windows/fold_1") and path.name.startswith("train_"),
                "processed evidence is outside Fold-1 training")
        contract_hash(path, str(row.sha256)); record(path)
    # Terminal identities are sufficient here; the heavy Ridge reuse inventory
    # remains frozen in the preparation instead of being duplicated or rewritten.
    ridge_counts = {}
    for name, manifest in (("broad", prep / "execution_manifest.csv"), ("third_seed", campaign / "seed3/manifest.csv")):
        frame = read_csv(manifest); require(not frame.fit_id.duplicated().any(), "duplicate Ridge fit identities")
        for row in frame.itertuples(index=False):
            path = campaign / f"ridge/fits/{row.fit_id}/terminal.json"; value = read_json(path)
            require_closed(value)
            require(value["status"] == "completed_r122_ridge_cell" and value["fit_sha256"] == row.fit_sha256,
                    f"invalid Ridge terminal: {row.fit_id}")
            record(path)
        ridge_counts[name] = len(frame)
    expected = protocol["expected_counts"]
    require(ridge_counts == {key: expected[key] for key in ("broad", "third_seed")}, "unexpected Ridge campaign counts")
    rhs = read_csv(campaign / "rhs/manifest.csv")
    require(len(rhs) == expected["normal_rhs"] and not rhs.fit_id.duplicated().any(), "incomplete Normal RHS manifest")
    for row in rhs.itertuples(index=False):
        output = Path(row.output_dir); value = read_json(output / "terminal.json"); require_closed(value)
        require(value["status"] == "completed_recursive_normal_fit" and value["converged"] is True,
                f"invalid RHS fit: {row.fit_id}")
        require(read_json(output / "validation_score.json")["test_opened"] is False, "invalid RHS score")
        for name in ("terminal.json", "validation_score.json", "beta_mean.bin", "beta_cov.bin"):
            record(output / name)
        record(Path(row.contract_path))
    atom_rows, cell_rows = [], []
    shortlist = read_csv(campaign / "rhs/closeout/al_shortlist.csv")
    require(len(shortlist) == 3 and shortlist.candidate_id.nunique() == 3, "invalid finalist shortlist")
    for candidate in shortlist.candidate_id.astype(str):
        for split in (1, 2, 3):
            root = campaign / f"al_internal/{candidate}/split={split}"
            metrics = read_json(root / "metrics.json"); require_closed(metrics)
            require(metrics["eligible"] is True and metrics["score_scope"] == protocol["selection_scope"],
                    "AL metrics have incorrect eligibility or scope")
            accepted = metrics["accepted_quantiles"]
            require(len(accepted) == 7 and {float(x["tau"]) for x in accepted} == set(QUANTILES)
                    and all(x["accepted"] for x in accepted), "incomplete accepted quantile ladder")
            cell_rows.append({k: v for k, v in metrics.items() if k != "accepted_quantiles"})
            record(root / "metrics.json")
            design = read_json(root / "design/design.json")
            require(design["test_opened"] is False and design["selection_boundary"] == "fold1_internal_training_only",
                    "design is outside the internal training scope")
            record(root / "design/design.json"); record(root / "design/terminal.json")
            design_terminal = read_json(root / "design/terminal.json")
            for name, key in (("X.bin", "X_sha256"), ("y.bin", "y_sha256")):
                contract_hash(root / "design" / name, design_terminal[key])
                record(root / "design" / name)
            for tau in QUANTILES:
                output = root / f"quantiles/al/tau={tau:.2f}"
                contract_path = root / f"contracts/final/tau={tau:.2f}.json"
                contract = read_json(contract_path); value = read_json(output / "terminal.json")
                require_closed(value, terminal=True)
                for flag in ("test_access_authorized", "article_mutation_authorized", "registry_mutation_authorized",
                             "joint_model_authorized", "mcmc_authorized", "exal_authorized"):
                    require(contract.get(flag) is False, f"AL contract firewall changed: {flag}")
                require(contract["candidate_id"] == candidate and contract["split"] == split
                        and contract["tau"] == tau and value["tau"] == tau
                        and value["tau0"] == contract["tau0"] == metrics["tau0"], "AL model identity changed")
                require(value["initialization_only"] is True and value["prior_center_from_initializer"] is False
                        and value["initializer_changes_prior"] is False, "initializer redefines the prior")
                require(value["family"] == "al" and value["package_version"] == "1.1.1"
                        and value["package_repository"] == "CRAN", "wrong likelihood or package")
                contract_hash(Path(contract["parent_dir"]) / "terminal.json", contract["parent_terminal_sha256"])
                contract_hash(Path(contract["design_dir"]) / "terminal.json", contract["design_terminal_sha256"])
                contract_hash(Path(contract["cran_manifest"]), contract["cran_manifest_sha256"])
                contract_hash(Path(contract["cran_adapter"]), contract["cran_adapter_sha256"])
                target = contract["design_terminal_sha256"] + f":tau={tau:.2f}:tau0={contract['tau0']:.17g}"
                require(target == contract["posterior_target_sha256"] == value["posterior_target_sha256"],
                        "quantile posterior-target identity mismatch")
                p = int(value["p"]); beta = np.fromfile(output / "beta_mean.bin", dtype="<f8")
                covariance = np.fromfile(output / "beta_cov.bin", dtype="<f8")
                require(len(beta) == p and len(covariance) == p * p and np.isfinite(covariance).all()
                        and np.all(np.diag(covariance.reshape(p, p)) > 0), "invalid compact AL posterior")
                trace = read_csv(output / "vb_trace.csv"); gate = trace_gate(trace, beta, float(value["sigma"]))
                stored = read_json(output / "diagnostics.json")
                for key in ("absolute_state_tail_max", "relative_state_tail_max", "relative_sigma_tail_max", "relative_elbo_tail_max"):
                    require(np.isclose(gate[key], stored[key], rtol=1e-8, atol=1e-15), "saved gate disagrees with raw trace")
                require(gate["external_gate_passed"] and stored["external_gate_passed"] is True,
                        "raw external numerical gate failed; this closeout is specific to the completed all-pass campaign")
                require(value["formal_converged"] == stored["formal_converged"], "formal convergence flag mismatch")
                require(int(value["iterations"]) == len(trace) <= int(contract["max_iter"]), "iteration count mismatch")
                atom_rows.append({"candidate_id": candidate, "split": split, "tau": tau,
                                  "iterations": len(trace), "formal_converged": bool(value["formal_converged"]),
                                  "at_cap": len(trace) == int(contract["max_iter"]),
                                  "train_seconds": value["train_seconds"], "trace_path": str(output / "vb_trace.csv"), **gate})
                for name in ("terminal.json", "diagnostics.json", "parameter_summary.json", "vb_trace.csv", "beta_mean.bin", "beta_cov.bin"):
                    record(output / name)
                record(contract_path)
    cells = pd.DataFrame(cell_rows); ranking = reconstruct_ranking(cells)
    original = read_csv(campaign / "al_internal/closeout/ranking.csv").reset_index(drop=True)
    require(ranking.candidate_id.tolist() == original.candidate_id.tolist(), "frozen AL ranking order changed")
    require(np.allclose(ranking.drop(columns="candidate_id"), original[ranking.columns].drop(columns="candidate_id"),
                        rtol=1e-12, atol=1e-15), "recomputed AL ranking differs from frozen scores")
    frozen = read_json(campaign / "frozen_internal_choice.json")
    require(frozen["candidate_id"] == ranking.iloc[0].candidate_id
            and np.isclose(frozen["internal_mean_AQL"], ranking.iloc[0].mean_AQL, rtol=1e-12), "frozen winner mismatch")
    storage: dict[str, dict[str, int]] = {}
    for path in campaign.rglob("*"):
        if path.is_file():
            suffix = path.suffix.lower() or "no_extension"
            item = storage.setdefault(suffix, {"files": 0, "bytes": 0})
            item["files"] += 1; item["bytes"] += path.stat().st_size
    return {"cells": cells, "ranking": ranking, "atoms": pd.DataFrame(atom_rows), "ledger": ledger,
            "storage": storage, "terminal": terminal, "control": control, "evaluation": evaluation,
            "ridge_counts": ridge_counts, "normal_rhs_count": len(rhs)}


def verify_ledger(ledger: dict[str, dict[str, Any]]) -> None:
    for value in ledger.values():
        contract_hash(Path(value["path"]), value["sha256"])


def render_pdf(path: Path, audit: dict[str, Any]) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages

    plt.rcParams.update({"font.size": 9, "axes.spines.top": False, "axes.spines.right": False,
                         "axes.grid": True, "grid.alpha": .18, "pdf.fonttype": 42})
    with PdfPages(path) as pdf:
        fig, axes = plt.subplots(1, 2, figsize=(11.7, 8.3))
        ranked = audit["ranking"]
        names = [str(x).replace("r122_", "") for x in ranked.candidate_id]
        axes[0].barh(names, ranked.mean_AQL, color=["#167d8d", "#6c8b45", "#98555f"])
        axes[0].invert_yaxis(); axes[0].set_xlabel("Internal mean AQL (processed price units)")
        axes[1].barh(names, 100 * ranked.mean_coverage, color=["#167d8d", "#6c8b45", "#98555f"])
        axes[1].invert_yaxis(); axes[1].axvline(80, color="#333333", linestyle="--")
        axes[1].set_xlim(0, 100); axes[1].set_xlabel("Coverage of nominal 80% interval (%)")
        fig.suptitle("BG R122: Completed Internal Validation, Not Official Test Results", fontsize=14)
        atoms = audit["atoms"]
        fig.text(.08, .12, f"All {len(atoms)} numerical checks passed. Formal convergence: {int(atoms.formal_converged.sum())}/{len(atoms)}; "
                 f"{int(atoms.at_cap.sum())} reached the cap.\n"
                 "The interval calibration weakness remains. These results do not authorize article promotion.", fontsize=10)
        fig.tight_layout(rect=(.04, .22, .98, .92)); pdf.savefig(fig); plt.close(fig)
        for (candidate, split), group in audit["atoms"].groupby(["candidate_id", "split"]):
            fig, axes = plt.subplots(2, 4, figsize=(11.7, 8.3))
            for ax, row in zip(axes.flat, group.sort_values("tau").itertuples(index=False)):
                trace = read_csv(Path(row.trace_path))
                ax.plot(trace["iter"], trace.elbo, color="#167d8d", linewidth=1.15)
                ax.set_title(f"q={row.tau:.2f} | {row.iterations} iter | formal={row.formal_converged}", fontsize=9)
                ax.set_xlabel("Iteration"); ax.set_ylabel("Raw total ELBO")
            axes.flat[-1].axis("off")
            fig.suptitle(f"{candidate} | Internal Split {split} | Complete Raw ELBO Traces", fontsize=13)
            fig.tight_layout(rect=(.02, .02, .98, .92)); pdf.savefig(fig); plt.close(fig)
            fig, axes = plt.subplots(2, 4, figsize=(11.7, 8.3))
            for ax, row in zip(axes.flat, group.sort_values("tau").itertuples(index=False)):
                trace = read_csv(Path(row.trace_path)).tail(50)
                ax.plot(trace["iter"], trace.elbo, color="#98555f", linewidth=1.15)
                ax.ticklabel_format(axis="y", style="plain", useOffset=False)
                ax.set_title(f"q={row.tau:.2f} | last 25 range={row.elbo_tail_range:.2g}", fontsize=9)
                ax.set_xlabel("Iteration"); ax.set_ylabel("Raw total ELBO (tail)")
            axes.flat[-1].axis("off")
            fig.suptitle(f"{candidate} | Internal Split {split} | Raw ELBO Tail Detail", fontsize=13)
            fig.tight_layout(rect=(.02, .02, .98, .92)); pdf.savefig(fig); plt.close(fig)


def run(args: argparse.Namespace) -> dict[str, Any]:
    campaign, prep, output = args.campaign.resolve(), args.prep.resolve(), args.output.resolve()
    validate_output_root(output, campaign, prep)
    protocol = read_json(args.protocol)
    audit = audit_campaign(campaign, prep, protocol)
    identity = {"campaign_terminal_sha256": sha256_file(campaign / "terminal.json"),
                "preparation_sha256": sha256_file(prep / "summary.json"),
                "protocol_sha256": sha256_file(args.protocol), "script_sha256": sha256_file(Path(__file__))}
    if output.exists():
        existing = read_json(output / "terminal.json")
        require(existing["identity"] == identity, "existing closeout belongs to another immutable audit")
        verify_ledger(audit["ledger"])
        for name, expected in existing["output_sha256"].items():
            contract_hash(output / name, expected)
        return existing
    output.mkdir(parents=True)
    audit["ranking"].to_csv(output / "internal_ranking.csv", index=False)
    audit["cells"].to_csv(output / "internal_split_metrics.csv", index=False)
    audit["atoms"].to_csv(output / "quantile_convergence_audit.csv", index=False)
    pd.DataFrame(audit["ledger"].values()).sort_values("path").to_csv(output / "frozen_evidence_manifest.csv", index=False)
    write_json(output / "storage_inventory.json", audit["storage"])
    render_pdf(output / "pricefm_r122_frozen_internal_diagnostics.pdf", audit)
    verify_ledger(audit["ledger"])
    atoms = audit["atoms"]
    result = {"status": "R122_FROZEN_INTERNAL_CLOSEOUT_COMPLETE_NOT_PROMOTED", "created_at_utc": now_utc(),
              "identity": identity, "executed_head": protocol["executed_head"],
              "counts": {"ridge_cells": sum(audit["ridge_counts"].values()), "normal_rhs_fits": audit["normal_rhs_count"],
                         "al_fits": len(atoms), "eligible_ladders": 9,
                         "formal_converged_al": int(atoms.formal_converged.sum()), "cap_reached_al": int(atoms.at_cap.sum()),
                         "failed_numerical_checks": int((~atoms.external_gate_passed).sum())},
              "frozen_winner": audit["terminal"]["frozen_choice"], "metric_units": protocol["metric_units"],
              "source_preservation_verified": True, "model_fitted": False,
              "max_elbo_tail_range": float(atoms.elbo_tail_range.max()),
              "free_disk_gib": shutil.disk_usage(output).free / 2**30,
              "ready_for_article_promotion": False, "integration_status": "NOT_READY_FOR_INTEGRATION",
              "historical_test_status": audit["evaluation"]["historical_test_status"],
              **{key: False for key in FORBIDDEN}}
    result["output_sha256"] = {p.name: sha256_file(p) for p in output.iterdir() if p.is_file()}
    write_json(output / "terminal.json", result)
    return result


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--campaign", type=Path, required=True)
    value.add_argument("--prep", type=Path, required=True)
    value.add_argument("--output", type=Path, required=True)
    value.add_argument("--protocol", type=Path, default=DEFAULT_PROTOCOL)
    return value


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
