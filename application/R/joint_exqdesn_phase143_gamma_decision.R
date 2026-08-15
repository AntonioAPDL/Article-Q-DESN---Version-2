# Phase143 sampled-gamma decision freeze for joint exQDESN validation.

app_joint_exqdesn_phase143_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase143_gamma_decision_freeze_20260723")
}

app_joint_exqdesn_phase143_required_packet_files <- function() {
  c(
    "artifact_manifest.csv",
    "run_config.csv",
    "phase136_case_assessment.csv",
    "phase136_best_variant_by_case.csv",
    "phase136_chain_jobs.csv",
    "phase136_chain_worker_failures.csv",
    "phase136_case_variant_prep_failures.csv",
    "runtime_summary.csv"
  )
}

app_joint_exqdesn_phase143_num <- function(x) {
  suppressWarnings(as.numeric(x))
}

app_joint_exqdesn_phase143_safe_sum <- function(x) {
  x <- app_joint_exqdesn_phase143_num(x)
  sum(x, na.rm = TRUE)
}

app_joint_exqdesn_phase143_safe_mean <- function(x) {
  x <- app_joint_exqdesn_phase143_num(x)
  if (!length(x) || all(is.na(x))) return(NA_real_)
  mean(x, na.rm = TRUE)
}

app_joint_exqdesn_phase143_safe_max <- function(x) {
  x <- app_joint_exqdesn_phase143_num(x)
  if (!length(x) || all(is.na(x))) return(NA_real_)
  max(x, na.rm = TRUE)
}

app_joint_exqdesn_phase143_safe_min <- function(x) {
  x <- app_joint_exqdesn_phase143_num(x)
  if (!length(x) || all(is.na(x))) return(NA_real_)
  min(x, na.rm = TRUE)
}

app_joint_exqdesn_phase143_has_cols <- function(x, cols, label) {
  missing <- setdiff(cols, names(x))
  if (length(missing)) {
    stop(sprintf("%s is missing required columns: %s", label, paste(missing, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}

app_joint_exqdesn_phase143_numericize_assessment <- function(d) {
  numeric_cols <- c(
    "mcmc_fit_truth_mae",
    "mcmc_forecast_truth_mae",
    "mcmc_fit_check_loss_mean",
    "mcmc_forecast_check_loss_mean",
    "mcmc_fit_raw_crossing_pairs",
    "mcmc_forecast_raw_crossing_pairs",
    "mcmc_fit_contract_crossing_pairs",
    "mcmc_forecast_contract_crossing_pairs",
    "max_rhat",
    "min_rough_ess_total",
    "max_gamma_rhat",
    "min_gamma_rough_ess_total",
    "max_gamma_chain_mean_gap",
    "max_gamma_lag1_autocorrelation",
    "max_sigma_upper_bound_hit_fraction"
  )
  for (nm in intersect(numeric_cols, names(d))) d[[nm]] <- app_joint_exqdesn_phase143_num(d[[nm]])
  d
}

app_joint_exqdesn_phase143_load_packet <- function(dir, packet_id, packet_role) {
  dir <- normalizePath(dir, mustWork = TRUE)
  required <- app_joint_exqdesn_phase143_required_packet_files()
  missing <- required[!file.exists(file.path(dir, required))]
  if (length(missing)) {
    stop(sprintf("Phase143 source packet '%s' is missing required files: %s", packet_id, paste(missing, collapse = ", ")), call. = FALSE)
  }
  manifest <- app_joint_qdesn_phase108_manifest_verify(dir, packet_id)
  assessment <- app_joint_exqdesn_phase143_numericize_assessment(app_read_csv(file.path(dir, "phase136_case_assessment.csv")))
  best <- app_joint_exqdesn_phase143_numericize_assessment(app_read_csv(file.path(dir, "phase136_best_variant_by_case.csv")))
  app_joint_exqdesn_phase143_has_cols(
    assessment,
    c("case_id", "scenario_id", "model_id", "variant_id", "phase136_gate_status",
      "mcmc_forecast_truth_mae", "mcmc_fit_truth_mae",
      "mcmc_forecast_contract_crossing_pairs", "mcmc_fit_contract_crossing_pairs"),
    sprintf("%s phase136_case_assessment.csv", packet_id)
  )
  app_joint_exqdesn_phase143_has_cols(
    best,
    c("case_id", "variant_id", "phase136_gate_status", "mcmc_forecast_truth_mae"),
    sprintf("%s phase136_best_variant_by_case.csv", packet_id)
  )
  list(
    packet_id = packet_id,
    packet_role = packet_role,
    dir = dir,
    manifest = manifest,
    run_config = app_read_csv(file.path(dir, "run_config.csv")),
    assessment = assessment,
    best = best,
    chain_jobs = app_read_csv(file.path(dir, "phase136_chain_jobs.csv")),
    worker_failures = app_read_csv(file.path(dir, "phase136_chain_worker_failures.csv")),
    prep_failures = app_read_csv(file.path(dir, "phase136_case_variant_prep_failures.csv")),
    runtime = app_read_csv(file.path(dir, "runtime_summary.csv"))
  )
}

app_joint_exqdesn_phase143_packet_health <- function(packet) {
  d <- packet$assessment
  worker_failures <- packet$worker_failures
  prep_failures <- packet$prep_failures
  chain_jobs <- packet$chain_jobs
  data.frame(
    packet_id = packet$packet_id,
    packet_role = packet$packet_role,
    packet_dir = packet$dir,
    manifest_rows = nrow(packet$manifest),
    manifest_pass = sum(packet$manifest$status == "pass", na.rm = TRUE),
    manifest_fail = sum(packet$manifest$status != "pass", na.rm = TRUE),
    case_variant_rows = nrow(d),
    chain_jobs = nrow(chain_jobs),
    worker_failures = nrow(worker_failures),
    prep_failures = nrow(prep_failures),
    gate_pass = sum(d$phase136_gate_status == "pass", na.rm = TRUE),
    gate_review = sum(d$phase136_gate_status == "review", na.rm = TRUE),
    gate_fail = sum(d$phase136_gate_status == "fail", na.rm = TRUE),
    fit_raw_crossings = app_joint_exqdesn_phase143_safe_sum(d$mcmc_fit_raw_crossing_pairs),
    forecast_raw_crossings = app_joint_exqdesn_phase143_safe_sum(d$mcmc_forecast_raw_crossing_pairs),
    fit_contract_crossings = app_joint_exqdesn_phase143_safe_sum(d$mcmc_fit_contract_crossing_pairs),
    forecast_contract_crossings = app_joint_exqdesn_phase143_safe_sum(d$mcmc_forecast_contract_crossing_pairs),
    mean_forecast_mae = app_joint_exqdesn_phase143_safe_mean(d$mcmc_forecast_truth_mae),
    mean_fit_mae = app_joint_exqdesn_phase143_safe_mean(d$mcmc_fit_truth_mae),
    max_rhat = if ("max_rhat" %in% names(d)) app_joint_exqdesn_phase143_safe_max(d$max_rhat) else NA_real_,
    max_gamma_rhat = if ("max_gamma_rhat" %in% names(d)) app_joint_exqdesn_phase143_safe_max(d$max_gamma_rhat) else NA_real_,
    min_gamma_rough_ess_total = if ("min_gamma_rough_ess_total" %in% names(d)) app_joint_exqdesn_phase143_safe_min(d$min_gamma_rough_ess_total) else NA_real_,
    max_gamma_lag1_autocorrelation = if ("max_gamma_lag1_autocorrelation" %in% names(d)) app_joint_exqdesn_phase143_safe_max(d$max_gamma_lag1_autocorrelation) else NA_real_,
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase143_gate_rank <- function(status) {
  rank <- c(pass = 1L, review = 2L, fail = 3L)
  out <- unname(rank[as.character(status)])
  out[is.na(out)] <- 99L
  as.integer(out)
}

app_joint_exqdesn_phase143_select_metric_first <- function(packet, metric = "mcmc_forecast_truth_mae") {
  d <- packet$assessment
  app_joint_exqdesn_phase143_has_cols(d, c("case_id", metric), packet$packet_id)
  rows <- lapply(split(d, d$case_id), function(one) {
    one <- one[order(one[[metric]], one$variant_id), , drop = FALSE]
    one[1L, , drop = FALSE]
  })
  out <- app_joint_qdesn_bind_rows(rows)
  out$selection_rule <- "metric_first_forecast_mae"
  out$source_packet_id <- packet$packet_id
  out
}

app_joint_exqdesn_phase143_select_gate_first <- function(packet, metric = "mcmc_forecast_truth_mae") {
  d <- packet$assessment
  app_joint_exqdesn_phase143_has_cols(d, c("case_id", "phase136_gate_status", metric), packet$packet_id)
  rows <- lapply(split(d, d$case_id), function(one) {
    one$phase143_gate_rank <- app_joint_exqdesn_phase143_gate_rank(one$phase136_gate_status)
    one <- one[order(one$phase143_gate_rank, one[[metric]], one$variant_id), , drop = FALSE]
    one[1L, , drop = FALSE]
  })
  out <- app_joint_qdesn_bind_rows(rows)
  out$selection_rule <- "gate_first_then_forecast_mae"
  out$source_packet_id <- packet$packet_id
  out
}

app_joint_exqdesn_phase143_comparison_columns <- function() {
  c(
    "case_id", "scenario_id", "scenario_class", "distribution_family", "dynamics_class",
    "source_model_id", "model_id", "display_label", "likelihood", "fit_structure",
    "inference", "variant_id", "phase136_variant_id", "gamma_update",
    "gamma_prior_type", "gamma_prior_center", "gamma_prior_sd_eta",
    "phase136_gate_status", "mcmc_forecast_truth_mae", "mcmc_fit_truth_mae",
    "mcmc_forecast_check_loss_mean", "mcmc_fit_check_loss_mean",
    "mcmc_forecast_raw_crossing_pairs", "mcmc_fit_raw_crossing_pairs",
    "mcmc_forecast_contract_crossing_pairs", "mcmc_fit_contract_crossing_pairs",
    "max_rhat", "max_gamma_rhat", "min_gamma_rough_ess_total",
    "max_gamma_lag1_autocorrelation", "status_reason"
  )
}

app_joint_exqdesn_phase143_candidate_rows <- function(d, packet_id, packet_role, selection_type, common_cases) {
  cols <- intersect(app_joint_exqdesn_phase143_comparison_columns(), names(d))
  out <- d[d$case_id %in% common_cases, cols, drop = FALSE]
  out <- out[match(common_cases, out$case_id), , drop = FALSE]
  out$packet_id <- packet_id
  out$packet_role <- packet_role
  out$selection_type <- selection_type
  missing_cols <- setdiff(app_joint_exqdesn_phase143_comparison_columns(), names(out))
  for (nm in missing_cols) out[[nm]] <- NA
  out[, c("packet_id", "packet_role", "selection_type", app_joint_exqdesn_phase143_comparison_columns()), drop = FALSE]
}

app_joint_exqdesn_phase143_compare_sources <- function(fixed, focus, regularized) {
  metric_regularized <- app_joint_exqdesn_phase143_select_metric_first(regularized)
  gate_regularized <- app_joint_exqdesn_phase143_select_gate_first(regularized)
  common <- Reduce(intersect, list(
    fixed$assessment$case_id,
    focus$best$case_id,
    metric_regularized$case_id,
    gate_regularized$case_id
  ))
  if (!length(common)) stop("No common high-priority cases across Phase140, Phase141 focus, and Phase142B.", call. = FALSE)
  rows <- app_joint_qdesn_bind_rows(list(
    app_joint_exqdesn_phase143_candidate_rows(fixed$assessment, fixed$packet_id, fixed$packet_role, "fixed_gamma_reference", common),
    app_joint_exqdesn_phase143_candidate_rows(focus$best, focus$packet_id, focus$packet_role, "geometry_focus_best", common),
    app_joint_exqdesn_phase143_candidate_rows(metric_regularized, regularized$packet_id, regularized$packet_role, "regularized_metric_first", common),
    app_joint_exqdesn_phase143_candidate_rows(gate_regularized, regularized$packet_id, regularized$packet_role, "regularized_gate_first", common)
  ))
  rows <- app_joint_exqdesn_phase143_numericize_assessment(rows)
  fixed_rows <- rows[rows$selection_type == "fixed_gamma_reference", , drop = FALSE]
  fixed_rows <- fixed_rows[match(rows$case_id, fixed_rows$case_id), , drop = FALSE]
  rows$fixed_gamma_forecast_mae <- fixed_rows$mcmc_forecast_truth_mae
  rows$fixed_gamma_fit_mae <- fixed_rows$mcmc_fit_truth_mae
  rows$fixed_gamma_forecast_check_loss <- fixed_rows$mcmc_forecast_check_loss_mean
  rows$delta_forecast_mae_vs_fixed_gamma <- rows$mcmc_forecast_truth_mae - rows$fixed_gamma_forecast_mae
  rows$delta_fit_mae_vs_fixed_gamma <- rows$mcmc_fit_truth_mae - rows$fixed_gamma_fit_mae
  rows$delta_forecast_check_loss_vs_fixed_gamma <- rows$mcmc_forecast_check_loss_mean - rows$fixed_gamma_forecast_check_loss
  rows$beats_fixed_gamma_forecast_mae <- rows$delta_forecast_mae_vs_fixed_gamma < 0
  rows$beats_fixed_gamma_fit_mae <- rows$delta_fit_mae_vs_fixed_gamma < 0
  rows$beats_fixed_gamma_forecast_check_loss <- rows$delta_forecast_check_loss_vs_fixed_gamma < 0
  rows
}

app_joint_exqdesn_phase143_metric_first_winners <- function(regularized) {
  out <- app_joint_exqdesn_phase143_select_metric_first(regularized)
  out[, intersect(c(
    "selection_rule", "source_packet_id", app_joint_exqdesn_phase143_comparison_columns()
  ), names(out)), drop = FALSE]
}

app_joint_exqdesn_phase143_gate_first_winners <- function(regularized) {
  out <- app_joint_exqdesn_phase143_select_gate_first(regularized)
  out[, intersect(c(
    "selection_rule", "source_packet_id", "phase143_gate_rank", app_joint_exqdesn_phase143_comparison_columns()
  ), names(out)), drop = FALSE]
}

app_joint_exqdesn_phase143_worker_failure_counts <- function(packet) {
  d <- packet$worker_failures
  if (!nrow(d)) {
    return(data.frame(packet_id = character(), variant_id = character(), worker_failures = integer(), stringsAsFactors = FALSE))
  }
  variant_col <- if ("phase136_variant_id" %in% names(d)) "phase136_variant_id" else if ("variant_id" %in% names(d)) "variant_id" else NA_character_
  if (is.na(variant_col)) {
    return(data.frame(packet_id = packet$packet_id, variant_id = "unknown", worker_failures = nrow(d), stringsAsFactors = FALSE))
  }
  out <- as.data.frame(table(as.character(d[[variant_col]])), stringsAsFactors = FALSE)
  names(out) <- c("variant_id", "worker_failures")
  out$packet_id <- packet$packet_id
  out[, c("packet_id", "variant_id", "worker_failures"), drop = FALSE]
}

app_joint_exqdesn_phase143_tradeoff_summary <- function(packets) {
  rows <- list()
  for (packet in packets) {
    d <- packet$assessment
    d$packet_id <- packet$packet_id
    d$packet_role <- packet$packet_role
    variant_col <- if ("variant_id" %in% names(d)) "variant_id" else "phase136_variant_id"
    split_keys <- unique(as.character(d[[variant_col]]))
    failures <- app_joint_exqdesn_phase143_worker_failure_counts(packet)
    for (variant in split_keys) {
      one <- d[as.character(d[[variant_col]]) == variant, , drop = FALSE]
      fail_n <- failures$worker_failures[match(variant, failures$variant_id)]
      rows[[length(rows) + 1L]] <- data.frame(
        packet_id = packet$packet_id,
        packet_role = packet$packet_role,
        variant_id = variant,
        case_variant_rows = nrow(one),
        worker_failures = ifelse(is.na(fail_n), 0L, as.integer(fail_n)),
        gate_pass = sum(one$phase136_gate_status == "pass", na.rm = TRUE),
        gate_review = sum(one$phase136_gate_status == "review", na.rm = TRUE),
        gate_fail = sum(one$phase136_gate_status == "fail", na.rm = TRUE),
        mean_forecast_mae = app_joint_exqdesn_phase143_safe_mean(one$mcmc_forecast_truth_mae),
        mean_fit_mae = app_joint_exqdesn_phase143_safe_mean(one$mcmc_fit_truth_mae),
        mean_forecast_check_loss = app_joint_exqdesn_phase143_safe_mean(one$mcmc_forecast_check_loss_mean),
        total_forecast_raw_crossings = app_joint_exqdesn_phase143_safe_sum(one$mcmc_forecast_raw_crossing_pairs),
        total_fit_raw_crossings = app_joint_exqdesn_phase143_safe_sum(one$mcmc_fit_raw_crossing_pairs),
        total_forecast_contract_crossings = app_joint_exqdesn_phase143_safe_sum(one$mcmc_forecast_contract_crossing_pairs),
        total_fit_contract_crossings = app_joint_exqdesn_phase143_safe_sum(one$mcmc_fit_contract_crossing_pairs),
        max_rhat = if ("max_rhat" %in% names(one)) app_joint_exqdesn_phase143_safe_max(one$max_rhat) else NA_real_,
        max_gamma_rhat = if ("max_gamma_rhat" %in% names(one)) app_joint_exqdesn_phase143_safe_max(one$max_gamma_rhat) else NA_real_,
        min_gamma_rough_ess_total = if ("min_gamma_rough_ess_total" %in% names(one)) app_joint_exqdesn_phase143_safe_min(one$min_gamma_rough_ess_total) else NA_real_,
        max_gamma_lag1_autocorrelation = if ("max_gamma_lag1_autocorrelation" %in% names(one)) app_joint_exqdesn_phase143_safe_max(one$max_gamma_lag1_autocorrelation) else NA_real_,
        stringsAsFactors = FALSE
      )
    }
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase143_decision_summary <- function(source_manifest, packet_health, comparison, metric_winners, gate_winners) {
  promoted_fixed <- comparison[comparison$selection_type == "fixed_gamma_reference", , drop = FALSE]
  regularized_metric <- comparison[comparison$selection_type == "regularized_metric_first", , drop = FALSE]
  focus <- comparison[comparison$selection_type == "geometry_focus_best", , drop = FALSE]
  source_manifest_fail <- any(source_manifest$status != "pass")
  promoted_contract_crossings <- app_joint_exqdesn_phase143_safe_sum(promoted_fixed$mcmc_fit_contract_crossing_pairs) +
    app_joint_exqdesn_phase143_safe_sum(promoted_fixed$mcmc_forecast_contract_crossing_pairs)
  selected_metrics <- c(
    promoted_fixed$mcmc_forecast_truth_mae,
    promoted_fixed$mcmc_fit_truth_mae,
    regularized_metric$mcmc_forecast_truth_mae,
    regularized_metric$mcmc_fit_truth_mae
  )
  nonfinite_selected <- any(!is.finite(app_joint_exqdesn_phase143_num(selected_metrics)))
  hard_fail <- source_manifest_fail || promoted_contract_crossings > 0 || nonfinite_selected
  regularized_beats_fixed <- sum(regularized_metric$beats_fixed_gamma_forecast_mae, na.rm = TRUE)
  focus_beats_fixed <- sum(focus$beats_fixed_gamma_forecast_mae, na.rm = TRUE)
  fixed_cases <- nrow(promoted_fixed)
  phase142_worker_failures <- packet_health$worker_failures[packet_health$packet_id == "phase142_regularized_gamma"]
  phase142_worker_failures <- ifelse(length(phase142_worker_failures), phase142_worker_failures[[1L]], 0L)
  raw_crossings_fixed <- app_joint_exqdesn_phase143_safe_sum(promoted_fixed$mcmc_fit_raw_crossing_pairs) +
    app_joint_exqdesn_phase143_safe_sum(promoted_fixed$mcmc_forecast_raw_crossing_pairs)
  gamma_review <- any(is.finite(app_joint_exqdesn_phase143_num(regularized_metric$max_gamma_lag1_autocorrelation)) &
    app_joint_exqdesn_phase143_num(regularized_metric$max_gamma_lag1_autocorrelation) > 0.99)
  data.frame(
    decision_id = "phase143_gamma_decision_freeze",
    gate_status = if (hard_fail) "fail" else "review",
    source_manifest_fail = source_manifest_fail,
    promoted_fixed_gamma_contract_crossings = promoted_contract_crossings,
    nonfinite_selected_metrics = nonfinite_selected,
    fixed_gamma_cases = fixed_cases,
    phase141_focus_beats_fixed_forecast_cases = focus_beats_fixed,
    phase142_regularized_beats_fixed_forecast_cases = regularized_beats_fixed,
    phase142_worker_failures = phase142_worker_failures,
    fixed_gamma_raw_crossings = raw_crossings_fixed,
    sampled_gamma_high_autocorrelation_review = gamma_review,
    primary_article_model_recommendation = "keep_joint_qdesn_rhs_al_as_primary_validation_anchor",
    sampled_gamma_exal_decision = if (hard_fail) {
      "blocked_by_source_or_contract_gate"
    } else {
      "do_not_promote_sampled_gamma_exal_to_article_primary_table"
    },
    fixed_gamma_exal_decision = if (hard_fail) {
      "blocked"
    } else {
      "strongest_exal_like_reference_not_full_sampled_exal"
    },
    next_action = if (hard_fail) {
      "repair_phase143_source_or_contract_gate_before_article_update"
    } else {
      "prepare_article_safe_language_update_after_user_approval"
    },
    no_new_mcmc_reason = paste(
      "Phase141 geometry and Phase142 regularization removed crossings but did not beat Phase140 fixed-gamma-zero",
      "on forecast MAE in any common high-priority case; additional broad sampled-gamma tuning is not the best use of compute."
    ),
    interpretation = paste(
      "The validation evidence favors the AL-like gamma-zero submodel for exAL sensitivity checks.",
      "The sampled gamma layer appears weakly identified or performance-adverse under the current quantile-grid validation contract."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase143_article_recommendation <- function(decision) {
  data.frame(
    recommendation_id = c(
      "primary_model",
      "sampled_gamma_exal",
      "fixed_gamma_zero_exal",
      "manuscript_claim_scope",
      "article_update_gate"
    ),
    status = c("ready_for_article_anchor", "diagnostic_only", "sensitivity_reference", "quantile_grid_only", decision$gate_status[[1L]]),
    recommendation = c(
      "Use Joint QDESN RHS under AL as the primary validation anchor.",
      "Do not promote sampled-gamma exQDESN RHS as an article-primary winner under the current evidence.",
      "Use fixed-gamma-zero exAL only as an AL-like sensitivity/reference if it is included.",
      "Keep claims on oracle quantile MAE/RMSE, check loss, grid CRPS, coverage/hit rates, and raw/contract crossings.",
      "Touch the manuscript only after this freeze artifact is reviewed."
    ),
    rationale = c(
      "It remains the stable and interpretable model family supported by the validation packets.",
      "Geometry and regularization screens did not recover fixed-gamma-zero performance.",
      "It recovers exAL-like performance but removes sampled gamma flexibility, so the wording must be explicit.",
      "The joint composite likelihood is a working likelihood for quantile paths, not a unique scalar posterior predictive density.",
      "The freeze is a decision audit; article integration should be a separate article-safe pass."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase143_next_experiment_recommendation <- function() {
  data.frame(
    priority = 1:5,
    action_id = c(
      "phase143_article_language_pass",
      "no_more_width_or_prior_sweeps",
      "defer_longer_sampled_gamma_mcmc",
      "optional_exal_model_redesign",
      "future_posterior_quantile_curve_uncertainty"
    ),
    launch_now = c(FALSE, FALSE, FALSE, FALSE, FALSE),
    recommendation = c(
      "Prepare a surgical manuscript/table/caption pass after reviewing the Phase143 freeze.",
      "Do not launch another broad slice-width or logit-normal gamma-prior sweep.",
      "Do not spend overnight compute just to increase sampled-gamma ESS before a model redesign.",
      "If exAL must become article-primary, design a new gamma parameterization: shared or block-shared gamma, hierarchical shrinkage, or blocked gamma/log-sigma updates.",
      "Treat posterior quantile-curve uncertainty or inverse-CDF response sampling as a separate future validation layer."
    ),
    rationale = c(
      "The current evidence is strong enough to support a conservative article narrative.",
      "Both geometry and regularization failed to beat fixed-gamma-zero on the high-priority comparison cases.",
      "Tight regularization already mixes well and performs poorly; looser regularization performs better but remains worse and sticky.",
      "The present issue is statistical identification/performance, not just an implementation nuisance.",
      "The present validation is valid as quantile-grid validation, not scalar density validation."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase143_readme <- function(decision, comparison) {
  c(
    "# Joint exQDESN Phase143 Gamma Decision Freeze",
    "",
    "This artifact freezes the post-Phase142 decision for the sampled-gamma exAL validation line.",
    "It compares the Phase140 fixed-gamma-zero reference, the Phase141 sampled-gamma geometry focus screen, and the Phase142B regularized sampled-gamma screen.",
    "",
    sprintf("- Gate status: `%s`", decision$gate_status[[1L]]),
    sprintf("- Sampled-gamma exAL decision: `%s`", decision$sampled_gamma_exal_decision[[1L]]),
    sprintf("- Fixed-gamma exAL decision: `%s`", decision$fixed_gamma_exal_decision[[1L]]),
    sprintf("- Common high-priority cases: %s", length(unique(comparison$case_id))),
    sprintf("- Phase141 focus beats fixed-gamma-zero forecast MAE cases: %s", decision$phase141_focus_beats_fixed_forecast_cases[[1L]]),
    sprintf("- Phase142 regularized beats fixed-gamma-zero forecast MAE cases: %s", decision$phase142_regularized_beats_fixed_forecast_cases[[1L]]),
    "",
    "Main conclusion:",
    "",
    decision$interpretation[[1L]],
    "",
    "No article files are modified by this stage. The next step is a separate article-safe wording/table pass only if the user approves it."
  )
}

app_joint_exqdesn_run_phase143_gamma_decision_freeze <- function(
  out_dir = app_joint_exqdesn_phase143_default_dir(),
  phase140_dir = app_path("application/cache/joint_qdesn_phase140_exal_fixed_gamma_zero_sensitivity_recovery_20260718"),
  phase141_focus_dir = app_path("application/cache/joint_qdesn_phase141_focus_width_sensitivity_screen_20260719"),
  phase142_dir = app_path("application/cache/joint_qdesn_phase142_regularized_gamma_screen_20260722")
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  fixed <- app_joint_exqdesn_phase143_load_packet(phase140_dir, "phase140_fixed_gamma_zero", "fixed_gamma_zero_reference")
  focus <- app_joint_exqdesn_phase143_load_packet(phase141_focus_dir, "phase141_focus_geometry", "sampled_gamma_geometry_focus")
  regularized <- app_joint_exqdesn_phase143_load_packet(phase142_dir, "phase142_regularized_gamma", "sampled_gamma_regularized")
  source_manifest <- app_joint_qdesn_bind_rows(list(fixed$manifest, focus$manifest, regularized$manifest))
  packet_health <- app_joint_qdesn_bind_rows(lapply(list(fixed, focus, regularized), app_joint_exqdesn_phase143_packet_health))
  comparison <- app_joint_exqdesn_phase143_compare_sources(fixed, focus, regularized)
  metric_winners <- app_joint_exqdesn_phase143_metric_first_winners(regularized)
  gate_winners <- app_joint_exqdesn_phase143_gate_first_winners(regularized)
  tradeoff <- app_joint_exqdesn_phase143_tradeoff_summary(list(fixed, focus, regularized))
  decision <- app_joint_exqdesn_phase143_decision_summary(source_manifest, packet_health, comparison, metric_winners, gate_winners)
  article <- app_joint_exqdesn_phase143_article_recommendation(decision)
  next_experiment <- app_joint_exqdesn_phase143_next_experiment_recommendation()
  run_config <- data.frame(
    run_id = "joint_qdesn_phase143_gamma_decision_freeze",
    out_dir = out_dir,
    phase140_dir = fixed$dir,
    phase141_focus_dir = focus$dir,
    phase142_dir = regularized$dir,
    phase140_rows = nrow(fixed$assessment),
    phase141_focus_rows = nrow(focus$assessment),
    phase142_rows = nrow(regularized$assessment),
    common_cases = length(unique(comparison$case_id)),
    mcmc_launched = FALSE,
    article_files_modified = FALSE,
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_exqdesn_phase143_readme(decision, comparison), readme_path, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    source_manifest_verification = app_joint_qvp_write_csv(source_manifest, file.path(out_dir, "source_manifest_verification.csv")),
    gamma_packet_health_summary = app_joint_qvp_write_csv(packet_health, file.path(out_dir, "gamma_packet_health_summary.csv")),
    gamma_packet_comparison_by_case = app_joint_qvp_write_csv(comparison, file.path(out_dir, "gamma_packet_comparison_by_case.csv")),
    gamma_variant_metric_first_winners = app_joint_qvp_write_csv(metric_winners, file.path(out_dir, "gamma_variant_metric_first_winners.csv")),
    gamma_variant_gate_first_winners = app_joint_qvp_write_csv(gate_winners, file.path(out_dir, "gamma_variant_gate_first_winners.csv")),
    gamma_diagnostic_tradeoff_summary = app_joint_qvp_write_csv(tradeoff, file.path(out_dir, "gamma_diagnostic_tradeoff_summary.csv")),
    gamma_decision_summary = app_joint_qvp_write_csv(decision, file.path(out_dir, "gamma_decision_summary.csv")),
    article_integration_recommendation = app_joint_qvp_write_csv(article, file.path(out_dir, "article_integration_recommendation.csv")),
    next_experiment_recommendation = app_joint_qvp_write_csv(next_experiment, file.path(out_dir, "next_experiment_recommendation.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = out_dir,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path),
    manifest = manifest_info$manifest,
    source_manifest = source_manifest,
    packet_health = packet_health,
    comparison = comparison,
    metric_winners = metric_winners,
    gate_winners = gate_winners,
    tradeoff = tradeoff,
    decision = decision,
    article = article,
    next_experiment = next_experiment
  )
}
