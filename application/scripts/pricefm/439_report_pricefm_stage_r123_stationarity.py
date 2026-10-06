#!/usr/bin/env python3
"""Render complete diagnostic traces without modifying model evidence."""
import argparse
import json
from pathlib import Path
import re

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
import numpy as np
import pandas as pd

import pricefm_r123_recovery as REC


def render(root, report_stem="pricefm_r123_stationarity_diagnostics"):
    root = Path(root)
    if not re.fullmatch(r"[a-zA-Z0-9_]+", report_stem):
        raise ValueError("report stem must be a simple ASCII filename")
    terminal = REC.read(root / "terminal.json")
    check = REC.read(root / "closeout/objective_check.json")
    if terminal["status"] != "R123_STATIONARITY_DIAGNOSIS_COMPLETE" or check["status"] != "R123_STATE_OBJECTIVE_CLOSEOUT_PASS":
        raise RuntimeError("full diagnostic/objective audit required")
    if REC.digest(root / "closeout/audit_table.csv") != check["audit_table_sha256"]:
        raise RuntimeError("audited table changed")
    table = pd.read_csv(root / "closeout/audit_table.csv")
    manifest = REC.read(root / "manifest.json")
    if len(table) != 10 or len(manifest) != 10: raise RuntimeError("incomplete diagnostic panel")
    output = root / "closeout" / f"{report_stem}.pdf"
    identity = root / "closeout" / ("report_identity.json" if report_stem ==
        "pricefm_r123_stationarity_diagnostics" else f"{report_stem}_identity.json")
    if output.exists() or identity.exists(): raise RuntimeError("refusing to overwrite diagnostic PDF or identity")
    plt.rcParams.update({"font.size": 9, "axes.titlesize": 10, "axes.labelsize": 9,
        "font.family": "DejaVu Sans", "axes.spines.top": False, "axes.spines.right": False,
        "pdf.fonttype": 42, "axes.grid": True, "grid.alpha": .18})
    with PdfPages(output) as pdf:
        for job in manifest:
            folder = Path(job["output_dir"]); value = REC.read(folder / "terminal.json")
            for name, wanted in value["artifact_sha256"].items():
                if REC.digest(folder / name) != wanted: raise RuntimeError("diagnostic artifact changed")
            trace = pd.read_csv(folder / "convergence_trace.csv")
            recorded = trace[trace.total_objective.notna()]
            geometry = REC.read(folder / "geometry.json")
            row = table[table.fit_id.eq(job["fit_id"])].iloc[0]
            fig, axes = plt.subplots(3, 2, figsize=(14, 10))
            fig.subplots_adjust(left=.16, right=.97, top=.83, bottom=.19, hspace=.80, wspace=.52)
            panels = [
                ("total_objective", "Raw Total Variational Objective", None, False),
                ("objective_delta_per_observation", "Absolute Objective Increment / Observation", 1e-8, True),
                ("prior_rms_log_precision_delta", "RMS Log Prior-Precision Change", 1e-6, True),
                ("rhs_max_log_rate_delta", "Maximum Active RHS Log-Rate Change", 1e-6, True),
                ("beta_cov_relative_delta", "Relative Covariance Change", 1e-6, True),
                ("sigma2_mean", "Noise Variance", None, False)]
            for ax, (column, title, threshold, logarithmic) in zip(axes.flat, panels):
                values = recorded[column].to_numpy()
                if logarithmic: values = np.maximum(np.abs(values), 1e-16)
                ax.plot(recorded.iter, values, color="#167D8D", linewidth=1.25)
                if logarithmic: ax.set_yscale("log")
                else: ax.ticklabel_format(axis="y", style="plain", useOffset=False)
                if threshold is not None: ax.axhline(threshold, color="#B34D42", ls="--", lw=.9)
                ax.set_title(title, loc="left"); ax.set_xlabel("Total Iteration")
            state = "FULL-STATE CERTIFIED" if row.certified else "CAPPED: NOT SELECTABLE"
            fig.text(.16, .95, "BG / R123 Convergence Diagnosis", fontsize=16, weight="bold")
            fig.text(.16, .91, f"{job['candidate_id']} | internal split {job['split']} | {row.initialization} | {state}", fontsize=10)
            fig.text(.16, .875, f"Recorded iterations {int(recorded.iter.min())} - {int(recorded.iter.max())}; "
                f"normalized Gram numerical rank {geometry['normalized_gram_numerical_rank']}/{geometry['p']}; "
                f"maximum precision jitter {row.maximum_precision_jitter:.2g}", fontsize=9, color="#555555")
            fig.text(.16, .065, "No objective history is invented before a saved checkpoint. Dashed lines are fixed tolerances.\n"
                "Training-internal diagnosis only; no official test, quantile fitting or article promotion.", fontsize=9)
            pdf.savefig(fig); plt.close(fig)
    REC.immutable(identity, dict(status="R123_DIAGNOSTIC_REPORT_COMPLETE",
        pdf_sha256=REC.digest(output), pages=10, test_opened=False, selection_authorized=False,
        renderer_sha256=REC.digest(__file__)))
    return {"pdf": str(output), "pages": 10, "certified": int(table.certified.sum()), "capped": int((~table.certified).sum())}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--report-stem", default="pricefm_r123_stationarity_diagnostics")
    args = parser.parse_args()
    print(json.dumps(render(args.root, args.report_stem), sort_keys=True))
