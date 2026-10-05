#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(args[[1L]], mustWork = TRUE)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]])
repo <- normalizePath(file.path(dirname(script), "..", "..", ".."))
source(file.path(repo, "application/R/pricefm_recursive_normal_fit.R"))
terminal <- jsonlite::read_json(file.path(root, "terminal.json"), simplifyVector = TRUE)
stopifnot(identical(terminal$status, "R123_STATIONARITY_DIAGNOSIS_COMPLETE"))
manifest <- jsonlite::read_json(file.path(root, "manifest.json"), simplifyVector = FALSE)
stopifnot(length(manifest) == 10L)
output <- file.path(root, "closeout")
stopifnot(!dir.exists(output))
records <- lapply(manifest, function(c) {
  fit <- readRDS(file.path(c$output_dir, "fit.rds"))
  endpoint <- jsonlite::read_json(file.path(c$output_dir, "terminal.json"), simplifyVector = FALSE)
  for (name in names(endpoint$artifact_sha256)) stopifnot(identical(
    digest::digest(file.path(c$output_dir, name), file = TRUE, algo = "sha256"), endpoint$artifact_sha256[[name]]))
  pkgload::load_all(c$package_path, quiet = TRUE, export_all = TRUE)
  factory <- get("beta_prior", envir = asNamespace("exdqlm"))
  prior <- factory("rhs_ns", rhs = list(tau0 = c$tau0, init_tau = 1, shrink_intercept = FALSE, intercept_prec = 1e-16))
  stopifnot(identical(prior$hypers, fit$beta_prior$hypers))
  objective <- app_pricefm_rhs_objective(fit$stats, fit$beta$mean, fit$beta$cov,
    fit$omega2$a, fit$omega2$b, fit$beta_prior$state, prior)
  stopifnot(abs(objective - tail(fit$trace$total_objective, 1L)) < 1e-7)
  P <- (fit$omega2$a / fit$omega2$b) * fit$stats$XtX +
    diag(prior$expected_prec(fit$beta_prior$state, fit$stats$p), fit$stats$p)
  reciprocal_condition <- rcond(P)
  covariance_inverse_residual <- max(abs(P %*% fit$beta$cov - diag(fit$stats$p)))
  record <- data.frame(fit_id = c$fit_id, candidate_id = c$candidate_id, split = c$split,
    initialization = if (is.null(c$initial_fit_path)) if (c$initial_tau == 1) "legacy_one" else "prior_scale" else "resume",
    certified = fit$converged, offset = fit$controls$resumed_from_iteration, iterations = nrow(fit$trace),
    objective = objective, maximum_precision_jitter = max(fit$trace$precision_jitter, na.rm = TRUE),
    reciprocal_precision_condition = reciprocal_condition,
    covariance_inverse_max_residual = covariance_inverse_residual,
    final_rhs_rate_delta = tail(fit$trace$rhs_max_log_rate_delta, 1),
    final_prior_precision_delta = tail(fit$trace$prior_rms_log_precision_delta, 1),
    final_objective_delta_per_observation = tail(fit$trace$objective_delta_per_observation, 1),
    minimum_objective_increment_per_observation = min(fit$trace$objective_delta_per_observation, na.rm = TRUE),
    checkpoint_objective_gain = NA_real_, fitted_rmse_change_from_checkpoint = NA_real_,
    beta_covariance_relative_change_from_checkpoint = NA_real_, noise_relative_change_from_checkpoint = NA_real_)
  if (!is.null(c$initial_fit_path)) {
    stopifnot(identical(digest::digest(c$initial_fit_path, file = TRUE, algo = "sha256"), c$initial_fit_sha256))
    old <- readRDS(c$initial_fit_path)
    before <- app_pricefm_rhs_objective(old$stats, old$beta$mean, old$beta$cov,
      old$omega2$a, old$omega2$b, old$beta_prior$state, prior)
    delta <- fit$beta$mean - old$beta$mean
    record$checkpoint_objective_gain <- objective - before
    record$fitted_rmse_change_from_checkpoint <- sqrt(max(0, as.numeric(crossprod(delta, fit$stats$XtX %*% delta)) / fit$stats$n))
    record$beta_covariance_relative_change_from_checkpoint <-
      sqrt(sum((fit$beta$cov - old$beta$cov)^2)) / sqrt(sum(old$beta$cov^2))
    record$noise_relative_change_from_checkpoint <- abs(fit$omega2$mean - old$omega2$mean) / old$omega2$mean
  }
  record
})
dir.create(output)
utils::write.csv(do.call(rbind, records), file.path(output, "audit_table.csv"), row.names = FALSE)
jsonlite::write_json(list(status = "R123_STATE_OBJECTIVE_CLOSEOUT_PASS", cases = 10,
  objective_reconstruction_verified = TRUE, source_head = jsonlite::read_json(file.path(root, "source_identity.json"))$head,
  test_opened = FALSE, selection_authorized = FALSE,
  audit_table_sha256 = digest::digest(file.path(output, "audit_table.csv"), file = TRUE, algo = "sha256")),
  file.path(output, "objective_check.json"), auto_unbox = TRUE, pretty = TRUE)
cat("R123 exact-state objective closeout passed\n")
