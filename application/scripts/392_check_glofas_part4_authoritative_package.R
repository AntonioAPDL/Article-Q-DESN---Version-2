#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- sub("^--file=", "", script_arg[[1L]])
repo_root <- normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(output_tag = "glofas_part4_joint_al_sweep10_20260911"))
tag <- trimws(as.character(args$output_tag)[[1L]])
table_path <- function(stem, ext = "csv") app_path("tables", paste0(stem, "__", tag, ".", ext))

paths <- c(
  forecast = table_path("glofas_application_part4_forecast_scores"),
  history = table_path("glofas_application_part4_historical_guardrail"),
  common = table_path("glofas_application_part4_common_grid_tradeoff"),
  convergence = table_path("glofas_application_part4_joint_convergence"),
  stability = table_path("glofas_application_part4_joint_sweep_stability"),
  specification = table_path("glofas_application_part4_model_spec"),
  score_tex = table_path("glofas_application_part4_forecast_scores", "tex"),
  all_scores_tex = table_path("glofas_application_part4_all_family_scores", "tex"),
  guardrail_tex = table_path("glofas_application_part4_historical_guardrail", "tex"),
  outputs_tex = table_path("glofas_application_part4_current_outputs", "tex"),
  main_figure = app_path("figures", "glofas_application", paste0("glofas_part4_joint_al_last30_issued28__", tag, ".pdf")),
  convergence_figure = app_path("figures", "glofas_application", "diagnostics", paste0("glofas_part4_joint_al_convergence_trace__", tag, ".pdf")),
  rhs_certificate = table_path("glofas_application_part4_rhs_release_certificate"),
  grouped_figure = app_path("figures", "glofas_application", "diagnostics", paste0("glofas_part4_grouped_family_comparison__", tag, ".pdf")),
  grouped_scores = table_path("glofas_application_part4_grouped_family_scores"),
  grouped_script = app_path("application", "scripts", "391_plot_glofas_part4_grouped_family_comparison.R"),
  contract_module = app_path("application", "R", "glofas_part4_publication_contract.R"),
  manifest = table_path("glofas_application_part4_publication_manifest")
)
missing <- paths[!file.exists(paths)]
if (length(missing)) stop(sprintf("Missing Part 4 publication files: %s", paste(missing, collapse = ", ")), call. = FALSE)

manifest <- read.csv(paths[["manifest"]], stringsAsFactors = FALSE)
manifest_targets <- file.path(repo_root, manifest$relative_path)
observed_hash <- vapply(manifest_targets, app_sha256_file, character(1L))
if (any(tolower(observed_hash) != tolower(manifest$sha256))) {
  stop("Part 4 publication-manifest hash verification failed.", call. = FALSE)
}
if (any(grepl("(^|/)local_trackers/", manifest$relative_path))) {
  stop("Runtime artifacts entered the article-safe Part 4 publication manifest.", call. = FALSE)
}
required_reproduction_code <- c(
  "application/scripts/391_plot_glofas_part4_grouped_family_comparison.R",
  "application/R/glofas_part4_publication_contract.R"
)
if (!all(required_reproduction_code %in% manifest$relative_path)) {
  stop("Part 4 publication manifest omits required reproduction code.", call. = FALSE)
}
if (!all(manifest$article_safe) ||
    any(manifest$overleaf_publish & grepl("^application/", manifest$relative_path)) ||
    !all(manifest$publication_role[manifest$relative_path %in% required_reproduction_code] == "reproduction_code") ||
    any(manifest$overleaf_publish[manifest$relative_path %in% required_reproduction_code])) {
  stop("The Part 4 Git/Overleaf publication boundary is malformed.", call. = FALSE)
}

scores <- read.csv(paths[["forecast"]], stringsAsFactors = FALSE)
required_families <- c("Normal Ridge", "Normal RHS/VB", "Independent AL", "Independent exAL", "Joint AL", "Joint exAL", "Raw GloFAS")
if (!setequal(scores$family, required_families) || nrow(scores) != length(required_families)) {
  stop("Part 4 forecast scoreboard does not contain the seven required families.", call. = FALSE)
}
selected <- scores[scores$family == "Joint AL", , drop = FALSE]
raw <- scores[scores$family == "Raw GloFAS", , drop = FALSE]
independent_al <- scores[scores$family == "Independent AL", , drop = FALSE]
if (nrow(selected) != 1L || !identical(selected$role, "selected_quantile_model") ||
    isTRUE(selected$converged) ||
    !identical(selected$numerical_status, "cap_stabilized_after_rhs_release") ||
    selected$n_scored_horizons != 28L ||
    selected$crossing_pairs != 0L || selected$crps_grid_log1p >= raw$crps_grid_log1p ||
    selected$crps_grid_log1p >= independent_al$crps_grid_log1p || selected$coverage90 < 0.80 ||
    selected$mean_check_loss >= raw$mean_check_loss || selected$interval_score >= raw$interval_score) {
  stop("The selected Joint AL row does not satisfy the frozen Part 4 forecast decision.", call. = FALSE)
}

convergence <- read.csv(paths[["convergence"]], stringsAsFactors = FALSE)
al <- convergence[convergence$family == "Joint AL", , drop = FALSE]
if (nrow(al) != 1L || isTRUE(al$converged) || isTRUE(al$outer_converged) ||
    !isTRUE(al$inner_converged) || !isTRUE(al$rhs_converged) ||
    !isTRUE(al$selection_eligible) ||
    !identical(al$numerical_status, "cap_stabilized_after_rhs_release") ||
    !identical(al$stopping_reason, "max_outer_iterations_outer_tolerance_not_met") ||
    al$outer_iterations != 10L || !isTRUE(all.equal(al$outer_tolerance, 1.0e-3)) ||
    !is.finite(al$final_parameter_change) || al$final_parameter_change <= al$outer_tolerance) {
  stop("Joint AL cap-stabilized qualification failed or strict convergence was overstated.", call. = FALSE)
}

stability <- read.csv(paths[["stability"]], stringsAsFactors = FALSE)
if (nrow(stability) != 8L || stability$scope[[1L]] != "all_quantiles" ||
    any(!is.finite(stability$mean_abs_path_change)) ||
    any(stability$mean_abs_path_change <= 0) ||
    any(!is.finite(stability$mean_check_loss_source)) ||
    any(!is.finite(stability$mean_check_loss_final)) ||
    any(stability$crps_grid_log1p_final >= stability$crps_grid_log1p_source) ||
    any(stability$relative_crps_change >= 0)) {
  stop("Sweep 5-to-10 stability evidence is incomplete or contradicts the frozen decision.", call. = FALSE)
}

rhs_certificate <- read.csv(paths[["rhs_certificate"]], stringsAsFactors = FALSE)
al_rhs <- rhs_certificate[rhs_certificate$family == "Joint AL", , drop = FALSE]
if (nrow(al_rhs) != 14L || !all(al_rhs$passed) ||
    any(al_rhs$tau_update_count != 5L) ||
    any(al_rhs$tau_update_count < al_rhs$min_tau_updates) ||
    !all(al_rhs$coefficient_response_after_release) ||
    anyNA(al_rhs$max_abs_block_mean_change_from_source) ||
    any(al_rhs$max_abs_block_mean_change_from_source <= 1.0e-12) ||
    !all(al_rhs$schedule_rebased) ||
    !identical(unique(al_rhs$source_freeze_iters), 50L) ||
    !identical(unique(al_rhs$effective_freeze_outer_iters), 5L)) {
  stop("Joint AL RHS release certificate failed.", call. = FALSE)
}

common <- read.csv(paths[["common"]], stringsAsFactors = FALSE)
if (!setequal(common$window, c("all", "last1000", "last200", "last50")) ||
    any(common$part4_joint_al_crps_log1p <= 0) || any(common$fr09_crps_log1p <= 0) ||
    any(common$relative_change <= 0)) {
  stop("The historical guardrail table does not preserve the audited Part 4/FR09 tradeoff.", call. = FALSE)
}

spec <- read.csv(paths[["specification"]], stringsAsFactors = FALSE)
if (!identical(spec$component, c("Reference", "Discrepancy")) ||
    !identical(as.integer(spec$n), c(3000L, 2500L)) ||
    !isTRUE(all.equal(as.numeric(spec$rhs_tau0), c(1, 0.001), tolerance = 1.0e-14))) {
  stop("The article-safe Part 4 specification table is inconsistent with the frozen anchors.", call. = FALSE)
}

outputs <- readLines(paths[["outputs_tex"]], warn = FALSE)
if (any(grepl("local_trackers", outputs, fixed = TRUE)) ||
    !any(grepl("GlofasApplicationCurrentOriginDate}{2022-12-25}", outputs, fixed = TRUE)) ||
    !any(grepl("GlofasApplicationCurrentNumericalStatus", outputs, fixed = TRUE)) ||
    !any(grepl("not strictly outer-converged", outputs, fixed = TRUE)) ||
    !any(grepl("strict outer tolerance not met", outputs, fixed = TRUE)) ||
    !any(grepl("No spread calibration or crossing correction", outputs, fixed = TRUE))) {
  stop("The proposed current-output registry is not article-safe or violates the frozen contract.", call. = FALSE)
}

health <- data.frame(
  check = c(
    "publication_manifest_hashes", "runtime_paths_excluded", "git_overleaf_boundary", "required_family_scoreboard",
    "joint_al_cap_status_not_overstated", "joint_al_inner_and_rhs_qualification", "sweep5_to_sweep10_stability",
    "rhs_scale_release_and_numerical_response", "issued_window_horizons", "no_crossing_fix_needed",
    "forecast_improvement_vs_raw_and_independent_al", "historical_tradeoff_disclosed", "frozen_anchor_specification"
  ),
  status = "pass",
  stringsAsFactors = FALSE
)
print(health, row.names = FALSE)
cat(sprintf(
  "PART4_ARTICLE_PACKAGE_VERIFIED\nselected_crps_log1p=%.8f\nraw_crps_log1p=%.8f\nreduction=%.4f%%\n",
  selected$crps_grid_log1p, raw$crps_grid_log1p, 100 * selected$crps_reduction_vs_raw
))
