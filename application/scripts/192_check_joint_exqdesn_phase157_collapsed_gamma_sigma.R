#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R",
  "joint_qdesn_simulation_validation.R", "joint_qdesn_vb_spec_screening.R",
  "joint_qdesn_calibration_screening.R", "joint_qdesn_mcmc_readiness.R",
  "joint_exqdesn_trace_tools.R", "joint_exqdesn_phase156_collapsed_gamma_sigma.R"
)) source(app_path("application/R", file))
args <- app_parse_args(list(
  freeze_dir = "application/cache/joint_qdesn_phase156b_collapsed_gamma_sigma_recovery_freeze_20260802",
  output_dir = "",
  orchestration_dir = "application/cache/joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802_orchestration"
))
value <- function(name) args[[gsub("_", "-", name, fixed = TRUE)]] %||% args[[name]]
freeze_dir <- as.character(value("freeze_dir"))[[1L]]
freeze_dir <- normalizePath(if (grepl("^/", freeze_dir)) freeze_dir else app_path(freeze_dir), mustWork = TRUE)
orchestration_dir <- as.character(value("orchestration_dir"))[[1L]]
orchestration_dir <- if (nzchar(orchestration_dir)) {
  normalizePath(if (grepl("^/", orchestration_dir)) orchestration_dir else app_path(orchestration_dir), mustWork = FALSE)
} else NULL
health <- app_joint_exqdesn_phase157_health(freeze_dir, orchestration_dir)
print(health$summary, row.names = FALSE)
by_scenario <- stats::aggregate(
  list(complete = health$inventory$state == "complete_verified"),
  list(scenario_id = health$inventory$scenario_id), sum
)
by_scenario$planned <- as.integer(table(health$inventory$scenario_id)[by_scenario$scenario_id])
by_scenario$remaining <- by_scenario$planned - by_scenario$complete
for (state in c("running", "failed", "skipped_after_abort", "incomplete", "queued")) {
  counts <- stats::aggregate(
    list(value = health$inventory$state == state),
    list(scenario_id = health$inventory$scenario_id), sum
  )
  names(counts)[[2L]] <- state
  by_scenario <- merge(by_scenario, counts, by = "scenario_id", all.x = TRUE, sort = FALSE)
}
print(by_scenario, row.names = FALSE)
output_dir <- as.character(value("output_dir"))[[1L]]
if (nzchar(output_dir)) {
  output_dir <- normalizePath(if (grepl("^/", output_dir)) output_dir else app_path(output_dir), mustWork = FALSE)
  app_ensure_dir(output_dir)
  app_joint_qvp_write_csv(health$summary, file.path(output_dir, "health_summary.csv"))
  app_joint_qvp_write_csv(health$inventory, file.path(output_dir, "chain_inventory.csv"))
  app_joint_qvp_write_csv(by_scenario, file.path(output_dir, "scenario_progress.csv"))
}
