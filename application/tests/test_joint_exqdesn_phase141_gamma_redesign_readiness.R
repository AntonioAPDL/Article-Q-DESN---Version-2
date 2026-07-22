repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for Joint exQDESN Phase141 test.", call. = FALSE)
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
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_calibration_screening.R"))
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_exqdesn_trace_tools.R"))
source(app_path("application/R/joint_exqdesn_phase136_gamma_kernel_packet.R"))
source(app_path("application/R/joint_exqdesn_phase141_gamma_redesign_readiness.R"))

write_fake_manifest <- function(paths, dir) {
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  app_joint_qvp_write_csv(manifest, file.path(dir, "artifact_manifest.csv"))
}

make_phase140_fixed_like_artifact <- function(dir) {
  app_ensure_dir(dir)
  run_config <- data.frame(
    run_id = "fake_phase140_fixed_gamma",
    phase135_screening_dir = "application/cache/fake_phase135_screening",
    phase135_audit_dir = "application/cache/fake_phase135_screening/phase135_result_audit",
    stringsAsFactors = FALSE
  )
  case_summary <- data.frame(
    case_id = c("regime_shift__joint_exqdesn_rhs_vb", "laplace_bridge__joint_exqdesn_rhs_vb"),
    scenario_id = c("regime_shift", "laplace_bridge"),
    scenario_class = c("stress", "bridge"),
    distribution_family = c("student_t", "laplace"),
    dynamics_class = c("regime_shift_location_scale", "ar1_seasonal_location_scale"),
    source_model_id = c("joint_exqdesn_rhs_vb", "joint_exqdesn_rhs_vb"),
    model_id = c("joint_exqdesn_rhs_mcmc", "joint_exqdesn_rhs_mcmc"),
    fit_structure = c("joint", "joint"),
    gamma_update = c("fixed", "fixed"),
    mcmc_n_chains = c(2L, 2L),
    all_requested_chains_completed = c(TRUE, TRUE),
    mcmc_fit_truth_mae = c(0.08, 0.09),
    mcmc_forecast_truth_mae = c(0.16, 0.10),
    mcmc_fit_raw_crossing_pairs = c(0L, 0L),
    mcmc_forecast_raw_crossing_pairs = c(0L, 0L),
    mcmc_fit_contract_crossing_pairs = c(0L, 0L),
    mcmc_forecast_contract_crossing_pairs = c(0L, 0L),
    stringsAsFactors = FALSE
  )
  assessment <- data.frame(
    case_id = case_summary$case_id,
    phase136_gate_status = c("review", "review"),
    status_reason = c("rough ESS below review threshold", "rough ESS below review threshold"),
    max_rhat = c(1.001, 1.002),
    min_rough_ess_total = c(0, 0),
    max_gamma_rhat = c(NA_real_, NA_real_),
    min_gamma_rough_ess_total = c(0, 0),
    stringsAsFactors = FALSE
  )
  chain_jobs <- data.frame(
    job_id = paste0(rep(case_summary$case_id, each = 2), "__chain_", rep(1:2, times = 2)),
    case_id = rep(case_summary$case_id, each = 2),
    phase136_variant_id = "fixed_zero",
    chain_id = rep(1:2, times = 2),
    chain_seed = 14101:14104,
    stringsAsFactors = FALSE
  )
  chain_failures <- data.frame(
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
  rhat <- data.frame(
    case_id = rep(case_summary$case_id, each = 2),
    parameter = rep(c("sigma", "gamma"), times = 2),
    tau = 0.5,
    n_chains = 2L,
    n_draws_per_chain = 10L,
    rhat = c(1.001, NA_real_, 1.002, NA_real_),
    rough_ess_total = c(2500, 0, 2400, 0),
    stringsAsFactors = FALSE
  )
  runtime <- data.frame(
    case_id = rep(case_summary$case_id, each = 2),
    runtime_component = "mcmc_chain",
    chain_id = rep(1:2, times = 2),
    elapsed_seconds = c(10, 11, 9, 10),
    stringsAsFactors = FALSE
  )
  improvement <- data.frame(
    case_id = case_summary$case_id,
    fixed_forecast_mae = case_summary$mcmc_forecast_truth_mae,
    best_prev_tag = c("phase136_initial", "phase136_initial"),
    best_prev_forecast_mae = c(0.18, 0.11),
    abs_improvement = c(0.02, 0.01),
    pct_improvement = c(11.1, 9.1),
    stringsAsFactors = FALSE
  )
  best_prior <- data.frame(
    case_id = case_summary$case_id,
    best_prev_tag = improvement$best_prev_tag,
    best_prev_forecast_mae = improvement$best_prev_forecast_mae,
    stringsAsFactors = FALSE
  )
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(dir, "run_config.csv")),
    phase136_mcmc_case_summary = app_joint_qvp_write_csv(case_summary, file.path(dir, "phase136_mcmc_case_summary.csv")),
    phase136_case_assessment = app_joint_qvp_write_csv(assessment, file.path(dir, "phase136_case_assessment.csv")),
    phase136_chain_jobs = app_joint_qvp_write_csv(chain_jobs, file.path(dir, "phase136_chain_jobs.csv")),
    phase136_chain_worker_failures = app_joint_qvp_write_csv(chain_failures, file.path(dir, "phase136_chain_worker_failures.csv")),
    mcmc_rhat_ess_summary = app_joint_qvp_write_csv(rhat, file.path(dir, "mcmc_rhat_ess_summary.csv")),
    runtime_summary = app_joint_qvp_write_csv(runtime, file.path(dir, "runtime_summary.csv")),
    phase140_fixed_zero_improvement_vs_best_prior_gamma = app_joint_qvp_write_csv(improvement, file.path(dir, "phase140_fixed_zero_improvement_vs_best_prior_gamma.csv")),
    phase140_vs_prior_gamma_packet_best_by_case = app_joint_qvp_write_csv(best_prior, file.path(dir, "phase140_vs_prior_gamma_packet_best_by_case.csv"))
  )
  write_fake_manifest(paths, dir)
  invisible(dir)
}

stopifnot(abs(app_joint_exqdesn_phase136_parse_width_token("0p5") - 0.5) < 1.0e-12)
bounded <- app_joint_exqdesn_phase136_variant_spec("bounded_w1")
stopifnot(identical(bounded$gamma_update[[1L]], "bounded_slice"))
stopifnot(identical(bounded$bounded_width_multiplier[[1L]], 1))
logit <- app_joint_exqdesn_phase136_variant_spec("logit_w0p5")
stopifnot(identical(logit$gamma_update[[1L]], "logit_slice"))
stopifnot(abs(logit$logit_eta_width[[1L]] - 0.5) < 1.0e-12)
selected_cases <- data.frame(case_id = "case_a", scenario_id = "normal_bridge", stringsAsFactors = FALSE)
registry <- app_joint_exqdesn_phase136_variant_registry(
  selected_cases,
  variant_ids = c("bounded_w1", "logit_w0p5", "fixed_zero")
)
stopifnot(identical(registry$bounded_width_multiplier[registry$phase136_variant_id == "bounded_w1"], 1))
stopifnot(abs(registry$logit_eta_width[registry$phase136_variant_id == "logit_w0p5"] - 0.5) < 1.0e-12)
stopifnot(identical(registry$gamma_update[registry$phase136_variant_id == "fixed_zero"], "fixed"))

root <- tempfile("joint_exqdesn_phase141_")
fixed_dir <- file.path(root, "phase140_fixed")
out_dir <- file.path(root, "phase141")
make_phase140_fixed_like_artifact(fixed_dir)

result <- app_joint_exqdesn_run_phase141_gamma_redesign_readiness(
  out_dir = out_dir,
  fixed_gamma_dir = fixed_dir,
  launch_root = file.path(root, "cache"),
  n_cores = 4L
)

stopifnot(dir.exists(result$out_dir))
stopifnot(identical(result$decision$phase141_decision[[1L]], "ready_for_targeted_gamma_geometry_screen"))
stopifnot(identical(result$decision$fixed_gamma_zero_promoted_as_final_exal[[1L]], FALSE))
stopifnot(nrow(result$launch_plan) == 2L)
stopifnot(any(grepl("bounded_w1,logit_w1", result$launch_plan$variant_ids, fixed = TRUE)))
stopifnot(any(grepl("--variant-ids", result$launch_plan$command, fixed = TRUE)))
stopifnot(any(result$case_priority$phase141_priority_tier == "tier1_regime_shift"))
stopifnot(any(result$candidate_registry$phase141_variant_id == "bounded_w0p5"))

required_outputs <- c(
  "run_config.csv",
  "fixed_gamma_manifest_verification.csv",
  "phase141_diagnostic_summary.csv",
  "phase141_case_priority.csv",
  "phase141_variant_catalog.csv",
  "phase141_candidate_registry.csv",
  "phase141_method_feasibility.csv",
  "phase141_launch_plan.csv",
  "phase141_decision_summary.csv",
  "phase141_launch_commands.txt",
  "provenance.csv",
  "README.md",
  "artifact_manifest.csv"
)
stopifnot(all(file.exists(file.path(result$out_dir, required_outputs))))
manifest <- app_joint_qdesn_phase108_manifest_verify(result$out_dir, "phase141")
stopifnot(nrow(manifest) >= length(required_outputs) - 1L)
stopifnot(all(manifest$status == "pass"))

cat("Joint exQDESN Phase141 gamma-redesign readiness tests passed.\n")
