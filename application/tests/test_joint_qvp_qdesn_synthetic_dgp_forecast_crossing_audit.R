phase4c_dir <- tempfile("joint_qvp_phase4c_source_")
phase4c_phase3_dir <- file.path(phase4c_dir, "phase3_forecast_validation")
dir.create(phase4c_phase3_dir, recursive = TRUE, showWarnings = FALSE)

tau <- c(0.10, 0.50, 0.90)
qraw <- c(1.0, 0.8, 2.0)
contract <- app_joint_qvp_phase3_contract_forecast(qraw, tau)
stopifnot(contract$n_raw_crossing_pairs == 1L)
stopifnot(contract$n_contract_crossing_pairs == 0L)
stopifnot(all(diff(contract$qhat_contract) >= -1.0e-10))

calibration_registry <- data.frame(
  scenario_id = "toy_crossing__calibration_r02",
  base_scenario_id = "toy_crossing",
  replicate_id = 2L,
  validation_tier = "calibration",
  seed = 202607999L,
  seed_role = "calibration_replicate_seed",
  stringsAsFactors = FALSE
)
run_config <- data.frame(
  scenario_id = "toy_crossing__calibration_r02",
  scenario_class = "stress",
  distribution_family = "gaussian_mixture",
  dynamics_class = "toy_crossing",
  seed = 202607999L,
  stringsAsFactors = FALSE
)
forecast_origin_config <- data.frame(
  scenario_id = "toy_crossing__calibration_r02",
  origin_index = 1L,
  forecast_time_index = 801L,
  forecast_retained_index = 501L,
  target_y = 0.9,
  refit = TRUE,
  fit_origin_index = 1L,
  used_fit_n = 500L,
  used_previous_test_n = 0L,
  stringsAsFactors = FALSE
)
forecast_quantiles_raw <- data.frame(
  scenario_id = "toy_crossing__calibration_r02",
  method = "vb_raw",
  origin_index = 1L,
  forecast_time_index = 801L,
  quantile_index = seq_along(tau),
  tau = tau,
  qhat = qraw,
  true_quantile = c(0.6, 1.0, 1.6),
  stringsAsFactors = FALSE
)
forecast_quantiles <- forecast_quantiles_raw
forecast_quantiles$method <- "vb"
forecast_quantiles$qhat <- contract$qhat_contract
raw_crossing_summary <- cbind(
  data.frame(
    scenario_id = "toy_crossing__calibration_r02",
    method = "vb_raw",
    origin_index = 1L,
    forecast_time_index = 801L,
    stringsAsFactors = FALSE
  ),
  app_joint_qvp_crossing_diagnostics(matrix(qraw, nrow = 1L), tau)
)
crossing_summary <- cbind(
  data.frame(
    scenario_id = "toy_crossing__calibration_r02",
    method = "vb",
    origin_index = 1L,
    forecast_time_index = 801L,
    stringsAsFactors = FALSE
  ),
  app_joint_qvp_crossing_diagnostics(matrix(contract$qhat_contract, nrow = 1L), tau)
)
forecast_monotone_adjustment <- data.frame(
  scenario_id = "toy_crossing__calibration_r02",
  method = "vb",
  origin_index = 1L,
  forecast_time_index = 801L,
  n_adjusted_quantiles = contract$n_adjusted_quantiles,
  max_abs_adjustment = contract$max_abs_adjustment,
  sum_abs_adjustment = contract$sum_abs_adjustment,
  n_raw_crossing_pairs = contract$n_raw_crossing_pairs,
  raw_max_crossing_magnitude = contract$raw_max_crossing_magnitude,
  n_contract_crossing_pairs = contract$n_contract_crossing_pairs,
  affected_tau_pairs = contract$affected_tau_pairs,
  adjustment_status = "review",
  stringsAsFactors = FALSE
)
vb_convergence_audit <- data.frame(
  scenario_id = "toy_crossing__calibration_r02",
  origin_index = 1L,
  forecast_time_index = 801L,
  refit = TRUE,
  fit_origin_index = 1L,
  status = "prototype_max_iter",
  converged = FALSE,
  n_iter = 240L,
  stringsAsFactors = FALSE
)

phase4c_paths <- c(
  calibration_registry = app_joint_qvp_write_csv(calibration_registry, file.path(phase4c_dir, "calibration_registry.csv")),
  run_config = app_joint_qvp_write_csv(run_config, file.path(phase4c_phase3_dir, "run_config.csv")),
  forecast_origin_config = app_joint_qvp_write_csv(forecast_origin_config, file.path(phase4c_phase3_dir, "forecast_origin_config.csv")),
  forecast_quantiles_raw = app_joint_qvp_write_csv(forecast_quantiles_raw, file.path(phase4c_phase3_dir, "forecast_quantiles_raw.csv")),
  forecast_quantiles = app_joint_qvp_write_csv(forecast_quantiles, file.path(phase4c_phase3_dir, "forecast_quantiles.csv")),
  forecast_monotone_adjustment = app_joint_qvp_write_csv(forecast_monotone_adjustment, file.path(phase4c_phase3_dir, "forecast_monotone_adjustment.csv")),
  raw_crossing_summary = app_joint_qvp_write_csv(raw_crossing_summary, file.path(phase4c_phase3_dir, "raw_crossing_summary.csv")),
  crossing_summary = app_joint_qvp_write_csv(crossing_summary, file.path(phase4c_phase3_dir, "crossing_summary.csv")),
  vb_convergence_audit = app_joint_qvp_write_csv(vb_convergence_audit, file.path(phase4c_phase3_dir, "vb_convergence_audit.csv"))
)
phase3_manifest <- data.frame(
  label = names(phase4c_paths)[names(phase4c_paths) != "calibration_registry"],
  relative_path = basename(phase4c_paths[names(phase4c_paths) != "calibration_registry"]),
  size_bytes = as.numeric(file.info(phase4c_paths[names(phase4c_paths) != "calibration_registry"])$size),
  sha256 = vapply(phase4c_paths[names(phase4c_paths) != "calibration_registry"], app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
app_joint_qvp_write_csv(phase3_manifest, file.path(phase4c_phase3_dir, "artifact_manifest.csv"))

phase4c_out <- tempfile("joint_qvp_phase4c_audit_")
phase4c_result <- app_joint_qvp_audit_synthetic_dgp_forecast_crossings(
  artifact_dir = phase4c_dir,
  out_dir = phase4c_out
)

expected_phase4c_labels <- c(
  "crossing_event_audit",
  "crossing_origin_context",
  "crossing_pair_detail",
  "crossing_vb_context",
  "crossing_remediation_recommendation",
  "provenance",
  "readme",
  "targeted_crossing_registry"
)
phase4c_manifest <- utils::read.csv(file.path(phase4c_result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(phase4c_manifest$label, expected_phase4c_labels))
stopifnot(all(nchar(phase4c_manifest$sha256) == 64L))
for (ii in seq_len(nrow(phase4c_manifest))) {
  artifact_path <- file.path(phase4c_result$out_dir, phase4c_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), phase4c_manifest$sha256[[ii]]))
}

event_audit <- utils::read.csv(file.path(phase4c_result$out_dir, "crossing_event_audit.csv"), stringsAsFactors = FALSE)
pair_detail <- utils::read.csv(file.path(phase4c_result$out_dir, "crossing_pair_detail.csv"), stringsAsFactors = FALSE)
vb_context <- utils::read.csv(file.path(phase4c_result$out_dir, "crossing_vb_context.csv"), stringsAsFactors = FALSE)
recommendation <- utils::read.csv(file.path(phase4c_result$out_dir, "crossing_remediation_recommendation.csv"), stringsAsFactors = FALSE)
targeted_registry <- utils::read.csv(file.path(phase4c_result$out_dir, "targeted_crossing_registry.csv"), stringsAsFactors = FALSE)

stopifnot(nrow(event_audit) == 1L)
stopifnot(event_audit$n_raw_crossing_pairs[[1L]] == 1L)
stopifnot(event_audit$n_contract_crossing_pairs[[1L]] == 0L)
stopifnot(nrow(pair_detail) == 1L)
stopifnot(pair_detail$lower_tau[[1L]] == 0.10)
stopifnot(pair_detail$upper_tau[[1L]] == 0.50)
stopifnot(pair_detail$crossing_magnitude[[1L]] > 0)
stopifnot(isTRUE(app_as_bool_vec(vb_context$vb_hit_max_iter)[[1L]]))
stopifnot(recommendation$gate_status[[1L]] == "review")
stopifnot(recommendation$recommendation_status[[1L]] == "contract_unblocked_raw_review")
stopifnot(nrow(targeted_registry) == 1L)
stopifnot(targeted_registry$scenario_id[[1L]] == "toy_crossing__calibration_r02")
stopifnot(targeted_registry$seed[[1L]] == 202607999L)
