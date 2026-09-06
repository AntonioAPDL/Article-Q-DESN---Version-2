#!/usr/bin/env python3
"""Gate the zero-freeze R76 repair from three diagnostic controls."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil

import numpy as np
import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R80 = DATA / "runs/pricefm_stage_r80_exal_diagnostic_replay_20260904"
R80B = DATA / "runs/pricefm_stage_r80b_zero_freeze_probe_20260904"
R80C = DATA / "runs/pricefm_stage_r80c_zero_freeze_controls_20260904"
OUTPUT = DATA / "authoritative/pricefm_stage_r80_zero_freeze_repair_gate_20260904"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r80-runs", type=Path, default=R80)
    p.add_argument("--r80b-runs", type=Path, default=R80B)
    p.add_argument("--r80c-runs", type=Path, default=R80C)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--force", action="store_true")
    return p


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def control_row(path: Path) -> dict:
    terminal_path = path / "terminal.json"
    terminal = json.loads(terminal_path.read_text())
    if terminal.get("status") != "completed" or terminal.get("test_loaded") is not False:
        raise RuntimeError(f"Zero-freeze control did not complete: {path}")
    trace = pd.read_csv(path / "vb_trace.csv")
    required = ["sigma", "gamma", "delta_state", "delta_sigma", "delta_gamma", "delta_s"]
    finite = np.isfinite(trace[required].to_numpy(float)).all()
    return {
        "task_id": terminal["task_id"], "case_id": terminal["case_id"],
        "tau": float(terminal["tau"]), "iter": int(terminal["iter"]),
        "structured_updates": int(terminal["structured_updates"]),
        "converged": bool(terminal["converged"]), "trace_finite": bool(finite),
        "max_abs_gamma": float(trace.gamma.abs().max()),
        "max_sigma": float(trace.sigma.max()),
        "tail_max_delta_state": float(trace.tail(10).delta_state.max()),
        "terminal_sha256": sha256(terminal_path), "output_dir": str(path),
    }


def run(args: argparse.Namespace) -> dict:
    baseline = sorted(args.r80_runs.glob("*/failure_diagnostics.json"))
    if len(baseline) != 3:
        raise RuntimeError("R80 baseline diagnostic replay is incomplete")
    events = [json.loads(path.read_text()) for path in baseline]
    fr = [e for e in events if e.get("kind") == "no_finite_gamma_grid"]
    terminal = [e for e in events if e.get("stage") == "terminal_contract"]
    root_demonstrated = (
        len(fr) == 1 and fr[0].get("iter") == 11 and
        max(abs(float(v)) for k, v in fr[0]["stats"].items() if k.startswith("sum_")) > 1e100
    )
    transient_demonstrated = len(terminal) == 2 and all(
        set(e.get("failed_fields", [])) == {"trace.sigma", "trace.delta_sigma"}
        for e in terminal
    )
    controls = [control_row(path.parent) for path in sorted(args.r80b_runs.glob("*/terminal.json"))]
    controls += [control_row(path.parent) for path in sorted(args.r80c_runs.glob("*/terminal.json"))]
    frame = pd.DataFrame(controls).sort_values(["case_id", "tau"])
    controls_pass = (
        len(frame) == 3 and set(frame.tau) == {0.25, 0.75} and frame.trace_finite.all()
        and frame.structured_updates.ge(35).all() and frame.max_abs_gamma.lt(20).all()
        and frame.max_sigma.lt(100).all() and frame.tail_max_delta_state.lt(2).all()
    )
    authorized = bool(root_demonstrated and transient_demonstrated and controls_pass)
    gates = pd.DataFrame([
        {"gate": "frozen_warmup_explosion_reproduced", "passed": root_demonstrated, "observed": "FR f3 tau .25 iteration 11"},
        {"gate": "late_transient_overflow_reproduced", "passed": transient_demonstrated, "observed": "SE_4 f1 tau .25/.75"},
        {"gate": "three_zero_freeze_controls_completed", "passed": len(frame) == 3, "observed": len(frame)},
        {"gate": "zero_freeze_control_traces_finite", "passed": bool(len(frame) == 3 and frame.trace_finite.all()), "observed": int(frame.trace_finite.sum())},
        {"gate": "minimum_structured_updates", "passed": bool(len(frame) == 3 and frame.structured_updates.ge(35).all()), "observed": int(frame.structured_updates.min())},
        {"gate": "bounded_tail_state_change", "passed": bool(len(frame) == 3 and frame.tail_max_delta_state.lt(2).all()), "observed": float(frame.tail_max_delta_state.max())},
        {"gate": "r81_bounded_retry_authorized", "passed": authorized, "observed": 14 if authorized else 0},
        {"gate": "test_registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)
    frame.to_csv(output / "pricefm_stage_r80_zero_freeze_control_results.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r80_zero_freeze_repair_gates.csv", index=False)
    sources = baseline
    for path in list(args.r80b_runs.glob("*")) + list(args.r80c_runs.glob("*")):
        if path.is_dir():
            sources.extend([path / "terminal.json", path / "vb_trace.csv", path / "method_summary.csv"])
    pd.DataFrame([{"path": str(p.resolve()), "sha256": sha256(p), "bytes": p.stat().st_size}
                  for p in sources]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "zero_freeze_repair_gate_passed" if authorized else "zero_freeze_repair_gate_failed",
        "diagnostic_controls": int(len(frame)), "r81_retry_authorized": authorized,
        "r81_retry_atoms": 14 if authorized else 0, "test_opened": False,
        "registry_mutated": False, "article_mutated": False,
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    (output / "pricefm_stage_r80_zero_freeze_repair_report.md").write_text(
        "# PriceFM Stage-R80 Zero-Freeze Repair Gate\n\n"
        "The registered controls test whether removing the frozen scale/skewness warm-up prevents "
        "both the immediate latent-state explosion and late transient sigma overflow while leaving "
        "the DESN, prior, likelihood, seed, data, and AL warm start unchanged. The result authorizes "
        "at most the 14 failed R76 atoms; it never authorizes a broad refit, test access, or mutation.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
