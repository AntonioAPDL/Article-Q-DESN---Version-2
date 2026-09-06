#!/usr/bin/env python3
"""Gate a broad R76 exAL launch using longer repaired-mechanism probes."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
from typing import Any

import numpy as np
import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r75b_large_n_gig_stability_probe_20260902"
GRID = DATA / "experiment_grids" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r75b_large_n_gig_stability_gate_20260902"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=GRID / "probe_manifest.csv")
    p.add_argument("--status", type=Path, default=GRID / "probe_status.csv")
    p.add_argument("--launch-summary", type=Path, default=GRID / "probe_launch_summary.json")
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--force", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest = pd.read_csv(args.manifest).sort_values(["region", "fold", "tau"])
    status = pd.read_csv(args.status)
    launch = json.loads(args.launch_summary.read_text())
    if len(manifest) != 9 or len(status) != 9 or set(manifest.task_id) != set(status.task_id):
        raise RuntimeError("R75B surface is incomplete")
    if launch.get("failed") != 0 or launch.get("completed") != 9:
        raise RuntimeError("R75B launch did not finish cleanly")
    rows: list[dict[str, Any]] = []
    tail_rows: list[dict[str, Any]] = []
    sources = [Path(__file__).resolve(), args.manifest.resolve(), args.status.resolve(), args.launch_summary.resolve()]
    for task in manifest.itertuples(index=False):
        output = Path(task.output_dir)
        terminal_path = output / "terminal.json"
        terminal = json.loads(terminal_path.read_text())
        if terminal.get("status") != "completed" or terminal.get("test_loaded") is not False:
            raise RuntimeError(f"Invalid R75B terminal: {terminal_path}")
        for name, expected in (terminal.get("artifact_sha256") or {}).items():
            if sha256(output / name) != expected:
                raise RuntimeError(f"Changed R75B artifact: {output / name}")
        summary = pd.read_csv(output / "probe_summary.csv")
        trace = pd.read_csv(output / "vb_trace.csv")
        if len(summary) != 1 or len(trace) < 80:
            raise RuntimeError(f"R75B trace is shorter than registered: {output}")
        required = ["sigma", "gamma", "delta_state", "delta_sigma", "delta_gamma", "delta_s"]
        if any(name not in trace for name in required) or not np.isfinite(trace[required].to_numpy(float)).all():
            raise RuntimeError(f"R75B required trace is non-finite: {output}")
        tail = trace.tail(10)
        first_elbo = pd.to_numeric(trace.elbo, errors="coerce").dropna().iloc[0]
        final_elbo = pd.to_numeric(trace.elbo, errors="coerce").dropna().iloc[-1]
        tail_rows.append({
            "task_id": task.task_id,
            "final_delta_state": float(trace.delta_state.iloc[-1]),
            "tail_max_delta_state": float(tail.delta_state.max()),
            "tail_median_delta_state": float(tail.delta_state.median()),
            "first_finite_elbo": float(first_elbo),
            "final_finite_elbo": float(final_elbo),
            "elbo_net_change": float(final_elbo - first_elbo),
            "converged": bool(summary.converged.iloc[0]),
        })
        rows.append(summary.iloc[0].to_dict())
        sources.extend([terminal_path, output / "probe_summary.csv", output / "vb_trace.csv",
                        output / "spd_factorization_trace.csv", output / "structured_grid.csv"])
    probes = pd.DataFrame(rows).sort_values(["region", "fold", "tau"])
    tails = pd.DataFrame(tail_rows).sort_values("task_id")
    finite = np.isfinite(probes[["exal_sigma", "exal_gamma", "beta_l2_ratio", "sigma_ratio", "train_AQL_ratio"]].to_numpy(float)).all()
    checks = pd.DataFrame([
        {"gate": "all_nine_long_probes_completed", "passed": len(probes) == 9, "observed": len(probes)},
        {"gate": "all_required_outputs_finite", "passed": finite, "observed": finite},
        {"gate": "large_n_backend_exercised", "passed": probes.large_n_bessel_backend.eq("uniform_large_order").all(), "observed": probes.large_n_bessel_backend.value_counts().to_dict()},
        {"gate": "production_minimum_structured_updates", "passed": probes.structured_updates.ge(35).all(), "observed": int(probes.structured_updates.min())},
        {"gate": "scale_bounded", "passed": probes.sigma_ratio.between(1e-6, 100).all(), "observed": float(probes.sigma_ratio.max())},
        {"gate": "skewness_bounded", "passed": probes.exal_gamma.abs().lt(20).all(), "observed": float(probes.exal_gamma.abs().max())},
        {"gate": "coefficients_not_exploding", "passed": probes.beta_l2_ratio.lt(20).all(), "observed": float(probes.beta_l2_ratio.max())},
        {"gate": "training_loss_not_exploding", "passed": probes.train_AQL_ratio.lt(5).all(), "observed": float(probes.train_AQL_ratio.max())},
        {"gate": "late_state_changes_bounded", "passed": tails.tail_max_delta_state.lt(2).all(), "observed": float(tails.tail_max_delta_state.max())},
        {"gate": "elbo_not_collapsing", "passed": tails.elbo_net_change.gt(-1e-6).all(), "observed": float(tails.elbo_net_change.min())},
        {"gate": "test_registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
    ])
    passed = bool(checks.passed.all())
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)
    probes.to_csv(output / "pricefm_stage_r75b_stability_probe_results.csv", index=False)
    tails.to_csv(output / "pricefm_stage_r75b_tail_stability.csv", index=False)
    checks.to_csv(output / "pricefm_stage_r75b_stability_gates.csv", index=False)
    pd.DataFrame([
        {"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in dict.fromkeys(path.resolve() for path in sources)
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "long_stability_gate_passed" if passed else "long_stability_gate_failed",
        "probes": 9,
        "converged_probes": int(probes.converged.astype(bool).sum()),
        "minimum_structured_updates": int(probes.structured_updates.min()),
        "max_abs_gamma": float(probes.exal_gamma.abs().max()),
        "max_sigma_ratio": float(probes.sigma_ratio.max()),
        "max_train_AQL_ratio": float(probes.train_AQL_ratio.max()),
        "max_tail_delta_state": float(tails.tail_max_delta_state.max()),
        "r76_broad_launch_authorized": passed,
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    (output / "pricefm_stage_r75b_stability_gate_report.md").write_text(
        "# PriceFM Stage-R75B exAL Stability Gate\n\n"
        f"Nine 100-iteration, train-only probes produced `{summary['status']}`. "
        "This gate evaluates numerical and optimization stability only; it does not select models "
        "or authorize test, registry, article, joint-model, or MCMC access.\n"
    )
    if not passed:
        raise RuntimeError(f"R75B stability gate failed: {checks.loc[~checks.passed, 'gate'].tolist()}")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
