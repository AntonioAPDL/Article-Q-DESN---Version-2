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
  launch_dir = "",
  audit_dir = "",
  freeze_dir = "",
  copy_large_forecast_files = "false",
  expected_selected_arm = "tau0_0p15_comparator",
  allow_selected_arm_override = "false"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

launch_dir <- if (nzchar(as.character(arg_value("launch_dir")))) {
  as.character(arg_value("launch_dir"))
} else {
  app_joint_qvp_default_synthetic_dgp_phase4j_launch_dir()
}
audit_dir <- if (nzchar(as.character(arg_value("audit_dir")))) {
  as.character(arg_value("audit_dir"))
} else {
  file.path(launch_dir, "phase4j_launch_audit")
}
freeze_dir <- if (nzchar(as.character(arg_value("freeze_dir")))) {
  as.character(arg_value("freeze_dir"))
} else {
  app_joint_qvp_default_synthetic_dgp_phase4j_freeze_dir()
}

result <- app_joint_qvp_freeze_synthetic_dgp_phase4k_article_candidate(
  launch_dir = launch_dir,
  audit_dir = audit_dir,
  freeze_dir = freeze_dir,
  copy_large_forecast_files = app_as_bool(arg_value("copy_large_forecast_files")),
  expected_selected_arm = as.character(arg_value("expected_selected_arm")),
  allow_selected_arm_override = app_as_bool(arg_value("allow_selected_arm_override"))
)

cat(sprintf("Joint-QVP synthetic DGP Phase 4k article-candidate freeze written to %s\n", result$freeze_dir))
cat(sprintf("Selected arm: %s\n", result$freeze_decision$selected_arm_id[[1L]]))
cat(sprintf("Selected tau0: %s\n", result$freeze_decision$selected_tau0[[1L]]))
cat(sprintf("Freeze gate: %s\n", result$freeze_decision$freeze_gate_status[[1L]]))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
