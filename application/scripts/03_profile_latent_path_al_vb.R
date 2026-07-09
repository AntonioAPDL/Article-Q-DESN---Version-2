#!/usr/bin/env Rscript
# Purpose: profile the latent-path AL-VB design and one-step update cost without
# launching the full fit.
# Inputs: application panel, model grid, cutoff file, and application config.
# Outputs: profile step timings, dimensions, and readiness notes.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_qdesn_features.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/fit_qdesn_discrepancy.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/fit_qdesn_latent_path.R"))

args <- app_parse_args(list(
  config = "application/config/glofas_latent_path_al_vb_dec25_full.yaml",
  run_id = NULL,
  fit_id = "",
  update_theta = "true",
  future_laplace = "false",
  save_design = "true",
  force_heavy = "false",
  dense_future_moments_mb_limit = "16000"
))

cfg <- app_read_config(app_path(args$config))
app_validate_application_model_contract(cfg)
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id %||% app_run_id(cfg))
app_stage_start("03_profile_latent_path_al_vb", run_dirs)
tryCatch({
  panel_path <- file.path(app_config_path(cfg, "cache"), "application_panel.rds")
  if (!file.exists(panel_path)) {
    stop(sprintf("Missing application panel: %s. Run 01_build_panel.R for this config first.", panel_path), call. = FALSE)
  }
  panel <- readRDS(panel_path)
  model_grid <- app_validate_model_grid(app_config_path(cfg, "model_grid"), app_config_path(cfg, "schema"))
  cutoffs <- app_validate_cutoffs(app_config_path(cfg, "cutoffs"))
  cutoff_row <- cutoffs[1L, , drop = FALSE]
  qrows <- model_grid[model_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  if (nzchar(args$fit_id)) qrows <- qrows[qrows$fit_id == args$fit_id, , drop = FALSE]
  if (!nrow(qrows)) stop("No latent-path Q-DESN rows matched the profile request.", call. = FALSE)
  row <- qrows[1L, , drop = FALSE]
  if (!app_is_latent_path_contract(cfg, row)) {
    stop("The latent-path profiler requires application_model.contract = latent_path_ensemble_likelihood.", call. = FALSE)
  }

  steps <- list()
  object_rows <- list()
  assessment_rows <- list()
  rss_mb <- function() {
    status <- tryCatch(readLines(sprintf("/proc/%d/status", Sys.getpid()), warn = FALSE), error = function(e) character())
    hit <- grep("^VmRSS:", status, value = TRUE)
    if (!length(hit)) return(NA_real_)
    value <- suppressWarnings(as.numeric(strsplit(hit[[1L]], "[[:space:]]+")[[1L]][2L]))
    value / 1024
  }
  obj_mb <- function(x) as.numeric(utils::object.size(x)) / 1024^2
  dense_mb <- function(nr, nc) as.numeric(nr) * as.numeric(nc) * 8 / 1024^2
  record_object <- function(name, x) {
    object_rows[[length(object_rows) + 1L]] <<- data.frame(
      object = name,
      object_size_mb = obj_mb(x),
      process_rss_mb = rss_mb(),
      stringsAsFactors = FALSE
    )
    invisible(x)
  }
  record_step <- function(name, expr) {
    invisible(gc())
    mem_before <- sum(gc()[, "used"])
    rss_before <- rss_mb()
    start <- proc.time()[["elapsed"]]
    value <- force(expr)
    elapsed <- proc.time()[["elapsed"]] - start
    mem_after <- sum(gc()[, "used"])
    rss_after <- rss_mb()
    steps[[length(steps) + 1L]] <<- data.frame(
      step = name,
      elapsed_seconds = elapsed,
      gc_used_before = mem_before,
      gc_used_after = mem_after,
      rss_mb_before = rss_before,
      rss_mb_after = rss_after,
      rss_mb_delta = rss_after - rss_before,
      stringsAsFactors = FALSE
    )
    app_write_csv(app_bind_rows_fill(steps), file.path(run_dirs$tables, "latent_path_profile_steps.csv"))
    value
  }

  design <- record_step("build_latent_path_design", {
    app_make_glofas_latent_path_design(panel, cfg, row, cutoff_row = cutoff_row)
  })
  record_object("design", design)
  y0 <- as.numeric(design$y_future_init)
  future0 <- record_step("future_builder_initial_path", {
    design$future_builder(y0)
  })
  record_object("future_builder_initial_path", future0)
  vb_args <- app_make_qdesn_discrepancy_vb_args(
    cfg,
    prior = app_map_qdesn_prior(row$coefficient_prior[[1L]]),
    seed = as.integer(row$reservoir_seed[[1L]] %||% cfg$reservoir$seed %||% 20260513L),
    likelihood_family = "al"
  )
  future_moment_strategy <- app_latent_future_moment_strategy(vb_args)
  future_update_strategy <- app_latent_future_update_strategy(vb_args)
  future_objective_strategy <- app_latent_future_objective_strategy(vb_args)
  p <- ncol(design$H_fixed)
  g_future_index <- app_latent_future_g_index(future0)
  n_future_design_rows <- nrow(future0$H_y) + length(g_future_index)
  n_future_groups <- nrow(future0$H_y)
  assessment_rows[[length(assessment_rows) + 1L]] <- data.frame(
    assessment = "dense_full_covariance_profile",
    future_moment_strategy = future_moment_strategy,
    future_update_strategy = future_update_strategy,
    future_objective_strategy = future_objective_strategy,
    chunking_enabled = isTRUE((vb_args$chunking %||% list())$enabled),
    chunking_mode = as.character((vb_args$chunking %||% list())$mode %||% NA_character_),
    chunk_size = as.integer((vb_args$chunking %||% list())$chunk_size %||% NA_integer_),
    n_augmented_features = p,
    n_base_features = ncol(design$X_base),
    n_fixed_rows = nrow(design$H_fixed),
    n_future_dates = nrow(design$future_key),
    n_future_groups = n_future_groups,
    n_issued_glofas_rows = nrow(design$latent_data$g_ensemble),
    n_future_design_rows = n_future_design_rows,
    theta_cov_mb = dense_mb(p, p),
    theta_second_mb = dense_mb(p, p),
    fixed_design_mb = dense_mb(nrow(design$H_fixed), p),
    one_future_second_moment_mb = dense_mb(p, p),
    dense_future_second_moments_mb = dense_mb(p, p) * n_future_design_rows,
    streamed_peak_future_second_moment_mb = dense_mb(p, p) * 2,
    y_future_cov_mb = dense_mb(length(y0), length(y0)),
    requested_horizon_max = design$latent_data$requested_horizon_max,
    horizon_max = design$latent_data$horizon_max,
    horizon_scope = design$latent_data$horizon_scope,
    available_horizons = paste(design$latent_data$available_horizons, collapse = ","),
    stringsAsFactors = FALSE
  )
  dense_limit <- suppressWarnings(as.numeric(args$dense_future_moments_mb_limit))
  if (!is.finite(dense_limit) || dense_limit <= 0) dense_limit <- 16000
  dense_future_mb <- assessment_rows[[length(assessment_rows)]]$dense_future_second_moments_mb[[1L]]
  skip_heavy <- is.finite(dense_future_mb) &&
    dense_future_mb > dense_limit &&
    !app_as_bool(args$force_heavy) &&
    identical(future_moment_strategy, "dense_debug")
  assessment_rows[[length(assessment_rows)]]$dense_future_moments_mb_limit <- dense_limit
  assessment_rows[[length(assessment_rows)]]$heavy_steps_status <- if (isTRUE(skip_heavy)) {
    "skipped_dense_future_moment_cost"
  } else if (identical(future_moment_strategy, "streamed_grouped")) {
    "streamed_grouped_profile_allowed"
  } else {
    "profiled"
  }
  assessment_rows[[length(assessment_rows)]]$recommendation <- if (isTRUE(skip_heavy)) {
    "do_not_launch_full_covariance_vb_before_implementing_structured_future_moments"
  } else if (identical(future_moment_strategy, "streamed_grouped")) {
    "profile_streamed_grouped_updates_before_full_fit"
  } else {
    "heavy_profile_allowed_by_current_limit"
  }
  app_write_csv(app_bind_rows_fill(assessment_rows), file.path(run_dirs$tables, "latent_path_vb_structure_assessment.csv"))
  if (isTRUE(skip_heavy)) {
    step_table <- app_bind_rows_fill(steps)
    summary <- data.frame(
      fit_id = row$fit_id[[1L]],
      model_id = row$model_id[[1L]],
      quantile_level = as.numeric(row$quantile_level[[1L]]),
      likelihood_family = row$likelihood_family[[1L]],
      coefficient_prior = row$coefficient_prior[[1L]],
      n_fixed_rows = nrow(design$H_fixed),
      n_future_dates = nrow(design$future_key),
      n_future_groups = n_future_groups,
      n_issued_glofas_rows = nrow(design$latent_data$g_ensemble),
      n_augmented_features = ncol(design$H_fixed),
      n_base_features = ncol(design$X_base),
      future_moment_strategy = future_moment_strategy,
      future_update_strategy = future_update_strategy,
      future_objective_strategy = future_objective_strategy,
      chunking_enabled = isTRUE((vb_args$chunking %||% list())$enabled),
      chunking_mode = as.character((vb_args$chunking %||% list())$mode %||% NA_character_),
      chunk_size = as.integer((vb_args$chunking %||% list())$chunk_size %||% NA_integer_),
      requested_horizon_max = design$latent_data$requested_horizon_max,
      horizon_max = design$latent_data$horizon_max,
      horizon_scope = design$latent_data$horizon_scope,
      available_horizons = paste(design$latent_data$available_horizons, collapse = ","),
      total_profile_seconds = sum(step_table$elapsed_seconds),
      theta_update_profiled = FALSE,
      future_laplace_profiled = FALSE,
      heavy_steps_status = "skipped_dense_future_moment_cost",
      dense_future_second_moments_mb = dense_future_mb,
      dense_future_moments_mb_limit = dense_limit,
      design_hash = app_hash_latent_path_design(design),
      stringsAsFactors = FALSE
    )
    app_write_csv(summary, file.path(run_dirs$tables, "latent_path_profile_summary.csv"))
    app_write_csv(step_table, file.path(run_dirs$tables, "latent_path_profile_steps.csv"))
    app_write_csv(app_bind_rows_fill(object_rows), file.path(run_dirs$tables, "latent_path_profile_object_sizes.csv"))
    if (app_as_bool(args$save_design)) {
      saveRDS(design, file.path(run_dirs$objects, "latent_path_profile_design.rds"))
    }
    app_stage_done(
      "03_profile_latent_path_al_vb",
      run_dirs,
      message = "Latent-path AL-VB heavy profile skipped because dense future-row moments exceed the configured limit."
    )
    cat(file.path(run_dirs$tables, "latent_path_vb_structure_assessment.csv"), "\n")
    quit(status = 0)
  }
  theta_mean <- rep(0, p)
  theta_cov <- diag(1, p)
  record_object("theta_cov_initial", theta_cov)
  y_cov <- diag(rep(stats::var(design$z_fixed, na.rm = TRUE), length(y0)))
  if (any(!is.finite(diag(y_cov))) || any(diag(y_cov) <= 0)) y_cov <- diag(1, length(y0))
  record_object("y_future_cov_initial", y_cov)
  row_moments <- record_step("row_moments_initial_path", {
    app_latent_row_moments(
      design, y0, y_cov, theta_mean, theta_cov,
      strategy = future_moment_strategy
    )
  })
  record_object("row_moments_initial_path", row_moments)
  constants <- app_latent_al_constants(as.numeric(row$quantile_level[[1L]]))
  sigma_state <- record_step("sigma_state_initialization", {
    app_latent_source_sigma_init(row_moments$source, vb_args$prior_sigma %||% list(a = 2, b = 1))
  })
  record_object("sigma_state_initialization", sigma_state)
  v_state <- record_step("latent_mixture_update_initialization", {
    app_latent_update_v(row_moments, sigma_state, constants)
  })
  record_object("latent_mixture_state", v_state)
  prior_state <- app_latent_prior_state_init(
    p = p,
    prior = app_map_qdesn_prior(row$coefficient_prior[[1L]]),
    intercept_index = design$intercept_index,
    vb_args = vb_args
  )
  if (app_as_bool(args$update_theta)) {
    theta_update <- record_step("theta_update_one_iteration", {
      app_latent_update_theta(row_moments, v_state$inv_mean, sigma_state, constants, prior_state, chunking = vb_args$chunking %||% NULL)
    })
    record_object("theta_update_one_iteration", theta_update)
  } else {
    theta_update <- NULL
  }
  if (app_as_bool(args$future_laplace)) {
    future_laplace_update <- record_step("future_path_laplace_one_iteration", {
      if (identical(future_update_strategy, "linearized_delta")) {
        app_latent_update_future_gaussian_delta(
          row_moments = row_moments,
          y_start = y0,
          theta_mean = if (is.null(theta_update)) theta_mean else theta_update$mean,
          theta_cov = if (is.null(theta_update)) theta_cov else theta_update$cov,
          e_inv_v = v_state$inv_mean,
          sigma_state = sigma_state,
          constants = constants
        )
      } else {
        app_latent_update_future_gaussian(
          y_start = y0,
          design = design,
          theta_mean = if (is.null(theta_update)) theta_mean else theta_update$mean,
          theta_cov = if (is.null(theta_update)) theta_cov else theta_update$cov,
          e_inv_v = v_state$inv_mean,
          sigma_state = sigma_state,
          constants = constants,
          objective_strategy = future_objective_strategy
        )
      }
    })
    record_object("future_path_laplace_one_iteration", future_laplace_update)
  }

  step_table <- app_bind_rows_fill(steps)
  summary <- data.frame(
    fit_id = row$fit_id[[1L]],
    model_id = row$model_id[[1L]],
    quantile_level = as.numeric(row$quantile_level[[1L]]),
    likelihood_family = row$likelihood_family[[1L]],
    coefficient_prior = row$coefficient_prior[[1L]],
    n_fixed_rows = nrow(design$H_fixed),
    n_future_dates = nrow(design$future_key),
    n_future_groups = n_future_groups,
    n_issued_glofas_rows = nrow(design$latent_data$g_ensemble),
    n_augmented_features = ncol(design$H_fixed),
    n_base_features = ncol(design$X_base),
    future_moment_strategy = future_moment_strategy,
    future_update_strategy = future_update_strategy,
    future_objective_strategy = future_objective_strategy,
    chunking_enabled = isTRUE((vb_args$chunking %||% list())$enabled),
    chunking_mode = as.character((vb_args$chunking %||% list())$mode %||% NA_character_),
    chunk_size = as.integer((vb_args$chunking %||% list())$chunk_size %||% NA_integer_),
    requested_horizon_max = design$latent_data$requested_horizon_max,
    horizon_max = design$latent_data$horizon_max,
    horizon_scope = design$latent_data$horizon_scope,
    available_horizons = paste(design$latent_data$available_horizons, collapse = ","),
    total_profile_seconds = sum(step_table$elapsed_seconds),
    theta_update_profiled = app_as_bool(args$update_theta),
    future_laplace_profiled = app_as_bool(args$future_laplace),
    design_hash = app_hash_latent_path_design(design),
    stringsAsFactors = FALSE
  )
  app_write_csv(summary, file.path(run_dirs$tables, "latent_path_profile_summary.csv"))
  app_write_csv(step_table, file.path(run_dirs$tables, "latent_path_profile_steps.csv"))
  app_write_csv(app_bind_rows_fill(object_rows), file.path(run_dirs$tables, "latent_path_profile_object_sizes.csv"))
  app_write_csv(app_bind_rows_fill(assessment_rows), file.path(run_dirs$tables, "latent_path_vb_structure_assessment.csv"))
  if (app_as_bool(args$save_design)) {
    saveRDS(design, file.path(run_dirs$objects, "latent_path_profile_design.rds"))
  }
  app_stage_done("03_profile_latent_path_al_vb", run_dirs, message = "Latent-path AL-VB profile completed without launching the full fit.")
  cat(file.path(run_dirs$tables, "latent_path_profile_summary.csv"), "\n")
}, error = function(e) {
  msg <- conditionMessage(e)
  app_stage_done("03_profile_latent_path_al_vb", run_dirs, status = "failed", message = msg)
  stop(msg, call. = FALSE)
})
