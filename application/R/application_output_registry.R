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
  if (grepl("qdesn", family) || grepl("qdesn", id)) return("Q--DESN calibration")
  if (grepl("raw_glofas", family) || grepl("raw_glofas", id)) return("Raw GloFAS")
  as.character(model_id)
}

app_format_decimal <- function(x, digits = 4L) {
  if (!is.finite(as.numeric(x))) return("")
  sprintf(paste0("%.", digits, "f"), as.numeric(x))
}

app_format_percent <- function(x, digits = 1L) {
  if (!is.finite(as.numeric(x))) return("")
  paste0(sprintf(paste0("%.", digits, "f"), 100 * as.numeric(x)), "\\%")
}

app_format_config_vector <- function(x, empty = "none", missing = "NA") {
  v <- unlist(x, use.names = FALSE)
  if (!length(v)) return(empty)
  if (all(is.na(v))) return(missing)
  paste(v, collapse = ",")
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
      crps_quantile_grid_mean = if ("crps_quantile_grid_mean" %in% names(row)) as.numeric(row$crps_quantile_grid_mean[[1L]]) else NA_real_,
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
  has_full_quantile_scores <- all(c("interval_score_mean", "crps_quantile_grid_mean") %in% names(summary)) &&
    any(is.finite(summary$interval_score_mean)) &&
    any(is.finite(summary$crps_quantile_grid_mean))
  if (has_full_quantile_scores) {
    lines <- c(
      "% Generated by application/R/application_output_registry.R",
      "\\small",
      "\\begin{tabular}{lrrrrrr}",
      "\\toprule",
      "Model & Horizons & Check & Interval & CRPS & Coverage & Reduction \\\\",
      "\\midrule"
    )
    for (i in seq_len(nrow(summary))) {
      lines <- c(lines, sprintf(
        "%s & %d & %s & %s & %s & %s & %s \\\\",
        app_latex_escape_text(summary$model_label[[i]]),
        summary$n_scored_horizons[[i]],
        app_format_decimal(summary$check_loss_mean[[i]], 4L),
        app_format_decimal(summary$interval_score_mean[[i]], 4L),
        app_format_decimal(summary$crps_quantile_grid_mean[[i]], 4L),
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
    command("GlofasApplicationCurrentReservoirSeed", values$reservoir_seed),
    command("GlofasApplicationCurrentSharedRhsTau", values$rhs_shared_tau0),
    command("GlofasApplicationCurrentDiscrepancyRhsTau", values$rhs_discrepancy_tau0),
    command("GlofasApplicationCurrentRhsTau", values$rhs_shared_tau0),
    command("GlofasApplicationCurrentSpreadCalibrationEnabled", values$spread_calibration_enabled),
    command("GlofasApplicationCurrentSpreadCalibrationFactor", values$spread_calibration_factor),
    command("GlofasApplicationCurrentSpreadCalibrationAdditiveWidth", values$spread_calibration_additive_width),
    command("GlofasApplicationCurrentSpreadCalibrationCenterQuantile", values$spread_calibration_center_quantile),
    text_command("GlofasApplicationCurrentSpreadCalibrationId", values$spread_calibration_id)
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
  qdesn <- summary[grepl("Q--DESN", summary$model_label), , drop = FALSE]
  raw <- summary[grepl("Raw GloFAS", summary$model_label), , drop = FALSE]
  if (nrow(qdesn) != 1L || nrow(raw) != 1L) {
    stop("Current application score summary must contain one Q-DESN row and one raw GloFAS row.", call. = FALSE)
  }

  current_values <- list(
    run_id = unique(manifest$run_id)[[1L]],
    config_path = app_latex_file_path(config_snapshot_path),
    promotion_manifest = app_latex_file_path(manifest_path),
    selection_manifest = selection_manifest,
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
    qdesn_crps = app_format_decimal(qdesn$crps_quantile_grid_mean[[1L]], 4L),
    raw_crps = app_format_decimal(raw$crps_quantile_grid_mean[[1L]], 4L),
    crps_reduction = if (is.finite(raw$crps_quantile_grid_mean[[1L]]) && raw$crps_quantile_grid_mean[[1L]] > 0) {
      app_format_percent((raw$crps_quantile_grid_mean[[1L]] - qdesn$crps_quantile_grid_mean[[1L]]) / raw$crps_quantile_grid_mean[[1L]], 1L)
    } else {
      ""
    },
    qdesn_mean_coverage = app_format_decimal(qdesn$interval_coverage_mean[[1L]], 3L),
    raw_mean_coverage = app_format_decimal(raw$interval_coverage_mean[[1L]], 3L),
    scored_horizons = as.character(qdesn$n_scored_horizons[[1L]]),
    origin_date = as.character(band$origin_date[[1L]]),
    vb_iterations = if ("vb_iterations" %in% names(fit_diag)) {
      paste0("median ", stats::median(as.numeric(fit_diag$vb_iterations), na.rm = TRUE), "; max ", max(as.numeric(fit_diag$vb_iterations), na.rm = TRUE))
    } else {
      NA_character_
    },
    reservoir_depth = as.character(cfg$reservoir$D %||% NA),
    reservoir_size = app_format_config_vector(cfg$reservoir$n %||% NA),
    reducer_size = app_format_config_vector(cfg$reservoir$n_tilde %||% list(), empty = "none"),
    reservoir_memory = as.character(cfg$reservoir$m %||% NA),
    reservoir_washout = as.character(cfg$reservoir$washout %||% NA),
    reservoir_alpha = app_format_config_vector(cfg$reservoir$alpha %||% NA),
    reservoir_rho = app_format_config_vector(cfg$reservoir$rho %||% NA),
    reservoir_seed = as.character(cfg$reservoir$seed %||% NA),
    rhs_shared_tau0 = as.character(cfg$inference$vb_ld$rhs_tau0 %||% NA),
    rhs_discrepancy_tau0 = as.character(cfg$inference$vb_ld$rhs_alpha_tau0 %||% cfg$inference$vb_ld$rhs_tau0 %||% NA),
    spread_calibration_enabled = ifelse(isTRUE(app_as_bool_vec(spread_row$enabled)[[1L]]), "yes", "no"),
    spread_calibration_factor = app_format_decimal(spread_row$spread_calibration_factor[[1L]], 1L),
    spread_calibration_additive_width = app_format_decimal(spread_row$spread_calibration_additive_width[[1L]], 1L),
    spread_calibration_center_quantile = app_format_decimal(spread_row$center_quantile[[1L]], 2L),
    spread_calibration_id = as.character(spread_row$calibration_id[[1L]] %||% "none")
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
