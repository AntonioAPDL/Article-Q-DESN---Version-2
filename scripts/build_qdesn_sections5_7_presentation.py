#!/usr/bin/env python3
"""Bounded editorial derivatives of frozen simulation/application displays.

Only captions, campaign labels, permitted administrative table columns and
ordinary lettering change. Scientific fits, scores, numerical inputs, original
assets and their manifests are never rewritten. PyMuPDF 1.26.5 is required only
for generation; the companion checker uses the standard library and pdftotext.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import tempfile

MANIFEST = "tables/qdesn_sections5_7_presentation_manifest.json"
BUILDER = "scripts/build_qdesn_sections5_7_presentation.py"
CHECKER = "scripts/check_qdesn_sections5_7_presentation.py"
SOURCE_PINS = {
    "tables/glofas_search3_mq_prior_settings.tex": "6a0ab95edfae4fb678822e40d023104eda4eb7e2dfccf9b0137ebba5316997a7",
    "tables/glofas_search3_mq_calibration.tex": "933b2f0c7ba648165e9951e7767231eec655e70d86270fc5f9b7dd7130bf571b",
    "tables/glofas_search3_mq_convergence.tex": "9e07d56c1c2c8b250ce138a55029957edf88fb851c3cc35173e5289a445aef45",
    "tables/joint_qdesn_pure_desn_v2_mq_score_table.tex": "68cf44c1b0ec0a3592a41677f2a9e26f8856b9db58fea8d208a42481218b875a",
    "tables/joint_qdesn_pure_desn_v2_mq_secondary_score_table.tex": "0191ce3255d350c85a9669018ad830f81f9d3c8b9291a95a40a32357423b35ce",
    "tables/joint_qdesn_pure_desn_v2_mq_recursive_policy_table.tex": "60bc21ca99d14ed8289dc6397536d28bcfedcae94e1401934340c34113258c1f",
    "tables/joint_qdesn_pure_desn_v2_mq_vb_score_table.tex": "438062b3450bf0d1bb34c255604e3622038dfda6cc59708c7cbf60c6a50ba125",
    "tables/joint_qdesn_pure_desn_v2_mq_contrast_table.tex": "a021de30bdd610276984bb939ed3ac4e7fc5eb821ffc7d96c4802db6ba75e1f1",
    "tables/joint_qdesn_pure_desn_v2_mq_crossing_table.tex": "c5aeb10a1f1c001daa4d1b182915729b8de7bc0d2835d9dc80492f5afabb3ede",
    "tables/joint_qdesn_pure_desn_v2_mq_oracle_recovery_table.tex": "246bf4996871ed8116c36875dd6f92baab86005353a320ce61cafa69c1719c94",
    "tables/glofas_search3_mq_main_scores.tex": "70ca70cae606a95a94ee0ff57f67c68e7b10349447b867599ce9ca4318ea7d14",
    "tables/glofas_search3_mq_part123_scores.tex": "18631881207c538ce2894159b73d028b98af2e5a10a57ab2e37e47ce10c4bd3b",
    "tables/glofas_search3_mq_part123_prior_settings.tex": "ecd3fd7016953d4a0e4cae6e2282358b6fc09abdd63b454d9052e94d4f2a4196",
    "tables/glofas_search3_part1234_final_20261007_selected_specifications.tex": "63626f0c8155544f910181567a77358626a4d7c59cf36ba075cb8e2546502906",
    "tables/pricefm_r98_global_aql_comparison.tex": "aed9fa10da6383d31f256c108d2530384ec57c275a54bc2d6f55754d287473a2",
    "tables/qdesn_pro_review_mcmc_forecast_figures.tex": "f72adec502255793e735224b4dae5c9ce5f64d821dadf7818cde80192604a4ce",
    "tables/qdesn_pro_review_mcmc_fit_figure.tex": "b97d6a39122ea1b8c8873b5bcc7b145dfdd5aeb096088dccfb0ecc9a4b70e45a",
    "tables/qdesn_pro_review_vb_fit_figure.tex": "1ae7b9a29f27135217587a57c4895b7cf3b7f5dad2032211e7567ede335dbf2f",
    "tables/joint_qdesn_pure_desn_v2_mq_forecast_figure.tex": "696117474b4ed88e51f6baa90db9196dcd4dc80e48dc8fe23a2680f682329457",
    "tables/joint_qdesn_pure_desn_v2_mq_fit_figure.tex": "251a4cf68d8fee34447bf1d2aabee699148ac701cba5ddebd487abca8ea34e50",
    "tables/joint_qdesn_pure_desn_v2_mq_protocol.tex": "6023f8595d255b3a7568a8e582c943efcaf16fa3f00fa31b3608b92a7110c77f",
    "figures/pricefm_application/pricefm_r98_region_aql_comparison.pdf": "870f43f594b86e607a93479568deb4943016bb201a870d2a8be9a3388e720413",
    "figures/glofas_application/glofas_search3_mq_review_20261013_calibration.pdf": "77feecd217761727c803c22f93404ff5ff5cc855560de4a92f9d3ebbeb2fb0fb",
    "figures/glofas_application/glofas_search3_mq_review_20261013_convergence.pdf": "c3e881e20588e6d67c85fcef1072a3b2885a2129f7c3039af0213e3e8eaac6e6",
    "figures/glofas_application/glofas_search3_mq_review_20261013_part1.pdf": "ea7a0ea3084e924a0b2334a83983df8f842ceb0fabd92d518b1cca5a79213705",
    "figures/glofas_application/glofas_search3_mq_review_20261013_part2.pdf": "46f744affdec69fc62a49e34ffc8d8912f6f58a10d2dfbc0267b9f8911e0ab8f",
    "figures/glofas_application/glofas_search3_mq_review_20261013_part3.pdf": "fd0fb8c0021d4892ea2881c232f83d5ef4fe1749b141dbd6aa6294be2373bb7a",
    "figures/glofas_application/glofas_search3_mq_review_20261013_part4.pdf": "ef42ea26067b4cfe01061320487a38a68f95bb616d2a26a35f5efd3fee5ba20e",
    "tables/glofas_search3_part1234_final_20261007_part4_scores.csv": "c15d21cda11c8c8a89742b32b8a0c07b85851176dac29c30076941e32c52c998",
    "tables/glofas_mq_presentation_manifest.json": "3ed5f035d6b6efe81d759b92903f62841f54bc448d6272aba193d80fbef26e48",
    "tables/joint_qdesn_mq_presentation_manifest.json": "4394aeac8e92f9ff50ed5697d552f021a1b59d5342a3807d1c5a20c4e05dcb52",
    "tables/pricefm_r98_article_projection_manifest.json": "1d6ea4f4f5d73617f45e9ca02940114a95d140debdf4c884b1a261999fee89c5",
    "tables/qdesn_pro_review_presentation_manifest.json": "648ef97d91adceaa17cf5958dcc515520ebe31ae65ca7fc1d58de5ca960a8e9e",
    "tables/glofas_figure4_common_window_manifest.json": "af9ef008903f5fc571803d75c322ada07ca3d691a2ff9cc83a3b5041012992f8",
    "figures/glofas_application/glofas_search3_part4_common_window_three_panel_review.pdf": "ff6e818e317a31b211be6ee247e45aa0826d42cbaee141cfae6902d8143f021f",
    "scripts/build_glofas_review_figures.py": "e55d0d93563e0f6f01fea9237be65b1c47fa046994be5a987e8b09877753df73",
}
TABLE_OUTPUTS = {
    "glofas_issued_priors": ("tables/glofas_search3_mq_prior_settings.tex", "tables/glofas_issued_prior_settings_display.tex"),
    "glofas_frequencies": ("tables/glofas_search3_mq_calibration.tex", "tables/glofas_empirical_quantile_frequencies_display.tex"),
    "glofas_stopping": ("tables/glofas_search3_mq_convergence.tex", "tables/glofas_variational_stopping_display.tex"),
    "glofas_main": ("tables/glofas_search3_mq_main_scores.tex", "tables/glofas_forecast_correction_main_scores_display.tex"),
    "glofas_components": ("tables/glofas_search3_mq_part123_scores.tex", "tables/glofas_reference_discrepancy_scores_display.tex"),
    "glofas_component_priors": ("tables/glofas_search3_mq_part123_prior_settings.tex", "tables/glofas_reference_discrepancy_priors_display.tex"),
    "glofas_specifications": ("tables/glofas_search3_part1234_final_20261007_selected_specifications.tex", "tables/glofas_selected_specifications_display.tex"),
    "pricefm_global": ("tables/pricefm_r98_global_aql_comparison.tex", "tables/pricefm_regional_comparison_display.tex"),
    "mq_design": ("tables/joint_qdesn_pure_desn_v2_mq_protocol.tex", "tables/qdesn_multiquantile_design_display.tex"),
}
MQ_TABLE_CAPTIONS = {
    "score": r"Oracle finite-grid \(\aCRPS\) in the multiquantile study. Means, medians, and equal-tailed 95\% limits summarize posterior coefficient and intercept uncertainty conditional on each model's averaged future predictor matrix. The mean-grid score evaluates the projected posterior-mean quantile grid and differs from the posterior mean of the score. Boldface identifies numerical minima; all winner and runner-up marginal intervals overlap. Q--DESN fits levels independently; MQ--DESN estimates their coefficients jointly.",
    "secondary_score": r"Finite-grid \(\aCRPS\) against realized observations. Posterior mean scores condition on each model's averaged future predictors; the mean-grid score evaluates its projected posterior-mean quantile grid. These scores are secondary to oracle \(\aCRPS\). Q--DESN fits levels independently; MQ--DESN estimates their coefficients jointly.",
    "recursive_policy": r"Oracle finite-grid \(\aCRPS\) under two treatments of future predictors. Entries are posterior means and equal-tailed 95\% intervals. Averaged-predictor scores condition on each model's mean future predictor matrix; trajectory-specific scores use each draw's recursively generated predictors. The intervals summarize different propagated uncertainties, not future-response interval coverage. Q--DESN fits levels independently; MQ--DESN estimates their coefficients jointly.",
    "vb_score": r"Variational oracle finite-grid \(\aCRPS\). Means, medians, and approximate equal-tailed 95\% limits condition on fixed intercept estimates and each model's averaged future predictor matrix; intercept uncertainty is not included. The mean-grid score evaluates the projected variational-mean quantile grid. Q--DESN fits levels independently; MQ--DESN estimates their coefficients jointly.",
    "contrast": r"MQ--DESN minus Q--DESN differences in oracle finite-grid \(\aCRPS\), summarized by posterior means and equal-tailed 95\% intervals. Positive differences favor independent estimation. Score draws from separately fitted models are paired by a fixed index rule, and these descriptive intervals depend on that pairing. The two asymmetric-tail intervals favor MQ--DESN; the other fourteen include zero.",
    "crossing": r"Raw adjacent-level crossing percentages and monotone adjustments. The first two columns describe posterior-mean grids; the third averages the eight mechanism-specific crossing percentages across posterior draws with equal weight. Each model has 24,000 fitting and 47,520 forecast comparisons. AL models use 3,750 draws; exAL models use 7,500 for Laplace and 3,750 otherwise. Adjustment magnitudes are on the response scale. Every projected grid is ordered. Q--DESN fits levels independently; MQ--DESN estimates their coefficients jointly.",
    "oracle_recovery": r"Recovery of known conditional quantile paths by projected posterior-mean grids. MAE and RMSE measure quantile-path recovery, separately from scores against observations. Fitting-sample entries are point summaries without posterior intervals. Q--DESN fits levels independently; MQ--DESN estimates their coefficients jointly.",
}
for _suffix in MQ_TABLE_CAPTIONS:
    TABLE_OUTPUTS["mq_" + _suffix] = ("tables/joint_qdesn_pure_desn_v2_mq_" + _suffix + "_table.tex",
                                      "tables/qdesn_multiquantile_" + _suffix + "_display.tex")
WRAPPER_OUTPUTS = {
    "independent_forecast": ("tables/qdesn_pro_review_mcmc_forecast_figures.tex", "tables/qdesn_single_quantile_forecast_figures_display.tex"),
    "independent_mcmc_fit": ("tables/qdesn_pro_review_mcmc_fit_figure.tex", "tables/qdesn_single_quantile_mcmc_fit_figure_display.tex"),
    "independent_vb_fit": ("tables/qdesn_pro_review_vb_fit_figure.tex", "tables/qdesn_single_quantile_vb_fit_figure_display.tex"),
    "mq_forecast": ("tables/joint_qdesn_pure_desn_v2_mq_forecast_figure.tex", "tables/qdesn_multiquantile_forecast_figure_display.tex"),
    "mq_fit": ("tables/joint_qdesn_pure_desn_v2_mq_fit_figure.tex", "tables/qdesn_multiquantile_fit_figure_display.tex"),
}
PDF_ROLES = {"part1": "reference", "part2": "discrepancy", "part3": "combined", "part4": "issued", "convergence": "convergence", "calibration": "calibration"}
PDF_OUTPUTS = {
    "glofas_" + role: ("figures/glofas_application/glofas_search3_mq_review_20261013_" + stage + ".pdf",
                       "figures/glofas_application/glofas_editorial_20261013_" + role + ".pdf")
    for stage, role in PDF_ROLES.items()
}
PDF_OUTPUTS["pricefm_region"] = ("figures/pricefm_application/pricefm_r98_region_aql_comparison.pdf", "figures/pricefm_application/pricefm_regional_aql_editorial_20261013.pdf")
PDF_OUTPUTS["glofas_common_window"] = ("figures/glofas_application/glofas_search3_part4_common_window_three_panel_review.pdf", "figures/glofas_application/glofas_common_window_statistical_labels_20261019.pdf")
PRICEFM_FROZEN_ROLE_PINS = {
    "pricefm_global": "2572a3f1aafe544175caec759f706de19d997a22084b92f742bc227c5a048193",
    "pricefm_region": "cd39567f25b9eaba53ed1540ced6d3f6352bfd7c8f8c3cba7f8a79e55f31e1fd",
}
PDF_LABELS = {
    "Part 1: univariate USGS forecast": "Reference-process forecasts",
    "Part 2: retrospective GloFAS discrepancy forecast": "Historical discrepancy extrapolation",
    "Part 3: joint historical USGS forecast": "Combined historical-model forecasts",
    "Part 4: issued-ensemble latent-path experiment": "Issued-ensemble forecast correction",
    "Part 4 corrected MQ-DESN convergence": "MQ-DESN variational stopping criteria",
    "Part 4 issued-window quantile calibration": "Issued-window empirical quantile frequencies",
    "R98 Q-DESN": "Q-DESN",
    "R92 historical": "Historical Q-DESN",
    "Last 30 observed dates and 28 issued horizons. MQ-DESN (AL) and MQ-DESN (exAL) use the strict corrected":
        "Last 30 observed dates and 28 issued horizons; all models use the common forecast window.",
    "terminal fits.": "",
    "Filled terminal points indicate the three consecutive full-state passes required for release.":
        "Filled points mark three consecutive complete iterations meeting the stopping criteria.",
    "Full-state pass": "Stopping criteria",
    "FALSE": "Not met",
    "TRUE": "Met",
    "Calibration is descriptive on the protected 28-day scoring window and is not a tuning criterion.":
        "Empirical quantile frequencies over the 28-day issued forecast window.",
    "Last 30 observed dates and the 30-day recursive forecast; magenta dashed is withheld USGS truth.":
        "Last 30 observed dates and the 30-day recursive forecast; magenta dashed marks withheld USGS observations.",
}
GAUSSIAN_LABELS = {"Normal Ridge": "Gaussian DESN (ridge)", "Normal RHS/VB": "Gaussian DESN (RHS)"}
ROLE_PDF_LABELS = {
    "glofas_calibration": {"Empirical coverage": "Empirical frequency", "Nominal quantile": "Probability level"},
    "glofas_discrepancy": {"log(1 + flow)": "GloFAS-USGS discrepancy", "Normal and raw": "Gaussian DESN"},
    "glofas_reference": {"Normal and raw": "Gaussian DESN"},
    "glofas_combined": {"Normal and raw": "Gaussian DESN"},
    "glofas_issued": {"Normal and raw": "Gaussian DESN and raw GloFAS"},
    "glofas_common_window": {"(b) Independent AL": "(b) Q-DESN (AL)", "(c) Normal Ridge": "(c) Gaussian DESN (ridge)"},
}
ROLE_LABELS = {"Part 1": "Reference only", "Part 2": "Discrepancy", "Part 3": "Combined historical"}
MAIN_OVERRIDE = "tables/qdesn_sections5_7_main_display_overrides.tex"
SUPP_OVERRIDE = "tables/qdesn_sections5_7_supp_display_overrides.tex"
MAIN_ALIASES = {"GlofasApplicationCurrentScoreTable": TABLE_OUTPUTS["glofas_main"][1],
                "GlofasApplicationCurrentForecastWindowFigure": PDF_OUTPUTS["glofas_common_window"][1]}
SUPP_ALIASES = {
    "GlofasApplicationCurrentPartOneFigure": PDF_OUTPUTS["glofas_reference"][1],
    "GlofasApplicationCurrentPartTwoFigure": PDF_OUTPUTS["glofas_discrepancy"][1],
    "GlofasApplicationCurrentPartThreeFigure": PDF_OUTPUTS["glofas_combined"][1],
    "GlofasApplicationCurrentFullComparisonFigure": PDF_OUTPUTS["glofas_issued"][1],
    "GlofasApplicationCurrentConvergenceFigure": PDF_OUTPUTS["glofas_convergence"][1],
    "GlofasApplicationCurrentCalibrationFigure": PDF_OUTPUTS["glofas_calibration"][1],
    "GlofasApplicationCurrentSupplementScoreTable": TABLE_OUTPUTS["glofas_components"][1],
    "GlofasApplicationCurrentPartOneTwoThreePriorSettingsTable": TABLE_OUTPUTS["glofas_component_priors"][1],
    "GlofasApplicationCurrentSpecificationsTable": TABLE_OUTPUTS["glofas_specifications"][1],
    "GlofasApplicationCurrentCalibrationTable": TABLE_OUTPUTS["glofas_frequencies"][1],
    "GlofasApplicationCurrentConvergenceTable": TABLE_OUTPUTS["glofas_stopping"][1],
    "GlofasApplicationCurrentPriorSettingsTable": TABLE_OUTPUTS["glofas_issued_priors"][1],
    "PricefmCurrentGlobalComparisonTable": TABLE_OUTPUTS["pricefm_global"][1],
    "PricefmCurrentRegionFigure": PDF_OUTPUTS["pricefm_region"][1],
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def table_rows(text: str) -> list[list[str]]:
    body = text.split(r"\midrule", 1)[1].split(r"\bottomrule", 1)[0]
    return [[cell.strip() for cell in line.strip().removesuffix(r"\\").split(" & ")]
            for line in body.splitlines() if " & " in line]


def gaussian_names(text: str) -> str:
    for old, new in GAUSSIAN_LABELS.items():
        text = text.replace(old, new)
    return text


def display_table(role: str, source: str) -> str:
    # These exact operations are independently checked in the companion script.
    if role == "glofas_main":
        lines = source.splitlines()
        result = []
        for line in lines:
            if " & " in line:
                cells = line.removesuffix(r"\\").strip().split(" & ")
                assert len(cells) == 5, "Expected the original five-column main table."
                line = " & ".join(cells[:4]) + r" \\"
            line = line.replace("lrrrr@{}", "lrrr@{}")
            result.append(line)
        return gaussian_names("\n".join(result) + "\n")
    text = "\n".join(line for line in source.splitlines() if not line.startswith("%")) + "\n"
    if role in {"glofas_components", "glofas_component_priors"}:
        text = text.replace("Part & Family", "Component & Model")
        for old, new in ROLE_LABELS.items():
            text = text.replace(old, new)
        if role == "glofas_component_priors":
            text = text.replace("Component & Model & Component", "Historical model & Model & Process")
            text = text.replace(r"Slab & $\tau$ posterior range", r"Slab or ridge variance & Effective global scale")
            text = text.replace(r"Ridge & Ridge: $\tau^2=10^4$", r"$\kappa_\beta^2=10^4$ & ---")
        return gaussian_names(text)
    if role == "glofas_frequencies":
        text = re.sub(r"\$q_\{([^}]+)\}\$", r"$p=\1$", text)
        return gaussian_names(text.replace("Family &", "Model &"))
    if role == "glofas_stopping":
        return text.replace("Outer sweep", "Outer iteration").replace("Full-state passes", "Consecutive complete iterations").replace("Strict convergence", "Stopping criteria met").replace("Family &", "Model &")
    if role == "glofas_issued_priors":
        return gaussian_names(text.replace("Family &", "Model &"))
    if role == "glofas_specifications":
        result = []
        for line in text.splitlines():
            if " & " in line:
                cells = line.removesuffix(r"\\").strip().split(" & ")
                assert len(cells) == 10
                line = " & ".join(cells[:1] + cells[2:]) + r" \\"
            line = line.replace("llrrrrrrrl", "lrrrrrrrl").replace("Search slab", "Screening slab")
            result.append(line)
        return "\n".join(result) + "\n"
    if role == "mq_design":
        for old, new in {
            "990 rows per setting": "990 origin--horizon pairs per setting",
            "Five chains per model cell": "Five chains per model and mechanism",
            "Feature design &": "Reservoir specification &",
            "separate source realizations": "separately simulated series",
            "The readout contains an intercept and all reservoir-layer states; response lags enter the reservoir only.": "The regression uses an intercept and the states from all reservoir layers.",
            "each model's averaged recursive design": "each model's averaged future predictor matrix",
            "VB intervals additionally hold intercepts fixed.": "VB intervals additionally condition on fixed intercept estimates.",
            "All 64 method--model comparisons are finite, and all 32 MCMC comparisons satisfy the score-functional criteria.": "Score calculations are finite for all 64 method--model comparisons; the 32 MCMC comparisons meet the stated score-stability criteria.",
            "Design and computation for the reservoir-only multi-quantile comparison.": "Design and computation for the multiquantile study.",
        }.items():
            assert old in text
            text = text.replace(old, new)
        return text
    if role.startswith("mq_"):
        return replace_commands(text, "caption", [MQ_TABLE_CAPTIONS[role.removeprefix("mq_")]])
    assert role == "pricefm_global"
    for old, new in {
        "Surface &": "Comparison &",
        "Q--DESN (R98 region-frozen)": "Q--DESN (fixed regional specification)",
        "PriceFM (cached direct replay)": "PriceFM",
        "Q--DESN (R92; historical sensitivity)": "Q--DESN (historical case-specific selection)",
    }.items():
        assert old in text
        text = text.replace(old, new)
    return text


CAPTIONS = {
    "independent_forecast": [
        r"MCMC forecast quantile-path mean absolute error (MAE) in the single-quantile study. Points and equal-tailed 95\% intervals summarize the draw-wise criterion averaged over the forecast pairs. Lower values are better. Navy circles identify \(\AL\) models and muted-brick triangles \(\exAL\) models; filled symbols denote Q--DESN and open symbols their dynamic linear comparators. Panels A--I identify the observation-error family and probability level, with separate horizontal scales. The dashed line marks exact recovery. DESN specifications are criterion-specific; their selection and the forecast-draw construction are documented in the supplement.",
        r"MCMC forecast check loss in the single-quantile study. Points and equal-tailed 95\% intervals summarize the draw-wise criterion averaged over the forecast pairs; lower values are better. Model encodings and panels are as in Figure~\ref{fig:simulation-500obs-mcmc-forecast-mae-intervals}. The dashed line marks the population expected check loss at the true conditional quantile. The supplement documents criterion-specific selection and forecast-draw construction.",
    ],
    "independent_mcmc_fit": [r"MCMC fitting-sample recovery in the single-quantile study. Points and equal-tailed 95\% intervals summarize draw-wise quantile-path root mean squared error (RMSE); lower values are better. Navy circles identify \(\AL\) models and muted-brick triangles \(\exAL\) models; filled symbols denote Q--DESN and open symbols their dynamic linear comparators. Panels A--I identify the observation-error family and probability level, with separate horizontal scales. The dashed line marks exact recovery. The summaries condition on the simulated series and the criterion-specific specification."],
    "independent_vb_fit": [r"Variational fitting-sample recovery in the single-quantile study. Points and approximate equal-tailed 95\% intervals summarize quantile-path RMSE under the variational fit; lower values are better. Model encodings follow Figure~\ref{fig:simulation-500obs-mcmc-fit-rmse-intervals}. Panels A--I identify the observation-error family and probability level, with separate horizontal scales. The dashed line marks exact recovery. The summaries condition on the simulated series and the criterion-specific specification."],
    "mq_forecast": [r"Oracle finite-grid \(\aCRPS\) in the multiquantile study. Points are posterior means and segments are equal-tailed 95\% intervals for the score averaged over the common forecast pairs, conditional on each model's averaged future predictors. Lower scores are better. Annotations \(c\) give raw adjacent-level crossing percentages for posterior-mean forecast grids. Q--DESN fits levels independently; MQ--DESN estimates their coefficients jointly. The scored grids use the monotone transformation specified in the supplement."],
    "mq_fit": [r"Fitting-sample recovery of known conditional quantile paths in the multiquantile study. Points give the RMSE of monotone posterior-mean grids, not posterior interval summaries. Annotations \(c\) give raw adjacent-level crossing percentages before projection. Q--DESN fits levels independently; MQ--DESN estimates their coefficients jointly."],
}


def replace_commands(text: str, command: str, replacements: list[str]) -> str:
    marker = "\\" + command + "{"
    pos = 0
    for replacement in replacements:
        at = text.index(marker, pos)
        start = at + len(marker)
        depth, end = 1, start
        while depth:
            if text[end] == "{" and (end == 0 or text[end - 1] != "\\"):
                depth += 1
            elif text[end] == "}" and text[end - 1] != "\\":
                depth -= 1
            end += 1
        text = text[:start] + replacement + text[end - 1:]
        pos = start + len(replacement) + 1
    assert marker not in text[pos:], "Unexpected additional caption command."
    return text


def display_wrapper(role: str, source: str) -> str:
    text = replace_commands(source, "caption", CAPTIONS[role])
    return text.replace("innovation families", "observation-error families")


def override_text(aliases: dict[str, str]) -> str:
    return "% Presentation-only selections; scientific aliases and originals are preserved.\n" + "\n".join(
        "\\renewcommand{\\" + name + "}{" + path + "}" for name, path in aliases.items()) + "\n"


def text_tokens(value: str) -> Counter:
    return Counter(value.split())


def numerical_tokens(value: str) -> Counter:
    return Counter(re.findall(r"(?<![A-Za-z])[+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?", value))


def labels_for_role(role: str) -> dict[str, str]:
    labels = dict(PDF_LABELS)
    if role.startswith("glofas_"):
        labels.update(GAUSSIAN_LABELS)
        labels.update(ROLE_PDF_LABELS.get(role, {}))
    return labels


def pdf_display(root: Path, output_root: Path, role: str, source: str, destination: str) -> dict:
    import fitz
    assert fitz.VersionBind == "1.26.5", "Use the pinned PyMuPDF generation environment."
    renderer_path = root / "scripts/build_glofas_review_figures.py"
    spec = importlib.util.spec_from_file_location("frozen_glofas_lettering", renderer_path)
    renderer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(renderer)
    renderer.verify_environment()
    doc = fitz.open(root / source)
    assert len(doc) == 1 and not doc[0].get_images(full=True)
    original_text = doc[0].get_text()
    original_rect = list(doc[0].rect)
    original_drawings = doc[0].get_drawings()
    removed_glyph_paths = 0
    if role == "pricefm_region":
        # Matplotlib's Type 3 glyph outlines also appear in get_drawings().
        # Verify the surviving paths are an unchanged subsequence and every
        # removed path is a black filled glyph wholly inside an original text
        # box; no scientific marks may be removed under this exception.
        spans = renderer.texts(doc[0])
        for span in spans:
            doc[0].add_redact_annot(fitz.Rect(span["bbox"]), fill=False, cross_out=False)
        doc[0].apply_redactions(images=0, graphics=0, text=0)
        after = doc[0].get_drawings()
        at = 0
        for before in original_drawings:
            if at < len(after) and renderer.canon(before) == renderer.canon(after[at]):
                at += 1
            else:
                assert before["type"] == "f" and before["fill"] == (0.0, 0.0, 0.0)
                # Four authenticated Type 3 glyphs have horizontal ink
                # bearings up to 0.21001bp outside the extracted text box.
                assert any(before["rect"] in fitz.Rect(span["bbox"]) + (-.25, -.25, .25, .25) for span in spans), \
                    "Redaction removed a non-glyph vector mark."
                removed_glyph_paths += 1
        assert at == len(after) and removed_glyph_paths == 220, "Unexpected Type 3 glyph inventory."
        original_drawings = after
        stripped_hash = renderer.drawing_hash(doc[0])
        assert not doc[0].get_text().strip()
    else:
        spans, stripped_hash = renderer.strip_text(doc)
    if role == "pricefm_region":
        proof = fitz.open()
        page = proof.new_page(width=468, height=original_rect[3])
        page.show_pdf_page(fitz.Rect(18, 0, 468, original_rect[3]), doc, 0, keep_proportion=False)
        scale_x, offset_x = 450 / original_rect[2], 18
    else:
        proof, page = doc, doc[0]
        scale_x, offset_x = 1, 0
    renderer.install_fonts(page)
    expected_words, exact_mapping = Counter(), {}
    for span in spans:
        old = span["text"]
        new = labels_for_role(role).get(old, old)
        if new != old:
            exact_mapping[old] = new
        expected_words.update(new.split())
        if not new:
            continue
        x, y = span["origin"]
        x = offset_x + x * scale_x
        size = 9 if role == "pricefm_region" else span["size"]
        bold = "Bold" in span["font"]
        fontname = "bold" if bold else "regular"
        font = fitz.Font(fontfile=renderer.BOLD if bold else renderer.FONT)
        if span["dir"] == (0.0, -1.0):
            if role == "pricefm_region":
                x = 10
            page.insert_text((x, y), new, fontname=fontname, fontsize=size, rotate=90)
            continue
        assert span["dir"] == (1.0, 0.0)
        if role.startswith("glofas_") and old in GAUSSIAN_LABELS:
            # Preserve the scientific legend strokes and readable type size.
            # The expanded statistical model name needs two text lines to
            # avoid intruding into the neighboring legend column.
            page.insert_text((x, y - 3), "Gaussian DESN", fontname=fontname, fontsize=size)
            page.insert_text((x, y + 7), new.removeprefix("Gaussian DESN "), fontname=fontname, fontsize=size)
            continue
        if role == "pricefm_region":
            if old == "Region":
                raise AssertionError("Expected a rotated Region label.")
            if old in {"PriceFM", "R98 Q-DESN", "R92 historical"}:
                if old == "R92 historical":
                    page.insert_text((x, y - 6), "Historical", fontname=fontname, fontsize=size)
                    page.insert_text((x, y + 4), "Q-DESN", fontname=fontname, fontsize=size)
                    continue
            elif re.fullmatch(r"[A-Z]{2}(?:_[A-Z0-9]+)?", old):
                x = 56 - font.text_length(new, fontsize=size)
            elif re.fullmatch(r"\d+", old):
                center = offset_x + (span["bbox"][0] + span["bbox"][2]) * scale_x / 2
                x = center - font.text_length(new, fontsize=size) / 2
            elif old.startswith("Mean AQL"):
                x = (468 - font.text_length(new, fontsize=size)) / 2
        assert x >= 0 and x + font.text_length(new, fontsize=size) <= page.rect.width + .02, \
            "Mapped label exceeds page width: " + new
        page.insert_text((x, y), new, fontname=fontname, fontsize=size)
    if role != "pricefm_region":
        assert renderer.drawing_hash(page) == stripped_hash, "GloFAS vector paths changed."
    output_drawings = page.get_drawings()
    assert len(output_drawings) == len(original_drawings), "Vector path count changed."
    for original, output in zip(original_drawings, output_drawings):
        before = original["rect"]
        expected = fitz.Rect(offset_x + before.x0 * scale_x, before.y0,
                             offset_x + before.x1 * scale_x, before.y1)
        assert max(abs(a - b) for a, b in zip(expected, output["rect"])) < .002, "Scientific vector coordinates changed."
        assert original["color"] == output["color"] and original["fill"] == output["fill"], "Scientific colors changed."
    target = output_root / destination
    target.parent.mkdir(parents=True, exist_ok=True)
    proof.set_metadata({"producer": "PyMuPDF " + fitz.VersionBind, "title": "Reader-facing forecast comparison"})
    proof.save(target, garbage=4, deflate=True, no_new_id=True)
    with fitz.open(target) as saved:
        text = saved[0].get_text()
        assert text_tokens(text) == expected_words, "Mapped PDF wording changed."
        mapped_source = "\n".join(labels_for_role(role).get(s["text"], s["text"]) for s in spans)
        assert numerical_tokens(text) == numerical_tokens(mapped_source), "Numerical PDF content changed beyond explicit label mappings."
        assert not re.search(r"\b(?:Part [1-4]|R9[28]|Search III)\b", text)
        final_spans = renderer.texts(saved[0])
        assert all(fitz.Rect(s["bbox"]) in saved[0].rect + (-.1, -.1, .1, .1) for s in final_spans), "Clipped ordinary label."
        minimum = min(s["size"] for s in final_spans)
        effective = minimum * (.98 * 468 * 72 / 72.27 / saved[0].rect.width if role.startswith("glofas") else 468 / saved[0].rect.width)
        assert effective >= 8, "Ordinary inserted lettering is smaller than 8bp."
        assert not saved[0].get_images(full=True)
        return {
            "role": role, "file": destination, "sha256": sha(target), "source": source,
            "source_sha256": sha(root / source), "permitted_operation": "exact label mapping and documented affine vector composition",
            "exact_span_label_mapping": exact_mapping, "expected_text_tokens": sorted(expected_words.items()),
            "numeric_tokens": sorted(numerical_tokens(text).items()), "vector_path_count": len(output_drawings),
            "vector_sha256": renderer.drawing_hash(saved[0]), "source_vector_sha256": stripped_hash,
            "removed_type3_text_glyph_paths": removed_glyph_paths,
            "affine_x_scale": scale_x, "affine_x_offset": offset_x,
            "minimum_effective_label_bp": effective, "page_dimensions_bp": list(saved[0].rect), "raster_images": 0,
        }


def retained_pricefm(root: Path) -> dict[str, dict]:
    previous = json.loads((root / MANIFEST).read_text())
    retained = {entry["role"]: entry for entry in previous["outputs"] if entry["role"] in PRICEFM_FROZEN_ROLE_PINS}
    assert set(retained) == set(PRICEFM_FROZEN_ROLE_PINS), "Excluded PriceFM receipt roles are missing."
    for role, entry in retained.items():
        assert hashlib.sha256(canonical(entry)).hexdigest() == PRICEFM_FROZEN_ROLE_PINS[role], "Excluded PriceFM receipt changed: " + role
        assert sha(root / entry["file"]) == entry["sha256"], "Excluded PriceFM output changed: " + role
        assert entry["source_sha256"] == SOURCE_PINS[entry["source"]] == sha(root / entry["source"])
    return retained


def build(root: Path, output_root: Path, *, exclude_pricefm: bool = False) -> dict:
    for path, expected in SOURCE_PINS.items():
        assert sha(root / path) == expected, "Frozen source changed: " + path
    outputs = []
    retained = retained_pricefm(root) if exclude_pricefm else {}
    for role, (source, destination) in TABLE_OUTPUTS.items():
        if role in retained:
            if output_root != root:
                (output_root / destination).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(root / destination, output_root / destination)
            outputs.append(retained[role])
            continue
        text = display_table(role, (root / source).read_text())
        target = output_root / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        outputs.append({"role": role, "file": destination, "sha256": sha(target), "source": source,
                        "source_sha256": sha(root / source), "permitted_operation": "explicit table-label/administrative-column transformation",
                        "rows": table_rows(text)})
    for role, (source, destination) in WRAPPER_OUTPUTS.items():
        target = output_root / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(display_wrapper(role, (root / source).read_text()))
        outputs.append({"role": role, "file": destination, "sha256": sha(target), "source": source,
                        "source_sha256": sha(root / source), "permitted_operation": "caption/alternative-text revision; labels and graphics unchanged"})
    for role, (source, destination) in PDF_OUTPUTS.items():
        if role in retained:
            if output_root != root:
                (output_root / destination).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(root / destination, output_root / destination)
            outputs.append(retained[role])
            continue
        outputs.append(pdf_display(root, output_root, role, source, destination))
    for role, path, aliases in (("main_overrides", MAIN_OVERRIDE, MAIN_ALIASES), ("supp_overrides", SUPP_OVERRIDE, SUPP_ALIASES)):
        target = output_root / path
        target.write_text(override_text(aliases))
        outputs.append({"role": role, "file": path, "sha256": sha(target), "permitted_operation": "document-specific presentation aliases", "aliases": aliases})
    for path, expected in SOURCE_PINS.items():
        assert sha(root / path) == expected, "A frozen source was modified."
    return {"schema": "qdesn-sections5-7-presentation-v1", "generator": BUILDER, "generator_sha256": sha(root / BUILDER),
            "sources": [{"file": path, "sha256": expected} for path, expected in sorted(SOURCE_PINS.items())],
            "outputs": outputs, "main_aliases": MAIN_ALIASES, "supp_aliases": SUPP_ALIASES,
            "scientific_runs": 0, "scores_recomputed": 0, "frozen_sources_modified": 0,
            "purpose": "Bounded reader-facing labels, captions and table columns; frozen scientific targets and evidence unchanged."}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--exclude-pricefm", action="store_true", help="Authenticate and retain frozen PriceFM outputs and per-role receipts without regeneration.")
    args = parser.parse_args()
    root = args.root.resolve()
    if args.check:
        with tempfile.TemporaryDirectory(prefix="qdesn-sections5-7-display-") as temporary:
            manifest = build(root, Path(temporary), exclude_pricefm=args.exclude_pricefm)
            assert (root / MANIFEST).read_bytes() == canonical(manifest), "Presentation manifest does not reproduce."
            for entry in manifest["outputs"]:
                assert (root / entry["file"]).read_bytes() == (Path(temporary) / entry["file"]).read_bytes(), entry["file"]
        print("QDESN_SECTIONS5_7_PRESENTATION_REPRODUCIBILITY=PASS")
    else:
        manifest = build(root, root, exclude_pricefm=args.exclude_pricefm)
        (root / MANIFEST).write_bytes(canonical(manifest))
        print("QDESN_SECTIONS5_7_PRESENTATION=BUILT")
    print(json.dumps({"outputs": len(manifest["outputs"]), "scientific_runs": 0, "scores_recomputed": 0}, sort_keys=True))


if __name__ == "__main__":
    main()
