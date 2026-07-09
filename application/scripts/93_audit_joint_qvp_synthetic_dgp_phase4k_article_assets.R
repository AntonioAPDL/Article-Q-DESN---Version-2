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
  freeze_dir = "",
  table_dir = "",
  figure_dir = "",
  audit_dir = "",
  expected_selected_arm = "tau0_0p15_comparator",
  expected_selected_tau0 = "0.15",
  allow_selected_arm_override = "false"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

freeze_dir <- if (nzchar(as.character(arg_value("freeze_dir")))) {
  as.character(arg_value("freeze_dir"))
} else {
  app_joint_qvp_default_synthetic_dgp_phase4j_freeze_dir()
}
table_dir <- if (nzchar(as.character(arg_value("table_dir")))) {
  as.character(arg_value("table_dir"))
} else {
  app_joint_qvp_phase4k_default_table_dir()
}
figure_dir <- if (nzchar(as.character(arg_value("figure_dir")))) {
  as.character(arg_value("figure_dir"))
} else {
  app_joint_qvp_phase4k_default_figure_dir()
}
audit_dir <- if (nzchar(as.character(arg_value("audit_dir")))) {
  as.character(arg_value("audit_dir"))
} else {
  file.path(freeze_dir, "phase4k_article_asset_audit")
}

result <- app_joint_qvp_audit_synthetic_dgp_phase4k_article_assets(
  freeze_dir = freeze_dir,
  table_dir = table_dir,
  figure_dir = figure_dir,
  audit_dir = audit_dir,
  expected_selected_arm = as.character(arg_value("expected_selected_arm")),
  expected_selected_tau0 = suppressWarnings(as.numeric(arg_value("expected_selected_tau0"))),
  allow_selected_arm_override = app_as_bool(arg_value("allow_selected_arm_override"))
)

cat(sprintf("Joint-QVP synthetic DGP Phase 4k article asset audit written to %s\n", result$audit_dir))
cat(sprintf("Audit gate: %s\n", result$audit$audit_gate_status[[1L]]))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
