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
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_vb_spec_screening.R", "joint_qdesn_calibration_screening.R",
  "joint_qdesn_mcmc_readiness.R", "joint_exqdesn_phase148_target_invariance.R",
  "joint_exqdesn_phase149_case_specific_screening.R",
  "joint_exqdesn_phase150_case_specific_mcmc_confirmation.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  mcmc_dir = "application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727",
  freeze_dir = "application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_freeze_20260727",
  orchestration_dir = "application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727_orchestration",
  session_name = "joint_qdesn_phase150_exal_mcmc_20260727",
  finalize = "true"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

resolve_path <- function(path, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

parse_flag <- function(x) {
  value <- tolower(trimws(as.character(x)[[1L]]))
  if (!value %in% c("true", "false")) stop("Expected true or false.", call. = FALSE)
  identical(value, "true")
}

mcmc_dir <- resolve_path(arg_value("mcmc_dir"))
freeze_dir <- resolve_path(arg_value("freeze_dir"))
orchestration_dir <- resolve_path(arg_value("orchestration_dir"))
app_ensure_dir(orchestration_dir)
session_name <- as.character(arg_value("session_name"))[[1L]]

session_alive <- identical(
  system2("tmux", c("has-session", "-t", session_name), stdout = FALSE, stderr = FALSE),
  0L
)
process_lines <- suppressWarnings(system2(
  "pgrep",
  c("-af", "125_run_joint_qdesn_phase122_mcmc_case_confirmation.R"),
  stdout = TRUE,
  stderr = FALSE
))
runner_process_count <- sum(grepl(
  "--file=application/scripts/125_run_joint_qdesn_phase122_mcmc_case_confirmation.R",
  process_lines,
  fixed = TRUE
))

status <- app_joint_exqdesn_phase150_lifecycle_status(
  mcmc_dir = mcmc_dir,
  freeze_dir = freeze_dir,
  orchestration_dir = orchestration_dir,
  session_alive = session_alive,
  runner_process_count = runner_process_count
)

if (identical(status$lifecycle_state[[1L]], "completed_pending_audit") && parse_flag(arg_value("finalize"))) {
  audit <- app_joint_exqdesn_phase150_audit_mcmc_output(
    mcmc_dir = mcmc_dir,
    freeze_dir = freeze_dir,
    out_dir = app_joint_exqdesn_phase150_default_audit_dir(mcmc_dir)
  )
  status <- app_joint_exqdesn_phase150_lifecycle_status(
    mcmc_dir = mcmc_dir,
    freeze_dir = freeze_dir,
    orchestration_dir = orchestration_dir,
    session_alive = FALSE,
    runner_process_count = 0L
  )
  status$post_run_audit_gate <- audit$assessment$gate_status[[1L]]
} else {
  status$post_run_audit_gate <- NA_character_
}

status$observed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
status_path <- file.path(orchestration_dir, "phase150_health_snapshot.csv")
app_joint_qvp_write_csv(status, status_path)

cat(sprintf("Phase150 lifecycle state: %s\n", status$lifecycle_state[[1L]]))
cat(sprintf("Recommendation: %s\n", status$recommendation[[1L]]))
cat(sprintf("Finalized cases: %s/%s\n", status$finalized_case_rows[[1L]], status$expected_cases[[1L]]))
cat(sprintf("Runner processes observed: %s\n", status$runner_process_count[[1L]]))
cat(sprintf("Health snapshot: %s\n", normalizePath(status_path, mustWork = TRUE)))

if (status$lifecycle_state[[1L]] %in% c("failed", "completed_missing_mcmc_artifacts")) {
  quit(status = 1L, save = "no")
}
