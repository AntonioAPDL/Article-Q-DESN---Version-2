#!/usr/bin/env python3.11
"""Bounded presentation-only appendix derivatives; no model objects or jobs.

The explicitly enumerated inputs are authenticated against the approved
a9220a25 baseline. Only new appendix_compact_20261106_*.tex outputs can be
written. --check authenticates sources, checks scientific keys and rounding,
and compares every derivative byte-for-byte without writing anything.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "tables/appendix_compact_20261106_"
OUTPUTS = tuple(PREFIX + role + ".tex" for role in (
    "glofas_specifications", "glofas_diagnostics", "glofas_convergence",
    "glofas_historical_scores", "mq_scores", "score_diagnostics",
    "ind_forecast_mae", "ind_fit_rmse", "ind_sensitivity", "ind_frequencies", "mq_fit_rmse",
))
SOURCE_SHA256 = {
    "tables/glofas_search3_part1234_final_20261007_selected_specifications.csv": "145f46473075f623f3f334c0144460c96c18a1523a3f555b75f3ac5ba9c3ecd7",
    "tables/glofas_same_family_20261103_family_metrics.csv": "da4b1bb897c55e2b23b9da7d32195311a010911a87ec0ea6688db76a80523b31",
    "tables/glofas_same_family_20261103_convergence.csv": "d25384bae5e2a5660ae83a8e1a06ffe97737f27535aaa2147157839e3ffd61b9",
    "tables/glofas_reference_discrepancy_scores_display.tex": "bb19c13b4d48f76913884742f6dfafdb04b0e8bc7c817092da2c5be41eff06b7",
    "tables/qdesn_multiquantile_recursive_policy_display.tex": "6a189d844cf9a402c4a2cf6b6a362f3d64db0beef1436a44186a07a48c1cb47f",
    "tables/joint_qdesn_pure_desn_v2_forecast_score_summary.csv": "9dacd530801674de5baa32624b38225dbb35ef1f3424548b34519b8fa78c16f0",
    "tables/independent_train500_eval300_mcmc_mae_figure_v1.tex": "d6a3a2a1d977063a13e2c9bc902bf031822b2e0e6cf3cc23234bdec16c88b40a",
    "tables/qdesn_single_quantile_mcmc_fit_figure_display.tex": "4b669e4102f5ffc55f58c2e1931d43dbb90b213c29f1bbe041c6a4ab6b8465ac",
    "tables/independent_train500_eval500_mcmc_figures_v1.tex": "35427b4a47d1e05553b40e075a3dda811923e4c64f2dd641da87292a9fdf4e3f",
    "tables/independent_forecast_calibration_figure_v1.tex": "54e403240197da236963283503561159d9a490a1eb512f8c7a1aee4ac5de640e",
    "tables/qdesn_multiquantile_fit_figure_display.tex": "b5f1d0af825da5810e2ee2aae19ed60ab8b9b991c8ef59828fc69a8cda0ebd05",
}
COMMENT = "% Presentation-only derivative; scripts/build_appendix_compact_tables_20261106.py\n"
FAMILIES = {
    "Raw GloFAS": "Raw GloFAS", "Normal Ridge": "Gaussian DESN (ridge)",
    "Normal RHS": "Gaussian DESN (RHS)", "Independent AL": "Q--DESN (AL)",
    "Independent exAL": "Q--DESN (exAL)", "MQ AL": "MQ--DESN (AL)",
    "MQ exAL": "MQ--DESN (exAL)",
}
SCENARIOS = {
    "Asymmetric-Laplace tail": "asymmetric_laplace_tail",
    "Gaussian-mixture innovations": "gaussian_mixture_bridge",
    "Laplace innovations": "laplace_bridge",
    "Nonlinear reservoir dynamics": "nonlinear_reservoir_friendly",
    "Gaussian innovations": "normal_bridge",
    "Persistent heavy tails": "persistent_heavy_tail", "Regime shift": "regime_shift",
    r"Student-\(t\) location--scale": "student_t_location_scale",
}


def authenticated_sources(root: Path = ROOT) -> dict[str, str]:
    result = {}
    for name, digest in SOURCE_SHA256.items():
        data = (root / name).read_bytes()
        if hashlib.sha256(data).hexdigest() != digest:
            raise ValueError(f"Frozen presentation input changed: {name}")
        result[name] = data.decode("utf-8")
    return result


def rows(sources: dict[str, str], name: str) -> list[dict[str, str]]:
    return list(csv.DictReader(io.StringIO(sources["tables/" + name])))


def tabular(columns: str, header: str, body: list[str]) -> str:
    return "\n".join([r"\begin{tabular}{" + columns + "}", r"\toprule", header + r" \\",
                      r"\midrule", *[row + r" \\" for row in body], r"\bottomrule",
                      r"\end{tabular}", ""])


def replace_captions(source: str, captions: list[str]) -> str:
    # Balanced braces preserve all graphics, dimensions, labels and alt text.
    for caption in captions:
        start = source.index(r"\caption{")
        opening = start + len(r"\caption")
        depth, end = 1, opening + 1
        while depth:
            if source[end] == "{":
                depth += 1
            elif source[end] == "}":
                depth -= 1
            end += 1
        source = source[:start] + "@@CAPTION@@{" + caption + "}" + source[end:]
    return source.replace("@@CAPTION@@", r"\caption")


def validate_mq_scores(source: str, data: list[dict[str, str]]) -> None:
    expected = {(r["scenario_id"], r["fit_structure"], r["likelihood_family"]): r
                for r in data if r["inference_method"] == "mcmc"}
    assert len(expected) == 32
    seen, scenario = set(), None
    for line in source.splitlines():
        if " & " not in line or "[" not in line:
            continue
        cells = [v.strip() for v in line.removesuffix(r"\\").split(" & ")]
        if cells[0]:
            scenario = SCENARIOS[cells[0]]
        structure = "joint" if cells[1].startswith("MQ") else "independent"
        likelihood = "exAL" if "exAL" in cells[1] else "AL"
        key = (scenario, structure, likelihood)
        assert key not in seen, key
        seen.add(key)
        for cell, prefix in zip(cells[2:], ["", "path_"]):
            row = expected[key]
            values = [float(row[prefix + "posterior_score_" + suffix])
                      for suffix in ["mean", "q025", "q975"]]
            assert cell == f"{values[0]:.4f} [{values[1]:.4f}, {values[2]:.4f}]", key
    assert seen == set(expected)


def build_outputs(root: Path = ROOT) -> dict[str, str]:
    sources = authenticated_sources(root)
    out = {}
    specs = rows(sources, "glofas_search3_part1234_final_20261007_selected_specifications.csv")
    assert {r["component"] for r in specs} == {"reference", "discrepancy"}
    body = []
    for r in specs:
        assert r["D"] == "1" and r["standardize_inputs"] == "TRUE" and r["dlm_extension_enabled"] == "FALSE"
        body.append(" & ".join([r["component"].capitalize(), r["n_vector"], r["output_lag_max"],
                    r["covariate_lag_max"], f'{float(r["alpha"]):.2f}', f'{float(r["rho"]):.2f}',
                    r["washout"], r["seed"]]))
    out["glofas_specifications"] = tabular("@{}lrrrrrrr@{}",
        r"Component & Width & \(m\) & \(m_z\) & Leak & Radius & Washout & Seed", body)

    metrics = rows(sources, "glofas_same_family_20261103_family_metrics.csv")
    assert len(metrics) == 7 and {r["family"] for r in metrics} == set(FAMILIES)
    out["glofas_diagnostics"] = tabular("@{}lrr@{}", "Model & Mean check loss & Max. violation", [
        " & ".join([FAMILIES[r["family"]], f'{float(r["mean_check_loss"]):.4f}',
                    f'{float(r["max_positive_adjacent_violation_log1p"]):.4f}']) for r in metrics])

    costs = rows(sources, "glofas_same_family_20261103_convergence.csv")
    assert len(costs) == 16 and all(r["numerical_gates_pass"] == "TRUE" for r in costs)
    indexed = {(r["family"], float(r["tau"]) if r["tau"] else None): r for r in costs}
    assert len(indexed) == 16
    body = []
    for level in [.05, .20, .35, .50, .65, .80, .95]:
        values = [f"{level:.2f}"]
        for family in ["Independent AL", "Independent exAL"]:
            r = indexed[family, level]
            values.extend([r["iterations"], f'{float(r["wall_seconds"])/3600:.2f}'])
        body.append(" & ".join(values))
    body.append(r"\midrule")
    for family in ["MQ AL", "MQ exAL"]:
        r = indexed[family, None]
        assert r["terminal_consecutive_passes"] == "3"
        body.append(r"\multicolumn{3}{@{}l}{" + FAMILIES[family] + r"; outer sweeps, worker hours} & "
                    + r["outer_iterations"] + " & " + f'{float(r["wall_seconds"])/3600:.2f}')
    out["glofas_convergence"] = tabular("@{}lrrrr@{}",
        r"Level & AL iterations & AL hours & exAL iterations & exAL hours", body).replace(r"\midrule \\", r"\midrule")

    historical = sources["tables/glofas_reference_discrepancy_scores_display.tex"]
    removed = [line for line in historical.splitlines() if line.startswith("Discrepancy &")]
    assert len(removed) == 6 and all(line.count("---") == 3 for line in removed)
    body = [line for line in historical.splitlines() if line.startswith(("Reference only &", "Combined historical &"))]
    assert len(body) == 12
    # Retain every scored cell literally, dropping only the six all-dash rows.
    out["glofas_historical_scores"] = historical
    for line in removed:
        out["glofas_historical_scores"] = out["glofas_historical_scores"].replace(line + "\n", "")

    score_rows = rows(sources, "joint_qdesn_pure_desn_v2_forecast_score_summary.csv")
    score_table = sources["tables/qdesn_multiquantile_recursive_policy_display.tex"]
    validate_mq_scores(score_table, score_rows)
    out["mq_scores"] = score_table.replace(r"\end{table}",
        r"\label{tab:joint-qdesn-pure-desn-v2-score}" + "\n" + r"\end{table}")
    mcmc = [r for r in score_rows if r["inference_method"] == "mcmc"]
    assert len(mcmc) == 32 and all(r["score_stability_status"] == "pass" for r in mcmc)
    body = []
    for title, column, digits in [(r"Rank-normalized \(\widehat R\)", "score_rank_rhat", 6),
            (r"Folded \(\widehat R\)", "score_folded_rhat", 6),
            ("Bulk ESS", "score_bulk_ess", 3), ("Tail ESS", "score_tail_ess", 3)]:
        values = [float(r[column]) for r in mcmc]
        body.append(f"{title} & {min(values):.{digits}f} & {max(values):.{digits}f}")
    out["score_diagnostics"] = tabular("@{}lrr@{}", "Score-sequence diagnostic & Minimum & Maximum", body)

    wrappers = {
        "ind_forecast_mae": ("independent_train500_eval300_mcmc_mae_figure_v1.tex", [
            r"MCMC forecast quantile-path MAE over 300 targets (10 origins). Points and equal-tailed 95\% intervals summarize draw-wise aggregate recovery error; lower is better. Navy circles denote AL and muted-brick triangles exAL; filled symbols denote Q--DESN and open symbols dynamic linear comparators. Panels identify family and level. The dashed line marks exact recovery. Corresponding 500-target panels use the same horizontal limits; intervals depend on the model-specific draw construction."]),
        "ind_fit_rmse": ("qdesn_single_quantile_mcmc_fit_figure_display.tex", [
            r"MCMC fitting-sample quantile-path RMSE: means and equal-tailed 95\% intervals conditional on each criterion-specific specification. Colours and symbols follow Figure~\ref{fig:simulation-500obs-mcmc-forecast-mae-intervals}; panels have separate horizontal scales. The dashed line marks exact recovery."]),
        "ind_sensitivity": ("independent_train500_eval500_mcmc_figures_v1.tex", [
            r"MCMC forecast quantile-path MAE over 500 targets (17 origins): draw-wise means and equal-tailed 95\% intervals. The final origin contributes 20 leads, others 30. Colours and symbols follow Figure~\ref{fig:simulation-500obs-mcmc-forecast-mae-intervals}; the dashed line marks exact recovery.",
            r"MCMC forecast check loss over the same 500 targets: draw-wise means and equal-tailed 95\% intervals. Colours and symbols follow Figure~\ref{fig:simulation-500obs-mcmc-forecast-mae-intervals}. The dashed line marks population expected check loss at the true conditional quantile, not a finite-sample lower bound."]),
        "ind_frequencies": ("independent_forecast_calibration_figure_v1.tex", [
            r"Empirical quantile frequencies over 300 and 500 targets using the check-loss specifications and pooled posterior-median forecasts. Each level uses its quantile-centred response series. Colours and symbols follow Figure~\ref{fig:simulation-500obs-mcmc-forecast-mae-intervals}; the dashed diagonal is nominal. No sampling confidence bands are shown."]),
        "mq_fit_rmse": ("qdesn_multiquantile_fit_figure_display.tex", [
            r"Multiquantile fitting-sample recovery: RMSE of monotone posterior-mean grids, not posterior interval summaries. Annotations \(c\) give raw adjacent-level crossing percentages before projection; Q--DESN fits levels independently and MQ--DESN links their coefficients."]),
    }
    for role, (name, captions) in wrappers.items():
        original = sources["tables/" + name]
        updated = replace_captions(original, captions)
        assert re.findall(r"\\includegraphics[^\n]+", original) == re.findall(r"\\includegraphics[^\n]+", updated)
        assert re.findall(r"\\label\{[^}]+\}", original) == re.findall(r"\\label\{[^}]+\}", updated)
        out[role] = updated
    result = {PREFIX + name + ".tex": COMMENT + value for name, value in out.items()}
    assert set(result) == set(OUTPUTS)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check exact derivatives; do not write")
    args = parser.parse_args()
    outputs = build_outputs()
    for name, value in outputs.items():
        destination = ROOT / name
        if args.check:
            if not destination.exists() or destination.read_text() != value:
                raise SystemExit(f"Presentation derivative differs: {name}")
        else:
            destination.write_text(value)
    print(f"{'Checked' if args.check else 'Built'} {len(outputs)} bounded presentation derivatives; frozen inputs authenticated.")


if __name__ == "__main__":
    main()
