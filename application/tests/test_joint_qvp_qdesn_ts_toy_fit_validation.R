ts_toy_fit_dir <- tempfile("joint_qvp_ts_toy_fit_")
ts_toy_fit_result <- app_joint_qvp_run_ts_toy_fit_validation(
  out_dir = ts_toy_fit_dir,
  Tn = 32L,
  seed = 20260701L,
  vb_max_iter = 50L,
  n_chains = 2L,
  mcmc_n_iter = 30L,
  mcmc_burn = 15L,
  mcmc_thin = 5L
)

ts_toy_fit_manifest <- utils::read.csv(
  file.path(ts_toy_fit_result$out_dir, "artifact_manifest.csv"),
  stringsAsFactors = FALSE
)
expected_ts_toy_fit_labels <- c(
  "run_config",
  "observed_series",
  "design_matrix",
  "true_quantiles",
  "fit_summary",
  "truth_fit_summary",
  "readout_truth_summary",
  "vb_mcmc_distance_summary",
  "mcmc_draw_summary",
  "crossing_summary",
  "objective_diagnostics",
  "elbo_terms",
  "figure_manifest",
  "provenance",
  "fit_overlay",
  "error_hit",
  "elbo_trace",
  "parameter_traces"
)
stopifnot(identical(ts_toy_fit_manifest$label, expected_ts_toy_fit_labels))
stopifnot(all(nchar(ts_toy_fit_manifest$sha256) == 64L))
for (ii in seq_len(nrow(ts_toy_fit_manifest))) {
  artifact_path <- file.path(ts_toy_fit_result$out_dir, ts_toy_fit_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), ts_toy_fit_manifest$sha256[[ii]]))
}

fit_summary <- utils::read.csv(file.path(ts_toy_fit_result$out_dir, "fit_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(fit_summary) == 1L)
stopifnot(fit_summary$Tn[[1L]] == 32L)
stopifnot(fit_summary$K[[1L]] == 3L)
stopifnot(fit_summary$p[[1L]] == 5L)
stopifnot(fit_summary$objective_status[[1L]] == "pass")
stopifnot(is.finite(fit_summary$vb_truth_normalized_qhat_distance[[1L]]))
stopifnot(is.finite(fit_summary$pooled_mcmc_truth_normalized_qhat_distance[[1L]]))
stopifnot(is.finite(fit_summary$vb_mcmc_max_normalized_distance[[1L]]))
stopifnot(fit_summary$total_vb_crossing_pairs[[1L]] == 0L)
stopifnot(fit_summary$total_pooled_mcmc_crossing_pairs[[1L]] == 0L)
stopifnot(isTRUE(fit_summary$all_chain_draws_finite[[1L]]))

truth_fit <- utils::read.csv(file.path(ts_toy_fit_result$out_dir, "truth_fit_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(truth_fit) == 9L)
stopifnot(identical(sort(unique(truth_fit$fit)), c("pooled_mcmc", "truth", "vb")))
truth_rows <- truth_fit[truth_fit$fit == "truth", , drop = FALSE]
stopifnot(max(abs(truth_rows$rmse_to_truth)) < 1.0e-12)
stopifnot(all(is.finite(truth_fit$empirical_hit_rate)))
stopifnot(all(truth_fit$empirical_hit_rate >= 0 & truth_fit$empirical_hit_rate <= 1))

readout <- utils::read.csv(file.path(ts_toy_fit_result$out_dir, "readout_truth_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(readout) == 2L * 3L * (1L + 5L))
stopifnot(all(is.finite(readout$error)))

distance <- utils::read.csv(file.path(ts_toy_fit_result$out_dir, "vb_mcmc_distance_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(distance) == 1L)
stopifnot(is.finite(distance$max_normalized_distance[[1L]]))

figures <- utils::read.csv(file.path(ts_toy_fit_result$out_dir, "figure_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(figures) == 4L)
stopifnot(all(figures$size_bytes > 0))
stopifnot(all(nchar(figures$sha256) == 64L))
