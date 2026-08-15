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

args <- app_parse_args(list(
  output_dir = "",
  fixture_dir = "",
  scenario_ids = "",
  vb_max_iter = "240",
  adaptive_vb_max_iter_grid = "240,480",
  vb_tol = "1e-4",
  rhs_vb_inner = "5",
  tau0 = "1",
  zeta2 = "Inf",
  a_sigma = "2",
  b_sigma = "1",
  alpha_prior_sd = "1",
  alpha_min_spacing = "0",
  review_adjustment_threshold = "1e-3",
  max_dense_dim = "300",
  n_cores = "1"
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

out_dir <- if (nzchar(as.character(arg_value("output_dir")))) {
  as.character(arg_value("output_dir"))
} else {
  app_joint_qdesn_default_vb_fit_validation_dir()
}

fixture_dir <- if (nzchar(as.character(arg_value("fixture_dir")))) {
  as.character(arg_value("fixture_dir"))
} else {
  app_joint_qdesn_default_simulation_fixture_dir()
}

adaptive_grid <- as.integer(parse_csv(arg_value("adaptive_vb_max_iter_grid")))
adaptive_grid <- adaptive_grid[is.finite(adaptive_grid) & adaptive_grid > 0L]
if (!length(adaptive_grid)) adaptive_grid <- parse_integer(arg_value("vb_max_iter"))

scenario_ids <- parse_csv(arg_value("scenario_ids"))

result <- app_joint_qdesn_run_vb_fit_validation(
  out_dir = out_dir,
  fixture_dir = fixture_dir,
  scenario_ids = if (length(scenario_ids)) scenario_ids else NULL,
  vb_max_iter = parse_integer(arg_value("vb_max_iter")),
  adaptive_vb_max_iter_grid = adaptive_grid,
  vb_tol = parse_number(arg_value("vb_tol")),
  rhs_vb_inner = parse_integer(arg_value("rhs_vb_inner")),
  tau0 = parse_number(arg_value("tau0")),
  zeta2 = parse_number(arg_value("zeta2")),
  a_sigma = parse_number(arg_value("a_sigma")),
  b_sigma = parse_number(arg_value("b_sigma")),
  alpha_prior_sd = parse_number(arg_value("alpha_prior_sd")),
  alpha_min_spacing = parse_number(arg_value("alpha_min_spacing")),
  review_adjustment_threshold = parse_number(arg_value("review_adjustment_threshold")),
  max_dense_dim = parse_integer(arg_value("max_dense_dim")),
  n_cores = parse_integer(arg_value("n_cores"))
)

cat(sprintf("Joint QDESN VB fit-validation artifacts written to %s\n", result$out_dir))
cat(sprintf("Fixture source: %s\n", result$fixture_dir))
cat(sprintf("Scenarios: %s\n", result$run_config$n_scenarios[[1L]]))
cat("Gate counts:\n")
print(table(result$fit_validation_assessment$gate_status))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
