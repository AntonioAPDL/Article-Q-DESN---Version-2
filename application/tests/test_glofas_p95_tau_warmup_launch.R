warmup_candidates_path <- app_path(
  "application/config/glofas_fit_recovery_p95_tau_warmup_candidates_20260809.csv"
)
warmup_candidates <- app_read_csv(warmup_candidates_path)
stopifnot(identical(
  warmup_candidates$candidate_id,
  c("fr09_p95_tauwarm25", "fr09_p95_tauwarm50")
))
stopifnot(identical(as.integer(warmup_candidates$freeze_tau_warmup_iters), c(25L, 50L)))
stopifnot(identical(as.integer(warmup_candidates$priority), c(1L, 2L)))

warmup_prepare_path <- app_path("application/scripts/glofas_fit_recovery_p95_tau_warmup_prepare.R")
warmup_finalize_path <- app_path("application/scripts/glofas_fit_recovery_p95_tau_warmup_finalize.R")
warmup_watch_path <- app_path("application/scripts/glofas_fit_recovery_watch.sh")
invisible(parse(warmup_prepare_path))
invisible(parse(warmup_finalize_path))
warmup_prepare_text <- paste(readLines(warmup_prepare_path, warn = FALSE), collapse = "\n")
warmup_finalize_text <- paste(readLines(warmup_finalize_path, warn = FALSE), collapse = "\n")
warmup_watch_text <- paste(readLines(warmup_watch_path, warn = FALSE), collapse = "\n")
stopifnot(grepl("expected_control_fit_sha256", warmup_prepare_text, fixed = TRUE))
stopifnot(grepl("source_snapshot_manifest.csv", warmup_prepare_text, fixed = TRUE))
stopifnot(grepl("rhs_freeze_tau_warmup_iters", warmup_prepare_text, fixed = TRUE))
stopifnot(grepl("warm_start <- list(enabled = FALSE)", warmup_prepare_text, fixed = TRUE))
stopifnot(grepl("p95_rhs_warmup_schedule_audit.csv", warmup_finalize_text, fixed = TRUE))
stopifnot(grepl("forecast_window_used", warmup_finalize_text, fixed = TRUE))
stopifnot(grepl("auto_launch_full7 <- FALSE", warmup_finalize_text, fixed = TRUE))
stopifnot(grepl("auto_promote <- FALSE", warmup_finalize_text, fixed = TRUE))
stopifnot(grepl(
  "application/scripts/glofas_fit_recovery_p95_tau_warmup_finalize.R",
  warmup_watch_text,
  fixed = TRUE
))

cat("GloFAS p95 RHS warmup launch-contract tests passed.\n")
