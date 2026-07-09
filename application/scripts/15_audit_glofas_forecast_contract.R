#!/usr/bin/env Rscript
# Purpose: no-refit audit of the GloFAS latent-path forecast contract. This
# script diagnoses whether forecast-window quantile collapse comes from input
# alignment, future-state construction, first-order prediction linearization,
# reservoir-state drift, or cross-quantile synthesis.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_qdesn_features.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/fit_qdesn_latent_path.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/make_manuscript_outputs.R"))

args <- app_parse_args(list(
  config = "local_trackers/runtime_configs/glofas_multiquantile_dec25_20260603/synthesis_config.yaml",
  source_manifest = "local_trackers/runtime_configs/glofas_multiquantile_dec25_20260603/synthesis_source_manifest.csv",
  synthesis_run_id = "glofas_multiquantile_dec25_20260603_synthesis_final",
  pre_cutoff_run_id = "glofas_multiquantile_dec25_20260603_pre_cutoff_history",
  prior_debug_run_id = "glofas_multiquantile_dec25_20260603_forecast_debug",
  run_id = "glofas_multiquantile_dec25_20260603_forecast_contract_audit",
  history_n = 1000,
  draw_subset = 3
))

cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id)
app_stage_start("15_audit_glofas_forecast_contract", run_dirs)
app_write_yaml(cfg, file.path(run_dirs$manifest, "run_config.yaml"))
app_write_json(cfg, file.path(run_dirs$manifest, "run_config.json"))
app_write_git_state(file.path(run_dirs$manifest, "git_state.txt"))
app_write_session_info(file.path(run_dirs$manifest, "session_info.txt"))

resolve_path <- function(path) {
  if (grepl("^/", path)) path else app_path(path)
}

safe_sd <- function(x) {
  s <- stats::sd(as.numeric(x), na.rm = TRUE)
  if (!is.finite(s) || s < 1.0e-10) 1 else s
}

safe_cor <- function(x, y) {
  x <- as.numeric(x)
  y <- as.numeric(y)
  if (length(x) != length(y) || length(x) < 2L) return(NA_real_)
  if (safe_sd(x) <= 1.0e-10 || safe_sd(y) <= 1.0e-10) return(NA_real_)
  stats::cor(x, y, use = "pairwise.complete.obs")
}

matrix_shift_summary <- function(X_hist, X_future, quantile_id, quantile_level, block, path_name) {
  X_hist <- as.matrix(X_hist)
  X_future <- as.matrix(X_future)
  storage.mode(X_hist) <- "double"
  storage.mode(X_future) <- "double"
  mu <- colMeans(X_hist, na.rm = TRUE)
  sig <- apply(X_hist, 2L, safe_sd)
  lo <- apply(X_hist, 2L, min, na.rm = TRUE)
  hi <- apply(X_hist, 2L, max, na.rm = TRUE)
  Z <- sweep(sweep(X_future, 2L, mu, "-"), 2L, sig, "/")
  outside <- sweep(X_future, 2L, lo, "<") | sweep(X_future, 2L, hi, ">")
  data.frame(
    quantile_id = quantile_id,
    quantile_level = quantile_level,
    block = block,
    path_name = path_name,
    horizon = seq_len(nrow(X_future)),
    max_abs_z = apply(abs(Z), 1L, max, na.rm = TRUE),
    mean_abs_z = rowMeans(abs(Z), na.rm = TRUE),
    n_abs_z_gt_3 = rowSums(abs(Z) > 3, na.rm = TRUE),
    n_abs_z_gt_5 = rowSums(abs(Z) > 5, na.rm = TRUE),
    frac_outside_history_range = rowMeans(outside, na.rm = TRUE),
    future_row_norm = sqrt(rowSums(X_future^2, na.rm = TRUE)),
    history_row_norm_median = stats::median(sqrt(rowSums(X_hist^2, na.rm = TRUE)), na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}

matrix_diff_summary <- function(A, B, quantile_id, quantile_level, block, comparison) {
  A <- as.matrix(A)
  B <- as.matrix(B)
  if (!all(dim(A) == dim(B))) {
    return(data.frame(
      quantile_id = quantile_id,
      quantile_level = quantile_level,
      block = block,
      comparison = comparison,
      horizon = NA_integer_,
      max_abs_diff = NA_real_,
      mean_abs_diff = NA_real_,
      row_l2_diff = NA_real_,
      compatible_dimensions = FALSE,
      stringsAsFactors = FALSE
    ))
  }
  D <- A - B
  data.frame(
    quantile_id = quantile_id,
    quantile_level = quantile_level,
    block = block,
    comparison = comparison,
    horizon = seq_len(nrow(D)),
    max_abs_diff = apply(abs(D), 1L, max, na.rm = TRUE),
    mean_abs_diff = rowMeans(abs(D), na.rm = TRUE),
    row_l2_diff = sqrt(rowSums(D^2, na.rm = TRUE)),
    compatible_dimensions = TRUE,
    stringsAsFactors = FALSE
  )
}

component_from_X <- function(X_beta, X_alpha, theta_mean, beta_index, alpha_index) {
  beta <- as.numeric(theta_mean[beta_index])
  alpha <- as.numeric(theta_mean[alpha_index])
  q_y <- as.numeric(as.matrix(X_beta) %*% beta)
  d_g <- as.numeric(as.matrix(X_alpha) %*% alpha)
  q_g <- q_y + d_g
  list(q_y = q_y, d_g = d_g, q_g = q_g)
}

linearized_draw_X <- function(lin, y_draw, block = c("beta", "alpha")) {
  block <- match.arg(block)
  X <- as.matrix(if (identical(block, "beta")) {
    lin$X_beta_future %||% lin$X_future
  } else {
    lin$X_alpha_future %||% lin$X_future
  })
  J <- if (identical(block, "beta")) {
    lin$J_beta %||% lin$J_x
  } else {
    lin$J_alpha %||% lin$J_x
  }
  delta <- as.numeric(y_draw) - as.numeric(lin$y_mean)
  for (h in seq_len(nrow(X))) {
    X[h, ] <- X[h, ] + as.numeric(as.matrix(J[[h]]) %*% delta)
  }
  X
}

crossing_summary <- function(values, quantile_levels, prefix) {
  o <- order(quantile_levels)
  values <- as.numeric(values[o])
  q <- as.numeric(quantile_levels[o])
  gaps <- diff(values)
  data.frame(
    component = prefix,
    pair = paste0("p", head(q, -1L), "_p", tail(q, -1L)),
    p_lower = head(q, -1L),
    p_upper = tail(q, -1L),
    gap = gaps,
    crossing = gaps < -1.0e-10,
    crossing_magnitude = pmax(-gaps, 0),
    stringsAsFactors = FALSE
  )
}

flatten_states <- function(states_future) {
  if (is.null(states_future) || !length(states_future)) return(NULL)
  rows <- lapply(states_future, function(x) as.numeric(unlist(x, use.names = FALSE)))
  p <- unique(vapply(rows, length, integer(1L)))
  if (length(p) != 1L) return(NULL)
  do.call(rbind, rows)
}

audit_future_design_no_jacobian <- function(design, y_future) {
  context <- design$future_context
  y_future <- as.numeric(y_future)
  if (length(y_future) != nrow(context$latent_data$future_key)) {
    stop("Latent future path length does not match future_key.", call. = FALSE)
  }
  two_block <- isTRUE(context$two_block_design %||% FALSE)
  qfit_beta <- context$qfit_beta %||% context$qfit
  qfit_alpha <- context$qfit_alpha %||% context$qfit
  feature_meta_beta <- context$feature_meta_beta %||% context$feature_meta
  feature_meta_alpha <- context$feature_meta_alpha %||% context$feature_meta

  cont_beta <- app_qdesn_continue_latent_path(
    qfit = qfit_beta,
    y_history = context$y_history_full,
    y_future = y_future,
    future_dates = context$latent_data$future_key$target_date,
    covariate_timeline = context$covariate_timeline,
    return_jacobian = FALSE
  )
  combined_beta_panel <- app_latent_path_combined_panel(
    base_panel = context$base_panel_full,
    latent_data = context$latent_data,
    y_future = y_future
  )
  assembled_beta <- app_build_readout_feature_matrix(
    reservoir_X = cont_beta$X_future_core,
    panel = combined_beta_panel,
    cfg = context$cfg,
    output_anchor_dates = context$latent_data$future_key$target_date,
    covariate_target_dates = context$latent_data$future_key$target_date,
    horizon = context$latent_data$future_key$horizon,
    feature_strategy = context$feature_strategy,
    horizon_scale = context$horizon_scale,
    feature_meta = feature_meta_beta,
    fit_scale = FALSE
  )

  if (isTRUE(two_block)) {
    qg_path <- as.numeric(context$glofas_future_quantile_path)
    if (length(qg_path) != length(y_future) || any(!is.finite(qg_path))) {
      stop("Two-block audit future builder requires a finite GloFAS quantile path.", call. = FALSE)
    }
    d_future <- qg_path - y_future
    cont_alpha <- app_qdesn_continue_latent_path(
      qfit = qfit_alpha,
      y_history = context$d_history_full,
      y_future = d_future,
      future_dates = context$latent_data$future_key$target_date,
      covariate_timeline = context$covariate_timeline,
      return_jacobian = FALSE
    )
    combined_alpha_panel <- app_latent_path_combined_panel(
      base_panel = context$base_panel_disc_full,
      latent_data = context$latent_data,
      y_future = d_future
    )
    assembled_alpha <- app_build_readout_feature_matrix(
      reservoir_X = cont_alpha$X_future_core,
      panel = combined_alpha_panel,
      cfg = context$cfg,
      output_anchor_dates = context$latent_data$future_key$target_date,
      covariate_target_dates = context$latent_data$future_key$target_date,
      horizon = context$latent_data$future_key$horizon,
      feature_strategy = context$feature_strategy,
      horizon_scale = context$horizon_scale,
      feature_meta = feature_meta_alpha,
      fit_scale = FALSE
    )
  } else {
    cont_alpha <- cont_beta
    assembled_alpha <- assembled_beta
    d_future <- NULL
  }

  list(
    X_future = assembled_beta$X,
    X_beta_future = assembled_beta$X,
    X_alpha_future = assembled_alpha$X,
    continuation_beta = cont_beta,
    continuation_alpha = cont_alpha,
    d_future = d_future,
    two_block_design = two_block
  )
}

contract_map <- data.frame(
  stage_order = seq_len(9),
  stage = c(
    "latent_path_data",
    "historical_design",
    "future_builder",
    "reference_desn_continuation",
    "discrepancy_desn_continuation",
    "vb_future_update",
    "posterior_draw_prediction",
    "multi_quantile_synthesis",
    "forecast_contract_audit"
  ),
  primary_function = c(
    "app_make_glofas_latent_path_data",
    "app_make_glofas_latent_path_design",
    "app_make_latent_path_future_builder",
    "app_qdesn_continue_latent_path",
    "app_qdesn_continue_latent_path",
    "app_latent_update_future_gaussian_delta / app_latent_update_future_gaussian",
    "app_predict_qdesn_latent_path_draws",
    "10_synthesize_glofas_quantile_runs.R",
    "15_audit_glofas_forecast_contract.R"
  ),
  input_contract = c(
    "application panel, cutoff, model row",
    "historical paired USGS/GloFAS rows and model config",
    "candidate latent future y path",
    "USGS history plus candidate latent future y path",
    "historical discrepancy plus q_g future path minus latent y path",
    "fixed historical likelihood rows plus future likelihood rows",
    "theta draws, latent-y draws, future design",
    "completed per-quantile prediction tables",
    "saved fit/design/draw/synthesis artifacts"
  ),
  required_invariant = c(
    "one future date per issued horizon; contiguous available horizons",
    "beta/reference and alpha/discrepancy rows are date-aligned",
    "returns H_y, H_g_key, X_beta_future, X_alpha_future, J_y, J_g_key",
    "future beta states use reference latent y path",
    "future alpha states use q_g path minus latent y path",
    "linearized_delta requires streamed grouped moments",
    "q_y_draw = q_g_draw - d_g_draw",
    "monotone synthesis only repairs, never validates, incoherent raw paths",
    "no refit; diagnose exact rebuilds, shifts, crossings, and feasibility"
  ),
  stringsAsFactors = FALSE
)
app_write_csv(contract_map, file.path(run_dirs$tables, "forecast_contract_map.csv"))

manifest <- app_read_csv(app_path(args$source_manifest))
if ("enabled" %in% names(manifest)) manifest <- manifest[app_as_bool_vec(manifest$enabled), , drop = FALSE]
app_check_required_columns(manifest, c("quantile_id", "quantile_level", "run_dir", "qdesn_fit_id"), "synthesis source manifest")
manifest$quantile_level <- as.numeric(manifest$quantile_level)
manifest <- manifest[order(manifest$quantile_level), , drop = FALSE]

history_n <- as.integer(args$history_n)
draw_subset_n <- as.integer(args$draw_subset)
if (!is.finite(history_n) || history_n <= 0L) history_n <- 1000L
if (!is.finite(draw_subset_n) || draw_subset_n < 0L) draw_subset_n <- 3L

pre_cutoff_table_exists <- function(cfg, run_id) {
  tables <- file.path(app_config_path(cfg, "runs"), run_id, "tables")
  any(file.exists(file.path(
    tables,
    c(
      "pre_cutoff_quantile_spread_by_date.csv",
      "pre_cutoff_quantile_spread_by_date_last1000.csv",
      "pre_cutoff_quantile_spread_by_date_last500.csv",
      "pre_cutoff_quantile_history.csv"
    )
  )))
}

contract_rows <- list()
input_rows <- list()
feature_shift_rows <- list()
linearized_diff_rows <- list()
prediction_rebuild_rows <- list()
state_shift_rows <- list()
historical_replay_rows <- list()
component_rows <- list()
draw_path_rows <- list()

for (i in seq_len(nrow(manifest))) {
  row <- manifest[i, , drop = FALSE]
  qid <- row$quantile_id[[1L]]
  qlev <- as.numeric(row$quantile_level[[1L]])
  message(sprintf("[forecast-contract-audit] quantile %s (%d/%d)", qid, i, nrow(manifest)))
  run_dir <- resolve_path(row$run_dir[[1L]])
  fit_id <- row$qdesn_fit_id[[1L]]
  fit_path <- file.path(run_dir, "objects", paste0(fit_id, ".rds"))
  design_path <- file.path(run_dir, "objects", paste0(fit_id, "__design.rds"))
  draw_path <- file.path(run_dir, "tables", "posterior_draw_predictions.csv")
  if (!file.exists(fit_path) || !file.exists(design_path) || !file.exists(draw_path)) {
    stop(sprintf("Missing source artifacts for %s.", qid), call. = FALSE)
  }

  fit <- readRDS(fit_path)
  design <- readRDS(design_path)
  draws <- app_read_csv(draw_path)
  lin <- fit$variational_state$future_linearization %||% NULL
  if (is.null(lin)) stop(sprintf("Missing future linearization for %s.", qid), call. = FALSE)
  theta_mean <- as.numeric(fit$variational_state$theta_mean %||% fit$summary$theta_mean)
  y_mean <- as.numeric(fit$variational_state$y_future_mean %||% fit$summary$y_future_mean)
  lin_mean <- as.numeric(lin$y_mean)

  beta_info <- design$feature_info_beta %||% design$feature_info
  alpha_info <- design$feature_info_alpha %||% design$feature_info
  beta_counts <- app_readout_feature_counts(beta_info)
  alpha_counts <- app_readout_feature_counts(alpha_info)
  contract_rows[[length(contract_rows) + 1L]] <- data.frame(
    quantile_id = qid,
    quantile_level = qlev,
    fit_id = fit_id,
    model_id = as.character(design$model_id %||% NA_character_),
    design_version = as.character(design$design_version %||% NA_character_),
    two_block_design = isTRUE(design$two_block_design %||% FALSE),
    future_discrepancy_convention = as.character(design$future_discrepancy_convention %||% NA_character_),
    prediction_state_strategy = paste(sort(unique(draws$prediction_state_strategy)), collapse = ";"),
    future_update_strategy = as.character(fit$vb_diagnostics$future_update_strategy %||% NA_character_),
    future_moment_strategy = as.character(fit$vb_diagnostics$future_moment_strategy %||% NA_character_),
    n_future = nrow(design$future_key),
    n_beta_features = ncol(design$X_beta),
    n_alpha_features = ncol(design$X_alpha),
    n_beta_reservoir_features = beta_counts$n_reservoir_features,
    n_alpha_reservoir_features = alpha_counts$n_reservoir_features,
    n_beta_output_lag_features = beta_counts$n_direct_output_lag_features,
    n_alpha_output_lag_features = alpha_counts$n_direct_output_lag_features,
    beta_seed = as.integer((design$future_context$model_row %||% data.frame())$reference_reservoir_seed[[1L]] %||% NA_integer_),
    alpha_seed = as.integer((design$future_context$model_row %||% data.frame())$discrepancy_reservoir_seed[[1L]] %||% NA_integer_),
    stringsAsFactors = FALSE
  )

  key <- design$future_key
  key$target_date <- as.Date(key$target_date)
  draw_key <- unique(draws[, c("target_date", "horizon"), drop = FALSE])
  draw_key$target_date <- as.Date(draw_key$target_date)
  draw_key$horizon <- as.integer(draw_key$horizon)
  draw_key <- draw_key[order(draw_key$target_date, draw_key$horizon), , drop = FALSE]
  input_rows[[length(input_rows) + 1L]] <- data.frame(
    quantile_id = qid,
    quantile_level = qlev,
    check = c(
      "future_key_matches_prediction_draws",
      "future_key_unique_target_dates",
      "future_horizons_contiguous",
      "beta_alpha_row_alignment",
      "beta_alpha_column_partition",
      "oracle_future_available",
      "glofas_future_quantile_path_finite"
    ),
    passed = c(
      identical(as.character(key$target_date), as.character(draw_key$target_date)) &&
        identical(as.integer(key$horizon), as.integer(draw_key$horizon)),
      !anyDuplicated(as.Date(key$target_date)),
      identical(as.integer(key$horizon), seq.int(min(as.integer(key$horizon)), max(as.integer(key$horizon)))),
      nrow(design$X_beta) == nrow(design$X_alpha) &&
        identical(as.Date(design$base_panel$target_date), as.Date((design$base_panel_disc_full %||% design$base_panel)$target_date[design$keep_idx] %||% design$base_panel$target_date)),
      identical(sort(c(as.integer(design$beta_index), as.integer(design$alpha_index))), seq_len(ncol(design$H_fixed))),
      all(is.finite(as.numeric(design$y_future_oracle))),
      all(is.finite(as.numeric(design$glofas_future_quantile_path)))
    ),
    detail = c(
      sprintf("future_key rows=%d, draw key rows=%d", nrow(key), nrow(draw_key)),
      sprintf("unique target dates=%d", length(unique(as.Date(key$target_date)))),
      sprintf("horizon range=%d:%d", min(as.integer(key$horizon)), max(as.integer(key$horizon))),
      sprintf("X_beta=%dx%d, X_alpha=%dx%d", nrow(design$X_beta), ncol(design$X_beta), nrow(design$X_alpha), ncol(design$X_alpha)),
      sprintf("H_fixed columns=%d, beta=%d, alpha=%d", ncol(design$H_fixed), length(design$beta_index), length(design$alpha_index)),
      sprintf("finite oracle count=%d/%d", sum(is.finite(as.numeric(design$y_future_oracle))), length(design$y_future_oracle)),
      sprintf("finite q_g path count=%d/%d", sum(is.finite(as.numeric(design$glofas_future_quantile_path))), length(design$glofas_future_quantile_path))
    ),
    stringsAsFactors = FALSE
  )

  hist_idx <- tail(seq_len(nrow(design$X_beta)), min(history_n, nrow(design$X_beta)))
  path_list <- list(
    initial_glofas_minus_median_discrepancy = as.numeric(design$y_future_init),
    vb_future_mean = y_mean,
    saved_linearization_mean = lin_mean
  )
  if (all(is.finite(as.numeric(design$y_future_oracle)))) {
    path_list$observed_future_oracle_diagnostic <- as.numeric(design$y_future_oracle)
  }

  for (path_name in names(path_list)) {
    y_path <- as.numeric(path_list[[path_name]])
    future <- audit_future_design_no_jacobian(design, y_path)
    Xb <- as.matrix(future$X_beta_future %||% future$X_future)
    Xa <- as.matrix(future$X_alpha_future %||% future$X_future)
    feature_shift_rows[[length(feature_shift_rows) + 1L]] <- matrix_shift_summary(
      design$X_beta[hist_idx, , drop = FALSE], Xb, qid, qlev, "beta_readout", path_name
    )
    feature_shift_rows[[length(feature_shift_rows) + 1L]] <- matrix_shift_summary(
      design$X_alpha[hist_idx, , drop = FALSE], Xa, qid, qlev, "alpha_readout", path_name
    )
    if (!is.null(design$X_core_beta) && !is.null(future$continuation_beta$X_future_core)) {
      state_shift_rows[[length(state_shift_rows) + 1L]] <- matrix_shift_summary(
        design$X_core_beta[hist_idx, , drop = FALSE],
        future$continuation_beta$X_future_core,
        qid, qlev, "beta_reservoir_core", path_name
      )
    }
    if (!is.null(design$X_core_alpha) && !is.null(future$continuation_alpha$X_future_core)) {
      state_shift_rows[[length(state_shift_rows) + 1L]] <- matrix_shift_summary(
        design$X_core_alpha[hist_idx, , drop = FALSE],
        future$continuation_alpha$X_future_core,
        qid, qlev, "alpha_reservoir_core", path_name
      )
    }

    if (path_name %in% c("vb_future_mean", "saved_linearization_mean")) {
      linearized_diff_rows[[length(linearized_diff_rows) + 1L]] <- matrix_diff_summary(
        Xb, lin$X_beta_future %||% lin$X_future, qid, qlev, "beta_readout",
        paste0(path_name, "_exact_builder_vs_saved_linearization")
      )
      linearized_diff_rows[[length(linearized_diff_rows) + 1L]] <- matrix_diff_summary(
        Xa, lin$X_alpha_future %||% lin$X_future, qid, qlev, "alpha_readout",
        paste0(path_name, "_exact_builder_vs_saved_linearization")
      )
    }

    comp <- component_from_X(Xb, Xa, theta_mean, design$beta_index, design$alpha_index)
    component_rows[[length(component_rows) + 1L]] <- data.frame(
      quantile_id = qid,
      quantile_level = qlev,
      path_name = path_name,
      horizon = as.integer(design$future_key$horizon),
      target_date = as.Date(design$future_key$target_date),
      q_y_theta_mean = comp$q_y,
      d_g_theta_mean = comp$d_g,
      q_g_theta_mean = comp$q_g,
      y_path = y_path,
      raw_glofas_quantile = as.numeric(design$glofas_future_quantile_path),
      y_future_oracle = as.numeric(design$y_future_oracle),
      stringsAsFactors = FALSE
    )
  }

  theta_draws <- as.matrix(fit$draws$theta)
  y_draws <- as.matrix(fit$draws$y_future)
  draw_ids <- if (draw_subset_n > 0L) {
    unique(round(seq(1, nrow(y_draws), length.out = min(draw_subset_n, nrow(y_draws)))))
  } else {
    integer()
  }
  if (length(draw_ids)) {
    for (s in draw_ids) {
      message(sprintf("[forecast-contract-audit] quantile %s exact draw rebuild %s", qid, s))
      Xb_lin <- linearized_draw_X(lin, y_draws[s, ], "beta")
      Xa_lin <- linearized_draw_X(lin, y_draws[s, ], "alpha")
      future_exact <- audit_future_design_no_jacobian(design, y_draws[s, ])
      Xb_exact <- as.matrix(future_exact$X_beta_future %||% future_exact$X_future)
      Xa_exact <- as.matrix(future_exact$X_alpha_future %||% future_exact$X_future)
      beta <- as.numeric(theta_draws[s, design$beta_index])
      alpha <- as.numeric(theta_draws[s, design$alpha_index])
      qy_lin <- as.numeric(Xb_lin %*% beta)
      dg_lin <- as.numeric(Xa_lin %*% alpha)
      qg_lin <- qy_lin + dg_lin
      qy_exact <- as.numeric(Xb_exact %*% beta)
      dg_exact <- as.numeric(Xa_exact %*% alpha)
      qg_exact <- qy_exact + dg_exact
      prediction_rebuild_rows[[length(prediction_rebuild_rows) + 1L]] <- data.frame(
        quantile_id = qid,
        quantile_level = qlev,
        draw_index = s,
        max_abs_q_y_diff = max(abs(qy_exact - qy_lin), na.rm = TRUE),
        max_abs_d_g_diff = max(abs(dg_exact - dg_lin), na.rm = TRUE),
        max_abs_q_g_diff = max(abs(qg_exact - qg_lin), na.rm = TRUE),
        mean_abs_q_y_diff = mean(abs(qy_exact - qy_lin), na.rm = TRUE),
        mean_abs_d_g_diff = mean(abs(dg_exact - dg_lin), na.rm = TRUE),
        mean_abs_q_g_diff = mean(abs(qg_exact - qg_lin), na.rm = TRUE),
        stringsAsFactors = FALSE
      )
      draw_path_rows[[length(draw_path_rows) + 1L]] <- data.frame(
        quantile_id = qid,
        quantile_level = qlev,
        draw_index = s,
        horizon = as.integer(design$future_key$horizon),
        target_date = as.Date(design$future_key$target_date),
        q_y_linearized = qy_lin,
        q_y_exact_rebuild = qy_exact,
        d_g_linearized = dg_lin,
        d_g_exact_rebuild = dg_exact,
        q_g_linearized = qg_lin,
        q_g_exact_rebuild = qg_exact,
        y_future_draw = as.numeric(y_draws[s, ]),
        stringsAsFactors = FALSE
      )
    }
  }

  historical_replay_rows[[length(historical_replay_rows) + 1L]] <- data.frame(
    quantile_id = qid,
    quantile_level = qlev,
    diagnostic = c(
      "pre_cutoff_fake_issued_replay",
      "observed_future_oracle_exact_rebuild",
      "pre_cutoff_fitted_path_reference"
    ),
    status = c(
      "limited_not_run",
      if (all(is.finite(as.numeric(design$y_future_oracle)))) "available_run" else "unavailable_missing_oracle_y",
      if (pre_cutoff_table_exists(cfg, args$pre_cutoff_run_id)) "available" else "missing"
    ),
    detail = c(
      "Saved source artifacts do not contain earlier issued ensemble origins needed for a genuine fake-forecast replay; avoiding synthetic proof.",
      "Exact future_builder was evaluated at observed future y where available.",
      sprintf("Reference run id: %s", args$pre_cutoff_run_id)
    ),
    stringsAsFactors = FALSE
  )

  rm(fit, design, draws)
  gc()
}

contract_status <- app_bind_rows_fill(contract_rows)
input_alignment <- app_bind_rows_fill(input_rows)
feature_shift <- app_bind_rows_fill(feature_shift_rows)
linearized_diff <- app_bind_rows_fill(linearized_diff_rows)
prediction_rebuild <- app_bind_rows_fill(prediction_rebuild_rows)
state_shift <- app_bind_rows_fill(state_shift_rows)
historical_replay <- app_bind_rows_fill(historical_replay_rows)
component_paths <- app_bind_rows_fill(component_rows)
draw_path_compare <- app_bind_rows_fill(draw_path_rows)
if (!nrow(prediction_rebuild)) {
  prediction_rebuild <- data.frame(
    quantile_id = character(),
    quantile_level = numeric(),
    draw_index = integer(),
    max_abs_q_y_diff = numeric(),
    max_abs_d_g_diff = numeric(),
    max_abs_q_g_diff = numeric(),
    mean_abs_q_y_diff = numeric(),
    mean_abs_d_g_diff = numeric(),
    mean_abs_q_g_diff = numeric()
  )
}
if (!nrow(draw_path_compare)) {
  draw_path_compare <- data.frame(
    quantile_id = character(),
    quantile_level = numeric(),
    draw_index = integer(),
    horizon = integer(),
    target_date = as.Date(character()),
    q_y_linearized = numeric(),
    q_y_exact_rebuild = numeric(),
    d_g_linearized = numeric(),
    d_g_exact_rebuild = numeric(),
    q_g_linearized = numeric(),
    q_g_exact_rebuild = numeric(),
    y_future_draw = numeric()
  )
}

app_write_csv(contract_status, file.path(run_dirs$tables, "forecast_contract_status_by_quantile.csv"))
app_write_csv(input_alignment, file.path(run_dirs$tables, "input_scaling_alignment.csv"))
app_write_csv(feature_shift, file.path(run_dirs$tables, "future_design_shift_by_path.csv"))
app_write_csv(linearized_diff, file.path(run_dirs$tables, "linearized_vs_exact_future_design.csv"))
app_write_csv(prediction_rebuild, file.path(run_dirs$tables, "linearized_vs_exact_draw_subset_summary.csv"))
app_write_csv(draw_path_compare, file.path(run_dirs$tables, "linearized_vs_exact_draw_subset_by_horizon.csv"))
app_write_csv(state_shift, file.path(run_dirs$tables, "reservoir_state_shift_by_block.csv"))
app_write_csv(historical_replay, file.path(run_dirs$tables, "historical_replay_feature_match.csv"))
app_write_csv(component_paths, file.path(run_dirs$tables, "future_component_paths_by_contract.csv"))

component_cross_rows <- list()
for (path_name in sort(unique(component_paths$path_name))) {
  for (h in sort(unique(component_paths$horizon))) {
    block <- component_paths[component_paths$path_name == path_name & component_paths$horizon == h, , drop = FALSE]
    if (nrow(block) < 2L) next
    for (component in c("q_y_theta_mean", "d_g_theta_mean", "q_g_theta_mean")) {
      cs <- crossing_summary(block[[component]], block$quantile_level, component)
      cs$path_name <- path_name
      cs$horizon <- h
      cs$target_date <- block$target_date[[1L]]
      component_cross_rows[[length(component_cross_rows) + 1L]] <- cs
    }
  }
}
component_cross <- app_bind_rows_fill(component_cross_rows)
app_write_csv(component_cross, file.path(run_dirs$tables, "component_crossing_decomposition.csv"))

prior_debug_summary_path <- file.path(app_config_path(cfg, "runs"), args$prior_debug_run_id, "tables", "forecast_debug_summary.csv")
prior_debug <- if (file.exists(prior_debug_summary_path)) app_read_csv(prior_debug_summary_path) else data.frame(metric = character(), value = numeric())

max_feature_shift <- max(feature_shift$max_abs_z, na.rm = TRUE)
max_state_shift <- if (nrow(state_shift)) max(state_shift$max_abs_z, na.rm = TRUE) else NA_real_
max_rebuild_diff <- if (nrow(prediction_rebuild)) {
  max(prediction_rebuild$max_abs_q_y_diff, prediction_rebuild$max_abs_d_g_diff, prediction_rebuild$max_abs_q_g_diff, na.rm = TRUE)
} else {
  NA_real_
}
max_saved_builder_diff <- max(linearized_diff$max_abs_diff, na.rm = TRUE)
total_component_crossings <- sum(component_cross$crossing, na.rm = TRUE)
all_input_checks_pass <- all(input_alignment$passed)
oracle_available_all <- all(historical_replay$status[historical_replay$diagnostic == "observed_future_oracle_exact_rebuild"] == "available_run")

candidate_fix <- data.frame(
  candidate = c(
    "fix_input_alignment_before_refit",
    "replace_draw_prediction_linearization_with_exact_rebuild",
    "revise_recursive_latent_path_model",
    "cross_quantile_coupled_future_path",
    "teacher_forced_oracle_mode"
  ),
  readiness = c(
    if (all_input_checks_pass) "not_indicated_by_current_audit" else "required_before_any_refit",
    if (is.finite(max_rebuild_diff) && max_rebuild_diff > 0.05) "candidate_needs_smoke" else "not_primary_from_draw_subset",
    if (is.finite(max_state_shift) && max_state_shift > 5) "candidate_needs_model_review" else "not_primary_from_state_shift",
    if (total_component_crossings > 0) "candidate_needs_design_review" else "not_indicated_by_crossings",
    if (oracle_available_all) "diagnostic_only_available" else "diagnostic_limited"
  ),
  rationale = c(
    sprintf("All input/date/block checks pass=%s.", all_input_checks_pass),
    sprintf("Max exact-vs-linearized draw-subset component difference=%0.4g.", max_rebuild_diff),
    sprintf("Max reservoir-state/readout shift versus fitted history=%0.4g.", max_state_shift),
    sprintf("Component-level theta-mean crossings across paths=%d.", total_component_crossings),
    "Oracle path is diagnostic only because it uses observed future reference values."
  ),
  promote_to_production = FALSE,
  stringsAsFactors = FALSE
)
app_write_csv(candidate_fix, file.path(run_dirs$tables, "candidate_fix_readiness.csv"))

audit_summary <- data.frame(
  metric = c(
    "all_input_alignment_checks_pass",
    "oracle_exact_rebuild_available_all_quantiles",
    "max_future_design_shift_z",
    "max_reservoir_state_shift_z",
    "max_saved_linearization_vs_exact_builder_design_diff",
    "max_exact_vs_linearized_draw_subset_prediction_diff",
    "component_theta_mean_crossing_count",
    "prior_debug_max_identity_error",
    "prior_debug_forecast_zero_width_30_horizons"
  ),
  value = c(
    as.character(all_input_checks_pass),
    as.character(oracle_available_all),
    sprintf("%0.12g", max_feature_shift),
    sprintf("%0.12g", max_state_shift),
    sprintf("%0.12g", max_saved_builder_diff),
    sprintf("%0.12g", max_rebuild_diff),
    as.character(total_component_crossings),
    as.character(prior_debug$value[match("max_identity_error", prior_debug$metric)] %||% NA_character_),
    as.character(prior_debug$value[match("forecast_zero_width_30_horizons", prior_debug$metric)] %||% NA_character_)
  ),
  stringsAsFactors = FALSE
)
app_write_csv(audit_summary, file.path(run_dirs$tables, "audit_summary.csv"))

out_dir <- file.path(app_config_path(cfg, "generated_outputs"), basename(run_dirs$run_dir))
fig_dir <- file.path(out_dir, "figures")
app_ensure_dir(fig_dir)
plot_pdf <- function(name, width = 8.5, height = 5.2, expr) {
  path <- file.path(fig_dir, name)
  grDevices::pdf(path, width = width, height = height)
  on.exit(grDevices::dev.off(), add = TRUE)
  force(expr)
  path
}

q_levels <- sort(unique(manifest$quantile_level))
q_cols <- grDevices::hcl.colors(length(q_levels), "Dark 3")
names(q_cols) <- as.character(q_levels)
figures <- c()

figures <- c(figures, design_shift = plot_pdf("glofas_contract_audit_future_design_shift.pdf", 9, 5.5, {
  plot_data <- feature_shift[feature_shift$path_name %in% c("vb_future_mean", "observed_future_oracle_diagnostic"), , drop = FALSE]
  ylim <- range(plot_data$max_abs_z, na.rm = TRUE)
  plot(range(plot_data$horizon), ylim, type = "n", xlab = "Forecast horizon", ylab = "Maximum absolute z-score", main = "Future readout-design shift by path")
  grid(col = "gray90")
  for (q in q_levels) {
    for (path_name in sort(unique(plot_data$path_name))) {
      block <- plot_data[abs(plot_data$quantile_level - q) < 1.0e-12 & plot_data$path_name == path_name & plot_data$block == "beta_readout", , drop = FALSE]
      if (nrow(block)) lines(block$horizon, block$max_abs_z, col = q_cols[[as.character(q)]], lwd = 1.4, lty = if (grepl("oracle", path_name)) 2 else 1)
    }
  }
  abline(h = c(3, 5), col = "gray40", lty = 3)
  legend("topleft", legend = c(paste0("p=", q_levels), "solid=VB mean, dashed=oracle"), col = c(q_cols, "#111111"), lty = c(rep(1, length(q_levels)), 1), lwd = 1.4, bty = "n", cex = 0.72, ncol = 2)
}))

figures <- c(figures, exact_vs_linearized = plot_pdf("glofas_contract_audit_exact_vs_linearized_draws.pdf", 8.8, 5.2, {
  if (nrow(prediction_rebuild)) {
    ylim <- range(c(prediction_rebuild$max_abs_q_y_diff, prediction_rebuild$max_abs_d_g_diff, prediction_rebuild$max_abs_q_g_diff), na.rm = TRUE)
    x <- seq_len(nrow(prediction_rebuild))
    plot(x, prediction_rebuild$max_abs_q_y_diff, type = "h", ylim = ylim, xlab = "Audited draw row", ylab = "Maximum absolute prediction difference", main = "Exact rebuild versus first-order prediction")
    grid(col = "gray90")
    points(x, prediction_rebuild$max_abs_d_g_diff, pch = 16, col = "#b91c1c", cex = 0.6)
    points(x, prediction_rebuild$max_abs_q_g_diff, pch = 16, col = "#2563eb", cex = 0.6)
    legend("topright", legend = c("q_y", "d_g", "q_g"), col = c("#111111", "#b91c1c", "#2563eb"), pch = c(NA, 16, 16), lty = c(1, NA, NA), bty = "n", cex = 0.78)
  } else {
    plot.new()
    text(0.5, 0.5, "Exact draw subset skipped")
  }
}))

figures <- c(figures, state_shift = plot_pdf("glofas_contract_audit_reservoir_state_shift.pdf", 8.8, 5.2, {
  plot_data <- state_shift[state_shift$path_name %in% c("vb_future_mean", "observed_future_oracle_diagnostic"), , drop = FALSE]
  ylim <- range(plot_data$max_abs_z, na.rm = TRUE)
  plot(range(plot_data$horizon), ylim, type = "n", xlab = "Forecast horizon", ylab = "Maximum absolute state z-score", main = "Reservoir-state shift by block")
  grid(col = "gray90")
  for (block_name in sort(unique(plot_data$block))) {
    block <- plot_data[plot_data$block == block_name & plot_data$path_name == "vb_future_mean", , drop = FALSE]
    med <- stats::aggregate(block$max_abs_z, list(horizon = block$horizon), median, na.rm = TRUE)
    lines(med$horizon, med$x, lwd = 1.8, col = if (grepl("beta", block_name)) "#2563eb" else "#b91c1c")
  }
  abline(h = c(3, 5), col = "gray40", lty = 3)
  legend("topleft", legend = c("beta/reference", "alpha/discrepancy"), col = c("#2563eb", "#b91c1c"), lwd = 1.8, bty = "n")
}))

figures <- c(figures, component_crossing = plot_pdf("glofas_contract_audit_component_crossings.pdf", 9, 5.6, {
  plot_data <- component_cross[component_cross$path_name == "vb_future_mean", , drop = FALSE]
  components <- sort(unique(plot_data$component))
  horizons <- sort(unique(plot_data$horizon))
  ylim <- c(0, max(plot_data$crossing_magnitude, na.rm = TRUE))
  plot(range(horizons), ylim, type = "n", xlab = "Forecast horizon", ylab = "Crossing magnitude", main = "Component-level crossings at VB future mean")
  grid(col = "gray90")
  cols <- c(q_y_theta_mean = "#2563eb", d_g_theta_mean = "#b91c1c", q_g_theta_mean = "#059669")
  for (component in components) {
    block <- plot_data[plot_data$component == component, , drop = FALSE]
    agg <- stats::aggregate(block$crossing_magnitude, list(horizon = block$horizon), sum, na.rm = TRUE)
    lines(agg$horizon, agg$x, col = cols[[component]] %||% "#111111", lwd = 1.8)
  }
  legend("topright", legend = components, col = cols[components], lwd = 1.8, bty = "n", cex = 0.76)
}))

figures <- c(figures, component_paths = plot_pdf("glofas_contract_audit_component_paths_vb_mean.pdf", 9, 7.2, {
  par(mfrow = c(3, 1), mar = c(3.2, 4.3, 2, 1))
  plot_data <- component_paths[component_paths$path_name == "vb_future_mean", , drop = FALSE]
  for (component in c("q_y_theta_mean", "d_g_theta_mean", "q_g_theta_mean")) {
    ylim <- range(plot_data[[component]], na.rm = TRUE)
    plot(range(plot_data$horizon), ylim, type = "n", xlab = "Forecast horizon", ylab = component, main = component)
    grid(col = "gray90")
    for (q in q_levels) {
      block <- plot_data[abs(plot_data$quantile_level - q) < 1.0e-12, , drop = FALSE]
      lines(block$horizon, block[[component]], col = q_cols[[as.character(q)]], lwd = 1.4)
    }
  }
}))

prov <- app_write_output_provenance(
  outputs = figures,
  run_dirs = run_dirs,
  cfg = cfg,
  path = file.path(run_dirs$tables, "forecast_contract_audit_figure_provenance.csv")
)
app_write_csv(prov, file.path(out_dir, "forecast_contract_audit_figure_provenance.csv"))

writeLines(
  c(
    sprintf("run_id: %s", basename(run_dirs$run_dir)),
    sprintf("synthesis_run_id: %s", args$synthesis_run_id),
    sprintf("pre_cutoff_run_id: %s", args$pre_cutoff_run_id),
    sprintf("history_n: %d", history_n),
    sprintf("draw_subset: %d", draw_subset_n),
    "exact_rebuild_mode: no_jacobian_feature_rebuild",
    sprintf("all_input_alignment_checks_pass: %s", all_input_checks_pass),
    sprintf("max_future_design_shift_z: %0.6g", max_feature_shift),
    sprintf("max_reservoir_state_shift_z: %0.6g", max_state_shift),
    sprintf("max_exact_vs_linearized_draw_subset_prediction_diff: %0.6g", max_rebuild_diff),
    sprintf("component_theta_mean_crossing_count: %d", total_component_crossings),
    sprintf("generated_outputs: %s", out_dir)
  ),
  file.path(run_dirs$tables, "forecast_contract_audit_summary.txt")
)

app_stage_done("15_audit_glofas_forecast_contract", run_dirs)
cat(run_dirs$run_dir, "\n")
