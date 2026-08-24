# Program-level closeout for completed GloFAS constrained-median campaigns.

app_glofas_screening_program_phase_summary <- function(phase) {
  required <- c(
    "phase_id", "runtime_root", "expected_total", "expected_completed",
    "expected_preflight_rejected", "expected_ranking_sha256", "expected_leader"
  )
  missing <- required[!vapply(required, function(name) {
    value <- phase[[name]]
    !is.null(value) && length(value) == 1L && !is.na(value[[1L]]) && nzchar(as.character(value[[1L]]))
  }, logical(1L))]
  if (length(missing)) {
    stop(sprintf("Closeout phase is missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }

  runtime_root <- app_resolve_path(phase$runtime_root, must_work = TRUE)
  ranking_path <- file.path(runtime_root, "constrained_median_ranking.csv")
  selection_path <- file.path(runtime_root, "selection_decision.csv")
  if (!file.exists(ranking_path) || !file.exists(selection_path)) {
    stop(sprintf("Closeout evidence is incomplete for %s.", phase$phase_id), call. = FALSE)
  }
  ranking_sha256 <- app_sha256_file(ranking_path)
  if (!identical(ranking_sha256, as.character(phase$expected_ranking_sha256))) {
    stop(sprintf("Ranking hash drift for %s.", phase$phase_id), call. = FALSE)
  }

  ranking <- app_read_csv(ranking_path)
  selection <- app_read_csv(selection_path)
  if (nrow(selection) != 1L || !app_as_bool(selection$batch_complete[[1L]])) {
    stop(sprintf("Phase %s is not strictly complete.", phase$phase_id), call. = FALSE)
  }
  required_ranking <- c(
    "candidate_id", "screen_rank", "forecast_p50_check_loss_mean",
    "forecast_improvement_fraction", "observed_log1p_mae_all",
    "observed_log1p_mae_last200", "eligible_for_full7_review"
  )
  if (length(setdiff(required_ranking, names(ranking)))) {
    stop(sprintf("Ranking schema drift for %s.", phase$phase_id), call. = FALSE)
  }
  ranking <- ranking[order(as.integer(ranking$screen_rank), ranking$candidate_id), , drop = FALSE]
  completed <- as.integer(selection$completed_candidates[[1L]])
  total <- as.integer(selection$total_candidates[[1L]])
  rejected <- if ("preflight_rejected_candidates" %in% names(selection)) {
    as.integer(selection$preflight_rejected_candidates[[1L]])
  } else {
    total - completed
  }
  expected <- c(
    total = as.integer(phase$expected_total),
    completed = as.integer(phase$expected_completed),
    rejected = as.integer(phase$expected_preflight_rejected)
  )
  actual <- c(total = total, completed = completed, rejected = rejected)
  if (!identical(actual, expected) || nrow(ranking) != completed) {
    stop(sprintf("Terminal-count drift for %s.", phase$phase_id), call. = FALSE)
  }
  leader <- ranking[1L, , drop = FALSE]
  if (!identical(as.character(leader$candidate_id[[1L]]), as.character(phase$expected_leader))) {
    stop(sprintf("Leader drift for %s.", phase$phase_id), call. = FALSE)
  }

  data.frame(
    phase_id = as.character(phase$phase_id),
    runtime_root = runtime_root,
    total_candidates = total,
    completed_candidates = completed,
    preflight_rejected_candidates = rejected,
    eligible_candidates = sum(app_as_bool_vec(ranking$eligible_for_full7_review)),
    leader_candidate_id = as.character(leader$candidate_id[[1L]]),
    leader_forecast_p50_check_loss_mean = as.numeric(leader$forecast_p50_check_loss_mean[[1L]]),
    leader_forecast_improvement_fraction = as.numeric(leader$forecast_improvement_fraction[[1L]]),
    leader_observed_log1p_mae_all = as.numeric(leader$observed_log1p_mae_all[[1L]]),
    leader_observed_log1p_mae_last200 = as.numeric(leader$observed_log1p_mae_last200[[1L]]),
    ranking_path = ranking_path,
    ranking_sha256 = ranking_sha256,
    selection_path = selection_path,
    selection_sha256 = app_sha256_file(selection_path),
    stringsAsFactors = FALSE
  )
}

app_glofas_screening_program_closeout <- function(contract) {
  phases <- contract$phases %||% list()
  if (!length(phases)) stop("Closeout contract requires at least one phase.", call. = FALSE)
  summaries <- app_bind_rows_fill(lapply(phases, app_glofas_screening_program_phase_summary))

  baseline <- contract$baseline %||% list()
  baseline_score <- as.numeric(baseline$forecast_p50_check_loss_mean %||% NA_real_)
  promotion_threshold <- as.numeric(baseline$minimum_relative_improvement %||% NA_real_)
  if (!is.finite(baseline_score) || baseline_score <= 0 ||
      !is.finite(promotion_threshold) || promotion_threshold <= 0) {
    stop("Closeout contract requires a positive baseline score and promotion threshold.", call. = FALSE)
  }

  best_index <- which.min(summaries$leader_forecast_p50_check_loss_mean)
  best <- summaries[best_index, , drop = FALSE]
  mechanism <- contract$mechanism_audit %||% NULL
  mechanism_gate <- FALSE
  mechanism_path <- NA_character_
  mechanism_sha256 <- NA_character_
  paired_ci_upper <- NA_real_
  if (!is.null(mechanism)) {
    mechanism_path <- app_resolve_path(mechanism$path, must_work = TRUE)
    mechanism_sha256 <- app_sha256_file(mechanism_path)
    if (!identical(mechanism_sha256, as.character(mechanism$expected_sha256))) {
      stop("Mechanism-decision hash drift.", call. = FALSE)
    }
    mechanism_decision <- app_read_csv(mechanism_path)
    if (nrow(mechanism_decision) != 1L) stop("Mechanism decision must contain one row.", call. = FALSE)
    mechanism_gate <- app_as_bool(mechanism_decision$cold_confirmation_warranted[[1L]]) &&
      app_as_bool(mechanism_decision$full7_warranted[[1L]])
    paired_ci_upper <- as.numeric(mechanism_decision$paired_anchor_ci_upper[[1L]])
  }

  all_terminal <- all(
    summaries$total_candidates ==
      summaries$completed_candidates + summaries$preflight_rejected_candidates
  )
  any_eligible <- any(summaries$eligible_candidates > 0L)
  threshold_pass <- best$leader_forecast_improvement_fraction[[1L]] >= promotion_threshold
  promote <- all_terminal && any_eligible && threshold_pass && mechanism_gate
  decision <- if (promote) {
    "cold_confirm_before_full7_review"
  } else {
    "retain_fr09_and_close_local_desn_screening_program"
  }
  expected_decision <- as.character(contract$expected_decision %||% "")
  if (nzchar(expected_decision) && !identical(decision, expected_decision)) {
    stop("Program decision differs from the frozen expected decision.", call. = FALSE)
  }

  decision_row <- data.frame(
    program_id = as.character(contract$program_id %||% "glofas_screening_program"),
    baseline_candidate_id = as.character(baseline$candidate_id %||% ""),
    baseline_forecast_p50_check_loss_mean = baseline_score,
    promotion_threshold_fraction = promotion_threshold,
    phases_complete = all_terminal,
    total_candidates = sum(summaries$total_candidates),
    completed_candidates = sum(summaries$completed_candidates),
    preflight_rejected_candidates = sum(summaries$preflight_rejected_candidates),
    best_phase_id = best$phase_id[[1L]],
    best_candidate_id = best$leader_candidate_id[[1L]],
    best_forecast_p50_check_loss_mean = best$leader_forecast_p50_check_loss_mean[[1L]],
    best_improvement_fraction = best$leader_forecast_improvement_fraction[[1L]],
    promotion_threshold_pass = threshold_pass,
    any_full7_eligible_candidate = any_eligible,
    paired_anchor_ci_upper = paired_ci_upper,
    mechanism_gate_pass = mechanism_gate,
    cold_confirmation_warranted = promote,
    full7_warranted = promote,
    article_update_warranted = promote,
    decision = decision,
    next_scientific_stage = if (promote) {
      "cold_p50_confirmation"
    } else {
      "prospective_multicutoff_transition_or_input_hypothesis_only"
    },
    stringsAsFactors = FALSE
  )
  list(phases = summaries, decision = decision_row)
}

