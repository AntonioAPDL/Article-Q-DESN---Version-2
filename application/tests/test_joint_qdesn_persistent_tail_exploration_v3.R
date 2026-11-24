#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application/scripts",
  "_joint_qdesn_persistent_tail_exploration_v3_bootstrap.R"))

contract <- app_joint_pht3_read_contract()
axes <- app_joint_pht3_read_axes()
stopifnot(
  identical(contract$scenario_id, "persistent_heavy_tail"),
  contract$candidate_count == 4096L,
  contract$a1_advance_count == 1024L,
  contract$a2_advance_count == 128L,
  contract$a3_advance_count == 64L,
  contract$h1_advance_count == 20L,
  contract$h2_advance_count == 16L,
  contract$q1_advance_count == 10L,
  contract$q2_advance_count == 4L,
  contract$maximum_joint_dense_dimension == 600L,
  contract$max_physical_workers == 30L,
  identical(contract$required_hostname, "jerez.be.ucsc.edu"),
  contract$protected_selection_forbidden,
  !contract$automatic_downstream_launch,
  identical(contract$tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)),
  max(axes$rho_supercritical) == 1.2,
  max(axes$state_budget) == 80L,
  max(axes$response_lags) == 60L
)

tmp <- tempfile("joint_pht3_test_")
on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
prepared <- app_joint_pht3_prepare(tmp)
candidates <- app_read_csv(file.path(tmp, "candidate_registry.csv"))
fixtures <- app_read_csv(file.path(tmp, "fixture_manifest.csv"))
expected <- app_read_csv(file.path(tmp, "expected_work.csv"))
stopifnot(
  nrow(candidates) == 4096L,
  !anyDuplicated(candidates$candidate_id),
  !anyDuplicated(candidates$structural_signature),
  sum(grepl("^anchor_", candidates$candidate_role)) == 32L,
  sum(candidates$candidate_role == "low_rho_high_alpha") == 1792L,
  sum(candidates$candidate_role == "compact_supercritical") == 1024L,
  sum(candidates$candidate_role == "heterogeneous_layered") == 768L,
  sum(candidates$candidate_role == "global_compact") == 480L,
  all(candidates$retained_state_budget <= 80L),
  all(candidates$joint_dense_dimension <= 600L),
  all(vapply(candidates$alpha,
    function(x) all(app_joint_shared_parse_num_vec(x) < 1), logical(1L))),
  nrow(fixtures) == 6L,
  all(app_as_bool_vec(fixtures$materialized[fixtures$panel == "discovery"])),
  all(!app_as_bool_vec(fixtures$materialized[fixtures$panel == "confirmation"])),
  all(fixtures$protected_rows_persisted == 0L),
  expected$n0_workers == 90L,
  expected$a1_workers == 12288L,
  expected$expected_a2_workers == 3072L,
  expected$expected_a3_workers == 1152L,
  expected$expected_h1_workers == 1344L,
  expected$expected_h2_workers == 300L,
  expected$expected_m1_workers == 288L,
  expected$expected_t1_workers == 60L,
  expected$expected_q3_workers == 18L,
  expected$expected_q3_component_fits == 126L,
  prepared$readiness$confirmation_materialized[[1L]] == FALSE
)

sealed <- app_joint_pht3_materialize_confirmation(tmp, contract)
stopifnot(
  nrow(sealed) == 3L,
  all(app_as_bool_vec(sealed$materialized)),
  all(file.exists(sealed$fixture_path)),
  all(grepl("confirmation_rep", basename(sealed$fixture_path), fixed = TRUE)),
  !any(sealed$fixture_path %in%
    fixtures$fixture_path[fixtures$panel == "discovery"]),
  all(sealed$protected_rows_persisted == 0L)
)

probe <- candidates
probe$finite_fraction <- 1
probe$protected_rows_loaded_max <- 0L
probe$max_state_saturation <- 0.01
probe$max_recursive_state_saturation <- 0.01
probe$recursive_state_finite_all <- TRUE
probe$perturbation_pass_all <- TRUE
probe$screening_eligible_all <- TRUE
probe$realized_connectivity_pass_all <- TRUE
probe$calibration_acrps_mean <- seq_len(nrow(probe)) / nrow(probe)
probe$calibration_acrps_worst <- probe$calibration_acrps_mean + 0.01
probe$calibration_acrps_sd <- 0.001
frontier <- app_joint_pht3_select_architectures(probe, 1024L, "a1", contract)
stopifnot(
  nrow(frontier) == 1024L,
  !anyDuplicated(frontier$candidate_id),
  all(app_joint_pht3_exact_source_ids(tmp) %in% frontier$source_candidate_id)
)

profiles <- app_joint_pht3_prior_profiles(contract)
stopifnot(nrow(profiles) == 7L, sum(profiles$prior_mode == "fixed_tau0") == 5L,
  sum(profiles$prior_mode == "calibrated_fraction") == 2L)
stopifnot(abs(app_joint_pht_tail_sentinel_score(c(1, 2, 3)) - 4) < 1e-12)

launcher <- paste(readLines(file.path(repo_root, "application/scripts",
  "launch_joint_qdesn_persistent_tail_exploration_v3_stage.sh"), warn = FALSE), collapse = "\n")
stopifnot(
  grepl("jerez.be.ucsc.edu", launcher, fixed = TRUE),
  grepl("1-30 reviewed physical-core CPU IDs", launcher, fixed = TRUE),
  grepl("taskset -c", launcher, fixed = TRUE),
  grepl("OMP_NUM_THREADS=1", launcher, fixed = TRUE),
  grepl("Another model Rscript is active", launcher, fixed = TRUE),
  grepl("q3) PLAN=sealed_full7_worker_plan.csv", launcher, fixed = TRUE),
  !grepl("finalize_joint_qdesn_persistent_tail_exploration", launcher, fixed = TRUE)
)

cat("Persistent-heavy-tail v3 exploration tests passed.\n")
