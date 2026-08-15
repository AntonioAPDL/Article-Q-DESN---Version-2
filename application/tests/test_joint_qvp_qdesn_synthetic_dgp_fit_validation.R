registry <- app_joint_qvp_load_synthetic_dgp_registry()
phase2_ids <- c("normal_bridge", "laplace_bridge")
phase2_registry <- registry[registry$scenario_id %in% phase2_ids, , drop = FALSE]
phase2_registry <- phase2_registry[match(phase2_ids, phase2_registry$scenario_id), , drop = FALSE]
phase2_registry$tau_grid <- "0.25,0.5,0.75"
phase2_registry$simulated_length <- 32L
phase2_registry$washout_length <- 6L
phase2_registry$train_length <- 14L
phase2_registry$test_length <- 12L
phase2_registry$seed <- c(202607021L, 202607022L)
app_joint_qvp_validate_synthetic_dgp_registry(phase2_registry)

phase1_dir <- tempfile("joint_qvp_phase2_fixture_")
phase1_result <- app_joint_qvp_materialize_synthetic_dgp_registry(
  out_dir = phase1_dir,
  registry = phase2_registry
)
phase1_manifest <- app_joint_qvp_verify_phase1_fixture_dir(phase1_result$out_dir)
stopifnot(all(phase1_manifest$file_exists))
stopifnot(all(phase1_manifest$hash_verified))

phase1_tables <- app_joint_qvp_load_phase1_fixture_tables(phase1_result$out_dir)
normal_train <- app_joint_qvp_phase2_train_fixture_from_tables(phase1_tables, "normal_bridge")
stopifnot(identical(normal_train$scenario_id, "normal_bridge"))
stopifnot(length(normal_train$y) == 14L)
stopifnot(all(normal_train$split == "train"))
stopifnot(min(normal_train$time_index) == normal_train$train_start)
stopifnot(max(normal_train$time_index) == normal_train$train_end)
stopifnot(!any(normal_train$time_index %in% phase1_tables$observed_series$time_index[
  phase1_tables$observed_series$scenario_id == "normal_bridge" &
    phase1_tables$observed_series$split == "test"
]))
stopifnot(all(is.finite(normal_train$y)))
stopifnot(all(is.finite(normal_train$Z)))
stopifnot(all(is.finite(normal_train$true_q)))
stopifnot(all(normal_train$sigma > 0))
stopifnot(sum(normal_train$crossing_diagnostics$n_crossing_pairs) == 0L)

phase2_dir <- tempfile("joint_qvp_phase2_fit_")
phase2_result <- app_joint_qvp_run_synthetic_dgp_fit_validation(
  out_dir = phase2_dir,
  fixture_dir = phase1_result$out_dir,
  scenario_ids = phase2_ids,
  mcmc_reference_scenarios = "normal_bridge",
  vb_max_iter = 16L,
  adaptive_vb_max_iter_grid = 16L,
  n_chains = 1L,
  mcmc_n_iter = 12L,
  mcmc_burn = 4L,
  mcmc_thin = 2L
)

expected_phase2_labels <- c(
  "run_config",
  "fixture_source_manifest",
  "fit_validation_assessment",
  "fit_summary",
  "truth_fit_summary",
  "pinball_summary",
  "hit_rate_summary",
  "crossing_summary",
  "vb_convergence_audit",
  "objective_diagnostics",
  "elbo_terms",
  "rhs_prior_summary",
  "mcmc_reference_summary",
  "mcmc_draw_summary",
  "chain_summary",
  "vb_mcmc_distance_summary",
  "runtime_summary",
  "provenance",
  "readme"
)
phase2_manifest <- utils::read.csv(file.path(phase2_result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(phase2_manifest$label, expected_phase2_labels))
stopifnot(all(nchar(phase2_manifest$sha256) == 64L))
for (ii in seq_len(nrow(phase2_manifest))) {
  artifact_path <- file.path(phase2_result$out_dir, phase2_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), phase2_manifest$sha256[[ii]]))
}

run_config <- utils::read.csv(file.path(phase2_result$out_dir, "run_config.csv"), stringsAsFactors = FALSE)
fit_summary <- utils::read.csv(file.path(phase2_result$out_dir, "fit_summary.csv"), stringsAsFactors = FALSE)
truth_fit_summary <- utils::read.csv(file.path(phase2_result$out_dir, "truth_fit_summary.csv"), stringsAsFactors = FALSE)
pinball_summary <- utils::read.csv(file.path(phase2_result$out_dir, "pinball_summary.csv"), stringsAsFactors = FALSE)
hit_rate_summary <- utils::read.csv(file.path(phase2_result$out_dir, "hit_rate_summary.csv"), stringsAsFactors = FALSE)
crossing_summary <- utils::read.csv(file.path(phase2_result$out_dir, "crossing_summary.csv"), stringsAsFactors = FALSE)
vb_convergence_audit <- utils::read.csv(file.path(phase2_result$out_dir, "vb_convergence_audit.csv"), stringsAsFactors = FALSE)
objective_diagnostics <- utils::read.csv(file.path(phase2_result$out_dir, "objective_diagnostics.csv"), stringsAsFactors = FALSE)
elbo_terms <- utils::read.csv(file.path(phase2_result$out_dir, "elbo_terms.csv"), stringsAsFactors = FALSE)
rhs_prior_summary <- utils::read.csv(file.path(phase2_result$out_dir, "rhs_prior_summary.csv"), stringsAsFactors = FALSE)
mcmc_reference_summary <- utils::read.csv(file.path(phase2_result$out_dir, "mcmc_reference_summary.csv"), stringsAsFactors = FALSE)
mcmc_draw_summary <- utils::read.csv(file.path(phase2_result$out_dir, "mcmc_draw_summary.csv"), stringsAsFactors = FALSE)
vb_mcmc_distance_summary <- utils::read.csv(file.path(phase2_result$out_dir, "vb_mcmc_distance_summary.csv"), stringsAsFactors = FALSE)
runtime_summary <- utils::read.csv(file.path(phase2_result$out_dir, "runtime_summary.csv"), stringsAsFactors = FALSE)
assessment <- utils::read.csv(file.path(phase2_result$out_dir, "fit_validation_assessment.csv"), stringsAsFactors = FALSE)

stopifnot(all(c("scenario_id", "n_train", "mcmc_reference", "no_test_leakage") %in% names(run_config)))
stopifnot(all(c("scenario_id", "fit", "inference", "truth_normalized_qhat_distance", "total_crossing_pairs", "no_test_leakage") %in% names(fit_summary)))
stopifnot(all(c("scenario_id", "fit", "quantile_index", "tau", "rmse_to_truth", "empirical_hit_rate") %in% names(truth_fit_summary)))
stopifnot(all(c("scenario_id", "fit", "tau", "pinball_mean", "n_train") %in% names(pinball_summary)))
stopifnot(all(c("scenario_id", "fit", "tau", "empirical_hit_rate", "hit_rate_minus_tau") %in% names(hit_rate_summary)))
stopifnot(all(c("scenario_id", "fit", "n_crossing_pairs") %in% names(crossing_summary)))
stopifnot(all(c("scenario_id", "attempt", "max_iter", "status") %in% names(vb_convergence_audit)))
stopifnot(all(c("scenario_id", "fit", "objective_status") %in% names(objective_diagnostics)))
stopifnot(all(c("scenario_id", "fit", "iter", "term", "value", "included_in_partial_elbo") %in% names(elbo_terms)))
stopifnot(all(c("scenario_id", "fit", "block", "mean_precision", "max_precision") %in% names(rhs_prior_summary)))
stopifnot(all(c("scenario_id", "reference_requested", "reference_status", "init_source") %in% names(mcmc_reference_summary)))
stopifnot(all(c("chain_id", "case_id", "block", "all_finite") %in% names(mcmc_draw_summary)))
stopifnot(all(c("case_id", "max_normalized_distance") %in% names(vb_mcmc_distance_summary)))
stopifnot(all(c("scenario_id", "component", "elapsed_sec") %in% names(runtime_summary)))
stopifnot(all(c("scenario_id", "implementation_status", "gate_status") %in% names(assessment)))

stopifnot(identical(sort(unique(run_config$scenario_id)), sort(phase2_ids)))
stopifnot(all(run_config$n_train == 14L))
stopifnot(all(run_config$no_test_leakage))
stopifnot(all(is.finite(fit_summary$truth_normalized_qhat_distance)))
stopifnot(all(is.finite(fit_summary$total_crossing_pairs)))
stopifnot(all(fit_summary$total_crossing_pairs >= 0L))
stopifnot(all(is.finite(truth_fit_summary$rmse_to_truth)))
stopifnot(all(is.finite(truth_fit_summary$empirical_hit_rate)))
stopifnot(all(is.finite(pinball_summary$pinball_mean)))
stopifnot(all(is.finite(hit_rate_summary$hit_rate_minus_tau)))
stopifnot(all(is.finite(crossing_summary$n_crossing_pairs)))
stopifnot(all(crossing_summary$n_crossing_pairs >= 0L))
stopifnot(all(is.finite(elbo_terms$value[elbo_terms$included_in_partial_elbo])))
stopifnot(all(is.finite(rhs_prior_summary$mean_precision)))
stopifnot(all(rhs_prior_summary$mean_precision > 0))
stopifnot(all(is.finite(runtime_summary$elapsed_sec)))
stopifnot(all(assessment$gate_status %in% c("pass", "review", "fail")))
vb_crossed_ids <- fit_summary$scenario_id[fit_summary$fit == "vb" & fit_summary$total_crossing_pairs > 0L]
if (length(vb_crossed_ids)) {
  stopifnot(all(assessment$gate_status[assessment$scenario_id %in% vb_crossed_ids] == "fail"))
}

normal_mcmc <- mcmc_reference_summary[mcmc_reference_summary$scenario_id == "normal_bridge", , drop = FALSE]
laplace_mcmc <- mcmc_reference_summary[mcmc_reference_summary$scenario_id == "laplace_bridge", , drop = FALSE]
stopifnot(nrow(normal_mcmc) == 1L)
stopifnot(isTRUE(normal_mcmc$reference_requested[[1L]]))
stopifnot(identical(normal_mcmc$init_source[[1L]], "provided"))
stopifnot(normal_mcmc$n_chains[[1L]] == 1L)
stopifnot(nrow(laplace_mcmc) == 1L)
stopifnot(!isTRUE(laplace_mcmc$reference_requested[[1L]]))
stopifnot(identical(laplace_mcmc$reference_status[[1L]], "skipped"))
stopifnot(all(mcmc_draw_summary$all_finite))
stopifnot(all(is.finite(vb_mcmc_distance_summary$max_normalized_distance)))

phase2_repeat_dir <- tempfile("joint_qvp_phase2_fit_repeat_")
phase2_repeat <- app_joint_qvp_run_synthetic_dgp_fit_validation(
  out_dir = phase2_repeat_dir,
  fixture_dir = phase1_result$out_dir,
  scenario_ids = phase2_ids,
  mcmc_reference_scenarios = "normal_bridge",
  vb_max_iter = 16L,
  adaptive_vb_max_iter_grid = 16L,
  n_chains = 1L,
  mcmc_n_iter = 12L,
  mcmc_burn = 4L,
  mcmc_thin = 2L
)
phase2_repeat_manifest <- utils::read.csv(file.path(phase2_repeat$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stable_labels <- setdiff(expected_phase2_labels, c("fit_summary", "runtime_summary"))
phase2_stable <- phase2_manifest[phase2_manifest$label %in% stable_labels, c("label", "sha256"), drop = FALSE]
phase2_repeat_stable <- phase2_repeat_manifest[phase2_repeat_manifest$label %in% stable_labels, c("label", "sha256"), drop = FALSE]
stopifnot(identical(phase2_stable$label, phase2_repeat_stable$label))
stopifnot(identical(phase2_stable$sha256, phase2_repeat_stable$sha256))
