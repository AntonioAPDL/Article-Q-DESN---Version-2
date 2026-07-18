repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for Joint exQDESN Phase137 test.", call. = FALSE)
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
source(app_path("application/R/joint_exqdesn_phase137_gamma_kernel_readiness.R"))

check_manifest <- function(dir) {
  manifest <- utils::read.csv(file.path(dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
  stopifnot(nrow(manifest) > 0L)
  stopifnot(all(nchar(manifest$sha256) == 64L))
  for (ii in seq_len(nrow(manifest))) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    stopifnot(file.exists(path))
    stopifnot(identical(app_sha256_file(path), manifest$sha256[[ii]]))
  }
  manifest
}

write_phase136_manifest <- function(paths, rel_paths, dir) {
  manifest <- data.frame(
    label = names(paths),
    relative_path = rel_paths,
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  app_joint_qvp_write_csv(manifest, file.path(dir, "artifact_manifest.csv"))
}

phase136_dir <- tempfile("joint_exqdesn_phase137_phase136_")
phase135_audit_dir <- tempfile("joint_exqdesn_phase137_phase135_audit_")
out_dir <- tempfile("joint_exqdesn_phase137_out_")
app_ensure_dir(phase136_dir)
app_ensure_dir(file.path(phase136_dir, "figures"))
app_ensure_dir(phase135_audit_dir)

run_config <- data.frame(
  run_id = "fake_phase136",
  phase135_screening_dir = "fake_phase135_screening",
  phase135_audit_dir = phase135_audit_dir,
  fixture_dir = "fake_fixture_dir",
  bounded_width_multiplier = 4,
  logit_eta_width = 4,
  gamma_slice_max_steps = 100L,
  chain_seed_stride = 100L,
  sigma_upper_multiplier = 50,
  gamma_init_mode = "vb_jittered",
  gamma_jitter_fraction = 0.10,
  trace_write_stride = 50L,
  stringsAsFactors = FALSE
)
paths <- c(run_config = app_joint_qvp_write_csv(run_config, file.path(phase136_dir, "run_config.csv")))

case_rows <- data.frame(
  case_id = rep(c("case_a__joint_exqdesn_rhs_vb", "case_b__joint_exqdesn_rhs_vb"), each = 2),
  scenario_id = rep(c("case_a", "case_b"), each = 2),
  scenario_class = "stress",
  distribution_family = "toy",
  dynamics_class = "toy",
  source_candidate_id = "source",
  source_model_id = "joint_exqdesn_rhs_vb",
  model_id = "joint_exqdesn_rhs_mcmc",
  display_label = "Joint exQDESN RHS MCMC",
  likelihood = "exal",
  fit_structure = "joint",
  inference = "MCMC",
  experiment_id = rep(c("bounded_w4", "logit_w4"), times = 2),
  variant_id = rep(c("bounded_w4", "logit_w4"), times = 2),
  phase136_variant_id = rep(c("bounded_w4", "logit_w4"), times = 2),
  phase136_case_variant_id = paste(rep(c("case_a__joint_exqdesn_rhs_vb", "case_b__joint_exqdesn_rhs_vb"), each = 2), rep(c("bounded_w4", "logit_w4"), times = 2), sep = "__"),
  gamma_update = rep(c("bounded_slice", "logit_slice"), times = 2),
  width_multiplier = c(4, NA, 4, NA),
  logit_eta_width = c(NA, 4, NA, 4),
  phase136_gate_status = "review",
  mcmc_fit_truth_mae = c(0.10, 0.11, 0.15, 0.13),
  mcmc_forecast_truth_mae = c(0.20, 0.22, 0.30, 0.25),
  mcmc_fit_check_loss_mean = c(0.09, 0.10, 0.12, 0.11),
  mcmc_forecast_check_loss_mean = c(0.18, 0.19, 0.23, 0.21),
  mcmc_fit_raw_crossing_pairs = 0L,
  mcmc_forecast_raw_crossing_pairs = 0L,
  mcmc_fit_contract_crossing_pairs = 0L,
  mcmc_forecast_contract_crossing_pairs = 0L,
  max_rhat = c(1.10, 1.12, 1.25, 1.15),
  min_rough_ess_total = c(180, 175, 130, 160),
  max_gamma_rhat = c(1.08, 1.09, 1.23, 1.10),
  min_gamma_rough_ess_total = c(160, 150, 120, 155),
  max_gamma_chain_mean_gap = c(0.2, 0.2, 0.5, 0.3),
  max_gamma_lag1_autocorrelation = c(0.995, 0.994, 0.996, 0.993),
  max_sigma_upper_bound_hit_fraction = 0,
  status_reason = "gamma lag-1 autocorrelation remains high",
  stringsAsFactors = FALSE
)
best_rows <- case_rows[c(1, 4), , drop = FALSE]
best_rows$phase136_recommendation <- c(
  "retain_bounded_slice_reference_or_compare_with_longer_run",
  "candidate_logit_gamma_update_for_next_packet"
)

paths <- c(paths,
  phase136_selected_cases = app_joint_qvp_write_csv(unique(case_rows[, c("case_id", "scenario_id", "source_model_id")]), file.path(phase136_dir, "phase136_selected_cases.csv")),
  phase136_variant_registry = app_joint_qvp_write_csv(case_rows, file.path(phase136_dir, "phase136_variant_registry.csv")),
  phase136_chain_jobs = app_joint_qvp_write_csv(data.frame(job_id = paste0("job_", 1:8), stringsAsFactors = FALSE), file.path(phase136_dir, "phase136_chain_jobs.csv")),
  phase136_case_variant_prep_failures = app_joint_qvp_write_csv(data.frame(worker = character(), reason = character()), file.path(phase136_dir, "phase136_case_variant_prep_failures.csv")),
  phase136_chain_worker_failures = app_joint_qvp_write_csv(data.frame(worker = character(), reason = character()), file.path(phase136_dir, "phase136_chain_worker_failures.csv")),
  phase136_mcmc_case_summary = app_joint_qvp_write_csv(case_rows, file.path(phase136_dir, "phase136_mcmc_case_summary.csv")),
  phase136_case_assessment = app_joint_qvp_write_csv(case_rows, file.path(phase136_dir, "phase136_case_assessment.csv")),
  phase136_best_variant_by_case = app_joint_qvp_write_csv(best_rows, file.path(phase136_dir, "phase136_best_variant_by_case.csv")),
  runtime_summary = app_joint_qvp_write_csv(data.frame(
    phase136_variant_id = rep(c("bounded_w4", "logit_w4"), each = 2),
    runtime_component = "mcmc_chain",
    elapsed_seconds = c(100, 120, 110, 130),
    stringsAsFactors = FALSE
  ), file.path(phase136_dir, "runtime_summary.csv")),
  mcmc_rhat_ess_summary = app_joint_qvp_write_csv(data.frame(
    phase136_variant_id = rep(c("bounded_w4", "logit_w4"), each = 2),
    parameter = "gamma",
    rhat = c(1.08, 1.12, 1.09, 1.15),
    rough_ess_total = c(150, 160, 140, 155),
    stringsAsFactors = FALSE
  ), file.path(phase136_dir, "mcmc_rhat_ess_summary.csv")),
  autocorrelation_summary = app_joint_qvp_write_csv(data.frame(
    variant_id = rep(c("bounded_w4", "logit_w4"), each = 2),
    parameter = "gamma",
    lag = 1L,
    autocorrelation = c(0.995, 0.996, 0.994, 0.993),
    stringsAsFactors = FALSE
  ), file.path(phase136_dir, "autocorrelation_summary.csv"))
)

figure_path <- file.path(phase136_dir, "figures", "phase136_trace_fake.pdf")
writeLines("not a real pdf, only a hash fixture", figure_path, useBytes = TRUE)
paths <- c(paths, figure = figure_path)
invisible(write_phase136_manifest(paths, basename(paths), phase136_dir))
writeLines("0", paste0(phase136_dir, ".exit"), useBytes = TRUE)

comparison <- data.frame(
  scenario_id = c("case_a", "case_b"),
  target_exal_model_id = "joint_exqdesn_rhs_vb",
  source_al_model_id = "joint_qdesn_rhs_vb",
  al_fit_mae = c(0.08, 0.10),
  exal_fit_mae = c(0.12, 0.16),
  al_forecast_mae = c(0.16, 0.18),
  exal_forecast_mae = c(0.24, 0.32),
  fit_delta_exal_minus_al = c(0.04, 0.06),
  forecast_delta_exal_minus_al = c(0.08, 0.14),
  stringsAsFactors = FALSE
)
invisible(app_joint_qvp_write_csv(comparison, file.path(phase135_audit_dir, "phase135_matched_exal_vs_source_al_vb_comparison.csv")))

result <- app_joint_exqdesn_run_phase137_gamma_kernel_readiness(
  out_dir = out_dir,
  phase136_dir = phase136_dir,
  next_n_chains = 8L,
  next_mcmc_n_iter = 16000L,
  next_mcmc_burn = 4000L,
  next_mcmc_thin = 1L,
  next_mcmc_seed_offset = 8600L
)

manifest <- check_manifest(result$out_dir)
expected_labels <- c(
  "run_config",
  "phase136_manifest_strict_verification",
  "phase136_manifest_repaired_verification",
  "phase136_manifest_repair_map",
  "phase137_health_summary",
  "phase137_kernel_variant_summary",
  "phase137_case_delta_summary",
  "phase137_phase136_vs_phase135_summary",
  "phase137_selected_case_kernel_registry",
  "phase137_next_launch_plan",
  "phase137_decision_summary",
  "phase137_launch_commands",
  "provenance",
  "readme"
)
stopifnot(identical(manifest$label, expected_labels))

strict <- utils::read.csv(file.path(result$out_dir, "phase136_manifest_strict_verification.csv"), stringsAsFactors = FALSE)
repaired <- utils::read.csv(file.path(result$out_dir, "phase136_manifest_repaired_verification.csv"), stringsAsFactors = FALSE)
repair_map <- utils::read.csv(file.path(result$out_dir, "phase136_manifest_repair_map.csv"), stringsAsFactors = FALSE)
decision <- utils::read.csv(file.path(result$out_dir, "phase137_decision_summary.csv"), stringsAsFactors = FALSE)
health <- utils::read.csv(file.path(result$out_dir, "phase137_health_summary.csv"), stringsAsFactors = FALSE)
launch <- utils::read.csv(file.path(result$out_dir, "phase137_next_launch_plan.csv"), stringsAsFactors = FALSE)
registry <- utils::read.csv(file.path(result$out_dir, "phase137_selected_case_kernel_registry.csv"), stringsAsFactors = FALSE)
comparison_out <- utils::read.csv(file.path(result$out_dir, "phase137_phase136_vs_phase135_summary.csv"), stringsAsFactors = FALSE)

stopifnot(any(strict$status == "fail"))
stopifnot(all(repaired$status == "pass"))
stopifnot(nrow(repair_map) == 1L)
stopifnot(repair_map$repair_action[[1L]] == "figures_subdir_path_repair")
stopifnot(decision$phase137_decision[[1L]] == "review_ready_for_selected_long_chain_confirmation")
stopifnot(decision$mcmc_launched_in_phase137[[1L]] == "FALSE" || identical(decision$mcmc_launched_in_phase137[[1L]], FALSE))
stopifnot(any(health$check == "Strict artifact manifest" & health$status == "review"))
stopifnot(any(health$check == "Path-repaired artifact manifest" & health$status == "pass"))
stopifnot(nrow(registry) == 2L)
stopifnot(identical(sort(unique(registry$phase136_variant_id)), c("bounded_w4", "logit_w4")))
stopifnot(nrow(launch) == 2L)
stopifnot(all(launch$launched_in_phase137 == "FALSE" | launch$launched_in_phase137 == FALSE))
stopifnot(all(grepl("145_run_joint_exqdesn_phase136_gamma_kernel_packet.R", launch$command, fixed = TRUE)))
stopifnot(all(grepl("--mcmc-n-iter 16000", launch$command, fixed = TRUE)))
stopifnot(nrow(comparison_out) == 2L)
stopifnot(all(is.finite(comparison_out$phase136_mcmc_minus_phase135_exal_vb_forecast_mae)))

cat("joint_exqdesn_phase137_gamma_kernel_readiness tests passed\n")
