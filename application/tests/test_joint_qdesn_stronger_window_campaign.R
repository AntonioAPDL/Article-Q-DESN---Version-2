#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application/scripts", "_joint_qdesn_stronger_window_bootstrap.R"))

contract <- app_joint_sw_read_contract()
axes <- app_joint_sw_read_axes()
registry <- app_joint_sw_read_registry()
stopifnot(
  contract$scenario_count == 8L,
  contract$candidate_count == 4096L,
  contract$candidate_count == contract$anchor_count + contract$local_count +
    contract$global_count + contract$mechanism_count + contract$high_capacity_count,
  identical(contract$r1a_origins, c(1L, 5L, 10L)),
  identical(contract$r1b_origins, c(1L, 3L, 5L, 7L, 9L, 10L)),
  identical(contract$full_origins, seq_len(10L)),
  contract$inner_training_rows == 1000L,
  contract$inner_calibration_rows == 300L,
  contract$protected_validation_rows == 1000L,
  identical(contract$exal_mcmc_method, "exact_M0"),
  contract$r1a_high_capacity_quota == 64L,
  contract$r1b_high_capacity_quota == 32L,
  contract$r2_high_capacity_quota == 8L,
  nrow(registry) == 8L
)

for (shape in axes$width_shape) {
  widths <- app_joint_sw_widths(8L, 20L, shape, axes$minimum_layer_width)
  stopifnot(length(widths) == 8L, sum(widths) == 20L, all(widths >= 2L))
}
stopifnot(
  identical(app_joint_sw_widths(1L, 24L, "flat"), 24L),
  sum(app_joint_sw_widths(4L, 75L, "hourglass")) == 75L,
  sum(app_joint_sw_widths(4L, 75L, "bottleneck")) == 75L
)

identity <- app_joint_sw_fixture_identity_audit(contract, registry)
stopifnot(
  nrow(identity) == 8L,
  all(identity$verified),
  all(identity$protected_rows == 1000L),
  all(identity$protected_start == 11001L),
  all(identity$protected_end == 12000L)
)

candidates <- app_joint_sw_candidate_registry("normal_bridge", contract, axes, registry)
stopifnot(
  nrow(candidates) == 4096L,
  !anyDuplicated(candidates$structural_signature),
  !anyDuplicated(candidates$candidate_id),
  sum(grepl("^anchor_", candidates$candidate_role)) == 16L,
  sum(candidates$candidate_role == "learned_local") == 1024L,
  sum(candidates$candidate_role == "global_low_discrepancy") == 2304L,
  sum(candidates$candidate_role == "mechanism_specific") == 512L,
  sum(candidates$candidate_role == "high_capacity_sentinel") == 240L,
  all(candidates$retained_state_budget[candidates$candidate_role == "high_capacity_sentinel"] %in% c(1500L, 2000L)),
  !any(candidates$retained_state_budget[candidates$candidate_role != "high_capacity_sentinel"] %in% c(1500L, 2000L)),
  all(!app_as_bool_vec(candidates$raw_inputs_in_readout)),
  all(app_as_bool_vec(candidates$full_states_all_layers))
)
parity <- candidates[candidates$candidate_role == "anchor_authoritative_v2", , drop = FALSE]
stopifnot(nrow(parity) == 1L, is.finite(parity$source_rhs_tau0), parity$source_rhs_tau0 > 0)

frontier_pool <- app_bind_rows_fill(list(
  candidates[grepl("^anchor_", candidates$candidate_role), , drop = FALSE],
  head(candidates[candidates$candidate_role == "high_capacity_sentinel", , drop = FALSE], 20L),
  head(candidates[candidates$candidate_role == "global_low_discrepancy", , drop = FALSE], 80L)
))
frontier_pool$finite_fraction <- 1
frontier_pool$calibration_acrps_mean <- seq_len(nrow(frontier_pool)) / nrow(frontier_pool)
frontier_pool$calibration_acrps_worst <- frontier_pool$calibration_acrps_mean + 0.01
frontier_pool$calibration_acrps_sd <- 0.001
frontier <- app_joint_sw_frontier(frontier_pool, n = 50L, high_quota = 8L, diversity_quota = 12L)
stopifnot(
  nrow(frontier) == 50L,
  !anyDuplicated(frontier$candidate_id),
  all(candidates$candidate_id[grepl("^anchor_", candidates$candidate_role)] %in% frontier$candidate_id),
  sum(frontier$retained_state_budget >= 1500L) >= 8L
)

aggregate_probe <- data.frame(
  scenario_id = rep("normal_bridge", 3L), candidate_id = rep("candidate", 3L),
  calibration_acrps_mean = c(1, 2, 3), runtime_seconds = c(2, 3, 4),
  peak_rss_kib = c(10, 20, 15), status = "completed", converged = c(TRUE, FALSE, TRUE),
  stringsAsFactors = FALSE
)
aggregate_probe <- app_joint_sw_aggregate_scores(aggregate_probe, c("scenario_id", "candidate_id"))
stopifnot(
  nrow(aggregate_probe) == 1L,
  aggregate_probe$evaluation_count == 3L,
  aggregate_probe$calibration_acrps_mean == 2,
  aggregate_probe$calibration_acrps_worst == 3,
  aggregate_probe$runtime_seconds_total == 9,
  abs(aggregate_probe$convergence_fraction - 2 / 3) < 1e-12
)

expected_rows <- candidates[grepl("^expected_degree_", candidates$recurrent_sparsity_mode), , drop = FALSE]
stopifnot(nrow(expected_rows) > 0L)
for (ii in seq_len(min(30L, nrow(expected_rows)))) {
  widths <- app_joint_shared_parse_num_vec(expected_rows$n[[ii]])
  degree <- as.numeric(sub("^expected_degree_", "", expected_rows$recurrent_sparsity_mode[[ii]]))
  observed <- app_joint_shared_parse_num_vec(expected_rows$pi_w[[ii]])
  stopifnot(max(abs(observed - pmin(1, degree / widths))) < 1e-8)
}

derived <- app_joint_sw_derived_dgp_registry(contract, registry)
sc <- derived[derived$scenario_id == "normal_bridge", , drop = FALSE]
sc$seed <- registry$selector_seed_base[registry$scenario_id == "normal_bridge"]
sc$seed_role <- "stronger_window_unit_selector"
fixture <- app_joint_qdesn_fixture_from_registry_row(sc)
fixture$registry_row <- sc
selector <- app_joint_pure_selector_fixture(fixture, contract)
small <- candidates[candidates$retained_state_budget == 20L, , drop = FALSE][1L, , drop = FALSE]
result <- app_joint_sw_score_ridge(selector, small, contract, contract$r1a_origins)
stopifnot(
  selector$protected_rows_persisted == 0L,
  nrow(selector$detailed_split) == 1800L,
  result$summary$n_train == 1000L,
  result$summary$n_calibration_scored == 90L,
  result$summary$protected_rows_loaded == 0L,
  nrow(result$detail) == 90L,
  identical(sort(unique(result$detail$origin_index)), contract$r1a_origins),
  identical(sort(unique(result$detail$horizon)), seq_len(30L)),
  is.finite(result$summary$calibration_acrps_mean)
)

cat("Stronger-window campaign contract tests passed.\n")
