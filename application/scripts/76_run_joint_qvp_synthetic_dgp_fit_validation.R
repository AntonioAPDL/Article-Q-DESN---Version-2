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
source(app_path("application/R/joint_qvp_qdesn.R"))

args <- app_parse_args(list(
  output_dir = "",
  registry = "",
  fixture_dir = "",
  scenario_ids = "",
  smoke = "false",
  vb_max_iter = "120",
  adaptive_vb_max_iter_grid = "120,240",
  mcmc_n_iter = "60",
  mcmc_burn = "30",
  mcmc_thin = "5",
  n_chains = "2",
  mcmc_reference_scenarios = "normal_bridge,gaussian_mixture_bridge,asymmetric_laplace_tail,persistent_heavy_tail"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) {
    return(args[[hyphen_name]])
  }
  args[[name]]
}

parse_csv <- function(x) {
  out <- trimws(strsplit(as.character(x), ",", fixed = TRUE)[[1L]])
  out[nzchar(out)]
}

out_dir <- if (nzchar(as.character(arg_value("output_dir")))) {
  as.character(arg_value("output_dir"))
} else {
  app_joint_qvp_default_synthetic_dgp_fit_validation_dir()
}

registry_path <- if (nzchar(as.character(arg_value("registry")))) {
  as.character(arg_value("registry"))
} else {
  app_joint_qvp_default_synthetic_dgp_registry_path()
}

fixture_dir <- if (nzchar(as.character(arg_value("fixture_dir")))) as.character(arg_value("fixture_dir")) else NULL
scenario_ids <- parse_csv(arg_value("scenario_ids"))
registry <- NULL
if (app_as_bool(arg_value("smoke")) && is.null(fixture_dir)) {
  registry <- app_read_csv(registry_path)
  if (length(scenario_ids)) {
    missing_ids <- setdiff(scenario_ids, registry$scenario_id)
    if (length(missing_ids)) stop("Requested --scenario-ids not found in registry: ", paste(missing_ids, collapse = ", "), call. = FALSE)
    registry <- registry[registry$scenario_id %in% scenario_ids, , drop = FALSE]
  }
  registry$simulated_length <- 90L
  registry$washout_length <- 20L
  registry$train_length <- 40L
  registry$test_length <- 30L
  app_joint_qvp_validate_synthetic_dgp_registry(registry)
}

parse_int <- function(x) as.integer(as.character(x)[[1L]])
vb_max_iter <- parse_int(arg_value("vb_max_iter"))
adaptive_grid <- as.integer(parse_csv(arg_value("adaptive_vb_max_iter_grid")))
adaptive_grid <- adaptive_grid[is.finite(adaptive_grid) & adaptive_grid > 0L]
if (!length(adaptive_grid)) adaptive_grid <- vb_max_iter
mcmc_refs <- parse_csv(arg_value("mcmc_reference_scenarios"))

result <- app_joint_qvp_run_synthetic_dgp_fit_validation(
  out_dir = out_dir,
  registry_path = registry_path,
  fixture_dir = fixture_dir,
  registry = registry,
  scenario_ids = if (length(scenario_ids)) scenario_ids else NULL,
  mcmc_reference_scenarios = mcmc_refs,
  vb_max_iter = vb_max_iter,
  adaptive_vb_max_iter_grid = adaptive_grid,
  n_chains = parse_int(arg_value("n_chains")),
  mcmc_n_iter = parse_int(arg_value("mcmc_n_iter")),
  mcmc_burn = parse_int(arg_value("mcmc_burn")),
  mcmc_thin = parse_int(arg_value("mcmc_thin"))
)

cat(sprintf("Joint-QVP synthetic DGP Phase 2 fit-validation artifacts written to %s\n", result$out_dir))
cat(sprintf("Fixture source: %s\n", result$fixture_dir))
cat(sprintf("Scenarios: %s\n", length(unique(result$run_config$scenario_id))))
cat("Gate counts:\n")
print(table(result$fit_validation_assessment$gate_status))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
