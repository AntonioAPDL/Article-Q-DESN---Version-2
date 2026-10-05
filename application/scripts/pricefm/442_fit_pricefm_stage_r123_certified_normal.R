#!/usr/bin/env Rscript
# Certified Normal parent packet, with terminal evidence for unsuccessful fits.
args <- commandArgs(trailingOnly = TRUE)
at <- match("--contract", args)
stopifnot(!is.na(at), at < length(args))
contract_path <- normalizePath(args[[at + 1L]], mustWork = TRUE)
c <- jsonlite::read_json(contract_path, simplifyVector = TRUE)
hash <- function(path) digest::digest(path, file = TRUE, algo = "sha256")
stopifnot(identical(c$selection_split, "train_validation_only"),
  identical(c$test_access_authorized, FALSE), identical(c$prior_type, "rhs_ns"),
  identical(c$convergence_mode, "full_variational"), !dir.exists(c$output_dir),
  c$max_iter == 2000, c$min_iter <= c$max_iter)
for (path in names(c$source_sha256)) stopifnot(identical(hash(path), c$source_sha256[[path]]))
stopifnot(identical(hash(file.path(c$stats_dir, "terminal.json")), c$stats_terminal_sha256))
meta <- jsonlite::read_json(file.path(c$stats_dir, "statistics.json"), simplifyVector = TRUE)
stats_terminal <- jsonlite::read_json(file.path(c$stats_dir, "terminal.json"), simplifyVector = FALSE)
stopifnot(identical(meta$test_opened, FALSE), identical(stats_terminal$test_opened, FALSE),
  identical(stats_terminal$status, "completed_causal_sufficient_statistics"))
for (name in names(stats_terminal$files)) stopifnot(identical(
  hash(file.path(c$stats_dir, name)), stats_terminal$files[[name]]$sha256))
read_f64 <- function(name, n) {
  con <- file(file.path(c$stats_dir, name), "rb"); on.exit(close(con))
  x <- readBin(con, double(), n, size = 8L, endian = "little")
  stopifnot(length(x) == n, all(is.finite(x))); x
}
stats <- list(n = as.integer(meta$n), p = as.integer(meta$p),
  XtX = matrix(read_f64("XtX.bin", meta$p^2), meta$p, byrow = TRUE),
  Xty = read_f64("Xty.bin", meta$p), yty = as.numeric(meta$yty))
source(c$helper_path)
pkgload::load_all(c$package_path, quiet = TRUE, export_all = TRUE)
factory <- get("beta_prior", envir = asNamespace("exdqlm"))
checkpoint <- if (is.null(c$initial_fit_path)) NULL else {
  stopifnot(identical(hash(c$initial_fit_path), c$initial_fit_sha256))
  fit <- readRDS(c$initial_fit_path)
  stopifnot(nrow(fit$trace) + c$stability_window <= c$max_iter,
    c$min_iter >= nrow(fit$trace) + c$stability_window)
  fit
}
failure <- NULL
started <- proc.time()[["elapsed"]]
fit <- tryCatch(app_pricefm_fit_rhs_stats(stats, c$tau0, factory,
  max_iter = c$max_iter, min_iter = c$min_iter, convergence_mode = "full_variational",
  record_objective = TRUE, initial_fit = checkpoint, initial_tau = 1,
  tol = c$tol, stability_window = c$stability_window, predictive_tol = c$predictive_tol,
  relative_beta_tol = c$relative_beta_tol, sigma_relative_tol = c$sigma_relative_tol,
  prior_rms_log_precision_tol = c$prior_rms_log_precision_tol,
  rhs_state_tol = c$rhs_state_tol, covariance_tol = c$covariance_tol,
  objective_per_observation_tol = c$objective_per_observation_tol,
  precision_accuracy_tol = c$precision_accuracy_tol), error = function(e) {
    message <- conditionMessage(e)
    if (!grepl("positive definite|non-finite full RHS|precision must be finite|invalid active RHS", message)) stop(e)
    failure <<- message; NULL
  })
elapsed <- proc.time()[["elapsed"]] - started
dir.create(dirname(c$output_dir), recursive = TRUE, showWarnings = FALSE)
tmp <- tempfile(pattern = paste0(basename(c$output_dir), ".tmp."), tmpdir = dirname(c$output_dir))
dir.create(tmp)
on.exit(if (dir.exists(tmp)) unlink(tmp, recursive = TRUE), add = TRUE)
write_json <- function(x, name) jsonlite::write_json(x, file.path(tmp, name),
  auto_unbox = TRUE, pretty = TRUE, null = "null", digits = 17)
write_f64 <- function(name, value, row_major = FALSE) {
  con <- file(file.path(tmp, name), "wb"); on.exit(close(con))
  writeBin(if (row_major) as.double(t(value)) else as.double(value), con, size = 8L, endian = "little")
}
certified <- !is.null(fit) && isTRUE(fit$converged) && isTRUE(fit$precision_accuracy$accepted)
summary <- list(stage = "R123_certified_successor", tag = c$tag,
  fit_id = c$fit_id, candidate_id = c$candidate_id, split = c$split,
  prior_type = "rhs_ns", tau0 = c$tau0, n = stats$n, p = stats$p,
  converged = certified, full_variational_certified = certified,
  iterations = if (is.null(fit)) NULL else nrow(fit$trace),
  omega_shape = if (is.null(fit)) NULL else fit$omega2$a,
  omega_rate = if (is.null(fit)) NULL else fit$omega2$b,
  resumed_from_iteration = if (is.null(checkpoint)) 0L else nrow(checkpoint$trace),
  termination_reason = if (is.null(fit)) "numerical_failure" else fit$termination_reason,
  precision_accuracy = if (is.null(fit)) NULL else fit$precision_accuracy,
  posterior_target_sha256 = c$posterior_target_sha256,
  contract_path = contract_path, contract_sha256 = hash(contract_path),
  initial_fit_sha256 = c$initial_fit_sha256, train_seconds = elapsed,
  initialization_only = TRUE, prior_center_from_initializer = FALSE,
  test_opened = FALSE, official_validation_opened = FALSE,
  registry_mutated = FALSE, article_mutated = FALSE)
if (!is.null(fit)) {
  saveRDS(fit, file.path(tmp, "fit.rds"), compress = "xz")
  write_f64("beta_mean.bin", fit$beta$mean)
  write_f64("beta_cov.bin", fit$beta$cov, TRUE)
  utils::write.csv(fit$trace, file.path(tmp, "convergence_trace.csv"), row.names = FALSE)
} else write_json(list(error = failure, checkpoint_preserved = !is.null(checkpoint)), "numerical_failure.json")
write_json(summary, "fit_summary.json")
names <- list.files(tmp)
summary$status <- if (certified) "completed_recursive_normal_fit" else
  if (is.null(fit)) "R123_SUCCESSOR_NUMERICAL_FAILURE" else "R123_SUCCESSOR_UNCERTIFIED"
summary$artifacts <- lapply(names, function(name) list(path = name,
  bytes = file.info(file.path(tmp, name))$size, sha256 = hash(file.path(tmp, name))))
write_json(summary, "terminal.json")
stopifnot(!dir.exists(c$output_dir), file.rename(tmp, c$output_dir))
cat(jsonlite::toJSON(summary, auto_unbox = TRUE, null = "null", digits = 17), "\n")
