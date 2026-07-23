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
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_exqdesn_phase143_gamma_decision.R"))

args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase143_gamma_decision_freeze_20260723",
  phase140_dir = "application/cache/joint_qdesn_phase140_exal_fixed_gamma_zero_sensitivity_recovery_20260718",
  phase141_focus_dir = "application/cache/joint_qdesn_phase141_focus_width_sensitivity_screen_20260719",
  phase142_dir = "application/cache/joint_qdesn_phase142_regularized_gamma_screen_20260722"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

result <- app_joint_exqdesn_run_phase143_gamma_decision_freeze(
  out_dir = arg_value("output_dir"),
  phase140_dir = arg_value("phase140_dir"),
  phase141_focus_dir = arg_value("phase141_focus_dir"),
  phase142_dir = arg_value("phase142_dir")
)

cat(sprintf("Phase143 gamma decision freeze written to %s\n", result$out_dir))
cat(sprintf("Gate status: %s\n", result$decision$gate_status[[1L]]))
cat(sprintf("Sampled-gamma exAL decision: %s\n", result$decision$sampled_gamma_exal_decision[[1L]]))
cat(sprintf("Fixed-gamma exAL decision: %s\n", result$decision$fixed_gamma_exal_decision[[1L]]))
cat(sprintf(
  "Phase142 regularized beats fixed-gamma forecast MAE cases: %s/%s\n",
  result$decision$phase142_regularized_beats_fixed_forecast_cases[[1L]],
  result$decision$fixed_gamma_cases[[1L]]
))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
