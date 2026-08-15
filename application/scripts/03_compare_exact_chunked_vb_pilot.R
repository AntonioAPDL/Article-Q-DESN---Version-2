#!/usr/bin/env Rscript
# Purpose: run or compare exact-chunked latent-path AL-VB pilot fits.
# The fit mode is intended to be launched once per config under /usr/bin/time -v
# so peak resident set size is measured by the parent process.

options(error = quote({
  cat("\n--- traceback ---\n", file = stderr())
  traceback(2)
  q(status = 1, save = "no")
}))

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/launch_control.R"))
source(app_path("application/R/artifact_hygiene.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_application_panel.R"))
source(app_path("application/R/build_qdesn_features.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/fit_qdesn_discrepancy.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/fit_qdesn_latent_path.R"))

args <- app_parse_args(list(
  mode = "fit",
  config = NULL,
  label = NULL,
  output_dir = "application/logs/exact_chunked_vb_fullspec_pilot_20260527",
  left_result = NULL,
  right_result = NULL,
  left_time_log = NULL,
  right_time_log = NULL,
  comparison_prefix = "paired_fullspec_exact_chunked",
  comparison_title = "Exact Chunked VB Pilot Comparison",
  tolerance = 1.0e-7,
  max_iter = NULL,
  n_draws = NULL,
  chunk_size = NULL,
  trace_chunking = NULL,
  profile_substeps = NULL,
  draw_backend = NULL
))

app_max_abs <- function(a, b) {
  a <- as.numeric(a)
  b <- as.numeric(b)
  if (!length(a) && !length(b)) return(0)
  max(abs(a - b), na.rm = TRUE)
}

app_min_symmetric_eigenvalue <- function(x) {
  x <- as.matrix(x)
  min(eigen((x + t(x)) / 2, symmetric = TRUE, only.values = TRUE)$values)
}

app_pilot_label <- function(path, label = NULL) {
  label <- as.character(label %||% "")[[1L]]
  if (nzchar(label)) return(label)
  tools::file_path_sans_ext(basename(path))
}

app_check_latent_no_leakage_from_fit <- function(result) {
  probe <- result$design$future_builder(result$fit$summary$y_future_mean)
  audits <- list(
    probe$continuation$future_input_audit %||% NULL,
    probe$continuation_beta$future_input_audit %||% NULL,
    probe$continuation_alpha$future_input_audit %||% NULL
  )
  cutoff_date <- result$design$latent_data$train_end
  checked <- 0L
  for (audit in audits) {
    if (is.null(audit) || !nrow(audit)) next
    app_latent_path_validate_no_usgs_leakage(
      data.frame(date = audit$input_date, role = audit$role, stringsAsFactors = FALSE),
      cutoff_date = cutoff_date
    )
    checked <- checked + 1L
  }
  checked
}

app_chunking_summary <- function(cfg) {
  ch <- cfg$inference$vb_ld$chunking %||% list(enabled = FALSE)
  data.frame(
    chunking_enabled = isTRUE(ch$enabled),
    chunking_mode = as.character(ch$mode %||% NA_character_),
    chunk_size = as.integer(ch$chunk_size %||% NA_integer_),
    chunking_order = as.character(ch$order %||% NA_character_),
    stringsAsFactors = FALSE
  )
}

app_apply_pilot_overrides <- function(cfg, max_iter = NULL, n_draws = NULL, chunk_size = NULL,
                                      trace_chunking = NULL, profile_substeps = NULL,
                                      draw_backend = NULL) {
  if (!is.null(max_iter) && nzchar(as.character(max_iter))) {
    max_iter <- as.integer(max_iter)
    if (!is.finite(max_iter) || max_iter < 1L) stop("--max_iter must be a positive integer.", call. = FALSE)
    cfg$inference$vb_ld$max_iter <- max_iter
    cfg$inference$vb_ld$max_iter_hard_cap <- max(
      as.integer(cfg$inference$vb_ld$max_iter_hard_cap %||% max_iter),
      max_iter
    )
  }
  if (!is.null(n_draws) && nzchar(as.character(n_draws))) {
    n_draws <- as.integer(n_draws)
    if (!is.finite(n_draws) || n_draws < 1L) stop("--n_draws must be a positive integer.", call. = FALSE)
    cfg$inference$vb_ld$n_draws <- n_draws
  }
  if (!is.null(chunk_size) && nzchar(as.character(chunk_size))) {
    chunk_size <- as.integer(chunk_size)
    if (!is.finite(chunk_size) || chunk_size < 1L) stop("--chunk_size must be a positive integer.", call. = FALSE)
    cfg$inference$vb_ld$chunking <- cfg$inference$vb_ld$chunking %||% list(enabled = TRUE, mode = "exact", order = "sequential")
    cfg$inference$vb_ld$chunking$enabled <- TRUE
    cfg$inference$vb_ld$chunking$mode <- "exact"
    cfg$inference$vb_ld$chunking$chunk_size <- chunk_size
    cfg$inference$vb_ld$chunking$order <- cfg$inference$vb_ld$chunking$order %||% "sequential"
  }
  if (!is.null(trace_chunking) && nzchar(as.character(trace_chunking))) {
    cfg$inference$vb_ld$chunking <- cfg$inference$vb_ld$chunking %||% list(enabled = TRUE, mode = "exact", order = "sequential")
    cfg$inference$vb_ld$chunking$trace <- app_as_bool(trace_chunking)
  }
  if (!is.null(profile_substeps) && nzchar(as.character(profile_substeps))) {
    cfg$inference$vb_ld$diagnostics <- cfg$inference$vb_ld$diagnostics %||% list()
    cfg$inference$vb_ld$diagnostics$profile_substeps <- app_as_bool(profile_substeps)
  }
  if (!is.null(draw_backend) && nzchar(as.character(draw_backend))) {
    cfg$inference$vb_ld$draw_backend <- tolower(as.character(draw_backend)[[1L]])
  }
  cfg
}

app_override_signature <- function(max_iter = NULL, n_draws = NULL, chunk_size = NULL,
                                   trace_chunking = NULL, profile_substeps = NULL,
                                   draw_backend = NULL) {
  vals <- c(
    max_iter = as.character(max_iter %||% ""),
    n_draws = as.character(n_draws %||% ""),
    chunk_size = as.character(chunk_size %||% ""),
    trace_chunking = as.character(trace_chunking %||% ""),
    profile_substeps = as.character(profile_substeps %||% ""),
    draw_backend = as.character(draw_backend %||% "")
  )
  paste(sprintf("%s=%s", names(vals), vals), collapse = ";")
}

app_fit_exact_chunked_pilot <- function(config_path, label, output_dir, max_iter = NULL, n_draws = NULL,
                                        chunk_size = NULL, trace_chunking = NULL,
                                        profile_substeps = NULL, draw_backend = NULL) {
  cfg <- app_read_config(app_path(config_path))
  cfg <- app_apply_pilot_overrides(
    cfg,
    max_iter = max_iter,
    n_draws = n_draws,
    chunk_size = chunk_size,
    trace_chunking = trace_chunking,
    profile_substeps = profile_substeps,
    draw_backend = draw_backend
  )
  app_validate_application_model_contract(cfg)
  app_ensure_dir(output_dir)

  model_grid <- app_validate_model_grid(app_config_path(cfg, "model_grid"), app_config_path(cfg, "schema"))
  qrows <- model_grid[
    model_grid$model_family == "qdesn_glofas_discrepancy" &
      app_as_bool_vec(model_grid$enabled %||% TRUE),
    ,
    drop = FALSE
  ]
  if (nrow(qrows) != 1L) {
    stop(sprintf("Expected one enabled Q-DESN discrepancy pilot row; found %d.", nrow(qrows)), call. = FALSE)
  }
  model_row <- qrows[1L, , drop = FALSE]
  engine_report <- app_check_qdesn_engine_api(
    cfg,
    require_discrepancy = app_qdesn_engine_requires_discrepancy_export(cfg, model_grid),
    stop_on_failure = TRUE
  )
  validated <- app_validate_input_manifest(
    app_config_path(cfg, "input_manifest"),
    app_config_path(cfg, "schema"),
    require_files = TRUE
  )
  if (!isTRUE(validated$ok)) {
    stop(paste(validated$issues, collapse = "\n"), call. = FALSE)
  }

  panel <- app_build_application_panel(cfg, validated$manifest, validated$schema)
  app_validate_panel(panel, validated$schema)
  cutoff_row <- app_latent_path_default_cutoff_row(cfg)
  gc(reset = TRUE)
  fit_time <- system.time({
    result <- app_fit_qdesn_latent_path(panel, cfg, model_row, cutoff_row = cutoff_row)
  })
  prediction <- app_predict_qdesn_latent_path_draws(result, panel, cfg, model_row)
  no_leakage_audits_checked <- app_check_latent_no_leakage_from_fit(result)
  identity_error <- app_max_abs(
    prediction$draws$q_y_draw,
    prediction$draws$q_g_draw - prediction$draws$d_g_draw
  )
  chunking <- app_chunking_summary(cfg)
  summary <- data.frame(
    label = label,
    config_path = normalizePath(app_path(config_path), mustWork = TRUE),
    config_hash = app_sha256_file(app_path(config_path)),
    override_signature = app_override_signature(max_iter, n_draws, chunk_size, trace_chunking, profile_substeps, draw_backend),
    article_git_sha = app_git_sha(short = FALSE) %||% NA_character_,
    engine_sha = engine_report$repo_git_sha %||% NA_character_,
    engine_branch = engine_report$repo_branch %||% NA_character_,
    application_name = cfg$application_name %||% NA_character_,
    fit_id = result$fit_id,
    model_id = result$model_id,
    cutoff_id = cutoff_row$cutoff_id[[1L]],
    origin_date = as.character(cutoff_row$origin_date[[1L]]),
    reservoir_seed = as.integer(app_model_row_value(model_row, "reservoir_seed", cfg$reservoir$seed %||% NA_integer_)),
    design_hash = result$design_summary$design_hash[[1L]],
    n_fixed_rows = result$design_summary$n_fixed_rows[[1L]],
    n_stacked_rows = result$design_summary$n_stacked_rows[[1L]],
    n_augmented_features = result$design_summary$n_augmented_features[[1L]],
    vb_converged = isTRUE(result$fit$vb_diagnostics$converged),
    vb_iterations = as.integer(result$fit$vb_diagnostics$iterations),
    vb_iteration_timing_rows = nrow(result$fit$vb_diagnostics$iteration_timing %||% data.frame()),
    vb_stage_timing_rows = nrow(result$fit$vb_diagnostics$stage_timing %||% data.frame()),
    vb_substep_timing_rows = nrow(result$fit$vb_diagnostics$substep_timing %||% data.frame()),
    draw_backend_requested = result$fit$vb_diagnostics$draw_backend_requested %||% NA_character_,
    theta_draw_backend = result$fit$vb_diagnostics$theta_draw_backend %||% NA_character_,
    future_draw_backend = result$fit$vb_diagnostics$future_draw_backend %||% NA_character_,
    fit_elapsed_sec = as.numeric(fit_time[["elapsed"]]),
    posterior_identity_max_abs = identity_error,
    no_leakage_audits_checked = no_leakage_audits_checked,
    y_future_cov_min_eigen = app_min_symmetric_eigenvalue(result$fit$summary$y_future_cov),
    stringsAsFactors = FALSE
  )
  summary <- cbind(summary, chunking)

  state <- list(
    theta_mean = result$fit$summary$theta_mean,
    theta_cov = result$fit$summary$theta_cov,
    sigma_mean = result$fit$summary$sigma_mean,
    sigma_shape = result$fit$variational_state$sigma$shape,
    sigma_rate = result$fit$variational_state$sigma$rate,
    y_future_mean = result$fit$summary$y_future_mean,
    y_future_cov = result$fit$summary$y_future_cov,
    elbo_trace = result$fit$vb_diagnostics$elbo_trace
  )
  out <- list(
    summary = summary,
    state = state,
    fit_diagnostics = result$fit$vb_diagnostics,
    prediction_draw_check = data.frame(
      label = label,
      n_draw_rows = nrow(prediction$draws),
      n_unique_draws = length(unique(prediction$draws$draw_id)),
      n_prediction_keys = nrow(prediction$summary),
      max_identity_error = identity_error,
      all_identity_errors_within_tolerance = identity_error <= 1.0e-10,
      stringsAsFactors = FALSE
    )
  )
  result_path <- file.path(output_dir, paste0(label, "__fit_state.rds"))
  summary_path <- file.path(output_dir, paste0(label, "__fit_summary.csv"))
  saveRDS(out, result_path)
  app_write_csv(summary, summary_path)
  if (nrow(result$fit$vb_diagnostics$iteration_timing %||% data.frame())) {
    app_write_csv(
      result$fit$vb_diagnostics$iteration_timing,
      file.path(output_dir, paste0(label, "__vb_iteration_timing.csv"))
    )
  }
  if (nrow(result$fit$vb_diagnostics$stage_timing %||% data.frame())) {
    app_write_csv(
      result$fit$vb_diagnostics$stage_timing,
      file.path(output_dir, paste0(label, "__fit_stage_timing.csv"))
    )
  }
  if (nrow(result$fit$vb_diagnostics$substep_timing %||% data.frame())) {
    app_write_csv(
      result$fit$vb_diagnostics$substep_timing,
      file.path(output_dir, paste0(label, "__vb_substep_timing.csv"))
    )
  }
  message(result_path)
  invisible(result_path)
}

app_read_time_v_log <- function(path) {
  if (is.null(path) || !nzchar(as.character(path)) || !file.exists(path)) {
    return(data.frame(
      time_log = as.character(path %||% NA_character_),
      time_elapsed_wall = NA_character_,
      max_rss_kb = NA_real_,
      user_seconds = NA_real_,
      system_seconds = NA_real_,
      percent_cpu = NA_character_,
      stringsAsFactors = FALSE
    ))
  }
  lines <- readLines(path, warn = FALSE)
  get_value <- function(pattern) {
    hit <- grep(pattern, lines, value = TRUE)
    if (!length(hit)) return(NA_character_)
    if (grepl("Elapsed", pattern, fixed = TRUE)) {
      return(trimws(sub("^\\s*Elapsed \\(wall clock\\) time \\(h:mm:ss or m:ss\\):\\s*", "", hit[[1L]])))
    }
    trimws(sub("^\\s*[^:]+:\\s*", "", hit[[1L]]))
  }
  data.frame(
    time_log = normalizePath(path, mustWork = FALSE),
    time_elapsed_wall = get_value("Elapsed \\(wall clock\\) time"),
    max_rss_kb = suppressWarnings(as.numeric(get_value("Maximum resident set size"))),
    user_seconds = suppressWarnings(as.numeric(get_value("User time"))),
    system_seconds = suppressWarnings(as.numeric(get_value("System time"))),
    percent_cpu = get_value("Percent of CPU"),
    stringsAsFactors = FALSE
  )
}

app_clean_config_for_twin_compare <- function(path) {
  cfg <- app_read_yaml(path)
  cfg$application_name <- NULL
  cfg$description <- NULL
  cfg$paths$cache <- NULL
  cfg$inference$vb_ld$chunking <- NULL
  cfg$execution$prelaunch$purpose <- NULL
  cfg$execution$final_launch$note <- NULL
  cfg
}

app_md_table <- function(x) {
  if (!nrow(x)) return(character())
  cols <- names(x)
  out <- c(
    paste(c("", cols, ""), collapse = " | "),
    paste(c("", rep("---", length(cols)), ""), collapse = " | ")
  )
  for (i in seq_len(nrow(x))) {
    vals <- vapply(x[i, , drop = FALSE], function(v) as.character(v[[1L]]), character(1L))
    out <- c(out, paste(c("", vals, ""), collapse = " | "))
  }
  out
}

app_compare_exact_chunked_pilots <- function(left_result, right_result, output_dir, left_time_log, right_time_log,
                                             tolerance, comparison_prefix, comparison_title) {
  left <- readRDS(left_result)
  right <- readRDS(right_result)
  app_ensure_dir(output_dir)

  metrics <- data.frame(
    metric = c(
      "theta_mean",
      "theta_cov",
      "sigma_mean",
      "sigma_shape",
      "sigma_rate",
      "y_future_mean",
      "y_future_cov",
      "elbo_trace"
    ),
    max_abs_diff = c(
      app_max_abs(left$state$theta_mean, right$state$theta_mean),
      app_max_abs(left$state$theta_cov, right$state$theta_cov),
      app_max_abs(left$state$sigma_mean, right$state$sigma_mean),
      app_max_abs(left$state$sigma_shape, right$state$sigma_shape),
      app_max_abs(left$state$sigma_rate, right$state$sigma_rate),
      app_max_abs(left$state$y_future_mean, right$state$y_future_mean),
      app_max_abs(left$state$y_future_cov, right$state$y_future_cov),
      app_max_abs(left$state$elbo_trace, right$state$elbo_trace)
    ),
    gate = TRUE,
    stringsAsFactors = FALSE
  )

  left_sum <- left$summary
  right_sum <- right$summary
  left_time <- cbind(label = left_sum$label[[1L]], app_read_time_v_log(left_time_log))
  right_time <- cbind(label = right_sum$label[[1L]], app_read_time_v_log(right_time_log))
  timing <- rbind(left_time, right_time)
  config_clean_equivalent <- identical(
    app_clean_config_for_twin_compare(left_sum$config_path[[1L]]),
    app_clean_config_for_twin_compare(right_sum$config_path[[1L]])
  )
  summary <- data.frame(
    left_label = left_sum$label[[1L]],
    right_label = right_sum$label[[1L]],
    left_config_hash = left_sum$config_hash[[1L]],
    right_config_hash = right_sum$config_hash[[1L]],
    intended_config_differences_only = config_clean_equivalent,
    same_engine_sha = identical(left_sum$engine_sha[[1L]], right_sum$engine_sha[[1L]]),
    engine_sha = right_sum$engine_sha[[1L]],
    same_design_hash = identical(left_sum$design_hash[[1L]], right_sum$design_hash[[1L]]),
    design_hash = right_sum$design_hash[[1L]],
    same_model_id = identical(left_sum$model_id[[1L]], right_sum$model_id[[1L]]),
    same_fit_id = identical(left_sum$fit_id[[1L]], right_sum$fit_id[[1L]]),
    same_cutoff_id = identical(left_sum$cutoff_id[[1L]], right_sum$cutoff_id[[1L]]),
    left_converged = left_sum$vb_converged[[1L]],
    right_converged = right_sum$vb_converged[[1L]],
    left_iterations = left_sum$vb_iterations[[1L]],
    right_iterations = right_sum$vb_iterations[[1L]],
    left_fit_elapsed_sec = left_sum$fit_elapsed_sec[[1L]],
    right_fit_elapsed_sec = right_sum$fit_elapsed_sec[[1L]],
    left_max_rss_kb = timing$max_rss_kb[timing$label == left_sum$label[[1L]]][[1L]],
    right_max_rss_kb = timing$max_rss_kb[timing$label == right_sum$label[[1L]]][[1L]],
    left_identity_max_abs = left_sum$posterior_identity_max_abs[[1L]],
    right_identity_max_abs = right_sum$posterior_identity_max_abs[[1L]],
    left_no_leakage_audits_checked = left_sum$no_leakage_audits_checked[[1L]],
    right_no_leakage_audits_checked = right_sum$no_leakage_audits_checked[[1L]],
    left_y_future_cov_min_eigen = left_sum$y_future_cov_min_eigen[[1L]],
    right_y_future_cov_min_eigen = right_sum$y_future_cov_min_eigen[[1L]],
    max_gate_diff = max(metrics$max_abs_diff[metrics$gate], na.rm = TRUE),
    tolerance = tolerance,
    passed = FALSE,
    stringsAsFactors = FALSE
  )
  summary$passed <- isTRUE(summary$intended_config_differences_only) &&
    isTRUE(summary$same_engine_sha) &&
    isTRUE(summary$same_design_hash) &&
    isTRUE(summary$same_model_id) &&
    isTRUE(summary$same_cutoff_id) &&
    identical(summary$left_iterations, summary$right_iterations) &&
    summary$left_identity_max_abs <= 1.0e-10 &&
    summary$right_identity_max_abs <= 1.0e-10 &&
    is.finite(summary$left_y_future_cov_min_eigen) &&
    is.finite(summary$right_y_future_cov_min_eigen) &&
    summary$max_gate_diff <= tolerance

  comparison_prefix <- gsub("[^A-Za-z0-9_.-]+", "_", comparison_prefix)
  app_write_csv(metrics, file.path(output_dir, paste0(comparison_prefix, "_metrics.csv")))
  app_write_csv(summary, file.path(output_dir, paste0(comparison_prefix, "_summary.csv")))
  app_write_csv(timing, file.path(output_dir, paste0(comparison_prefix, "_timing.csv")))

  md <- c(
    paste0("# ", comparison_title),
    "",
    "## Summary",
    "",
    app_md_table(summary),
    "",
    "## Fitted-State Metrics",
    "",
    app_md_table(metrics),
    "",
    "## Timing",
    "",
    app_md_table(timing)
  )
  writeLines(md, file.path(output_dir, paste0(comparison_prefix, "_comparison.md")))
  print(summary)
  print(metrics)
  print(timing)
  if (!isTRUE(summary$passed[[1L]])) {
    stop("Paired exact-chunked pilot comparison failed its fitted-state gate.", call. = FALSE)
  }
  invisible(summary)
}

mode <- tolower(as.character(args$mode %||% "fit")[[1L]])
output_dir <- app_path(args$output_dir)
if (identical(mode, "fit")) {
  if (is.null(args$config)) stop("--config is required for mode=fit.", call. = FALSE)
  label <- app_pilot_label(args$config, args$label)
  app_fit_exact_chunked_pilot(
    args$config,
    label = label,
    output_dir = output_dir,
    max_iter = args$max_iter,
    n_draws = args$n_draws,
    chunk_size = args$chunk_size,
    trace_chunking = args$trace_chunking,
    profile_substeps = args$profile_substeps,
    draw_backend = args$draw_backend
  )
} else if (identical(mode, "compare")) {
  if (is.null(args$left_result) || is.null(args$right_result)) {
    stop("--left_result and --right_result are required for mode=compare.", call. = FALSE)
  }
  app_compare_exact_chunked_pilots(
    left_result = app_path(args$left_result),
    right_result = app_path(args$right_result),
    output_dir = output_dir,
    left_time_log = if (is.null(args$left_time_log)) NULL else app_path(args$left_time_log),
    right_time_log = if (is.null(args$right_time_log)) NULL else app_path(args$right_time_log),
    tolerance = as.numeric(args$tolerance %||% 1.0e-7),
    comparison_prefix = as.character(args$comparison_prefix %||% "paired_fullspec_exact_chunked")[[1L]],
    comparison_title = as.character(args$comparison_title %||% "Exact Chunked VB Pilot Comparison")[[1L]]
  )
} else {
  stop(sprintf("Unsupported mode '%s'. Use fit or compare.", mode), call. = FALSE)
}
