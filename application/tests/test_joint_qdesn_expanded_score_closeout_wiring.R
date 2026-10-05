#!/usr/bin/env Rscript

file_arg <- sub("^--file=", "", commandArgs(FALSE)[grep(
  "^--file=", commandArgs(FALSE))])
repo_root <- normalizePath(file.path(dirname(file_arg), "..", ".."))
source(file.path(repo_root, "application", "scripts",
  "_joint_qdesn_recursive_mean_forecast_bootstrap.R"))

recovery_path <- file.path(repo_root, "application", "config",
  "joint_qdesn_pure_recursive_expanded_score_recovery_v1_20261004.csv")
recovery <- app_joint_recursive_read_recovery_contract(recovery_path)
stopifnot(
  recovery$recovery_worker_id == 41L,
  recovery$unchanged_worker_id == 56L,
  identical(recovery$antithetic_pair_counts, c(1L, 2L)),
  recovery$parent_contract_sha256 ==
    "bbf8b12dd05d352eb0cfa84ffc71b9510ff667a68cecc897a29991f85cd683c7",
  recovery$cell_plan_sha256 ==
    "bdd9b9406d0d0dedc468795797e9f96ca9fdb15e035eb2e4ef837634caf7dc72"
)

read_script <- function(name) paste(readLines(
  file.path(repo_root, "application", "scripts", name), warn = FALSE
), collapse = "\n")
closeout <- read_script("closeout_joint_qdesn_pure_recursive_score_review.R")
finalizer <- read_script(
  "finalize_joint_qdesn_recursive_mean_forecast.R")
recovery_launcher <- read_script(
  "launch_joint_qdesn_pure_recursive_expanded_score_recovery_jerez.sh")
review_launcher <- read_script(
  "launch_joint_qdesn_pure_recursive_expanded_score_review_jerez.sh")
materializer <- read_script(
  "prepare_joint_qdesn_pure_recursive_expanded_score_review_contract.R")
cleanup <- read_script(
  "cleanup_joint_qdesn_pure_recursive_legacy_oracles.R")
stopifnot(
  grepl("recovery_contract_path", closeout, fixed = TRUE),
  grepl("review_contract_path", finalizer, fixed = TRUE),
  grepl("allowed_review_contract_sha256", finalizer, fixed = TRUE),
  grepl("--recovery-contract-path", review_launcher, fixed = TRUE),
  grepl("--review-contract-path", review_launcher, fixed = TRUE),
  grepl("63,1,0,41", review_launcher, fixed = TRUE),
  grepl("COMPLETE_WITH_ONE_SCORE_STABILITY_REVIEW", review_launcher,
    fixed = TRUE),
  grepl('RUNTIME="${SCORE_ROOT}/score_recovery_v1"', recovery_launcher,
    fixed = TRUE),
  grepl("63 complete and worker 41 failed", materializer, fixed = TRUE),
  grepl("score_gate_multiplier", materializer, fixed = TRUE),
  grepl("required_state_trajectory_draws", materializer, fixed = TRUE),
  grepl("JEREZ_JOINT_LEGACY_STORAGE_CLEANUP_V1", cleanup, fixed = TRUE),
  grepl("current_duplicates_verified", cleanup, fixed = TRUE),
  grepl("JOINT workers or finalizers are active", cleanup, fixed = TRUE),
  grepl("current 64-cell final packet is not frozen", cleanup, fixed = TRUE)
)
cat("Expanded score closeout wiring tests passed.\n")
