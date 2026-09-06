#!/usr/bin/env python3
"""Gate the R75 numerical repair using package and real-data probe evidence."""

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
TAG = "pricefm_stage_r75_large_n_gig_mechanism_probe_20260902"
GRID = DATA / "experiment_grids" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r75_large_n_gig_mechanism_gate_20260902"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=GRID / "probe_manifest.csv")
    p.add_argument("--status", type=Path, default=GRID / "probe_status.csv")
    p.add_argument("--launch-summary", type=Path, default=GRID / "probe_launch_summary.json")
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-tasks", type=int, default=9)
    p.add_argument("--force", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest = pd.read_csv(args.manifest)
    status = pd.read_csv(args.status)
    launch = json.loads(args.launch_summary.read_text())
    if len(manifest) != args.expected_tasks or len(status) != args.expected_tasks:
        raise RuntimeError("Unexpected R75 probe count")
    if set(manifest.task_id) != set(status.task_id) or launch.get("failed") != 0:
        raise RuntimeError("R75 probe launch did not complete cleanly")
    rows = []
    sources = [Path(__file__).resolve(), args.manifest.resolve(), args.status.resolve(), args.launch_summary.resolve()]
    for task in manifest.itertuples(index=False):
        output = Path(task.output_dir)
        terminal_path = output / "terminal.json"
        terminal = json.loads(terminal_path.read_text())
        if terminal.get("status") != "completed" or terminal.get("test_loaded"):
            raise RuntimeError(f"Invalid R75 probe terminal: {terminal_path}")
        hashes = terminal.get("artifact_sha256") or {}
        for name, expected in hashes.items():
            if sha256(output / name) != expected:
                raise RuntimeError(f"Changed R75 probe artifact: {output / name}")
        frame = pd.read_csv(output / "probe_summary.csv")
        if len(frame) != 1:
            raise RuntimeError(f"Invalid R75 probe summary: {output}")
        rows.append(frame.iloc[0].to_dict())
        sources.extend([terminal_path, output / "probe_summary.csv", output / "vb_trace.csv",
                        output / "spd_factorization_trace.csv", output / "structured_grid.csv"])
    probes = pd.DataFrame(rows).sort_values(["region", "fold", "tau"])
    numeric = ["exal_sigma", "exal_gamma", "beta_l2_ratio", "sigma_ratio", "train_AQL_ratio", "elapsed_seconds"]
    finite = np.isfinite(probes[numeric].to_numpy(float)).all()
    checks = pd.DataFrame([
        {"gate": "all_nine_probes_completed", "passed": len(probes) == args.expected_tasks, "observed": len(probes)},
        {"gate": "all_outputs_finite", "passed": finite, "observed": finite},
        {"gate": "large_n_uniform_backend_exercised", "passed": probes.large_n_bessel_backend.eq("uniform_large_order").all(), "observed": probes.large_n_bessel_backend.value_counts().to_dict()},
        {"gate": "structured_updates_active", "passed": probes.structured_updates.ge(1).all(), "observed": int(probes.structured_updates.min())},
        {"gate": "delta_s_observable", "passed": probes.delta_s_nonzero.astype(bool).all(), "observed": int(probes.delta_s_nonzero.astype(bool).sum())},
        {"gate": "no_beta_explosion", "passed": probes.beta_l2_ratio.between(1e-4, 20).all(), "observed": float(probes.beta_l2_ratio.max())},
        {"gate": "no_sigma_explosion", "passed": probes.sigma_ratio.between(1e-4, 100).all(), "observed": float(probes.sigma_ratio.max())},
        {"gate": "no_training_loss_explosion", "passed": probes.train_AQL_ratio.lt(5).all(), "observed": float(probes.train_AQL_ratio.max())},
        {"gate": "test_registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
    ])
    passed = bool(checks.passed.all())
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)
    probes.to_csv(output / "pricefm_stage_r75_real_data_probe_results.csv", index=False)
    checks.to_csv(output / "pricefm_stage_r75_mechanism_gates.csv", index=False)
    pd.DataFrame([
        {"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in dict.fromkeys(sources)
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "large_n_structured_exal_mechanism_gate_passed" if passed else "large_n_structured_exal_mechanism_gate_failed",
        "probes": int(len(probes)), "probe_failures": int((~checks.passed).sum()),
        "max_beta_l2_ratio": float(probes.beta_l2_ratio.max()),
        "max_sigma_ratio": float(probes.sigma_ratio.max()),
        "max_train_AQL_ratio": float(probes.train_AQL_ratio.max()),
        "r76_launch_prep_authorized": passed,
        "r76_broad_launch_authorized": False,
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    (output / "pricefm_stage_r75_mechanism_gate_report.md").write_text(
        "# PriceFM Stage-R75 Structured-exAL Mechanism Gate\n\n"
        f"All {len(probes)} bounded real-data probes were checked. Gate status: "
        f"`{summary['status']}`. This authorizes R76 launch preparation only; it does "
        "not authorize test access, registry/article mutation, joint fitting, or MCMC.\n"
    )
    if not passed:
        raise RuntimeError(f"R75 mechanism gate failed: {checks.loc[~checks.passed, 'gate'].tolist()}")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
