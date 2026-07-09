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
  audit_dir = "",
  article_freeze_dir = ""
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

out_dir <- if (nzchar(as.character(arg_value("output_dir")))) {
  as.character(arg_value("output_dir"))
} else {
  app_joint_qvp_default_synthetic_dgp_phase4j_launch_dir()
}
audit_dir <- if (nzchar(as.character(arg_value("audit_dir")))) {
  as.character(arg_value("audit_dir"))
} else {
  file.path(out_dir, "phase4j_launch_audit")
}
article_freeze_dir <- if (nzchar(as.character(arg_value("article_freeze_dir")))) {
  as.character(arg_value("article_freeze_dir"))
} else {
  app_joint_qvp_default_synthetic_dgp_phase4j_freeze_dir()
}

result <- app_joint_qvp_audit_synthetic_dgp_phase4j_tau0_candidate_launch(
  out_dir = out_dir,
  audit_dir = audit_dir,
  article_freeze_dir = article_freeze_dir
)

cat(sprintf("Joint-QVP synthetic DGP Phase 4j launch audit written to %s\n", result$audit_dir))
cat(sprintf("Audit gate: %s\n", result$health$audit_gate_status[[1L]]))
cat(sprintf("Selected arm: %s\n", result$decision$selected_arm_id[[1L]]))
cat(sprintf("Selected tau0: %s\n", result$decision$selected_tau0[[1L]]))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
