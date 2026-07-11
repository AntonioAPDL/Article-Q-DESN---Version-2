# Phase 106 VB specification screening for the joint QDESN simulation study.

app_joint_qdesn_default_vb_spec_screening_dir <- function() {
  app_path("application/cache/joint_qdesn_vb_spec_screening_phase106_20260706")
}

app_joint_qdesn_default_vb_spec_screening_registry <- function(
  out_dir = app_joint_qdesn_default_vb_spec_screening_dir(),
  n_cores = 9L
) {
  candidate_ids <- c(
    "baseline_current",
    "rhs_tau0_0p5",
    "rhs_tau0_0p25",
    "rhs_tau0_0p5_alpha0p5"
  )
  data.frame(
    candidate_id = candidate_ids,
    candidate_label = c(
      "Current article baseline",
      "RHS tau0 0.5",
      "RHS tau0 0.25",
      "RHS tau0 0.5 with alpha sd 0.5"
    ),
    use_existing_artifacts = c(TRUE, FALSE, FALSE, FALSE),
    fit_dir = c(
      app_joint_qdesn_default_vb_fit_validation_dir(),
      file.path(out_dir, "candidates", candidate_ids[[2L]], "fit"),
      file.path(out_dir, "candidates", candidate_ids[[3L]], "fit"),
      file.path(out_dir, "candidates", candidate_ids[[4L]], "fit")
    ),
    forecast_dir = c(
      app_joint_qdesn_default_vb_forecast_validation_dir(),
      file.path(out_dir, "candidates", candidate_ids[[2L]], "forecast"),
      file.path(out_dir, "candidates", candidate_ids[[3L]], "forecast"),
      file.path(out_dir, "candidates", candidate_ids[[4L]], "forecast")
    ),
    vb_max_iter = c(240L, 480L, 480L, 480L),
    adaptive_vb_max_iter_grid = c("240,480", "480,960", "480,960", "480,960"),
    vb_tol = rep(1.0e-4, 4L),
    rhs_vb_inner = c(5L, 7L, 7L, 7L),
    tau0 = c(1, 0.5, 0.25, 0.5),
    zeta2 = c(Inf, Inf, Inf, Inf),
    a_sigma = rep(2, 4L),
    b_sigma = rep(1, 4L),
    alpha_prior_sd = c(1, 1, 1, 0.5),
    alpha_min_spacing = rep(0, 4L),
    gamma_init_policy = rep("default", 4L),
    review_adjustment_threshold = rep(1.0e-3, 4L),
    max_dense_dim = rep(300L, 4L),
    n_cores = rep(as.integer(n_cores), 4L),
    candidate_role = c("baseline_reference", rep("full_screening_candidate", 3L)),
    notes = c(
      "References the current article-scale fit and forecast artifacts without rerunning.",
      "Tests moderate additional RHS shrinkage with the explicit exAL alpha-prior contract.",
      "Tests aggressive RHS shrinkage for crossing and noise reduction.",
      "Tests moderate RHS shrinkage plus tighter empirical alpha prior for exAL/AL intercept stability."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_parse_iter_grid <- function(x) {
  vals <- trimws(strsplit(as.character(x)[[1L]], ",", fixed = TRUE)[[1L]])
  vals <- as.integer(suppressWarnings(as.numeric(vals[nzchar(vals)])))
  vals <- vals[is.finite(vals) & vals > 0L]
  if (!length(vals)) stop("adaptive_vb_max_iter_grid must contain positive integers.", call. = FALSE)
  vals
}

app_joint_qdesn_prepare_screening_registry <- function(registry) {
  if (!"gamma_init_policy" %in% names(registry)) registry$gamma_init_policy <- "default"
  if (!"scenario_ids" %in% names(registry)) registry$scenario_ids <- ""
  if (!"model_ids" %in% names(registry)) registry$model_ids <- ""
  registry$gamma_init_policy <- ifelse(
    is.na(registry$gamma_init_policy) | !nzchar(registry$gamma_init_policy),
    "default",
    as.character(registry$gamma_init_policy)
  )
  registry$scenario_ids <- ifelse(
    is.na(registry$scenario_ids),
    "",
    as.character(registry$scenario_ids)
  )
  registry$model_ids <- ifelse(
    is.na(registry$model_ids),
    "",
    as.character(registry$model_ids)
  )
  registry
}

app_joint_qdesn_validate_screening_registry <- function(
  registry,
  allow_alpha_prior_vectors = TRUE
) {
  registry <- app_joint_qdesn_prepare_screening_registry(registry)
  required <- c(
    "candidate_id", "candidate_label", "use_existing_artifacts", "fit_dir", "forecast_dir",
    "vb_max_iter", "adaptive_vb_max_iter_grid", "vb_tol", "rhs_vb_inner",
    "tau0", "zeta2", "a_sigma", "b_sigma", "alpha_prior_sd", "alpha_min_spacing",
    "review_adjustment_threshold", "max_dense_dim", "n_cores", "candidate_role", "notes"
  )
  app_check_required_columns(registry, required, "joint QDESN VB spec screening registry")
  if (any(!nzchar(registry$candidate_id)) || anyDuplicated(registry$candidate_id)) {
    stop("Screening candidate ids must be nonempty and unique.", call. = FALSE)
  }
  if (any(!registry$use_existing_artifacts %in% c(TRUE, FALSE))) {
    stop("use_existing_artifacts must be logical.", call. = FALSE)
  }
  positive_cols <- c(
    "vb_max_iter", "vb_tol", "rhs_vb_inner", "tau0", "a_sigma", "b_sigma",
    "review_adjustment_threshold", "max_dense_dim", "n_cores"
  )
  for (nm in positive_cols) {
    x <- suppressWarnings(as.numeric(registry[[nm]]))
    if (any(!is.finite(x) | x <= 0)) stop(sprintf("%s must be positive and finite.", nm), call. = FALSE)
  }
  for (ii in seq_len(nrow(registry))) {
    alpha_sd <- app_joint_qdesn_parse_numeric_vector(registry$alpha_prior_sd[[ii]], "alpha_prior_sd", allow_inf = TRUE)
    if (any((!is.finite(alpha_sd) & !is.infinite(alpha_sd)) | alpha_sd <= 0)) {
      stop("alpha_prior_sd values must be positive finite values or Inf.", call. = FALSE)
    }
    if (!isTRUE(allow_alpha_prior_vectors) && length(alpha_sd) != 1L) {
      stop(
        sprintf(
          "alpha_prior_sd must be scalar for mixed joint/independent screening candidate '%s'.",
          registry$candidate_id[[ii]]
        ),
        call. = FALSE
      )
    }
  }
  if (any(!registry$gamma_init_policy %in% app_joint_qdesn_gamma_init_policy_choices())) {
    stop(
      sprintf(
        "gamma_init_policy must be one of: %s.",
        paste(app_joint_qdesn_gamma_init_policy_choices(), collapse = ", ")
      ),
      call. = FALSE
    )
  }
  available_models <- app_joint_qdesn_simulation_model_specs()$model_id
  for (ii in seq_len(nrow(registry))) {
    model_ids <- app_joint_qdesn_parse_id_csv(registry$model_ids[[ii]])
    missing_models <- setdiff(model_ids, available_models)
    if (length(missing_models)) {
      stop(
        sprintf(
          "Unknown model_ids for screening candidate '%s': %s.",
          registry$candidate_id[[ii]],
          paste(missing_models, collapse = ", ")
        ),
        call. = FALSE
      )
    }
  }
  for (ii in seq_len(nrow(registry))) app_joint_qdesn_parse_iter_grid(registry$adaptive_vb_max_iter_grid[[ii]])
  invisible(TRUE)
}

app_joint_qdesn_screening_write_csv <- function(x, path) {
  app_ensure_dir(dirname(path))
  utils::write.csv(x, path, row.names = FALSE, na = "")
  normalizePath(path, mustWork = TRUE)
}

app_joint_qdesn_screening_verify_manifest <- function(dir, candidate_id, stage) {
  manifest_path <- file.path(dir, "artifact_manifest.csv")
  if (!file.exists(manifest_path)) {
    return(data.frame(
      candidate_id = candidate_id,
      stage = stage,
      label = "artifact_manifest",
      relative_path = "artifact_manifest.csv",
      path = normalizePath(manifest_path, mustWork = FALSE),
      exists = FALSE,
      declared_sha256 = NA_character_,
      actual_sha256 = NA_character_,
      declared_size_bytes = NA_real_,
      actual_size_bytes = NA_real_,
      status = "fail",
      stringsAsFactors = FALSE
    ))
  }
  manifest <- app_read_csv(manifest_path)
  app_check_required_columns(manifest, c("label", "relative_path", "size_bytes", "sha256"), "screening nested manifest")
  app_joint_qdesn_bind_rows(lapply(seq_len(nrow(manifest)), function(ii) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    exists <- file.exists(path)
    actual_sha <- if (exists) app_sha256_file(path) else NA_character_
    actual_size <- if (exists) as.numeric(file.info(path)$size) else NA_real_
    data.frame(
      candidate_id = candidate_id,
      stage = stage,
      label = manifest$label[[ii]],
      relative_path = manifest$relative_path[[ii]],
      path = normalizePath(path, mustWork = FALSE),
      exists = exists,
      declared_sha256 = manifest$sha256[[ii]],
      actual_sha256 = actual_sha,
      declared_size_bytes = as.numeric(manifest$size_bytes[[ii]]),
      actual_size_bytes = actual_size,
      status = if (exists &&
        identical(tolower(actual_sha), tolower(manifest$sha256[[ii]])) &&
        identical(as.numeric(actual_size), as.numeric(manifest$size_bytes[[ii]]))) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_qdesn_screening_candidate_dirs <- function(registry) {
  data.frame(
    candidate_id = registry$candidate_id,
    candidate_label = registry$candidate_label,
    use_existing_artifacts = registry$use_existing_artifacts,
    fit_dir = normalizePath(registry$fit_dir, mustWork = FALSE),
    forecast_dir = normalizePath(registry$forecast_dir, mustWork = FALSE),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_screening_read_stage <- function(dir, stage, stem) {
  filename <- switch(
    stem,
    assessment = if (stage == "fit") "fit_validation_assessment.csv" else "forecast_validation_assessment.csv",
    truth = if (stage == "fit") "fit_truth_comparison.csv" else "forecast_truth_comparison.csv",
    check = "check_loss_summary.csv",
    crps = "crps_grid_summary.csv",
    hit = "hit_rate_summary.csv",
    interval = "interval_summary.csv",
    vb = "vb_convergence_audit.csv",
    runtime = "runtime_summary.csv",
    stop(sprintf("Unknown screening stage stem '%s'.", stem), call. = FALSE)
  )
  app_read_csv(file.path(dir, filename))
}

app_joint_qdesn_screening_empty_failure_rows <- function() {
  data.frame(
    candidate_id = character(),
    candidate_label = character(),
    candidate_role = character(),
    stage = character(),
    validation_label = character(),
    scenario_id = character(),
    worker_index = integer(),
    worker_status = character(),
    error_class = character(),
    error_message = character(),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_screening_stage_failures <- function(dir, stage, candidate_row) {
  path <- file.path(dir, "scenario_failure.csv")
  if (!file.exists(path)) return(app_joint_qdesn_screening_empty_failure_rows())
  failures <- app_read_csv(path)
  if (!nrow(failures)) return(app_joint_qdesn_screening_empty_failure_rows())
  cbind(
    app_joint_qdesn_screening_candidate_meta(
      candidate_row,
      c("candidate_id", "candidate_label", "candidate_role"),
      nrow(failures)
    ),
    data.frame(stage = stage, failures, stringsAsFactors = FALSE)
  )
}

app_joint_qdesn_screening_candidate_meta <- function(candidate_row, cols, n) {
  meta <- candidate_row[, cols, drop = FALSE]
  row.names(meta) <- NULL
  meta[rep(1L, n), , drop = FALSE]
}

app_joint_qdesn_screening_model_metrics <- function(dir, stage, candidate_row) {
  truth <- app_joint_qdesn_screening_read_stage(dir, stage, "truth")
  assessment <- app_joint_qdesn_screening_read_stage(dir, stage, "assessment")
  check <- app_joint_qdesn_screening_read_stage(dir, stage, "check")
  crps <- app_joint_qdesn_screening_read_stage(dir, stage, "crps")
  hit <- app_joint_qdesn_screening_read_stage(dir, stage, "hit")
  interval <- app_joint_qdesn_screening_read_stage(dir, stage, "interval")
  by_model <- c("model_id", "display_label", "likelihood", "fit_structure")
  truth_m <- aggregate(cbind(truth_abs_error, truth_sq_error) ~ model_id + display_label + likelihood + fit_structure, truth, mean, na.rm = TRUE)
  truth_m$truth_rmse <- sqrt(truth_m$truth_sq_error)
  names(truth_m)[names(truth_m) == "truth_abs_error"] <- "truth_mae"
  check_m <- aggregate(check_loss_mean ~ model_id + display_label + likelihood + fit_structure, check, mean, na.rm = TRUE)
  crps_m <- aggregate(crps_grid_mean ~ model_id + display_label + likelihood + fit_structure, crps, mean, na.rm = TRUE)
  hit_m <- aggregate(abs_hit_rate_error ~ model_id + display_label + likelihood + fit_structure, hit, mean, na.rm = TRUE)
  interval_m <- aggregate(cbind(abs_coverage_error, interval_width_mean, interval_score_mean) ~ model_id + display_label + likelihood + fit_structure, interval, mean, na.rm = TRUE)
  cross_m <- aggregate(cbind(raw_crossing_pairs, contract_crossing_pairs, reached_max_iter, elapsed_seconds) ~ model_id + display_label + likelihood + fit_structure, assessment, sum, na.rm = TRUE)
  adj_m <- aggregate(max_abs_adjustment ~ model_id + display_label + likelihood + fit_structure, assessment, max, na.rm = TRUE)
  rate_m <- aggregate(adjustment_rate ~ model_id + display_label + likelihood + fit_structure, assessment, mean, na.rm = TRUE)
  finite_m <- aggregate(cbind(finite_quantiles, finite_scores) ~ model_id + display_label + likelihood + fit_structure, assessment, all)
  gate_m <- aggregate(gate_status ~ model_id + display_label + likelihood + fit_structure, assessment, function(x) paste(sort(unique(x)), collapse = ";"))
  out <- Reduce(function(x, y) merge(x, y, by = by_model, all = TRUE), list(
    truth_m, check_m, crps_m, hit_m, interval_m, cross_m, adj_m, rate_m, finite_m, gate_m
  ))
  cbind(
    app_joint_qdesn_screening_candidate_meta(candidate_row, c(
      "candidate_id", "candidate_label", "candidate_role", "tau0", "zeta2",
      "alpha_prior_sd", "alpha_min_spacing", "gamma_init_policy", "scenario_ids", "model_ids",
      "vb_max_iter", "adaptive_vb_max_iter_grid", "rhs_vb_inner"
    ), nrow(out)),
    data.frame(stage = stage, out, stringsAsFactors = FALSE)
  )
}

app_joint_qdesn_screening_scenario_metrics <- function(dir, stage, candidate_row) {
  truth <- app_joint_qdesn_screening_read_stage(dir, stage, "truth")
  assessment <- app_joint_qdesn_screening_read_stage(dir, stage, "assessment")
  check <- app_joint_qdesn_screening_read_stage(dir, stage, "check")
  by_sm <- c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure")
  truth_m <- aggregate(cbind(truth_abs_error, truth_sq_error) ~ scenario_id + model_id + display_label + likelihood + fit_structure, truth, mean, na.rm = TRUE)
  truth_m$truth_rmse <- sqrt(truth_m$truth_sq_error)
  names(truth_m)[names(truth_m) == "truth_abs_error"] <- "truth_mae"
  check_m <- aggregate(check_loss_mean ~ scenario_id + model_id + display_label + likelihood + fit_structure, check, mean, na.rm = TRUE)
  assess_m <- assessment[, c(by_sm, "gate_status", "raw_crossing_pairs", "contract_crossing_pairs", "max_abs_adjustment", "adjustment_rate", "reached_max_iter", "status_reason"), drop = FALSE]
  out <- Reduce(function(x, y) merge(x, y, by = by_sm, all = TRUE), list(truth_m, check_m, assess_m))
  cbind(
    app_joint_qdesn_screening_candidate_meta(
      candidate_row,
      c("candidate_id", "candidate_label", "candidate_role", "tau0", "zeta2", "alpha_prior_sd", "alpha_min_spacing", "gamma_init_policy"),
      nrow(out)
    ),
    data.frame(stage = stage, out, stringsAsFactors = FALSE)
  )
}

app_joint_qdesn_screening_tau_metrics <- function(dir, stage, candidate_row) {
  truth <- app_joint_qdesn_screening_read_stage(dir, stage, "truth")
  check <- app_joint_qdesn_screening_read_stage(dir, stage, "check")
  by_tau <- c("model_id", "display_label", "likelihood", "fit_structure", "tau")
  truth_m <- aggregate(cbind(truth_abs_error, truth_sq_error) ~ model_id + display_label + likelihood + fit_structure + tau, truth, mean, na.rm = TRUE)
  truth_m$truth_rmse <- sqrt(truth_m$truth_sq_error)
  names(truth_m)[names(truth_m) == "truth_abs_error"] <- "truth_mae"
  check_m <- aggregate(check_loss_mean ~ model_id + display_label + likelihood + fit_structure + tau, check, mean, na.rm = TRUE)
  out <- merge(truth_m, check_m, by = by_tau, all = TRUE)
  cbind(
    app_joint_qdesn_screening_candidate_meta(
      candidate_row,
      c("candidate_id", "candidate_label", "candidate_role", "tau0", "zeta2", "alpha_prior_sd", "alpha_min_spacing", "gamma_init_policy"),
      nrow(out)
    ),
    data.frame(stage = stage, out, stringsAsFactors = FALSE)
  )
}

app_joint_qdesn_screening_health <- function(
  candidate_dirs,
  manifest_verification,
  fit_model,
  forecast_model,
  fit_scenario,
  forecast_scenario,
  scenario_failures,
  catastrophic_truth_mae = 5
) {
  rows <- lapply(seq_len(nrow(candidate_dirs)), function(ii) {
    cid <- candidate_dirs$candidate_id[[ii]]
    mv <- manifest_verification[manifest_verification$candidate_id == cid, , drop = FALSE]
    fit_m <- fit_model[fit_model$candidate_id == cid, , drop = FALSE]
    fc_m <- forecast_model[forecast_model$candidate_id == cid, , drop = FALSE]
    fc_sc <- forecast_scenario[forecast_scenario$candidate_id == cid, , drop = FALSE]
    sf <- scenario_failures[scenario_failures$candidate_id == cid, , drop = FALSE]
    catastrophic_rows <- sum(fc_sc$truth_mae > catastrophic_truth_mae, na.rm = TRUE)
    fail <- any(mv$status != "pass") ||
      nrow(sf) > 0L ||
      any(fit_m$gate_status == "fail" | fc_m$gate_status == "fail", na.rm = TRUE) ||
      any(fit_m$contract_crossing_pairs > 0 | fc_m$contract_crossing_pairs > 0, na.rm = TRUE) ||
      any(!fit_m$finite_quantiles | !fit_m$finite_scores | !fc_m$finite_quantiles | !fc_m$finite_scores, na.rm = TRUE) ||
      catastrophic_rows > 0L
    review <- !fail && (
      any(fit_m$gate_status == "review" | fc_m$gate_status == "review", na.rm = TRUE) ||
        any(fit_m$raw_crossing_pairs > 0 | fc_m$raw_crossing_pairs > 0, na.rm = TRUE) ||
        any(fit_m$reached_max_iter > 0 | fc_m$reached_max_iter > 0, na.rm = TRUE)
    )
    data.frame(
      candidate_id = cid,
      candidate_label = candidate_dirs$candidate_label[[ii]],
      manifest_status = if (all(mv$status == "pass")) "pass" else "fail",
      fit_models = nrow(fit_m),
      forecast_models = nrow(fc_m),
      scenario_worker_failures = nrow(sf),
      fit_worker_failures = sum(sf$stage == "fit", na.rm = TRUE),
      forecast_worker_failures = sum(sf$stage == "forecast", na.rm = TRUE),
      fit_fail_models = sum(fit_m$gate_status == "fail", na.rm = TRUE),
      forecast_fail_models = sum(fc_m$gate_status == "fail", na.rm = TRUE),
      fit_raw_crossings = sum(fit_m$raw_crossing_pairs, na.rm = TRUE),
      forecast_raw_crossings = sum(fc_m$raw_crossing_pairs, na.rm = TRUE),
      contract_crossings = sum(fit_m$contract_crossing_pairs, fc_m$contract_crossing_pairs, na.rm = TRUE),
      max_forecast_adjustment = max(fc_m$max_abs_adjustment, na.rm = TRUE),
      max_forecast_truth_mae = max(fc_sc$truth_mae, na.rm = TRUE),
      catastrophic_rows = catastrophic_rows,
      fit_reached_max_iter = sum(fit_m$reached_max_iter, na.rm = TRUE),
      forecast_reached_max_iter = sum(fc_m$reached_max_iter, na.rm = TRUE),
      elapsed_seconds = sum(fit_m$elapsed_seconds, fc_m$elapsed_seconds, na.rm = TRUE),
      gate_status = if (fail) "fail" else if (review) "review" else "pass",
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_screening_scorecard <- function(health, fit_model, forecast_model, forecast_scenario) {
  rows <- lapply(seq_len(nrow(health)), function(ii) {
    cid <- health$candidate_id[[ii]]
    fit_m <- fit_model[fit_model$candidate_id == cid, , drop = FALSE]
    fc_m <- forecast_model[forecast_model$candidate_id == cid, , drop = FALSE]
    fc_sc <- forecast_scenario[forecast_scenario$candidate_id == cid, , drop = FALSE]
    ind_exal <- fc_m[fc_m$model_id == "exqdesn_rhs_independent_vb", , drop = FALSE]
    joint_al <- fc_m[fc_m$model_id == "joint_qdesn_rhs_vb", , drop = FALSE]
    score <- mean(fc_m$truth_mae, na.rm = TRUE) +
      0.50 * mean(fit_m$truth_mae, na.rm = TRUE) +
      0.001 * sum(fc_m$raw_crossing_pairs, na.rm = TRUE) +
      0.010 * min(max(fc_m$max_abs_adjustment, na.rm = TRUE), 10) +
      0.005 * sum(fc_m$reached_max_iter, na.rm = TRUE)
    data.frame(
      candidate_id = cid,
      candidate_label = health$candidate_label[[ii]],
      gate_status = health$gate_status[[ii]],
      screening_score = score,
      mean_fit_truth_mae = mean(fit_m$truth_mae, na.rm = TRUE),
      mean_forecast_truth_mae = mean(fc_m$truth_mae, na.rm = TRUE),
      joint_qdesn_forecast_truth_mae = if (nrow(joint_al)) joint_al$truth_mae[[1L]] else NA_real_,
      independent_exqdesn_forecast_truth_mae = if (nrow(ind_exal)) ind_exal$truth_mae[[1L]] else NA_real_,
      max_scenario_forecast_truth_mae = max(fc_sc$truth_mae, na.rm = TRUE),
      forecast_raw_crossings = health$forecast_raw_crossings[[ii]],
      max_forecast_adjustment = health$max_forecast_adjustment[[ii]],
      elapsed_minutes = health$elapsed_seconds[[ii]] / 60,
      recommendation_class = if (health$gate_status[[ii]] == "pass") {
        "ready_for_article_candidate"
      } else if (health$gate_status[[ii]] == "review") {
        "usable_with_review"
      } else {
        "not_article_ready"
      },
      stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  out$rank <- rank(ifelse(out$gate_status == "fail", Inf, out$screening_score), ties.method = "first")
  out[order(out$rank, out$screening_score), , drop = FALSE]
}

app_joint_qdesn_screening_selected_spec <- function(scorecard) {
  eligible <- scorecard[scorecard$gate_status %in% c("pass", "review"), , drop = FALSE]
  if (!nrow(eligible)) eligible <- scorecard
  best <- eligible[order(eligible$rank, eligible$screening_score), , drop = FALSE][1L, , drop = FALSE]
  best$selected <- TRUE
  best$next_action <- if (best$gate_status[[1L]] == "pass") {
    "Freeze this VB specification, regenerate article evidence assets, then launch VB-initialized MCMC references."
  } else if (best$gate_status[[1L]] == "review") {
    "Review raw crossings, max-iteration status, and independent exQDESN behavior before freezing article assets."
  } else {
    "No candidate is article-ready; prioritize exAL stabilization before MCMC."
  }
  best
}

app_joint_qdesn_screening_readme <- function(health, selected, candidate_registry) {
  c(
    "# Joint QDESN Phase 106 VB Specification Screening",
    "",
    "This directory contains the Phase 106 VB specification screening artifacts.",
    "The screening reuses the frozen joint QDESN synthetic fixtures and compares fit-window recovery with no-refit held-out forecast validation.",
    "",
    sprintf("Candidates declared: %d", nrow(candidate_registry)),
    sprintf("Completed candidates in health table: %d", nrow(health)),
    "",
    "Selected candidate:",
    "",
    sprintf("- `%s`: %s", selected$candidate_id[[1L]], selected$next_action[[1L]]),
    "",
    "Gate counts:",
    paste(capture.output(print(table(health$gate_status))), collapse = "\n"),
    "",
    "MCMC remains deferred until a VB specification is frozen."
  )
}

app_joint_qdesn_audit_vb_spec_screening <- function(
  out_dir = app_joint_qdesn_default_vb_spec_screening_dir(),
  candidate_registry = NULL,
  catastrophic_truth_mae = 5
) {
  out_dir <- normalizePath(out_dir, mustWork = TRUE)
  if (is.null(candidate_registry)) {
    candidate_registry <- app_read_csv(file.path(out_dir, "candidate_registry.csv"))
  }
  candidate_registry <- app_joint_qdesn_prepare_screening_registry(candidate_registry)
  app_joint_qdesn_validate_screening_registry(candidate_registry, allow_alpha_prior_vectors = FALSE)
  candidate_dirs <- app_joint_qdesn_screening_candidate_dirs(candidate_registry)
  manifest_verification <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(candidate_dirs)), function(ii) {
    cid <- candidate_dirs$candidate_id[[ii]]
    app_joint_qdesn_bind_rows(list(
      app_joint_qdesn_screening_verify_manifest(candidate_dirs$fit_dir[[ii]], cid, "fit"),
      app_joint_qdesn_screening_verify_manifest(candidate_dirs$forecast_dir[[ii]], cid, "forecast")
    ))
  }))
  complete <- aggregate(status ~ candidate_id, manifest_verification, function(x) all(x == "pass"))
  complete_ids <- complete$candidate_id[complete$status]
  if (!length(complete_ids)) stop("No complete screening candidates available for audit.", call. = FALSE)
  fit_model <- app_joint_qdesn_bind_rows(lapply(complete_ids, function(cid) {
    ii <- match(cid, candidate_registry$candidate_id)
    app_joint_qdesn_screening_model_metrics(candidate_registry$fit_dir[[ii]], "fit", candidate_registry[ii, , drop = FALSE])
  }))
  forecast_model <- app_joint_qdesn_bind_rows(lapply(complete_ids, function(cid) {
    ii <- match(cid, candidate_registry$candidate_id)
    app_joint_qdesn_screening_model_metrics(candidate_registry$forecast_dir[[ii]], "forecast", candidate_registry[ii, , drop = FALSE])
  }))
  fit_scenario <- app_joint_qdesn_bind_rows(lapply(complete_ids, function(cid) {
    ii <- match(cid, candidate_registry$candidate_id)
    app_joint_qdesn_screening_scenario_metrics(candidate_registry$fit_dir[[ii]], "fit", candidate_registry[ii, , drop = FALSE])
  }))
  forecast_scenario <- app_joint_qdesn_bind_rows(lapply(complete_ids, function(cid) {
    ii <- match(cid, candidate_registry$candidate_id)
    app_joint_qdesn_screening_scenario_metrics(candidate_registry$forecast_dir[[ii]], "forecast", candidate_registry[ii, , drop = FALSE])
  }))
  forecast_tau <- app_joint_qdesn_bind_rows(lapply(complete_ids, function(cid) {
    ii <- match(cid, candidate_registry$candidate_id)
    app_joint_qdesn_screening_tau_metrics(candidate_registry$forecast_dir[[ii]], "forecast", candidate_registry[ii, , drop = FALSE])
  }))
  scenario_failures <- app_joint_qdesn_bind_rows(lapply(complete_ids, function(cid) {
    ii <- match(cid, candidate_registry$candidate_id)
    app_joint_qdesn_bind_rows(list(
      app_joint_qdesn_screening_stage_failures(candidate_registry$fit_dir[[ii]], "fit", candidate_registry[ii, , drop = FALSE]),
      app_joint_qdesn_screening_stage_failures(candidate_registry$forecast_dir[[ii]], "forecast", candidate_registry[ii, , drop = FALSE])
    ))
  }))
  health <- app_joint_qdesn_screening_health(
    candidate_dirs[candidate_dirs$candidate_id %in% complete_ids, , drop = FALSE],
    manifest_verification,
    fit_model,
    forecast_model,
    fit_scenario,
    forecast_scenario,
    scenario_failures,
    catastrophic_truth_mae
  )
  scorecard <- app_joint_qdesn_screening_scorecard(health, fit_model, forecast_model, forecast_scenario)
  selected <- app_joint_qdesn_screening_selected_spec(scorecard)
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qdesn_screening_readme(health, selected, candidate_registry), readme_path, useBytes = TRUE)
  run_config <- data.frame(
    run_id = "joint_qdesn_vb_spec_screening_phase106",
    out_dir = out_dir,
    n_declared_candidates = nrow(candidate_registry),
    n_completed_candidates = length(complete_ids),
    catastrophic_truth_mae = catastrophic_truth_mae,
    stringsAsFactors = FALSE
  )
  paths <- c(
    candidate_registry = app_joint_qdesn_screening_write_csv(candidate_registry, file.path(out_dir, "candidate_registry.csv")),
    screening_run_config = app_joint_qdesn_screening_write_csv(run_config, file.path(out_dir, "screening_run_config.csv")),
    candidate_artifact_dirs = app_joint_qdesn_screening_write_csv(candidate_dirs, file.path(out_dir, "candidate_artifact_dirs.csv")),
    candidate_manifest_verification = app_joint_qdesn_screening_write_csv(manifest_verification, file.path(out_dir, "candidate_manifest_verification.csv")),
    fit_model_metric_summary = app_joint_qdesn_screening_write_csv(fit_model, file.path(out_dir, "fit_model_metric_summary.csv")),
    forecast_model_metric_summary = app_joint_qdesn_screening_write_csv(forecast_model, file.path(out_dir, "forecast_model_metric_summary.csv")),
    fit_scenario_metric_summary = app_joint_qdesn_screening_write_csv(fit_scenario, file.path(out_dir, "fit_scenario_metric_summary.csv")),
    forecast_scenario_metric_summary = app_joint_qdesn_screening_write_csv(forecast_scenario, file.path(out_dir, "forecast_scenario_metric_summary.csv")),
    forecast_tau_metric_summary = app_joint_qdesn_screening_write_csv(forecast_tau, file.path(out_dir, "forecast_tau_metric_summary.csv")),
    scenario_failure_summary = app_joint_qdesn_screening_write_csv(scenario_failures, file.path(out_dir, "scenario_failure_summary.csv")),
    screening_health_summary = app_joint_qdesn_screening_write_csv(health, file.path(out_dir, "screening_health_summary.csv")),
    candidate_scorecard = app_joint_qdesn_screening_write_csv(scorecard, file.path(out_dir, "candidate_scorecard.csv")),
    selected_spec_recommendation = app_joint_qdesn_screening_write_csv(selected, file.path(out_dir, "selected_spec_recommendation.csv")),
    provenance = app_joint_qdesn_screening_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = out_dir,
    candidate_registry = candidate_registry,
    candidate_dirs = candidate_dirs,
    manifest_verification = manifest_verification,
    scenario_failures = scenario_failures,
    health = health,
    scorecard = scorecard,
    selected = selected,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path)
  )
}

app_joint_qdesn_run_vb_spec_screening <- function(
  out_dir = app_joint_qdesn_default_vb_spec_screening_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  candidate_registry = NULL,
  candidate_ids = NULL,
  n_cores = 9L,
  reuse_completed = TRUE,
  audit_only = FALSE,
  catastrophic_truth_mae = 5
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  if (is.null(candidate_registry)) {
    candidate_registry <- app_joint_qdesn_default_vb_spec_screening_registry(out_dir = out_dir, n_cores = n_cores)
  }
  candidate_registry <- app_joint_qdesn_prepare_screening_registry(candidate_registry)
  if (!is.null(candidate_ids) && length(candidate_ids)) {
    missing <- setdiff(candidate_ids, candidate_registry$candidate_id)
    if (length(missing)) stop("Unknown candidate_ids: ", paste(missing, collapse = ", "), call. = FALSE)
    candidate_registry <- candidate_registry[candidate_registry$candidate_id %in% candidate_ids, , drop = FALSE]
  }
  candidate_registry$n_cores <- as.integer(n_cores)
  app_joint_qdesn_validate_screening_registry(candidate_registry, allow_alpha_prior_vectors = FALSE)
  app_joint_qdesn_screening_write_csv(candidate_registry, file.path(out_dir, "candidate_registry.csv"))
  if (!isTRUE(audit_only)) {
    for (ii in seq_len(nrow(candidate_registry))) {
      cand <- candidate_registry[ii, , drop = FALSE]
      if (isTRUE(cand$use_existing_artifacts[[1L]])) next
      fit_manifest <- file.path(cand$fit_dir[[1L]], "artifact_manifest.csv")
      forecast_manifest <- file.path(cand$forecast_dir[[1L]], "artifact_manifest.csv")
      if (isTRUE(reuse_completed) && file.exists(fit_manifest) && file.exists(forecast_manifest)) next
      message(sprintf("Running Phase 106 candidate '%s' fit validation.", cand$candidate_id[[1L]]))
      app_joint_qdesn_run_vb_fit_validation(
        out_dir = cand$fit_dir[[1L]],
        fixture_dir = fixture_dir,
        vb_max_iter = as.integer(cand$vb_max_iter[[1L]]),
        adaptive_vb_max_iter_grid = app_joint_qdesn_parse_iter_grid(cand$adaptive_vb_max_iter_grid[[1L]]),
        vb_tol = as.numeric(cand$vb_tol[[1L]]),
        rhs_vb_inner = as.integer(cand$rhs_vb_inner[[1L]]),
        tau0 = as.numeric(cand$tau0[[1L]]),
        zeta2 = as.numeric(cand$zeta2[[1L]]),
        a_sigma = as.numeric(cand$a_sigma[[1L]]),
        b_sigma = as.numeric(cand$b_sigma[[1L]]),
        alpha_prior_sd = app_joint_qdesn_parse_numeric_vector(cand$alpha_prior_sd[[1L]], "alpha_prior_sd", allow_inf = TRUE),
        alpha_min_spacing = as.numeric(cand$alpha_min_spacing[[1L]]),
        gamma_init_policy = cand$gamma_init_policy[[1L]],
        scenario_ids = app_joint_qdesn_parse_id_csv(cand$scenario_ids[[1L]]),
        model_ids = app_joint_qdesn_parse_id_csv(cand$model_ids[[1L]]),
        review_adjustment_threshold = as.numeric(cand$review_adjustment_threshold[[1L]]),
        max_dense_dim = as.integer(cand$max_dense_dim[[1L]]),
        n_cores = as.integer(cand$n_cores[[1L]])
      )
      message(sprintf("Running Phase 106 candidate '%s' forecast validation.", cand$candidate_id[[1L]]))
      app_joint_qdesn_run_vb_forecast_validation(
        out_dir = cand$forecast_dir[[1L]],
        fixture_dir = fixture_dir,
        vb_max_iter = as.integer(cand$vb_max_iter[[1L]]),
        adaptive_vb_max_iter_grid = app_joint_qdesn_parse_iter_grid(cand$adaptive_vb_max_iter_grid[[1L]]),
        vb_tol = as.numeric(cand$vb_tol[[1L]]),
        rhs_vb_inner = as.integer(cand$rhs_vb_inner[[1L]]),
        tau0 = as.numeric(cand$tau0[[1L]]),
        zeta2 = as.numeric(cand$zeta2[[1L]]),
        a_sigma = as.numeric(cand$a_sigma[[1L]]),
        b_sigma = as.numeric(cand$b_sigma[[1L]]),
        alpha_prior_sd = app_joint_qdesn_parse_numeric_vector(cand$alpha_prior_sd[[1L]], "alpha_prior_sd", allow_inf = TRUE),
        alpha_min_spacing = as.numeric(cand$alpha_min_spacing[[1L]]),
        gamma_init_policy = cand$gamma_init_policy[[1L]],
        scenario_ids = app_joint_qdesn_parse_id_csv(cand$scenario_ids[[1L]]),
        model_ids = app_joint_qdesn_parse_id_csv(cand$model_ids[[1L]]),
        review_adjustment_threshold = as.numeric(cand$review_adjustment_threshold[[1L]]),
        max_dense_dim = as.integer(cand$max_dense_dim[[1L]]),
        n_cores = as.integer(cand$n_cores[[1L]])
      )
    }
  }
  app_joint_qdesn_audit_vb_spec_screening(
    out_dir = out_dir,
    candidate_registry = candidate_registry,
    catastrophic_truth_mae = catastrophic_truth_mae
  )
}
