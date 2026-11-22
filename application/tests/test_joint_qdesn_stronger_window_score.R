#!/usr/bin/env Rscript
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."))
source(file.path(repo_root, "application/scripts/_joint_qdesn_stronger_window_bootstrap.R"))

contract <- app_joint_swscore_contract()
tau <- app_joint_swscore_numvec(contract, "quantile_grid")
weights <- app_joint_swscore_numvec(contract, "trapezoidal_weights")
stopifnot(
  identical(tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)),
  identical(weights, c(0.025, 0.100, 0.200, 0.250, 0.200, 0.100, 0.025)),
  abs(sum(weights) - 0.9) < 1e-12,
  app_joint_swscore_value(contract, "canonical_forecast_policy") == "recursive_mean_state",
  app_joint_swscore_value(contract, "sensitivity_forecast_policy") == "recursive_path",
  app_joint_swscore_value(contract, "promotion_unit") == "complete_four_model_scenario_packet"
)

prepare_body <- paste(deparse(app_joint_swscore_finalize_mcmc), collapse = "\n")
score_body <- paste(deparse(app_joint_swscore_run_cell), collapse = "\n")
oracle_final_body <- paste(deparse(app_joint_swscore_finalize_oracle), collapse = "\n")
final_body <- paste(deparse(app_joint_swscore_finalize), collapse = "\n")
stopifnot(
  grepl("nrow(summary) != 192L", prepare_body, fixed = TRUE),
  grepl("M0_v_collapsed_support_logit", prepare_body, fixed = TRUE),
  grepl("score_launch_readiness.csv", score_body, fixed = TRUE),
  grepl("app_joint_recursive_mean_design", score_body, fixed = TRUE),
  grepl("app_joint_pure_recursive_path_score_draws", score_body, fixed = TRUE),
  grepl("Oracle worker %d manifest is not verified", oracle_final_body, fixed = TRUE),
  grepl("interval_overlap_is_equivalence = FALSE", final_body, fixed = TRUE),
  grepl("promote_complete_challenger_packet", final_body, fixed = TRUE)
)

cat("Stronger-window score tests passed.\n")
