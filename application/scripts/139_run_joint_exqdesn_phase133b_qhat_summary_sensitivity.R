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
source(app_path("application/R/joint_exqdesn_phase133b_qhat_sensitivity.R"))

args <- app_parse_args(list(
  output_dir = "",
  phase133_dir = "",
  phase121_dir = "",
  fixture_dir = "",
  scenario_ids = "",
  model_ids = "joint_exqdesn_rhs_vb",
  n_chains = "2",
  mcmc_n_iter = "1200",
  mcmc_burn = "600",
  mcmc_thin = "10",
  mcmc_seed_offset = "13320",
  chain_seed_stride = "100",
  sigma_upper_multiplier = "50",
  distance_pass = "5",
  chain_pass = "5",
  n_cores = "5",
  qhat_max_draws = "2000",
  qhat_draw_seed = "133020",
  qhat_trim_fraction = "0.10"
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

parse_integer <- function(x) {
  out <- as.integer(suppressWarnings(as.numeric(as.character(x)[[1L]])))
  if (is.na(out)) stop(sprintf("Expected integer value, got '%s'.", x), call. = FALSE)
  out
}

parse_number <- function(x) {
  out <- suppressWarnings(as.numeric(as.character(x)[[1L]]))
  if (!is.finite(out)) stop(sprintf("Expected numeric value, got '%s'.", x), call. = FALSE)
  out
}

resolve_path <- function(path, default, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(path)) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

scenario_ids <- parse_csv(arg_value("scenario_ids"))
if (!length(scenario_ids)) scenario_ids <- NULL

result <- app_joint_exqdesn_run_phase133b_qhat_sensitivity(
  out_dir = resolve_path(arg_value("output_dir"), app_joint_exqdesn_phase133b_default_dir(), must_work = FALSE),
  phase133_dir = resolve_path(arg_value("phase133_dir"), app_joint_exqdesn_phase133b_default_phase133_dir(), must_work = TRUE),
  phase121_dir = resolve_path(arg_value("phase121_dir"), app_joint_qdesn_default_phase121_case_vb_freeze_dir_fallback(), must_work = TRUE),
  fixture_dir = resolve_path(arg_value("fixture_dir"), app_joint_qdesn_default_simulation_fixture_dir(), must_work = TRUE),
  scenario_ids = scenario_ids,
  model_ids = parse_csv(arg_value("model_ids")),
  n_chains = parse_integer(arg_value("n_chains")),
  mcmc_n_iter = parse_integer(arg_value("mcmc_n_iter")),
  mcmc_burn = parse_integer(arg_value("mcmc_burn")),
  mcmc_thin = parse_integer(arg_value("mcmc_thin")),
  mcmc_seed_offset = parse_integer(arg_value("mcmc_seed_offset")),
  chain_seed_stride = parse_integer(arg_value("chain_seed_stride")),
  sigma_upper_multiplier = parse_number(arg_value("sigma_upper_multiplier")),
  distance_pass = parse_number(arg_value("distance_pass")),
  chain_pass = parse_number(arg_value("chain_pass")),
  n_cores = parse_integer(arg_value("n_cores")),
  qhat_max_draws = parse_integer(arg_value("qhat_max_draws")),
  qhat_draw_seed = parse_integer(arg_value("qhat_draw_seed")),
  qhat_trim_fraction = parse_number(arg_value("qhat_trim_fraction"))
)

cat(sprintf("Joint exQDESN Phase133B qhat-summary sensitivity artifacts written to %s\n", result$out_dir))
cat("Run summary:\n")
print(result$run_config[, c(
  "n_cases", "mcmc_n_chains", "mcmc_n_iter", "mcmc_burn", "mcmc_thin",
  "n_cores", "qhat_max_draws", "qhat_summary_methods"
)], row.names = FALSE)
cat("Assessment:\n")
print(result$assessment, row.names = FALSE)
cat("Recommendations:\n")
print(result$recommendations[, c("scenario_id", "best_qhat_summary_method", "best_method_delta_vs_phase125_mean", "best_method_gap_to_current_winner", "recommended_next_action")], row.names = FALSE)
cat(sprintf("Worker failures: %d\n", nrow(result$worker_failures)))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
