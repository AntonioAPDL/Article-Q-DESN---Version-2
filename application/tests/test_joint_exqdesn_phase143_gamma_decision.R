repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for Joint exQDESN Phase143 test.", call. = FALSE)
  }
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_fixtures.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_exqdesn_phase143_gamma_decision.R"))

phase143_make_assessment <- function(case_id, variant_id, gate, forecast_mae, fit_mae,
                                     gamma_rhat = NA_real_, gamma_ess = NA_real_,
                                     gamma_ac1 = NA_real_, raw_cross = 0) {
  data.frame(
    case_id = case_id,
    scenario_id = sub("__.*$", "", case_id),
    scenario_class = "stress",
    distribution_family = "toy",
    dynamics_class = "toy_dynamic",
    source_candidate_id = paste(case_id, "source", sep = "__"),
    source_model_id = "joint_exqdesn_rhs_vb",
    model_id = "joint_exqdesn_rhs_mcmc",
    display_label = "JOINT exQDESN RHS MCMC",
    likelihood = "exal",
    fit_structure = "joint",
    inference = "MCMC",
    experiment_id = variant_id,
    variant_id = variant_id,
    phase136_variant_id = variant_id,
    phase136_case_variant_id = paste(case_id, variant_id, sep = "__"),
    gamma_update = ifelse(identical(variant_id, "fixed_zero"), "fixed", "logit_slice"),
    width_multiplier = NA_real_,
    logit_eta_width = ifelse(identical(variant_id, "fixed_zero"), NA_real_, 1),
    gamma_prior_type = ifelse(grepl("^logit_prior", variant_id), "logit_normal", "none"),
    gamma_prior_center = ifelse(grepl("^logit_prior", variant_id), 0, NA_real_),
    gamma_prior_sd_eta = ifelse(grepl("1p0$", variant_id), 1, ifelse(grepl("0p25$", variant_id), 0.25, NA_real_)),
    gamma_slice_width_summary = "1,1,1",
    phase136_gate_status = gate,
    mcmc_fit_truth_mae = fit_mae,
    mcmc_forecast_truth_mae = forecast_mae,
    mcmc_fit_check_loss_mean = fit_mae + 0.01,
    mcmc_forecast_check_loss_mean = forecast_mae + 0.01,
    mcmc_fit_raw_crossing_pairs = 0,
    mcmc_forecast_raw_crossing_pairs = raw_cross,
    mcmc_fit_contract_crossing_pairs = 0,
    mcmc_forecast_contract_crossing_pairs = 0,
    max_rhat = ifelse(is.na(gamma_rhat), 1.001, gamma_rhat),
    min_rough_ess_total = ifelse(is.na(gamma_ess), 500, gamma_ess),
    max_gamma_rhat = gamma_rhat,
    min_gamma_rough_ess_total = gamma_ess,
    max_gamma_chain_mean_gap = 0.1,
    max_gamma_lag1_autocorrelation = gamma_ac1,
    max_sigma_upper_bound_hit_fraction = 0,
    status_reason = ifelse(gate == "review", "gamma lag-1 autocorrelation remains high", ""),
    stringsAsFactors = FALSE
  )
}

phase143_write_packet <- function(dir, assessment, best, worker_failures = NULL) {
  app_ensure_dir(dir)
  worker_failures <- worker_failures %||% data.frame(
    validation_label = character(),
    scenario_id = character(),
    worker_index = integer(),
    worker_status = character(),
    error_class = character(),
    error_message = character(),
    job_id = character(),
    phase136_case_variant_id = character(),
    case_id = character(),
    phase136_variant_id = character(),
    chain_id = integer(),
    chain_seed = integer(),
    stringsAsFactors = FALSE
  )
  prep_failures <- data.frame(
    validation_label = character(),
    scenario_id = character(),
    worker_index = integer(),
    worker_status = character(),
    error_class = character(),
    error_message = character(),
    stringsAsFactors = FALSE
  )
  chain_jobs <- data.frame(
    job_id = paste0("job_", seq_len(max(1L, nrow(assessment)))),
    phase136_case_variant_id = assessment$phase136_case_variant_id[seq_len(max(1L, nrow(assessment)))],
    case_id = assessment$case_id[seq_len(max(1L, nrow(assessment)))],
    phase136_variant_id = assessment$phase136_variant_id[seq_len(max(1L, nrow(assessment)))],
    chain_id = seq_len(max(1L, nrow(assessment))),
    chain_seed = 1000L + seq_len(max(1L, nrow(assessment))),
    stringsAsFactors = FALSE
  )
  runtime <- data.frame(
    case_id = assessment$case_id,
    phase136_variant_id = assessment$phase136_variant_id,
    runtime_component = "mcmc_chain",
    chain_id = seq_len(nrow(assessment)),
    elapsed_seconds = 1,
    sec_per_iter = 0.01,
    stringsAsFactors = FALSE
  )
  paths <- c(
    run_config = app_joint_qvp_write_csv(data.frame(run_id = "toy", stringsAsFactors = FALSE), file.path(dir, "run_config.csv")),
    phase136_case_assessment = app_joint_qvp_write_csv(assessment, file.path(dir, "phase136_case_assessment.csv")),
    phase136_best_variant_by_case = app_joint_qvp_write_csv(best, file.path(dir, "phase136_best_variant_by_case.csv")),
    phase136_chain_jobs = app_joint_qvp_write_csv(chain_jobs, file.path(dir, "phase136_chain_jobs.csv")),
    phase136_chain_worker_failures = app_joint_qvp_write_csv(worker_failures, file.path(dir, "phase136_chain_worker_failures.csv")),
    phase136_case_variant_prep_failures = app_joint_qvp_write_csv(prep_failures, file.path(dir, "phase136_case_variant_prep_failures.csv")),
    runtime_summary = app_joint_qvp_write_csv(runtime, file.path(dir, "runtime_summary.csv"))
  )
  invisible(app_joint_qdesn_write_manifest(paths, dir))
}

cases <- c("case_a__joint_exqdesn_rhs_vb", "case_b__joint_exqdesn_rhs_vb")

fixed <- app_joint_qdesn_bind_rows(list(
  phase143_make_assessment(cases[[1L]], "fixed_zero", "review", 0.10, 0.08, raw_cross = 1),
  phase143_make_assessment(cases[[2L]], "fixed_zero", "review", 0.20, 0.16)
))
focus <- app_joint_qdesn_bind_rows(list(
  phase143_make_assessment(cases[[1L]], "logit_w0p5", "review", 0.13, 0.11, gamma_rhat = 1.15, gamma_ess = 220, gamma_ac1 = 0.998),
  phase143_make_assessment(cases[[2L]], "logit_w2", "review", 0.23, 0.18, gamma_rhat = 1.12, gamma_ess = 260, gamma_ac1 = 0.997)
))
regularized <- app_joint_qdesn_bind_rows(list(
  phase143_make_assessment(cases[[1L]], "logit_prior_sd_0p25", "pass", 0.15, 0.14, gamma_rhat = 1.005, gamma_ess = 1200, gamma_ac1 = 0.97),
  phase143_make_assessment(cases[[1L]], "logit_prior_sd_1p0", "review", 0.14, 0.13, gamma_rhat = 1.08, gamma_ess = 300, gamma_ac1 = 0.998),
  phase143_make_assessment(cases[[2L]], "logit_prior_sd_0p25", "pass", 0.25, 0.22, gamma_rhat = 1.004, gamma_ess = 1100, gamma_ac1 = 0.971),
  phase143_make_assessment(cases[[2L]], "logit_prior_sd_1p0", "review", 0.24, 0.21, gamma_rhat = 1.07, gamma_ess = 320, gamma_ac1 = 0.997)
))

tmp <- tempfile("joint_exqdesn_phase143_")
fixed_dir <- file.path(tmp, "fixed")
focus_dir <- file.path(tmp, "focus")
reg_dir <- file.path(tmp, "regularized")
out_dir <- file.path(tmp, "freeze")

phase143_write_packet(fixed_dir, fixed, fixed)
phase143_write_packet(focus_dir, focus, focus)
worker_failure <- data.frame(
  validation_label = "phase136_mcmc_chain",
  scenario_id = "case_b",
  worker_index = 4L,
  worker_status = "fail",
  error_class = "simpleError",
  error_message = "toy failure in non-promoted diagnostic variant",
  job_id = "case_b__joint_exqdesn_rhs_vb__logit_prior_sd_0p25__chain_04",
  phase136_case_variant_id = "case_b__joint_exqdesn_rhs_vb__logit_prior_sd_0p25",
  case_id = cases[[2L]],
  phase136_variant_id = "logit_prior_sd_0p25",
  chain_id = 4L,
  chain_seed = 1404L,
  stringsAsFactors = FALSE
)
phase143_write_packet(reg_dir, regularized, regularized[regularized$phase136_gate_status == "pass", , drop = FALSE], worker_failure)

result <- app_joint_exqdesn_run_phase143_gamma_decision_freeze(
  out_dir = out_dir,
  phase140_dir = fixed_dir,
  phase141_focus_dir = focus_dir,
  phase142_dir = reg_dir
)

stopifnot(dir.exists(result$out_dir))
stopifnot(nrow(result$packet_health) == 3L)
stopifnot(nrow(result$comparison) == 8L)
stopifnot(nrow(result$metric_winners) == 2L)
stopifnot(all(result$metric_winners$variant_id == "logit_prior_sd_1p0"))
stopifnot(nrow(result$gate_winners) == 2L)
stopifnot(all(result$gate_winners$variant_id == "logit_prior_sd_0p25"))
stopifnot(identical(result$decision$gate_status[[1L]], "review"))
stopifnot(identical(result$decision$sampled_gamma_exal_decision[[1L]], "do_not_promote_sampled_gamma_exal_to_article_primary_table"))
stopifnot(result$decision$phase142_regularized_beats_fixed_forecast_cases[[1L]] == 0L)
stopifnot(result$decision$phase142_worker_failures[[1L]] == 1L)
stopifnot(all(result$source_manifest$status == "pass"))
stopifnot(file.exists(file.path(result$out_dir, "artifact_manifest.csv")))

manifest <- app_joint_qdesn_phase108_manifest_verify(result$out_dir, "phase143")
stopifnot(all(manifest$status == "pass"))

required_outputs <- c(
  "run_config.csv",
  "source_manifest_verification.csv",
  "gamma_packet_health_summary.csv",
  "gamma_packet_comparison_by_case.csv",
  "gamma_variant_metric_first_winners.csv",
  "gamma_variant_gate_first_winners.csv",
  "gamma_diagnostic_tradeoff_summary.csv",
  "gamma_decision_summary.csv",
  "article_integration_recommendation.csv",
  "next_experiment_recommendation.csv",
  "provenance.csv",
  "README.md",
  "artifact_manifest.csv"
)
stopifnot(all(file.exists(file.path(result$out_dir, required_outputs))))

cat("Joint exQDESN Phase143 gamma decision tests passed.\n")
