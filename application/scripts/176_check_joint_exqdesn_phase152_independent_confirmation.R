#!/usr/bin/env Rscript

script_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
repo_root <- normalizePath(file.path(dirname(normalizePath(script_arg)), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_vb_spec_screening.R", "joint_qdesn_mcmc_readiness.R",
  "joint_exqdesn_trace_tools.R",
  "joint_exqdesn_phase149_case_specific_screening.R",
  "joint_exqdesn_phase150_case_specific_mcmc_confirmation.R",
  "latent_path_design.R", "joint_exqdesn_phase151_feature_design_screening.R",
  "joint_exqdesn_phase152_independent_confirmation.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  readiness_dir = app_joint_exqdesn_phase152_default_readiness_dir(),
  vb_dir = app_joint_exqdesn_phase152_default_vb_dir(),
  mcmc_dir = app_joint_exqdesn_phase152_default_mcmc_dir(),
  orchestration_dir = app_joint_exqdesn_phase152_default_orchestration_dir(),
  session_name = "joint_exqdesn_phase152_confirmation_20260729"
))
value <- function(hyphen, underscore) args[[hyphen]] %||% args[[underscore]]
session_name <- value("session-name", "session_name")
session_alive <- nzchar(Sys.which("tmux")) &&
  system2("tmux", c("has-session", "-t", session_name),
          stdout = FALSE, stderr = FALSE) == 0L
pattern <- "[1]74_run_joint_exqdesn_phase152_vb_confirmation|[1]75_run_joint_exqdesn_phase152_mcmc_confirmation"
runner_count <- suppressWarnings(as.integer(system(
  sprintf("pgrep -af %s | wc -l", shQuote(pattern)), intern = TRUE
)))
if (!is.finite(runner_count)) runner_count <- 0L
health <- app_joint_exqdesn_phase152_health(
  readiness_dir = value("readiness-dir", "readiness_dir"),
  vb_dir = value("vb-dir", "vb_dir"),
  mcmc_dir = value("mcmc-dir", "mcmc_dir"),
  session_alive = session_alive,
  runner_process_count = runner_count
)
orchestration_dir <- value("orchestration-dir", "orchestration_dir")
app_ensure_dir(orchestration_dir)
app_joint_qvp_write_csv(
  health, file.path(orchestration_dir, "phase152_health_summary.csv")
)
print(health, row.names = FALSE)
