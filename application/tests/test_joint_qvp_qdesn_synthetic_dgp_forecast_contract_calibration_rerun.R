phase4d_out <- tempfile("joint_qvp_phase4d_contract_rerun_")
phase4d <- app_joint_qvp_prepare_synthetic_dgp_forecast_contract_calibration_rerun(
  out_dir = phase4d_out,
  scenario_ids = "normal_bridge",
  tier = "calibration",
  n_replicates = 2L,
  seed_base = 202699000L,
  simulated_length = 72L,
  washout_length = 12L,
  train_length = 42L,
  test_length = 18L,
  vb_max_iter = 12L,
  adaptive_vb_max_iter_grid = c(12L, 24L),
  refit_stride = 5L,
  forecast_origin_stride = 2L,
  max_origins_per_scenario = 3L
)

stopifnot(dir.exists(phase4d$prep_dir))
stopifnot(nrow(phase4d$calibration_registry) == 2L)
stopifnot(!anyDuplicated(phase4d$calibration_registry$scenario_id))
stopifnot(identical(as.integer(phase4d$calibration_registry$replicate_id), c(1L, 2L)))
stopifnot(identical(as.integer(phase4d$calibration_registry$seed), c(202700001L, 202700002L)))
stopifnot(all(phase4d$preflight$status == "pass"))
stopifnot(phase4d$plan$preflight_gate[[1L]] == "pass")
stopifnot(phase4d$plan$n_registry_rows[[1L]] == 2L)
stopifnot(phase4d$plan$expected_forecast_origin_rows[[1L]] == 6L)
stopifnot(phase4d$plan$expected_forecast_quantile_rows[[1L]] == 42L)

stopifnot(identical(
  phase4d$commands$step_id,
  c("phase4_contract_calibration", "phase4b_readiness_audit", "phase4c_crossing_audit")
))
stopifnot(grepl("78_run_joint_qvp_synthetic_dgp_forecast_calibration.R", phase4d$commands$command[[1L]], fixed = TRUE))
stopifnot(grepl("--vb-max-iter 12", phase4d$commands$command[[1L]], fixed = TRUE))
stopifnot(grepl("--adaptive-vb-max-iter-grid 12,24", phase4d$commands$command[[1L]], fixed = TRUE))
stopifnot(grepl("79_audit_joint_qvp_synthetic_dgp_forecast_calibration.R", phase4d$commands$command[[2L]], fixed = TRUE))
stopifnot(grepl("80_audit_joint_qvp_synthetic_dgp_forecast_crossings.R", phase4d$commands$command[[3L]], fixed = TRUE))

stopifnot(any(phase4d$expected_artifacts$relative_path == file.path("phase3_forecast_validation", "forecast_quantiles_raw.csv")))
stopifnot(any(phase4d$expected_artifacts$relative_path == file.path("phase3_forecast_validation", "forecast_monotone_adjustment.csv")))
stopifnot(any(phase4d$expected_artifacts$relative_path == file.path("phase3_forecast_validation", "raw_crossing_summary.csv")))
stopifnot(any(phase4d$expected_artifacts$relative_path == file.path("phase4b_readiness_audit", "calibration_readiness_summary.csv")))
stopifnot(any(phase4d$expected_artifacts$relative_path == file.path("phase4c_crossing_audit", "crossing_remediation_recommendation.csv")))

expected_phase4d_labels <- c(
  "contract_rerun_plan",
  "contract_rerun_commands",
  "contract_rerun_preflight",
  "expected_artifacts",
  "calibration_registry_preview",
  "provenance",
  "readme"
)
phase4d_manifest <- utils::read.csv(file.path(phase4d$prep_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(phase4d_manifest$label, expected_phase4d_labels))
stopifnot(all(nchar(phase4d_manifest$sha256) == 64L))
for (ii in seq_len(nrow(phase4d_manifest))) {
  artifact_path <- file.path(phase4d$prep_dir, phase4d_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), phase4d_manifest$sha256[[ii]]))
}

phase4d_plan <- utils::read.csv(file.path(phase4d$prep_dir, "contract_rerun_plan.csv"), stringsAsFactors = FALSE)
phase4d_preflight <- utils::read.csv(file.path(phase4d$prep_dir, "contract_rerun_preflight.csv"), stringsAsFactors = FALSE)
phase4d_registry <- utils::read.csv(file.path(phase4d$prep_dir, "calibration_registry_preview.csv"), stringsAsFactors = FALSE)

stopifnot(phase4d_plan$preflight_gate[[1L]] == "pass")
stopifnot(all(phase4d_preflight$status == "pass"))
stopifnot(identical(phase4d_registry$scenario_id, phase4d$calibration_registry$scenario_id))
