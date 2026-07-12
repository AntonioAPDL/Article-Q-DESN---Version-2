#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- if (!is.na(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_calibration_screening.R"))
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_qdesn_phase123_mcmc_article_freeze.R"))
source(app_path("application/R/joint_qdesn_phase125_balanced_mcmc_audit.R"))

args <- app_parse_args(list(
  output_dir = "",
  phase122_dir = "",
  phase124c_dir = "",
  source_block_ids = "phase122_existing_mcmc,phase124c_missing_cell_mcmc",
  expected_scenarios = paste(app_joint_qdesn_phase125_expected_scenarios(), collapse = ","),
  expected_models = paste(app_joint_qdesn_phase125_expected_models(), collapse = ",")
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_csv <- function(x) {
  x <- as.character(x)[[1L]]
  if (!nzchar(trimws(x))) return(character())
  vals <- trimws(strsplit(x, ",", fixed = TRUE)[[1L]])
  vals[nzchar(vals)]
}

resolve_path <- function(path, default, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(path)) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, winslash = "/", mustWork = must_work)
}

source_block_ids <- parse_csv(arg_value("source_block_ids"))
source_dirs <- c(
  resolve_path(arg_value("phase122_dir"), app_joint_qdesn_default_phase122_mcmc_case_confirmation_dir(), must_work = TRUE),
  resolve_path(arg_value("phase124c_dir"), app_path("application/cache/joint_qdesn_phase124c_mcmc_balanced_completion_20260711"), must_work = TRUE)
)
if (length(source_block_ids) != length(source_dirs)) {
  stop("--source-block-ids must contain exactly two comma-separated labels.", call. = FALSE)
}

source_blocks <- data.frame(
  source_block_id = source_block_ids,
  source_role = c("existing_case_specific_mcmc_rows", "balanced_missing_cell_mcmc_rows"),
  source_dir = source_dirs,
  stringsAsFactors = FALSE
)

result <- app_joint_qdesn_run_phase125_balanced_mcmc_audit(
  out_dir = resolve_path(
    arg_value("output_dir"),
    app_joint_qdesn_default_phase125_balanced_mcmc_audit_dir(),
    must_work = FALSE
  ),
  source_blocks = source_blocks,
  expected_scenarios = parse_csv(arg_value("expected_scenarios")),
  expected_models = parse_csv(arg_value("expected_models"))
)

cat(sprintf("Joint QDESN Phase 125 balanced MCMC audit written to %s\n", result$out_dir))
cat("Health summary:\n")
print(result$health[, c("component", "status", "progress"), drop = FALSE], row.names = FALSE)
cat("Gate counts:\n")
print(table(result$gate_summary$status))
cat("Model summary:\n")
print(result$model_summary[, c(
  "model_label", "n_cases", "n_pass", "n_review", "n_fail",
  "mcmc_fit_truth_mae", "mcmc_forecast_truth_mae",
  "mcmc_forecast_check_loss", "mcmc_forecast_crps_grid",
  "mcmc_forecast_raw_crossing_pairs",
  "mcmc_forecast_contract_crossing_pairs", "gate_status"
)], row.names = FALSE)
cat("Recommendation:\n")
print(result$recommendation, row.names = FALSE)
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
