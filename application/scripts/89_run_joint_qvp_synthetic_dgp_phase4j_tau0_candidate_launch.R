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

args <- app_parse_args(list(
  registry = "",
  output_dir = "",
  scenario_ids = "",
  tier = "tau0_candidate_launch",
  tau0_arms = "0.10,0.15",
  include_reference_arm = "false",
  arm_ids = "",
  n_replicates = "",
  seed_base = "",
  simulated_length = "",
  washout_length = "",
  train_length = "",
  test_length = "",
  vb_max_iter = "",
  adaptive_vb_max_iter_grid = "",
  refit_stride = "",
  forecast_origin_stride = "",
  max_origins_per_scenario = "",
  vb_tol = "",
  kappa = "",
  a_sigma = "",
  b_sigma = "",
  alpha_prior_mean = "",
  primary_arm_id = "tau0_0p10_primary"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_csv <- function(x) {
  out <- trimws(strsplit(as.character(x), ",", fixed = TRUE)[[1L]])
  out[nzchar(out)]
}

parse_number_grid <- function(x) {
  vals <- suppressWarnings(as.numeric(parse_csv(x)))
  vals <- vals[is.finite(vals) & vals > 0]
  if (!length(vals)) stop(sprintf("Expected a positive numeric grid, got '%s'.", as.character(x)[[1L]]), call. = FALSE)
  vals
}

parse_optional_int <- function(x) {
  x <- as.character(x)[[1L]]
  if (!nzchar(x)) return(NULL)
  out <- suppressWarnings(as.integer(x))
  if (is.na(out)) stop(sprintf("Expected integer, got '%s'.", x), call. = FALSE)
  out
}

parse_optional_number <- function(x) {
  x <- as.character(x)[[1L]]
  if (!nzchar(x)) return(NULL)
  out <- suppressWarnings(as.numeric(x))
  if (is.na(out)) stop(sprintf("Expected numeric, got '%s'.", x), call. = FALSE)
  out
}

parse_optional_number_or_inf <- function(x) {
  x <- as.character(x)[[1L]]
  if (!nzchar(x)) return(NULL)
  out <- suppressWarnings(as.numeric(x))
  if (is.na(out)) stop(sprintf("Expected numeric or Inf, got '%s'.", x), call. = FALSE)
  out
}

parse_optional_int_grid <- function(x) {
  x <- as.character(x)[[1L]]
  if (!nzchar(x)) return(NULL)
  out <- suppressWarnings(as.integer(parse_csv(x)))
  out <- out[is.finite(out) & out > 0L]
  if (!length(out)) stop(sprintf("Expected a positive integer grid, got '%s'.", x), call. = FALSE)
  out
}

tier <- as.character(arg_value("tier"))[[1L]]
out_dir <- if (nzchar(as.character(arg_value("output_dir")))) {
  as.character(arg_value("output_dir"))
} else {
  app_joint_qvp_default_synthetic_dgp_phase4j_launch_dir()
}
registry_path <- if (nzchar(as.character(arg_value("registry")))) {
  as.character(arg_value("registry"))
} else {
  app_joint_qvp_default_synthetic_dgp_registry_path()
}

result <- app_joint_qvp_run_synthetic_dgp_phase4j_tau0_candidate_launch(
  out_dir = out_dir,
  registry_path = registry_path,
  scenario_ids = parse_csv(arg_value("scenario_ids")),
  tier = tier,
  tau0_arms = parse_number_grid(arg_value("tau0_arms")),
  include_reference_arm = app_as_bool(arg_value("include_reference_arm")),
  arm_ids = parse_csv(arg_value("arm_ids")),
  n_replicates = parse_optional_int(arg_value("n_replicates")),
  seed_base = parse_optional_int(arg_value("seed_base")),
  simulated_length = parse_optional_int(arg_value("simulated_length")),
  washout_length = parse_optional_int(arg_value("washout_length")),
  train_length = parse_optional_int(arg_value("train_length")),
  test_length = parse_optional_int(arg_value("test_length")),
  vb_max_iter = parse_optional_int(arg_value("vb_max_iter")),
  adaptive_vb_max_iter_grid = parse_optional_int_grid(arg_value("adaptive_vb_max_iter_grid")),
  refit_stride = parse_optional_int(arg_value("refit_stride")),
  forecast_origin_stride = parse_optional_int(arg_value("forecast_origin_stride")),
  max_origins_per_scenario = parse_optional_number_or_inf(arg_value("max_origins_per_scenario")),
  vb_tol = parse_optional_number(arg_value("vb_tol")) %||% 1.0e-4,
  kappa = parse_optional_number(arg_value("kappa")) %||% 1,
  a_sigma = parse_optional_number(arg_value("a_sigma")) %||% 2,
  b_sigma = parse_optional_number(arg_value("b_sigma")) %||% 1,
  alpha_prior_mean = if (nzchar(as.character(arg_value("alpha_prior_mean")))) as.character(arg_value("alpha_prior_mean")) else "empirical_quantile",
  primary_arm_id = as.character(arg_value("primary_arm_id"))[[1L]]
)

cat(sprintf("Joint-QVP synthetic DGP Phase 4j tau0 candidate launch artifacts written to %s\n", result$out_dir))
cat(sprintf("Launch registry rows: %s\n", nrow(result$launch_registry)))
cat(sprintf("Candidate arms: %s\n", nrow(result$launch_arm_grid)))
cat(sprintf("Gate: %s\n", result$phase4j_readiness_assessment$gate_status[[1L]]))
cat(sprintf("Recommendation: %s\n", result$launch_recommendation$recommendation_status[[1L]]))
cat(sprintf("Selected arm: %s\n", result$launch_recommendation$selected_arm_id[[1L]]))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
