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
  artifact_dir = "",
  output_dir = ""
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

artifact_dir <- if (nzchar(as.character(arg_value("artifact_dir")))) {
  as.character(arg_value("artifact_dir"))
} else {
  app_path("application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_20260702")
}
out_dir <- if (nzchar(as.character(arg_value("output_dir")))) as.character(arg_value("output_dir")) else NULL

result <- app_joint_qvp_audit_synthetic_dgp_forecast_crossings(
  artifact_dir = artifact_dir,
  out_dir = out_dir
)

cat(sprintf("Joint-QVP synthetic DGP Phase 4c crossing audit written to %s\n", result$out_dir))
cat(sprintf("Audited Phase 3 directory: %s\n", result$phase3_dir))
cat(sprintf("Crossing event rows: %s\n", nrow(result$crossing_event_audit)))
cat(sprintf("Crossing pair rows: %s\n", nrow(result$crossing_pair_detail)))
cat(sprintf("Gate: %s\n", result$crossing_remediation_recommendation$gate_status[[1L]]))
cat(sprintf("Recommendation: %s\n", result$crossing_remediation_recommendation$recommendation_status[[1L]]))
cat("Recommended follow-up command:\n")
cat(result$crossing_remediation_recommendation$recommended_followup_command[[1L]], "\n")
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
