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
  targeted_registry = "",
  output_dir = "",
  tier = "smoke",
  screen_ids = "",
  scenario_ids = "",
  vb_max_iter = "",
  adaptive_vb_max_iter_grid = "",
  refit_stride = "",
  forecast_origin_stride = "",
  max_origins_per_scenario = "",
  vb_tol = "",
  kappa = "",
  a_sigma = "",
  b_sigma = "",
  alpha_prior_mean = ""
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
  app_joint_qvp_default_synthetic_dgp_phase4g_screen_dir()
}
targeted_registry_path <- if (nzchar(as.character(arg_value("targeted_registry")))) {
  as.character(arg_value("targeted_registry"))
} else {
  app_joint_qvp_default_synthetic_dgp_phase4g_targeted_registry_path()
}

result <- app_joint_qvp_run_synthetic_dgp_phase4g_prior_design_screen(
  out_dir = out_dir,
  targeted_registry_path = targeted_registry_path,
  tier = tier,
  screen_ids = parse_csv(arg_value("screen_ids")),
  scenario_ids = parse_csv(arg_value("scenario_ids")),
  vb_max_iter = parse_optional_int(arg_value("vb_max_iter")),
  adaptive_vb_max_iter_grid = parse_optional_int_grid(arg_value("adaptive_vb_max_iter_grid")),
  refit_stride = parse_optional_int(arg_value("refit_stride")),
  forecast_origin_stride = parse_optional_int(arg_value("forecast_origin_stride")),
  max_origins_per_scenario = parse_optional_number_or_inf(arg_value("max_origins_per_scenario")),
  vb_tol = parse_optional_number(arg_value("vb_tol")) %||% 1.0e-4,
  kappa = parse_optional_number(arg_value("kappa")) %||% 1,
  a_sigma = parse_optional_number(arg_value("a_sigma")) %||% 2,
  b_sigma = parse_optional_number(arg_value("b_sigma")) %||% 1,
  alpha_prior_mean = if (nzchar(as.character(arg_value("alpha_prior_mean")))) as.character(arg_value("alpha_prior_mean")) else "empirical_quantile"
)

cat(sprintf("Joint-QVP synthetic DGP Phase 4g prior/design screen artifacts written to %s\n", result$out_dir))
cat(sprintf("Targeted registry rows: %s\n", nrow(result$targeted_registry)))
cat(sprintf("Screen rows: %s\n", nrow(result$screen_grid)))
cat("Screen statuses:\n")
print(table(result$screen_candidate_ranking$screen_status))
cat(sprintf("Recommendation: %s\n", result$screen_recommendation$recommendation_status[[1L]]))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
