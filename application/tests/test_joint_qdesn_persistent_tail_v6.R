#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application", "R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application", "scripts",
  "_joint_qdesn_persistent_tail_v6_bootstrap.R"))

contract <- app_joint_pht6_read_contract()
stopifnot(
  contract$version == "joint_qdesn_persistent_tail_v6",
  contract$v5_winner_id == "persistent_heavy_tail__fitfirst_v4_3242",
  contract$v5_secondary_id == "persistent_heavy_tail__fitfirst_v4_2430",
  identical(contract$tau3, c(0.05, 0.5, 0.95)),
  identical(contract$tau7, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)),
  length(contract$tail_multipliers) == 15L,
  contract$qualification_triplets == 12L,
  contract$qualification_replicates == 3L,
  contract$sealed_replicates == 10L,
  contract$seven_replicates == 5L,
  contract$max_physical_workers == 15L,
  !contract$automatic_downstream_launch,
  contract$promote_any_strict_mean_improvement,
  !contract$interval_overlap_is_equivalence)

component <- function(tau, profile, fit, h1, rec, score) data.frame(
  scenario_id = contract$scenario_id, candidate_id = contract$v5_winner_id,
  D = 4L, n = "6;10;14;18", n_tilde = "6;10;14", retained_state_budget = 48L,
  response_lags = 2L, alpha = "0.39;0.64;0.90;0.9995",
  rho = "0.01;0.16;0.39;0.61", pi_w = "0.005;0.005;0.005;0.005",
  pi_in = "0.25;0.25;0.25;0.25", input_scale = 0.075, reservoir_seed = 1L,
  profile_id = profile, prior_spec_id = profile, quantile_spec_id = paste0(profile, "_", tau),
  normal_rhs_tau0 = 1, rhs_tau0 = c(`0.05` = 0.03, `0.5` = 0.1, `0.95` = 0.3)[[as.character(tau)]],
  rhs_zeta2_profile = "64", rhs_zeta2_fixed = 64,
  al_tau0_multiplier = c(`0.05` = 0.03, `0.5` = 0.1, `0.95` = 0.3)[[as.character(tau)]],
  tau = tau, training_quantile_mae = fit, horizon1_quantile_mae = h1,
  recursive_quantile_mae = rec, dgp_expected_quantile_score = score,
  hard_functional_pass = TRUE, stringsAsFactors = FALSE)

lower <- component(0.05, "lower", 0.09, 0.10, 0.40, 0.20)
median <- component(0.5, "median", 0.03, 0.04, 0.45, 0.70)
upper <- component(0.95, "upper", 0.10, 0.11, 0.50, 0.30)
triplet <- app_joint_pht6_triplet_from_components(lower, median, upper, "unit_challenger")
stopifnot(nrow(triplet) == 1L, triplet$lower_rhs_tau0 == 0.03,
  triplet$median_rhs_tau0 == 0.1, triplet$upper_rhs_tau0 == 0.3,
  app_joint_pht6_prior_row(triplet, 0.10)$rhs_tau0 == 0.03,
  app_joint_pht6_prior_row(triplet, 0.25)$rhs_tau0 == 0.1,
  app_joint_pht6_prior_row(triplet, 0.90)$rhs_tau0 == 0.3)

fixtures <- data.frame(replicate_id = 1:3, dgp_seed = 101:103,
  fixture_path = paste0("/tmp/v6_fixture_", 1:3, ".rds"), stringsAsFactors = FALSE)
plan <- app_joint_pht6_component_plan(triplet, fixtures, "qualification", 1:10)
stopifnot(nrow(plan) == 9L, identical(plan$qualification_worker_id, 1:9),
  all(table(plan$replicate_id) == 3L), all(table(plan$tau) == 3L),
  all(plan$origin_indices == "1;2;3;4;5;6;7;8;9;10"))

make_replicates <- function(id, candidate, role, score, fit_scale = 1, hard = TRUE,
    crossing = 0L) data.frame(triplet_id = id, candidate_id = candidate,
  triplet_role = role, replicate_id = 1:3,
  lower_fit_mae = 0.10 * fit_scale, median_fit_mae = 0.03,
  upper_fit_mae = 0.11 * fit_scale, lower_horizon1_mae = 0.10,
  median_horizon1_mae = 0.04, upper_horizon1_mae = 0.11,
  lower_recursive_mae = 0.40, median_recursive_mae = 0.45,
  upper_recursive_mae = 0.50, dgp_score = score + c(-0.001, 0, 0.001),
  realized_score = score + 0.01, raw_crossing_pairs = 0L,
  contract_crossing_pairs = crossing, hard_functional_pass = hard,
  convergence_review = FALSE, stringsAsFactors = FALSE)

replicates <- app_bind_rows_fill(list(
  make_replicates("baseline", contract$v5_winner_id, "v5_frozen_control", 0.44),
  make_replicates("forecast", "new_forecast", "screen_best_by_architecture", 0.43),
  make_replicates("fit", "new_fit", "screen_best_by_architecture", 0.442, 0.80),
  make_replicates("bad", "bad_crossing", "screen_best_by_architecture", 0.40, 1, TRUE, 1L)))
aggregate <- app_joint_pht6_qualification_gates(
  app_joint_pht6_triplet_aggregate(replicates), contract)
stopifnot(aggregate$strict_forecast_improvement[aggregate$triplet_id == "forecast"],
  aggregate$fit_frontier[aggregate$triplet_id == "fit"],
  aggregate$score_noninferior[aggregate$triplet_id == "fit"],
  !aggregate$hard_eligible[aggregate$triplet_id == "bad"])

launcher <- paste(readLines(file.path(repo_root, "application", "scripts",
  "launch_joint_qdesn_persistent_tail_v6_stage.sh"), warn = FALSE), collapse = "\n")
stopifnot(grepl("<= 15", launcher, fixed = TRUE), grepl("taskset -c", launcher, fixed = TRUE),
  grepl("OMP_NUM_THREADS=1", launcher, fixed = TRUE),
  grepl("QUALIFICATION_COMPLETE_SEALED_AUTHORIZED", launcher, fixed = TRUE),
  !grepl("finalize_joint_qdesn_persistent_tail_v6_stage", launcher, fixed = TRUE))

cat("JOINT_PERSISTENT_TAIL_V6_TEST_PASS expectations=39 production_runs=0\n")
