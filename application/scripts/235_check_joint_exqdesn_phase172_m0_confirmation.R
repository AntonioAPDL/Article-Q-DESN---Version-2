#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)

for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R", "joint_exqdesn_trace_tools.R",
  "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_qdesn_phase153_balanced_independent_replication.R",
  "joint_qdesn_phase154_mcmc_evidence_reconciliation.R",
  "joint_qdesn_phase155_article_promotion.R",
  "joint_exqdesn_exact_structured_inference.R", "joint_exqdesn_inference_dispatch.R",
  "joint_exqdesn_phase164_165_readiness.R", "joint_exqdesn_phase166_168_structured_vb.R",
  "joint_exqdesn_phase167_169_mcmc_method_selection.R", "joint_exqdesn_phase169r_recovery.R",
  "joint_exqdesn_phase170_default_promotion.R", "joint_exqdesn_phase171_175_article_confirmation.R"
)) source(app_path("application/R", file))

dirs <- app_joint_exqdesn_phase171_175_dirs()
health <- app_joint_exqdesn_phase172_health(dirs$phase171, dirs$phase172_orchestration)
session <- "joint_exqdesn_phase172_m0_article_20260809"
tmux_status <- system2("tmux", c("has-session", "-t", session), stdout = FALSE, stderr = FALSE) == 0L
running_lines <- system2("pgrep", c("-af", "233_run_joint_exqdesn_phase172_m0_chain.R"), stdout = TRUE, stderr = FALSE)
running <- sum(grepl("Rscript", running_lines, fixed = TRUE))
health$summary$running_workers <- running
health$summary$tmux_status <- if (tmux_status) "running" else "absent"
completed_runtime <- unlist(lapply(health$plan$worker_output_dir[health$plan$state == "complete"], function(dir) {
  path <- file.path(dir, "runtime.csv")
  if (file.exists(path)) app_read_csv(path)$elapsed_seconds[[1L]] else NA_real_
}), use.names = FALSE)
completed_runtime <- completed_runtime[is.finite(completed_runtime)]
health$summary$median_completed_worker_hours <- if (length(completed_runtime)) stats::median(completed_runtime) / 3600 else NA_real_
health$summary$estimated_remaining_cpu_hours <- if (length(completed_runtime)) stats::median(completed_runtime) / 3600 * health$summary$remaining_workers else NA_real_
app_ensure_dir(dirs$phase172_orchestration)
app_joint_qvp_write_csv(health$summary, file.path(dirs$phase172_orchestration, "latest_health_summary.csv"))
app_joint_qvp_write_csv(health$by_cell, file.path(dirs$phase172_orchestration, "latest_health_by_cell.csv"))
app_joint_qvp_write_csv(health$by_wave, file.path(dirs$phase172_orchestration, "latest_health_by_wave.csv"))
print(health$summary, row.names = FALSE)
print(health$by_wave, row.names = FALSE)
