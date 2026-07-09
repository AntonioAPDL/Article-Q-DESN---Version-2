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
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_fixtures.R"))

args <- app_parse_args(list(
  output_dir = "",
  registry = "",
  scenario_ids = ""
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

out_dir <- if (nzchar(as.character(arg_value("output_dir")))) {
  as.character(arg_value("output_dir"))
} else {
  app_joint_qdesn_default_simulation_fixture_dir()
}

registry_path <- if (nzchar(as.character(arg_value("registry")))) {
  as.character(arg_value("registry"))
} else {
  app_joint_qdesn_default_simulation_registry_path()
}

scenario_ids <- parse_csv(arg_value("scenario_ids"))

result <- app_joint_qdesn_materialize_simulation_fixtures(
  out_dir = out_dir,
  registry_path = registry_path,
  scenario_ids = if (length(scenario_ids)) scenario_ids else NULL
)

cat(sprintf("Joint QDESN simulation DGP fixtures written to %s\n", result$out_dir))
cat(sprintf("Registry rows: %s\n", nrow(result$registry)))
cat(sprintf("Observed rows: %s\n", result$run_config$total_observed_rows[[1L]]))
cat(sprintf("Forecast-origin rows: %s\n", nrow(result$forecast_origin_plan)))
cat("Fixture validation status counts:\n")
print(table(result$fixture_validation$status))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
cat("Model fitting launched: FALSE\n")
