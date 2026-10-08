closeout_tmp <- tempfile("glofas_search3_final_closeout_")
dir.create(closeout_tmp, recursive = TRUE)

status_dir <- file.path(closeout_tmp, "status")
dir.create(status_dir)
file.create(file.path(status_dir, c("a.completed", "b.completed", "c.failed")))
marker_counts <- app_glofas_closeout_marker_counts(status_dir)
stopifnot(
  marker_counts$completed == 2L,
  marker_counts$failed == 1L,
  marker_counts$running == 0L,
  marker_counts$pending == 0L
)

tau <- c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95)
dates <- as.Date("2022-12-26") + 0:3
quantile_rows <- expand.grid(
  target_date = dates,
  quantile_level = tau,
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)
quantile_rows <- quantile_rows[order(-quantile_rows$quantile_level, quantile_rows$target_date), ]
quantile_rows$horizon <- as.integer(quantile_rows$target_date - min(dates)) + 1L
quantile_rows$y_reference <- rep(c(0.5, 1.0, 1.5, 2.0), times = length(tau))
quantile_rows$qhat <- quantile_rows$y_reference + stats::qnorm(quantile_rows$quantile_level) * 0.2

summary_row <- app_glofas_closeout_summarize_quantiles(
  quantile_rows, "fixture", "unit_test", "completed"
)
stopifnot(
  nrow(summary_row) == 1L,
  summary_row$n_scored_horizons == 4L,
  summary_row$crossing_pairs == 0L,
  is.finite(summary_row$crps_grid_log1p)
)
calibration <- app_glofas_closeout_calibration(quantile_rows, "fixture")
stopifnot(nrow(calibration) == 7L, setequal(calibration$quantile_level, tau))

duplicate_rows <- rbind(quantile_rows, quantile_rows[1L, ])
stopifnot(inherits(try(
  app_glofas_closeout_summarize_quantiles(duplicate_rows, "fixture", "unit_test", "completed"),
  silent = TRUE
), "try-error"))

trace <- data.frame(
  outer_iteration = 13:15,
  parameter_change = c(9e-4, 8e-4, 7e-4),
  all_inner_converged = TRUE,
  rhs_convergence_gate_passed = TRUE,
  full_state_pass = TRUE,
  terminal_consecutive_passes = 1:3,
  max_rhs_global_relative_change = c(8e-4, 7e-4, 6e-4)
)
fit <- list(
  converged = TRUE,
  converged_outer = TRUE,
  converged_inner = TRUE,
  converged_rhs = TRUE,
  stopping_reason = "full_state_converged",
  trace = trace
)
fit_gate <- app_glofas_closeout_validate_joint_fit(fit)
stopifnot(
  fit_gate$converged,
  fit_gate$outer_iteration == 15L,
  fit_gate$terminal_consecutive_passes == 3L
)
fit$trace$terminal_consecutive_passes[3L] <- 2L
stopifnot(inherits(try(app_glofas_closeout_validate_joint_fit(fit), silent = TRUE), "try-error"))

artifact_dir <- file.path(closeout_tmp, "artifacts")
dir.create(artifact_dir)
writeLines("alpha", file.path(artifact_dir, "a.txt"))
writeLines("beta", file.path(artifact_dir, "b.txt"))
manifest_path <- file.path(closeout_tmp, "manifest.csv")
manifest <- app_glofas_closeout_write_manifest(
  closeout_tmp, c("artifacts/a.txt", "artifacts/b.txt"), manifest_path
)
stopifnot(nrow(manifest) == 2L)
verified <- app_glofas_closeout_verify_manifest(closeout_tmp, manifest_path)
stopifnot(identical(manifest$sha256, verified$sha256))

unsafe_manifest <- manifest
unsafe_manifest$relative_path[[1L]] <- "../outside.txt"
unsafe_path <- file.path(closeout_tmp, "unsafe.csv")
write.csv(unsafe_manifest, unsafe_path, row.names = FALSE)
stopifnot(inherits(try(
  app_glofas_closeout_verify_manifest(closeout_tmp, unsafe_path),
  silent = TRUE
), "try-error"))

unlink(closeout_tmp, recursive = TRUE)
cat("GloFAS Search III final closeout tests passed.\n")
