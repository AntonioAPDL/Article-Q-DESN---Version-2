repo_root <- normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))), "..", ".."))
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

phase149_dir <- app_joint_exqdesn_phase149_default_dir()
readiness_dir <- app_joint_exqdesn_phase149_default_readiness_dir()
phase149_audit_dir <- file.path(phase149_dir, "phase149_result_audit")
needed <- c(
  file.path(phase149_dir, "artifact_manifest.csv"),
  file.path(readiness_dir, "phase149_case_specific_screening_registry.csv"),
  file.path(phase149_audit_dir, "phase149_result_assessment.csv"),
  file.path(phase149_audit_dir, "phase149_candidate_ranking.csv"),
  file.path(phase149_audit_dir, "phase149_scenario_summary.csv")
)
if (!all(file.exists(needed))) {
  cat("Phase150 case-specific MCMC freeze test skipped: Phase149 artifacts are not available.\n")
  quit(status = 0, save = "no")
}

out_dir <- tempfile("phase150_freeze_")
mcmc_dir <- tempfile("phase150_mcmc_")
result <- app_joint_exqdesn_run_phase150_mcmc_freeze(
  out_dir = out_dir,
  phase149_dir = phase149_dir,
  readiness_dir = readiness_dir,
  phase149_audit_dir = phase149_audit_dir,
  mcmc_dir = mcmc_dir,
  n_chains = 8L,
  mcmc_n_iter = 8000L,
  mcmc_burn = 2000L,
  mcmc_thin = 4L,
  n_cores = 8L
)

stopifnot(identical(result$assessment$gate_status[[1L]], "pass"))
stopifnot(nrow(result$controls) == 8L)
stopifnot(length(unique(result$controls$scenario_ids)) == 8L)
stopifnot(all(result$controls$model_ids == "joint_exqdesn_rhs_vb"))
stopifnot(all(result$controls$phase121_selection_status == "phase150_selected_from_phase149_case_specific_vb"))
stopifnot(!any(result$controls$phase149_contract_crossing_pairs > 0L))
stopifnot(!any(result$controls$phase149_raw_crossing_pairs > 0L))
stopifnot(!any(result$controls$phase149_reached_max_iter))

loaded <- app_joint_qdesn_phase122_load_phase121(result$out_dir)
stopifnot(nrow(loaded$controls) == 8L)
stopifnot(all(loaded$manifest_verification$status == "pass"))
stopifnot(file.exists(file.path(result$out_dir, "phase150_mcmc_launch_plan.csv")))
stopifnot(grepl("125_run_joint_qdesn_phase122_mcmc_case_confirmation.R", result$launch_plan$command[[1L]], fixed = TRUE))
stopifnot(result$launch_plan$n_chains[[1L]] == 8L)

orchestration_dir <- tempfile("phase150_orchestration_")
dir.create(orchestration_dir, recursive = TRUE)
running_status <- app_joint_exqdesn_phase150_lifecycle_status(
  mcmc_dir = mcmc_dir,
  freeze_dir = result$out_dir,
  orchestration_dir = orchestration_dir,
  session_alive = TRUE,
  runner_process_count = 9L
)
stopifnot(identical(running_status$lifecycle_state[[1L]], "running"))
stopifnot(identical(running_status$recommendation[[1L]], "preserve_active_run_and_recheck_later"))

interrupted_status <- app_joint_exqdesn_phase150_lifecycle_status(
  mcmc_dir = mcmc_dir,
  freeze_dir = result$out_dir,
  orchestration_dir = orchestration_dir,
  session_alive = FALSE,
  runner_process_count = 0L
)
stopifnot(identical(interrupted_status$lifecycle_state[[1L]], "interrupted_or_stale"))

dir.create(mcmc_dir, recursive = TRUE)
utils::write.csv(data.frame(case_id = "test_case"), file.path(mcmc_dir, "mcmc_case_summary.csv"), row.names = FALSE)
utils::write.csv(data.frame(case_id = "test_case", gate_status = "pass"), file.path(mcmc_dir, "mcmc_case_assessment.csv"), row.names = FALSE)
utils::write.csv(data.frame(label = "test"), file.path(mcmc_dir, "artifact_manifest.csv"), row.names = FALSE)
writeLines("0", file.path(orchestration_dir, "phase150_mcmc.exit"))
audit_in_progress_status <- app_joint_exqdesn_phase150_lifecycle_status(
  mcmc_dir = mcmc_dir,
  freeze_dir = result$out_dir,
  orchestration_dir = orchestration_dir,
  session_alive = TRUE,
  runner_process_count = 1L
)
stopifnot(identical(audit_in_progress_status$lifecycle_state[[1L]], "completed_audit_in_progress"))
stopifnot(identical(audit_in_progress_status$recommendation[[1L]], "preserve_automatic_post_run_audit"))

writeLines("1", file.path(orchestration_dir, "phase150_mcmc.exit"))
failed_status <- app_joint_exqdesn_phase150_lifecycle_status(
  mcmc_dir = mcmc_dir,
  freeze_dir = result$out_dir,
  orchestration_dir = orchestration_dir
)
stopifnot(identical(failed_status$lifecycle_state[[1L]], "failed"))

cat("Joint exQDESN Phase150 case-specific MCMC confirmation freeze tests passed.\n")
