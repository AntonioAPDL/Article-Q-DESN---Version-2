#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- if (!is.na(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_fixtures.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))

args <- app_parse_args(list(
  fixture_dir = "application/cache/joint_qdesn_simulation_dgp_fixtures_20260706",
  output_dir = "application/cache/joint_qdesn_independent_exal_tail_failure_diagnostic_20260706",
  scenario_id = "asymmetric_laplace_tail",
  tau_grid = "0.05,0.10,0.25,0.50,0.75,0.90,0.95",
  sensitivity_tau_grid = "0.70,0.75,0.80",
  alpha_prior_sd_grid = "1,0.5,0.25",
  vb_max_iter = "480",
  vb_tol = "1e-4",
  rhs_vb_inner = "5",
  tau0 = "1",
  zeta2 = "Inf",
  a_sigma = "2",
  b_sigma = "1",
  n_cores = "6"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_csv_numeric <- function(x) {
  vals <- trimws(strsplit(as.character(x), ",", fixed = TRUE)[[1L]])
  vals <- vals[nzchar(vals)]
  out <- suppressWarnings(as.numeric(vals))
  if (!length(out) || any(!is.finite(out))) stop("Expected comma-separated numeric values.", call. = FALSE)
  out
}

parse_number <- function(x) {
  out <- suppressWarnings(as.numeric(as.character(x)[[1L]]))
  if (is.na(out)) stop(sprintf("Expected numeric, got '%s'.", as.character(x)[[1L]]), call. = FALSE)
  out
}

parse_integer <- function(x) {
  out <- as.integer(parse_number(x))
  if (is.na(out)) stop(sprintf("Expected integer, got '%s'.", as.character(x)[[1L]]), call. = FALSE)
  out
}

resolve_repo_path <- function(path, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

write_csv <- function(x, path) {
  app_ensure_dir(dirname(path))
  utils::write.csv(x, path, row.names = FALSE, na = "")
  normalizePath(path, mustWork = TRUE)
}

bind_rows <- function(rows) app_bind_rows_fill(rows)

parallel_lapply <- function(X, FUN, ..., n_cores) {
  n_cores <- max(1L, min(as.integer(n_cores), length(X)))
  if (n_cores <= 1L || .Platform$OS.type == "windows") return(lapply(X, FUN, ...))
  parallel::mclapply(X, FUN, ..., mc.cores = n_cores, mc.preschedule = FALSE)
}

scenario_fixture_for_tau <- function(artifacts, scenario_id, tau) {
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
  tau_index <- which(abs(as.numeric(fixture$tau) - as.numeric(tau)) < 1.0e-12)
  truth_available <- length(tau_index) == 1L
  if (truth_available) {
    true_q <- as.matrix(fixture$true_q[, tau_index, drop = FALSE])
  } else {
    true_q <- matrix(NA_real_, nrow = length(fixture$y), ncol = 1L)
  }
  colnames(true_q) <- app_joint_qdesn_quantile_slug(tau)
  scenario_meta <- fixture$scenario_meta
  list(
    scenario_id = scenario_id,
    y = as.numeric(fixture$y),
    Z = as.matrix(fixture$Z),
    tau = as.numeric(tau),
    true_q = true_q,
    true_quantile_available = truth_available,
    row_meta = fixture$row_meta,
    scenario_class = scenario_meta$scenario_class[[1L]],
    distribution_family = scenario_meta$distribution_family[[1L]],
    dynamics_class = scenario_meta$dynamics_class[[1L]]
  )
}

fit_one_tau <- function(job, artifacts, controls) {
  fixture <- scenario_fixture_for_tau(artifacts, job$scenario_id, job$tau)
  tau <- fixture$tau
  Z <- fixture$Z
  y <- fixture$y
  started <- proc.time()[["elapsed"]]
  al <- app_joint_qvp_fit_al_vb_tiny(
    y = y,
    Z = Z,
    tau = tau,
    max_iter = controls$vb_max_iter,
    tol = controls$vb_tol,
    kappa = 1,
    tau0 = controls$tau0,
    zeta2 = controls$zeta2,
    a_sigma = controls$a_sigma,
    b_sigma = controls$b_sigma,
    alpha_prior_mean = "empirical_quantile",
    alpha_prior_sd = job$alpha_prior_sd,
    alpha_min_spacing = 0,
    max_dense_dim = controls$max_dense_dim,
    rhs_vb_inner = controls$rhs_vb_inner
  )
  exal <- app_joint_qvp_fit_exal_vb_ld_tiny(
    y = y,
    Z = Z,
    tau = tau,
    max_iter = controls$vb_max_iter,
    tol = controls$vb_tol,
    kappa = 1,
    tau0 = controls$tau0,
    zeta2 = controls$zeta2,
    a_sigma = controls$a_sigma,
    b_sigma = controls$b_sigma,
    init = al,
    alpha_min_spacing = 0,
    max_dense_dim = controls$max_dense_dim,
    rhs_vb_inner = controls$rhs_vb_inner
  )
  elapsed <- proc.time()[["elapsed"]] - started
  make_summary <- function(fit, likelihood, label) {
    raw <- as.numeric(fit$qhat_mean[, 1L])
    truth <- as.numeric(fixture$true_q[, 1L])
    truth_available <- isTRUE(fixture$true_quantile_available) && any(is.finite(truth))
    data.frame(
      diagnostic_scope = job$diagnostic_scope,
      scenario_id = job$scenario_id,
      tau = tau,
      alpha_prior_sd = job$alpha_prior_sd,
      likelihood = likelihood,
      display_label = label,
      converged = isTRUE(fit$converged),
      reached_max_iter = !isTRUE(fit$converged),
      trace_rows = nrow(fit$trace %||% data.frame()),
      final_iter = if (!is.null(fit$trace) && nrow(fit$trace) && "iter" %in% names(fit$trace)) max(fit$trace$iter, na.rm = TRUE) else NA_integer_,
      alpha_mean = as.numeric(fit$alpha_mean)[[1L]],
      sigma_mean = as.numeric(fit$sigma_mean)[[1L]],
      gamma_mean = if (!is.null(fit$gamma_mean)) as.numeric(fit$gamma_mean)[[1L]] else NA_real_,
      beta_l2_norm = sqrt(sum(as.numeric(fit$beta_mean)^2)),
      qhat_raw_mean = mean(raw),
      qhat_raw_min = min(raw),
      qhat_raw_max = max(raw),
      true_quantile_available = truth_available,
      true_quantile_mean = if (truth_available) mean(truth) else NA_real_,
      truth_mae = if (truth_available) mean(abs(raw - truth)) else NA_real_,
      truth_rmse = if (truth_available) sqrt(mean((raw - truth)^2)) else NA_real_,
      check_loss_mean = mean(app_check_loss(y, raw, tau)),
      elapsed_seconds = elapsed,
      stringsAsFactors = FALSE
    )
  }
  list(
    fixture = fixture,
    al_fit = al,
    exal_fit = exal,
    summary = rbind(
      make_summary(al, "al", "QDESN RHS"),
      make_summary(exal, "exal", "exQDESN RHS")
    )
  )
}

combined_contract_summary <- function(fit_results, likelihood, alpha_prior_sd) {
  keep <- vapply(fit_results, function(x) {
    identical(x$summary$diagnostic_scope[[1L]], "current_grid_reproduction") &&
      abs(x$summary$alpha_prior_sd[[1L]] - alpha_prior_sd) < 1.0e-12
  }, logical(1L))
  blocks <- fit_results[keep]
  if (!length(blocks)) return(data.frame())
  tau <- vapply(blocks, function(x) x$fixture$tau[[1L]], numeric(1L))
  ord <- order(tau)
  blocks <- blocks[ord]
  tau <- tau[ord]
  raw <- do.call(cbind, lapply(blocks, function(x) {
    fit <- if (likelihood == "al") x$al_fit else x$exal_fit
    as.numeric(fit$qhat_mean[, 1L])
  }))
  true_q <- do.call(cbind, lapply(blocks, function(x) as.numeric(x$fixture$true_q[, 1L])))
  y <- blocks[[1L]]$fixture$y
  contract <- app_joint_qdesn_apply_monotone_contract(raw, tau)
  rows <- lapply(seq_along(tau), function(k) {
    adj <- contract$qhat_contract[, k] - raw[, k]
    data.frame(
      diagnostic_scope = "current_grid_reproduction",
      scenario_id = blocks[[1L]]$fixture$scenario_id,
      alpha_prior_sd = alpha_prior_sd,
      likelihood = likelihood,
      display_label = if (likelihood == "al") "QDESN RHS" else "exQDESN RHS",
      tau = tau[[k]],
      raw_mean = mean(raw[, k]),
      raw_min = min(raw[, k]),
      raw_max = max(raw[, k]),
      contract_mean = mean(contract$qhat_contract[, k]),
      contract_min = min(contract$qhat_contract[, k]),
      contract_max = max(contract$qhat_contract[, k]),
      true_quantile_mean = mean(true_q[, k]),
      raw_truth_mae = mean(abs(raw[, k] - true_q[, k])),
      contract_truth_mae = mean(abs(contract$qhat_contract[, k] - true_q[, k])),
      contract_check_loss_mean = mean(app_check_loss(y, contract$qhat_contract[, k], tau[[k]])),
      mean_abs_adjustment = mean(abs(adj)),
      max_abs_adjustment = max(abs(adj)),
      adjustment_rate = mean(abs(adj) > 1.0e-10),
      raw_crossing_pairs_total = sum(contract$raw_crossing$n_crossing_pairs),
      contract_crossing_pairs_total = sum(contract$contract_crossing$n_crossing_pairs),
      stringsAsFactors = FALSE
    )
  })
  bind_rows(rows)
}

failure_assessment <- function(raw_contract, tau_summary) {
  exal <- raw_contract[raw_contract$likelihood == "exal", , drop = FALSE]
  primary <- exal[abs(exal$tau - 0.75) < 1.0e-12, , drop = FALSE]
  severe <- nrow(primary) &&
    primary$max_abs_adjustment[[1L]] > 1 &&
    primary$contract_truth_mae[[1L]] > 1
  data.frame(
    issue_id = "independent_exal_asymmetric_tail_tau075",
    status = if (severe) "confirmed_failure" else "not_reproduced",
    scenario_id = unique(exal$scenario_id)[[1L]],
    model = "exQDESN RHS",
    primary_tau = 0.75,
    raw_crossing_pairs_total = if (nrow(exal)) max(exal$raw_crossing_pairs_total, na.rm = TRUE) else NA_real_,
    contract_crossing_pairs_total = if (nrow(exal)) max(exal$contract_crossing_pairs_total, na.rm = TRUE) else NA_real_,
    max_abs_adjustment_tau075 = if (nrow(primary)) primary$max_abs_adjustment[[1L]] else NA_real_,
    contract_truth_mae_tau075 = if (nrow(primary)) primary$contract_truth_mae[[1L]] else NA_real_,
    likely_cause = "K=1 exAL update or initialization instability at an interior upper quantile; joint exAL does not show the same failure.",
    recommended_next_action = "Add detailed exAL coordinate-update tracing and test stabilizers before using independent exQDESN RHS in main article tables.",
    stringsAsFactors = FALSE
  )
}

fixture_dir <- resolve_repo_path(arg_value("fixture_dir"), must_work = TRUE)
out_dir <- resolve_repo_path(arg_value("output_dir"), must_work = FALSE)
app_ensure_dir(out_dir)
scenario_id <- as.character(arg_value("scenario_id"))
tau_grid <- parse_csv_numeric(arg_value("tau_grid"))
sensitivity_tau_grid <- parse_csv_numeric(arg_value("sensitivity_tau_grid"))
alpha_prior_sd_grid <- parse_csv_numeric(arg_value("alpha_prior_sd_grid"))
controls <- list(
  vb_max_iter = parse_integer(arg_value("vb_max_iter")),
  vb_tol = parse_number(arg_value("vb_tol")),
  rhs_vb_inner = parse_integer(arg_value("rhs_vb_inner")),
  tau0 = parse_number(arg_value("tau0")),
  zeta2 = parse_number(arg_value("zeta2")),
  a_sigma = parse_number(arg_value("a_sigma")),
  b_sigma = parse_number(arg_value("b_sigma")),
  max_dense_dim = 300L
)
n_cores <- parse_integer(arg_value("n_cores"))

artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)
registry <- artifacts$frozen_registry
registry <- registry[registry$scenario_id == scenario_id, , drop = FALSE]
if (nrow(registry) != 1L) stop(sprintf("Unknown scenario_id '%s'.", scenario_id), call. = FALSE)

jobs <- list()
for (tau in tau_grid) {
  jobs[[length(jobs) + 1L]] <- data.frame(
    diagnostic_scope = "current_grid_reproduction",
    scenario_id = scenario_id,
    tau = tau,
    alpha_prior_sd = 1,
    stringsAsFactors = FALSE
  )
}
for (tau in sensitivity_tau_grid) {
  for (apsd in alpha_prior_sd_grid) {
    jobs[[length(jobs) + 1L]] <- data.frame(
      diagnostic_scope = "tau_alpha_prior_sensitivity",
      scenario_id = scenario_id,
      tau = tau,
      alpha_prior_sd = apsd,
      stringsAsFactors = FALSE
    )
  }
}
jobs <- bind_rows(jobs)
job_list <- split(jobs, seq_len(nrow(jobs)))
fit_results <- parallel_lapply(job_list, fit_one_tau, artifacts = artifacts, controls = controls, n_cores = n_cores)

tau_summary <- bind_rows(lapply(fit_results, `[[`, "summary"))
raw_contract <- bind_rows(list(
  combined_contract_summary(fit_results, "al", 1),
  combined_contract_summary(fit_results, "exal", 1)
))
hit_truth <- tau_summary[, c("diagnostic_scope", "scenario_id", "tau", "alpha_prior_sd", "likelihood", "display_label", "truth_mae", "truth_rmse", "check_loss_mean", "qhat_raw_mean", "true_quantile_mean"), drop = FALSE]
alpha_gamma_sigma <- tau_summary[, c("diagnostic_scope", "scenario_id", "tau", "alpha_prior_sd", "likelihood", "display_label", "alpha_mean", "gamma_mean", "sigma_mean", "converged", "reached_max_iter", "final_iter"), drop = FALSE]
beta_norm <- tau_summary[, c("diagnostic_scope", "scenario_id", "tau", "alpha_prior_sd", "likelihood", "display_label", "beta_l2_norm", "qhat_raw_min", "qhat_raw_max"), drop = FALSE]
assessment <- failure_assessment(raw_contract, tau_summary)
run_config <- data.frame(
  run_id = "joint_qdesn_independent_exal_tail_failure_diagnostic",
  fixture_dir = fixture_dir,
  out_dir = out_dir,
  scenario_id = scenario_id,
  tau_grid = app_joint_qdesn_format_tau(tau_grid),
  sensitivity_tau_grid = app_joint_qdesn_format_tau(sensitivity_tau_grid),
  alpha_prior_sd_grid = paste(alpha_prior_sd_grid, collapse = ","),
  vb_max_iter = controls$vb_max_iter,
  vb_tol = controls$vb_tol,
  rhs_vb_inner = controls$rhs_vb_inner,
  tau0 = controls$tau0,
  n_cores = n_cores,
  stringsAsFactors = FALSE
)
readme_path <- file.path(out_dir, "README.md")
writeLines(c(
  "# Joint QDESN Independent exAL Tail-Failure Diagnostic",
  "",
  "This diagnostic targets the independent `exQDESN RHS` failure on the `asymmetric_laplace_tail` scenario.",
  "It reproduces K=1 AL and exAL fits on the current quantile grid and probes nearby tau values with alpha-prior initialization sensitivity.",
  "",
  sprintf("Status: `%s`.", assessment$status[[1L]]),
  sprintf("Recommended action: %s", assessment$recommended_next_action[[1L]])
), readme_path, useBytes = TRUE)

paths <- c(
  targeted_run_config = write_csv(run_config, file.path(out_dir, "targeted_run_config.csv")),
  tau_specific_fit_summary = write_csv(tau_summary, file.path(out_dir, "tau_specific_fit_summary.csv")),
  alpha_gamma_sigma_path_summary = write_csv(alpha_gamma_sigma, file.path(out_dir, "alpha_gamma_sigma_path_summary.csv")),
  beta_norm_summary = write_csv(beta_norm, file.path(out_dir, "beta_norm_summary.csv")),
  raw_contract_quantile_summary = write_csv(raw_contract, file.path(out_dir, "raw_contract_quantile_summary.csv")),
  hit_truth_score_summary = write_csv(hit_truth, file.path(out_dir, "hit_truth_score_summary.csv")),
  exal_failure_assessment = write_csv(assessment, file.path(out_dir, "exal_failure_assessment.csv")),
  provenance = write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
  readme = normalizePath(readme_path, mustWork = TRUE)
)
manifest <- data.frame(
  label = names(paths),
  relative_path = basename(paths),
  size_bytes = as.numeric(file.info(paths)$size),
  sha256 = vapply(paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
manifest_path <- write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))

cat(sprintf("Joint QDESN independent exAL tail diagnostic written to %s\n", out_dir))
cat(sprintf("Assessment status: %s\n", assessment$status[[1L]]))
cat(sprintf("Artifact manifest: %s\n", manifest_path))
