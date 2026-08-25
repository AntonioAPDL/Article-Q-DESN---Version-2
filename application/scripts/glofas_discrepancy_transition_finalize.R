#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(
    dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])),
    "..", ".."
  ),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/artifact_hygiene.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/glofas_discrepancy_transition.R"))
source(app_path("application/R/glofas_fit_recovery.R"))
source(app_path("application/R/glofas_discrepancy_transition_campaign.R"))

args <- app_parse_args(list(
  output_root = "local_trackers/runtime_configs/glofas_discrepancy_transition_bridge_20260825",
  cleanup = TRUE
))
resolve_repo <- function(path, must_work = FALSE) {
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}
output_root <- resolve_repo(args$output_root, must_work = TRUE)
manifest <- app_read_csv(file.path(output_root, "runtime_manifest.csv"))
campaign <- app_read_yaml(file.path(output_root, "campaign_snapshot.yaml"))
candidates <- app_glofas_transition_validate_candidates(
  app_read_csv(file.path(output_root, "candidate_registry_snapshot.csv"))
)

state_path <- file.path(output_root, "scheduler_state.csv")
state <- if (file.exists(state_path)) app_read_csv(state_path) else data.frame()
terminal <- c("completed", "completed_existing")
complete_markers <- file.exists(file.path(manifest$run_dir, ".fit_recovery_complete"))
state_status <- if (nrow(state)) {
  as.character(state$status[match(manifest$candidate_id, state$candidate_id)])
} else {
  rep(NA_character_, nrow(manifest))
}
status_summary <- data.frame(
  total = nrow(manifest),
  completed = sum(complete_markers),
  running = sum(state_status %in% c("running", "running_external"), na.rm = TRUE),
  pending = sum(state_status %in% c("pending"), na.rm = TRUE),
  failed = sum(grepl("failed", state_status), na.rm = TRUE),
  completion_percent = 100 * sum(complete_markers) / nrow(manifest),
  finalized_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  stringsAsFactors = FALSE
)
app_write_csv(status_summary, file.path(output_root, "tables", "finalization_status.csv"))
if (!all(complete_markers) || (nrow(state) && any(!state_status %in% terminal))) {
  stop(sprintf(
    "Transition campaign is not terminal: %d/%d complete.",
    sum(complete_markers), nrow(manifest)
  ), call. = FALSE)
}

score_rows <- list()
horizon_rows <- list()
diagnostic_rows <- list()
history_rows <- list()
for (i in seq_len(nrow(manifest))) {
  row <- manifest[i, , drop = FALSE]
  run_dir <- row$run_dir[[1L]]
  required <- c(
    "tables/prediction_quantiles.csv",
    "tables/fit_status.csv",
    "tables/qdesn_discrepancy_fit_diagnostics.csv",
    "tables/qdesn_discrepancy_design_summary.csv",
    "tables/score_summary.csv"
  )
  missing <- required[!file.exists(file.path(run_dir, required))]
  if (length(missing)) {
    stop(sprintf(
      "Completed run %s lacks: %s.",
      row$candidate_id[[1L]], paste(missing, collapse = ", ")
    ), call. = FALSE)
  }
  scored <- app_glofas_transition_score_prediction_table(
    app_read_csv(file.path(run_dir, "tables", "prediction_quantiles.csv")),
    candidate_id = row$base_candidate_id[[1L]],
    cutoff_id = row$cutoff_id[[1L]],
    selection_role = row$selection_role[[1L]]
  )
  score_rows[[length(score_rows) + 1L]] <- scored$summary
  horizon_rows[[length(horizon_rows) + 1L]] <- scored$horizon

  fit_status <- app_read_csv(file.path(run_dir, "tables", "fit_status.csv"))
  fit_status <- fit_status[
    fit_status$model_family == "qdesn_glofas_discrepancy",
    ,
    drop = FALSE
  ]
  diagnostics <- app_read_csv(file.path(
    run_dir, "tables", "qdesn_discrepancy_fit_diagnostics.csv"
  ))
  design <- app_read_csv(file.path(
    run_dir, "tables", "qdesn_discrepancy_design_summary.csv"
  ))
  if (nrow(fit_status) != 1L || nrow(diagnostics) != 1L || nrow(design) != 1L) {
    stop(sprintf("Run %s has nonunique fit diagnostics.", row$candidate_id[[1L]]), call. = FALSE)
  }
  diagnostic_rows[[length(diagnostic_rows) + 1L]] <- data.frame(
    candidate_id = row$base_candidate_id[[1L]],
    runtime_candidate_id = row$candidate_id[[1L]],
    cutoff_id = row$cutoff_id[[1L]],
    selection_role = row$selection_role[[1L]],
    fit_status = fit_status$status[[1L]],
    runtime_seconds = as.numeric(fit_status$runtime_seconds[[1L]]),
    vb_converged = app_as_bool(diagnostics$vb_converged[[1L]]),
    vb_iterations = as.integer(diagnostics$vb_iterations[[1L]]),
    finite_theta = app_as_bool(diagnostics$finite_theta[[1L]]),
    finite_sigma = app_as_bool(diagnostics$finite_sigma[[1L]]),
    max_abs_theta = as.numeric(diagnostics$max_abs_theta[[1L]]),
    design_hash = as.character(design$design_hash[[1L]]),
    transition_contract_hash = as.character(
      design$discrepancy_transition_contract_hash[[1L]] %||%
        row$discrepancy_transition_contract_hash[[1L]]
    ),
    future_policy = as.character(design$covariate_future_policy[[1L]]),
    uses_realized_future = app_as_bool(design$covariate_uses_realized_future[[1L]]),
    context_variables = as.character(
      design$discrepancy_context_variables[[1L]] %||% ""
    ),
    stringsAsFactors = FALSE
  )
  history_path <- file.path(
    output_root,
    "scores",
    paste0(row$candidate_id[[1L]], "_observed_fit_scores.csv")
  )
  if (!file.exists(history_path)) {
    stop(sprintf("Run %s lacks causal observed-fit scores.", row$candidate_id[[1L]]), call. = FALSE)
  }
  history <- app_read_csv(history_path)
  history <- history[history$window %in% c("all", "last200", "last50"), , drop = FALSE]
  history$base_candidate_id <- row$base_candidate_id[[1L]]
  history$cutoff_id <- row$cutoff_id[[1L]]
  history$selection_role <- row$selection_role[[1L]]
  history_rows[[length(history_rows) + 1L]] <- history
}

scores <- app_bind_rows_fill(score_rows)
horizon <- app_bind_rows_fill(horizon_rows)
diagnostics <- app_bind_rows_fill(diagnostic_rows)
history <- app_bind_rows_fill(history_rows)
app_write_csv(scores, file.path(output_root, "tables", "transition_run_scores.csv"))
app_write_csv(horizon, file.path(output_root, "tables", "transition_horizon_scores.csv"))
app_write_csv(diagnostics, file.path(output_root, "tables", "transition_fit_diagnostics.csv"))
app_write_csv(history, file.path(output_root, "tables", "transition_observed_fit_scores.csv"))

primary <- scores[scores$selection_role == campaign$scoring$primary_origin_role, , drop = FALSE]
if (length(unique(primary$cutoff_id)) != 3L) {
  stop("Finalization requires all three primary v3.1 origins.", call. = FALSE)
}
aggregate <- app_glofas_transition_equal_origin_aggregate(primary)
aggregate <- merge(
  aggregate,
  candidates[, c(
    "candidate_id", "anchor_method", "anchor_window", "anchor_half_life",
    "glofas_level", "glofas_anomaly", "role", "priority"
  )],
  by = "candidate_id",
  all.x = TRUE
)
comparator_id <- "t01_last"
comparator_score <- aggregate$future_p50_check_loss[
  aggregate$candidate_id == comparator_id
]
if (length(comparator_score) != 1L || !is.finite(comparator_score)) {
  stop("The T01 mechanism comparator is missing from primary aggregation.", call. = FALSE)
}
baseline_scores <- app_read_csv(file.path(
  output_root, "tables", "causal_baseline_scores.csv"
))
baseline_primary <- baseline_scores[
  baseline_scores$selection_role == campaign$scoring$primary_origin_role,
  ,
  drop = FALSE
]
baseline_aggregate <- app_glofas_transition_equal_origin_aggregate(baseline_primary)
baseline_aggregate <- baseline_aggregate[
  baseline_aggregate$method_class == "deterministic_causal_baseline",
  ,
  drop = FALSE
]
best_baseline <- baseline_aggregate[
  which.min(baseline_aggregate$future_p50_check_loss),
  ,
  drop = FALSE
]
app_write_csv(
  baseline_aggregate[order(baseline_aggregate$future_p50_check_loss), , drop = FALSE],
  file.path(output_root, "tables", "causal_baseline_ranking.csv")
)

t01_by_origin <- primary[
  primary$candidate_id == comparator_id,
  c("cutoff_id", "future_p50_check_loss", "glofas_reconstruction_mae"),
  drop = FALSE
]
names(t01_by_origin)[-1L] <- paste0(names(t01_by_origin)[-1L], "_t01")
origin_compare <- merge(primary, t01_by_origin, by = "cutoff_id", all.x = TRUE)
origin_compare$relative_change_vs_t01 <- (
  origin_compare$future_p50_check_loss - origin_compare$future_p50_check_loss_t01
) / origin_compare$future_p50_check_loss_t01
origin_gate <- do.call(rbind, lapply(unique(origin_compare$candidate_id), function(id) {
  block <- origin_compare[origin_compare$candidate_id == id, , drop = FALSE]
  data.frame(
    candidate_id = id,
    primary_origin_wins = sum(
      block$future_p50_check_loss <= block$future_p50_check_loss_t01
    ),
    worst_primary_origin_regression = max(block$relative_change_vs_t01),
    worst_glofas_reconstruction_ratio = max(
      block$glofas_reconstruction_mae /
        pmax(block$glofas_reconstruction_mae_t01, .Machine$double.eps)
    ),
    stringsAsFactors = FALSE
  )
}))
app_write_csv(origin_compare, file.path(output_root, "tables", "transition_origin_comparison.csv"))

t01_history <- history[history$base_candidate_id == comparator_id, c(
  "cutoff_id", "window", "p50_check_loss_mean"
), drop = FALSE]
names(t01_history)[[3L]] <- "p50_check_loss_mean_t01"
history_compare <- merge(history, t01_history, by = c("cutoff_id", "window"), all.x = TRUE)
history_compare$relative_change_vs_t01 <- (
  history_compare$p50_check_loss_mean - history_compare$p50_check_loss_mean_t01
) / history_compare$p50_check_loss_mean_t01
history_gate <- do.call(rbind, lapply(unique(history_compare$base_candidate_id), function(id) {
  block <- history_compare[history_compare$base_candidate_id == id, , drop = FALSE]
  all_change <- block$relative_change_vs_t01[block$window == "all"]
  trailing_change <- block$relative_change_vs_t01[block$window %in% c("last200", "last50")]
  data.frame(
    candidate_id = id,
    worst_observed_all_regression = max(all_change, na.rm = TRUE),
    worst_observed_trailing_regression = max(trailing_change, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}))
app_write_csv(
  history_compare,
  file.path(output_root, "tables", "transition_observed_guardrail_comparison.csv")
)

fit_gate <- do.call(rbind, lapply(unique(diagnostics$candidate_id), function(id) {
  block <- diagnostics[diagnostics$candidate_id == id, , drop = FALSE]
  data.frame(
    candidate_id = id,
    all_fits_completed = all(block$fit_status == "completed"),
    all_vb_converged = all(block$vb_converged),
    all_finite = all(block$finite_theta & block$finite_sigma),
    no_future_covariate_leakage = all(
      block$future_policy == "origin_persistence" & !block$uses_realized_future
    ),
    mean_runtime_seconds = mean(block$runtime_seconds),
    max_runtime_seconds = max(block$runtime_seconds),
    mean_vb_iterations = mean(block$vb_iterations),
    stringsAsFactors = FALSE
  )
}))

ranking <- Reduce(function(x, y) merge(x, y, by = "candidate_id", all.x = TRUE), list(
  aggregate, origin_gate, history_gate, fit_gate
))
ranking$absolute_gain_vs_t01 <- comparator_score - ranking$future_p50_check_loss
ranking$relative_gain_vs_t01 <- ranking$absolute_gain_vs_t01 / comparator_score
ranking$gain_exceeds_repeatability <- ranking$absolute_gain_vs_t01 >
  as.numeric(campaign$scoring$repeatability_absolute_envelope)
ranking$passes_improvement_gate <- ranking$relative_gain_vs_t01 >=
  as.numeric(campaign$scoring$required_relative_improvement)
ranking$passes_causal_baseline_gate <- ranking$future_p50_check_loss <
  best_baseline$future_p50_check_loss[[1L]]
ranking$passes_origin_win_gate <- ranking$primary_origin_wins >=
  as.integer(campaign$scoring$minimum_primary_origin_wins)
ranking$passes_origin_regression_gate <- ranking$worst_primary_origin_regression <=
  as.numeric(campaign$scoring$maximum_primary_origin_regression)
ranking$passes_observed_all_gate <- ranking$worst_observed_all_regression <=
  as.numeric(campaign$scoring$observed_all_relative_guardrail)
ranking$passes_observed_trailing_gate <- ranking$worst_observed_trailing_regression <=
  as.numeric(campaign$scoring$observed_trailing_relative_guardrail)
ranking$passes_reconstruction_gate <- ranking$worst_glofas_reconstruction_ratio <= 1.10
ranking$passes_numerical_gate <- ranking$all_fits_completed &
  ranking$all_vb_converged & ranking$all_finite &
  ranking$no_future_covariate_leakage
ranking$passes_all_development_gates <- with(ranking,
  gain_exceeds_repeatability & passes_improvement_gate &
    passes_causal_baseline_gate & passes_origin_win_gate &
    passes_origin_regression_gate & passes_observed_all_gate &
    passes_observed_trailing_gate & passes_reconstruction_gate &
    passes_numerical_gate
)
ranking <- ranking[order(
  -as.integer(ranking$passes_all_development_gates),
  ranking$future_p50_check_loss,
  ranking$priority
), , drop = FALSE]
ranking$rank <- seq_len(nrow(ranking))
app_write_csv(ranking, file.path(output_root, "tables", "transition_candidate_ranking.csv"))

passing <- ranking$candidate_id[ranking$passes_all_development_gates]
decision <- data.frame(
  decision = if (length(passing)) {
    "development_candidate_requires_cold_confirmation"
  } else {
    "no_transition_candidate_passed_frozen_development_gates"
  },
  selected_candidate = if (length(passing)) passing[[1L]] else NA_character_,
  exploratory_leader = ranking$candidate_id[[1L]],
  comparator = comparator_id,
  comparator_primary_check_loss = comparator_score,
  best_causal_baseline = best_baseline$candidate_id[[1L]],
  best_causal_baseline_check_loss = best_baseline$future_p50_check_loss[[1L]],
  december_2022_evaluated = FALSE,
  full7_launched = FALSE,
  article_update_authorized = FALSE,
  stringsAsFactors = FALSE
)
app_write_csv(decision, file.path(output_root, "tables", "transition_decision.csv"))

if (app_as_bool(args$cleanup)) {
  keep_n <- as.integer(campaign$execution$retain_top_candidate_count)
  protected_ids <- unique(c(
    comparator_id,
    utils::head(ranking$candidate_id, keep_n),
    passing
  ))
  cleanup_rows <- list()
  for (i in seq_len(nrow(manifest))) {
    run_dir <- manifest$run_dir[[i]]
    protected <- manifest$base_candidate_id[[i]] %in% protected_ids
    inventory <- app_glofas_fit_recovery_cleanup(
      run_dir,
      runs_root = file.path(output_root, "runs"),
      execute = TRUE,
      protected = protected
    )
    if (nrow(inventory)) {
      inventory$candidate_id <- manifest$candidate_id[[i]]
      inventory$base_candidate_id <- manifest$base_candidate_id[[i]]
      cleanup_rows[[length(cleanup_rows) + 1L]] <- inventory
    }
  }
  cleanup_report <- app_bind_rows_fill(cleanup_rows)
  app_write_csv(cleanup_report, file.path(output_root, "cleanup", "cleanup_report.csv"))
}

writeLines(c(
  paste("Decision:", decision$decision[[1L]]),
  paste("Exploratory leader:", decision$exploratory_leader[[1L]]),
  paste("Selected for cold confirmation:", decision$selected_candidate[[1L]]),
  "December 2022 was not evaluated; no full7 or article update was launched."
), file.path(output_root, "FINALIZATION_SUMMARY.txt"))
writeLines(
  format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  file.path(output_root, ".transition_campaign_complete")
)
cat(file.path(output_root, "tables", "transition_candidate_ranking.csv"), "\n")
