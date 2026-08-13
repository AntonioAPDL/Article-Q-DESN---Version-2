#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/glofas_fit_recovery.R"))
source(app_path("application/R/glofas_constrained_median_screening.R"))

args <- app_parse_args(list(
  output_root = "",
  allow_partial = FALSE,
  cleanup = FALSE
))
if (!nzchar(as.character(args$output_root %||% ""))) {
  stop("--output_root is required.", call. = FALSE)
}
output_root <- app_resolve_path(args$output_root, must_work = TRUE)
manifest <- app_read_csv(file.path(output_root, "runtime_manifest.csv"))
space <- app_read_yaml(file.path(output_root, "screening_space_snapshot.yaml"))

complete <- vapply(manifest$run_dir, function(path) {
  file.exists(file.path(path, ".fit_recovery_complete"))
}, logical(1L))
if (!all(complete) && !app_as_bool(args$allow_partial)) {
  stop(sprintf(
    "Screen is incomplete: %d/%d candidates completed. Use --allow_partial true only for an explicitly provisional ranking.",
    sum(complete), length(complete)
  ), call. = FALSE)
}
finished <- manifest[complete, , drop = FALSE]
if (!nrow(finished)) stop("No completed candidates are available to finalize.", call. = FALSE)

observed_rows <- list()
forecast_rows <- list()
technical_rows <- list()
for (i in seq_len(nrow(finished))) {
  candidate_id <- finished$candidate_id[[i]]
  observed_path <- file.path(output_root, "scores", paste0(candidate_id, "_observed_fit_scores.csv"))
  if (!file.exists(observed_path)) stop(sprintf("Missing observed-fit scores for %s.", candidate_id), call. = FALSE)
  observed_rows[[i]] <- app_read_csv(observed_path)

  score_path <- file.path(finished$run_dir[[i]], "tables", "score_summary.csv")
  score <- app_read_csv(score_path)
  qrow <- score[grepl("^qdesn_", score$model_id), , drop = FALSE]
  if (nrow(qrow) != 1L || !is.finite(as.numeric(qrow$check_loss_mean[[1L]]))) {
    stop(sprintf("Candidate %s lacks one finite p50 Q-DESN forecast check-loss row.", candidate_id), call. = FALSE)
  }
  forecast_rows[[i]] <- data.frame(
    candidate_id = candidate_id,
    forecast_p50_check_loss_mean = as.numeric(qrow$check_loss_mean[[1L]]),
    stringsAsFactors = FALSE
  )

  diagnostics_path <- file.path(finished$run_dir[[i]], "tables", "qdesn_discrepancy_fit_diagnostics.csv")
  diagnostics <- app_read_csv(diagnostics_path)
  drow <- diagnostics[abs(as.numeric(diagnostics$quantile_level) - 0.5) < 1e-12, , drop = FALSE]
  if (nrow(drow) != 1L) stop(sprintf("Candidate %s lacks one p50 fit-diagnostic row.", candidate_id), call. = FALSE)
  require_converged <- app_as_bool((space$selection %||% list())$require_vb_converged %||% FALSE)
  technical_pass <- app_as_bool(drow$finite_theta[[1L]]) &&
    is.finite(as.numeric(drow$vb_elbo_final[[1L]])) &&
    (!require_converged || app_as_bool(drow$vb_converged[[1L]]))
  technical_rows[[i]] <- data.frame(
    candidate_id = candidate_id,
    technical_gate_pass = technical_pass,
    vb_converged = app_as_bool(drow$vb_converged[[1L]]),
    vb_iterations = as.integer(drow$vb_iterations[[1L]]),
    vb_elbo_final = as.numeric(drow$vb_elbo_final[[1L]]),
    stringsAsFactors = FALSE
  )
}

observed <- app_bind_rows_fill(observed_rows)
forecast <- app_bind_rows_fill(forecast_rows)
technical <- app_bind_rows_fill(technical_rows)
ranking <- app_glofas_median_screen_rank(
  observed_scores = observed,
  forecast_scores = forecast,
  baseline = space$baseline %||% list(),
  policy = (space$selection %||% list())$policy %||% list(),
  technical_status = technical
)
ranking <- merge(ranking, technical, by = c("candidate_id", "technical_gate_pass"), all.x = TRUE, sort = FALSE)
ranking <- merge(ranking, manifest, by = "candidate_id", all.x = TRUE, sort = FALSE)
ranking <- ranking[order(ranking$screen_rank), , drop = FALSE]
ranking$ranking_scope <- if (all(complete)) "complete_batch" else "provisional_partial_batch"
ranking$selection_metric_note <- paste(
  "p50 uses check loss and MAE; genuine distributional CRPS requires",
  "an independently fitted multi-quantile confirmation"
)

app_write_csv(observed, file.path(output_root, "observed_fit_scores_all.csv"))
app_write_csv(forecast, file.path(output_root, "forecast_p50_scores_all.csv"))
app_write_csv(technical, file.path(output_root, "technical_gates_all.csv"))
app_write_csv(ranking, file.path(output_root, "constrained_median_ranking.csv"))

decision <- data.frame(
  batch_complete = all(complete),
  completed_candidates = sum(complete),
  total_candidates = length(complete),
  eligible_candidates = sum(ranking$eligible_for_full7_review),
  recommended_candidate = if (any(ranking$eligible_for_full7_review)) {
    ranking$candidate_id[which(ranking$eligible_for_full7_review)[[1L]]]
  } else NA_character_,
  auto_promote = FALSE,
  auto_launch_full7 = FALSE,
  next_gate = if (any(ranking$eligible_for_full7_review)) {
    "diagnostic_review_then_cold_p50_refit_then_full7_confirmation"
  } else {
    "revise_user_supplied_screening_space"
  },
  stringsAsFactors = FALSE
)
app_write_csv(decision, file.path(output_root, "selection_decision.csv"))

if (app_as_bool(args$cleanup)) {
  if (!all(complete)) stop("Cleanup is prohibited for a partial batch.", call. = FALSE)
  protected <- ranking$candidate_id[ranking$eligible_for_full7_review]
  if (!length(protected)) protected <- ranking$candidate_id[[1L]]
  cleanup_rows <- list()
  for (i in seq_len(nrow(manifest))) {
    cleanup <- app_glofas_fit_recovery_cleanup(
      manifest$run_dir[[i]],
      runs_root = file.path(output_root, "runs"),
      execute = TRUE,
      protected = manifest$candidate_id[[i]] %in% protected
    )
    if (nrow(cleanup)) {
      cleanup$candidate_id <- manifest$candidate_id[[i]]
      cleanup_rows[[length(cleanup_rows) + 1L]] <- cleanup
    }
  }
  app_write_csv(app_bind_rows_fill(cleanup_rows), file.path(output_root, "cleanup", "cleanup_report.csv"))
}

cat(file.path(output_root, "constrained_median_ranking.csv"), "\n")
