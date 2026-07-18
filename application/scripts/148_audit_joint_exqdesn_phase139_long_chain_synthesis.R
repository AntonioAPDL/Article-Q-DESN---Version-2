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
source(app_path("application/R/joint_exqdesn_trace_tools.R"))
source(app_path("application/R/joint_exqdesn_phase136_gamma_kernel_packet.R"))
source(app_path("application/R/joint_exqdesn_phase137_gamma_kernel_readiness.R"))
source(app_path("application/R/joint_exqdesn_phase139_long_chain_synthesis.R"))

args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase139_exal_long_chain_synthesis_20260717",
  phase135_screening_dir = "application/cache/joint_qdesn_phase135_matched_exal_screening_20260715",
  phase135_audit_dir = "application/cache/joint_qdesn_phase135_matched_exal_screening_20260715/phase135_result_audit",
  phase136_dir = "application/cache/joint_qdesn_phase136_exal_gamma_kernel_packet_20260715",
  phase137_dir = "application/cache/joint_qdesn_phase137_exal_gamma_kernel_readiness_20260716",
  phase138_bounded_dir = "application/cache/joint_qdesn_phase138_exal_selected_long_chain_confirmation_20260716_bounded_w4",
  phase138_logit_dir = "application/cache/joint_qdesn_phase138_exal_selected_long_chain_confirmation_20260716_logit_w4",
  phase138_orchestration_dir = "application/cache/joint_qdesn_phase138_selected_long_chain_confirmation_20260716_orchestration"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

result <- app_joint_exqdesn_run_phase139_long_chain_synthesis(
  out_dir = arg_value("output_dir"),
  phase135_screening_dir = arg_value("phase135_screening_dir"),
  phase135_audit_dir = arg_value("phase135_audit_dir"),
  phase136_dir = arg_value("phase136_dir"),
  phase137_dir = arg_value("phase137_dir"),
  phase138_dirs = c(
    bounded_w4 = arg_value("phase138_bounded_dir"),
    logit_w4 = arg_value("phase138_logit_dir")
  ),
  phase138_orchestration_dir = arg_value("phase138_orchestration_dir")
)

cat(sprintf("Phase139 long-chain synthesis artifacts written to %s\n", result$out_dir))
cat("\nDecision:\n")
print(result$decision, row.names = FALSE)
cat("\nHealth summary:\n")
print(result$health[, c("check", "status", "observed")], row.names = FALSE)
cat("\nPhase138 vs Phase136 forecast deltas:\n")
print(result$vs136[, c("scenario_id", "source_model_id", "gamma_update", "delta_forecast_mae_phase138_minus_phase136")], row.names = FALSE)
cat("\nexAL MCMC vs matched AL forecast deltas:\n")
print(result$exal_vs_al[, c("scenario_id", "source_model_id", "phase138_mcmc_minus_matched_al_forecast_mae", "interpretation")], row.names = FALSE)
cat(sprintf("\nArtifact manifest: %s\n", result$paths[["artifact_manifest"]]))
