repo_root <- normalizePath(file.path(dirname(normalizePath(sub(
  "^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
))), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_phase153_balanced_independent_replication.R"
)) source(app_path("application/R", path))

freeze <- app_joint_qdesn_phase153_load_control_freeze()
stopifnot(freeze$audit$gate_status[[1L]] == "pass")
stopifnot(nrow(freeze$frozen) == 32L)
stopifnot(all(freeze$source_manifest$verified))
stopifnot(all(table(freeze$frozen$model_id) == 8L))
stopifnot(all(table(freeze$frozen$base_scenario_id) == 4L))
stopifnot(
  sum(freeze$frozen$source_freeze_id == "phase150_joint_exal_winners") == 8L
)
stopifnot(all(
  freeze$frozen$model_id[
    freeze$frozen$source_freeze_id == "phase150_joint_exal_winners"
  ] == "joint_exqdesn_rhs_vb"
))

base_registry <- app_joint_qdesn_load_simulation_registry()
dgp_a <- app_joint_qdesn_phase153_build_dgp_registry(
  base_registry,
  n_dgp_replicates = 2L,
  seed_base = 153800000L,
  excluded_seeds = base_registry$seed
)
dgp_b <- app_joint_qdesn_phase153_build_dgp_registry(
  base_registry,
  n_dgp_replicates = 2L,
  seed_base = 153800000L,
  excluded_seeds = base_registry$seed
)
stopifnot(identical(dgp_a, dgp_b))
stopifnot(nrow(dgp_a) == 16L)
stopifnot(!anyDuplicated(dgp_a$scenario_id))
stopifnot(!anyDuplicated(dgp_a$seed))
stopifnot(!any(dgp_a$seed %in% base_registry$seed))
stopifnot(all(dgp_a$simulated_length == 12000L))
stopifnot(all(dgp_a$dgp_warmup_length == 2000L))
stopifnot(all(dgp_a$desn_washout_length == 500L))
stopifnot(all(dgp_a$fit_length == 500L))
stopifnot(all(dgp_a$validation_length == 1000L))
stopifnot(all(dgp_a$forecast_origin_stride == 30L))
stopifnot(all(dgp_a$max_lead == 30L))

candidate_a <- app_joint_qdesn_phase153_build_candidate_registry(
  freeze$frozen,
  dgp_a
)
candidate_b <- app_joint_qdesn_phase153_build_candidate_registry(
  freeze$frozen,
  dgp_a
)
stopifnot(identical(candidate_a, candidate_b))
stopifnot(nrow(candidate_a) == 64L)
stopifnot(!anyDuplicated(candidate_a$candidate_id))
stopifnot(all(table(candidate_a$model_id) == 16L))
stopifnot(all(table(candidate_a$base_scenario_id) == 8L))

seed_audit <- app_joint_qdesn_phase153_seed_collision_audit(
  dgp_a,
  original_seeds = base_registry$seed,
  phase152_seeds = integer()
)
stopifnot(all(seed_audit$seed_status == "pass"))
exhausted_audit <- app_joint_qdesn_phase153_exhausted_dimension_audit()
stopifnot(all(!exhausted_audit$repeated_in_phase153))
stopifnot(all(grepl(
  "freeze|close",
  exhausted_audit$phase153_action
)))

readiness_dir <- tempfile("phase153_readiness_")
readiness <- app_joint_qdesn_run_phase153_readiness(
  out_dir = readiness_dir,
  fixture_dir = tempfile("phase153_fixture_not_materialized_"),
  n_dgp_replicates = 2L,
  seed_base = 153800000L,
  materialize_fixtures = FALSE
)
stopifnot(readiness$assessment$gate_status[[1L]] == "pass")
stopifnot(nrow(readiness$dgp_registry) == 16L)
stopifnot(nrow(readiness$candidate_registry) == 64L)
stopifnot(all(app_joint_qdesn_phase153_verify_manifest(
  readiness_dir,
  "phase153_test_readiness"
)$verified))

metrics <- app_joint_qdesn_phase153_metric_names()
candidate_rows <- list()
tau_rows <- list()
scenarios <- app_joint_qdesn_phase153_target_scenarios()
models <- app_joint_qdesn_phase153_model_order()
taus <- c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)
for (ss in seq_along(scenarios)) {
  for (rr in seq_len(3L)) {
    for (mm in seq_along(models)) {
      scale <- 1 + 0.04 * (mm - 1L) + 0.002 * rr
      row <- data.frame(
        candidate_id = paste(scenarios[[ss]], sprintf("r%02d", rr), models[[mm]], sep = "__"),
        base_scenario_id = scenarios[[ss]],
        dgp_replicate_id = sprintf("r%02d", rr),
        dgp_seed = 800000L + ss * 100L + rr,
        model_id = models[[mm]],
        implementation_status = "pass",
        gate_status = "pass",
        vb_reached_max_iter = FALSE,
        fit_raw_crossing_pairs = 0L,
        forecast_raw_crossing_pairs = 0L,
        fit_contract_crossing_pairs = 0L,
        forecast_contract_crossing_pairs = 0L,
        fit_max_abs_adjustment = 0,
        forecast_max_abs_adjustment = 0,
        total_elapsed_seconds = 1 + mm / 10,
        stringsAsFactors = FALSE
      )
      for (metric in metrics) {
        baseline <- if (grepl("check|crps", metric)) 0.20 else if (grepl("hit", metric)) 0.03 else 0.10
        row[[metric]] <- baseline * scale
      }
      candidate_rows[[length(candidate_rows) + 1L]] <- row
      for (window in c("fit", "forecast")) {
        for (tau in taus) {
          tau_rows[[length(tau_rows) + 1L]] <- data.frame(
            candidate_id = row$candidate_id,
            base_scenario_id = scenarios[[ss]],
            dgp_replicate_id = sprintf("r%02d", rr),
            dgp_seed = row$dgp_seed,
            model_id = models[[mm]],
            validation_window = window,
            tau = tau,
            truth_mae = 0.10 * scale,
            truth_rmse = 0.12 * scale,
            truth_bias = 0.01 * (mm - 1L),
            check_loss_mean = 0.20 * scale,
            hit_rate = tau,
            hit_rate_error = 0,
            abs_hit_rate_error = 0,
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }
}
candidate_summary <- app_joint_qdesn_bind_rows(candidate_rows)
tau_summary <- app_joint_qdesn_bind_rows(tau_rows)

paired_rows <- app_joint_qdesn_phase153_paired_contrast_rows(candidate_summary)
stopifnot(nrow(paired_rows) == 8L * 3L * 6L * length(metrics))
paired_a <- app_joint_qdesn_phase153_paired_contrast_summary(
  paired_rows,
  bootstrap_replicates = 100L,
  seed_base = 153990000L
)
paired_b <- app_joint_qdesn_phase153_paired_contrast_summary(
  paired_rows,
  bootstrap_replicates = 100L,
  seed_base = 153990000L
)
stopifnot(identical(paired_a, paired_b))
stopifnot(nrow(paired_a) == 8L * 6L * length(metrics))
stopifnot(all(paired_a$n_replicates == 3L))
stopifnot(all(is.finite(paired_a$median_delta)))

rank_rows <- app_joint_qdesn_phase153_rank_rows(candidate_summary)
rank_summary <- app_joint_qdesn_phase153_rank_summary(rank_rows)
stopifnot(nrow(rank_rows) == nrow(candidate_summary))
stopifnot(nrow(rank_summary) == 32L)
stopifnot(all(rank_summary$n_replicates == 3L))

tau_contrast <- app_joint_qdesn_phase153_tau_contrast_summary(tau_summary)
stopifnot(
  nrow(tau_contrast$replicate_rows) ==
    8L * 3L * 2L * length(taus) * 4L * 3L
)
stopifnot(nrow(tau_contrast$summary) == 8L * 2L * length(taus) * 4L * 3L)
stopifnot(all(is.finite(tau_contrast$summary$median_delta)))

checkpoint <- tempfile("phase153_checkpoint_")
fake_result <- list(
  candidate_summary = candidate_summary[1L, , drop = FALSE],
  tau_summary = tau_summary[
    tau_summary$candidate_id == candidate_summary$candidate_id[[1L]],
    ,
    drop = FALSE
  ],
  interval_summary = data.frame(
    candidate_id = candidate_summary$candidate_id[[1L]],
    interval = "0.05_0.95",
    coverage = 0.90,
    stringsAsFactors = FALSE
  ),
  vb_diagnostics = data.frame(
    candidate_id = candidate_summary$candidate_id[[1L]],
    converged = TRUE,
    stringsAsFactors = FALSE
  )
)
checkpoint_dir <- app_joint_qdesn_phase153_write_candidate(
  fake_result,
  checkpoint,
  candidate_summary$candidate_id[[1L]]
)
stopifnot(app_joint_qdesn_phase153_verify_candidate_dir(checkpoint_dir))
write("corruption", file.path(checkpoint_dir, "candidate_summary.csv"), append = TRUE)
stopifnot(!app_joint_qdesn_phase153_verify_candidate_dir(checkpoint_dir))

cat("Joint QDESN Phase153 balanced independent-replication tests passed.\n")
