"""Compact diagnostics for a frozen-fit, training-internal forecast replay."""
from __future__ import annotations

import json
import os
from pathlib import Path

import numpy as np
import pandas as pd


NAMES = {"r123_6d32d129873c7930": "A", "r123_3e15bdc342f556c1": "B",
         "r123_8680f8aaeaeae8ce": "C"}
COLORS = {"mean_feature": "#087f8c", "path_specific": "#a14b92", "normal_driver": "#d27826"}


def report(output, jobs, frame, comparison, ranking, labels):
    output = Path(output)
    os.environ["MPLCONFIGDIR"] = str(output / "plot_cache")
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages
    plt.rcParams.update({"font.size": 10, "axes.spines.top": False, "axes.spines.right": False,
                         "axes.grid": True, "grid.alpha": .2, "pdf.fonttype": 42})
    leader = str(ranking.iloc[0].candidate_id)
    lines = ["# R124 covariance-preserving forecast replay", "",
        "BG; outer Fold 1 training only; three internal chronological validation splits.",
        "96 quarter-hour steps = 24 hours. AQL is in outer-Fold-1 scaled-price units, not EUR/MWh.",
        "No models were refitted; official validation/test and article authority remain untouched.", "",
        "## Corrected primary ranking", "", "| Candidate | Mean AQL | Late AQL | Coverage 80% | Crossing |",
        "|---|---:|---:|---:|---:|"]
    for row in ranking.itertuples():
        lines.append(f"| {NAMES[row.candidate_id]} | {row.mean_AQL:.8f} | {row.mean_late_AQL:.8f} | "
                     f"{row.mean_coverage:.3f} | {row.mean_crossing:.4f} |")
    lines.extend(["", "## Same-fit legacy versus corrected primary", "",
        "| Candidate | Internal split | Legacy AQL | Corrected AQL | Change |",
        "|---|---:|---:|---:|---:|"])
    for row in comparison.itertuples():
        lines.append(f"| {NAMES[row.candidate_id]} | {row.split} | {row.legacy_AQL:.8f} | {row.AQL:.8f} | {row.AQL_change_percent:+.2f}% |")
    capped = int((~labels.formal_converged).sum())
    lines.extend(["", "## Interpretation and limitations", "",
        f"The corrected internal leader is {NAMES[leader]}. All nine Normal parents and 63 AL fits were reused.",
        f"{capped} AL fits remain iteration-capped. The external raw gate is not a full-state stationarity certificate.",
        "The former sampler added jI to the saved covariance unconditionally; this replay adds no variance.",
        "Any score change therefore concerns forecast simulation, not a changed prior or refitted posterior.",
        "The primary mean-feature forecast averages conditional quantile readouts; it is not a marginal-mixture quantile.",
        "Path-specific readouts and Normal-driver empirical quantiles are separate diagnostics, not interchangeable estimands.",
        "Coverage of these approximate quantile curves cannot by itself diagnose VB posterior underdispersion.",
        "No old forecast curves were reconstructed: the legacy comparison uses its verified saved metrics only.",
        "Inspect raw ELBO traces alongside the formal labels; a flat visible tail does not certify unexported RHS/latent states.", "",
        "## Next stage, not launched", "",
        "Separate authorization is required for official-fold evaluation. Freeze the corrected spec/tau0 before opening outcomes.",
        "Fit the selected specification on each full-fold training window (3 Normal + 21 AL fits), not the partial internal windows.",
        "Document or resolve the capped-fit stationarity gap without blanket refitting. Match units, timestamps and origins to actual cached PriceFM.",
        "Do not use a QDESN-with-PriceFM-driver score as PriceFM's own score. Do not tune on official test outcomes.", "",
        "NOT_READY_FOR_INTEGRATION for scientific/article authority.", ""])
    (output / "replay_report.md").write_text("\n".join(lines))
    with PdfPages(output / "replay_diagnostics.pdf") as pdf:
        fig = plt.figure(figsize=(11.7, 8.3))
        fig.text(.07, .91, "R124 | Covariance-preserving replay", fontsize=20, weight="bold")
        fig.text(.07, .85, "BG / Fold-1 training-internal validation / three chronological splits", fontsize=12)
        fig.text(.07, .80, "Same fits, corrected Gaussian covariance; 500 recursive Normal-driven paths per origin.")
        columns = ["Candidate", "Mean AQL", "Late AQL", "80% coverage", "Crossing"]
        rows = [[NAMES[r.candidate_id], f"{r.mean_AQL:.6f}", f"{r.mean_late_AQL:.6f}",
                 f"{r.mean_coverage:.1%}", f"{r.mean_crossing:.2%}"] for r in ranking.itertuples()]
        ax = fig.add_axes([.07, .52, .86, .20]); ax.axis("off")
        table = ax.table(cellText=rows, colLabels=columns, loc="center", cellLoc="center")
        table.auto_set_font_size(False); table.set_fontsize(11); table.scale(1, 1.8)
        fig.text(.07, .43, "Interpretation", fontsize=13, weight="bold")
        fig.text(.07, .18,
            "AQL is scaled-price loss, not article currency AQL. 96 steps = 24 hours.\n"
            f"{capped}/63 AL fits remain capped; full-state variational stationarity is not certified.\n"
            "Mean-feature curves approximate conditional quantiles, not marginal-mixture quantiles.\n"
            "Official folds were not opened. No refitting, screening or article promotion occurred.\n"
            "The next official evaluation needs separately authorized full-training fits.", linespacing=1.8)
        pdf.savefig(fig); plt.close(fig)
        fig, axes = plt.subplots(1, 3, figsize=(11.7, 6.3), sharey=True)
        for ax, (candidate, group) in zip(axes, comparison.groupby("candidate_id", sort=True)):
            group = group.sort_values("split")
            ax.plot(group.split, group.legacy_AQL, "o--", label="Legacy sampler", color="#7b8290")
            ax.plot(group.split, group.AQL, "o-", label="Correct covariance", color=COLORS["mean_feature"])
            ax.set(title=f"Candidate {NAMES[candidate]}", xlabel="Internal split", xticks=[1, 2, 3])
        axes[0].set_ylabel("Mean-feature AQL (scaled price)"); axes[-1].legend()
        fig.suptitle("Same fitted posteriors: effect of removing covariance inflation", fontsize=15)
        fig.tight_layout(rect=[0, .03, 1, .93]); pdf.savefig(fig); plt.close(fig)
        fig, axes = plt.subplots(1, 3, figsize=(11.7, 6.3), sharey=True)
        for ax, (candidate, group) in zip(axes, frame.groupby("candidate_id", sort=True)):
            for operator, rows in group.groupby("operator"):
                rows = rows.sort_values("split")
                ax.plot(rows.split, rows.AQL, "o-", color=COLORS[operator], label=operator.replace("_", " "))
            ax.set(title=f"Candidate {NAMES[candidate]}", xlabel="Internal split", xticks=[1, 2, 3])
        axes[0].set_ylabel("AQL (scaled price)"); axes[-1].legend(fontsize=8)
        fig.suptitle("Three operators from the same corrected recursion", fontsize=15)
        fig.tight_layout(rect=[0, .03, 1, .93]); pdf.savefig(fig); plt.close(fig)
        for split in (1, 2, 3):
            job = next(j for j in jobs if j["candidate_id"] == "r123_3e15bdc342f556c1" and j["split"] == split)
            fig, axes = plt.subplots(4, 2, figsize=(11.7, 8.3))
            for ax, (tau, path) in zip(axes.flat, sorted(job["quantile_dirs"].items(), key=lambda v: float(v[0]))):
                trace = pd.read_csv(Path(path) / "vb_trace.csv")
                terminal = json.loads((Path(path) / "terminal.json").read_text())
                ax.plot(trace["iter"], trace.elbo, color="#254b6e", linewidth=1)
                label = "converged" if terminal["formal_converged"] else "iteration cap"
                ax.set_title(f"AL q={float(tau):.2f} / {label}", fontsize=10)
                ax.set_xlabel("Iteration"); ax.set_ylabel("Raw total ELBO")
                ax.ticklabel_format(axis="y", style="plain", useOffset=False)
            axes.flat[-1].axis("off")
            axes.flat[-1].text(0, .8, "Frozen fits; no ELBO normalization.\nVisible tail flatness is not a complete\nRHS/latent-state convergence certificate.", va="top", fontsize=10)
            fig.suptitle(f"Candidate B / internal split {split}: raw total ELBO", fontsize=15)
            fig.tight_layout(rect=[0, .02, 1, .95]); pdf.savefig(fig); plt.close(fig)
        for job in sorted((j for j in jobs if j["candidate_id"] == leader), key=lambda j: j["split"]):
            with np.load(Path(job["output_dir"]) / "predictions.npz", allow_pickle=False) as values:
                count = len(values["truth"]); selected = sorted({0, count // 2, count - 1})
                fig, axes = plt.subplots(len(selected), 1, figsize=(11.7, 8.3), sharex=True)
                for ax, origin in zip(np.atleast_1d(axes), selected):
                    ax.plot(np.arange(1, 97) / 4, values["truth"][origin], color="#23272b", label="Observed price", linewidth=1.2)
                    for operator in COLORS:
                        curve = values[operator][origin]
                        ax.plot(np.arange(1, 97) / 4, curve[:, 3], color=COLORS[operator], label=operator.replace("_", " "), linewidth=1)
                        ax.fill_between(np.arange(1, 97) / 4, curve[:, 0], curve[:, -1], color=COLORS[operator], alpha=.10)
                    ax.set_title(str(values["origin_utc"][origin]), fontsize=10)
                    ax.set_ylabel("Scaled price")
                axes[0].legend(ncol=4, fontsize=8); axes[-1].set_xlabel("Hours ahead (15-minute steps)")
                fig.suptitle(f"Corrected leader {NAMES[leader]} / internal split {job['split']} / fixed first, middle, last origins", fontsize=13)
                fig.tight_layout(rect=[0, .02, 1, .94]); pdf.savefig(fig); plt.close(fig)
