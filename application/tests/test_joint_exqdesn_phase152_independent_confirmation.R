repo_root <- normalizePath(file.path(dirname(normalizePath(sub(
  "^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
))), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_vb_spec_screening.R", "joint_qdesn_mcmc_readiness.R",
  "joint_exqdesn_trace_tools.R",
  "joint_exqdesn_phase149_case_specific_screening.R",
  "joint_exqdesn_phase150_case_specific_mcmc_confirmation.R",
  "latent_path_design.R", "joint_exqdesn_phase151_feature_design_screening.R",
  "joint_exqdesn_phase152_independent_confirmation.R"
)) source(app_path("application/R", path))

source_freeze <- app_joint_exqdesn_phase152_load_phase151_freeze()
stopifnot(nrow(source_freeze$selected) == 2L)
stopifnot(nrow(source_freeze$direct) == 2L)
stopifnot(all(source_freeze$source_manifest$verified))
stopifnot(setequal(
  source_freeze$selected$scenario_id,
  app_joint_exqdesn_phase152_target_scenarios()
))

base_registry <- app_joint_qdesn_load_simulation_registry()
dgp_a <- app_joint_exqdesn_phase152_build_dgp_registry(
  base_registry, n_dgp_replicates = 3L
)
dgp_b <- app_joint_exqdesn_phase152_build_dgp_registry(
  base_registry, n_dgp_replicates = 3L
)
stopifnot(identical(dgp_a, dgp_b))
stopifnot(nrow(dgp_a) == 6L)
stopifnot(!anyDuplicated(dgp_a$scenario_id))
stopifnot(!anyDuplicated(dgp_a$seed))
stopifnot(all(dgp_a$simulated_length == 12000L))
stopifnot(all(dgp_a$dgp_warmup_length == 2000L))
stopifnot(all(dgp_a$desn_washout_length == 500L))
stopifnot(all(dgp_a$fit_length == 500L))
stopifnot(all(dgp_a$validation_length == 1000L))

vb_a <- app_joint_exqdesn_phase152_build_vb_registry(
  source_freeze$frozen, dgp_a, n_reservoir_replicates = 2L
)
vb_b <- app_joint_exqdesn_phase152_build_vb_registry(
  source_freeze$frozen, dgp_a, n_reservoir_replicates = 2L
)
stopifnot(identical(vb_a, vb_b))
stopifnot(nrow(vb_a) == 18L)
stopifnot(!anyDuplicated(vb_a$candidate_id))
stopifnot(sum(vb_a$confirmation_role == "direct_control") == 6L)
stopifnot(sum(vb_a$confirmation_role == "selected_feature_map") == 12L)
stopifnot(!anyDuplicated(vb_a$reservoir_seed[
  vb_a$confirmation_role == "selected_feature_map"
]))

chain_plan <- app_joint_exqdesn_phase152_chain_seed_plan(
  source_freeze$frozen, n_chains = 8L
)
stopifnot(nrow(chain_plan) == 16L)
stopifnot(!anyDuplicated(chain_plan$chain_seed))
stopifnot(all(table(chain_plan$base_scenario_id) == 8L))

metric_names <- app_joint_exqdesn_phase152_metric_names()
candidate_rows <- list()
tau_rows <- list()
scenarios <- app_joint_exqdesn_phase152_target_scenarios()
for (ss in seq_along(scenarios)) {
  scenario <- scenarios[[ss]]
  for (rr in seq_len(10L)) {
    dgp_id <- sprintf("r%02d", rr)
    roles <- c("direct_control", rep("selected_feature_map", 3L))
    factors <- if (ss == 1L) c(1, 0.88, 0.90, 0.92) else c(1, 1.01, 1.02, 1.03)
    for (kk in seq_along(roles)) {
      row <- data.frame(
        candidate_id = paste(scenario, dgp_id, kk, sep = "__"),
        base_scenario_id = scenario,
        dgp_replicate_id = dgp_id,
        dgp_seed = 10000L + ss * 100L + rr,
        reservoir_replicate_id = if (kk == 1L) "none" else sprintf("r%02d", kk - 1L),
        reservoir_seed = if (kk == 1L) NA_integer_ else 20000L + ss * 1000L + rr * 10L + kk,
        confirmation_role = roles[[kk]],
        implementation_status = "pass",
        vb_reached_max_iter = FALSE,
        fit_contract_crossing_pairs = 0L,
        forecast_contract_crossing_pairs = 0L,
        stringsAsFactors = FALSE
      )
      for (metric in metric_names) {
        base <- if (grepl("check|crps", metric)) 0.20 else if (grepl("hit", metric)) 0.03 else 0.10
        factor <- factors[[kk]]
        if (grepl("^fit_", metric) && kk > 1L) factor <- 1.01
        if (grepl("check|crps", metric) && kk > 1L) factor <- 0.99
        row[[metric]] <- base * factor
      }
      candidate_rows[[length(candidate_rows) + 1L]] <- row
      for (tau in c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)) {
        tau_rows[[length(tau_rows) + 1L]] <- data.frame(
          candidate_id = row$candidate_id,
          base_scenario_id = scenario,
          dgp_replicate_id = dgp_id,
          dgp_seed = row$dgp_seed,
          confirmation_role = roles[[kk]],
          validation_window = "forecast",
          tau = tau,
          truth_mae = 0.10 * factors[[kk]],
          truth_rmse = 0.12 * factors[[kk]],
          check_loss_mean = 0.20 * if (kk == 1L) 1 else 0.99,
          abs_hit_rate_error = 0.02,
          stringsAsFactors = FALSE
        )
      }
    }
  }
}
candidate_summary <- app_joint_qdesn_bind_rows(candidate_rows)
tau_summary <- app_joint_qdesn_bind_rows(tau_rows)
paired <- app_joint_exqdesn_phase152_paired_rows(candidate_summary)
seed_comparison <- app_joint_exqdesn_phase152_seed_comparison(candidate_summary)
tau_paired <- app_joint_exqdesn_phase152_tau_paired_rows(tau_summary)
decision <- app_joint_exqdesn_phase152_promotion_decision(
  candidate_summary, paired, seed_comparison, tau_paired
)
stopifnot(nrow(paired) == 20L)
stopifnot(nrow(seed_comparison) == 60L)
stopifnot(nrow(tau_paired) == 140L)
stopifnot(
  decision$promotion_status[
    decision$base_scenario_id == "gaussian_mixture_bridge"
  ] == "promote_to_mcmc"
)
stopifnot(
  decision$promotion_status[
    decision$base_scenario_id == "nonlinear_reservoir_friendly"
  ] == "reject_after_independent_confirmation"
)

tmp_checkpoint <- tempfile("phase152_checkpoint_")
app_joint_exqdesn_phase152_atomic_checkpoint(tmp_checkpoint, function(tmp) {
  object_path <- file.path(tmp, "object.rds")
  saveRDS(list(value = 1), object_path)
  summary_path <- app_joint_qvp_write_csv(
    data.frame(value = 1), file.path(tmp, "summary.csv")
  )
  c(object = normalizePath(object_path), summary = summary_path)
})
stopifnot(app_joint_exqdesn_phase152_verify_compact_checkpoint(tmp_checkpoint))

tmp_no_survivor <- tempfile("phase152_no_survivor_")
reject_decision <- decision
reject_decision$promotion_status <- "reject_after_independent_confirmation"
no_survivor <- app_joint_exqdesn_phase152_write_no_survivor_mcmc(
  tmp_no_survivor,
  reject_decision,
  tempfile("vb_source_"),
  data.frame(
    source_id = "synthetic_test",
    label = "source",
    relative_path = "source.csv",
    exists = TRUE,
    declared_sha256 = "abc",
    actual_sha256 = "abc",
    verified = TRUE,
    stringsAsFactors = FALSE
  )
)
stopifnot(no_survivor$assessment$gate_status[[1L]] == "pass")
stopifnot(all(app_joint_exqdesn_phase152_verify_manifest(
  tmp_no_survivor, "no_survivor"
)$verified))

mcmc_summary <- data.frame(
  scenario_id = "gaussian_mixture_bridge",
  all_init_source_provided = TRUE,
  all_draws_finite = TRUE,
  fit_truth_mae = 0.09,
  forecast_truth_mae = 0.08,
  forecast_check_loss_mean = 0.19,
  forecast_crps_grid_mean = 0.18,
  max_gamma_rhat = 1.15,
  min_gamma_rough_ess = 500,
  max_sigma_rhat = 1.05,
  min_sigma_rough_ess = 600,
  fit_contract_crossing_pairs = 0L,
  forecast_contract_crossing_pairs = 0L,
  delta_forecast_mae_vs_phase150_direct = -0.01,
  ratio_fit_mae_vs_phase150_direct = 1.01,
  ratio_check_loss_vs_phase150_direct = 1.00,
  ratio_crps_vs_phase150_direct = 1.00,
  stringsAsFactors = FALSE
)
mcmc_gate <- app_joint_exqdesn_phase152_mcmc_assessment(mcmc_summary)
stopifnot(mcmc_gate$implementation_status[[1L]] == "pass")
stopifnot(mcmc_gate$performance_status[[1L]] == "pass")
stopifnot(mcmc_gate$mixing_status[[1L]] == "pass")
stopifnot(mcmc_gate$gate_status[[1L]] == "pass")

cat("Joint exQDESN Phase152 independent-confirmation tests passed.\n")
