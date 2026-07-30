#!/usr/bin/env Rscript

script_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
repo_root <- normalizePath(file.path(dirname(normalizePath(script_arg)), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_vb_spec_screening.R", "joint_exqdesn_phase149_case_specific_screening.R",
  "latent_path_design.R", "joint_exqdesn_phase151_feature_design_screening.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  output_dir = app_joint_exqdesn_phase151_default_dir(),
  readiness_dir = app_joint_exqdesn_phase151_default_readiness_dir(),
  orchestration_dir = app_joint_exqdesn_phase151_default_orchestration_dir(),
  session_name = "joint_exqdesn_phase151_feature_screen_20260728",
  finalize = "false"
))
value <- function(hyphen, underscore) args[[hyphen]] %||% args[[underscore]]
session_name <- value("session-name", "session_name")
session_alive <- identical(
  suppressWarnings(system2("tmux", c("has-session", "-t", session_name), stdout = FALSE, stderr = FALSE)),
  0L
)
process_lines <- suppressWarnings(system2(
  "pgrep",
  c("-af", "[1]70_run_joint_exqdesn_phase151_feature_design_screening.R"),
  stdout = TRUE, stderr = FALSE
))
health <- app_joint_exqdesn_phase151_health(
  out_dir = value("output-dir", "output_dir"),
  readiness_dir = value("readiness-dir", "readiness_dir"),
  session_alive = session_alive,
  runner_process_count = length(process_lines)
)
if (app_as_bool(args$finalize) &&
    health$lifecycle_state[[1L]] == "completed_pending_aggregation") {
  app_joint_exqdesn_phase151_aggregate(
    value("output-dir", "output_dir"),
    value("readiness-dir", "readiness_dir")
  )
  health <- app_joint_exqdesn_phase151_health(
    out_dir = value("output-dir", "output_dir"),
    readiness_dir = value("readiness-dir", "readiness_dir"),
    session_alive = FALSE,
    runner_process_count = 0L
  )
}
orchestration_dir <- value("orchestration-dir", "orchestration_dir")
app_ensure_dir(orchestration_dir)
app_joint_qvp_write_csv(health, file.path(orchestration_dir, "phase151_health_summary.csv"))
print(health)
