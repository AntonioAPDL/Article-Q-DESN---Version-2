# Article-side adapter skeleton for the latent-path ensemble-likelihood model.

app_make_glofas_latent_path_data <- function(panel, cfg, cutoff_row, model_row = NULL) {
  app_validate_application_model_contract(cfg, model_row)
  if (!app_is_latent_path_contract(cfg, model_row)) {
    stop("app_make_glofas_latent_path_data() requires latent_path_ensemble_likelihood.", call. = FALSE)
  }
  app_check_required_columns(panel, app_discrepancy_required_panel_columns(), "application panel")

  origin <- as.Date(cutoff_row$origin_date[[1L]])
  train_start <- as.Date(cutoff_row$train_start[[1L]])
  train_end <- as.Date(cutoff_row$train_end[[1L]])
  eval_start <- as.Date(cutoff_row$eval_start[[1L]])
  eval_end <- as.Date(cutoff_row$eval_end[[1L]])
  h_min <- as.integer(cutoff_row$horizon_min[[1L]] %||% cfg$forecast_protocol$default_horizon_min %||% 1L)
  h_max_requested <- as.integer(cutoff_row$horizon_max[[1L]] %||% cfg$forecast_protocol$default_horizon_max %||% 30L)

  panel$origin_date <- as.Date(panel$origin_date)
  panel$target_date <- as.Date(panel$target_date)
  panel$horizon <- as.integer(panel$horizon)

  hist_mask <- panel$is_retrospective &
    panel$target_date >= train_start &
    panel$target_date <= train_end
  hist_panel <- panel[hist_mask, , drop = FALSE]
  hist_panel <- hist_panel[order(hist_panel$target_date, hist_panel$origin_date), , drop = FALSE]
  if (!nrow(hist_panel)) stop("Latent-path model has no retrospective historical rows.", call. = FALSE)

  y_hist <- hist_panel[is.finite(hist_panel$y_transformed), , drop = FALSE]
  g_retro <- hist_panel[is.finite(hist_panel$g_transformed), , drop = FALSE]
  if (!nrow(y_hist)) stop("Latent-path model has no historical USGS rows.", call. = FALSE)
  if (!nrow(g_retro)) stop("Latent-path model has no retrospective GloFAS rows.", call. = FALSE)

  ens_mask <- panel$is_ensemble &
    panel$origin_date == origin &
    panel$target_date >= eval_start &
    panel$target_date <= eval_end &
    panel$horizon >= h_min &
    panel$horizon <= h_max_requested &
    is.finite(panel$g_transformed)
  g_ens <- panel[ens_mask, , drop = FALSE]
  g_ens <- g_ens[order(g_ens$target_date, g_ens$horizon, g_ens$member), , drop = FALSE]
  if (!nrow(g_ens)) stop("Latent-path model has no issued GloFAS ensemble rows.", call. = FALSE)
  member_limit <- suppressWarnings(as.integer(
    (cfg$application_model %||% list())$max_ensemble_members_per_horizon %||%
      (cfg$latent_path %||% list())$max_ensemble_members_per_horizon %||%
      NA_integer_
  ))
  if (is.finite(member_limit) && member_limit > 0L) {
    split_key <- paste(g_ens$target_date, g_ens$horizon)
    keep <- unlist(lapply(split(seq_len(nrow(g_ens)), split_key), utils::head, n = member_limit), use.names = FALSE)
    g_ens <- g_ens[sort(keep), , drop = FALSE]
  }

  available_horizons <- sort(unique(as.integer(g_ens$horizon)))
  if (any(!is.finite(available_horizons))) {
    stop("Latent-path issued ensemble rows contain invalid horizons.", call. = FALSE)
  }
  if (!identical(available_horizons, seq.int(min(available_horizons), max(available_horizons)))) {
    missing_h <- setdiff(seq.int(min(available_horizons), max(available_horizons)), available_horizons)
    stop(
      sprintf(
        "Latent-path issued ensemble horizons must be contiguous; missing horizon(s): %s.",
        paste(missing_h, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  if (min(available_horizons) > h_min) {
    stop(
      sprintf(
        "Latent-path issued ensemble rows start at horizon %d, but requested horizon_min is %d.",
        min(available_horizons),
        h_min
      ),
      call. = FALSE
    )
  }
  h_max <- max(available_horizons)

  future_key <- unique(g_ens[, c("target_date", "horizon"), drop = FALSE])
  future_key <- future_key[order(future_key$target_date, future_key$horizon), , drop = FALSE]
  if (any(duplicated(future_key$target_date))) {
    stop("Latent-path model requires one forecast horizon per target date.", call. = FALSE)
  }

  y_future_oracle <- vapply(future_key$target_date, function(d) {
    vals <- panel$y_transformed[panel$target_date == d & is.finite(panel$y_transformed)]
    if (length(vals)) vals[[1L]] else NA_real_
  }, numeric(1L))

  source_scope <- app_application_model_contract_row(cfg, model_row)
  out <- list(
    cutoff_id = as.character(cutoff_row$cutoff_id[[1L]] %||% NA_character_),
    origin_date = origin,
    train_start = train_start,
    train_end = train_end,
    horizon_min = h_min,
    horizon_max = h_max,
    requested_horizon_min = h_min,
    requested_horizon_max = h_max_requested,
    available_horizons = available_horizons,
    horizon_scope = if (h_max < h_max_requested) "available_issued_ensemble_horizon" else "requested_horizon",
    historical_panel = hist_panel,
    y_history = y_hist,
    g_retro = g_retro,
    g_ensemble = g_ens,
    future_key = future_key,
    y_future_oracle = y_future_oracle,
    source_parameter_scope = source_scope,
    application_model_contract = app_application_model_contract(cfg, model_row)
  )
  class(out) <- "glofas_latent_path_data"
  app_validate_glofas_latent_path_data(out)
  out
}

app_validate_glofas_latent_path_data <- function(x) {
  required <- c("historical_panel", "y_history", "g_retro", "g_ensemble", "future_key", "source_parameter_scope")
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(sprintf("Latent-path data object is missing: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  if (!nrow(x$y_history) || !nrow(x$g_retro) || !nrow(x$g_ensemble) || !nrow(x$future_key)) {
    stop("Latent-path data object has empty required row blocks.", call. = FALSE)
  }
  if (anyDuplicated(as.Date(x$y_history$target_date))) {
    stop("Latent-path historical USGS rows must have one row per target date.", call. = FALSE)
  }
  if (anyDuplicated(as.Date(x$g_retro$target_date))) {
    stop("Latent-path retrospective GloFAS rows must have one row per target date.", call. = FALSE)
  }
  if (!all(as.Date(x$g_ensemble$target_date) %in% as.Date(x$future_key$target_date))) {
    stop("Latent-path issued ensemble rows contain target dates outside future_key.", call. = FALSE)
  }
  if (!identical(as.character(x$application_model_contract), "latent_path_ensemble_likelihood")) {
    stop("Latent-path data object has the wrong application model contract.", call. = FALSE)
  }
  if (!identical(as.character(x$source_parameter_scope$issued_glofas_role[[1L]]), "likelihood_rows")) {
    stop("Latent-path data object must treat issued GloFAS rows as likelihood rows.", call. = FALSE)
  }
  invisible(TRUE)
}

app_latent_path_data_summary <- function(x, model_row = NULL) {
  app_validate_glofas_latent_path_data(x)
  row_value <- function(nm, default = NA_character_) {
    if (!is.null(model_row) && nm %in% names(model_row)) {
      val <- model_row[[nm]][[1L]]
      if (!is.null(val) && length(val) && !is.na(val)) return(as.character(val))
    }
    default
  }
  data.frame(
    fit_id = row_value("fit_id"),
    model_id = row_value("model_id"),
    application_model_contract = as.character(x$application_model_contract),
    origin_date = as.character(x$origin_date),
    train_start = as.character(x$train_start),
    train_end = as.character(x$train_end),
    horizon_min = as.integer(x$horizon_min),
    horizon_max = as.integer(x$horizon_max),
    requested_horizon_min = as.integer(x$requested_horizon_min %||% x$horizon_min),
    requested_horizon_max = as.integer(x$requested_horizon_max %||% x$horizon_max),
    horizon_scope = as.character(x$horizon_scope %||% "requested_horizon"),
    n_y_history = nrow(x$y_history),
    n_glofas_retrospective = nrow(x$g_retro),
    n_glofas_ensemble = nrow(x$g_ensemble),
    n_future_dates = nrow(x$future_key),
    glofas_scale_scope = as.character(x$source_parameter_scope$glofas_scale_scope[[1L]]),
    glofas_asymmetry_scope = as.character(x$source_parameter_scope$glofas_asymmetry_scope[[1L]] %||% NA_character_),
    stringsAsFactors = FALSE
  )
}

app_latent_path_default_cutoff_row <- function(cfg) {
  cutoffs <- app_validate_cutoffs(app_config_path(cfg, "cutoffs"))
  if (!nrow(cutoffs)) stop("No enabled cutoff rows are available for latent-path fitting.", call. = FALSE)
  if (nrow(cutoffs) > 1L) {
    stop(
      "Latent-path fitting currently requires a single enabled cutoff in the active configuration.",
      call. = FALSE
    )
  }
  cutoffs[1L, , drop = FALSE]
}

app_latent_path_initial_future <- function(latent_data, p0) {
  qg <- app_latent_path_glofas_quantile_path(latent_data, p0)
  d_hist <- as.numeric(latent_data$g_retro$g_transformed) - as.numeric(latent_data$y_history$y_transformed)
  d0 <- stats::median(d_hist[is.finite(d_hist)], na.rm = TRUE)
  if (!is.finite(d0)) d0 <- 0
  init <- qg - d0
  fallback <- utils::tail(as.numeric(latent_data$y_history$y_transformed), 1L)
  init[!is.finite(init)] <- fallback
  init
}

app_latent_path_glofas_quantile_path <- function(latent_data, p0) {
  qg <- vapply(seq_len(nrow(latent_data$future_key)), function(i) {
    idx <- latent_data$g_ensemble$target_date == latent_data$future_key$target_date[[i]] &
      latent_data$g_ensemble$horizon == latent_data$future_key$horizon[[i]]
    app_ensemble_quantile(latent_data$g_ensemble[idx, , drop = FALSE], p0)
  }, numeric(1L))
  if (any(!is.finite(qg))) {
    stop("Unable to compute finite GloFAS future quantile path for latent-path design.", call. = FALSE)
  }
  qg
}

app_latent_path_discrepancy_panel <- function(panel) {
  out <- panel
  d <- as.numeric(out$g_transformed) - as.numeric(out$y_transformed)
  if (any(!is.finite(d))) {
    stop("Discrepancy reservoir panel requires finite retrospective GloFAS and reference values.", call. = FALSE)
  }
  out$y_transformed <- d
  app_copy_covariate_attrs(out, panel)
}

app_latent_path_combined_panel <- function(base_panel, latent_data, y_future) {
  future <- data.frame(
    origin_date = latent_data$origin_date,
    target_date = as.Date(latent_data$future_key$target_date),
    horizon = as.integer(latent_data$future_key$horizon),
    member = NA_character_,
    is_retrospective = FALSE,
    is_ensemble = FALSE,
    y_transformed = as.numeric(y_future),
    g_transformed = NA_real_,
    split = "latent_future",
    cutoff_id = latent_data$cutoff_id,
    stringsAsFactors = FALSE
  )
  missing <- setdiff(names(base_panel), names(future))
  for (nm in missing) future[[nm]] <- NA
  future <- future[, names(base_panel), drop = FALSE]
  out <- rbind(base_panel, future)
  app_copy_covariate_attrs(out, base_panel)
}

app_latent_path_feature_block <- function(
  panel,
  cfg,
  model_row,
  drop,
  seed,
  feature_strategy,
  horizon_scale
) {
  if (isTRUE(app_qdesn_reservoir_uses_covariates(cfg))) {
    qfit <- app_qdesn_build_article_design_full(
      panel = panel,
      cfg = cfg,
      seed = seed,
      drop = drop
    )
    keep_idx <- as.integer(qfit$meta$keep_idx)
    kept_panel <- panel[keep_idx, , drop = FALSE]
    kept_panel <- app_copy_covariate_attrs(kept_panel, panel)
    assembled <- app_build_readout_feature_matrix(
      reservoir_X = qfit$X,
      panel = panel,
      cfg = cfg,
      output_anchor_dates = kept_panel$target_date,
      covariate_target_dates = kept_panel$target_date,
      horizon = kept_panel$horizon,
      feature_strategy = feature_strategy,
      horizon_scale = horizon_scale,
      fit_scale = TRUE
    )
    qfit$meta$feature_contract <- assembled$contract
    qfit$meta$feature_info <- assembled$feature_info
    qfit$meta$readout_scale_info <- assembled$readout_scale_info
    feature <- list(
      X = assembled$X,
      X_core = qfit$X,
      X_covariates = NULL,
      panel = kept_panel,
      keep_idx = keep_idx,
      feature_info = assembled$feature_info,
      readout_scale_info = assembled$readout_scale_info,
      meta = qfit$meta
    )
  } else {
    feature <- app_feature_matrix_from_panel(
      panel = panel,
      cfg = cfg,
      model_row = model_row,
      drop = drop,
      feature_strategy = feature_strategy,
      horizon_scale = horizon_scale,
      seed_override = seed
    )
    qfit <- app_build_qdesn_design_full(
      y = panel$y_transformed,
      cfg = cfg,
      seed = seed,
      drop = drop
    )
  }
  list(feature = feature, qfit = qfit)
}

app_latent_path_output_lag_jacobian <- function(feature_info, future_key, feature_meta, cfg) {
  contract <- app_feature_contract(cfg)
  H <- nrow(future_key)
  p <- nrow(feature_info)
  J <- vector("list", H)
  future_dates <- as.Date(future_key$target_date)
  output_scale <- (feature_meta$readout_scale_info %||% list())$output_lags %||% NULL
  for (h in seq_len(H)) {
    Jh <- matrix(0, nrow = p, ncol = H)
    lag_rows <- which(feature_info$block == "direct_output_lag")
    if (length(lag_rows)) {
      for (r in lag_rows) {
        L <- as.integer(feature_info$lag[[r]])
        lookup <- future_dates[[h]] - L
        k <- match(lookup, future_dates)
        if (!is.na(k) && k < h) {
          col <- as.character(feature_info$column_name[[r]])
          scale <- 1
          if (isTRUE(contract$readout$standardize_output_lags) && !is.null(output_scale)) {
            scale <- as.numeric(output_scale$scale[[col]])
            if (!is.finite(scale) || scale <= 0) scale <- 1
          }
          Jh[r, k] <- 1 / scale
        }
      }
    }
    J[[h]] <- Jh
  }
  J
}

app_make_latent_path_future_builder <- function(context) {
  force(context)
  function(y_future) {
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
      return_jacobian = TRUE
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
    feature_info_beta <- assembled_beta$feature_info
    J_direct_beta <- app_latent_path_output_lag_jacobian(
      feature_info = feature_info_beta,
      future_key = context$latent_data$future_key,
      feature_meta = feature_meta_beta,
      cfg = context$cfg
    )
    res_rows_beta <- which(feature_info_beta$block == "reservoir_state")
    J_beta <- vector("list", length(J_direct_beta))
    for (h in seq_along(J_direct_beta)) {
      Jh <- J_direct_beta[[h]]
      if (length(res_rows_beta)) {
        if (length(res_rows_beta) != nrow(cont_beta$J_future_core[[h]])) {
          stop("Reference reservoir sensitivity dimension does not match readout feature rows.", call. = FALSE)
        }
        Jh[res_rows_beta, ] <- cont_beta$J_future_core[[h]]
      }
      J_beta[[h]] <- Jh
    }

    if (isTRUE(two_block)) {
      qg_path <- as.numeric(context$glofas_future_quantile_path)
      if (length(qg_path) != length(y_future) || any(!is.finite(qg_path))) {
        stop("Two-block latent-path future builder requires a finite GloFAS quantile path.", call. = FALSE)
      }
      d_future <- qg_path - y_future
      cont_alpha <- app_qdesn_continue_latent_path(
        qfit = qfit_alpha,
        y_history = context$d_history_full,
        y_future = d_future,
        future_dates = context$latent_data$future_key$target_date,
        covariate_timeline = context$covariate_timeline,
        return_jacobian = TRUE
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
      feature_info_alpha <- assembled_alpha$feature_info
      J_direct_alpha <- app_latent_path_output_lag_jacobian(
        feature_info = feature_info_alpha,
        future_key = context$latent_data$future_key,
        feature_meta = feature_meta_alpha,
        cfg = context$cfg
      )
      res_rows_alpha <- which(feature_info_alpha$block == "reservoir_state")
      J_alpha <- vector("list", length(J_direct_alpha))
      for (h in seq_along(J_direct_alpha)) {
        Jh <- -J_direct_alpha[[h]]
        if (length(res_rows_alpha)) {
          if (length(res_rows_alpha) != nrow(cont_alpha$J_future_core[[h]])) {
            stop("Discrepancy reservoir sensitivity dimension does not match readout feature rows.", call. = FALSE)
          }
          Jh[res_rows_alpha, ] <- -cont_alpha$J_future_core[[h]]
        }
        J_alpha[[h]] <- Jh
      }
      X_beta <- assembled_beta$X
      X_alpha <- assembled_alpha$X
    } else {
      cont_alpha <- cont_beta
      feature_info_alpha <- feature_info_beta
      J_alpha <- J_beta
      X_beta <- assembled_beta$X
      X_alpha <- assembled_beta$X
      d_future <- NULL
    }

    p_beta <- ncol(X_beta)
    p_alpha <- ncol(X_alpha)
    H_y <- cbind(X_beta, matrix(0, nrow = nrow(X_beta), ncol = p_alpha))
    H_g_key <- cbind(X_beta, X_alpha)
    colnames(H_y) <- c(paste0("beta__", colnames(X_beta)), paste0("alpha__", colnames(X_alpha)))
    colnames(H_g_key) <- colnames(H_y)
    J_y <- lapply(J_beta, function(Jh) rbind(Jh, matrix(0, nrow = p_alpha, ncol = ncol(Jh))))
    J_g_key <- vector("list", length(J_beta))
    for (h in seq_along(J_beta)) {
      if (!all(dim(J_beta[[h]])[2L] == dim(J_alpha[[h]])[2L])) {
        stop("Reference and discrepancy future Jacobians have incompatible column counts.", call. = FALSE)
      }
      J_g_key[[h]] <- rbind(J_beta[[h]], J_alpha[[h]])
    }

    ens <- context$latent_data$g_ensemble
    key_id <- paste(context$latent_data$future_key$target_date, context$latent_data$future_key$horizon)
    ens_id <- paste(ens$target_date, ens$horizon)
    ens_future_index <- match(ens_id, key_id)
    if (any(is.na(ens_future_index))) stop("Issued ensemble rows do not match the latent future key.", call. = FALSE)
    row_info_y <- data.frame(
      source = "Y",
      row_role = "latent_future_usgs",
      future_index = seq_len(nrow(context$latent_data$future_key)),
      origin_date = context$latent_data$origin_date,
      target_date = context$latent_data$future_key$target_date,
      horizon = context$latent_data$future_key$horizon,
      member = NA_character_,
      stringsAsFactors = FALSE
    )
    row_info_g <- data.frame(
      source = "G",
      row_role = "issued_glofas_ensemble",
      future_index = ens_future_index,
      origin_date = ens$origin_date,
      target_date = ens$target_date,
      horizon = ens$horizon,
      member = ens$member,
      stringsAsFactors = FALSE
    )
    row_info_g_key <- data.frame(
      source = "G",
      row_role = "issued_glofas_ensemble_key",
      future_index = seq_len(nrow(context$latent_data$future_key)),
      origin_date = context$latent_data$origin_date,
      target_date = context$latent_data$future_key$target_date,
      horizon = context$latent_data$future_key$horizon,
      member = NA_character_,
      stringsAsFactors = FALSE
    )
    list(
      X_future = X_beta,
      X_beta_future = X_beta,
      X_alpha_future = X_alpha,
      H_y = H_y,
      H_g_key = H_g_key,
      g_future_index = ens_future_index,
      J_y = J_y,
      J_g_key = J_g_key,
      z_g = as.numeric(ens$g_transformed),
      row_info_y = row_info_y,
      row_info_g_key = row_info_g_key,
      row_info_g = row_info_g,
      feature_info = feature_info_beta,
      feature_info_beta = feature_info_beta,
      feature_info_alpha = feature_info_alpha,
      continuation = cont_beta,
      continuation_beta = cont_beta,
      continuation_alpha = cont_alpha,
      d_future = d_future,
      two_block_design = two_block,
      future_discrepancy_convention = if (isTRUE(two_block)) {
        "glofas_quantile_path_minus_latent_reference_path"
      } else {
        "shared_reference_feature_map"
      }
    )
  }
}

app_make_glofas_latent_path_design <- function(panel, cfg, model_row, cutoff_row = NULL, drop = NULL) {
  cutoff_row <- cutoff_row %||% app_latent_path_default_cutoff_row(cfg)
  latent_data <- app_make_glofas_latent_path_data(panel, cfg, cutoff_row, model_row)
  two_block <- isTRUE(app_discrepancy_uses_two_blocks(cfg))
  p0 <- as.numeric(model_row$quantile_level[[1L]])
  method <- app_normalize_qdesn_method(model_row$inference_method[[1L]])
  likelihood_family <- app_model_row_likelihood_family(model_row, cfg)
  if (!identical(method, "vb") || !identical(likelihood_family, "al")) {
    stop("The executable latent-path fitter currently supports inference_method = vb_ld and likelihood_family = al.", call. = FALSE)
  }
  design_timing <- list()
  time_design_step <- function(step, expr) {
    start <- proc.time()[["elapsed"]]
    value <- force(expr)
    elapsed <- proc.time()[["elapsed"]] - start
    design_timing[[length(design_timing) + 1L]] <<- data.frame(
      stage = paste0("build_latent_path_design.", step),
      elapsed_seconds = as.numeric(elapsed),
      stringsAsFactors = FALSE
    )
    value
  }

  base_mask <- latent_data$historical_panel$is_retrospective &
    is.finite(latent_data$historical_panel$y_transformed) &
    is.finite(latent_data$historical_panel$g_transformed)
  base_panel_full <- app_order_retrospective_panel(latent_data$historical_panel[base_mask, , drop = FALSE])
  base_panel_full <- app_copy_covariate_attrs(base_panel_full, panel)
  if (!nrow(base_panel_full)) stop("Latent-path design has no finite historical paired rows.", call. = FALSE)
  history_limit <- suppressWarnings(as.integer(
    (cfg$application_model %||% list())$max_history_rows %||%
      (cfg$latent_path %||% list())$max_history_rows %||%
      NA_integer_
  ))
  if (is.finite(history_limit) && history_limit > 0L && nrow(base_panel_full) > history_limit) {
    base_panel_full <- utils::tail(base_panel_full, history_limit)
    base_panel_full <- app_copy_covariate_attrs(base_panel_full, panel)
  }

  seed <- suppressWarnings(as.integer(app_model_row_value(model_row, "reservoir_seed", cfg$reservoir$seed %||% 20260513L)))
  if (!is.finite(seed)) seed <- as.integer(cfg$reservoir$seed %||% 20260513L)
  drop <- drop %||% as.integer(cfg$reservoir$washout %||% cfg$reservoir$m %||% 0L)
  horizon_scale <- app_discrepancy_horizon_scale(panel, cfg)
  latent_feature_strategy <- app_prediction_contract(
    cfg,
    model_family = "qdesn_glofas_discrepancy"
  )$discrepancy_feature_strategy

  beta_seed <- app_discrepancy_block_seed(model_row, cfg, "reference")
  alpha_seed <- app_discrepancy_block_seed(model_row, cfg, "discrepancy")
  beta_block <- time_design_step("beta_feature_block", {
    app_latent_path_feature_block(
    panel = base_panel_full,
    cfg = cfg,
    model_row = model_row,
    drop = drop,
    seed = beta_seed,
    feature_strategy = latent_feature_strategy,
    horizon_scale = horizon_scale
    )
  })
  feature_beta <- beta_block$feature
  qfit_beta <- beta_block$qfit

  if (isTRUE(two_block)) {
    base_panel_disc_full <- app_latent_path_discrepancy_panel(base_panel_full)
    alpha_block <- time_design_step("alpha_feature_block", {
      app_latent_path_feature_block(
      panel = base_panel_disc_full,
      cfg = cfg,
      model_row = model_row,
      drop = drop,
      seed = alpha_seed,
      feature_strategy = latent_feature_strategy,
      horizon_scale = horizon_scale
      )
    })
    feature_alpha <- alpha_block$feature
    qfit_alpha <- alpha_block$qfit
    if (!identical(as.integer(feature_beta$keep_idx), as.integer(feature_alpha$keep_idx))) {
      stop("Reference and discrepancy latent-path feature blocks retained different rows after washout.", call. = FALSE)
    }
    if (!identical(as.Date(feature_beta$panel$target_date), as.Date(feature_alpha$panel$target_date))) {
      stop("Reference and discrepancy latent-path feature blocks are not target-date aligned.", call. = FALSE)
    }
  } else {
    base_panel_disc_full <- app_latent_path_discrepancy_panel(base_panel_full)
    feature_alpha <- feature_beta
    qfit_alpha <- qfit_beta
  }

  base_panel <- feature_beta$panel
  X_beta <- feature_beta$X
  X_alpha <- feature_alpha$X
  if (nrow(X_beta) != nrow(X_alpha)) {
    stop("Reference and discrepancy feature matrices must have the same number of rows.", call. = FALSE)
  }
  source <- factor(c(rep("Y", nrow(base_panel)), rep("G", nrow(base_panel))), levels = c("Y", "G"))
  X_beta_stack <- rbind(X_beta, X_beta)
  X_alpha_stack <- rbind(X_alpha, X_alpha)
  H_fixed <- time_design_step("fixed_augmented_design", {
    app_make_augmented_discrepancy_design(X_beta_stack, source, X_alpha_stack)
  })
  z_fixed <- c(base_panel$y_transformed, base_panel$g_transformed)
  row_info_fixed <- rbind(
    data.frame(
      source = "Y",
      row_role = "historical_usgs",
      feature_row = seq_len(nrow(base_panel)),
      origin_date = base_panel$origin_date,
      target_date = base_panel$target_date,
      horizon = base_panel$horizon,
      member = base_panel$member,
      is_future = FALSE,
      stringsAsFactors = FALSE
    ),
    data.frame(
      source = "G",
      row_role = "historical_glofas_retrospective",
      feature_row = seq_len(nrow(base_panel)),
      origin_date = base_panel$origin_date,
      target_date = base_panel$target_date,
      horizon = base_panel$horizon,
      member = base_panel$member,
      is_future = FALSE,
      stringsAsFactors = FALSE
    )
  )

  p_beta <- ncol(X_beta)
  p_alpha <- ncol(X_alpha)
  intercept_index <- sort(unique(c(app_constant_one_columns(X_beta), p_beta + app_constant_one_columns(X_alpha))))
  glofas_future_quantile_path <- app_latent_path_glofas_quantile_path(latent_data, p0)
  context <- list(
    cfg = cfg,
    model_row = model_row,
    latent_data = latent_data,
    qfit = qfit_beta,
    qfit_beta = qfit_beta,
    qfit_alpha = qfit_alpha,
    y_history_full = as.numeric(base_panel_full$y_transformed),
    d_history_full = as.numeric(base_panel_disc_full$y_transformed),
    base_panel_full = base_panel_full,
    base_panel_disc_full = base_panel_disc_full,
    feature_meta = feature_beta$meta,
    feature_meta_beta = feature_beta$meta,
    feature_meta_alpha = feature_alpha$meta,
    horizon_scale = horizon_scale,
    feature_strategy = latent_feature_strategy,
    covariate_timeline = app_panel_covariate_timeline(base_panel_full, required = isTRUE(app_qdesn_reservoir_uses_covariates(cfg))),
    two_block_design = two_block,
    glofas_future_quantile_path = glofas_future_quantile_path,
    future_discrepancy_convention = if (isTRUE(two_block)) {
      "glofas_quantile_path_minus_latent_reference_path"
    } else {
      "shared_reference_feature_map"
    }
  )
  out <- list(
    z_fixed = as.numeric(z_fixed),
    H_fixed = H_fixed,
    source_fixed = source,
    row_info_fixed = row_info_fixed,
    X_beta = X_beta,
    X_alpha = X_alpha,
    X_base = X_beta,
    X_beta_stack = X_beta_stack,
    X_alpha_stack = X_alpha_stack,
    X_core_beta = feature_beta$X_core,
    X_core_alpha = feature_alpha$X_core,
    feature_info = feature_beta$feature_info,
    feature_info_beta = feature_beta$feature_info,
    feature_info_alpha = feature_alpha$feature_info,
    feature_meta = feature_beta$meta,
    feature_meta_beta = feature_beta$meta,
    feature_meta_alpha = feature_alpha$meta,
    readout_scale_info = feature_beta$readout_scale_info,
    readout_scale_info_alpha = feature_alpha$readout_scale_info,
    base_panel = base_panel,
    base_panel_full = base_panel_full,
    base_panel_disc_full = base_panel_disc_full,
    keep_idx = feature_beta$keep_idx,
    latent_data = latent_data,
    future_key = latent_data$future_key,
    y_future_init = app_latent_path_initial_future(latent_data, p0),
    y_future_oracle = latent_data$y_future_oracle,
    glofas_future_quantile_path = glofas_future_quantile_path,
    future_context = context,
    future_builder = app_make_latent_path_future_builder(context),
    beta_index = seq_len(p_beta),
    alpha_index = p_beta + seq_len(p_alpha),
    intercept_index = intercept_index,
    p0 = p0,
    feature_strategy = context$feature_strategy,
    horizon_scale = horizon_scale,
    design_version = if (isTRUE(two_block)) {
      "latent_path_two_block_v0.3"
    } else if (isTRUE(app_qdesn_reservoir_uses_covariates(cfg))) {
      "latent_path_covariate_reservoir_v0.1"
    } else {
      "latent_path_v0.1"
    },
    two_block_design = two_block,
    future_discrepancy_convention = context$future_discrepancy_convention,
    application_model_contract = "latent_path_ensemble_likelihood",
    fit_id = model_row$fit_id[[1L]],
    model_id = model_row$model_id[[1L]]
  )
  class(out) <- "glofas_latent_path_design"
  probe <- time_design_step("future_probe_init", {
    app_latent_path_future_probe(out)
  })
  time_design_step("validate_design", {
    app_validate_glofas_latent_path_design(out, probe = probe)
  })
  attr(out, "future_probe_init") <- probe
  attr(out, "design_substep_timing") <- if (length(design_timing)) {
    do.call(rbind, design_timing)
  } else {
    data.frame(stage = character(), elapsed_seconds = numeric())
  }
  out
}

app_latent_path_future_probe <- function(x, probe = NULL) {
  if (!is.null(probe)) return(probe)
  cached <- attr(x, "future_probe_init", exact = TRUE)
  if (!is.null(cached)) return(cached)
  x$future_builder(x$y_future_init)
}

app_latent_path_drop_runtime_cache <- function(x) {
  attr(x, "future_probe_init") <- NULL
  x
}

app_validate_glofas_latent_path_design <- function(x, probe = NULL) {
  required <- c("z_fixed", "H_fixed", "source_fixed", "row_info_fixed", "future_builder", "future_key", "beta_index", "alpha_index")
  missing <- setdiff(required, names(x))
  if (length(missing)) stop(sprintf("Latent-path design is missing: %s", paste(missing, collapse = ", ")), call. = FALSE)
  if (!is.matrix(x$H_fixed) || nrow(x$H_fixed) != length(x$z_fixed)) {
    stop("Latent-path fixed design has incompatible H_fixed and z_fixed.", call. = FALSE)
  }
  if (!length(x$beta_index) || !length(x$alpha_index)) {
    stop("Latent-path design requires non-empty beta and alpha coefficient blocks.", call. = FALSE)
  }
  if (!identical(sort(c(as.integer(x$beta_index), as.integer(x$alpha_index))), seq_len(ncol(x$H_fixed)))) {
    stop("Latent-path beta and alpha coefficient blocks must partition H_fixed columns.", call. = FALSE)
  }
  if (!is.null(x$X_beta) && ncol(x$X_beta) != length(x$beta_index)) {
    stop("Latent-path reference feature block does not match beta_index.", call. = FALSE)
  }
  if (!is.null(x$X_alpha) && ncol(x$X_alpha) != length(x$alpha_index)) {
    stop("Latent-path discrepancy feature block does not match alpha_index.", call. = FALSE)
  }
  if (length(x$source_fixed) != length(x$z_fixed) || !all(as.character(x$source_fixed) %in% c("Y", "G"))) {
    stop("Latent-path fixed source labels are invalid.", call. = FALSE)
  }
  if (!is.function(x$future_builder)) stop("Latent-path design requires a future_builder function.", call. = FALSE)
  probe <- app_latent_path_future_probe(x, probe = probe)
  if (!all(c("H_y", "J_y", "z_g", "row_info_y", "row_info_g") %in% names(probe))) {
    stop("Latent-path future builder returned an incomplete object.", call. = FALSE)
  }
  has_expanded <- all(c("H_g", "J_g") %in% names(probe))
  has_keyed <- all(c("H_g_key", "J_g_key", "g_future_index") %in% names(probe))
  if (!isTRUE(has_expanded || has_keyed)) {
    stop("Latent-path future builder must return either expanded or keyed GloFAS future design objects.", call. = FALSE)
  }
  H_g_check <- if (isTRUE(has_keyed)) as.matrix(probe$H_g_key) else as.matrix(probe$H_g)
  if (ncol(probe$H_y) != ncol(x$H_fixed) || ncol(H_g_check) != ncol(x$H_fixed)) {
    stop("Latent-path future design has incompatible column count.", call. = FALSE)
  }
  invisible(TRUE)
}

app_hash_latent_path_design <- function(x, probe = NULL) {
  probe <- app_latent_path_future_probe(x, probe = probe)
  app_validate_glofas_latent_path_design(x, probe = probe)
  tmp <- tempfile("glofas_latent_path_design_", fileext = ".rds")
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(
    list(
      z_fixed = x$z_fixed,
      H_fixed = x$H_fixed,
      source_fixed = as.character(x$source_fixed),
      row_info_fixed = x$row_info_fixed,
      future_key = x$future_key,
      y_future_init = x$y_future_init,
      H_y_init = probe$H_y,
      H_g_key_init = app_latent_future_H_g_key(probe),
      g_future_index = app_latent_future_g_index(probe),
	      row_info_y = probe$row_info_y,
	      row_info_g = probe$row_info_g,
	      X_beta = x$X_beta %||% x$X_base,
	      X_alpha = x$X_alpha %||% x$X_base,
	      feature_info_beta = x$feature_info_beta %||% x$feature_info,
	      feature_info_alpha = x$feature_info_alpha %||% x$feature_info,
	      p0 = x$p0,
	      beta_index = x$beta_index,
	      alpha_index = x$alpha_index,
	      intercept_index = x$intercept_index,
	      two_block_design = isTRUE(x$two_block_design %||% FALSE),
	      future_discrepancy_convention = x$future_discrepancy_convention %||% NA_character_,
	      design_version = x$design_version
	    ),
	    tmp
	  )
  app_sha256_file(tmp)
}

app_latent_path_design_summary <- function(x, probe = NULL) {
  probe <- app_latent_path_future_probe(x, probe = probe)
  app_validate_glofas_latent_path_design(x, probe = probe)
  cfg <- (x$future_context %||% list())$cfg %||% list()
  model_row <- (x$future_context %||% list())$model_row %||% data.frame()
  cfg_seed <- app_config_reservoir_seed(cfg)
  model_seed <- suppressWarnings(as.integer(app_model_row_value(model_row, "reservoir_seed", NA_integer_)))
  effective_seed <- app_model_row_reservoir_seed(model_row, cfg)
  reference_seed <- app_qdesn_block_seed(model_row, cfg, "reference")
  discrepancy_seed <- app_qdesn_block_seed(model_row, cfg, "discrepancy")
  counts_beta <- app_readout_feature_counts(x$feature_info_beta %||% x$feature_info)
  counts_alpha <- app_readout_feature_counts(x$feature_info_alpha %||% x$feature_info)
  reservoir_info_beta <- (x$feature_meta_beta %||% x$feature_meta %||% list())$reservoir_input_info %||% data.frame()
  reservoir_info_alpha <- (x$feature_meta_alpha %||% x$feature_meta %||% list())$reservoir_input_info %||% data.frame()
  n_res_input_output_beta <- if (nrow(reservoir_info_beta)) sum(reservoir_info_beta$input_block == "output_lag") else NA_integer_
  n_res_input_cov_beta <- if (nrow(reservoir_info_beta)) sum(reservoir_info_beta$input_block == "covariate_lag") else NA_integer_
  n_res_input_output_alpha <- if (nrow(reservoir_info_alpha)) sum(reservoir_info_alpha$input_block == "output_lag") else NA_integer_
  n_res_input_cov_alpha <- if (nrow(reservoir_info_alpha)) sum(reservoir_info_alpha$input_block == "covariate_lag") else NA_integer_
  covariate_timeline <- (x$future_context %||% list())$covariate_timeline %||% NULL
  covariate_policy_audit <- if (!is.null(covariate_timeline)) app_covariate_policy_audit(covariate_timeline) else data.frame()
  covariate_future_policy <- if (!is.null(covariate_timeline)) attr(covariate_timeline, "covariate_future_policy") %||% NA_character_ else NA_character_
  covariate_source_provider <- if (!is.null(covariate_timeline)) attr(covariate_timeline, "covariate_source_provider") %||% NA_character_ else NA_character_
  covariate_uses_realized_future <- if (nrow(covariate_policy_audit)) any(covariate_policy_audit$n_uses_realized_future > 0, na.rm = TRUE) else NA
  covariate_source_manifest_hash <- if (!is.null(covariate_timeline)) app_covariate_source_manifest_hash(covariate_timeline) else NA_character_
  data.frame(
    fit_id = x$fit_id %||% NA_character_,
    model_id = x$model_id %||% NA_character_,
    quantile_level = x$p0 %||% NA_real_,
    cfg_reservoir_seed = cfg_seed,
    model_grid_reservoir_seed = model_seed,
    effective_reservoir_seed = effective_seed,
    reference_reservoir_seed = reference_seed,
    discrepancy_reservoir_seed = discrepancy_seed,
    discrepancy_reservoir_seed_offset = discrepancy_seed - reference_seed,
    n_stacked_rows = length(x$z_fixed) + nrow(x$future_key) + nrow(x$latent_data$g_ensemble),
    n_y_rows = sum(as.character(x$source_fixed) == "Y") + nrow(x$future_key),
    n_g_rows = sum(as.character(x$source_fixed) == "G") + nrow(x$latent_data$g_ensemble),
    n_fixed_rows = length(x$z_fixed),
    n_y_fixed_rows = sum(as.character(x$source_fixed) == "Y"),
    n_g_fixed_rows = sum(as.character(x$source_fixed) == "G"),
    n_future_dates = nrow(x$future_key),
    n_issued_glofas_rows = nrow(x$latent_data$g_ensemble),
    max_history_rows_config = (x$future_context$cfg$application_model %||% list())$max_history_rows %||% NA_integer_,
    max_ensemble_members_per_horizon_config = (x$future_context$cfg$application_model %||% list())$max_ensemble_members_per_horizon %||% NA_integer_,
    requested_horizon_max = x$latent_data$requested_horizon_max,
    horizon_max = x$latent_data$horizon_max,
    horizon_scope = x$latent_data$horizon_scope,
    n_base_features = ncol(x$X_base),
    n_augmented_features = ncol(x$H_fixed),
    n_beta_features = length(x$beta_index),
    n_alpha_features = length(x$alpha_index),
    n_intercept_features = counts_beta$n_intercept_features + counts_alpha$n_intercept_features,
    n_beta_intercept_features = counts_beta$n_intercept_features,
    n_alpha_intercept_features = counts_alpha$n_intercept_features,
    n_reservoir_features = counts_beta$n_reservoir_features,
    n_beta_reservoir_features = counts_beta$n_reservoir_features,
    n_alpha_reservoir_features = counts_alpha$n_reservoir_features,
    n_direct_output_lag_features = counts_beta$n_direct_output_lag_features,
    n_beta_direct_output_lag_features = counts_beta$n_direct_output_lag_features,
    n_alpha_direct_output_lag_features = counts_alpha$n_direct_output_lag_features,
    n_direct_covariate_lag_features = counts_beta$n_direct_covariate_lag_features,
    n_beta_direct_covariate_lag_features = counts_beta$n_direct_covariate_lag_features,
    n_alpha_direct_covariate_lag_features = counts_alpha$n_direct_covariate_lag_features,
    n_horizon_features = counts_beta$n_horizon_features,
    n_beta_horizon_features = counts_beta$n_horizon_features,
    n_alpha_horizon_features = counts_alpha$n_horizon_features,
    n_reservoir_input_output_lag_features = n_res_input_output_beta,
    n_beta_reservoir_input_output_lag_features = n_res_input_output_beta,
    n_alpha_reservoir_input_output_lag_features = n_res_input_output_alpha,
    n_reservoir_input_covariate_lag_features = n_res_input_cov_beta,
    n_beta_reservoir_input_covariate_lag_features = n_res_input_cov_beta,
    n_alpha_reservoir_input_covariate_lag_features = n_res_input_cov_alpha,
    feature_contract_version = (x$feature_meta %||% list())$feature_contract$version %||% NA_character_,
    design_version = x$design_version %||% "latent_path_v0.1",
    two_block_design = isTRUE(x$two_block_design %||% FALSE),
    future_discrepancy_convention = x$future_discrepancy_convention %||% NA_character_,
    feature_strategy = x$feature_strategy %||% "recursive_latent_path",
    horizon_scale = x$horizon_scale %||% NA_real_,
    covariates_enabled = !is.null(covariate_timeline),
    covariate_future_policy = covariate_future_policy,
    covariate_source_provider = covariate_source_provider,
    covariate_uses_realized_future = covariate_uses_realized_future,
    covariate_source_manifest_hash = covariate_source_manifest_hash,
    design_hash = app_hash_latent_path_design(x, probe = probe),
    stringsAsFactors = FALSE
  )
}

app_latent_path_fit_diagnostics <- function(result) {
  base <- app_discrepancy_fit_diagnostics(result)
  base$application_model_contract <- "latent_path_ensemble_likelihood"
  base$n_future_dates <- nrow(result$design$future_key)
  base$latent_path_objective_type <- result$fit$vb_diagnostics$objective_type %||% NA_character_
  base$future_moment_strategy <- result$fit$vb_diagnostics$future_moment_strategy %||% NA_character_
  base$future_update_strategy <- result$fit$vb_diagnostics$future_update_strategy %||% NA_character_
  base$future_objective_strategy <- result$fit$vb_diagnostics$future_objective_strategy %||% NA_character_
  chunking <- result$fit$vb_diagnostics$chunking %||% list(enabled = FALSE)
  base$vb_chunking_enabled <- isTRUE(chunking$enabled)
  base$vb_chunking_mode <- as.character(chunking$mode %||% NA_character_)
  base$vb_chunk_size <- as.integer(chunking$chunk_size %||% NA_integer_)
  base$vb_iteration_timing_rows <- nrow(result$fit$vb_diagnostics$iteration_timing %||% data.frame())
  base$vb_stage_timing_rows <- nrow(result$fit$vb_diagnostics$stage_timing %||% data.frame())
  base$vb_substep_timing_rows <- nrow(result$fit$vb_diagnostics$substep_timing %||% data.frame())
  base$vb_draw_backend_requested <- result$fit$vb_diagnostics$draw_backend_requested %||% NA_character_
  base$vb_theta_draw_backend <- result$fit$vb_diagnostics$theta_draw_backend %||% NA_character_
  base$vb_future_draw_backend <- result$fit$vb_diagnostics$future_draw_backend %||% NA_character_
  warm_start <- result$fit$vb_diagnostics$warm_start %||% list(enabled = FALSE)
  base$vb_warm_start_enabled <- app_as_bool(warm_start$enabled %||% FALSE)
  base$vb_warm_start_used <- app_as_bool(warm_start$used %||% FALSE)
  base$vb_warm_start_theta_used <- app_as_bool(warm_start$theta_used %||% FALSE)
  base$vb_warm_start_future_used <- app_as_bool(warm_start$future_used %||% FALSE)
  base$vb_warm_start_sigma_used <- app_as_bool(warm_start$sigma_used %||% FALSE)
  base$vb_warm_start_source <- warm_start$source_path %||% NA_character_
  base$vb_warm_start_source_sha256 <- warm_start$source_sha256 %||% NA_character_
  base$vb_warm_start_message <- warm_start$message %||% NA_character_
  base
}

app_predict_qdesn_latent_path_draws <- function(result, panel, cfg, model_row) {
  required_result <- c("fit", "design", "fit_id", "model_id", "model_family", "quantile_level")
  missing_result <- setdiff(required_result, names(result))
  if (length(missing_result)) {
    stop(sprintf("Latent-path prediction result is missing: %s", paste(missing_result, collapse = ", ")), call. = FALSE)
  }
  contract <- app_prediction_contract(cfg, model_family = "qdesn_glofas_discrepancy")
  theta <- app_discrepancy_theta_draws(result$fit)
  y_draws <- as.matrix(result$fit$draws$y_future)
  if (nrow(theta) != nrow(y_draws)) {
    stop("Latent-path theta and future-path draws must have the same row count.", call. = FALSE)
  }
  n_draw <- nrow(theta)
  H <- nrow(result$design$future_key)
  prediction_design_hash <- NULL
  if (!is.null(result$design_summary) && "design_hash" %in% names(result$design_summary)) {
    prediction_design_hash <- result$design_summary$design_hash[[1L]]
  }
  prediction_design_hash <- prediction_design_hash %||% app_hash_latent_path_design(result$design)
  linearization <- result$fit$variational_state$future_linearization %||% NULL
  use_linearization <- !is.null(linearization) &&
    identical(linearization$strategy, "first_order_delta") &&
    length(linearization$J_x) == H &&
    nrow(linearization$X_future) == H &&
    length(linearization$y_mean) == H
  rows <- vector("list", n_draw * H)
  k <- 1L
  for (s in seq_len(n_draw)) {
    if (isTRUE(use_linearization)) {
      delta <- as.numeric(y_draws[s, ]) - as.numeric(linearization$y_mean)
      X_beta <- as.matrix(linearization$X_beta_future %||% linearization$X_future)
      X_alpha <- as.matrix(linearization$X_alpha_future %||% linearization$X_future)
      for (h in seq_len(H)) {
        X_beta[h, ] <- X_beta[h, ] + as.numeric(as.matrix((linearization$J_beta %||% linearization$J_x)[[h]]) %*% delta)
        X_alpha[h, ] <- X_alpha[h, ] + as.numeric(as.matrix((linearization$J_alpha %||% linearization$J_x)[[h]]) %*% delta)
      }
    } else {
      future <- result$design$future_builder(y_draws[s, ])
      X_beta <- future$X_beta_future %||% future$X_future
      X_alpha <- future$X_alpha_future %||% future$X_future
    }
    beta <- theta[s, result$design$beta_index]
    alpha <- theta[s, result$design$alpha_index]
    q_y <- as.numeric(X_beta %*% beta)
    d_g <- as.numeric(X_alpha %*% alpha)
    q_g <- q_y + d_g
    for (h in seq_len(H)) {
      rows[[k]] <- data.frame(
        draw_id = sprintf("%s:draw_%05d", result$fit_id, s),
        draw_index = s,
        fit_id = result$fit_id,
        model_id = result$model_id,
        model_family = result$model_family,
        quantile_level = as.numeric(result$quantile_level),
        origin_date = result$design$latent_data$origin_date,
        target_date = result$design$future_key$target_date[[h]],
        horizon = result$design$future_key$horizon[[h]],
        discrepancy_feature_date = result$design$future_key$target_date[[h]],
        q_y_draw = q_y[[h]],
        q_g_draw = q_g[[h]],
        d_g_draw = d_g[[h]],
        q_y_model_draw = q_y[[h]],
        q_g_model_draw = q_g[[h]],
        latent_y_draw = y_draws[s, h],
        prediction_state_strategy = if (isTRUE(use_linearization)) "first_order_delta" else "exact_rebuild",
        raw_glofas_quantile = app_ensemble_quantile(
          result$design$latent_data$g_ensemble[
            result$design$latent_data$g_ensemble$target_date == result$design$future_key$target_date[[h]] &
              result$design$latent_data$g_ensemble$horizon == result$design$future_key$horizon[[h]],
            ,
            drop = FALSE
          ],
          as.numeric(result$quantile_level)
        ),
        y_reference = result$design$y_future_oracle[[h]],
        prediction_design_hash = prediction_design_hash,
        stringsAsFactors = FALSE
      )
      k <- k + 1L
    }
  }
  draw_rows <- do.call(rbind, rows)
  draw_rows <- cbind(
    draw_rows,
    app_prediction_contract_columns(contract, result$model_family, nrow(draw_rows))
  )
  app_validate_posterior_draw_prediction_table(draw_rows)
  list(
    draws = draw_rows[order(draw_rows$origin_date, draw_rows$target_date, draw_rows$horizon, draw_rows$draw_index), , drop = FALSE],
    summary = app_summarize_discrepancy_draw_predictions(draw_rows),
	    prediction_design = list(
	      row_info = result$design$future_key,
	      design_version = result$design$design_version,
	      feature_strategy = result$design$feature_strategy %||% contract$discrepancy_feature_strategy,
	      prediction_state_strategy = if (isTRUE(use_linearization)) "first_order_delta" else "exact_rebuild",
	      p0 = result$design$p0
	    ),
	    prediction_design_summary = data.frame(
	      fit_id = result$fit_id,
	      model_id = result$model_id,
	      quantile_level = result$quantile_level,
	      n_prediction_rows = H,
	      n_prediction_features = ncol(result$design$X_base %||% result$design$X_beta),
	      prediction_design_hash = prediction_design_hash,
	      prediction_state_strategy = if (isTRUE(use_linearization)) "first_order_delta" else "exact_rebuild",
	      design_version = result$design$design_version,
	      feature_strategy = result$design$feature_strategy %||% contract$discrepancy_feature_strategy,
	      stringsAsFactors = FALSE
	    )
	  )
}

app_fit_qdesn_latent_path <- function(panel, cfg, model_row, cutoff_row = NULL, drop = NULL) {
  stage_timing <- list()
  time_stage <- function(step, expr) {
    start <- proc.time()[["elapsed"]]
    value <- force(expr)
    elapsed <- proc.time()[["elapsed"]] - start
    stage_timing[[length(stage_timing) + 1L]] <<- data.frame(
      stage = step,
      elapsed_seconds = as.numeric(elapsed),
      stringsAsFactors = FALSE
    )
    value
  }

  design <- time_stage("build_latent_path_design", {
    app_make_glofas_latent_path_design(
      panel = panel,
      cfg = cfg,
      model_row = model_row,
      cutoff_row = cutoff_row,
      drop = drop
    )
  })
  p0 <- as.numeric(model_row$quantile_level[[1L]])
  method <- app_normalize_qdesn_method(model_row$inference_method[[1L]])
  likelihood_family <- app_model_row_likelihood_family(model_row, cfg)
  prior <- app_map_qdesn_prior(model_row$coefficient_prior[[1L]])
  seed <- suppressWarnings(as.integer(app_model_row_value(model_row, "reservoir_seed", cfg$reservoir$seed %||% 20260513L)))
  if (!is.finite(seed)) seed <- as.integer(cfg$reservoir$seed %||% 20260513L)
  if (!identical(method, "vb") || !identical(likelihood_family, "al")) {
    stop("Latent-path fitting currently supports AL-VB only.", call. = FALSE)
  }

  vb_args <- time_stage("prepare_vb_args", {
    app_make_qdesn_discrepancy_vb_args(
      cfg,
      prior = prior,
      seed = seed,
      likelihood_family = likelihood_family
    )
  })
  vb_args$likelihood_family <- likelihood_family
  fit <- time_stage("fit_latent_path_al_vb_core", {
    app_fit_latent_path_al_vb_core(
      design = design,
      p0 = p0,
      coefficient_prior = prior,
      vb_args = vb_args,
      seed = seed
    )
  })
  design_summary <- time_stage("summarize_latent_path_design", {
    app_latent_path_design_summary(design)
  })
  stage_timing_df <- if (length(stage_timing)) {
    do.call(rbind, stage_timing)
  } else {
    data.frame(stage = character(), elapsed_seconds = numeric())
  }
  design_substeps <- attr(design, "design_substep_timing", exact = TRUE)
  if (!is.null(design_substeps) && nrow(design_substeps)) {
    stage_timing_df <- rbind(stage_timing_df, design_substeps)
  }
  fit$vb_diagnostics$stage_timing <- stage_timing_df

  list(
    fit_id = model_row$fit_id[[1L]],
    model_id = model_row$model_id[[1L]],
    model_family = model_row$model_family[[1L]],
    quantile_level = p0,
    method = method,
    likelihood_family = likelihood_family,
    coefficient_prior = prior,
    fit = fit,
    design = design,
    design_summary = design_summary,
    mcmc_args = list(),
    vb_args = vb_args,
    status = "completed",
    message = "latent-path AL-VB fit completed"
  )
}
