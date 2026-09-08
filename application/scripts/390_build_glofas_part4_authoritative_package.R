#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- sub("^--file=", "", script_arg[[1L]])
repo_root <- normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
suppressPackageStartupMessages(library(ggplot2))

args <- app_parse_args(list(
  source_runtime_root = "local_trackers/runtime_configs/glofas_part4_latent_family_dec25_exactopt_r3_fivecore_20260906",
  continuation_runtime_root = "local_trackers/runtime_configs/glofas_part4_joint_convergence_closeout_20260907",
  output_tag = "glofas_part4_joint_al_authoritative_20260907"
))
source_root <- app_resolve_path(args$source_runtime_root, must_work = TRUE)
continuation_root <- app_resolve_path(args$continuation_runtime_root, must_work = TRUE)
tag <- trimws(as.character(args$output_tag)[[1L]])
if (!grepl("^[A-Za-z0-9_.-]+$", tag)) stop("Invalid --output_tag.", call. = FALSE)

source_label <- basename(source_root)
al_job <- "glofas_part4_joint_al_continuation_20260907"
exal_job <- "glofas_part4_joint_exal_continuation_20260907"
tau_grid <- c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95)
tau_ids <- c("p05", "p20", "p35", "p50", "p65", "p80", "p95")
common_tau <- c(0.05, 0.35, 0.50, 0.65, 0.80, 0.95)
cutoff <- as.Date("2022-12-25")
issued_start <- as.Date("2022-12-26")
issued_end <- as.Date("2023-01-22")

assert_complete <- function(root, job_id) {
  path <- file.path(root, "status", paste0(job_id, ".completed"))
  if (!file.exists(path)) stop(sprintf("Required completed marker is missing: %s.", path), call. = FALSE)
  invisible(path)
}

verify_artifact_manifest <- function(root, job_id) {
  path <- file.path(root, "manifests", paste0(job_id, "_artifacts.csv"))
  manifest <- read.csv(path, stringsAsFactors = FALSE)
  observed <- vapply(manifest$relative_path, function(rel) {
    target <- file.path(root, rel)
    if (!file.exists(target)) return(NA_character_)
    app_sha256_file(target)
  }, character(1L))
  if (anyNA(observed) || any(tolower(observed) != tolower(manifest$sha256))) {
    stop(sprintf("Artifact-manifest verification failed for %s.", job_id), call. = FALSE)
  }
  invisible(path)
}

base_manifest <- read.csv(file.path(source_root, "configs", "part4_model_manifest.csv"), stringsAsFactors = FALSE)
if (nrow(base_manifest) != 18L || anyDuplicated(base_manifest$run_id)) {
  stop("The frozen Part 4 source manifest is not the expected 18-job DAG.", call. = FALSE)
}
for (job in base_manifest$run_id) {
  assert_complete(source_root, job)
  verify_artifact_manifest(source_root, job)
}
for (job in c(al_job, exal_job)) {
  assert_complete(continuation_root, job)
  verify_artifact_manifest(continuation_root, job)
}

fixed_audit <- read.csv(file.path(source_root, "manifests", "part4_fixed_window_audit.csv"), stringsAsFactors = FALSE)
required_audit <- c(
  origin = "2022-12-25", train_end = "2022-12-25",
  eval_start = "2022-12-26", eval_end = "2023-01-24",
  requested_horizon = "30", issued_horizons = "1:28",
  issued_dates = "2022-12-26:2023-01-22", member_count = "51:51",
  scoring_truth_available = "28/28"
)
observed_audit <- setNames(as.character(fixed_audit$detail), fixed_audit$check)
if (!identical(unname(observed_audit[names(required_audit)]), unname(required_audit)) ||
    any(fixed_audit$status[match(names(required_audit), fixed_audit$check)] != "pass")) {
  stop("The frozen Part 4 window audit does not match the publication contract.", call. = FALSE)
}

al_fit_path <- file.path(continuation_root, "objects", paste0(al_job, "_fit_side.rds"))
exal_fit_path <- file.path(continuation_root, "objects", paste0(exal_job, "_fit_side.rds"))
message("Reading final joint convergence metadata...")
al_fit <- readRDS(al_fit_path)
al_convergence <- data.frame(
  family = "Joint AL", converged = isTRUE(al_fit$converged),
  outer_converged = isTRUE(al_fit$converged_outer), inner_converged = isTRUE(al_fit$converged_inner),
  rhs_converged = isTRUE(al_fit$converged_rhs),
  outer_iterations = nrow(al_fit$trace), continuation_count = al_fit$continuation_count,
  stopping_reason = al_fit$stopping_reason, cumulative_runtime_seconds = al_fit$runtime_seconds,
  stringsAsFactors = FALSE
)
if (!isTRUE(al_fit$converged) || !isTRUE(al_fit$converged_outer) ||
    !isTRUE(al_fit$converged_inner) || !isTRUE(al_fit$converged_rhs)) {
  stop("Joint AL did not pass the outer, inner, and RHS convergence gates.", call. = FALSE)
}
al_rhs_certificate <- merge(
  al_fit$rhs_convergence_diagnostics,
  al_fit$rhs_schedule_rebase_audit,
  by = c("component", "rhs_block"), all = TRUE
)
al_rhs_certificate$family <- "Joint AL"
rm(al_fit)
invisible(gc())
exal_fit <- readRDS(exal_fit_path)
exal_convergence <- data.frame(
  family = "Joint exAL", converged = isTRUE(exal_fit$converged),
  outer_converged = isTRUE(exal_fit$converged_outer), inner_converged = isTRUE(exal_fit$converged_inner),
  rhs_converged = isTRUE(exal_fit$converged_rhs),
  outer_iterations = nrow(exal_fit$trace), continuation_count = exal_fit$continuation_count,
  stopping_reason = exal_fit$stopping_reason, cumulative_runtime_seconds = exal_fit$runtime_seconds,
  stringsAsFactors = FALSE
)
exal_rhs_certificate <- merge(
  exal_fit$rhs_convergence_diagnostics,
  exal_fit$rhs_schedule_rebase_audit,
  by = c("component", "rhs_block"), all = TRUE
)
exal_rhs_certificate$family <- "Joint exAL"
rm(exal_fit)
invisible(gc())
convergence <- rbind(al_convergence, exal_convergence)
rhs_certificate <- app_bind_rows_fill(list(al_rhs_certificate, exal_rhs_certificate))

score_file <- function(root, job, suffix = "by_horizon") {
  file.path(root, "scores", paste0(job, "_", suffix, ".csv"))
}
prediction_file <- function(root, job) {
  file.path(root, "predictions", paste0(job, "_posterior_draws.csv.gz"))
}
coefficient_file <- function(root, job) {
  file.path(root, "coefficients", paste0(job, "_coefficients.csv"))
}

check_loss <- function(y, q, tau) (tau - as.numeric(y < q)) * (y - q)
grid_crps_by_date <- function(rows) {
  rows$target_date <- as.Date(rows$target_date)
  blocks <- split(rows, rows$target_date)
  vapply(blocks, function(block) {
    block <- block[order(as.numeric(block$quantile_level)), , drop = FALSE]
    q <- as.numeric(block$quantile_level)
    2 * sum(diff(q) * (head(block$check_loss, -1L) + tail(block$check_loss, -1L)) / 2)
  }, numeric(1L))
}

summarize_quantile_rows <- function(rows, family, runtime_seconds, converged, role) {
  rows$target_date <- as.Date(rows$target_date)
  rows <- rows[order(rows$target_date, as.numeric(rows$quantile_level)), , drop = FALSE]
  dates <- sort(unique(rows$target_date))
  wide <- reshape(
    rows[c("target_date", "y_reference", "y_reference_original", "quantile_level", "qhat", "qhat_original")],
    idvar = c("target_date", "y_reference", "y_reference_original"),
    timevar = "quantile_level", direction = "wide"
  )
  alpha <- 0.10
  interval <- (wide$qhat.0.95 - wide$qhat.0.05) +
    (2 / alpha) * (wide$qhat.0.05 - wide$y_reference) * as.numeric(wide$y_reference < wide$qhat.0.05) +
    (2 / alpha) * (wide$y_reference - wide$qhat.0.95) * as.numeric(wide$y_reference > wide$qhat.0.95)
  interval_original <- (wide$qhat_original.0.95 - wide$qhat_original.0.05) +
    (2 / alpha) * (wide$qhat_original.0.05 - wide$y_reference_original) * as.numeric(wide$y_reference_original < wide$qhat_original.0.05) +
    (2 / alpha) * (wide$y_reference_original - wide$qhat_original.0.95) * as.numeric(wide$y_reference_original > wide$qhat_original.0.95)
  qmat <- do.call(cbind, lapply(tau_grid, function(q) {
    rows$qhat[abs(as.numeric(rows$quantile_level) - q) < 1.0e-12]
  }))
  p50 <- rows[abs(as.numeric(rows$quantile_level) - 0.50) < 1.0e-12, , drop = FALSE]
  data.frame(
    family = family, role = role, n_scored_horizons = length(dates),
    mean_check_loss = mean(rows$check_loss),
    interval_score = mean(interval), coverage90 = mean(wide$y_reference >= wide$qhat.0.05 & wide$y_reference <= wide$qhat.0.95),
    crps_grid_log1p = mean(grid_crps_by_date(rows)),
    interval_score_original = mean(interval_original),
    crps_grid_original = mean(vapply(split(rows, rows$target_date), function(block) {
      block <- block[order(block$quantile_level), , drop = FALSE]
      q <- as.numeric(block$quantile_level)
      2 * sum(diff(q) * (head(block$check_loss_original, -1L) + tail(block$check_loss_original, -1L)) / 2)
    }, numeric(1L))),
    median_mae_log1p = mean(abs(p50$qhat - p50$y_reference)),
    median_rmse_log1p = sqrt(mean((p50$qhat - p50$y_reference)^2)),
    crossing_pairs = sum(qmat[, -ncol(qmat), drop = FALSE] > qmat[, -1L, drop = FALSE]),
    runtime_seconds = runtime_seconds, converged = converged,
    stringsAsFactors = FALSE
  )
}

independent_rows <- function(likelihood) {
  family <- paste0("independent_", likelihood, "_rhs_vb")
  jobs <- paste0(source_label, "_", family, "_", tau_ids)
  do.call(rbind, lapply(jobs, function(job) read.csv(score_file(source_root, job), stringsAsFactors = FALSE)))
}
joint_rows <- function(job) read.csv(score_file(continuation_root, job), stringsAsFactors = FALSE)

normal_rows <- function(job) {
  draws <- read.csv(gzfile(prediction_file(source_root, job)), stringsAsFactors = FALSE)
  draws$target_date <- as.Date(draws$target_date)
  blocks <- split(draws, draws$target_date)
  do.call(rbind, lapply(blocks, function(block) {
    y <- unique(as.numeric(block$y_reference))
    y_original <- expm1(y)
    qhat <- as.numeric(quantile(block$latent_y_draw, probs = tau_grid, names = FALSE, type = 8))
    data.frame(
      target_date = unique(block$target_date), horizon = unique(block$horizon),
      quantile_level = tau_grid, y_reference = y, qhat = qhat,
      check_loss = check_loss(y, qhat, tau_grid),
      y_reference_original = y_original, qhat_original = expm1(qhat),
      check_loss_original = check_loss(y_original, expm1(qhat), tau_grid),
      stringsAsFactors = FALSE
    )
  }))
}

normal_runtime <- function(job) {
  read.csv(score_file(source_root, job, "summary"), stringsAsFactors = FALSE)$runtime_seconds[[1L]]
}
independent_runtime <- function(likelihood) {
  jobs <- paste0(source_label, "_independent_", likelihood, "_rhs_vb_", tau_ids)
  sum(vapply(jobs, function(job) {
    read.csv(score_file(source_root, job, "summary"), stringsAsFactors = FALSE)$runtime_seconds[[1L]]
  }, numeric(1L)))
}

message("Recomputing comparable seven-quantile forecast scores...")
forecast_scores <- rbind(
  summarize_quantile_rows(
    normal_rows(paste0(source_label, "_normal_ridge_diagnostic")), "Normal Ridge",
    normal_runtime(paste0(source_label, "_normal_ridge_diagnostic")), TRUE, "normal_baseline"
  ),
  summarize_quantile_rows(
    normal_rows(paste0(source_label, "_normal_rhs_vb_diagnostic")), "Normal RHS/VB",
    normal_runtime(paste0(source_label, "_normal_rhs_vb_diagnostic")), TRUE, "normal_baseline"
  ),
  summarize_quantile_rows(independent_rows("al"), "Independent AL", independent_runtime("al"), TRUE, "quantile_comparator"),
  summarize_quantile_rows(independent_rows("exal"), "Independent exAL", independent_runtime("exal"), TRUE, "quantile_comparator"),
  summarize_quantile_rows(joint_rows(al_job), "Joint AL", al_convergence$cumulative_runtime_seconds, TRUE, "selected_quantile_model"),
  summarize_quantile_rows(joint_rows(exal_job), "Joint exAL", exal_convergence$cumulative_runtime_seconds, exal_convergence$converged, "quantile_sensitivity")
)

message("Reading the frozen design for raw-GloFAS and historical guardrail recomputation...")
design_path <- file.path(source_root, "objects", "part4_shared_design_truth_free.rds")
design <- readRDS(design_path)
panel <- design$base_panel
panel$target_date <- as.Date(panel$target_date)
ensemble <- design$latent_data$g_ensemble
ensemble$target_date <- as.Date(ensemble$target_date)
ensemble <- ensemble[ensemble$target_date >= issued_start & ensemble$target_date <= issued_end, , drop = FALSE]
truth_sidecar <- readRDS(file.path(source_root, "objects", "part4_scoring_panel_sidecar.rds"))$panel
truth_sidecar$target_date <- as.Date(truth_sidecar$target_date)
raw_rows <- do.call(rbind, lapply(split(ensemble, ensemble$target_date), function(block) {
  date <- unique(block$target_date)
  y <- truth_sidecar$y_transformed[truth_sidecar$target_date == date]
  qhat <- as.numeric(quantile(block$g_transformed, probs = tau_grid, names = FALSE, type = 8))
  data.frame(
    target_date = date, horizon = as.integer(date - cutoff), quantile_level = tau_grid,
    y_reference = y, qhat = qhat, check_loss = check_loss(y, qhat, tau_grid),
    y_reference_original = expm1(y), qhat_original = expm1(qhat),
    check_loss_original = check_loss(expm1(y), expm1(qhat), tau_grid), stringsAsFactors = FALSE
  )
}))
forecast_scores <- rbind(
  forecast_scores,
  summarize_quantile_rows(raw_rows, "Raw GloFAS", 0, TRUE, "raw_ensemble_baseline")
)
forecast_scores <- forecast_scores[order(forecast_scores$crps_grid_log1p), , drop = FALSE]
raw_crps <- forecast_scores$crps_grid_log1p[forecast_scores$family == "Raw GloFAS"]
forecast_scores$crps_reduction_vs_raw <- (raw_crps - forecast_scores$crps_grid_log1p) / raw_crps

message("Recomputing the Joint AL historical guardrail on the fitted scale...")
al_coef <- read.csv(coefficient_file(continuation_root, al_job), stringsAsFactors = FALSE)
history_q <- do.call(cbind, lapply(tau_grid, function(q) {
  block <- al_coef[abs(as.numeric(al_coef$quantile_level) - q) < 1.0e-12, , drop = FALSE]
  beta <- block[startsWith(block$coefficient, "beta__"), , drop = FALSE]
  if (nrow(beta) != ncol(design$X_beta)) stop("Joint AL historical coefficient/design mismatch.", call. = FALSE)
  as.numeric(design$X_beta %*% as.numeric(beta$mean))
}))
colnames(history_q) <- format(tau_grid, trim = TRUE)
history_d <- do.call(cbind, lapply(tau_grid, function(q) {
  block <- al_coef[abs(as.numeric(al_coef$quantile_level) - q) < 1.0e-12, , drop = FALSE]
  alpha <- block[startsWith(block$coefficient, "alpha__"), , drop = FALSE]
  if (nrow(alpha) != ncol(design$X_alpha)) stop("Joint AL discrepancy coefficient/design mismatch.", call. = FALSE)
  as.numeric(design$X_alpha %*% as.numeric(alpha$mean))
}))
colnames(history_d) <- format(tau_grid, trim = TRUE)
history_truth <- as.numeric(panel$y_transformed)
history_windows <- list(all = seq_along(history_truth), last1000 = tail(seq_along(history_truth), 1000L),
                        last200 = tail(seq_along(history_truth), 200L), last50 = tail(seq_along(history_truth), 50L))
historical_new <- do.call(rbind, lapply(names(history_windows), function(window) {
  idx <- history_windows[[window]]
  losses <- vapply(seq_along(tau_grid), function(k) mean(check_loss(history_truth[idx], history_q[idx, k], tau_grid[[k]])), numeric(1L))
  p50 <- history_q[idx, 4L]
  data.frame(
    authority = "Part4 Joint AL", window = window, grid = "native_7q_0.05_0.20_0.35_0.50_0.65_0.80_0.95",
    n_dates = length(idx), crps_grid_log1p = 2 * sum(diff(tau_grid) * (head(losses, -1L) + tail(losses, -1L)) / 2),
    coverage90 = mean(history_truth[idx] >= history_q[idx, 1L] & history_truth[idx] <= history_q[idx, 7L]),
    median_mae_log1p = mean(abs(p50 - history_truth[idx])), median_rmse_log1p = sqrt(mean((p50 - history_truth[idx])^2)),
    crossing_date_fraction = mean(apply(history_q[idx, , drop = FALSE], 1L, function(x) any(diff(x) < 0))),
    crossing_pair_count = sum(history_q[idx, -ncol(history_q), drop = FALSE] > history_q[idx, -1L, drop = FALSE]),
    stringsAsFactors = FALSE
  )
}))
old_native <- read.csv(
  app_path("tables", "glofas_application_observed_history_full7_scores__glofas_fr09_authoritative_full7_20260811.csv"),
  stringsAsFactors = FALSE
)
old_native <- old_native[old_native$estimate_mode == "independent" & old_native$window %in% names(history_windows), , drop = FALSE]
historical_old <- data.frame(
  authority = "FR09 independent AL", window = old_native$window,
  grid = "native_7q_0.05_0.15_0.35_0.50_0.65_0.80_0.95", n_dates = old_native$n_dates,
  crps_grid_log1p = old_native$crps_quantile_grid_mean, coverage90 = old_native$interval_coverage,
  median_mae_log1p = old_native$median_log1p_mae, median_rmse_log1p = old_native$median_log1p_rmse,
  crossing_date_fraction = old_native$crossing_date_fraction,
  crossing_pair_count = old_native$crossing_pair_count, stringsAsFactors = FALSE
)
historical_guardrail <- rbind(historical_old, historical_new)

old_by_q <- read.csv(
  app_path("tables", "glofas_application_observed_history_full7_scores_by_quantile__glofas_fr09_authoritative_full7_20260811.csv"),
  stringsAsFactors = FALSE
)
old_by_q <- old_by_q[old_by_q$estimate_mode == "independent" & old_by_q$window %in% names(history_windows) &
                       old_by_q$quantile_level %in% common_tau, , drop = FALSE]
common_grid <- do.call(rbind, lapply(names(history_windows), function(window) {
  idx <- history_windows[[window]]
  new_losses <- vapply(common_tau, function(q) {
    k <- which(abs(tau_grid - q) < 1.0e-12)
    mean(check_loss(history_truth[idx], history_q[idx, k], q))
  }, numeric(1L))
  old <- old_by_q[old_by_q$window == window, , drop = FALSE]
  old <- old[order(old$quantile_level), , drop = FALSE]
  old_crps <- 2 * sum(diff(common_tau) * (head(old$check_loss_mean, -1L) + tail(old$check_loss_mean, -1L)) / 2)
  new_crps <- 2 * sum(diff(common_tau) * (head(new_losses, -1L) + tail(new_losses, -1L)) / 2)
  data.frame(
    window = window, grid = "common_6q_0.05_0.35_0.50_0.65_0.80_0.95",
    fr09_crps_log1p = old_crps, part4_joint_al_crps_log1p = new_crps,
    relative_change = (new_crps - old_crps) / old_crps,
    decision = "Part4 improves issued forecast but materially worsens historical fit",
    stringsAsFactors = FALSE
  )
}))

model_spec <- data.frame(
  component = c("Reference", "Discrepancy"), D = c(1L, 1L), n = c(3000L, 2500L), m = c(360L, 360L),
  output_lags = c("1:360", "1:360 discrepancy"), covariate_lags = c("PPT/soil 0:180", "PPT/soil 0:180"),
  alpha = c(0.50, 0.80), rho = c(0.90, 0.70), washout = c(500L, 500L),
  seed = c(20260512L, 20261521L), rhs_tau0 = c(1, 0.001), direct_readout_inputs = c("none", "none"),
  stringsAsFactors = FALSE
)

table_dir <- app_path("tables")
figure_dir <- app_path("figures", "glofas_application")
app_ensure_dir(table_dir)
app_ensure_dir(figure_dir)
paths <- c(
  forecast_csv = file.path(table_dir, paste0("glofas_application_part4_forecast_scores__", tag, ".csv")),
  history_csv = file.path(table_dir, paste0("glofas_application_part4_historical_guardrail__", tag, ".csv")),
  common_csv = file.path(table_dir, paste0("glofas_application_part4_common_grid_tradeoff__", tag, ".csv")),
  convergence_csv = file.path(table_dir, paste0("glofas_application_part4_joint_convergence__", tag, ".csv")),
  rhs_certificate_csv = file.path(table_dir, paste0("glofas_application_part4_rhs_release_certificate__", tag, ".csv")),
  spec_csv = file.path(table_dir, paste0("glofas_application_part4_model_spec__", tag, ".csv")),
  decision_csv = file.path(table_dir, paste0("glofas_application_part4_selection_decision__", tag, ".csv")),
  score_tex = file.path(table_dir, paste0("glofas_application_part4_forecast_scores__", tag, ".tex")),
  all_scores_tex = file.path(table_dir, paste0("glofas_application_part4_all_family_scores__", tag, ".tex")),
  guardrail_tex = file.path(table_dir, paste0("glofas_application_part4_historical_guardrail__", tag, ".tex")),
  outputs_tex = file.path(table_dir, paste0("glofas_application_part4_current_outputs__", tag, ".tex")),
  main_figure = file.path(figure_dir, paste0("glofas_part4_joint_al_last30_issued28__", tag, ".pdf")),
  grouped_figure = file.path(figure_dir, "diagnostics", paste0("glofas_part4_grouped_family_comparison__", tag, ".pdf")),
  grouped_scores = file.path(table_dir, paste0("glofas_application_part4_grouped_family_scores__", tag, ".csv")),
  grouped_script = app_path("application", "scripts", "391_plot_glofas_part4_grouped_family_comparison.R")
)
write.csv(forecast_scores, paths[["forecast_csv"]], row.names = FALSE)
write.csv(historical_guardrail, paths[["history_csv"]], row.names = FALSE)
write.csv(common_grid, paths[["common_csv"]], row.names = FALSE)
write.csv(convergence, paths[["convergence_csv"]], row.names = FALSE)
write.csv(rhs_certificate, paths[["rhs_certificate_csv"]], row.names = FALSE)
write.csv(model_spec, paths[["spec_csv"]], row.names = FALSE)

selected <- forecast_scores[forecast_scores$family == "Joint AL", , drop = FALSE]
raw <- forecast_scores[forecast_scores$family == "Raw GloFAS", , drop = FALSE]
repo_relative <- function(path) substring(normalizePath(path, mustWork = FALSE), nchar(normalizePath(repo_root)) + 2L)
selection_decision <- data.frame(
  selected_family = "Joint AL",
  authority_scope = "Part4 issued-window latent-path ensemble-likelihood experiment",
  quantile_grid = paste(format(tau_grid, trim = TRUE), collapse = ","),
  selected_crps_grid_log1p = selected$crps_grid_log1p,
  raw_glofas_crps_grid_log1p = raw$crps_grid_log1p,
  crps_reduction_vs_raw = selected$crps_reduction_vs_raw,
  normal_ridge_numerically_lower = forecast_scores$crps_grid_log1p[forecast_scores$family == "Normal Ridge"] < selected$crps_grid_log1p,
  normal_ridge_role = "Normal diagnostic baseline with severe interval undercoverage; not the selected quantile model",
  historical_guardrail = "failed versus FR09; preserve and disclose FR09 as stronger historical benchmark",
  crossing_fix = "none",
  scientific_status = "selected_after_outer_inner_and_rhs_convergence_qualification",
  stringsAsFactors = FALSE
)
write.csv(selection_decision, paths[["decision_csv"]], row.names = FALSE)
score_tex <- c(
  "\\begin{tabular}{lrrrrrr}", "\\toprule",
  "Model & Horizons & Check loss & Interval score & CRPS & Coverage & CRPS reduction \\\\",
  "\\midrule",
  sprintf("Joint AL Q--DESN & %d & %.4f & %.4f & %.4f & %.3f & %.1f\\%% \\\\", selected$n_scored_horizons, selected$mean_check_loss, selected$interval_score, selected$crps_grid_log1p, selected$coverage90, 100 * selected$crps_reduction_vs_raw),
  sprintf("Independent AL Q--DESN & %d & %.4f & %.4f & %.4f & %.3f & %.1f\\%% \\\\", forecast_scores$n_scored_horizons[forecast_scores$family == "Independent AL"], forecast_scores$mean_check_loss[forecast_scores$family == "Independent AL"], forecast_scores$interval_score[forecast_scores$family == "Independent AL"], forecast_scores$crps_grid_log1p[forecast_scores$family == "Independent AL"], forecast_scores$coverage90[forecast_scores$family == "Independent AL"], 100 * forecast_scores$crps_reduction_vs_raw[forecast_scores$family == "Independent AL"]),
  sprintf("Raw GloFAS & %d & %.4f & %.4f & %.4f & %.3f & -- \\\\", raw$n_scored_horizons, raw$mean_check_loss, raw$interval_score, raw$crps_grid_log1p, raw$coverage90),
  "\\bottomrule", "\\end{tabular}"
)
writeLines(score_tex, paths[["score_tex"]])
all_scores_tex <- c(
  "\\begin{tabular}{lrrrrr}", "\\toprule",
  "Model & CRPS (log1p) & CRPS (original) & Coverage & CPU hours & Converged \\\\",
  "\\midrule",
  vapply(seq_len(nrow(forecast_scores)), function(i) sprintf(
    "%s & %.4f & %.3f & %.3f & %.2f & %s \\\\",
    forecast_scores$family[[i]], forecast_scores$crps_grid_log1p[[i]],
    forecast_scores$crps_grid_original[[i]], forecast_scores$coverage90[[i]],
    forecast_scores$runtime_seconds[[i]] / 3600,
    if (isTRUE(forecast_scores$converged[[i]])) "yes" else "no"
  ), character(1L)),
  "\\bottomrule", "\\end{tabular}"
)
writeLines(all_scores_tex, paths[["all_scores_tex"]])
guardrail_tex <- c(
  "\\begin{tabular}{lrrr}", "\\toprule",
  "Historical window & FR09 CRPS & Part 4 Joint AL CRPS & Relative change \\\\", "\\midrule",
  vapply(seq_len(nrow(common_grid)), function(i) sprintf(
    "%s & %.4f & %.4f & %+.1f\\%% \\\\", common_grid$window[[i]], common_grid$fr09_crps_log1p[[i]],
    common_grid$part4_joint_al_crps_log1p[[i]], 100 * common_grid$relative_change[[i]]
  ), character(1L)),
  "\\bottomrule", "\\end{tabular}"
)
writeLines(guardrail_tex, paths[["guardrail_tex"]])

outputs <- c(
  sprintf("\\newcommand{\\GlofasApplicationCurrentRunId}{\\detokenize{%s}}", tag),
  sprintf("\\newcommand{\\GlofasApplicationCurrentConfigPath}{\\detokenize{%s}}", repo_relative(paths[["spec_csv"]])),
  sprintf("\\newcommand{\\GlofasApplicationCurrentPromotionManifest}{\\detokenize{%s}}", repo_relative(paths[["decision_csv"]])),
  sprintf("\\newcommand{\\GlofasApplicationCurrentSelectionManifest}{\\detokenize{%s}}", repo_relative(paths[["decision_csv"]])),
  sprintf("\\newcommand{\\GlofasApplicationCurrentCandidateId}{\\detokenize{%s}}", al_job),
  "\\newcommand{\\GlofasApplicationCurrentDiscrepancyTransitionStrategy}{\\detokenize{joint latent-path ensemble likelihood}}",
  sprintf("\\newcommand{\\GlofasApplicationCurrentScoreTable}{%s}", repo_relative(paths[["score_tex"]])),
  sprintf("\\newcommand{\\GlofasApplicationCurrentCorrectedPathsFigure}{%s}", repo_relative(paths[["main_figure"]])),
  sprintf("\\newcommand{\\GlofasApplicationCurrentForecastWindowFigure}{%s}", repo_relative(paths[["main_figure"]])),
  sprintf("\\newcommand{\\GlofasApplicationCurrentQdesnCheckLoss}{%.4f}", selected$mean_check_loss),
  sprintf("\\newcommand{\\GlofasApplicationCurrentRawCheckLoss}{%.4f}", raw$mean_check_loss),
  sprintf("\\newcommand{\\GlofasApplicationCurrentCheckLossReduction}{%.1f\\%%}", 100 * (raw$mean_check_loss - selected$mean_check_loss) / raw$mean_check_loss),
  sprintf("\\newcommand{\\GlofasApplicationCurrentQdesnIntervalScore}{%.4f}", selected$interval_score),
  sprintf("\\newcommand{\\GlofasApplicationCurrentRawIntervalScore}{%.4f}", raw$interval_score),
  sprintf("\\newcommand{\\GlofasApplicationCurrentIntervalScoreReduction}{%.1f\\%%}", 100 * (raw$interval_score - selected$interval_score) / raw$interval_score),
  sprintf("\\newcommand{\\GlofasApplicationCurrentQdesnAcrps}{%.4f}", selected$crps_grid_log1p),
  sprintf("\\newcommand{\\GlofasApplicationCurrentRawAcrps}{%.4f}", raw$crps_grid_log1p),
  sprintf("\\newcommand{\\GlofasApplicationCurrentAcrpsReduction}{%.1f\\%%}", 100 * selected$crps_reduction_vs_raw),
  sprintf("\\newcommand{\\GlofasApplicationCurrentQdesnCrps}{%.4f}", selected$crps_grid_log1p),
  sprintf("\\newcommand{\\GlofasApplicationCurrentRawCrps}{%.4f}", raw$crps_grid_log1p),
  sprintf("\\newcommand{\\GlofasApplicationCurrentCrpsReduction}{%.1f\\%%}", 100 * selected$crps_reduction_vs_raw),
  sprintf("\\newcommand{\\GlofasApplicationCurrentQdesnMeanCoverage}{%.3f}", selected$coverage90),
  sprintf("\\newcommand{\\GlofasApplicationCurrentRawMeanCoverage}{%.3f}", raw$coverage90),
  "\\newcommand{\\GlofasApplicationCurrentScoredHorizons}{28}",
  "\\newcommand{\\GlofasApplicationCurrentOriginDate}{2022-12-25}",
  sprintf("\\newcommand{\\GlofasApplicationCurrentVbIterations}{%d joint outer iterations after one schedule-qualified state continuation}", al_convergence$outer_iterations),
  "\\newcommand{\\GlofasApplicationCurrentReservoirDepth}{1}",
  "\\newcommand{\\GlofasApplicationCurrentReservoirSize}{3000}",
  "\\newcommand{\\GlofasApplicationCurrentReducerSize}{none}",
  "\\newcommand{\\GlofasApplicationCurrentReservoirMemory}{360}",
  "\\newcommand{\\GlofasApplicationCurrentReservoirWashout}{500}",
  "\\newcommand{\\GlofasApplicationCurrentReservoirAlpha}{0.5}",
  "\\newcommand{\\GlofasApplicationCurrentReservoirRho}{0.9}",
  "\\newcommand{\\GlofasApplicationCurrentReservoirPiW}{0.03}",
  "\\newcommand{\\GlofasApplicationCurrentReservoirPiIn}{1}",
  "\\newcommand{\\GlofasApplicationCurrentReservoirWinScaleGlobal}{0.18}",
  "\\newcommand{\\GlofasApplicationCurrentReservoirWinScaleBias}{0.18}",
  "\\newcommand{\\GlofasApplicationCurrentReservoirSeed}{20260512}",
  "\\newcommand{\\GlofasApplicationCurrentReferenceReservoirDepth}{1}",
  "\\newcommand{\\GlofasApplicationCurrentReferenceReservoirSize}{3000}",
  "\\newcommand{\\GlofasApplicationCurrentReferenceReducerSize}{none}",
  "\\newcommand{\\GlofasApplicationCurrentReferenceReservoirMemory}{360}",
  "\\newcommand{\\GlofasApplicationCurrentReferenceReservoirWashout}{500}",
  "\\newcommand{\\GlofasApplicationCurrentReferenceReservoirAlpha}{0.5}",
  "\\newcommand{\\GlofasApplicationCurrentReferenceReservoirRho}{0.9}",
  "\\newcommand{\\GlofasApplicationCurrentReferenceReservoirPiW}{0.03}",
  "\\newcommand{\\GlofasApplicationCurrentReferenceReservoirPiIn}{1}",
  "\\newcommand{\\GlofasApplicationCurrentReferenceReservoirWinScaleGlobal}{0.18}",
  "\\newcommand{\\GlofasApplicationCurrentReferenceReservoirWinScaleBias}{0.18}",
  "\\newcommand{\\GlofasApplicationCurrentReferenceReservoirSeed}{20260512}",
  "\\newcommand{\\GlofasApplicationCurrentDiscrepancyReservoirDepth}{1}",
  "\\newcommand{\\GlofasApplicationCurrentDiscrepancyReservoirSize}{2500}",
  "\\newcommand{\\GlofasApplicationCurrentDiscrepancyReservoirMemory}{360}",
  "\\newcommand{\\GlofasApplicationCurrentDiscrepancyReservoirWashout}{500}",
  "\\newcommand{\\GlofasApplicationCurrentDiscrepancyReservoirAlpha}{0.8}",
  "\\newcommand{\\GlofasApplicationCurrentDiscrepancyReservoirRho}{0.7}",
  "\\newcommand{\\GlofasApplicationCurrentDiscrepancyReservoirPiW}{0.03}",
  "\\newcommand{\\GlofasApplicationCurrentDiscrepancyReservoirPiIn}{1}",
  "\\newcommand{\\GlofasApplicationCurrentDiscrepancyReservoirWinScaleGlobal}{0.18}",
  "\\newcommand{\\GlofasApplicationCurrentDiscrepancyReservoirWinScaleBias}{0.18}",
  "\\newcommand{\\GlofasApplicationCurrentDiscrepancyReservoirSeed}{20261521}",
  "\\newcommand{\\GlofasApplicationCurrentSharedRhsTau}{1}",
  "\\newcommand{\\GlofasApplicationCurrentDiscrepancyRhsTau}{0.001}",
  "\\newcommand{\\GlofasApplicationCurrentRhsTau}{1}",
  "\\newcommand{\\GlofasApplicationCurrentSpreadCalibrationEnabled}{no}",
  "\\newcommand{\\GlofasApplicationCurrentSpreadCalibrationFactor}{1.0}",
  "\\newcommand{\\GlofasApplicationCurrentSpreadCalibrationAdditiveWidth}{0.0}",
  "\\newcommand{\\GlofasApplicationCurrentSpreadCalibrationCenterQuantile}{0.50}",
  "\\newcommand{\\GlofasApplicationCurrentSpreadCalibrationId}{\\detokenize{none}}",
  "\\newcommand{\\GlofasApplicationCurrentSpreadCalibrationDescription}{\\detokenize{No spread calibration or crossing correction was applied.}}",
  sprintf("\\newcommand{\\GlofasApplicationCurrentObservedHistoryAcrps}{%.4f}", historical_new$crps_grid_log1p[historical_new$window == "all"]),
  sprintf("\\newcommand{\\GlofasApplicationCurrentObservedHistoryCoverage}{%.3f}", historical_new$coverage90[historical_new$window == "all"]),
  "\\newcommand{\\GlofasApplicationCurrentObservedHistoryDates}{12,495}"
)
writeLines(outputs, paths[["outputs_tex"]])

message("Building the article-scale Joint AL path figure...")
history_idx <- which(panel$target_date >= cutoff - 29L & panel$target_date <= cutoff)
history_paths <- do.call(rbind, lapply(seq_along(tau_grid), function(k) data.frame(
  target_date = rep(panel$target_date[history_idx], 2L), quantile_level = tau_grid[[k]],
  target = rep(c("USGS latent path", "GloFAS - USGS discrepancy"), each = length(history_idx)),
  value = c(history_q[history_idx, k], history_d[history_idx, k]),
  segment = "Historical fit", stringsAsFactors = FALSE
)))
joint_prediction <- read.csv(gzfile(prediction_file(continuation_root, al_job)), stringsAsFactors = FALSE)
joint_prediction$target_date <- as.Date(joint_prediction$target_date)
key <- interaction(joint_prediction$target_date, joint_prediction$quantile_level, drop = TRUE)
forecast_paths <- do.call(rbind, lapply(split(joint_prediction, key), function(block) data.frame(
  target_date = unique(block$target_date), quantile_level = unique(block$quantile_level),
  target = c("USGS latent path", "GloFAS - USGS discrepancy"),
  value = c(mean(block$q_y_draw), mean(block$d_g_draw)), segment = "Issued latent path",
  stringsAsFactors = FALSE
)))
plot_paths <- rbind(history_paths, forecast_paths)
ensemble_mean <- aggregate(g_transformed ~ target_date, ensemble, mean)
observed <- rbind(
  data.frame(target_date = panel$target_date[history_idx], target = "USGS latent path", value = panel$y_transformed[history_idx], series = "Observed history"),
  data.frame(target_date = panel$target_date[history_idx], target = "GloFAS - USGS discrepancy", value = panel$g_transformed[history_idx] - panel$y_transformed[history_idx], series = "Observed history"),
  data.frame(target_date = truth_sidecar$target_date, target = "USGS latent path", value = truth_sidecar$y_transformed, series = "Withheld truth (scoring only)"),
  data.frame(target_date = truth_sidecar$target_date, target = "GloFAS - USGS discrepancy", value = ensemble_mean$g_transformed - truth_sidecar$y_transformed, series = "Withheld truth (scoring only)")
)
retrospective <- data.frame(
  target_date = panel$target_date[history_idx], target = "USGS latent path",
  value = panel$g_transformed[history_idx]
)
ensemble$target <- "USGS latent path"
ensemble_mean$target <- "USGS latent path"
tau_colors <- c("0.05"="#3558A6", "0.2"="#4C86B5", "0.35"="#45A69A", "0.5"="#238443", "0.65"="#C49A21", "0.8"="#E06B26", "0.95"="#B83242")
p <- ggplot() +
  geom_line(data = ensemble, aes(target_date, g_transformed, group = member), color = "#9CC7CE", alpha = 0.25, linewidth = 0.23) +
  geom_line(data = ensemble_mean, aes(target_date, g_transformed), color = "#005D6A", linewidth = 0.95) +
  geom_line(data = retrospective, aes(target_date, value), color = "#00839B", linewidth = 0.82) +
  geom_line(data = observed, aes(target_date, value, color = series), linewidth = 0.95) +
  geom_line(data = plot_paths, aes(target_date, value, color = factor(quantile_level), linetype = segment, group = interaction(quantile_level, segment)), linewidth = 0.82) +
  geom_vline(xintercept = cutoff, linetype = "dotted", color = "#5D6870") +
  scale_color_manual(values = c("Observed history"="#181818", "Withheld truth (scoring only)"="#7B2C83", tau_colors), name = NULL) +
  scale_linetype_manual(values = c("Historical fit"="dashed", "Issued latent path"="solid"), name = NULL) +
  scale_x_date(date_breaks = "14 days", date_labels = "%b %d", limits = c(cutoff - 29L, issued_end), expand = expansion(mult = c(0.01, 0.02))) +
  facet_grid(rows = vars(factor(target, levels = c("USGS latent path", "GloFAS - USGS discrepancy"))), scales = "free_y") +
  labs(
    title = "GloFAS Part 4: joint AL Q-DESN latent USGS path",
    subtitle = sprintf("Last 30 historical dates and 28 issued horizons; 51 GloFAS members; log1p scale; 7-q CRPS %.4f", selected$crps_grid_log1p),
    x = "Date", y = "Fitted log1p scale", color = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", size = 15), plot.subtitle = element_text(color = "#4A5560"),
    panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(),
    legend.position = "top", legend.key.width = grid::unit(1.1, "cm"),
    plot.margin = margin(8, 12, 8, 8)
  ) + guides(color = guide_legend(nrow = 2, byrow = TRUE))
ggsave(paths[["main_figure"]], p, width = 11.5, height = 8.2, device = cairo_pdf)

rm(design)
invisible(gc())
manifest_paths <- unname(paths[file.exists(paths)])
publication_manifest <- data.frame(
  relative_path = substring(normalizePath(manifest_paths), nchar(normalizePath(repo_root)) + 2L),
  size_bytes = as.numeric(file.info(manifest_paths)$size),
  sha256 = vapply(manifest_paths, app_sha256_file, character(1L)),
  article_safe = TRUE, stringsAsFactors = FALSE
)
manifest_path <- file.path(table_dir, paste0("glofas_application_part4_publication_manifest__", tag, ".csv"))
write.csv(publication_manifest, manifest_path, row.names = FALSE)
cat(sprintf("PART4_PUBLICATION_PACKAGE_READY\ntag=%s\nmanifest=%s\n", tag, manifest_path))
