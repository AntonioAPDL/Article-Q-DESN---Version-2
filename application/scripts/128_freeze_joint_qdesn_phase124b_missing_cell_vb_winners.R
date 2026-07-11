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
source(app_path("application/R/joint_qdesn_simulation_fixtures.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_calibration_screening.R"))
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_qdesn_phase123_mcmc_article_freeze.R"))
source(app_path("application/R/joint_qdesn_phase124_balanced_completion.R"))

args <- app_parse_args(list(
  output_dir = "",
  phase124_prepare_dir = "",
  phase124_vb_dir = "",
  fixture_dir = "",
  mcmc_out_dir = "",
  forecast_mae_abs_tolerance = "0.0005",
  forecast_mae_rel_tolerance = "0.005",
  n_cores = "12",
  n_chains = "2",
  mcmc_n_iter = "1200",
  mcmc_burn = "600",
  mcmc_thin = "10"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_integer <- function(x) {
  out <- as.integer(suppressWarnings(as.numeric(as.character(x)[[1L]])))
  if (is.na(out)) stop(sprintf("Expected integer value, got '%s'.", as.character(x)[[1L]]), call. = FALSE)
  out
}

parse_number <- function(x) {
  out <- suppressWarnings(as.numeric(as.character(x)[[1L]]))
  if (is.na(out)) stop(sprintf("Expected numeric value, got '%s'.", as.character(x)[[1L]]), call. = FALSE)
  out
}

resolve_path <- function(path, default, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(path)) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, winslash = "/", mustWork = must_work)
}

result <- app_joint_qdesn_run_phase124b_missing_cell_vb_winner_freeze(
  out_dir = resolve_path(arg_value("output_dir"), app_joint_qdesn_default_phase124b_missing_cell_vb_freeze_dir(), must_work = FALSE),
  phase124_prepare_dir = resolve_path(arg_value("phase124_prepare_dir"), app_joint_qdesn_default_phase124_balanced_completion_dir(), must_work = TRUE),
  phase124_vb_dir = resolve_path(arg_value("phase124_vb_dir"), app_joint_qdesn_default_phase124_vb_completion_dir(), must_work = TRUE),
  fixture_dir = resolve_path(arg_value("fixture_dir"), app_joint_qdesn_default_simulation_fixture_dir(), must_work = FALSE),
  mcmc_out_dir = resolve_path(arg_value("mcmc_out_dir"), app_joint_qdesn_default_phase124c_mcmc_completion_dir(), must_work = FALSE),
  forecast_mae_abs_tolerance = parse_number(arg_value("forecast_mae_abs_tolerance")),
  forecast_mae_rel_tolerance = parse_number(arg_value("forecast_mae_rel_tolerance")),
  n_cores = parse_integer(arg_value("n_cores")),
  n_chains = parse_integer(arg_value("n_chains")),
  mcmc_n_iter = parse_integer(arg_value("mcmc_n_iter")),
  mcmc_burn = parse_integer(arg_value("mcmc_burn")),
  mcmc_thin = parse_integer(arg_value("mcmc_thin"))
)

cat(sprintf("Joint QDESN Phase 124b missing-cell VB winner freeze written to %s\n", result$out_dir))
cat("Freeze summary:\n")
print(result$run_config[, c(
  "freeze_status", "n_candidate_rows", "n_missing_cells", "n_case_winners",
  "n_pass_winners", "n_review_winners", "n_fail_winners",
  "selected_contract_crossings", "selected_raw_crossings", "selected_max_iter_flags"
)], row.names = FALSE)
cat("Gate counts:\n")
print(table(result$gate_audit$status))
cat("Winner counts by model:\n")
print(table(result$winners$model_ids, result$winners$phase121_selection_status))
cat("Phase124c MCMC launch command:\n")
print(result$launch_plan[result$launch_plan$command_id == "launch_phase124c_mcmc_completion", "command"], quote = FALSE)
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
