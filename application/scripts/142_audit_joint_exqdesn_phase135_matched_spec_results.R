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
source(app_path("application/R/joint_exqdesn_phase135_matched_spec_readiness.R"))

args <- app_parse_args(list(
  output_dir = "",
  screening_dir = "",
  phase121_dir = "",
  phase124c_dir = ""
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

resolve_path <- function(path, default, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(path)) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

result <- app_joint_exqdesn_run_phase135_matched_spec_result_audit(
  out_dir = resolve_path(arg_value("output_dir"), app_joint_exqdesn_phase135_default_result_audit_dir(), must_work = FALSE),
  screening_dir = resolve_path(arg_value("screening_dir"), app_joint_exqdesn_phase135_default_screening_dir(), must_work = TRUE),
  phase121_dir = resolve_path(arg_value("phase121_dir"), app_joint_qdesn_default_phase121_case_vb_freeze_dir_fallback(), must_work = TRUE),
  phase124c_dir = resolve_path(arg_value("phase124c_dir"), app_joint_exqdesn_phase135_default_phase124c_dir(), must_work = TRUE)
)

cat(sprintf("Joint exQDESN Phase135 matched-spec result audit written to %s\n", result$out_dir))
cat("Decision:\n")
print(result$decision, row.names = FALSE)
cat("Matched AL vs exAL model summary:\n")
print(result$model_summary[, c(
  "comparison_class",
  "n_rows",
  "n_exal_worse_fit",
  "n_exal_worse_forecast",
  "mean_al_forecast_mae",
  "mean_exal_forecast_mae",
  "mean_forecast_delta_exal_minus_al",
  "exal_raw_crossings",
  "exal_contract_crossings",
  "decision"
)], row.names = FALSE)
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
