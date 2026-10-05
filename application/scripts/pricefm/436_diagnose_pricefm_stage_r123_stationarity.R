#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
contract_path <- args[[match("--contract", args) + 1L]]
c <- jsonlite::read_json(contract_path, simplifyVector = TRUE)
stopifnot(identical(c$selection_split, "train_validation_only"),
  identical(c$test_access_authorized, FALSE), identical(c$prior_type, "rhs_ns"),
  !dir.exists(c$output_dir), identical(c$convergence_mode, "full_variational"))
hash <- function(path) digest::digest(path, file = TRUE, algo = "sha256")
for (source_path in names(c$source_sha256)) stopifnot(identical(hash(source_path), c$source_sha256[[source_path]]))
meta <- jsonlite::read_json(file.path(c$stats_dir, "statistics.json"), simplifyVector = TRUE)
terminal <- jsonlite::read_json(file.path(c$stats_dir, "terminal.json"), simplifyVector = FALSE)
stopifnot(identical(meta$test_opened, FALSE), identical(terminal$test_opened, FALSE),
  identical(terminal$status, "completed_causal_sufficient_statistics"))
for (name in names(terminal$files)) stopifnot(identical(hash(file.path(c$stats_dir, name)), terminal$files[[name]]$sha256))
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
prior_factory <- get("beta_prior", envir = asNamespace("exdqlm"))
checkpoint <- if (is.null(c$initial_fit_path)) NULL else {
  stopifnot(identical(hash(c$initial_fit_path), c$initial_fit_sha256)); readRDS(c$initial_fit_path)
}
fit <- app_pricefm_fit_rhs_stats(stats, c$tau0, prior_factory, max_iter = c$max_iter,
  min_iter = c$min_iter, convergence_mode = "full_variational", record_objective = TRUE,
  initial_fit = checkpoint, initial_tau = c$initial_tau, tol = c$tol,
  stability_window = c$stability_window, predictive_tol = c$predictive_tol,
  relative_beta_tol = c$relative_beta_tol, sigma_relative_tol = c$sigma_relative_tol,
  prior_rms_log_precision_tol = c$prior_rms_log_precision_tol,
  rhs_state_tol = c$rhs_state_tol, covariance_tol = c$covariance_tol,
  objective_per_observation_tol = c$objective_per_observation_tol)
diagonal <- sqrt(pmax(diag(stats$XtX), .Machine$double.eps))
correlation <- stats$XtX / outer(diagonal, diagonal)
eigenvalues <- eigen(correlation, symmetric = TRUE, only.values = TRUE)$values
geometry <- list(normalized_gram_min_eigenvalue = min(eigenvalues),
  normalized_gram_max_eigenvalue = max(eigenvalues),
  normalized_gram_numerical_rank = sum(eigenvalues > max(eigenvalues) * 1e-10),
  p = stats$p, n = stats$n)
dir.create(c$output_dir, recursive = TRUE)
saveRDS(fit, file.path(c$output_dir, "fit.rds"), compress = "xz")
utils::write.csv(fit$trace, file.path(c$output_dir, "convergence_trace.csv"), row.names = FALSE)
jsonlite::write_json(geometry, file.path(c$output_dir, "geometry.json"), auto_unbox = TRUE, pretty = TRUE)
summary <- list(status = if (fit$converged) "R123_FULL_VARIATIONAL_CERTIFIED" else "R123_VARIATIONAL_CAP_DIAGNOSTIC",
  fit_id = c$fit_id, candidate_id = c$candidate_id, split = c$split,
  converged = fit$converged, iterations = nrow(fit$trace),
  resumed_from_iteration = fit$controls$resumed_from_iteration, tau0 = c$tau0,
  last_trace = as.list(tail(fit$trace, 1)), target_contract_sha256 = c$target_contract_sha256,
  contract_sha256 = hash(contract_path), test_opened = FALSE, official_validation_opened = FALSE,
  selection_authorized = FALSE, registry_mutated = FALSE, article_mutated = FALSE)
jsonlite::write_json(summary, file.path(c$output_dir, "summary.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
summary$artifact_sha256 <- setNames(lapply(c("fit.rds", "convergence_trace.csv", "geometry.json", "summary.json"),
  function(name) hash(file.path(c$output_dir, name))), c("fit.rds", "convergence_trace.csv", "geometry.json", "summary.json"))
jsonlite::write_json(summary, file.path(c$output_dir, "terminal.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
cat(jsonlite::toJSON(summary, auto_unbox = TRUE), "\n")
