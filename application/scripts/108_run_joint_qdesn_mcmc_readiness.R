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
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))

args <- app_parse_args(list(
  output_dir = "",
  fixture_dir = "",
  phase107_dir = "",
  scenario_ids = "",
  candidate_id = "rhs_tau0_0p5_alpha0p5",
  n_chains = "2",
  mcmc_n_iter = "80",
  mcmc_burn = "40",
  mcmc_thin = "5",
  mcmc_seed_offset = "3100",
  chain_seed_stride = "100",
  sigma_upper_multiplier = "50",
  distance_pass = "5",
  chain_pass = "5",
  n_cores = "4",
  final_article_mcmc_table = "false"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_csv <- function(x) {
  vals <- trimws(strsplit(as.character(x), ",", fixed = TRUE)[[1L]])
  vals[nzchar(vals)]
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

parse_bool <- function(x) {
  x <- tolower(trimws(as.character(x)[[1L]]))
  if (x %in% c("true", "t", "1", "yes", "y")) return(TRUE)
  if (x %in% c("false", "f", "0", "no", "n")) return(FALSE)
  stop(sprintf("Expected boolean value, got '%s'.", x), call. = FALSE)
}

resolve_path <- function(path, default, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(path)) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

scenario_ids <- parse_csv(arg_value("scenario_ids"))

result <- app_joint_qdesn_run_mcmc_readiness(
  out_dir = resolve_path(arg_value("output_dir"), app_joint_qdesn_default_mcmc_readiness_dir(), must_work = FALSE),
  fixture_dir = resolve_path(arg_value("fixture_dir"), app_joint_qdesn_default_simulation_fixture_dir(), must_work = TRUE),
  phase107_dir = resolve_path(arg_value("phase107_dir"), app_joint_qdesn_default_phase107_dir(), must_work = TRUE),
  scenario_ids = if (length(scenario_ids)) scenario_ids else NULL,
  candidate_id = as.character(arg_value("candidate_id"))[[1L]],
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
  final_article_mcmc_table = parse_bool(arg_value("final_article_mcmc_table"))
)

cat(sprintf("Joint QDESN Phase 108 MCMC readiness artifacts written to %s\n", result$out_dir))
cat("Assessment gate counts:\n")
print(table(result$assessment$gate_status))
cat("Scenario summary:\n")
print(result$summary[, c(
  "scenario_id", "vb_converged", "mcmc_n_keep_total",
  "mcmc_truth_mae", "vb_mcmc_max_normalized_distance",
  "mcmc_contract_crossing_pairs", "total_elapsed_seconds"
)], row.names = FALSE)
cat(sprintf("Worker failures: %s\n", nrow(result$worker_failures)))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
