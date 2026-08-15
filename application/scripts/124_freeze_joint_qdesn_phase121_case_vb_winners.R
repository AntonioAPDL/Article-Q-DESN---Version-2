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

args <- app_parse_args(list(
  output_dir = "",
  al_high_priority_dir = "",
  exal_high_priority_dir = "",
  phase120_targeted_dir = "",
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
  normalizePath(out, mustWork = must_work)
}

phase119_root <- app_joint_qdesn_default_phase119_case_screening_dir()
result <- app_joint_qdesn_run_phase121_case_vb_winner_freeze(
  out_dir = resolve_path(arg_value("output_dir"), app_joint_qdesn_default_phase121_case_vb_freeze_dir(), must_work = FALSE),
  al_high_priority_dir = resolve_path(arg_value("al_high_priority_dir"), file.path(phase119_root, "al_high_priority"), must_work = TRUE),
  exal_high_priority_dir = resolve_path(arg_value("exal_high_priority_dir"), file.path(phase119_root, "exal_high_priority"), must_work = TRUE),
  phase120_targeted_dir = resolve_path(arg_value("phase120_targeted_dir"), file.path(app_joint_qdesn_default_phase120_case_screening_dir(), "targeted_followup"), must_work = TRUE),
  fixture_dir = resolve_path(arg_value("fixture_dir"), app_joint_qdesn_default_simulation_fixture_dir(), must_work = FALSE),
  mcmc_out_dir = resolve_path(arg_value("mcmc_out_dir"), app_path("application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711"), must_work = FALSE),
  forecast_mae_abs_tolerance = parse_number(arg_value("forecast_mae_abs_tolerance")),
  forecast_mae_rel_tolerance = parse_number(arg_value("forecast_mae_rel_tolerance")),
  n_cores = parse_integer(arg_value("n_cores")),
  n_chains = parse_integer(arg_value("n_chains")),
  mcmc_n_iter = parse_integer(arg_value("mcmc_n_iter")),
  mcmc_burn = parse_integer(arg_value("mcmc_burn")),
  mcmc_thin = parse_integer(arg_value("mcmc_thin"))
)

cat(sprintf("Joint QDESN Phase 121 case-specific VB winner freeze written to %s\n", result$out_dir))
cat("Freeze summary:\n")
print(result$run_config[, c(
  "freeze_status", "n_candidate_rows", "n_case_winners",
  "n_pass_winners", "n_review_winners", "selected_contract_crossings",
  "selected_raw_crossings", "selected_max_iter_flags"
)], row.names = FALSE)
cat("Gate counts:\n")
print(table(result$gate_audit$status))
cat("Winner counts by model:\n")
print(table(result$winners$model_ids, result$winners$phase121_selection_status))
cat("MCMC readiness:\n")
print(result$mcmc_gap[, c("model_id", "selected_cases", "readiness_status")], row.names = FALSE)
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
