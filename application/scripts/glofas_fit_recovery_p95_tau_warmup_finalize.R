#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_fit_recovery.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/glofas_fit_recovery_selection.R"))
source(app_path("application/R/glofas_fit_recovery_scientific_audit.R"))

args <- app_parse_args(list(
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_p95_tau_warmup_20260809",
  cutoff_date = "2022-12-25",
  windows = "all,1000,500,200,100,50"
))
resolve_repo <- function(path, must_work = FALSE) {
  normalizePath(if (grepl("^/", path)) path else app_path(path), mustWork = must_work)
}
provenance_value <- function(table, field) {
  value <- table$value[table$field == field]
  if (length(value) != 1L || !nzchar(value[[1L]])) {
    stop(sprintf("Preparation provenance lacks one '%s' value.", field), call. = FALSE)
  }
  value[[1L]]
}

output_root <- resolve_repo(args$output_root, TRUE)
cutoff_date <- as.Date(args$cutoff_date)
windows <- trimws(strsplit(as.character(args$windows), ",", fixed = TRUE)[[1L]])
windows <- vapply(windows, function(x) if (tolower(x) == "all") NA_integer_ else as.integer(x), integer(1L))
for (dir in c("tables", "figures", "manifest")) app_ensure_dir(file.path(output_root, dir))

runtime <- app_read_csv(file.path(output_root, "runtime_manifest.csv"))
if (nrow(runtime) != 2L || !identical(sort(as.integer(runtime$freeze_tau_warmup_iters)), c(25L, 50L))) {
  stop("The p95 warmup runtime manifest must contain exactly k=25 and k=50.", call. = FALSE)
}
prep_provenance <- app_read_csv(file.path(output_root, "manifest", "preparation_provenance.csv"))
control_fit_path <- resolve_repo(provenance_value(prep_provenance, "control_fit_path"), TRUE)
control_fit_sha256 <- provenance_value(prep_provenance, "control_fit_sha256")
if (!identical(app_sha256_file(control_fit_path), control_fit_sha256)) {
  stop("The immutable p95 control fit changed after preparation.", call. = FALSE)
}
control_history_path <- normalizePath(
  file.path(output_root, "source", "control_post_fit_quantile_history_summary.csv"),
  mustWork = TRUE
)

source_rows <- list(data.frame(
  candidate_id = "fr09_persistence_innovation_control",
  quantile_id = "p95",
  quantile_level = 0.95,
  source_kind = "immutable_effective_k0_control",
  run_id = "glofas_fit_recovery_transition_full7_20260808_fr09_persistence_innovation_p95",
  run_dir = dirname(dirname(control_fit_path)),
  history_path = control_history_path,
  fit_object = control_fit_path,
  fit_object_sha256 = control_fit_sha256,
  candidate_role = "frozen_full7_control",
  stringsAsFactors = FALSE
))
schedule_rows <- list()
rhs_trace_rows <- list()
vb_trace_rows <- list()

for (i in seq_len(nrow(runtime))) {
  candidate_id <- runtime$candidate_id[[i]]
  run_dir <- normalizePath(runtime$run_dir[[i]], mustWork = TRUE)
  if (!file.exists(file.path(run_dir, ".fit_recovery_complete"))) {
    stop(sprintf("Warmup source is incomplete: %s.", candidate_id), call. = FALSE)
  }
  fit_manifest <- app_read_csv(file.path(run_dir, "manifest", "qdesn_discrepancy_fit_manifest.csv"))
  if (nrow(fit_manifest) != 1L || fit_manifest$status[[1L]] != "completed") {
    stop(sprintf("Warmup fit manifest is incomplete: %s.", candidate_id), call. = FALSE)
  }
  fit_path <- resolve_repo(fit_manifest$fit_object[[1L]], TRUE)
  history_path <- normalizePath(
    file.path(run_dir, "tables", "post_fit_quantile_history_summary.csv"),
    mustWork = TRUE
  )
  source_rows[[length(source_rows) + 1L]] <- data.frame(
    candidate_id = candidate_id,
    quantile_id = "p95",
    quantile_level = 0.95,
    source_kind = runtime$source_kind[[i]],
    run_id = runtime$run_id[[i]],
    run_dir = run_dir,
    history_path = history_path,
    fit_object = fit_path,
    fit_object_sha256 = app_sha256_file(fit_path),
    candidate_role = runtime$role[[i]],
    stringsAsFactors = FALSE
  )

  fit <- readRDS(fit_path)
  if (is.list(fit[["fit"]]) && !is.null(fit[["fit"]]$vb_diagnostics)) fit <- fit[["fit"]]
  rhs_diag <- fit$vb_diagnostics$rhs_global_scale %||% NULL
  rhs_trace <- fit$vb_diagnostics$rhs_global_scale_trace %||% NULL
  if (!is.list(rhs_diag) || !is.data.frame(rhs_diag$blocks) ||
      !is.data.frame(rhs_trace) || !nrow(rhs_trace)) {
    stop(sprintf("Warmup diagnostics are missing for %s.", candidate_id), call. = FALSE)
  }
  expected_first <- as.integer(runtime$expected_first_tau_update_iter[[i]])
  expected_minimum <- as.integer(runtime$expected_minimum_convergence_iter[[i]])
  requested_warmup <- as.integer(runtime$freeze_tau_warmup_iters[[i]])
  required_blocks <- c("beta", "alpha")
  if (!identical(sort(as.character(rhs_diag$blocks$block)), sort(required_blocks))) {
    stop(sprintf("Warmup diagnostics do not contain beta and alpha for %s.", candidate_id), call. = FALSE)
  }
  for (block_name in required_blocks) {
    block <- rhs_diag$blocks[rhs_diag$blocks$block == block_name, , drop = FALSE]
    block_trace <- rhs_trace[rhs_trace$block == block_name, , drop = FALSE]
    first_trace_update <- if (any(block_trace$global_update_performed)) {
      min(block_trace$iteration[block_trace$global_update_performed])
    } else {
      NA_integer_
    }
    no_update_during_warmup <- !any(
      block_trace$global_update_performed & block_trace$iteration <= requested_warmup
    )
    schedule_rows[[length(schedule_rows) + 1L]] <- data.frame(
      candidate_id = candidate_id,
      block = block_name,
      requested_warmup_iters = requested_warmup,
      effective_warmup_iters = as.integer(block$freeze_tau_warmup_iters[[1L]]),
      expected_first_tau_update_iter = expected_first,
      recorded_first_tau_update_iter = as.integer(block$first_tau_update_iter[[1L]]),
      trace_first_tau_update_iter = as.integer(first_trace_update),
      expected_minimum_convergence_iter = expected_minimum,
      recorded_minimum_convergence_iter = as.integer(rhs_diag$minimum_convergence_iteration),
      fit_iterations = as.integer(fit$vb_diagnostics$iterations),
      tau_update_count = as.integer(block$tau_update_count[[1L]]),
      no_update_during_warmup = no_update_during_warmup,
      enough_tau_updates = app_as_bool(block$enough_tau_updates[[1L]]),
      coefficient_response_after_release = app_as_bool(block$coefficient_response_after_release[[1L]]),
      block_gate_passed = app_as_bool(block$gate_passed[[1L]]),
      fit_converged = app_as_bool(fit$vb_diagnostics$converged),
      cold_start = !app_as_bool((fit$vb_diagnostics$warm_start %||% list())$used %||% FALSE),
      finite_trace = all(is.finite(block_trace$effective_tau)) &&
        all(is.finite(block_trace$coefficient_l2)) &&
        all(is.finite(block_trace$local_scale_median)),
      stringsAsFactors = FALSE
    )
  }
  rhs_trace$candidate_id <- candidate_id
  rhs_trace$release_iteration <- expected_first
  rhs_trace_rows[[length(rhs_trace_rows) + 1L]] <- rhs_trace
  vb_trace_rows[[length(vb_trace_rows) + 1L]] <- rbind(
    data.frame(
      candidate_id = candidate_id,
      iteration = seq_along(fit$vb_diagnostics$elbo_trace),
      trace = "objective",
      value = as.numeric(fit$vb_diagnostics$elbo_trace),
      release_iteration = expected_first,
      stringsAsFactors = FALSE
    ),
    data.frame(
      candidate_id = candidate_id,
      iteration = seq_along(fit$vb_diagnostics$parameter_change_trace),
      trace = "max_parameter_change",
      value = as.numeric(fit$vb_diagnostics$parameter_change_trace),
      release_iteration = expected_first,
      stringsAsFactors = FALSE
    )
  )
}

schedule_audit <- app_bind_rows_fill(schedule_rows)
schedule_audit$gate_pass <- with(schedule_audit,
  requested_warmup_iters == effective_warmup_iters &
    expected_first_tau_update_iter == recorded_first_tau_update_iter &
    expected_first_tau_update_iter == trace_first_tau_update_iter &
    expected_minimum_convergence_iter == recorded_minimum_convergence_iter &
    fit_iterations >= expected_minimum_convergence_iter &
    tau_update_count >= 1L & no_update_during_warmup & enough_tau_updates &
    coefficient_response_after_release & block_gate_passed & fit_converged &
    cold_start & finite_trace)
app_write_csv(schedule_audit, file.path(output_root, "tables", "p95_rhs_warmup_schedule_audit.csv"))
if (!all(schedule_audit$gate_pass)) {
  stop("At least one p95 warmup candidate failed the requested/effective schedule gate.", call. = FALSE)
}
rhs_traces <- app_bind_rows_fill(rhs_trace_rows)
vb_traces <- app_bind_rows_fill(vb_trace_rows)
app_write_csv(rhs_traces, file.path(output_root, "tables", "p95_rhs_global_scale_traces.csv"))
app_write_csv(vb_traces, file.path(output_root, "tables", "p95_vb_objective_parameter_traces.csv"))

source_manifest <- app_bind_rows_fill(source_rows)
source_manifest <- app_glofas_selection_validate_source_manifest(source_manifest, require_complete = TRUE)
app_write_csv(source_manifest, file.path(output_root, "manifest", "p95_source_manifest.csv"))
fit_gate <- app_glofas_selection_fit_gate(source_manifest)
app_write_csv(fit_gate, file.path(output_root, "tables", "p95_fit_gate.csv"))
if (!all(fit_gate$gate_pass)) stop("At least one p95 warmup fit failed its technical fit gate.", call. = FALSE)

raw_histories <- lapply(seq_len(nrow(source_manifest)), function(i) {
  x <- app_read_csv(source_manifest$history_path[[i]])
  x$candidate_id <- source_manifest$candidate_id[[i]]
  x
})
names(raw_histories) <- source_manifest$candidate_id
histories <- lapply(seq_along(raw_histories), function(i) {
  app_glofas_fit_recovery_history(raw_histories[[i]], names(raw_histories)[[i]], cutoff_date)
})
names(histories) <- names(raw_histories)
histories <- app_glofas_fit_recovery_align_histories(histories)
common_dates <- histories[[1L]]$target_date
if (length(common_dates) < 1000L) stop("P95 warmup candidates have insufficient common history.", call. = FALSE)

metric_rows <- list()
component_rows <- list()
detail_rows <- list()
for (candidate_id in names(histories)) {
  history <- histories[[candidate_id]]
  component <- app_glofas_scientific_component_audit(raw_histories[[candidate_id]], candidate_id)
  component_rows[[length(component_rows) + 1L]] <- component$summary
  detail_rows[[length(detail_rows) + 1L]] <- component$detail
  for (window in windows) {
    selected <- if (is.finite(window)) tail(seq_len(nrow(history)), min(as.integer(window), nrow(history))) else seq_len(nrow(history))
    block <- history[selected, , drop = FALSE]
    metric_rows[[length(metric_rows) + 1L]] <- data.frame(
      candidate_id = candidate_id,
      window = app_glofas_fit_recovery_window_label(window),
      n_dates = nrow(block),
      date_min = as.character(min(block$target_date)),
      date_max = as.character(max(block$target_date)),
      log1p_check_loss_mean = app_glofas_fit_recovery_check_loss(block$y_log1p, block$qhat_log1p, 0.95),
      original_check_loss_mean = app_glofas_fit_recovery_check_loss(block$y_original, block$qhat_original, 0.95),
      log1p_mae = mean(abs(block$qhat_log1p - block$y_log1p)),
      original_mae = mean(abs(block$qhat_original - block$y_original)),
      observed_max = max(block$y_original),
      fitted_max = max(block$qhat_original),
      fitted_max_to_observed_max_ratio = max(block$qhat_original) / max(block$y_original),
      n_above_20x_observed_max = sum(block$qhat_original > 20 * max(block$y_original)),
      stringsAsFactors = FALSE
    )
  }
}
metrics <- app_bind_rows_fill(metric_rows)
components <- app_bind_rows_fill(component_rows)
details <- app_bind_rows_fill(detail_rows)
all_metrics <- metrics[metrics$window == "all", , drop = FALSE]
candidate_gate <- merge(
  all_metrics,
  components[, c(
    "candidate_id", "prediction_identity_max_abs_error",
    "fitted_abs_discrepancy_to_history_q995_ratio"
  ), drop = FALSE],
  by = "candidate_id", all = TRUE
)
candidate_gate <- merge(
  candidate_gate,
  aggregate(gate_pass ~ candidate_id, fit_gate, all),
  by = "candidate_id", all = TRUE
)
schedule_by_candidate <- aggregate(gate_pass ~ candidate_id, schedule_audit, all)
names(schedule_by_candidate)[[2L]] <- "warmup_schedule_gate_pass"
candidate_gate <- merge(candidate_gate, schedule_by_candidate, by = "candidate_id", all.x = TRUE)
candidate_gate$warmup_schedule_gate_pass[is.na(candidate_gate$warmup_schedule_gate_pass)] <- TRUE
candidate_gate$finite_score_gate_pass <- with(candidate_gate,
  is.finite(log1p_check_loss_mean) & is.finite(original_check_loss_mean))
candidate_gate$identity_gate_pass <- candidate_gate$prediction_identity_max_abs_error <= 1.0e-8
candidate_gate$tail_scale_gate_pass <- with(candidate_gate,
  fitted_max_to_observed_max_ratio <= 20 & n_above_20x_observed_max == 0L)
candidate_gate$discrepancy_support_gate_pass <-
  candidate_gate$fitted_abs_discrepancy_to_history_q995_ratio <= 1.5
candidate_gate$scientific_gate_pass <- with(candidate_gate,
  app_as_bool_vec(gate_pass) & app_as_bool_vec(warmup_schedule_gate_pass) &
    finite_score_gate_pass & identity_gate_pass & tail_scale_gate_pass &
    discrepancy_support_gate_pass)
candidate_gate$is_new_candidate <- candidate_gate$candidate_id != "fr09_persistence_innovation_control"
candidate_gate$eligible_for_human_review <- candidate_gate$scientific_gate_pass & candidate_gate$is_new_candidate
candidate_gate$auto_launch_full7 <- FALSE
candidate_gate$auto_promote <- FALSE
warmup_order <- setNames(runtime$freeze_tau_warmup_iters, runtime$candidate_id)
candidate_gate$warmup_iters <- unname(warmup_order[candidate_gate$candidate_id])
candidate_gate$warmup_iters[is.na(candidate_gate$warmup_iters)] <- 0L
ranking <- candidate_gate[order(
  !candidate_gate$eligible_for_human_review,
  candidate_gate$original_check_loss_mean,
  candidate_gate$log1p_check_loss_mean,
  candidate_gate$warmup_iters
), , drop = FALSE]
ranking$rank <- seq_len(nrow(ranking))
ranking$decision <- ifelse(
  ranking$eligible_for_human_review,
  "eligible_for_human_review_then_blocked_pseudo_cutoff_replay",
  "blocked_scientific_gate"
)
ranking <- ranking[, c("rank", setdiff(names(ranking), "rank")), drop = FALSE]

app_write_csv(metrics, file.path(output_root, "tables", "p95_dual_scale_scores.csv"))
app_write_csv(components, file.path(output_root, "tables", "p95_component_summary.csv"))
app_write_csv(details, file.path(output_root, "tables", "p95_component_detail.csv"))
app_write_csv(candidate_gate, file.path(output_root, "tables", "p95_scientific_gate.csv"))
app_write_csv(ranking, file.path(output_root, "tables", "p95_tau_warmup_ranking.csv"))
app_write_csv(data.frame(
  n_common_dates = length(common_dates),
  date_min = as.character(min(common_dates)),
  date_max = as.character(max(common_dates)),
  stringsAsFactors = FALSE
), file.path(output_root, "tables", "p95_common_date_audit.csv"))

if (!requireNamespace("ggplot2", quietly = TRUE) || !isTRUE(capabilities("cairo"))) {
  stop("P95 warmup finalization requires ggplot2 and Cairo graphics.", call. = FALSE)
}
theme_warmup <- ggplot2::theme_bw(base_size = 9) + ggplot2::theme(
  panel.grid.minor = ggplot2::element_blank(),
  legend.position = "bottom",
  strip.background = ggplot2::element_rect(fill = "gray94", color = "gray75")
)
last200 <- app_bind_rows_fill(lapply(histories, function(x) tail(x, 200L)))
last200_long <- rbind(
  data.frame(candidate_id = last200$candidate_id, target_date = last200$target_date,
             path = "observed", value = last200$y_log1p),
  data.frame(candidate_id = last200$candidate_id, target_date = last200$target_date,
             path = "fitted_p95", value = last200$qhat_log1p)
)
fit_plot <- ggplot2::ggplot(last200_long, ggplot2::aes(target_date, value, color = path)) +
  ggplot2::geom_line(linewidth = 0.42) +
  ggplot2::facet_wrap(~ candidate_id, ncol = 1L) +
  ggplot2::scale_color_manual(values = c(observed = "gray45", fitted_p95 = "#A63D40")) +
  ggplot2::labs(
    title = "P95 global-scale warmup fit over the final 200 observed dates",
    subtitle = "Cold-start comparison; the held-out forecast window is excluded from selection",
    x = NULL, y = "log(1 + streamflow)", color = NULL
  ) + theme_warmup
tail_plot <- ggplot2::ggplot(details, ggplot2::aes(target_date, q_y_original, color = candidate_id)) +
  ggplot2::geom_point(alpha = 0.38, size = 0.65) +
  ggplot2::scale_y_log10() +
  ggplot2::facet_wrap(~ candidate_id, ncol = 1L) +
  ggplot2::labs(
    title = "P95 fitted scale across the observed history",
    subtitle = "Original streamflow scale shown logarithmically",
    x = NULL, y = "Fitted p95 streamflow", color = NULL
  ) + theme_warmup + ggplot2::theme(legend.position = "none")
release_data <- unique(rhs_traces[, c("candidate_id", "release_iteration"), drop = FALSE])
tau_plot <- ggplot2::ggplot(rhs_traces, ggplot2::aes(iteration, effective_tau, color = block)) +
  ggplot2::geom_line(linewidth = 0.48) +
  ggplot2::geom_vline(
    data = release_data,
    ggplot2::aes(xintercept = release_iteration),
    inherit.aes = FALSE,
    linetype = "dashed", color = "gray35", linewidth = 0.35
  ) +
  ggplot2::facet_wrap(~ candidate_id, ncol = 1L, scales = "free_y") +
  ggplot2::labs(
    title = "RHS global-scale trajectories",
    subtitle = "Dashed line marks the first global tau/xi update",
    x = "VB iteration", y = "Effective global scale", color = "Readout block"
  ) + theme_warmup
coef_plot <- ggplot2::ggplot(rhs_traces, ggplot2::aes(iteration, coefficient_l2, color = block)) +
  ggplot2::geom_line(linewidth = 0.48) +
  ggplot2::geom_vline(
    data = release_data,
    ggplot2::aes(xintercept = release_iteration),
    inherit.aes = FALSE,
    linetype = "dashed", color = "gray35", linewidth = 0.35
  ) +
  ggplot2::facet_wrap(~ candidate_id, ncol = 1L, scales = "free_y") +
  ggplot2::labs(
    title = "Readout coefficient norms during global-scale warmup",
    subtitle = "Coefficients update throughout the warmup; only global tau/xi is frozen",
    x = "VB iteration", y = "Coefficient L2 norm", color = "Readout block"
  ) + theme_warmup
vb_plot <- ggplot2::ggplot(vb_traces, ggplot2::aes(iteration, value)) +
  ggplot2::geom_line(linewidth = 0.42, color = "#315C7C") +
  ggplot2::geom_vline(
    data = unique(vb_traces[, c("candidate_id", "trace", "release_iteration"), drop = FALSE]),
    ggplot2::aes(xintercept = release_iteration),
    inherit.aes = FALSE,
    linetype = "dashed", color = "gray35", linewidth = 0.35
  ) +
  ggplot2::facet_grid(trace ~ candidate_id, scales = "free_y") +
  ggplot2::labs(
    title = "P95 VB objective and parameter-change traces",
    subtitle = "Dashed line marks global-scale release",
    x = "VB iteration", y = NULL
  ) + theme_warmup
for (spec in list(
  list(name = "p95_tau_warmup_last200_fit", plot = fit_plot, width = 9.4, height = 8.4),
  list(name = "p95_tau_warmup_full_history_scale", plot = tail_plot, width = 9.4, height = 8.4),
  list(name = "p95_tau_warmup_global_scale_traces", plot = tau_plot, width = 9.4, height = 6.8),
  list(name = "p95_tau_warmup_coefficient_norm_traces", plot = coef_plot, width = 9.4, height = 6.8),
  list(name = "p95_tau_warmup_vb_traces", plot = vb_plot, width = 10.2, height = 6.8)
)) {
  app_glofas_selection_save_plot(spec$plot, file.path(output_root, "figures", paste0(spec$name, ".pdf")), spec$width, spec$height)
  app_glofas_selection_save_plot(spec$plot, file.path(output_root, "figures", paste0(spec$name, ".png")), spec$width, spec$height)
}

eligible <- ranking[ranking$eligible_for_human_review, , drop = FALSE]
decision_path <- if (nrow(eligible)) {
  file.path(output_root, "P95_TAU_WARMUP_REVIEW_READY.txt")
} else {
  file.path(output_root, "P95_TAU_WARMUP_BLOCKED.txt")
}
writeLines(c(
  if (nrow(eligible)) sprintf("Top candidate: %s", eligible$candidate_id[[1L]]) else
    "Neither p95 warmup candidate passed every scientific gate.",
  "If both candidates pass, lower observed-history p95 check loss wins; ties prefer k=25.",
  "The next permitted action is human review followed by blocked pseudo-cutoff replay.",
  "No full-seven launch, promotion, cleanup, or article update is authorized automatically."
), decision_path)
final_provenance <- data.frame(
  field = c(
    "finalized_at", "repo_head", "finalizer_sha256", "source_manifest_sha256",
    "schedule_audit_sha256", "ranking_sha256", "selection_scope",
    "forecast_window_used", "automatic_full7", "automatic_promotion"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)[[1L]],
    app_sha256_file(app_path("application/scripts/glofas_fit_recovery_p95_tau_warmup_finalize.R")),
    app_sha256_file(file.path(output_root, "manifest", "p95_source_manifest.csv")),
    app_sha256_file(file.path(output_root, "tables", "p95_rhs_warmup_schedule_audit.csv")),
    app_sha256_file(file.path(output_root, "tables", "p95_tau_warmup_ranking.csv")),
    "observed_history_p95_only", "false", "false", "false"
  ),
  stringsAsFactors = FALSE
)
app_write_csv(final_provenance, file.path(output_root, "manifest", "finalization_provenance.csv"))
artifact_paths <- c(
  list.files(file.path(output_root, "tables"), full.names = TRUE),
  list.files(file.path(output_root, "figures"), full.names = TRUE),
  list.files(file.path(output_root, "manifest"), full.names = TRUE),
  decision_path
)
artifact_paths <- artifact_paths[basename(artifact_paths) != "artifact_manifest.csv"]
app_write_csv(data.frame(
  path = normalizePath(artifact_paths, mustWork = TRUE),
  size_bytes = as.numeric(file.info(artifact_paths)$size),
  sha256 = vapply(artifact_paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
), file.path(output_root, "manifest", "artifact_manifest.csv"))
cat(normalizePath(decision_path, mustWork = TRUE), "\n")
