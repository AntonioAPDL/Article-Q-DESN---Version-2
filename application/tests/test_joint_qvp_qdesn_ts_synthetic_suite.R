ts_suite_dir <- tempfile("joint_qvp_ts_suite_")
ts_suite_scenarios <- app_joint_qvp_default_ts_synthetic_scenarios()[1:3, ]
ts_suite_scenarios$Tn <- 24L
ts_suite_result <- app_joint_qvp_run_ts_synthetic_suite(
  out_dir = ts_suite_dir,
  scenarios = ts_suite_scenarios
)

ts_suite_manifest <- utils::read.csv(
  file.path(ts_suite_result$out_dir, "artifact_manifest.csv"),
  stringsAsFactors = FALSE
)
expected_ts_suite_labels <- c(
  "run_config",
  "scenario_summary",
  "observed_series",
  "design_matrix",
  "true_quantile_long",
  "true_readout_parameters",
  "dgp_parameters",
  "crossing_summary",
  "provenance"
)
stopifnot(identical(ts_suite_manifest$label, expected_ts_suite_labels))
stopifnot(all(nchar(ts_suite_manifest$sha256) == 64L))
for (ii in seq_len(nrow(ts_suite_manifest))) {
  artifact_path <- file.path(ts_suite_result$out_dir, ts_suite_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), ts_suite_manifest$sha256[[ii]]))
}

scenario_summary <- utils::read.csv(file.path(ts_suite_result$out_dir, "scenario_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(scenario_summary) == 3L)
stopifnot(identical(scenario_summary$case_id, ts_suite_scenarios$case_id))
stopifnot(all(scenario_summary$Tn == 24L))
stopifnot(all(scenario_summary$p == 5L))
stopifnot(all(scenario_summary$K == 3L))
stopifnot(all(scenario_summary$sigma_min > 0))
stopifnot(all(scenario_summary$total_crossing_pairs == 0L))
stopifnot(all(is.finite(scenario_summary$max_quantile_width)))

observed <- utils::read.csv(file.path(ts_suite_result$out_dir, "observed_series.csv"), stringsAsFactors = FALSE)
design <- utils::read.csv(file.path(ts_suite_result$out_dir, "design_matrix.csv"), stringsAsFactors = FALSE)
true_long <- utils::read.csv(file.path(ts_suite_result$out_dir, "true_quantile_long.csv"), stringsAsFactors = FALSE)
readout <- utils::read.csv(file.path(ts_suite_result$out_dir, "true_readout_parameters.csv"), stringsAsFactors = FALSE)
crossing <- utils::read.csv(file.path(ts_suite_result$out_dir, "crossing_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(observed) == 3L * 24L)
stopifnot(nrow(design) == 3L * 24L)
stopifnot(nrow(true_long) == 3L * 24L * 3L)
stopifnot(nrow(readout) == 3L * 3L * (1L + 5L))
stopifnot(all(observed$sigma > 0))
stopifnot(all(is.finite(design$lag_y)))
stopifnot(all(is.finite(true_long$true_quantile)))
stopifnot(sum(crossing$n_crossing_pairs) == 0L)
