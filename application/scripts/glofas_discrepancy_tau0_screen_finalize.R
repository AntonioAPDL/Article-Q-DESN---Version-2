#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_discrepancy_tau0_screen.R"))

args <- app_parse_args(list(
  manifest = "local_trackers/runtime_configs/glofas_discrepancy_tau0_relax_p50_20260831/candidate_registry.csv",
  output_root = "local_trackers/runtime_configs/glofas_discrepancy_tau0_relax_p50_20260831",
  source_root = "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829"
))
resolve_path <- function(path, must_work = TRUE) {
  normalizePath(if (grepl("^/", path)) path else file.path(repo_root, path), mustWork = must_work)
}
one_file <- function(path, pattern, label) {
  files <- list.files(path, pattern = pattern, full.names = TRUE)
  if (length(files) != 1L) {
    stop(sprintf("Expected one %s in %s; found %d.", label, path, length(files)), call. = FALSE)
  }
  normalizePath(files, mustWork = TRUE)
}
read_required <- function(path, required, label) {
  if (!file.exists(path)) stop(sprintf("Missing %s: %s.", label, path), call. = FALSE)
  out <- app_read_csv(path)
  missing <- setdiff(required, names(out))
  if (!nrow(out) || length(missing)) {
    stop(sprintf("%s is empty or missing: %s.", label, paste(missing, collapse = ", ")), call. = FALSE)
  }
  out
}
scalar <- function(x, name) {
  value <- as.numeric(x[[name]][[1L]])
  if (length(value) != 1L || !is.finite(value)) stop(sprintf("Non-finite %s.", name), call. = FALSE)
  value
}
history_wide <- function(scores) {
  wanted <- c("all", "last1000", "last200", "last50")
  values <- setNames(rep(NA_real_, length(wanted)), wanted)
  for (window in wanted) {
    hit <- scores[as.character(scores$window) == window, , drop = FALSE]
    if (nrow(hit) != 1L) stop(sprintf("Expected one observed-fit score for %s.", window), call. = FALSE)
    values[[window]] <- as.numeric(hit$log1p_mae[[1L]])
  }
  values
}

manifest_path <- resolve_path(as.character(args$manifest), must_work = TRUE)
output_root <- resolve_path(as.character(args$output_root), must_work = TRUE)
source_root <- resolve_path(as.character(args$source_root), must_work = TRUE)
manifest <- app_read_csv(manifest_path)
if (nrow(manifest) != 5L) stop("Finalization requires the frozen five-fit manifest.", call. = FALSE)

completion <- data.frame(
  candidate_id = manifest$candidate_id,
  completion_marker = file.exists(file.path(manifest$run_dir, ".fit_recovery_complete")),
  failed_marker = file.exists(file.path(manifest$run_dir, ".fit_recovery_failed")),
  stringsAsFactors = FALSE
)
app_ensure_dir(file.path(output_root, "tables"))
app_write_csv(completion, file.path(output_root, "tables", "completion_audit.csv"))
if (!all(completion$completion_marker) || any(completion$failed_marker)) {
  stop(sprintf(
    "Campaign is not cleanly complete: %d/%d complete and %d failed markers.",
    sum(completion$completion_marker), nrow(completion), sum(completion$failed_marker)
  ), call. = FALSE)
}

source_runtime <- app_read_csv(file.path(source_root, "runtime_manifest.csv"))
if (nrow(source_runtime) != 1L) stop("Source runtime manifest must contain one row.", call. = FALSE)
source_run_dir <- normalizePath(source_runtime$run_dir[[1L]], mustWork = TRUE)
source_candidate_id <- as.character(source_runtime$candidate_id[[1L]])
source_row <- data.frame(
  candidate_id = source_candidate_id,
  candidate_role = "existing_tau0_0p1_evidence",
  discrepancy_tau0 = 0.1,
  reference_tau0 = 0.1,
  warm_start_enabled = FALSE,
  run_dir = source_run_dir,
  score_path = one_file(file.path(source_root, "scores"), "_observed_fit_scores[.]csv$", "source observed-fit score"),
  stringsAsFactors = FALSE
)
candidate_rows <- manifest[, c(
  "candidate_id", "candidate_role", "discrepancy_tau0", "reference_tau0",
  "warm_start_enabled", "run_dir"
), drop = FALSE]
candidate_rows$score_path <- file.path(
  output_root, "scores", paste0(candidate_rows$candidate_id, "_observed_fit_scores.csv")
)
evidence <- rbind(source_row, candidate_rows)

all_forecast <- vector("list", nrow(evidence))
all_history <- vector("list", nrow(evidence))
all_paths <- vector("list", nrow(evidence))
metric_rows <- vector("list", nrow(evidence))
for (i in seq_len(nrow(evidence))) {
  candidate_id <- as.character(evidence$candidate_id[[i]])
  run_dir <- normalizePath(evidence$run_dir[[i]], mustWork = TRUE)
  table_dir <- file.path(run_dir, "tables")
  forecast_path <- file.path(table_dir, "post_fit_forecast_window_summary.csv")
  history_path <- file.path(table_dir, "post_fit_discrepancy_history_summary.csv")
  diagnostic_path <- file.path(table_dir, "qdesn_discrepancy_fit_diagnostics.csv")
  fit_status_path <- file.path(table_dir, "fit_status.csv")
  forecast <- read_required(
    forecast_path,
    c("target_date", "horizon", "raw_glofas_quantile", "y_reference", "q_y_median", "d_g_median"),
    paste(candidate_id, "forecast summary")
  )
  history <- read_required(
    history_path,
    c("target_date", "observed_discrepancy", "d_g_median"),
    paste(candidate_id, "discrepancy history")
  )
  observed_scores <- read_required(
    evidence$score_path[[i]], c("window", "log1p_mae"), paste(candidate_id, "observed-fit scores")
  )
  diagnostic <- read_required(
    diagnostic_path,
    c(
      "model_family", "finite_theta", "finite_sigma", "vb_converged", "vb_iterations",
      "alpha_norm_mean", "rhs_alpha_effective_tau", "vb_warm_start_enabled",
      "vb_warm_start_used", "vb_warm_start_compatibility_class"
    ),
    paste(candidate_id, "fit diagnostics")
  )
  diagnostic <- diagnostic[diagnostic$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  fit_status <- read_required(
    fit_status_path, c("model_family", "status", "runtime_seconds"), paste(candidate_id, "fit status")
  )
  fit_status <- fit_status[fit_status$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  if (nrow(diagnostic) != 1L || nrow(fit_status) != 1L) {
    stop(sprintf("%s does not have one Q-DESN diagnostic/status row.", candidate_id), call. = FALSE)
  }
  history$target_date <- as.Date(history$target_date)
  history <- history[order(history$target_date), , drop = FALSE]
  last_discrepancy <- as.numeric(tail(history$observed_discrepancy, 1L))
  forecast_metrics <- app_glofas_discrepancy_tau0_forecast_metrics(forecast, last_discrepancy)
  observed <- history_wide(observed_scores)
  requested_warm <- app_as_bool(evidence$warm_start_enabled[[i]])
  warm_semantics_pass <- if (requested_warm) {
    app_as_bool(diagnostic$vb_warm_start_enabled[[1L]]) &&
      app_as_bool(diagnostic$vb_warm_start_used[[1L]]) &&
      identical(as.character(diagnostic$vb_warm_start_compatibility_class[[1L]]), "exact_design")
  } else {
    !app_as_bool(diagnostic$vb_warm_start_used[[1L]])
  }
  technical_gate <- identical(as.character(fit_status$status[[1L]]), "completed") &&
    app_as_bool(diagnostic$finite_theta[[1L]]) && app_as_bool(diagnostic$finite_sigma[[1L]]) &&
    app_as_bool(diagnostic$vb_converged[[1L]]) && warm_semantics_pass
  metric_rows[[i]] <- cbind(
    data.frame(
      candidate_id = candidate_id,
      candidate_role = as.character(evidence$candidate_role[[i]]),
      discrepancy_tau0 = as.numeric(evidence$discrepancy_tau0[[i]]),
      reference_tau0 = as.numeric(evidence$reference_tau0[[i]]),
      warm_start_requested = requested_warm,
      warm_start_used = app_as_bool(diagnostic$vb_warm_start_used[[1L]]),
      warm_start_compatibility_class = as.character(diagnostic$vb_warm_start_compatibility_class[[1L]]),
      warm_start_semantics_pass = warm_semantics_pass,
      fit_status = as.character(fit_status$status[[1L]]),
      technical_gate_pass = technical_gate,
      vb_converged = app_as_bool(diagnostic$vb_converged[[1L]]),
      vb_iterations = as.integer(diagnostic$vb_iterations[[1L]]),
      fit_runtime_seconds = as.numeric(fit_status$runtime_seconds[[1L]]),
      discrepancy_coefficient_norm = as.numeric(diagnostic$alpha_norm_mean[[1L]]),
      discrepancy_effective_tau = as.numeric(diagnostic$rhs_alpha_effective_tau[[1L]]),
      observed_log1p_mae_all = observed[["all"]],
      observed_log1p_mae_last1000 = observed[["last1000"]],
      observed_log1p_mae_last200 = observed[["last200"]],
      observed_log1p_mae_last50 = observed[["last50"]],
      stringsAsFactors = FALSE
    ),
    forecast_metrics
  )
  forecast$candidate_id <- candidate_id
  forecast$discrepancy_tau0 <- as.numeric(evidence$discrepancy_tau0[[i]])
  history$candidate_id <- candidate_id
  history$discrepancy_tau0 <- as.numeric(evidence$discrepancy_tau0[[i]])
  all_forecast[[i]] <- forecast
  all_history[[i]] <- history
  all_paths[[i]] <- data.frame(
    candidate_id = candidate_id,
    role = c("forecast", "history", "observed_scores", "diagnostic", "fit_status"),
    path = c(forecast_path, history_path, evidence$score_path[[i]], diagnostic_path, fit_status_path),
    stringsAsFactors = FALSE
  )
}
metrics <- do.call(rbind, metric_rows)
forecast_paths <- do.call(rbind, all_forecast)
history_paths <- do.call(rbind, all_history)
evidence_paths <- do.call(rbind, all_paths)

warm_id <- manifest$candidate_id[
  as.numeric(manifest$discrepancy_tau0) == 1 & app_as_bool_vec(manifest$warm_start_enabled)
]
cold_id <- manifest$candidate_id[
  as.numeric(manifest$discrepancy_tau0) == 1 & !app_as_bool_vec(manifest$warm_start_enabled)
]
if (length(warm_id) != 1L || length(cold_id) != 1L) stop("The tau0=1 canary pair is incomplete.", call. = FALSE)
canary <- app_glofas_discrepancy_tau0_canary(
  all_forecast[[match(warm_id, evidence$candidate_id)]],
  all_forecast[[match(cold_id, evidence$candidate_id)]],
  app_read_csv(evidence$score_path[match(warm_id, evidence$candidate_id)]),
  app_read_csv(evidence$score_path[match(cold_id, evidence$candidate_id)])
)
canary$warm_candidate_id <- warm_id
canary$cold_candidate_id <- cold_id

ranking_input <- metrics[metrics$candidate_role != "cold_canary", , drop = FALSE]
ranking <- app_glofas_discrepancy_tau0_rank(ranking_input)
if (!isTRUE(canary$equivalent[[1L]])) {
  ranking$eligible_for_cold_confirmation <- FALSE
  ranking$decision <- "blocked_warm_cold_non_equivalence"
}
eligible <- ranking[ranking$eligible_for_cold_confirmation, , drop = FALSE]
best <- ranking[1L, , drop = FALSE]
selection <- data.frame(
  selected_candidate_id = as.character(best$candidate_id[[1L]]),
  selected_discrepancy_tau0 = as.numeric(best$discrepancy_tau0[[1L]]),
  selected_forecast_check_loss = as.numeric(best$forecast_check_loss[[1L]]),
  selected_discrepancy_mae = as.numeric(best$discrepancy_mae[[1L]]),
  warm_cold_equivalence_passed = isTRUE(canary$equivalent[[1L]]),
  eligible_candidate_count = nrow(eligible),
  decision = if (!isTRUE(canary$equivalent[[1L]])) {
    "stop_warm_start_not_numerically_equivalent"
  } else if (nrow(eligible)) {
    "review_eligible_candidate_then_run_prospective_cold_confirmation"
  } else {
    "retain_fr09_no_candidate_passed_forecast_and_history_gates"
  },
  automatic_promotion = FALSE,
  automatic_full7 = FALSE,
  finalized_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  stringsAsFactors = FALSE
)

table_paths <- c(
  candidate_metrics = file.path(output_root, "tables", "candidate_metrics.csv"),
  candidate_ranking = file.path(output_root, "tables", "candidate_ranking.csv"),
  warm_cold_canary = file.path(output_root, "tables", "warm_cold_canary.csv"),
  history_guardrails = file.path(output_root, "tables", "history_guardrails.csv"),
  selection_decision = file.path(output_root, "tables", "selection_decision.csv"),
  evidence_paths = file.path(output_root, "tables", "evidence_paths.csv")
)
app_write_csv(metrics, table_paths[["candidate_metrics"]])
app_write_csv(ranking, table_paths[["candidate_ranking"]])
app_write_csv(canary, table_paths[["warm_cold_canary"]])
app_write_csv(app_glofas_discrepancy_tau0_guardrails(), table_paths[["history_guardrails"]])
app_write_csv(selection, table_paths[["selection_decision"]])
app_write_csv(evidence_paths, table_paths[["evidence_paths"]])

figure_root <- file.path(output_root, "figures")
app_ensure_dir(figure_root)
plot_rows <- metrics[metrics$candidate_role != "cold_canary", , drop = FALSE]
plot_rows <- plot_rows[order(plot_rows$discrepancy_tau0), , drop = FALSE]
score_figure <- file.path(figure_root, "discrepancy_tau0_score_tradeoff.pdf")
grDevices::pdf(score_figure, width = 9, height = 7, onefile = TRUE)
graphics::par(mfrow = c(2, 2), mar = c(4.2, 4.4, 2.4, 1.0))
graphics::plot(plot_rows$discrepancy_tau0, plot_rows$forecast_check_loss, log = "x", type = "b", pch = 19,
  xlab = "Discrepancy RHS tau0", ylab = "Forecast p50 check loss", main = "Forecast score")
graphics::abline(h = unique(plot_rows$persistence_forecast_check_loss)[1L], lty = 2, col = "grey40")
graphics::plot(plot_rows$discrepancy_tau0, plot_rows$discrepancy_mae, log = "x", type = "b", pch = 19,
  xlab = "Discrepancy RHS tau0", ylab = "Forecast discrepancy MAE", main = "Discrepancy forecast")
graphics::abline(h = unique(plot_rows$persistence_discrepancy_mae)[1L], lty = 2, col = "grey40")
graphics::plot(plot_rows$discrepancy_tau0, plot_rows$observed_log1p_mae_all, log = "x", type = "b", pch = 19,
  xlab = "Discrepancy RHS tau0", ylab = "Historical log1p MAE", main = "All-history guardrail")
graphics::abline(h = app_glofas_discrepancy_tau0_guardrails()$maximum_allowed_log1p_mae[1L], lty = 2, col = "firebrick")
graphics::plot(plot_rows$discrepancy_tau0, plot_rows$discrepancy_coefficient_norm, log = "xy", type = "b", pch = 19,
  xlab = "Discrepancy RHS tau0", ylab = "Discrepancy coefficient L2 norm", main = "Readout signal")
grDevices::dev.off()

path_figure <- file.path(figure_root, "forecast_discrepancy_paths_by_tau0.pdf")
forecast_dates <- sort(unique(as.Date(forecast_paths$target_date)))
observed_path <- forecast_paths[forecast_paths$candidate_id == evidence$candidate_id[[1L]], , drop = FALSE]
observed_path <- observed_path[order(as.Date(observed_path$target_date)), , drop = FALSE]
range_y <- range(c(forecast_paths$d_g_median, forecast_paths$raw_glofas_quantile - forecast_paths$y_reference), finite = TRUE)
grDevices::pdf(path_figure, width = 11, height = 6)
graphics::plot(as.Date(observed_path$target_date), observed_path$raw_glofas_quantile - observed_path$y_reference,
  type = "o", pch = 16, lwd = 2, xlab = "Target date", ylab = "GloFAS - USGS discrepancy (log1p)",
  ylim = range_y, main = "Forecast discrepancy paths under larger RHS tau0")
colors <- grDevices::hcl.colors(nrow(plot_rows), "Dark 3")
for (i in seq_len(nrow(plot_rows))) {
  path <- forecast_paths[forecast_paths$candidate_id == plot_rows$candidate_id[[i]], , drop = FALSE]
  path <- path[order(as.Date(path$target_date)), , drop = FALSE]
  graphics::lines(as.Date(path$target_date), path$d_g_median, col = colors[[i]], lwd = 2)
}
graphics::legend("topleft", legend = c("Observed future discrepancy", paste0("tau0=", plot_rows$discrepancy_tau0)),
  col = c("black", colors), lty = 1, pch = c(16, rep(NA_integer_, length(colors))), bty = "n", cex = 0.82)
grDevices::dev.off()

history_figure <- file.path(figure_root, "recent_discrepancy_fit_by_tau0.pdf")
recent_dates <- sort(unique(as.Date(history_paths$target_date)))
recent_dates <- tail(recent_dates, 200L)
recent <- history_paths[as.Date(history_paths$target_date) %in% recent_dates, , drop = FALSE]
observed_recent <- recent[recent$candidate_id == evidence$candidate_id[[1L]], , drop = FALSE]
observed_recent <- observed_recent[order(as.Date(observed_recent$target_date)), , drop = FALSE]
range_history <- range(c(recent$observed_discrepancy, recent$d_g_median), finite = TRUE)
grDevices::pdf(history_figure, width = 11, height = 6)
graphics::plot(as.Date(observed_recent$target_date), observed_recent$observed_discrepancy,
  type = "l", col = "black", lwd = 2, xlab = "Date", ylab = "GloFAS - USGS discrepancy (log1p)",
  ylim = range_history, main = "Last 200 observed discrepancy fits")
for (i in seq_len(nrow(plot_rows))) {
  path <- recent[recent$candidate_id == plot_rows$candidate_id[[i]], , drop = FALSE]
  path <- path[order(as.Date(path$target_date)), , drop = FALSE]
  graphics::lines(as.Date(path$target_date), path$d_g_median, col = colors[[i]], lwd = 1.5)
}
graphics::legend("topleft", legend = c("Observed discrepancy", paste0("tau0=", plot_rows$discrepancy_tau0)),
  col = c("black", colors), lty = 1, bty = "n", cex = 0.82)
grDevices::dev.off()

artifact_paths <- c(unname(table_paths), score_figure, path_figure, history_figure, manifest_path)
artifact_manifest <- data.frame(
  path = normalizePath(artifact_paths, mustWork = TRUE),
  size_bytes = as.numeric(file.info(artifact_paths)$size),
  sha256 = vapply(artifact_paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
app_write_csv(artifact_manifest, file.path(output_root, "tables", "finalization_artifact_manifest.csv"))
writeLines(format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), file.path(output_root, ".finalized"))
cat(normalizePath(table_paths[["selection_decision"]], mustWork = TRUE), "\n")
