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
  allow_partial = FALSE,
  cleanup = FALSE,
  mode = "strict",
  protect_top_n = 2L,
  protect_controls = TRUE,
  protect_candidate_ids = ""
))
if (!nzchar(as.character(args$output_root %||% ""))) {
  stop("--output_root is required.", call. = FALSE)
}
output_root <- app_resolve_path(args$output_root, must_work = TRUE)
mode <- match.arg(tolower(as.character(args$mode %||% "strict")), c("strict", "forensic"))
forensic <- identical(mode, "forensic")
if (forensic && app_as_bool(args$cleanup)) {
  stop("Cleanup is prohibited during a forensic closeout.", call. = FALSE)
}
artifact_root <- if (forensic) file.path(output_root, "forensic_closeout") else output_root
app_ensure_dir(artifact_root)
artifact_path <- function(name) file.path(artifact_root, name)
manifest <- app_read_csv(file.path(output_root, "runtime_manifest.csv"))
space <- app_read_yaml(file.path(output_root, "screening_space_snapshot.yaml"))

candidate_states <- app_glofas_median_screen_candidate_states(manifest, output_root)
fit_complete <- candidate_states$state == "completed"
preflight_rejected <- candidate_states$state == "preflight_rejected"
failed <- candidate_states$state == "failed"
terminal <- fit_complete | preflight_rejected
allow_partial <- forensic || app_as_bool(args$allow_partial)
if (!all(terminal) && !allow_partial) {
  stop(sprintf(
    "Screen is incomplete: %d/%d candidates reached a terminal state. Use --allow_partial true only for an explicitly provisional ranking.",
    sum(terminal), length(terminal)
  ), call. = FALSE)
}
app_write_csv(candidate_states, artifact_path("candidate_state_census.csv"))
finished <- manifest[fit_complete, , drop = FALSE]
if (!nrow(finished)) stop("No completed candidates are available to finalize.", call. = FALSE)

preflight_rows <- lapply(seq_len(nrow(manifest)), function(i) {
  enabled <- if ("reservoir_preflight_enabled" %in% names(manifest)) {
    app_as_bool(manifest$reservoir_preflight_enabled[[i]])
  } else FALSE
  audit_path <- file.path(output_root, "status", paste0(manifest$candidate_id[[i]], ".reservoir_preflight.csv"))
  if (enabled && !file.exists(audit_path)) {
    if (terminal[[i]]) {
      stop(sprintf("Missing reservoir preflight audit for %s.", manifest$candidate_id[[i]]), call. = FALSE)
    }
    return(data.frame(
      candidate_id = manifest$candidate_id[[i]], decision = "pending",
      gate_pass = FALSE, reject_policy = "reject", summary_path = "",
      summary_sha256 = "", stringsAsFactors = FALSE
    ))
  }
  if (!enabled) {
    return(data.frame(
      candidate_id = manifest$candidate_id[[i]], decision = "not_run",
      gate_pass = TRUE, reject_policy = "none", summary_path = "",
      summary_sha256 = "", stringsAsFactors = FALSE
    ))
  }
  audit <- app_read_csv(audit_path)
  if (nrow(audit) != 1L) stop(sprintf("Invalid reservoir preflight audit for %s.", manifest$candidate_id[[i]]), call. = FALSE)
  audit[, intersect(
    c("candidate_id", "decision", "gate_pass", "reject_policy", "summary_path", "summary_sha256"),
    names(audit)
  ), drop = FALSE]
})
preflight_gates <- app_bind_rows_fill(preflight_rows)
app_write_csv(preflight_gates, artifact_path("reservoir_preflight_gates_all.csv"))
app_write_csv(
  preflight_gates[!app_as_bool_vec(preflight_gates$gate_pass), , drop = FALSE],
  artifact_path("reservoir_preflight_rejections.csv")
)

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
  preflight_row <- preflight_gates[preflight_gates$candidate_id == candidate_id, , drop = FALSE]
  if (nrow(preflight_row) != 1L) stop(sprintf("Candidate %s lacks one reservoir preflight gate.", candidate_id), call. = FALSE)
  preflight_pass <- app_as_bool(preflight_row$gate_pass[[1L]])
  technical_pass <- app_as_bool(drow$finite_theta[[1L]]) &&
    is.finite(as.numeric(drow$vb_elbo_final[[1L]])) &&
    (!require_converged || app_as_bool(drow$vb_converged[[1L]])) &&
    preflight_pass
  technical_rows[[i]] <- data.frame(
    candidate_id = candidate_id,
    technical_gate_pass = technical_pass,
    vb_converged = app_as_bool(drow$vb_converged[[1L]]),
    vb_iterations = as.integer(drow$vb_iterations[[1L]]),
    vb_elbo_final = as.numeric(drow$vb_elbo_final[[1L]]),
    reservoir_preflight_decision = as.character(preflight_row$decision[[1L]]),
    reservoir_preflight_pass = preflight_pass,
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
ranking$ranking_scope <- if (all(terminal)) {
  "complete_batch"
} else if (forensic) {
  "forensic_partial_batch"
} else {
  "provisional_partial_batch"
}
ranking$selection_metric_note <- paste(
  "p50 uses check loss and MAE; genuine distributional CRPS requires",
  "an independently fitted multi-quantile confirmation"
)

app_write_csv(observed, artifact_path("observed_fit_scores_all.csv"))
app_write_csv(forecast, artifact_path("forecast_p50_scores_all.csv"))
app_write_csv(technical, artifact_path("technical_gates_all.csv"))
app_write_csv(ranking, artifact_path("constrained_median_ranking.csv"))

decision <- data.frame(
  batch_complete = all(terminal),
  completed_candidates = sum(fit_complete),
  preflight_rejected_candidates = sum(preflight_rejected),
  failed_candidates = sum(failed),
  incomplete_candidates = sum(!terminal & !failed),
  terminal_candidates = sum(terminal),
  total_candidates = length(terminal),
  eligible_candidates = sum(ranking$eligible_for_full7_review),
  recommended_candidate = if (any(ranking$eligible_for_full7_review)) {
    ranking$candidate_id[which(ranking$eligible_for_full7_review)[[1L]]]
  } else NA_character_,
  auto_promote = FALSE,
  auto_launch_full7 = FALSE,
  next_gate = if (!all(terminal)) {
    "repair_failed_or_incomplete_candidates_then_strict_finalize"
  } else if (any(ranking$eligible_for_full7_review)) {
    "diagnostic_review_then_cold_p50_refit_then_full7_confirmation"
  } else {
    "revise_user_supplied_screening_space"
  },
  stringsAsFactors = FALSE
)
app_write_csv(decision, artifact_path("selection_decision.csv"))

explicit_protection <- strsplit(
  as.character(args$protect_candidate_ids %||% ""),
  ",",
  fixed = TRUE
)[[1L]]
protected <- app_glofas_median_screen_protected_candidates(
  ranking = ranking,
  manifest = manifest,
  top_n = args$protect_top_n,
  keep_controls = app_as_bool(args$protect_controls),
  explicit = explicit_protection
)
retention <- manifest[, intersect(
  c("candidate_id", "candidate_set", "candidate_label", "candidate_role", "run_id", "run_dir"),
  names(manifest)
), drop = FALSE]
retention$screen_rank <- ranking$screen_rank[match(retention$candidate_id, ranking$candidate_id)]
retention$eligible_for_full7_review <- ranking$eligible_for_full7_review[
  match(retention$candidate_id, ranking$candidate_id)
]
retention$candidate_state <- candidate_states$state[
  match(retention$candidate_id, candidate_states$candidate_id)
]
retention$protected <- retention$candidate_id %in% protected
retention$retention_action <- ifelse(
  retention$protected,
  "keep_heavy_artifacts",
  ifelse(retention$candidate_state == "preflight_rejected", "no_fit_payload", "delete_heavy_artifacts_after_audit")
)
app_write_csv(retention, artifact_path("retention_decision.csv"))

cleanup_report_path <- artifact_path(file.path("cleanup", "cleanup_report.csv"))
cleanup_dry_run_path <- artifact_path(file.path("cleanup", "dry_run_cleanup.csv"))
if (app_as_bool(args$cleanup)) {
  if (!all(terminal)) stop("Cleanup is prohibited for a partial batch.", call. = FALSE)

  retained_rows <- lapply(protected, function(candidate_id) {
    run_dir <- manifest$run_dir[match(candidate_id, manifest$candidate_id)]
    inventory <- app_glofas_fit_recovery_heavy_inventory(run_dir)
    if (!nrow(inventory)) return(data.frame())
    inventory$candidate_id <- candidate_id
    inventory$sha256 <- vapply(inventory$path, app_sha256_file, character(1L))
    inventory
  })
  retained_manifest <- app_bind_rows_fill(retained_rows)
  if (!ncol(retained_manifest)) {
    retained_manifest <- data.frame(
      path = character(), extension = character(), size_bytes = numeric(),
      candidate_id = character(), sha256 = character(),
      stringsAsFactors = FALSE
    )
  }
  app_write_csv(retained_manifest, artifact_path("retained_heavy_artifact_manifest.csv"))

  dry_run_rows <- list()
  for (i in seq_len(nrow(manifest))) {
    dry_run <- app_glofas_fit_recovery_cleanup(
      manifest$run_dir[[i]],
      runs_root = file.path(output_root, "runs"),
      execute = FALSE,
      protected = manifest$candidate_id[[i]] %in% protected
    )
    if (nrow(dry_run)) {
      dry_run$candidate_id <- manifest$candidate_id[[i]]
      dry_run_rows[[length(dry_run_rows) + 1L]] <- dry_run
    }
  }
  existing_dry_run <- if (file.exists(cleanup_dry_run_path)) {
    app_read_csv(cleanup_dry_run_path)
  } else {
    data.frame()
  }
  dry_run_report <- app_glofas_median_screen_merge_cleanup_reports(
    existing_dry_run,
    app_bind_rows_fill(dry_run_rows)
  )
  app_write_csv(dry_run_report, cleanup_dry_run_path)

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
  existing_cleanup <- if (file.exists(cleanup_report_path)) {
    app_read_csv(cleanup_report_path)
  } else {
    app_glofas_median_screen_recover_cleanup_dry_run(dry_run_report)
  }
  cleanup_report <- app_glofas_median_screen_merge_cleanup_reports(
    existing_cleanup,
    app_bind_rows_fill(cleanup_rows)
  )
  app_write_csv(cleanup_report, cleanup_report_path)
}

ranking_path <- artifact_path("constrained_median_ranking.csv")
selection_path <- artifact_path("selection_decision.csv")
status_label <- if (forensic) {
  "forensic_partial_closeout"
} else if (all(terminal)) {
  "strict_closeout_completed"
} else {
  "provisional_partial_closeout"
}
app_write_csv(data.frame(
  status = status_label,
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  mode = mode,
  batch_complete = all(terminal),
  completed_candidates = sum(fit_complete),
  preflight_rejected_candidates = sum(preflight_rejected),
  failed_candidates = sum(failed),
  incomplete_candidates = sum(!terminal & !failed),
  terminal_candidates = sum(terminal),
  total_candidates = length(terminal),
  cleanup_requested = app_as_bool(args$cleanup),
  protected_candidates = paste(protected, collapse = ";"),
  ranking_path = ranking_path,
  ranking_sha256 = app_sha256_file(ranking_path),
  selection_path = selection_path,
  selection_sha256 = app_sha256_file(selection_path),
  cleanup_report_path = if (file.exists(cleanup_report_path)) cleanup_report_path else NA_character_,
  cleanup_report_sha256 = if (file.exists(cleanup_report_path)) {
    app_sha256_file(cleanup_report_path)
  } else {
    NA_character_
  },
  stringsAsFactors = FALSE
), artifact_path("finalization_status.csv"))

closeout_evidence <- c(
  "candidate_state_census.csv",
  "reservoir_preflight_gates_all.csv",
  "reservoir_preflight_rejections.csv",
  "observed_fit_scores_all.csv",
  "forecast_p50_scores_all.csv",
  "technical_gates_all.csv",
  "constrained_median_ranking.csv",
  "selection_decision.csv",
  "retention_decision.csv",
  "finalization_status.csv",
  if (file.exists(artifact_path("retained_heavy_artifact_manifest.csv"))) {
    "retained_heavy_artifact_manifest.csv"
  },
  if (file.exists(cleanup_dry_run_path)) file.path("cleanup", "dry_run_cleanup.csv"),
  if (file.exists(cleanup_report_path)) file.path("cleanup", "cleanup_report.csv")
)
closeout_evidence <- unique(closeout_evidence[nzchar(closeout_evidence)])
closeout_paths <- artifact_path(closeout_evidence)
if (any(!file.exists(closeout_paths))) {
  stop("Closeout evidence packet is incomplete after finalization.", call. = FALSE)
}
app_write_csv(data.frame(
  artifact = closeout_evidence,
  path = closeout_paths,
  sha256 = vapply(closeout_paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
), artifact_path("closeout_artifact_manifest.csv"))

cat(ranking_path, "\n")
