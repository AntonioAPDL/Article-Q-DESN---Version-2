repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for Joint exQDESN Phase139 test.", call. = FALSE)
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
source(app_path("application/R/joint_exqdesn_phase137_gamma_kernel_readiness.R"))
source(app_path("application/R/joint_exqdesn_phase139_long_chain_synthesis.R"))

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

write_manifest <- function(paths, rel_paths, dir) {
  manifest <- data.frame(
    label = names(paths),
    relative_path = rel_paths,
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  app_joint_qvp_write_csv(manifest, file.path(dir, "artifact_manifest.csv"))
}

empty_failures <- function() {
  data.frame(worker = character(), reason = character(), stringsAsFactors = FALSE)
}

case_rows <- function(case_id, scenario_id, source_model_id, variant, gamma_update,
                      forecast, fit, gamma_rhat, gamma_ess, lag1, status_reason) {
  data.frame(
    case_id = case_id,
    scenario_id = scenario_id,
    scenario_class = "stress",
    distribution_family = "toy",
    dynamics_class = "toy",
    source_candidate_id = paste0(case_id, "__source"),
    source_model_id = source_model_id,
    model_id = sub("_vb$", "_mcmc", source_model_id),
    display_label = "Joint exQDESN RHS MCMC",
    likelihood = "exal",
    fit_structure = "joint",
    inference = "MCMC",
    experiment_id = variant,
    variant_id = variant,
    phase136_variant_id = variant,
    phase136_case_variant_id = paste(case_id, variant, sep = "__"),
    gamma_update = gamma_update,
    width_multiplier = if (identical(variant, "bounded_w4")) 4 else NA_real_,
    logit_eta_width = if (identical(variant, "logit_w4")) 4 else NA_real_,
    gamma_slice_width_summary = "4,4,4,4,4,4,4",
    phase136_gate_status = "review",
    mcmc_fit_truth_mae = fit,
    mcmc_forecast_truth_mae = forecast,
    mcmc_fit_check_loss_mean = fit + 0.01,
    mcmc_forecast_check_loss_mean = forecast + 0.01,
    mcmc_fit_raw_crossing_pairs = 0L,
    mcmc_forecast_raw_crossing_pairs = 0L,
    mcmc_fit_contract_crossing_pairs = 0L,
    mcmc_forecast_contract_crossing_pairs = 0L,
    max_rhat = gamma_rhat,
    min_rough_ess_total = gamma_ess,
    max_gamma_rhat = gamma_rhat,
    min_gamma_rough_ess_total = gamma_ess,
    max_gamma_chain_mean_gap = 0.2,
    max_gamma_lag1_autocorrelation = lag1,
    max_sigma_upper_bound_hit_fraction = 0,
    status_reason = status_reason,
    stringsAsFactors = FALSE
  )
}

write_phase136_like <- function(dir, rows, phase135_audit_dir, figure_repair = FALSE) {
  app_ensure_dir(dir)
  if (figure_repair) app_ensure_dir(file.path(dir, "figures"))
  run_config <- data.frame(
    run_id = "fake_phase136_like",
    phase135_screening_dir = "fake_phase135_screening",
    phase135_audit_dir = phase135_audit_dir,
    fixture_dir = "fake_fixture",
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
  paths <- c(run_config = app_joint_qvp_write_csv(run_config, file.path(dir, "run_config.csv")))
  chain_jobs <- data.frame(job_id = paste0("job_", seq_len(8L)), stringsAsFactors = FALSE)
  runtime <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(rows)), function(ii) {
    row <- rows[ii, , drop = FALSE]
    meta <- row[, c("case_id", "scenario_id", "scenario_class", "distribution_family", "dynamics_class",
                    "source_candidate_id", "source_model_id", "model_id", "display_label", "likelihood",
                    "fit_structure", "inference", "experiment_id", "variant_id", "phase136_variant_id",
                    "phase136_case_variant_id", "gamma_update", "width_multiplier", "logit_eta_width")]
    meta <- meta[rep(1L, 4L), , drop = FALSE]
    row.names(meta) <- NULL
    data.frame(
      meta,
      runtime_component = "mcmc_chain",
      chain_id = seq_len(4L),
      chain_seed = 1000L + seq_len(4L),
      elapsed_seconds = 100 + 10 * seq_len(4L),
      sec_per_iter = 0.01,
      stringsAsFactors = FALSE
    )
  }))
  rhat <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(rows)), function(ii) {
    row <- rows[ii, , drop = FALSE]
    meta <- row[, c("case_id", "scenario_id", "scenario_class", "distribution_family", "dynamics_class",
                    "source_candidate_id", "source_model_id", "model_id", "display_label", "likelihood",
                    "fit_structure", "inference", "experiment_id", "variant_id", "phase136_variant_id",
                    "phase136_case_variant_id", "gamma_update", "width_multiplier", "logit_eta_width")]
    meta <- meta[rep(1L, 2L), , drop = FALSE]
    row.names(meta) <- NULL
    data.frame(
      meta,
      parameter = "gamma",
      quantile_index = seq_len(2L),
      tau = c(0.10, 0.90),
      n_chains = 4L,
      n_draws_per_chain = 50L,
      rhat = c(row$max_gamma_rhat[[1L]], row$max_gamma_rhat[[1L]] - 0.01),
      rough_ess_total = c(row$min_gamma_rough_ess_total[[1L]], row$min_gamma_rough_ess_total[[1L]] + 10),
      stringsAsFactors = FALSE
    )
  }))
  ac <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(rows)), function(ii) {
    row <- rows[ii, , drop = FALSE]
    meta <- data.frame(
      case_id = row$case_id,
      scenario_id = row$scenario_id,
      model_id = row$model_id,
      experiment_id = row$experiment_id,
      variant_id = row$variant_id,
      width_multiplier = row$width_multiplier,
      stringsAsFactors = FALSE
    )
    meta <- meta[rep(1L, 2L), , drop = FALSE]
    row.names(meta) <- NULL
    data.frame(
      meta,
      chain_id = 1L,
      chain_seed = 1001L,
      quantile_index = seq_len(2L),
      tau = c(0.10, 0.90),
      parameter = "gamma",
      lag = 1L,
      autocorrelation = c(row$max_gamma_lag1_autocorrelation[[1L]], row$max_gamma_lag1_autocorrelation[[1L]] - 0.001),
      stringsAsFactors = FALSE
    )
  }))
  best <- rows
  best$phase136_recommendation <- "fake_best"
  paths <- c(paths,
    phase136_selected_cases = app_joint_qvp_write_csv(unique(rows[, c("case_id", "scenario_id", "source_model_id")]), file.path(dir, "phase136_selected_cases.csv")),
    phase136_variant_registry = app_joint_qvp_write_csv(rows, file.path(dir, "phase136_variant_registry.csv")),
    phase136_chain_jobs = app_joint_qvp_write_csv(chain_jobs, file.path(dir, "phase136_chain_jobs.csv")),
    phase136_case_variant_prep_failures = app_joint_qvp_write_csv(empty_failures(), file.path(dir, "phase136_case_variant_prep_failures.csv")),
    phase136_chain_worker_failures = app_joint_qvp_write_csv(empty_failures(), file.path(dir, "phase136_chain_worker_failures.csv")),
    phase136_mcmc_case_summary = app_joint_qvp_write_csv(rows, file.path(dir, "phase136_mcmc_case_summary.csv")),
    phase136_case_assessment = app_joint_qvp_write_csv(rows, file.path(dir, "phase136_case_assessment.csv")),
    phase136_best_variant_by_case = app_joint_qvp_write_csv(best, file.path(dir, "phase136_best_variant_by_case.csv")),
    runtime_summary = app_joint_qvp_write_csv(runtime, file.path(dir, "runtime_summary.csv")),
    mcmc_rhat_ess_summary = app_joint_qvp_write_csv(rhat, file.path(dir, "mcmc_rhat_ess_summary.csv")),
    autocorrelation_summary = app_joint_qvp_write_csv(ac, file.path(dir, "autocorrelation_summary.csv"))
  )
  if (figure_repair) {
    figure_path <- file.path(dir, "figures", "trace.pdf")
    writeLines("fake figure", figure_path, useBytes = TRUE)
    paths <- c(paths, trace = figure_path)
    rel_paths <- c(basename(paths[-length(paths)]), "trace.pdf")
  } else {
    rel_paths <- basename(paths)
  }
  invisible(write_manifest(paths, rel_paths, dir))
}

root <- tempfile("joint_exqdesn_phase139_")
phase135_screen <- file.path(root, "phase135_screen")
phase135_audit <- file.path(root, "phase135_audit")
phase136_dir <- file.path(root, "phase136")
phase137_dir <- file.path(root, "phase137")
phase138_bounded <- file.path(root, "phase138_bounded")
phase138_logit <- file.path(root, "phase138_logit")
phase138_orch <- file.path(root, "phase138_orch")
out_dir <- file.path(root, "phase139")
app_ensure_dir(phase135_screen)
app_ensure_dir(phase135_audit)
app_ensure_dir(phase137_dir)
app_ensure_dir(phase138_orch)

dummy_screen <- app_joint_qvp_write_csv(data.frame(x = 1), file.path(phase135_screen, "dummy.csv"))
invisible(write_manifest(c(dummy = dummy_screen), "dummy.csv", phase135_screen))

comparison <- data.frame(
  scenario_id = c("case_a", "case_b"),
  pair_id = "joint_matched_to_joint_al",
  comparison_class = "joint",
  source_al_model_id = "joint_qdesn_rhs_vb",
  target_exal_model_id = "joint_exqdesn_rhs_vb",
  al_fit_mae = c(0.08, 0.10),
  exal_fit_mae = c(0.12, 0.20),
  fit_delta_exal_minus_al = c(0.04, 0.10),
  fit_relative_delta_exal_minus_al = c(0.50, 1.00),
  al_forecast_mae = c(0.09, 0.11),
  exal_forecast_mae = c(0.13, 0.22),
  forecast_delta_exal_minus_al = c(0.04, 0.11),
  forecast_relative_delta_exal_minus_al = c(0.44, 1.00),
  al_fit_check_loss = c(0.1, 0.1),
  exal_fit_check_loss = c(0.11, 0.11),
  al_forecast_check_loss = c(0.12, 0.12),
  exal_forecast_check_loss = c(0.13, 0.13),
  al_fit_gate_status = "pass",
  al_forecast_gate_status = "pass",
  exal_gate_status = "pass",
  al_forecast_raw_crossings = 0L,
  exal_forecast_raw_crossings = 0L,
  al_forecast_contract_crossings = 0L,
  exal_forecast_contract_crossings = 0L,
  al_forecast_max_adjustment = 0,
  exal_forecast_max_adjustment = 0,
  al_fit_reached_max_iter = FALSE,
  al_forecast_reached_max_iter = FALSE,
  exal_fit_reached_max_iter = FALSE,
  exal_forecast_reached_max_iter = FALSE,
  exal_underperforms_al_fit = TRUE,
  exal_underperforms_al_forecast = TRUE,
  phase135_result_class = "exal_matched_spec_underperforms_al",
  article_mcmc_promotion_status = "hold_until_gamma_mixing_mcmc_protocol",
  stringsAsFactors = FALSE
)
decision135 <- data.frame(phase135_decision = "fake_review", stringsAsFactors = FALSE)
paths135 <- c(
  comparison = app_joint_qvp_write_csv(comparison, file.path(phase135_audit, "phase135_matched_exal_vs_source_al_vb_comparison.csv")),
  decision = app_joint_qvp_write_csv(decision135, file.path(phase135_audit, "phase135_result_decision.csv"))
)
invisible(write_manifest(paths135, basename(paths135), phase135_audit))

rows136 <- app_joint_qdesn_bind_rows(list(
  case_rows("case_a__joint_exqdesn_rhs_vb", "case_a", "joint_exqdesn_rhs_vb", "bounded_w4", "bounded_slice", 0.10, 0.10, 1.10, 120, 0.998, "gamma lag-1 autocorrelation remains high"),
  case_rows("case_b__joint_exqdesn_rhs_vb", "case_b", "joint_exqdesn_rhs_vb", "logit_w4", "logit_slice", 0.20, 0.20, 1.30, 100, 0.999, "MCMC Rhat exceeds review threshold; gamma lag-1 autocorrelation remains high")
))
write_phase136_like(phase136_dir, rows136, phase135_audit, figure_repair = TRUE)
writeLines("0", paste0(phase136_dir, ".exit"), useBytes = TRUE)

selected137 <- rows136
selected137$phase137_selection_status <- "selected_for_long_chain_confirmation"
launch137 <- data.frame(
  launch_group_id = c("selected_bounded_w4", "selected_logit_w4"),
  phase136_variant_id = c("bounded_w4", "logit_w4"),
  n_cases = 1L,
  total_chain_jobs = 4L,
  mcmc_n_iter = 16000L,
  n_cores = 4L,
  launched_in_phase137 = FALSE,
  stringsAsFactors = FALSE
)
decision137 <- data.frame(phase137_decision = "review_ready_for_selected_long_chain_confirmation", stringsAsFactors = FALSE)
paths137 <- c(
  selected = app_joint_qvp_write_csv(selected137, file.path(phase137_dir, "phase137_selected_case_kernel_registry.csv")),
  launch = app_joint_qvp_write_csv(launch137, file.path(phase137_dir, "phase137_next_launch_plan.csv")),
  decision = app_joint_qvp_write_csv(decision137, file.path(phase137_dir, "phase137_decision_summary.csv"))
)
invisible(write_manifest(paths137, basename(paths137), phase137_dir))

rows138_bounded <- case_rows("case_a__joint_exqdesn_rhs_vb", "case_a", "joint_exqdesn_rhs_vb", "bounded_w4", "bounded_slice", 0.11, 0.11, 1.18, 240, 0.999, "gamma lag-1 autocorrelation remains high")
rows138_logit <- case_rows("case_b__joint_exqdesn_rhs_vb", "case_b", "joint_exqdesn_rhs_vb", "logit_w4", "logit_slice", 0.18, 0.19, 1.12, 260, 0.999, "gamma lag-1 autocorrelation remains high")
write_phase136_like(phase138_bounded, rows138_bounded, phase135_audit, figure_repair = TRUE)
write_phase136_like(phase138_logit, rows138_logit, phase135_audit, figure_repair = TRUE)

writeLines("0", file.path(phase138_orch, "01_selected_bounded_w4.exit"), useBytes = TRUE)
writeLines("0", file.path(phase138_orch, "02_selected_logit_w4.exit"), useBytes = TRUE)
writeLines("0", file.path(phase138_orch, "phase138_scheduler.exit"), useBytes = TRUE)
orch_dummy <- app_joint_qvp_write_csv(data.frame(x = 1), file.path(phase138_orch, "phase138_orchestration_plan.csv"))
invisible(write_manifest(c(plan = orch_dummy), "phase138_orchestration_plan.csv", phase138_orch))

result <- app_joint_exqdesn_run_phase139_long_chain_synthesis(
  out_dir = out_dir,
  phase135_screening_dir = phase135_screen,
  phase135_audit_dir = phase135_audit,
  phase136_dir = phase136_dir,
  phase137_dir = phase137_dir,
  phase138_dirs = c(bounded_w4 = phase138_bounded, logit_w4 = phase138_logit),
  phase138_orchestration_dir = phase138_orch
)

stopifnot(file.exists(file.path(out_dir, "phase139_decision_summary.csv")))
stopifnot(file.exists(file.path(out_dir, "phase139_exal_vs_matched_al.csv")))
stopifnot(file.exists(file.path(out_dir, "phase139_phase138_vs_phase136.csv")))
stopifnot(nrow(result$vs136) == 2L)
stopifnot(nrow(result$exal_vs_al) == 2L)
stopifnot(any(result$manifest_audit$figure_path_repair_rows > 0L))
if (!identical(result$decision$phase139_decision[[1L]], "review_do_not_promote_exal_as_article_winner")) {
  print(result$decision)
  print(result$health)
  stop("Unexpected Phase139 decision in synthetic fixture.", call. = FALSE)
}
stopifnot(result$decision$phase138_forecast_improved_vs_phase136_cases[[1L]] == 1L)
stopifnot(result$decision$phase138_matches_or_beats_matched_al_forecast_cases[[1L]] == 0L)
manifest <- check_manifest(out_dir)
stopifnot("phase139_decision_summary" %in% manifest$label)

cat("test_joint_exqdesn_phase139_long_chain_synthesis passed\n")
