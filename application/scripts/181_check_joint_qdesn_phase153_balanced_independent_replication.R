#!/usr/bin/env Rscript

script_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
repo_root <- normalizePath(file.path(dirname(normalizePath(script_arg)), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_phase153_balanced_independent_replication.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  output_dir = app_joint_qdesn_phase153_default_vb_dir(),
  readiness_dir = app_joint_qdesn_phase153_default_readiness_dir(),
  orchestration_dir = app_joint_qdesn_phase153_default_orchestration_dir(),
  session_name = "joint_qdesn_phase153_balanced_replication_20260729"
))
value <- function(hyphen, underscore) args[[hyphen]] %||% args[[underscore]]

health <- app_joint_qdesn_phase153_health(
  readiness_dir = value("readiness-dir", "readiness_dir"),
  out_dir = value("output-dir", "output_dir"),
  orchestration_dir = value("orchestration-dir", "orchestration_dir"),
  session_name = value("session-name", "session_name")
)
print(health)
if (health$lifecycle_state[[1L]] == "incomplete_not_running") quit(status = 2L)
