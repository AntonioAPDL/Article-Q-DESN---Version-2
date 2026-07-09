ts_toy <- app_joint_qvp_simulate_ts_toy_synthetic(
  Tn = 48L,
  tau = c(0.1, 0.5, 0.9),
  seed = 20260731L,
  df = 5,
  period = 12L
)
ts_toy_repeat <- app_joint_qvp_simulate_ts_toy_synthetic(
  Tn = 48L,
  tau = c(0.1, 0.5, 0.9),
  seed = 20260731L,
  df = 5,
  period = 12L
)

stopifnot(length(ts_toy$y) == 48L)
stopifnot(identical(dim(ts_toy$Z), c(48L, 5L)))
stopifnot(identical(dim(ts_toy$true_q), c(48L, 3L)))
stopifnot(identical(colnames(ts_toy$Z), c("lag_y", "trend", "sin_season", "cos_season", "abs_lag_scaled")))
stopifnot(all(is.finite(ts_toy$y)))
stopifnot(all(is.finite(ts_toy$Z)))
stopifnot(all(is.finite(ts_toy$true_q)))
stopifnot(all(ts_toy$sigma > 0))
stopifnot(identical(round(ts_toy$y, 12), round(ts_toy_repeat$y, 12)))
stopifnot(identical(round(ts_toy$true_q, 12), round(ts_toy_repeat$true_q, 12)))

linear_q <- ts_toy$Z %*% ts_toy$beta +
  matrix(ts_toy$alpha, nrow = nrow(ts_toy$Z), ncol = length(ts_toy$tau), byrow = TRUE)
stopifnot(max(abs(ts_toy$true_q - linear_q)) < 1.0e-12)
stopifnot(sum(ts_toy$crossing_diagnostics$n_crossing_pairs) == 0L)
stopifnot(identical(ts_toy$dynamic, "ar1_seasonal_location_scale"))
stopifnot(identical(ts_toy$likelihood, "standardized_student_t"))

bad_ts_toy <- try(app_joint_qvp_simulate_ts_toy_synthetic(
  Tn = 8L,
  seed = 1L
), silent = TRUE)
stopifnot(inherits(bad_ts_toy, "try-error"))

bad_df_ts_toy <- try(app_joint_qvp_simulate_ts_toy_synthetic(
  Tn = 20L,
  df = 2,
  seed = 1L
), silent = TRUE)
stopifnot(inherits(bad_df_ts_toy, "try-error"))

ts_toy_dir <- tempfile("joint_qvp_ts_toy_")
ts_toy_result <- app_joint_qvp_run_ts_toy_synthetic(
  out_dir = ts_toy_dir,
  Tn = 32L,
  tau = c(0.1, 0.5, 0.9),
  seed = 20260731L,
  df = 5,
  period = 12L
)
ts_toy_manifest <- utils::read.csv(
  file.path(ts_toy_result$out_dir, "artifact_manifest.csv"),
  stringsAsFactors = FALSE
)
expected_ts_toy_labels <- c(
  "run_config",
  "observed_series",
  "design_matrix",
  "true_quantiles",
  "true_quantile_long",
  "true_readout_parameters",
  "dgp_parameters",
  "crossing_summary",
  "provenance"
)
stopifnot(identical(ts_toy_manifest$label, expected_ts_toy_labels))
stopifnot(all(nchar(ts_toy_manifest$sha256) == 64L))
for (ii in seq_len(nrow(ts_toy_manifest))) {
  artifact_path <- file.path(ts_toy_result$out_dir, ts_toy_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), ts_toy_manifest$sha256[[ii]]))
}

run_config <- utils::read.csv(file.path(ts_toy_result$out_dir, "run_config.csv"), stringsAsFactors = FALSE)
stopifnot(identical(run_config$true_quantile_contract[[1L]], "true_q = Z %*% beta(tau) + alpha(tau)"))
observed <- utils::read.csv(file.path(ts_toy_result$out_dir, "observed_series.csv"), stringsAsFactors = FALSE)
design <- utils::read.csv(file.path(ts_toy_result$out_dir, "design_matrix.csv"), stringsAsFactors = FALSE)
true_quantiles <- utils::read.csv(file.path(ts_toy_result$out_dir, "true_quantiles.csv"), stringsAsFactors = FALSE)
true_long <- utils::read.csv(file.path(ts_toy_result$out_dir, "true_quantile_long.csv"), stringsAsFactors = FALSE)
readout <- utils::read.csv(file.path(ts_toy_result$out_dir, "true_readout_parameters.csv"), stringsAsFactors = FALSE)
crossing <- utils::read.csv(file.path(ts_toy_result$out_dir, "crossing_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(observed) == 32L)
stopifnot(nrow(design) == 32L)
stopifnot(nrow(true_quantiles) == 32L)
stopifnot(nrow(true_long) == 32L * 3L)
stopifnot(nrow(readout) == 3L * (1L + 5L))
stopifnot(all(observed$sigma > 0))
stopifnot(all(c("q_tau_0p1", "q_tau_0p5", "q_tau_0p9") %in% names(true_quantiles)))
stopifnot(sum(crossing$n_crossing_pairs) == 0L)
