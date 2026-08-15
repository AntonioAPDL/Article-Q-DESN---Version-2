#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)
for (file in c(
  "input_contract.R",
  "synthesize_quantiles.R",
  "score_forecasts.R",
  "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R",
  "joint_qdesn_simulation_validation.R",
  "joint_qdesn_vb_spec_screening.R",
  "joint_exqdesn_phase162_scenario_classification.R",
  "joint_exqdesn_phase163b_corrected_closure.R"
)) source(app_path("application/R", file))

candidate_template <- data.frame(
  candidate_id = c("candidate_good", "candidate_tail_only"),
  candidate_label = c("good", "tail only"),
  scenario_id = "scenario_a",
  source_phase150_candidate_id = "phase150_a",
  phase163_role = c("good", "tail_only"),
  tau0 = 0.5,
  zeta2 = 16,
  alpha_prior_sd = 1,
  gamma_init_policy = "zero",
  truth_mae_fit = c(0.101, 0.101),
  check_loss_mean_fit = 0.2,
  crps_grid_mean_fit = 0.4,
  contract_crossing_pairs_fit = 0,
  finite_quantiles_fit = TRUE,
  finite_scores_fit = TRUE,
  gate_status_fit = "pass",
  reached_max_iter_fit = FALSE,
  truth_mae_forecast = c(0.190, 0.201),
  check_loss_mean_forecast = c(0.201, 0.201),
  crps_grid_mean_forecast = c(0.401, 0.401),
  contract_crossing_pairs_forecast = 0,
  finite_quantiles_forecast = TRUE,
  finite_scores_forecast = TRUE,
  gate_status_forecast = "pass",
  reached_max_iter_forecast = FALSE,
  forecast_tau095_truth_mae = c(0.285, 0.285),
  forecast_tau095_truth_rmse = c(0.3, 0.3),
  forecast_tau095_check_loss_mean = c(0.05, 0.05),
  nested_manifests_verified = TRUE,
  worker_failure_count = 0L,
  stringsAsFactors = FALSE
)
benchmark_template <- data.frame(
  scenario_id = "scenario_a",
  phase150_vb_candidate_id = "phase150_a",
  phase150_vb_model_id = "joint_exqdesn_rhs_vb",
  vb_fit_truth_mae = 0.1,
  vb_forecast_truth_mae = 0.2,
  vb_fit_check_loss_mean = 0.2,
  vb_forecast_check_loss_mean = 0.2,
  vb_fit_contract_crossing_pairs = 0,
  vb_forecast_contract_crossing_pairs = 0,
  vb_forecast_candidate_id = "phase150_a",
  vb_forecast_tau095_truth_mae = 0.3,
  vb_fit_candidate_id = "phase150_a",
  vb_fit_tau095_truth_mae = 0.3,
  vb_forecast_crps_grid = 0.4,
  vb_fit_crps_grid = 0.4,
  benchmark_inference = "VB-LD",
  benchmark_role = "inference_matched_phase150_vb",
  stringsAsFactors = FALSE
)
ranked <- app_joint_exqdesn_phase163b_rank(candidate_template, benchmark_template)
stopifnot(sum(ranked$eligible_for_mcmc_confirmation) == 1L)
stopifnot(ranked$eligible_for_mcmc_confirmation[ranked$candidate_id == "candidate_good"])
stopifnot(!ranked$eligible_for_mcmc_confirmation[ranked$candidate_id == "candidate_tail_only"])
stopifnot(grepl("aggregate_forecast_mae_improvement", ranked$failed_gates[ranked$candidate_id == "candidate_tail_only"]))

dirs <- app_joint_exqdesn_phase163b_dirs()
dirs$output <- tempfile("phase163b_closure_")
result <- app_joint_exqdesn_phase163b_run(dirs)
stopifnot(result$assessment$gate_status == "pass")
stopifnot(result$assessment$candidates == 20L)
stopifnot(result$assessment$scenarios == 5L)
stopifnot(result$assessment$corrected_eligible_candidates == 0L)
stopifnot(result$assessment$legacy_eligible_candidates == 4L)
stopifnot(!result$assessment$mcmc_authorized)
stopifnot(nrow(result$winners) == 5L)
stopifnot(all(result$ranking$benchmark_inference == "VB-LD"))
stopifnot(all(result$ranking$gate_source_candidate_match))
stopifnot(all(result$ranking$contract_crossing_pairs_fit == 0))
stopifnot(all(result$ranking$contract_crossing_pairs_forecast == 0))

manifest <- app_read_csv(file.path(dirs$output, "artifact_manifest.csv"))
stopifnot(nrow(manifest) == 12L)
paths <- file.path(dirs$output, manifest$relative_path)
stopifnot(all(file.exists(paths)))
stopifnot(all(vapply(paths, app_sha256_file, character(1L)) == manifest$sha256))
source_verification <- app_read_csv(file.path(dirs$output, "source_manifest_verification.csv"))
stopifnot(all(source_verification$status == "pass"))
complete_manifest <- app_read_csv(file.path(dirs$output, "phase163_complete_manifest.csv"))
stopifnot(all(complete_manifest$status == "pass"))

cat("Phase163b corrected-closure tests passed.\n")
