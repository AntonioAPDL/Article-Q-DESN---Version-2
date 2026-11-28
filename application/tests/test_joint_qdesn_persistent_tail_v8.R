#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application", "R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application", "scripts", "_joint_qdesn_persistent_tail_v8_bootstrap.R"))

ct <- app_joint_pht8_read_contract(); arms <- app_joint_pht8_arms(ct)
stopifnot(ct$version == "joint_qdesn_persistent_tail_v8_joint_prior_calibration",
  ct$v7_parent_head == "6aa48ea681df6fe2e32636fb70ed9ff5176085f3",
  ct$candidate_id == "persistent_heavy_tail__fitfirst_v4_2430",
  identical(ct$tau, c(.05, .10, .25, .50, .75, .90, .95)),
  abs(sum(ct$weights) - .9) < 1e-12, ct$screen_replicates == 3L,
  ct$qualification_replicates == 5L, ct$chains_per_cell == 3L,
  ct$oracle_max_shards == 8L,
  ct$exal_method == "M0_v_collapsed_support_logit",
  !ct$scalar_mixing_is_hard_gate, ct$protected_selection_forbidden,
  ct$architecture_changes_forbidden, !ct$automatic_downstream_launch)

stopifnot(nrow(arms) == 105L, sum(arms$baseline) == 1L, sum(arms$sentinel) == 10L,
  setequal(unique(arms$anchor_tau0), ct$anchor_tau0),
  setequal(unique(arms$innovation_tau0), ct$innovation_tau0),
  setequal(unique(arms$slab_profile), ct$slab_profiles))
baseline <- arms[arms$baseline, , drop = FALSE]
stopifnot(baseline$anchor_tau0 == 1e-7, baseline$innovation_tau0 == 1e-13,
  baseline$anchor_zeta2 == .01, baseline$innovation_zeta2 == .01)

fixtures <- app_joint_pht8_fixture_plan(ct)
stopifnot(nrow(fixtures) == 9L, sum(fixtures$panel == "sentinel") == 1L,
  sum(fixtures$panel == "screen") == 3L,
  sum(fixtures$panel == "qualification") == 5L,
  !anyDuplicated(fixtures$seed_offset))
screen <- merge(expand.grid(context_id = fixtures$context_id[fixtures$panel == "screen"],
  likelihood_family = "AL"), arms, by = NULL)
sentinel <- merge(expand.grid(context_id = fixtures$context_id[fixtures$panel == "sentinel"],
  likelihood_family = c("AL", "exAL")), arms[arms$sentinel, ], by = NULL)
stopifnot(nrow(screen) == 315L, nrow(sentinel) == 20L)

# Internal selection forecasts are teacher-forced across ten origins and recursive within 30 steps.
mock_design <- list(row_meta = data.frame(full_time_index = 1:1800),
  calibration_local = 1501:1800)
forecast_map <- app_joint_pht8_internal_forecast_map(mock_design)
stopifnot(nrow(forecast_map) == 300L, identical(unique(forecast_map$origin_index), 1:10),
  all(table(forecast_map$origin_index) == 30L),
  identical(forecast_map$horizon, rep(1:30, times = 10L)),
  identical(forecast_map$full_time_index, 1501:1800))
bad_design <- mock_design
bad_design$calibration_local <- 1501:1799
error <- tryCatch({ app_joint_pht8_internal_forecast_map(bad_design); NULL }, error = identity)
stopifnot(inherits(error, "error"))

# Oracle history keeps original indices through calibration and removes protected rows.
full_fixture <- list(y = 1:400, mu = 1:400, sigma = rep(1, 400),
  innovation = rep(0, 400), innovation_raw = rep(0, 400),
  true_q = matrix(0, 400, length(ct$tau)), Z = matrix(0, 400, 1),
  detailed_split = data.frame(full_time_index = 1:400,
    role = c(rep("fit", 300), rep("validation", 100))))
selector_fixture <- list(detailed_split = data.frame(full_time_index = 101:300))
oracle_fixture <- app_joint_pht8_internal_oracle_fixture(full_fixture, selector_fixture)
stopifnot(length(oracle_fixture$y) == 300L, nrow(oracle_fixture$true_q) == 300L,
  nrow(oracle_fixture$Z) == 300L,
  !any(oracle_fixture$detailed_split$role == "validation"))

# Plan receipts fail closed and health counts only verified DONE workers.
root <- tempfile("pht8_test_"); dir.create(root)
plan <- data.frame(worker_id = 1:2, value = c("a", "b"))
app_joint_pht8_freeze_plan(root, "sentinel_context", plan)
health <- app_joint_pht8_health(root, "sentinel_context")
stopifnot(health$expected == 2L, health$completed == 0L, health$status == "ready")
writeLines("tamper", file.path(root, "sentinel_context_plan.csv"), sep = "\n")
error <- tryCatch({ app_joint_pht8_verify_plan(root, "sentinel_context"); NULL }, error = identity)
stopifnot(inherits(error, "error")); unlink(root, recursive = TRUE)

# Complete target identity changes with every scientific prior coordinate.
mock_context <- list(design = list(scenario_id = ct$scenario_id, tau = ct$tau,
  design_fingerprint = strrep("a", 64L), train_local = 1:2,
  Z = matrix(0, 2, 1)))
hash <- app_joint_pht8_target_hash(mock_context, baseline, "AL")
altered <- baseline; altered$innovation_tau0 <- 1e-7
stopifnot(grepl("^[0-9a-f]{64}$", hash),
  hash != app_joint_pht8_target_hash(mock_context, altered, "AL"),
  hash != app_joint_pht8_target_hash(mock_context, baseline, "exAL"))
al_sampler_hash <- app_joint_pht8_sampler_hash("AL", ct)
exal_sampler_hash <- app_joint_pht8_sampler_hash("exAL", ct)
stopifnot(grepl("^[0-9a-f]{64}$", al_sampler_hash),
  grepl("^[0-9a-f]{64}$", exal_sampler_hash),
  al_sampler_hash != exal_sampler_hash,
  grepl("adaptive-gaussian-m0", ct$execution_branch, fixed = TRUE))

# Chain combination requires both posterior-target and effective-kernel identity.
metadata <- data.frame(likelihood_family = rep("exAL", 3L),
  arm_id = rep("candidate", 3L), chain_id = 1:3,
  complete_posterior_target_sha256 = rep(strrep("a", 64L), 3L),
  effective_sampler_control_sha256 = rep(exal_sampler_hash, 3L),
  stringsAsFactors = FALSE)
stopifnot(isTRUE(app_joint_pht8_validate_chain_metadata(metadata,
  "exAL", "candidate", 3L)))
incompatible <- metadata
incompatible$effective_sampler_control_sha256[[3L]] <- al_sampler_hash
error <- tryCatch({
  app_joint_pht8_validate_chain_metadata(incompatible, "exAL", "candidate", 3L)
  NULL
}, error = identity)
stopifnot(inherits(error, "error"), grepl("incompatible", conditionMessage(error)))

# Aggregation keeps fit, forecast, interval, crossing, and convergence dimensions separate.
mock <- data.frame(arm_id = rep(arms$arm_id[1:2], each = 3L), likelihood_family = "AL",
  fit_mae = rep(c(.2, .1), each = 3L), lower_fit_mae = rep(c(.3, .2), each = 3L),
  middle_fit_mae = rep(c(.1, .05), each = 3L), upper_fit_mae = rep(c(.3, .2), each = 3L),
  worst_band_fit_mae = rep(c(.3, .2), each = 3L), posterior_score_mean = rep(c(.6, .5), each = 3L),
  canonical_score = rep(c(.59, .49), each = 3L), posterior_score_interval_width = .1,
  finite_functionals = TRUE, contract_crossing_pairs = 0L, fit_contract_crossing_pairs = 0L,
  convergence_review_only = c(FALSE, TRUE, FALSE, rep(FALSE, 3L)))
aggregate <- app_joint_pht8_aggregate_vb(mock)
stopifnot(nrow(aggregate) == 2L, all(aggregate$replicate_count == 3L),
  aggregate$worst_band_fit_mae_mean[aggregate$arm_id == arms$arm_id[[2L]]] == .2,
  any(aggregate$convergence_review_any))

# Singular broad-screen arms are excluded wholesale; valid arms keep all matched replicates.
screen_failures <- data.frame(arm_id = arms$arm_id[[1L]], context_id = 1L,
  error_message = "singular", stringsAsFactors = FALSE)
classified <- app_joint_pht8_screen_eligibility(mock, screen_failures, 3L)
stopifnot(nrow(classified$eligible) == 3L,
  all(classified$eligible$arm_id == arms$arm_id[[2L]]),
  nrow(classified$disqualified) == 1L,
  classified$disqualified$whole_arm_excluded,
  classified$disqualified$disqualified_workers == 1L)

launcher <- paste(readLines(file.path(repo_root, "application", "scripts",
  "launch_joint_qdesn_persistent_tail_v8_stage.sh"), warn = FALSE), collapse = "\n")
stopifnot(grepl("jerez.be.ucsc.edu", launcher, fixed = TRUE),
  grepl("taskset -c", launcher, fixed = TRUE), grepl("OMP_NUM_THREADS=1", launcher, fixed = TRUE),
  grepl(ct$execution_branch, launcher, fixed = TRUE),
  !grepl("finalize_joint_qdesn_persistent_tail_v8_stage", launcher, fixed = TRUE))

cat("JOINT_PERSISTENT_TAIL_V8_TEST_PASS expectations=66 production_runs=0\n")
