#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/artifact_hygiene.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/glofas_fit_recovery.R"))
source(app_path("application/R/glofas_constrained_median_screening.R"))

args <- app_parse_args(list(
  output_root = "",
  audit_root = "",
  baseline_contract = "application/config/glofas_constrained_median_baseline_fr09.yaml",
  top_n = 2L,
  block_length = 5L,
  bootstrap_replicates = 10000L,
  bootstrap_seed = 20260823L
))
if (!nzchar(as.character(args$output_root %||% ""))) {
  stop("--output_root is required.", call. = FALSE)
}
output_root <- app_resolve_path(args$output_root, must_work = TRUE)
audit_root <- if (nzchar(as.character(args$audit_root %||% ""))) {
  app_resolve_path(args$audit_root, must_work = FALSE)
} else {
  file.path(output_root, "structural_closeout_audit")
}
for (path in c(audit_root, file.path(audit_root, "tables"), file.path(audit_root, "figures"))) {
  app_ensure_dir(path)
}

finalization_path <- file.path(output_root, "finalization_status.csv")
ranking_path <- file.path(output_root, "constrained_median_ranking.csv")
manifest_path <- file.path(output_root, "runtime_manifest.csv")
anchor_path <- file.path(output_root, "campaign_anchor_contract.csv")
for (path in c(finalization_path, ranking_path, manifest_path, anchor_path)) {
  if (!file.exists(path)) stop(sprintf("Required strict-closeout artifact is missing: %s", path), call. = FALSE)
}
finalization <- app_read_csv(finalization_path)
if (nrow(finalization) != 1L || !app_as_bool(finalization$batch_complete[[1L]]) ||
    !identical(as.character(finalization$mode[[1L]] %||% "strict"), "strict")) {
  stop("Structural closeout audit requires one complete strict finalization.", call. = FALSE)
}
ranking <- app_read_csv(ranking_path)
manifest <- app_read_csv(manifest_path)
anchor_contract <- app_read_csv(anchor_path)
anchor <- stats::setNames(as.list(anchor_contract$value), anchor_contract$field)
baseline_contract <- app_read_yaml(app_resolve_path(args$baseline_contract, must_work = TRUE))

top_n <- suppressWarnings(as.integer(args$top_n))
if (!is.finite(top_n) || top_n < 1L) stop("--top_n must be positive.", call. = FALSE)
ranking <- ranking[order(as.integer(ranking$screen_rank), ranking$candidate_id), , drop = FALSE]
top_ids <- head(as.character(ranking$candidate_id), top_n)
control_ids <- if ("candidate_role" %in% names(manifest)) {
  as.character(manifest$candidate_id[grepl("control", manifest$candidate_role, ignore.case = TRUE)])
} else character()
campaign_ids <- unique(c(top_ids, control_ids))

run_dir_from_fit <- function(path) {
  path <- normalizePath(path, mustWork = TRUE)
  dirname(dirname(path))
}
source_rows <- list()
for (candidate_id in campaign_ids) {
  hit <- manifest[manifest$candidate_id == candidate_id, , drop = FALSE]
  if (nrow(hit) != 1L) stop(sprintf("Missing manifest row for %s.", candidate_id), call. = FALSE)
  source_rows[[length(source_rows) + 1L]] <- data.frame(
    candidate_id = candidate_id,
    source_role = if (candidate_id %in% top_ids) "structural_top" else "repeatability_control",
    run_dir = as.character(hit$run_dir[[1L]]),
    stringsAsFactors = FALSE
  )
}
source_rows[[length(source_rows) + 1L]] <- data.frame(
  candidate_id = as.character(anchor$anchor_candidate_id),
  source_role = "focused_anchor",
  run_dir = run_dir_from_fit(as.character(anchor$anchor_fit_object_path)),
  stringsAsFactors = FALSE
)
source_rows[[length(source_rows) + 1L]] <- data.frame(
  candidate_id = as.character(baseline_contract$candidate_id),
  source_role = "authoritative_fr09",
  run_dir = run_dir_from_fit(as.character(baseline_contract$artifacts$source_fit$path)),
  stringsAsFactors = FALSE
)
sources <- app_bind_rows_fill(source_rows)
sources <- sources[!duplicated(sources$candidate_id), , drop = FALSE]
sources$score_path <- file.path(sources$run_dir, "tables", "score_by_quantile.csv")
if (any(!file.exists(sources$score_path))) {
  stop(sprintf(
    "Missing p50 horizon score paths: %s.",
    paste(sources$score_path[!file.exists(sources$score_path)], collapse = ", ")
  ), call. = FALSE)
}
sources$score_sha256 <- vapply(sources$score_path, app_sha256_file, character(1L))

read_path <- function(source_row) {
  score <- app_read_csv(source_row$score_path[[1L]])
  keep <- grepl("^qdesn_", as.character(score$model_id)) &
    abs(as.numeric(score$quantile_level) - 0.5) < 1e-12
  score <- score[keep, , drop = FALSE]
  required <- c("target_date", "horizon", "check_loss")
  missing <- setdiff(required, names(score))
  if (!nrow(score) || length(missing)) {
    stop(sprintf("Invalid p50 horizon scores for %s.", source_row$candidate_id[[1L]]), call. = FALSE)
  }
  score <- score[order(as.integer(score$horizon), as.Date(score$target_date)), , drop = FALSE]
  if (anyDuplicated(paste(score$target_date, score$horizon)) ||
      any(!is.finite(as.numeric(score$check_loss)))) {
    stop(sprintf("Non-finite or duplicate p50 horizon scores for %s.", source_row$candidate_id[[1L]]), call. = FALSE)
  }
  data.frame(
    candidate_id = source_row$candidate_id[[1L]],
    source_role = source_row$source_role[[1L]],
    target_date = as.Date(score$target_date),
    horizon = as.integer(score$horizon),
    check_loss = as.numeric(score$check_loss),
    stringsAsFactors = FALSE
  )
}
paths <- app_bind_rows_fill(lapply(seq_len(nrow(sources)), function(i) read_path(sources[i, , drop = FALSE])))

comparison_ids <- c(
  authoritative_fr09 = as.character(baseline_contract$candidate_id),
  focused_anchor = as.character(anchor$anchor_candidate_id)
)
paired_rows <- list()
bootstrap_rows <- list()
for (candidate_id in top_ids) {
  candidate <- paths[paths$candidate_id == candidate_id, , drop = FALSE]
  for (comparison_role in names(comparison_ids)) {
    comparator_id <- comparison_ids[[comparison_role]]
    comparator <- paths[paths$candidate_id == comparator_id, , drop = FALSE]
    key_candidate <- paste(candidate$target_date, candidate$horizon)
    key_comparator <- paste(comparator$target_date, comparator$horizon)
    index <- match(key_candidate, key_comparator)
    if (anyNA(index) || nrow(candidate) != nrow(comparator)) {
      stop(sprintf("Horizon grids differ for %s and %s.", candidate_id, comparator_id), call. = FALSE)
    }
    difference <- candidate$check_loss - comparator$check_loss[index]
    paired_rows[[length(paired_rows) + 1L]] <- data.frame(
      candidate_id = candidate_id,
      comparator_id = comparator_id,
      comparator_role = comparison_role,
      target_date = candidate$target_date,
      horizon = candidate$horizon,
      candidate_check_loss = candidate$check_loss,
      comparator_check_loss = comparator$check_loss[index],
      check_loss_difference = difference,
      stringsAsFactors = FALSE
    )
    bootstrap <- app_glofas_median_screen_moving_block_bootstrap(
      difference,
      block_length = min(as.integer(args$block_length), length(difference)),
      replicates = as.integer(args$bootstrap_replicates),
      seed = as.integer(args$bootstrap_seed) + length(bootstrap_rows)
    )
    bootstrap_rows[[length(bootstrap_rows) + 1L]] <- cbind(
      data.frame(
        candidate_id = candidate_id,
        comparator_id = comparator_id,
        comparator_role = comparison_role,
        stringsAsFactors = FALSE
      ),
      bootstrap
    )
  }
}
paired <- app_bind_rows_fill(paired_rows)
bootstrap <- app_bind_rows_fill(bootstrap_rows)

scheduler_path <- file.path(output_root, "scheduler_state.csv")
scheduler <- if (file.exists(scheduler_path)) app_read_csv(scheduler_path) else data.frame()
runtime <- ranking[ranking$candidate_id %in% top_ids, c(
  "candidate_id", "screen_rank", "forecast_p50_check_loss_mean",
  "forecast_improvement_fraction", "observed_log1p_mae_all",
  "observed_log1p_mae_last1000", "observed_log1p_mae_last200",
  "observed_log1p_mae_last50", "eligible_for_full7_review"
), drop = FALSE]
if (nrow(scheduler)) {
  runtime$started_at <- scheduler$started_at[match(runtime$candidate_id, scheduler$candidate_id)]
  runtime$finished_at <- scheduler$finished_at[match(runtime$candidate_id, scheduler$candidate_id)]
  runtime$wall_hours <- as.numeric(
    as.POSIXct(runtime$finished_at, tz = "UTC") - as.POSIXct(runtime$started_at, tz = "UTC"),
    units = "hours"
  )
}

control_scores <- ranking[
  ranking$candidate_id %in% control_ids,
  c("candidate_id", "forecast_p50_check_loss_mean"),
  drop = FALSE
]
repeatability_envelope <- if (nrow(control_scores) >= 2L) {
  diff(range(as.numeric(control_scores$forecast_p50_check_loss_mean)))
} else NA_real_
best_id <- top_ids[[1L]]
best <- ranking[ranking$candidate_id == best_id, , drop = FALSE]
best_anchor <- bootstrap[
  bootstrap$candidate_id == best_id & bootstrap$comparator_role == "focused_anchor",
  , drop = FALSE
]
cold_confirmation_warranted <- nrow(best_anchor) == 1L &&
  app_as_bool(best$eligible_for_full7_review[[1L]]) &&
  best_anchor$ci_upper[[1L]] < 0 &&
  (!is.finite(repeatability_envelope) || -best_anchor$mean_difference[[1L]] > repeatability_envelope)
decision <- data.frame(
  best_candidate_id = best_id,
  best_forecast_p50_check_loss_mean = as.numeric(best$forecast_p50_check_loss_mean[[1L]]),
  frozen_fr09_improvement_fraction = as.numeric(best$forecast_improvement_fraction[[1L]]),
  frozen_three_percent_gate_pass = app_as_bool(best$forecast_gate_pass[[1L]]),
  historical_guardrails_pass = app_as_bool(best$historical_hard_gate_pass[[1L]]),
  technical_gate_pass = app_as_bool(best$technical_gate_pass[[1L]]),
  warm_cold_repeatability_envelope = repeatability_envelope,
  paired_anchor_mean_difference = if (nrow(best_anchor)) best_anchor$mean_difference[[1L]] else NA_real_,
  paired_anchor_ci_lower = if (nrow(best_anchor)) best_anchor$ci_lower[[1L]] else NA_real_,
  paired_anchor_ci_upper = if (nrow(best_anchor)) best_anchor$ci_upper[[1L]] else NA_real_,
  cold_confirmation_warranted = cold_confirmation_warranted,
  full7_warranted = FALSE,
  article_update_warranted = FALSE,
  next_action = if (cold_confirmation_warranted) {
    "run_bounded_cold_confirmation_before_any_full7_fit"
  } else {
    "retain_fr09_and_close_structural_campaign_without_refit"
  },
  stringsAsFactors = FALSE
)

tables <- list(
  source_manifest = sources,
  candidate_forecast_paths = paths,
  paired_horizon_differences = paired,
  paired_block_bootstrap = bootstrap,
  runtime_comparison = runtime,
  mechanism_decision = decision
)
for (name in names(tables)) {
  app_write_csv(tables[[name]], file.path(audit_root, "tables", paste0(name, ".csv")))
}

paired_plot <- ggplot2::ggplot(
  paired,
  ggplot2::aes(horizon, check_loss_difference, color = candidate_id)
) +
  ggplot2::geom_hline(yintercept = 0, linewidth = 0.35, color = "#555555") +
  ggplot2::geom_line(linewidth = 0.65) +
  ggplot2::facet_wrap(~comparator_role, ncol = 1L, scales = "free_y") +
  ggplot2::labs(
    x = "Forecast horizon (days)",
    y = "Paired p50 check-loss difference",
    color = "Candidate"
  ) +
  ggplot2::theme_bw(base_size = 9) +
  ggplot2::theme(legend.position = "bottom", panel.grid.minor = ggplot2::element_blank())
ggplot2::ggsave(
  file.path(audit_root, "figures", "paired_horizon_check_loss_differences.pdf"),
  paired_plot,
  width = 7.1,
  height = 5.2
)

runtime_plot <- ggplot2::ggplot(
  runtime,
  ggplot2::aes(wall_hours, forecast_p50_check_loss_mean, label = candidate_id)
) +
  ggplot2::geom_point(size = 2.2, color = "#2C6E9B") +
  ggplot2::geom_text(check_overlap = TRUE, nudge_y = 0.00015, size = 2.6) +
  ggplot2::labs(x = "Wall time (hours)", y = "Forecast-window p50 check loss") +
  ggplot2::theme_bw(base_size = 9) +
  ggplot2::theme(panel.grid.minor = ggplot2::element_blank())
ggplot2::ggsave(
  file.path(audit_root, "figures", "score_runtime_tradeoff.pdf"),
  runtime_plot,
  width = 7.1,
  height = 4.4
)

evidence <- unlist(lapply(names(tables), function(name) {
  file.path(audit_root, "tables", paste0(name, ".csv"))
}), use.names = FALSE)
evidence <- c(evidence, list.files(file.path(audit_root, "figures"), full.names = TRUE))
audit_manifest <- data.frame(
  path = evidence,
  sha256 = vapply(evidence, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
app_write_csv(audit_manifest, file.path(audit_root, "audit_manifest.csv"))
app_write_csv(data.frame(
  status = "completed",
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  output_root = output_root,
  ranking_sha256 = app_sha256_file(ranking_path),
  decision = decision$next_action[[1L]],
  cold_confirmation_warranted = decision$cold_confirmation_warranted[[1L]],
  full7_warranted = FALSE,
  article_update_warranted = FALSE,
  stringsAsFactors = FALSE
), file.path(audit_root, "audit_status.csv"))

cat(file.path(audit_root, "tables", "mechanism_decision.csv"), "\n")
