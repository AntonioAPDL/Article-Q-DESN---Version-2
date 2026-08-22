# Current manuscript-facing application output registry.

app_latex_escape_text <- function(x) {
  x <- as.character(x)
  x <- gsub("\\\\", "\\\\textbackslash{}", x)
  x <- gsub("([#$%&_{}])", "\\\\\\1", x, perl = TRUE)
  x <- gsub("~", "\\\\textasciitilde{}", x, fixed = TRUE)
  x <- gsub("\\^", "\\\\textasciicircum{}", x)
  x
}

app_latex_file_path <- function(path) {
  app_prefer_repo_relative_path(path)
}

app_manifest_role_path <- function(manifest, role = NULL, role_pattern = NULL) {
  if (!is.null(role)) {
    rows <- manifest[manifest$output_role == role, , drop = FALSE]
  } else {
    rows <- manifest[grepl(role_pattern, manifest$output_role), , drop = FALSE]
  }
  if (nrow(rows) != 1L) {
    label <- role %||% role_pattern
    stop(sprintf("Expected exactly one promoted output for '%s'; found %d.", label, nrow(rows)), call. = FALSE)
  }
  rows$promoted_path[[1L]]
}

app_manifest_optional_role_path <- function(manifest, role = NULL, role_pattern = NULL) {
  if (!is.null(role)) {
    rows <- manifest[manifest$output_role == role, , drop = FALSE]
  } else {
    rows <- manifest[grepl(role_pattern, manifest$output_role), , drop = FALSE]
  }
  if (nrow(rows) != 1L) return(NA_character_)
  rows$promoted_path[[1L]]
}

app_application_model_label <- function(model_id, model_family) {
  family <- tolower(as.character(model_family %||% ""))
  id <- tolower(as.character(model_id %||% ""))
  if (grepl("qdesn", family) || grepl("qdesn", id)) return("Q--DESN correction")
  if (grepl("raw_glofas", family) || grepl("raw_glofas", id)) return("Raw GloFAS")
  as.character(model_id)
}

app_application_transition_label <- function(strategy) {
  strategy <- as.character(strategy %||% "")[[1L]]
  if (identical(strategy, "persistence_anchored_innovation")) {
    return("persistence-anchored innovation")
  }
  gsub("_", " ", strategy, fixed = TRUE)
}

app_format_decimal <- function(x, digits = 4L) {
  if (!is.finite(as.numeric(x))) return("")
  sprintf(paste0("%.", digits, "f"), as.numeric(x))
}

app_format_percent <- function(x, digits = 1L) {
  if (!is.finite(as.numeric(x))) return("")
  paste0(sprintf(paste0("%.", digits, "f"), 100 * as.numeric(x)), "\\%")
}

app_format_integer <- function(x) {
  if (!is.finite(as.numeric(x))) return("")
  format(as.integer(round(as.numeric(x))), big.mark = ",", scientific = FALSE, trim = TRUE)
}

app_format_config_vector <- function(x, empty = "none", missing = "NA") {
  v <- unlist(x, use.names = FALSE)
  if (!length(v)) return(empty)
  if (all(is.na(v))) return(missing)
  paste(v, collapse = ",")
}

app_registry_spec_value <- function(spec, name, fallback = NA_character_) {
  if (!nrow(spec) || !name %in% names(spec)) return(as.character(fallback))
  value <- spec[[name]][[1L]]
  if (!length(value) || is.na(value) || !nzchar(trimws(as.character(value)))) {
    return(as.character(fallback))
  }
  gsub(";", ",", as.character(value), fixed = TRUE)
}

app_build_current_application_score_summary <- function(score_path, metrics_path = NULL) {
  score <- app_read_csv(score_path)
  metrics <- if (!is.null(metrics_path) && file.exists(metrics_path)) app_read_csv(metrics_path) else data.frame()
  if (!all(c("model_id", "check_loss_mean", "n_quantile_scores") %in% names(score))) {
    stop("Score summary is missing required columns.", call. = FALSE)
  }

  rows <- vector("list", nrow(score))
  raw_loss <- score$check_loss_mean[grepl("raw_glofas", score$model_id)]
  raw_loss <- if (length(raw_loss)) as.numeric(raw_loss[[1L]]) else NA_real_
  for (i in seq_len(nrow(score))) {
    row <- score[i, , drop = FALSE]
    metric_row <- if (nrow(metrics) && "model_id" %in% names(metrics)) {
      metrics[metrics$model_id == row$model_id[[1L]], , drop = FALSE]
    } else {
      data.frame()
    }
    check_loss <- as.numeric(row$check_loss_mean[[1L]])
    reduction <- if (is.finite(raw_loss) && raw_loss > 0 && grepl("qdesn", row$model_id[[1L]])) {
      (raw_loss - check_loss) / raw_loss
    } else {
      NA_real_
    }
    model_family <- if ("model_family" %in% names(metric_row) && nrow(metric_row)) metric_row$model_family[[1L]] else row$model_id[[1L]]
    rows[[i]] <- data.frame(
      model_label = app_application_model_label(row$model_id[[1L]], model_family),
      model_id = row$model_id[[1L]],
      n_scored_horizons = if ("n" %in% names(metric_row) && "n_quantile_levels" %in% names(metric_row) && nrow(metric_row)) {
        as.integer(round(as.numeric(metric_row$n[[1L]]) / as.numeric(metric_row$n_quantile_levels[[1L]])))
      } else {
        as.integer(row$n_quantile_scores[[1L]])
      },
      n_quantile_scores = as.integer(row$n_quantile_scores[[1L]]),
      check_loss_mean = check_loss,
      check_loss_reduction_vs_raw = reduction,
      interval_score_mean = if ("interval_score_mean" %in% names(row)) as.numeric(row$interval_score_mean[[1L]]) else NA_real_,
      interval_coverage_mean = if ("interval_coverage_mean" %in% names(row)) as.numeric(row$interval_coverage_mean[[1L]]) else NA_real_,
      acrps_quantile_grid_mean = if ("acrps_quantile_grid_mean" %in% names(row)) {
        as.numeric(row$acrps_quantile_grid_mean[[1L]])
      } else if ("crps_quantile_grid_mean" %in% names(row)) {
        as.numeric(row$crps_quantile_grid_mean[[1L]])
      } else {
        NA_real_
      },
      crps_quantile_grid_mean = if ("acrps_quantile_grid_mean" %in% names(row)) {
        as.numeric(row$acrps_quantile_grid_mean[[1L]])
      } else if ("crps_quantile_grid_mean" %in% names(row)) {
        as.numeric(row$crps_quantile_grid_mean[[1L]])
      } else {
        NA_real_
      },
      mae_to_observation = if ("mae_to_observation" %in% names(metric_row) && nrow(metric_row)) as.numeric(metric_row$mae_to_observation[[1L]]) else NA_real_,
      rmse_to_observation = if ("rmse_to_observation" %in% names(metric_row) && nrow(metric_row)) as.numeric(metric_row$rmse_to_observation[[1L]]) else NA_real_,
      bias_to_observation = if ("bias_to_observation" %in% names(metric_row) && nrow(metric_row)) as.numeric(metric_row$bias_to_observation[[1L]]) else NA_real_,
      stringsAsFactors = FALSE
    )
  }

  out <- do.call(rbind, rows)
  out$order <- ifelse(grepl("Q--DESN", out$model_label), 1L, 2L)
  out <- out[order(out$order, out$model_label), setdiff(names(out), "order"), drop = FALSE]
  rownames(out) <- NULL
  out
}

app_write_current_application_score_tex <- function(summary, path) {
  app_ensure_dir(dirname(path))
  reduction <- ifelse(
    is.finite(summary$check_loss_reduction_vs_raw),
    vapply(summary$check_loss_reduction_vs_raw, app_format_percent, character(1L)),
    "Reference"
  )
  acrps_col <- if ("acrps_quantile_grid_mean" %in% names(summary)) "acrps_quantile_grid_mean" else "crps_quantile_grid_mean"
  has_full_quantile_scores <- all(c("interval_score_mean", acrps_col) %in% names(summary)) &&
    any(is.finite(summary$interval_score_mean)) &&
    any(is.finite(summary[[acrps_col]]))
  if (has_full_quantile_scores) {
    lines <- c(
      "% Generated by application/R/application_output_registry.R",
      "\\small",
      "\\begin{tabular}{lrrrrrr}",
      "\\toprule",
      "Model & Horizons & Check & Interval & aCRPS & Coverage & Check reduction \\\\",
      "\\midrule"
    )
    for (i in seq_len(nrow(summary))) {
      lines <- c(lines, sprintf(
        "%s & %d & %s & %s & %s & %s & %s \\\\",
        app_latex_escape_text(summary$model_label[[i]]),
        summary$n_scored_horizons[[i]],
        app_format_decimal(summary$check_loss_mean[[i]], 4L),
        app_format_decimal(summary$interval_score_mean[[i]], 4L),
        app_format_decimal(summary[[acrps_col]][[i]], 4L),
        app_format_decimal(summary$interval_coverage_mean[[i]], 3L),
        reduction[[i]]
      ))
    }
  } else {
    lines <- c(
      "% Generated by application/R/application_output_registry.R",
      "\\begin{tabular}{lrrr}",
      "\\toprule",
      "Model & Scored horizons & Mean check loss & Reduction vs. raw \\\\",
      "\\midrule"
    )
    for (i in seq_len(nrow(summary))) {
      lines <- c(lines, sprintf(
        "%s & %d & %s & %s \\\\",
        app_latex_escape_text(summary$model_label[[i]]),
        summary$n_scored_horizons[[i]],
        app_format_decimal(summary$check_loss_mean[[i]], 4L),
        reduction[[i]]
      ))
    }
  }
  lines <- c(lines, "\\bottomrule", "\\end{tabular}")
  writeLines(lines, path)
  invisible(path)
}

app_write_current_application_registry_tex <- function(values, path) {
  app_ensure_dir(dirname(path))
  command <- function(name, value) sprintf("\\newcommand{\\%s}{%s}", name, value)
  text_command <- function(name, value) {
    sprintf("\\newcommand{\\%s}{\\detokenize{%s}}", name, value)
  }
  lines <- c(
    "% Generated by application/R/application_output_registry.R",
    "% Stable current-output aliases for the GloFAS application section.",
    text_command("GlofasApplicationCurrentRunId", values$run_id),
    text_command("GlofasApplicationCurrentConfigPath", values$config_path),
    text_command("GlofasApplicationCurrentPromotionManifest", values$promotion_manifest),
    text_command("GlofasApplicationCurrentSelectionManifest", values$selection_manifest),
    text_command("GlofasApplicationCurrentCandidateId", values$candidate_id),
    text_command("GlofasApplicationCurrentDiscrepancyTransitionStrategy", values$discrepancy_transition_strategy),
    command("GlofasApplicationCurrentScoreTable", values$score_tex),
    command("GlofasApplicationCurrentCorrectedPathsFigure", values$corrected_paths_figure),
    command("GlofasApplicationCurrentForecastWindowFigure", values$forecast_window_figure),
    command("GlofasApplicationCurrentDiagnosticTracesFigure", values$diagnostic_traces_figure),
    command("GlofasApplicationCurrentQdesnCheckLoss", values$qdesn_check_loss),
    command("GlofasApplicationCurrentRawCheckLoss", values$raw_check_loss),
    command("GlofasApplicationCurrentCheckLossReduction", values$check_loss_reduction),
    command("GlofasApplicationCurrentQdesnIntervalScore", values$qdesn_interval_score),
    command("GlofasApplicationCurrentRawIntervalScore", values$raw_interval_score),
    command("GlofasApplicationCurrentIntervalScoreReduction", values$interval_score_reduction),
    command("GlofasApplicationCurrentQdesnAcrps", values$qdesn_acrps),
    command("GlofasApplicationCurrentRawAcrps", values$raw_acrps),
    command("GlofasApplicationCurrentAcrpsReduction", values$acrps_reduction),
    command("GlofasApplicationCurrentQdesnCrps", values$qdesn_crps),
    command("GlofasApplicationCurrentRawCrps", values$raw_crps),
    command("GlofasApplicationCurrentCrpsReduction", values$crps_reduction),
    command("GlofasApplicationCurrentQdesnMeanCoverage", values$qdesn_mean_coverage),
    command("GlofasApplicationCurrentRawMeanCoverage", values$raw_mean_coverage),
    command("GlofasApplicationCurrentScoredHorizons", values$scored_horizons),
    command("GlofasApplicationCurrentOriginDate", values$origin_date),
    command("GlofasApplicationCurrentVbIterations", values$vb_iterations),
    command("GlofasApplicationCurrentReservoirDepth", values$reservoir_depth),
    command("GlofasApplicationCurrentReservoirSize", values$reservoir_size),
    command("GlofasApplicationCurrentReducerSize", values$reducer_size),
    command("GlofasApplicationCurrentReservoirMemory", values$reservoir_memory),
    command("GlofasApplicationCurrentReservoirWashout", values$reservoir_washout),
    command("GlofasApplicationCurrentReservoirAlpha", values$reservoir_alpha),
    command("GlofasApplicationCurrentReservoirRho", values$reservoir_rho),
    command("GlofasApplicationCurrentReservoirPiW", values$reservoir_pi_w),
    command("GlofasApplicationCurrentReservoirPiIn", values$reservoir_pi_in),
    command("GlofasApplicationCurrentReservoirWinScaleGlobal", values$reservoir_win_scale_global),
    command("GlofasApplicationCurrentReservoirWinScaleBias", values$reservoir_win_scale_bias),
    command("GlofasApplicationCurrentReservoirSeed", values$reservoir_seed),
    command("GlofasApplicationCurrentReferenceReservoirDepth", values$reference_reservoir_depth),
    command("GlofasApplicationCurrentReferenceReservoirSize", values$reference_reservoir_size),
    command("GlofasApplicationCurrentReferenceReducerSize", values$reference_reducer_size),
    command("GlofasApplicationCurrentReferenceReservoirMemory", values$reference_reservoir_memory),
    command("GlofasApplicationCurrentReferenceReservoirWashout", values$reference_reservoir_washout),
    command("GlofasApplicationCurrentReferenceReservoirAlpha", values$reference_reservoir_alpha),
    command("GlofasApplicationCurrentReferenceReservoirRho", values$reference_reservoir_rho),
    command("GlofasApplicationCurrentReferenceReservoirPiW", values$reference_reservoir_pi_w),
    command("GlofasApplicationCurrentReferenceReservoirPiIn", values$reference_reservoir_pi_in),
    command("GlofasApplicationCurrentReferenceReservoirWinScaleGlobal", values$reference_reservoir_win_scale_global),
    command("GlofasApplicationCurrentReferenceReservoirWinScaleBias", values$reference_reservoir_win_scale_bias),
    command("GlofasApplicationCurrentReferenceReservoirSeed", values$reference_reservoir_seed),
    command("GlofasApplicationCurrentDiscrepancyReservoirDepth", values$discrepancy_reservoir_depth),
    command("GlofasApplicationCurrentDiscrepancyReservoirSize", values$discrepancy_reservoir_size),
    command("GlofasApplicationCurrentDiscrepancyReducerSize", values$discrepancy_reducer_size),
    command("GlofasApplicationCurrentDiscrepancyReservoirMemory", values$discrepancy_reservoir_memory),
    command("GlofasApplicationCurrentDiscrepancyReservoirWashout", values$discrepancy_reservoir_washout),
    command("GlofasApplicationCurrentDiscrepancyReservoirAlpha", values$discrepancy_reservoir_alpha),
    command("GlofasApplicationCurrentDiscrepancyReservoirRho", values$discrepancy_reservoir_rho),
    command("GlofasApplicationCurrentDiscrepancyReservoirPiW", values$discrepancy_reservoir_pi_w),
    command("GlofasApplicationCurrentDiscrepancyReservoirPiIn", values$discrepancy_reservoir_pi_in),
    command("GlofasApplicationCurrentDiscrepancyReservoirWinScaleGlobal", values$discrepancy_reservoir_win_scale_global),
    command("GlofasApplicationCurrentDiscrepancyReservoirWinScaleBias", values$discrepancy_reservoir_win_scale_bias),
    command("GlofasApplicationCurrentDiscrepancyReservoirSeed", values$discrepancy_reservoir_seed),
    command("GlofasApplicationCurrentSharedRhsTau", values$rhs_shared_tau0),
    command("GlofasApplicationCurrentDiscrepancyRhsTau", values$rhs_discrepancy_tau0),
    command("GlofasApplicationCurrentRhsTau", values$rhs_shared_tau0),
    command("GlofasApplicationCurrentSpreadCalibrationEnabled", values$spread_calibration_enabled),
    command("GlofasApplicationCurrentSpreadCalibrationFactor", values$spread_calibration_factor),
    command("GlofasApplicationCurrentSpreadCalibrationAdditiveWidth", values$spread_calibration_additive_width),
    command("GlofasApplicationCurrentSpreadCalibrationCenterQuantile", values$spread_calibration_center_quantile),
    text_command("GlofasApplicationCurrentSpreadCalibrationId", values$spread_calibration_id),
    text_command("GlofasApplicationCurrentSpreadCalibrationDescription", values$spread_calibration_description),
    command("GlofasApplicationCurrentObservedHistoryAcrps", values$observed_history_acrps),
    command("GlofasApplicationCurrentObservedHistoryCrps", values$observed_history_crps),
    command("GlofasApplicationCurrentObservedHistoryCoverage", values$observed_history_coverage),
    command("GlofasApplicationCurrentObservedHistoryDates", values$observed_history_dates)
  )
  writeLines(lines, path)
  invisible(path)
}

app_write_current_application_selection <- function(
  promotion_manifest,
  registry_tex = "tables/glofas_application_current_outputs.tex",
  score_tex = "tables/glofas_application_current_score_summary.tex",
  score_csv = "tables/glofas_application_current_score_summary.csv",
  selection_manifest = "tables/glofas_application_current_selection_manifest.csv",
  quiet = FALSE
) {
  manifest_path <- app_resolve_path(promotion_manifest, must_work = TRUE)
  manifest <- app_read_csv(manifest_path)
  if (!nrow(manifest)) stop("Promotion manifest is empty.", call. = FALSE)
  if (!all(c("output_role", "promoted_path", "run_id", "config_path") %in% names(manifest))) {
    stop("Promotion manifest is missing required columns.", call. = FALSE)
  }

  score_path <- app_manifest_role_path(manifest, "score_summary_csv")
  metrics_path <- app_manifest_role_path(manifest, "post_fit_metrics_by_model")
  band_path <- app_manifest_role_path(manifest, "post_fit_forecast_window_band_check")
  fit_diag_path <- app_manifest_role_path(manifest, "qdesn_discrepancy_fit_diagnostics")
  config_snapshot_path <- app_manifest_role_path(manifest, "run_config_yaml")
  model_spec_path <- app_manifest_optional_role_path(manifest, "authoritative_model_spec")
  model_spec <- if (!is.na(model_spec_path) && file.exists(model_spec_path)) {
    app_read_csv(model_spec_path)
  } else {
    data.frame()
  }
  observed_history_path <- app_manifest_optional_role_path(manifest, "observed_history_full7_ranking")
  observed_history <- if (!is.na(observed_history_path) && file.exists(observed_history_path)) {
    app_read_csv(observed_history_path)
  } else {
    data.frame()
  }

  summary <- app_build_current_application_score_summary(score_path, metrics_path)
  app_write_csv(summary, app_path(score_csv))
  app_write_current_application_score_tex(summary, app_path(score_tex))

  band <- app_read_csv(band_path)
  fit_diag <- app_read_csv(fit_diag_path)
  cfg <- app_read_yaml(config_snapshot_path)
  spread_manifest_path <- app_manifest_optional_role_path(manifest, "spread_calibration_manifest")
  spread_manifest <- if (is.character(spread_manifest_path) && length(spread_manifest_path) == 1L &&
    !is.na(spread_manifest_path) && file.exists(spread_manifest_path)) {
    app_read_csv(spread_manifest_path)
  } else {
    data.frame(
      enabled = FALSE,
      spread_calibration_factor = NA_real_,
      spread_calibration_additive_width = NA_real_,
      center_quantile = NA_real_,
      calibration_id = "none",
      stringsAsFactors = FALSE
    )
  }
  spread_row <- spread_manifest[1L, , drop = FALSE]
  spread_enabled <- isTRUE(app_as_bool_vec(spread_row$enabled)[[1L]])
  qdesn <- summary[grepl("Q--DESN", summary$model_label), , drop = FALSE]
  raw <- summary[grepl("Raw GloFAS", summary$model_label), , drop = FALSE]
  if (nrow(qdesn) != 1L || nrow(raw) != 1L) {
    stop("Current application score summary must contain one Q-DESN row and one raw GloFAS row.", call. = FALSE)
  }

  fallback_depth <- as.character(cfg$reservoir$D %||% NA)
  fallback_size <- app_format_config_vector(cfg$reservoir$n %||% NA)
  fallback_reducer <- app_format_config_vector(cfg$reservoir$n_tilde %||% list(), empty = "none")
  fallback_memory <- as.character(cfg$reservoir$m %||% NA)
  fallback_washout <- as.character(cfg$reservoir$washout %||% NA)
  fallback_alpha <- app_format_config_vector(cfg$reservoir$alpha %||% NA)
  fallback_rho <- app_format_config_vector(cfg$reservoir$rho %||% NA)
  fallback_pi_w <- app_format_config_vector(cfg$reservoir$pi_w %||% NA)
  fallback_pi_in <- app_format_config_vector(cfg$reservoir$pi_in %||% NA)
  fallback_win_global <- as.character(cfg$reservoir$win_scale_global %||% NA)
  fallback_win_bias <- as.character(cfg$reservoir$win_scale_bias %||% NA)
  fallback_seed <- as.character(cfg$reservoir$seed %||% NA)
  observed_row <- if (nrow(observed_history)) observed_history[1L, , drop = FALSE] else data.frame()

  qdesn_acrps <- if ("acrps_quantile_grid_mean" %in% names(qdesn)) qdesn$acrps_quantile_grid_mean[[1L]] else qdesn$crps_quantile_grid_mean[[1L]]
  raw_acrps <- if ("acrps_quantile_grid_mean" %in% names(raw)) raw$acrps_quantile_grid_mean[[1L]] else raw$crps_quantile_grid_mean[[1L]]
  observed_history_acrps <- if (nrow(observed_row) && "acrps_quantile_grid_mean" %in% names(observed_row)) {
    observed_row$acrps_quantile_grid_mean[[1L]]
  } else if (nrow(observed_row) && "crps_quantile_grid_mean" %in% names(observed_row)) {
    observed_row$crps_quantile_grid_mean[[1L]]
  } else {
    NA_real_
  }

  current_values <- list(
    run_id = unique(manifest$run_id)[[1L]],
    config_path = app_latex_file_path(config_snapshot_path),
    promotion_manifest = app_latex_file_path(manifest_path),
    selection_manifest = selection_manifest,
    candidate_id = app_registry_spec_value(model_spec, "candidate_id", unique(manifest$run_id)[[1L]]),
    discrepancy_transition_strategy = app_application_transition_label(
      app_registry_spec_value(model_spec, "discrepancy_transition_strategy", "not recorded")
    ),
    score_tex = score_tex,
    corrected_paths_figure = app_latex_file_path(app_manifest_role_path(manifest, "discrepancy_corrected_quantile_paths")),
    forecast_window_figure = app_latex_file_path(app_manifest_role_path(manifest, role_pattern = "__forecast_window_pm30$")),
    diagnostic_traces_figure = app_latex_file_path(app_manifest_role_path(manifest, role_pattern = "diagnostic_traces$")),
    qdesn_check_loss = app_format_decimal(qdesn$check_loss_mean[[1L]], 4L),
    raw_check_loss = app_format_decimal(raw$check_loss_mean[[1L]], 4L),
    check_loss_reduction = app_format_percent(qdesn$check_loss_reduction_vs_raw[[1L]], 1L),
    qdesn_interval_score = app_format_decimal(qdesn$interval_score_mean[[1L]], 4L),
    raw_interval_score = app_format_decimal(raw$interval_score_mean[[1L]], 4L),
    interval_score_reduction = if (is.finite(raw$interval_score_mean[[1L]]) && raw$interval_score_mean[[1L]] > 0) {
      app_format_percent((raw$interval_score_mean[[1L]] - qdesn$interval_score_mean[[1L]]) / raw$interval_score_mean[[1L]], 1L)
    } else {
      ""
    },
    qdesn_acrps = app_format_decimal(qdesn_acrps, 4L),
    raw_acrps = app_format_decimal(raw_acrps, 4L),
    acrps_reduction = if (is.finite(raw_acrps) && raw_acrps > 0) {
      app_format_percent((raw_acrps - qdesn_acrps) / raw_acrps, 1L)
    } else {
      ""
    },
    qdesn_crps = app_format_decimal(qdesn_acrps, 4L),
    raw_crps = app_format_decimal(raw_acrps, 4L),
    crps_reduction = if (is.finite(raw_acrps) && raw_acrps > 0) {
      app_format_percent((raw_acrps - qdesn_acrps) / raw_acrps, 1L)
    } else {
      ""
    },
    qdesn_mean_coverage = app_format_decimal(qdesn$interval_coverage_mean[[1L]], 3L),
    raw_mean_coverage = app_format_decimal(raw$interval_coverage_mean[[1L]], 3L),
    scored_horizons = as.character(qdesn$n_scored_horizons[[1L]]),
    origin_date = as.character(band$origin_date[[1L]]),
    vb_iterations = if ("vb_iterations" %in% names(fit_diag)) {
      paste0(
        "a median of ", stats::median(as.numeric(fit_diag$vb_iterations), na.rm = TRUE),
        " and a maximum of ", max(as.numeric(fit_diag$vb_iterations), na.rm = TRUE)
      )
    } else {
      NA_character_
    },
    reservoir_depth = app_registry_spec_value(model_spec, "reference_D", fallback_depth),
    reservoir_size = app_registry_spec_value(model_spec, "reference_n", fallback_size),
    reducer_size = app_registry_spec_value(model_spec, "reference_n_tilde", fallback_reducer),
    reservoir_memory = app_registry_spec_value(model_spec, "reference_m", fallback_memory),
    reservoir_washout = app_registry_spec_value(model_spec, "reference_washout", fallback_washout),
    reservoir_alpha = app_registry_spec_value(model_spec, "reference_alpha", fallback_alpha),
    reservoir_rho = app_registry_spec_value(model_spec, "reference_rho", fallback_rho),
    reservoir_pi_w = app_registry_spec_value(model_spec, "reference_pi_w", fallback_pi_w),
    reservoir_pi_in = app_registry_spec_value(model_spec, "reference_pi_in", fallback_pi_in),
    reservoir_win_scale_global = app_registry_spec_value(model_spec, "reference_win_scale_global", fallback_win_global),
    reservoir_win_scale_bias = app_registry_spec_value(model_spec, "reference_win_scale_bias", fallback_win_bias),
    reservoir_seed = app_registry_spec_value(model_spec, "reference_seed", fallback_seed),
    reference_reservoir_depth = app_registry_spec_value(model_spec, "reference_D", fallback_depth),
    reference_reservoir_size = app_registry_spec_value(model_spec, "reference_n", fallback_size),
    reference_reducer_size = app_registry_spec_value(model_spec, "reference_n_tilde", fallback_reducer),
    reference_reservoir_memory = app_registry_spec_value(model_spec, "reference_m", fallback_memory),
    reference_reservoir_washout = app_registry_spec_value(model_spec, "reference_washout", fallback_washout),
    reference_reservoir_alpha = app_registry_spec_value(model_spec, "reference_alpha", fallback_alpha),
    reference_reservoir_rho = app_registry_spec_value(model_spec, "reference_rho", fallback_rho),
    reference_reservoir_pi_w = app_registry_spec_value(model_spec, "reference_pi_w", fallback_pi_w),
    reference_reservoir_pi_in = app_registry_spec_value(model_spec, "reference_pi_in", fallback_pi_in),
    reference_reservoir_win_scale_global = app_registry_spec_value(model_spec, "reference_win_scale_global", fallback_win_global),
    reference_reservoir_win_scale_bias = app_registry_spec_value(model_spec, "reference_win_scale_bias", fallback_win_bias),
    reference_reservoir_seed = app_registry_spec_value(model_spec, "reference_seed", fallback_seed),
    discrepancy_reservoir_depth = app_registry_spec_value(model_spec, "discrepancy_D", fallback_depth),
    discrepancy_reservoir_size = app_registry_spec_value(model_spec, "discrepancy_n", fallback_size),
    discrepancy_reducer_size = app_registry_spec_value(model_spec, "discrepancy_n_tilde", fallback_reducer),
    discrepancy_reservoir_memory = app_registry_spec_value(model_spec, "discrepancy_m", fallback_memory),
    discrepancy_reservoir_washout = app_registry_spec_value(model_spec, "discrepancy_washout", fallback_washout),
    discrepancy_reservoir_alpha = app_registry_spec_value(model_spec, "discrepancy_alpha", fallback_alpha),
    discrepancy_reservoir_rho = app_registry_spec_value(model_spec, "discrepancy_rho", fallback_rho),
    discrepancy_reservoir_pi_w = app_registry_spec_value(model_spec, "discrepancy_pi_w", fallback_pi_w),
    discrepancy_reservoir_pi_in = app_registry_spec_value(model_spec, "discrepancy_pi_in", fallback_pi_in),
    discrepancy_reservoir_win_scale_global = app_registry_spec_value(model_spec, "discrepancy_win_scale_global", fallback_win_global),
    discrepancy_reservoir_win_scale_bias = app_registry_spec_value(model_spec, "discrepancy_win_scale_bias", fallback_win_bias),
    discrepancy_reservoir_seed = app_registry_spec_value(model_spec, "discrepancy_seed", fallback_seed),
    rhs_shared_tau0 = app_registry_spec_value(model_spec, "shared_rhs_tau0", cfg$inference$vb_ld$rhs_tau0 %||% NA),
    rhs_discrepancy_tau0 = app_registry_spec_value(model_spec, "discrepancy_rhs_tau0", cfg$inference$vb_ld$rhs_alpha_tau0 %||% cfg$inference$vb_ld$rhs_tau0 %||% NA),
    spread_calibration_enabled = ifelse(spread_enabled, "yes", "no"),
    spread_calibration_factor = app_format_decimal(spread_row$spread_calibration_factor[[1L]], 1L),
    spread_calibration_additive_width = app_format_decimal(spread_row$spread_calibration_additive_width[[1L]], 1L),
    spread_calibration_center_quantile = app_format_decimal(spread_row$center_quantile[[1L]], 2L),
    spread_calibration_id = as.character(spread_row$calibration_id[[1L]] %||% "none"),
    spread_calibration_description = if (spread_enabled) {
      sprintf(
        "An additional spread calibration is applied before display around quantile %s, with multiplicative factor %s and additive half-width %s.",
        app_format_decimal(spread_row$center_quantile[[1L]], 2L),
        app_format_decimal(spread_row$spread_calibration_factor[[1L]], 1L),
        app_format_decimal(spread_row$spread_calibration_additive_width[[1L]], 1L)
      )
    } else {
      "No additional spread calibration is applied before display; the displayed bands are synthesized from the fitted quantile models and then passed through monotone rearrangement."
    },
    observed_history_acrps = if (nrow(observed_row)) app_format_decimal(observed_history_acrps, 4L) else "",
    observed_history_crps = if (nrow(observed_row)) app_format_decimal(observed_history_acrps, 4L) else "",
    observed_history_coverage = if (nrow(observed_row)) app_format_decimal(observed_row$interval_coverage[[1L]], 3L) else "",
    observed_history_dates = if (nrow(observed_row)) app_format_integer(observed_row$n_dates[[1L]]) else ""
  )
  app_write_current_application_registry_tex(current_values, app_path(registry_tex))

  selected_paths <- c(
    current_registry = registry_tex,
    current_score_tex = score_tex,
    current_score_csv = score_csv,
    promotion_manifest = current_values$promotion_manifest,
    corrected_paths_figure = current_values$corrected_paths_figure,
    forecast_window_figure = current_values$forecast_window_figure,
    diagnostic_traces_figure = current_values$diagnostic_traces_figure,
    run_config_snapshot = app_latex_file_path(config_snapshot_path),
    fit_diagnostics = app_latex_file_path(fit_diag_path),
    score_summary_csv = app_latex_file_path(score_path)
  )
  optional_selected <- c(
    authoritative_model_spec = model_spec_path,
    authoritative_component_registry = app_manifest_optional_role_path(manifest, "authoritative_component_registry"),
    authoritative_promotion_decision = app_manifest_optional_role_path(manifest, "authoritative_promotion_decision"),
    authoritative_component_integrity_audit = app_manifest_optional_role_path(manifest, "authoritative_component_integrity_audit"),
    observed_history_full7_ranking = observed_history_path
  )
  keep_optional <- !is.na(optional_selected) & nzchar(optional_selected) & file.exists(optional_selected)
  if (any(keep_optional)) {
    selected_paths <- c(selected_paths, vapply(optional_selected[keep_optional], app_latex_file_path, character(1L)))
  }
  selected_abs_paths <- ifelse(
    grepl("^/", unname(selected_paths)),
    unname(selected_paths),
    file.path(app_repo_root(), unname(selected_paths))
  )
  selection <- data.frame(
    role = names(selected_paths),
    path = unname(selected_paths),
    sha256 = vapply(selected_abs_paths, app_sha256_file, character(1L)),
    selected_run_id = current_values$run_id,
    selected_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    selection_git_sha = app_git_sha(short = FALSE) %||% NA_character_,
    promotion_article_git_sha = unique(manifest$article_git_sha %||% NA_character_)[[1L]],
    engine_repo_sha = unique(manifest$engine_repo_sha %||% NA_character_)[[1L]],
    stringsAsFactors = FALSE
  )
  app_write_csv(selection, app_path(selection_manifest))
  if (!isTRUE(quiet)) cat(app_path(registry_tex), "\n")
  invisible(list(summary = summary, registry = current_values, selection = selection))
}
