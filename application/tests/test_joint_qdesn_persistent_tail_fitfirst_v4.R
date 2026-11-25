#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application", "scripts",
  "_joint_qdesn_persistent_tail_fitfirst_v4_bootstrap.R"))

contract <- app_joint_pht4_read_contract()
axes <- app_joint_pht4_read_axes()
stopifnot(
  contract$candidate_count == 8192L,
  contract$rhs_max_iter == 500L,
  contract$al_max_iter == 500L,
  contract$rhs_tolerance == 1e-3,
  contract$al_tolerance == 1e-3,
  max(axes$depth) == 8L,
  max(axes$response_lags) == 360L,
  max(axes$promotable_state_budget) == 84L,
  max(axes$diagnostic_state_budget) == 2000L,
  max(axes$rho_supercritical) == 1.2,
  !contract$automatic_downstream_launch,
  contract$protected_selection_forbidden
)

tmp <- tempfile("joint_pht4_test_")
on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
prepared <- app_joint_pht4_prepare(tmp)
candidates <- app_read_csv(file.path(tmp, "candidate_registry.csv"))
fixtures <- app_read_csv(file.path(tmp, "fixture_manifest.csv"))
expected <- app_read_csv(file.path(tmp, "expected_work.csv"))
historical <- app_joint_pht4_historical_signatures()
generated <- !app_as_bool_vec(candidates$prior_signature_exception)
stopifnot(
  nrow(candidates) == 8192L,
  !anyDuplicated(candidates$candidate_id),
  !anyDuplicated(candidates$structural_signature),
  identical(app_joint_qvp_sha256_text(paste(candidates$structural_signature, collapse = "|")),
    contract$candidate_signature_sha256),
  !any(candidates$structural_signature[generated] %in% historical),
  sum(candidates$candidate_role == "named_control") == 32L,
  sum(candidates$candidate_role == "local_fit") == 2048L,
  sum(candidates$candidate_role == "layered_fit") == 2048L,
  sum(candidates$candidate_role == "long_memory") == 1536L,
  sum(candidates$candidate_role == "supercritical") == 1024L,
  sum(candidates$candidate_role == "high_capacity_diagnostic") == 1024L,
  sum(candidates$candidate_role == "global_unseen") == 480L,
  all(candidates$retained_state_budget[!app_as_bool_vec(candidates$diagnostic_only)] <= 84L),
  all(candidates$joint_backend_eligible[!app_as_bool_vec(candidates$diagnostic_only)]),
  nrow(fixtures) == 13L,
  sum(app_as_bool_vec(fixtures$materialized)) == 3L,
  all(fixtures$protected_rows_persisted == 0L),
  expected$r1_workers == 24576L,
  expected$r2_workers == 3072L,
  expected$r3_workers == 1152L,
  expected$h1_workers == 1920L,
  expected$h2_workers_max == 576L,
  expected$m1_workers == 480L,
  expected$t1_workers == 120L,
  expected$s1_workers == 35L,
  prepared$readiness$tail_materialized[[1L]] == FALSE,
  prepared$readiness$sealed_materialized[[1L]] == FALSE
)

base <- app_joint_sw_read_contract(file.path(tmp, "frozen_contract.csv"))
stopifnot(base$rhs_max_iter == 500L, base$rhs_min_iter == 50L,
  base$rhs_tolerance == 1e-3, base$median_max_iter == 500L,
  base$quantile_max_iter == 500L, base$vb_tolerance == 1e-3,
  base$max_readout_dimension == 2000L)

probe <- candidates
probe$training_location_mae_mean <- seq_len(nrow(probe)) / nrow(probe)
probe$horizon1_location_mae_mean <- probe$training_location_mae_mean + 0.01
probe$recursive_location_mae_mean <- probe$training_location_mae_mean + 0.02
probe$hard_functional_pass_all <- TRUE
probe$forecast_only_score <- rev(probe$training_location_mae_mean)
frontier <- app_joint_pht4_select_quota(probe, 128L,
  c(named_control = 3L, local_fit = 32L, layered_fit = 32L, long_memory = 24L,
    supercritical = 16L, high_capacity_diagnostic = 8L, global_unseen = 13L), TRUE)
stopifnot(nrow(frontier) == 128L,
  app_joint_pht4_exact_id(probe) %in% frontier$candidate_id,
  !"forecast_only_score" %in% c("training_location_mae_mean",
    "horizon1_location_mae_mean", "recursive_location_mae_mean"))

tail_probe <- data.frame(
  candidate_id = c("exact", "good", "bad_lower"),
  source_candidate_id = c("persistent_heavy_tail__targeted_0209", NA, NA),
  hard_functional_pass_all = TRUE,
  median_fit_mae = c(0.10, 0.095, 0.095),
  training_quantile_mae_mean_lower = c(0.10, 0.105, 0.30),
  training_quantile_mae_mean_upper = c(0.10, 0.105, 0.105),
  median_horizon1_mae = c(0.10, 0.10, 0.10),
  horizon1_quantile_mae_mean_lower = c(0.10, 0.105, 0.105),
  horizon1_quantile_mae_mean_upper = c(0.10, 0.105, 0.105),
  stringsAsFactors = FALSE)
gated <- app_joint_pht4_apply_tail_gates(tail_probe, contract)$table
stopifnot(gated$fit_capable[gated$candidate_id == "good"],
  !gated$lower_fit_gate[gated$candidate_id == "bad_lower"],
  gated$upper_fit_gate[gated$candidate_id == "bad_lower"])

r1 <- file.path(tmp, "r1_worker_plan.csv")
original <- readBin(r1, "raw", n = file.info(r1)$size)
write("corruption", r1, append = TRUE)
error <- tryCatch({ app_joint_pht4_verify_plan(tmp, "r1"); NULL }, error = identity)
stopifnot(inherits(error, "error"))
writeBin(original, r1)
app_joint_pht4_verify_plan(tmp, "r1")

launcher <- paste(readLines(file.path(repo_root, "application", "scripts",
  "launch_joint_qdesn_persistent_tail_fitfirst_v4_stage.sh"), warn = FALSE), collapse = "\n")
stopifnot(
  grepl("jerez.be.ucsc.edu", launcher, fixed = TRUE),
  grepl("SENTINELS_COMPLETE_R1_AUTHORIZED", launcher, fixed = TRUE),
  grepl("taskset -c", launcher, fixed = TRUE),
  grepl("OMP_NUM_THREADS=1", launcher, fixed = TRUE),
  grepl("1-30 reviewed physical-core CPU IDs", launcher, fixed = TRUE),
  !grepl("finalize_joint_qdesn_persistent_tail_fitfirst_v4_stage", launcher, fixed = TRUE)
)

cat("JOINT_PERSISTENT_TAIL_FITFIRST_V4_TEST_PASS expectations=54 production_runs=0\n")
