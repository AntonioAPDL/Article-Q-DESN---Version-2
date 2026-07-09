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
  tier = "smoke",
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
  max_origins_per_scenario = ""
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

parse_optional_int <- function(x) {
  x <- as.character(x)[[1L]]
  if (!nzchar(x)) return(NULL)
  out <- suppressWarnings(as.integer(x))
  if (is.na(out)) stop(sprintf("Expected integer, got '%s'.", x), call. = FALSE)
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
defaults <- app_joint_qvp_phase4_tier_defaults(tier)
out_dir <- if (nzchar(as.character(arg_value("output_dir")))) {
  as.character(arg_value("output_dir"))
} else {
  app_joint_qvp_default_synthetic_dgp_forecast_calibration_dir()
}
registry_path <- if (nzchar(as.character(arg_value("registry")))) {
  as.character(arg_value("registry"))
} else {
  app_joint_qvp_default_synthetic_dgp_registry_path()
}
scenario_ids <- parse_csv(arg_value("scenario_ids"))

result <- app_joint_qvp_run_synthetic_dgp_forecast_calibration(
  out_dir = out_dir,
  registry_path = registry_path,
  scenario_ids = if (length(scenario_ids)) scenario_ids else NULL,
  tier = tier,
  n_replicates = parse_optional_int(arg_value("n_replicates")),
  seed_base = parse_optional_int(arg_value("seed_base")),
  simulated_length = parse_optional_int(arg_value("simulated_length")),
  washout_length = parse_optional_int(arg_value("washout_length")),
  train_length = parse_optional_int(arg_value("train_length")),
  test_length = parse_optional_int(arg_value("test_length")),
  vb_max_iter = parse_optional_int(arg_value("vb_max_iter")) %||% defaults$vb_max_iter,
  adaptive_vb_max_iter_grid = parse_optional_int_grid(arg_value("adaptive_vb_max_iter_grid")) %||% defaults$adaptive_vb_max_iter_grid,
  refit_stride = parse_optional_int(arg_value("refit_stride")) %||% defaults$refit_stride,
  forecast_origin_stride = parse_optional_int(arg_value("forecast_origin_stride")) %||% defaults$forecast_origin_stride,
  max_origins_per_scenario = parse_optional_number_or_inf(arg_value("max_origins_per_scenario")) %||% defaults$max_origins_per_scenario
)

cat(sprintf("Joint-QVP synthetic DGP Phase 4 forecast-calibration artifacts written to %s\n", result$out_dir))
cat(sprintf("Underlying Phase 3 artifacts: %s\n", result$phase3_out_dir))
cat(sprintf("Tier: %s\n", result$calibration_run_config$validation_tier[[1L]]))
cat(sprintf("Calibration registry rows: %s\n", nrow(result$calibration_registry)))
cat(sprintf("Threshold rows: %s\n", nrow(result$forecast_calibrated_thresholds)))
cat("Gate counts:\n")
print(table(result$forecast_calibration_assessment$gate_status))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
