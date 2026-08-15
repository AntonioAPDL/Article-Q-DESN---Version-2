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
  output_dir = "",
  registry = "",
  fixture_dir = "",
  phase2_dir = "",
  scenario_ids = "",
  smoke = "false",
  kappa = "1",
  tau0 = "1",
  zeta2 = "Inf",
  a_sigma = "2",
  b_sigma = "1",
  alpha_prior_mean = "empirical_quantile",
  alpha_prior_sd = "1",
  alpha_min_spacing = "0",
  vb_max_iter = "80",
  adaptive_vb_max_iter_grid = "80,160",
  rhs_vb_inner = "5",
  vb_tol = "1e-4",
  refit_stride = "1",
  forecast_origin_stride = "1",
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

parse_int <- function(x) as.integer(as.character(x)[[1L]])

parse_number <- function(x) {
  out <- suppressWarnings(as.numeric(as.character(x)[[1L]]))
  if (is.na(out)) stop(sprintf("Expected numeric, got '%s'.", as.character(x)[[1L]]), call. = FALSE)
  out
}

parse_number_or_inf <- function(x, default = Inf) {
  x <- as.character(x)[[1L]]
  if (!nzchar(x)) return(default)
  out <- suppressWarnings(as.numeric(x))
  if (is.na(out)) stop(sprintf("Expected numeric or Inf, got '%s'.", x), call. = FALSE)
  out
}

out_dir <- if (nzchar(as.character(arg_value("output_dir")))) {
  as.character(arg_value("output_dir"))
} else {
  app_joint_qvp_default_synthetic_dgp_forecast_validation_dir()
}

registry_path <- if (nzchar(as.character(arg_value("registry")))) {
  as.character(arg_value("registry"))
} else {
  app_joint_qvp_default_synthetic_dgp_registry_path()
}

fixture_dir <- if (nzchar(as.character(arg_value("fixture_dir")))) as.character(arg_value("fixture_dir")) else NULL
phase2_dir <- if (nzchar(as.character(arg_value("phase2_dir")))) as.character(arg_value("phase2_dir")) else NULL
scenario_ids <- parse_csv(arg_value("scenario_ids"))
is_smoke <- app_as_bool(arg_value("smoke"))

registry <- NULL
if (is_smoke && is.null(fixture_dir)) {
  registry <- app_read_csv(registry_path)
  if (length(scenario_ids)) {
    missing_ids <- setdiff(scenario_ids, registry$scenario_id)
    if (length(missing_ids)) stop("Requested --scenario-ids not found in registry: ", paste(missing_ids, collapse = ", "), call. = FALSE)
    registry <- registry[registry$scenario_id %in% scenario_ids, , drop = FALSE]
  }
  registry$simulated_length <- 72L
  registry$washout_length <- 12L
  registry$train_length <- 42L
  registry$test_length <- 18L
  app_joint_qvp_validate_synthetic_dgp_registry(registry)
}

vb_max_iter <- parse_int(arg_value("vb_max_iter"))
adaptive_grid <- as.integer(parse_csv(arg_value("adaptive_vb_max_iter_grid")))
adaptive_grid <- adaptive_grid[is.finite(adaptive_grid) & adaptive_grid > 0L]
if (!length(adaptive_grid)) adaptive_grid <- vb_max_iter
max_origins <- parse_number_or_inf(
  arg_value("max_origins_per_scenario"),
  default = if (is_smoke) 3 else Inf
)

result <- app_joint_qvp_run_synthetic_dgp_forecast_validation(
  out_dir = out_dir,
  registry_path = registry_path,
  fixture_dir = fixture_dir,
  phase2_dir = phase2_dir,
  registry = registry,
  scenario_ids = if (length(scenario_ids)) scenario_ids else NULL,
  kappa = parse_number(arg_value("kappa")),
  tau0 = parse_number(arg_value("tau0")),
  zeta2 = parse_number_or_inf(arg_value("zeta2")),
  a_sigma = parse_number(arg_value("a_sigma")),
  b_sigma = parse_number(arg_value("b_sigma")),
  alpha_prior_mean = as.character(arg_value("alpha_prior_mean")),
  alpha_prior_sd = parse_number_or_inf(arg_value("alpha_prior_sd")),
  alpha_min_spacing = parse_number(arg_value("alpha_min_spacing")),
  vb_max_iter = vb_max_iter,
  adaptive_vb_max_iter_grid = adaptive_grid,
  rhs_vb_inner = parse_int(arg_value("rhs_vb_inner")),
  vb_tol = parse_number(arg_value("vb_tol")),
  refit_stride = parse_int(arg_value("refit_stride")),
  forecast_origin_stride = parse_int(arg_value("forecast_origin_stride")),
  max_origins_per_scenario = max_origins
)

cat(sprintf("Joint-QVP synthetic DGP Phase 3 forecast-validation artifacts written to %s\n", result$out_dir))
cat(sprintf("Fixture source: %s\n", result$fixture_dir))
cat(sprintf("Scenarios: %s\n", length(unique(result$run_config$scenario_id))))
cat(sprintf("Forecast origins: %s\n", nrow(result$forecast_origin_config)))
cat("Gate counts:\n")
print(table(result$forecast_validation_assessment$gate_status))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
