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

args <- app_parse_args(list(
  output_dir = "",
  phase121_dir = "",
  fixture_dir = "",
  case_ids = "",
  scenario_ids = "",
  model_ids = "",
  scenario_limit_per_model = "",
  n_chains = "2",
  mcmc_n_iter = "80",
  mcmc_burn = "40",
  mcmc_thin = "5",
  mcmc_seed_offset = "4100",
  chain_seed_stride = "100",
  sigma_upper_multiplier = "50",
  distance_pass = "5",
  chain_pass = "5",
  n_cores = "1"
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

parse_integer <- function(x, allow_empty = FALSE) {
  x <- as.character(x)[[1L]]
  if (allow_empty && !nzchar(trimws(x))) return(NULL)
  out <- as.integer(suppressWarnings(as.numeric(x)))
  if (is.na(out)) stop(sprintf("Expected integer value, got '%s'.", x), call. = FALSE)
  out
}

parse_number <- function(x) {
  x <- as.character(x)[[1L]]
  out <- suppressWarnings(as.numeric(x))
  if (is.na(out)) stop(sprintf("Expected numeric value, got '%s'.", x), call. = FALSE)
  out
}

resolve_path <- function(path, default, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(path)) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

result <- app_joint_qdesn_run_phase122_mcmc_case_confirmation(
  out_dir = resolve_path(arg_value("output_dir"), app_joint_qdesn_default_phase122_mcmc_case_confirmation_dir(), must_work = FALSE),
  phase121_dir = resolve_path(arg_value("phase121_dir"), app_joint_qdesn_default_phase121_case_vb_freeze_dir_fallback(), must_work = TRUE),
  fixture_dir = resolve_path(arg_value("fixture_dir"), app_joint_qdesn_default_simulation_fixture_dir(), must_work = TRUE),
  case_ids = parse_csv(arg_value("case_ids")),
  scenario_ids = parse_csv(arg_value("scenario_ids")),
  model_ids = parse_csv(arg_value("model_ids")),
  scenario_limit_per_model = parse_integer(arg_value("scenario_limit_per_model"), allow_empty = TRUE),
  n_chains = parse_integer(arg_value("n_chains")),
  mcmc_n_iter = parse_integer(arg_value("mcmc_n_iter")),
  mcmc_burn = parse_integer(arg_value("mcmc_burn")),
  mcmc_thin = parse_integer(arg_value("mcmc_thin")),
  mcmc_seed_offset = parse_integer(arg_value("mcmc_seed_offset")),
  chain_seed_stride = parse_integer(arg_value("chain_seed_stride")),
  sigma_upper_multiplier = parse_number(arg_value("sigma_upper_multiplier")),
  distance_pass = parse_number(arg_value("distance_pass")),
  chain_pass = parse_number(arg_value("chain_pass")),
  n_cores = parse_integer(arg_value("n_cores"))
)

cat(sprintf("Joint QDESN Phase 122 MCMC case-confirmation artifacts written to %s\n", result$out_dir))
cat("Run summary:\n")
print(result$run_config[, c(
  "n_cases", "mcmc_n_chains", "mcmc_n_iter", "mcmc_burn",
  "mcmc_thin", "n_cores", "validation_contract"
)], row.names = FALSE)
cat("Gate counts:\n")
print(table(result$assessment$gate_status))
cat("Model/case counts:\n")
print(table(result$summary$source_model_id, result$assessment$gate_status))
cat(sprintf("Worker failures: %d\n", nrow(result$worker_failures)))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
