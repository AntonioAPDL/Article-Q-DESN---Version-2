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
  phase4_dir = "",
  output_dir = "",
  article_output_dir = "",
  fallback_calibration_output_dir = ""
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

phase4_dir <- if (nzchar(as.character(arg_value("phase4_dir")))) {
  as.character(arg_value("phase4_dir"))
} else {
  app_joint_qvp_default_synthetic_dgp_forecast_calibration_dir()
}
out_dir <- if (nzchar(as.character(arg_value("output_dir")))) as.character(arg_value("output_dir")) else NULL
article_output_dir <- if (nzchar(as.character(arg_value("article_output_dir")))) {
  as.character(arg_value("article_output_dir"))
} else {
  app_path("application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_article_candidate_20260702")
}
fallback_calibration_output_dir <- if (nzchar(as.character(arg_value("fallback_calibration_output_dir")))) {
  as.character(arg_value("fallback_calibration_output_dir"))
} else {
  app_path("application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_followup_20260702")
}

result <- app_joint_qvp_audit_synthetic_dgp_forecast_calibration(
  phase4_dir = phase4_dir,
  out_dir = out_dir,
  article_output_dir = article_output_dir,
  fallback_calibration_output_dir = fallback_calibration_output_dir
)

cat(sprintf("Joint-QVP synthetic DGP Phase 4b readiness audit written to %s\n", result$out_dir))
cat(sprintf("Audited Phase 4 directory: %s\n", result$phase4_dir))
cat(sprintf("Gate: %s\n", result$calibration_readiness_summary$gate_status[[1L]]))
cat(sprintf("Recommendation: %s\n", result$article_candidate_recommendation$recommendation_status[[1L]]))
cat("Recommended next command:\n")
cat(result$article_candidate_recommendation$recommended_next_command[[1L]], "\n")
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
