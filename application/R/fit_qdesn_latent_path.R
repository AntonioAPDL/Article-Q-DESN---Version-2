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

app_latent_path_discrepancy_transition_strategy <- function(cfg) {
  strategy <- as.character(
    (cfg$prediction %||% list())$discrepancy_transition_strategy %||% "recursive_level"
  )
  allowed <- c("recursive_level", "persistence_anchored_innovation")
  if (length(strategy) != 1L || is.na(strategy) || !strategy %in% allowed) {
    stop(
      sprintf(
        "prediction.discrepancy_transition_strategy must be one of: %s.",
        paste(allowed, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  strategy
}

app_latent_path_discrepancy_lag_one <- function(panel, anchor_dates) {
  lagged <- app_y_lag_matrix(
    panel = panel,
    anchor_dates = anchor_dates,
    lags = 1L,
    standardize = FALSE
  )$X
  out <- as.numeric(lagged[, 1L])
  if (length(out) != length(anchor_dates) || any(!is.finite(out))) {
    stop("Persistence-anchored discrepancy baselines must be finite and date aligned.", call. = FALSE)
  }
  out
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
  compiled <- new.env(parent = emptyenv())
  compiled$enabled <- !identical(
    (context$runtime_optimization %||% list())$compiled_future_contract,
    FALSE
  )
  compiled$active_jacobian <- isTRUE(compiled$enabled) && !identical(
    (context$runtime_optimization %||% list())$active_future_jacobian,
    FALSE
  )
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
    cfg_beta <- context$cfg_beta %||% app_qdesn_block_config(context$cfg, "reference")
    cfg_alpha <- context$cfg_alpha %||% app_qdesn_block_config(
      context$cfg,
      if (isTRUE(two_block)) "discrepancy" else "reference"
    )
    discrepancy_input_stream <- if (isTRUE(two_block)) {
      as.character(
        context$discrepancy_input_stream %||%
          app_qdesn_block_input_stream(context$cfg, "discrepancy")
      )[[1L]]
    } else {
      "reference"
    }
    alpha_uses_reference_input <- isTRUE(two_block) &&
      identical(discrepancy_input_stream, "reference")

    beta_input_contract <- if (isTRUE(compiled$enabled)) {
      compiled$beta_input_contract %||% NULL
    } else {
      NULL
    }
    cont_beta <- app_qdesn_continue_latent_path(
      qfit = qfit_beta,
      y_history = context$y_history_full,
      y_future = y_future,
      future_dates = context$latent_data$future_key$target_date,
      covariate_timeline = context$covariate_timeline,
      return_jacobian = TRUE,
      active_jacobian = isTRUE(compiled$active_jacobian),
      compiled_inputs = beta_input_contract,
      compile_inputs = isTRUE(compiled$enabled),
      verify_compiled_hash = FALSE
    )
    if (isTRUE(compiled$enabled)) {
      if (is.null(compiled$beta_input_contract)) {
        compiled$beta_input_contract <- cont_beta$compiled_input_contract
      }
      cont_beta$compiled_input_contract <- NULL
    }
    beta_readout_cached <- isTRUE(compiled$enabled) &&
      !is.null(compiled$beta_readout)
    if (isTRUE(beta_readout_cached)) {
      feature_info_beta <- compiled$beta_readout$feature_info
      beta_signature <- compiled$beta_readout$signature
      J_direct_beta <- compiled$beta_readout$J_direct
      res_rows_beta <- compiled$beta_readout$reservoir_rows
      delta_y <- y_future - compiled$beta_readout$anchor_y_future
      X_beta_cached <- compiled$beta_readout$anchor_X
      if (any(delta_y != 0)) {
        for (h in seq_len(nrow(X_beta_cached))) {
          X_beta_cached[h, ] <- X_beta_cached[h, ] +
            as.numeric(J_direct_beta[[h]] %*% delta_y)
        }
      }
      if (length(res_rows_beta)) {
        if (length(res_rows_beta) != ncol(cont_beta$X_future_core)) {
          stop("Cached reference readout reservoir rows are incompatible with continuation states.", call. = FALSE)
        }
        X_beta_cached[, res_rows_beta] <- cont_beta$X_future_core
      }
      assembled_beta <- list(
        X = X_beta_cached,
        feature_info = feature_info_beta,
        readout_scale_info = compiled$beta_readout$readout_scale_info,
        contract = compiled$beta_readout$contract
      )
    } else {
      combined_beta_panel <- app_latent_path_combined_panel(
        base_panel = context$base_panel_full,
        latent_data = context$latent_data,
        y_future = y_future
      )
      assembled_beta <- app_build_readout_feature_matrix(
        reservoir_X = cont_beta$X_future_core,
        panel = combined_beta_panel,
        cfg = cfg_beta,
        output_anchor_dates = context$latent_data$future_key$target_date,
        covariate_target_dates = context$latent_data$future_key$target_date,
        horizon = context$latent_data$future_key$horizon,
        feature_strategy = context$feature_strategy,
        horizon_scale = context$horizon_scale,
        feature_meta = feature_meta_beta,
        fit_scale = FALSE
      )
      feature_info_beta <- assembled_beta$feature_info
      beta_signature <- data.frame(
        column_name = as.character(feature_info_beta$column_name),
        block = as.character(feature_info_beta$block),
        variable = as.character(feature_info_beta$variable),
        lag = suppressWarnings(as.integer(feature_info_beta$lag)),
        stringsAsFactors = FALSE
      )
      J_direct_beta <- app_latent_path_output_lag_jacobian(
        feature_info = feature_info_beta,
        future_key = context$latent_data$future_key,
        feature_meta = feature_meta_beta,
        cfg = cfg_beta
      )
      res_rows_beta <- which(feature_info_beta$block == "reservoir_state")
      if (isTRUE(compiled$enabled)) {
        compiled$beta_readout <- list(
          anchor_y_future = y_future,
          anchor_X = assembled_beta$X,
          feature_info = feature_info_beta,
          signature = beta_signature,
          J_direct = J_direct_beta,
          reservoir_rows = res_rows_beta,
          readout_scale_info = assembled_beta$readout_scale_info,
          contract = assembled_beta$contract
        )
      }
    }
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

    alpha_feature_static <- FALSE
    if (isTRUE(two_block)) {
      qg_path <- as.numeric(context$glofas_future_quantile_path)
      if (length(qg_path) != length(y_future) || any(!is.finite(qg_path))) {
        stop("Two-block latent-path future builder requires a finite GloFAS quantile path.", call. = FALSE)
      }
      transition_strategy <- context$discrepancy_transition_strategy %||% "recursive_level"
      if (identical(transition_strategy, "persistence_anchored_innovation")) {
        discrepancy_baseline_future <- rep(
          utils::tail(as.numeric(context$d_history_full), 1L),
          length(y_future)
        )
        d_feature_future <- discrepancy_baseline_future
      } else {
        discrepancy_baseline_future <- rep(0, length(y_future))
        d_feature_future <- qg_path - y_future
      }
      if (any(!is.finite(discrepancy_baseline_future)) || any(!is.finite(d_feature_future))) {
        stop("Discrepancy future baselines and feature paths must be finite.", call. = FALSE)
      }
      alpha_feature_static <- identical(transition_strategy, "persistence_anchored_innovation") &&
        !isTRUE(alpha_uses_reference_input)
      alpha_cache_valid <- isTRUE(compiled$enabled) && isTRUE(alpha_feature_static) &&
        !is.null(compiled$alpha_static)
      if (isTRUE(alpha_cache_valid)) {
        cont_alpha <- compiled$alpha_static$continuation
        assembled_alpha <- compiled$alpha_static$assembled
        feature_info_alpha <- compiled$alpha_static$feature_info
        J_alpha <- compiled$alpha_static$jacobian
      } else {
        alpha_input_contract <- if (isTRUE(compiled$enabled)) {
          compiled$alpha_input_contract %||% NULL
        } else {
          NULL
        }
        alpha_history <- if (isTRUE(alpha_uses_reference_input)) {
          context$y_history_full
        } else {
          context$d_history_full
        }
        alpha_future <- if (isTRUE(alpha_uses_reference_input)) y_future else d_feature_future
        alpha_panel <- if (isTRUE(alpha_uses_reference_input)) {
          context$base_panel_full
        } else {
          context$base_panel_disc_full
        }
        alpha_derivative_sign <- if (isTRUE(alpha_uses_reference_input)) 1 else -1
        cont_alpha <- app_qdesn_continue_latent_path(
          qfit = qfit_alpha,
          y_history = alpha_history,
          y_future = alpha_future,
          future_dates = context$latent_data$future_key$target_date,
          covariate_timeline = context$covariate_timeline,
          # A discrepancy block driven by the latent reference path is dynamic,
          # even under persistence-anchored discrepancy innovations.
          return_jacobian = !isTRUE(alpha_feature_static) || !isTRUE(compiled$enabled),
          active_jacobian = isTRUE(compiled$active_jacobian),
          compiled_inputs = alpha_input_contract,
          compile_inputs = isTRUE(compiled$enabled),
          verify_compiled_hash = FALSE
        )
        if (isTRUE(compiled$enabled)) {
          if (is.null(compiled$alpha_input_contract)) {
            compiled$alpha_input_contract <- cont_alpha$compiled_input_contract
          }
          cont_alpha$compiled_input_contract <- NULL
        }
        combined_alpha_panel <- app_latent_path_combined_panel(
          base_panel = alpha_panel,
          latent_data = context$latent_data,
          y_future = alpha_future
        )
        assembled_alpha <- app_build_readout_feature_matrix(
          reservoir_X = cont_alpha$X_future_core,
          panel = combined_alpha_panel,
          cfg = cfg_alpha,
          output_anchor_dates = context$latent_data$future_key$target_date,
          covariate_target_dates = context$latent_data$future_key$target_date,
          horizon = context$latent_data$future_key$horizon,
          feature_strategy = context$feature_strategy,
          horizon_scale = context$horizon_scale,
          feature_meta = feature_meta_alpha,
          fit_scale = FALSE
        )
        feature_info_alpha <- assembled_alpha$feature_info
        if (isTRUE(alpha_feature_static)) {
          J_alpha <- lapply(seq_len(nrow(context$latent_data$future_key)), function(h) {
            matrix(0, nrow = ncol(assembled_alpha$X), ncol = length(y_future))
          })
          if (isTRUE(compiled$enabled)) {
            compiled$alpha_static <- list(
              continuation = cont_alpha,
              assembled = assembled_alpha,
              feature_info = feature_info_alpha,
              jacobian = J_alpha
            )
          }
        } else {
          J_direct_alpha <- app_latent_path_output_lag_jacobian(
            feature_info = feature_info_alpha,
            future_key = context$latent_data$future_key,
            feature_meta = feature_meta_alpha,
            cfg = cfg_alpha
          )
          res_rows_alpha <- which(feature_info_alpha$block == "reservoir_state")
          J_alpha <- vector("list", length(J_direct_alpha))
          for (h in seq_along(J_direct_alpha)) {
            Jh <- alpha_derivative_sign * J_direct_alpha[[h]]
            if (length(res_rows_alpha)) {
              if (length(res_rows_alpha) != nrow(cont_alpha$J_future_core[[h]])) {
                stop("Discrepancy reservoir sensitivity dimension does not match readout feature rows.", call. = FALSE)
              }
              Jh[res_rows_alpha, ] <- alpha_derivative_sign * cont_alpha$J_future_core[[h]]
            }
            J_alpha[[h]] <- Jh
          }
        }
      }
      X_beta <- assembled_beta$X
      X_alpha <- assembled_alpha$X
    } else {
      cont_alpha <- cont_beta
      feature_info_alpha <- feature_info_beta
      J_alpha <- J_beta
      X_beta <- assembled_beta$X
      X_alpha <- assembled_beta$X
      d_feature_future <- NULL
      discrepancy_baseline_future <- rep(0, length(y_future))
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
    paired_future_jacobian <- isTRUE(compiled$enabled) &&
      (!isTRUE(two_block) || isTRUE(alpha_feature_static))

    if (isTRUE(compiled$enabled) && !is.null(compiled$future_rows)) {
      ens <- compiled$future_rows$ensemble
      ens_future_index <- compiled$future_rows$ensemble_future_index
      row_info_y <- compiled$future_rows$row_info_y
      row_info_g <- compiled$future_rows$row_info_g
      row_info_g_key <- compiled$future_rows$row_info_g_key
    } else {
      ens <- context$latent_data$g_ensemble
      key_id <- paste(context$latent_data$future_key$target_date, context$latent_data$future_key$horizon)
      ens_id <- paste(ens$target_date, ens$horizon)
      ens_future_index <- match(ens_id, key_id)
      if (any(is.na(ens_future_index))) stop("Issued ensemble rows do not match the latent future key.", call. = FALSE)
      row_info_y <- data.frame(
        source = "Y", row_role = "latent_future_usgs",
        future_index = seq_len(nrow(context$latent_data$future_key)),
        origin_date = context$latent_data$origin_date,
        target_date = context$latent_data$future_key$target_date,
        horizon = context$latent_data$future_key$horizon,
        member = NA_character_, stringsAsFactors = FALSE
      )
      row_info_g <- data.frame(
        source = "G", row_role = "issued_glofas_ensemble",
        future_index = ens_future_index, origin_date = ens$origin_date,
        target_date = ens$target_date, horizon = ens$horizon, member = ens$member,
        stringsAsFactors = FALSE
      )
      row_info_g_key <- data.frame(
        source = "G", row_role = "issued_glofas_ensemble_key",
        future_index = seq_len(nrow(context$latent_data$future_key)),
        origin_date = context$latent_data$origin_date,
        target_date = context$latent_data$future_key$target_date,
        horizon = context$latent_data$future_key$horizon,
        member = NA_character_, stringsAsFactors = FALSE
      )
      if (isTRUE(compiled$enabled)) {
        compiled$future_rows <- list(
          ensemble = ens,
          ensemble_future_index = ens_future_index,
          row_info_y = row_info_y,
          row_info_g = row_info_g,
          row_info_g_key = row_info_g_key
        )
      }
    }
    if (isTRUE(compiled$enabled) && is.null(compiled$contract_hash)) {
      compiled$contract_hash <- app_latent_path_contract_hash(
        list(
          future_key = context$latent_data$future_key,
          ensemble_future_index = ens_future_index,
          beta_signature = beta_signature,
          alpha_columns = as.character(feature_info_alpha$column_name),
          active_jacobian = isTRUE(compiled$active_jacobian),
          reference_readout_template = !is.null(compiled$beta_readout),
          beta_input_contract_hash = compiled$beta_input_contract$contract_hash %||% NA_character_,
          alpha_input_contract_hash = compiled$alpha_input_contract$contract_hash %||% NA_character_,
          paired_future_jacobian = isTRUE(paired_future_jacobian),
          persistence_static = isTRUE(alpha_feature_static),
          discrepancy_input_stream = discrepancy_input_stream
        ),
        prefix = "latent_compiled_future_"
      )
    }
    list(
      X_future = X_beta,
      X_beta_future = X_beta,
      X_alpha_future = X_alpha,
      H_y = H_y,
      H_g_key = H_g_key,
      g_future_index = ens_future_index,
      J_y = J_y,
      J_g_key = J_g_key,
      paired_future_jacobian = isTRUE(paired_future_jacobian),
      z_g = as.numeric(ens$g_transformed) - discrepancy_baseline_future[ens_future_index],
      row_info_y = row_info_y,
      row_info_g_key = row_info_g_key,
      row_info_g = row_info_g,
      feature_info = feature_info_beta,
      feature_info_beta = feature_info_beta,
      feature_info_alpha = feature_info_alpha,
      continuation = cont_beta,
      continuation_beta = cont_beta,
      continuation_alpha = cont_alpha,
      d_future = d_feature_future,
      discrepancy_feature_path = d_feature_future,
      discrepancy_baseline_future = discrepancy_baseline_future,
      discrepancy_transition_strategy = context$discrepancy_transition_strategy %||% "recursive_level",
      discrepancy_input_stream = discrepancy_input_stream,
      two_block_design = two_block,
      future_discrepancy_convention = context$future_discrepancy_convention,
      compiled_future_contract = list(
        enabled = isTRUE(compiled$enabled),
        active_jacobian = isTRUE(compiled$active_jacobian),
        reference_readout_template_cached = !is.null(compiled$beta_readout),
        beta_input_contract_hash = compiled$beta_input_contract$contract_hash %||% NA_character_,
        alpha_input_contract_hash = compiled$alpha_input_contract$contract_hash %||% NA_character_,
        paired_future_jacobian = isTRUE(paired_future_jacobian),
        persistence_static = !is.null(compiled$alpha_static),
        contract_hash = compiled$contract_hash %||% NA_character_
      )
    )
  }
}

app_latent_reference_feature_cache_config <- function(cfg) {
  raw <- (cfg$runtime_optimization %||% list())$reference_feature_cache %||% list()
  env_root <- Sys.getenv("QDESN_REFERENCE_FEATURE_CACHE_ROOT", unset = "")
  configured_root <- raw$root %||% ""
  configured_root <- if (length(configured_root)) {
    as.character(configured_root[[1L]])
  } else {
    ""
  }
  if (is.na(configured_root)) configured_root <- ""
  root <- trimws(configured_root)
  if (!nzchar(root)) root <- trimws(env_root)
  enabled <- app_as_bool(raw$enabled %||% nzchar(root))
  wait_seconds <- suppressWarnings(as.numeric(raw$wait_seconds %||% 600))
  poll_seconds <- suppressWarnings(as.numeric(raw$poll_seconds %||% 0.25))
  if (!is.finite(wait_seconds) || wait_seconds <= 0) wait_seconds <- 600
  if (!is.finite(poll_seconds) || poll_seconds <= 0) poll_seconds <- 0.25
  if (isTRUE(enabled) && !nzchar(root)) {
    stop("Reference feature caching is enabled but no cache root is configured.", call. = FALSE)
  }
  list(
    enabled = enabled,
    root = if (nzchar(root)) normalizePath(root, mustWork = FALSE) else "",
    wait_seconds = wait_seconds,
    poll_seconds = poll_seconds,
    schema_version = "glofas_reference_feature_cache_v1"
  )
}

app_latent_reference_feature_cache_engine_hash <- function() {
  names <- c(
    "app_latent_path_feature_block",
    "app_qdesn_build_article_design_full",
    "app_build_readout_feature_matrix"
  )
  bodies <- lapply(names, function(name) {
    if (!exists(name, mode = "function", inherits = TRUE)) return(NULL)
    body(get(name, mode = "function", inherits = TRUE))
  })
  names(bodies) <- names
  app_latent_path_contract_hash(bodies, prefix = "latent_reference_feature_engine_")
}

app_latent_reference_feature_cache_contract <- function(
  base_panel_full,
  cfg_beta,
  model_row,
  drop,
  seed,
  feature_strategy,
  horizon_scale
) {
  model_contract <- as.list(model_row[1L, , drop = FALSE])
  model_contract[c("fit_id", "model_id", "quantile_level")] <- NULL
  contract <- list(
    schema_version = "glofas_reference_feature_cache_contract_v1",
    block_role = "reference",
    panel_hash = app_latent_path_contract_hash(
      base_panel_full,
      prefix = "latent_reference_panel_"
    ),
    reference_config_hash = app_latent_path_contract_hash(
      cfg_beta,
      prefix = "latent_reference_config_"
    ),
    model_contract = model_contract,
    drop = as.integer(drop),
    seed = as.integer(seed),
    feature_strategy = as.character(feature_strategy),
    horizon_scale = as.numeric(horizon_scale),
    engine_hash = app_latent_reference_feature_cache_engine_hash()
  )
  contract$contract_hash <- app_latent_path_contract_hash(
    contract,
    prefix = "latent_reference_feature_cache_"
  )
  contract
}

app_latent_reference_feature_cache_path <- function(cache_cfg, contract) {
  file.path(cache_cfg$root, paste0(contract$contract_hash, ".rds"))
}

app_latent_reference_feature_cache_validate <- function(payload, contract) {
  block_role <- as.character(contract$block_role %||% "reference")[[1L]]
  if (!identical(block_role, "reference")) {
    stop("Reference feature cache contracts cannot contain discrepancy-block payloads.", call. = FALSE)
  }
  if (!is.list(payload) ||
      !identical(payload$schema_version, "glofas_reference_feature_cache_v1") ||
      !identical(payload$contract$contract_hash, contract$contract_hash) ||
      !is.list(payload$beta_block) ||
      !all(c("feature", "qfit") %in% names(payload$beta_block))) {
    stop("Reference feature cache payload failed its semantic contract.", call. = FALSE)
  }
  invisible(TRUE)
}

app_latent_reference_feature_cache_read <- function(path, contract) {
  hash_path <- paste0(path, ".sha256")
  if (!file.exists(path) || !file.exists(hash_path)) {
    stop("Reference feature cache payload or hash is missing.", call. = FALSE)
  }
  expected <- tolower(trimws(readLines(hash_path, n = 1L, warn = FALSE)))
  observed <- tolower(app_sha256_file(path))
  if (!identical(expected, observed)) {
    stop(sprintf("Reference feature cache hash mismatch: %s.", path), call. = FALSE)
  }
  payload <- readRDS(path)
  app_latent_reference_feature_cache_validate(payload, contract)
  payload
}

app_latent_reference_feature_cache_write <- function(path, contract, beta_block) {
  app_ensure_dir(dirname(path))
  payload <- list(
    schema_version = "glofas_reference_feature_cache_v1",
    contract = contract,
    beta_block = beta_block,
    created_at = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
  app_latent_reference_feature_cache_validate(payload, contract)
  tmp <- paste0(path, ".tmp.", Sys.getpid())
  tmp_hash <- paste0(tmp, ".sha256")
  on.exit(unlink(c(tmp, tmp_hash), force = TRUE), add = TRUE)
  saveRDS(payload, tmp, compress = FALSE, version = 3L)
  if (exists("app_latent_checkpoint_fsync", mode = "function")) {
    app_latent_checkpoint_fsync(tmp)
  }
  roundtrip <- readRDS(tmp)
  app_latent_reference_feature_cache_validate(roundtrip, contract)
  writeLines(app_sha256_file(tmp), tmp_hash, useBytes = TRUE)
  if (exists("app_latent_checkpoint_fsync", mode = "function")) {
    app_latent_checkpoint_fsync(tmp_hash)
  }
  if (!file.rename(tmp, path)) {
    stop(sprintf("Could not atomically install reference feature cache: %s.", path), call. = FALSE)
  }
  if (!file.rename(tmp_hash, paste0(path, ".sha256"))) {
    unlink(path, force = TRUE)
    stop(sprintf("Could not install reference feature cache hash: %s.", path), call. = FALSE)
  }
  invisible(payload)
}

app_latent_reference_feature_cache_get_or_build <- function(
  cache_cfg,
  contract,
  builder
) {
  if (!is.function(builder)) stop("Reference feature cache builder must be a function.", call. = FALSE)
  if (!isTRUE(cache_cfg$enabled)) {
    return(list(
      beta_block = builder(),
      diagnostics = list(enabled = FALSE, hit = FALSE, path = NA_character_)
    ))
  }
  app_ensure_dir(cache_cfg$root)
  path <- app_latent_reference_feature_cache_path(cache_cfg, contract)
  read_valid <- function() tryCatch(
    app_latent_reference_feature_cache_read(path, contract),
    error = function(e) NULL
  )
  cached <- read_valid()
  if (!is.null(cached)) {
    return(list(
      beta_block = cached$beta_block,
      diagnostics = list(
        enabled = TRUE, hit = TRUE, path = path,
        contract_hash = contract$contract_hash,
        payload_sha256 = app_sha256_file(path)
      )
    ))
  }
  lock <- paste0(path, ".lock")
  started <- proc.time()[["elapsed"]]
  acquired <- FALSE
  repeat {
    acquired <- dir.create(lock, showWarnings = FALSE, recursive = FALSE)
    if (isTRUE(acquired)) break
    cached <- read_valid()
    if (!is.null(cached)) {
      return(list(
        beta_block = cached$beta_block,
        diagnostics = list(
          enabled = TRUE, hit = TRUE, waited = TRUE, path = path,
          contract_hash = contract$contract_hash,
          payload_sha256 = app_sha256_file(path)
        )
      ))
    }
    if (proc.time()[["elapsed"]] - started >= cache_cfg$wait_seconds) {
      stop(sprintf("Timed out waiting for immutable reference feature cache lock: %s.", lock), call. = FALSE)
    }
    Sys.sleep(cache_cfg$poll_seconds)
  }
  on.exit(if (isTRUE(acquired)) unlink(lock, recursive = TRUE, force = TRUE), add = TRUE)
  saveRDS(
    list(pid = Sys.getpid(), host = Sys.info()[["nodename"]], created_at = Sys.time()),
    file.path(lock, "owner.rds")
  )
  cached <- read_valid()
  if (!is.null(cached)) {
    return(list(
      beta_block = cached$beta_block,
      diagnostics = list(
        enabled = TRUE, hit = TRUE, waited = TRUE, path = path,
        contract_hash = contract$contract_hash,
        payload_sha256 = app_sha256_file(path)
      )
    ))
  }
  beta_block <- builder()
  app_latent_reference_feature_cache_write(path, contract, beta_block)
  list(
    beta_block = beta_block,
    diagnostics = list(
      enabled = TRUE, hit = FALSE, waited = FALSE, path = path,
      contract_hash = contract$contract_hash,
      payload_sha256 = app_sha256_file(path)
    )
  )
}

app_make_glofas_latent_path_design <- function(panel, cfg, model_row, cutoff_row = NULL, drop = NULL) {
  cutoff_row <- cutoff_row %||% app_latent_path_default_cutoff_row(cfg)
  latent_data <- app_make_glofas_latent_path_data(panel, cfg, cutoff_row, model_row)
  two_block <- isTRUE(app_discrepancy_uses_two_blocks(cfg))
  discrepancy_transition_strategy <- app_latent_path_discrepancy_transition_strategy(cfg)
  if (!isTRUE(two_block) && !identical(discrepancy_transition_strategy, "recursive_level")) {
    stop(
      "Persistence-anchored discrepancy innovations require feature_contract.two_block_design = true.",
      call. = FALSE
    )
  }
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
  cfg_beta <- app_qdesn_block_config(cfg, "reference")
  cfg_alpha <- if (isTRUE(two_block)) app_qdesn_block_config(cfg, "discrepancy") else cfg_beta
  discrepancy_input_stream <- if (isTRUE(two_block)) {
    app_qdesn_block_input_stream(cfg, "discrepancy")
  } else {
    "reference"
  }
  drop <- app_qdesn_common_washout(cfg, drop = drop)
  row_alignment <- app_feature_contract_common_history_alignment(
    configs = if (isTRUE(two_block)) {
      list(reference = cfg_beta, discrepancy = cfg_alpha)
    } else {
      list(reference = cfg_beta)
    },
    requested_drop = drop
  )
  drop <- unique(row_alignment$common_drop)
  if (length(drop) != 1L || !is.finite(drop)) {
    stop("Feature-block history alignment did not produce one common drop.", call. = FALSE)
  }
  drop <- as.integer(drop)
  horizon_scale <- app_discrepancy_horizon_scale(panel, cfg)
  latent_feature_strategy <- app_prediction_contract(
    cfg,
    model_family = "qdesn_glofas_discrepancy"
  )$discrepancy_feature_strategy

  beta_seed <- app_discrepancy_block_seed(model_row, cfg, "reference")
  alpha_seed <- app_discrepancy_block_seed(model_row, cfg, "discrepancy")
  reference_cache_cfg <- app_latent_reference_feature_cache_config(cfg)
  reference_cache_contract <- app_latent_reference_feature_cache_contract(
    base_panel_full = base_panel_full,
    cfg_beta = cfg_beta,
    model_row = model_row,
    drop = drop,
    seed = beta_seed,
    feature_strategy = latent_feature_strategy,
    horizon_scale = horizon_scale
  )
  beta_cache <- time_design_step("beta_feature_block", {
    app_latent_reference_feature_cache_get_or_build(
      cache_cfg = reference_cache_cfg,
      contract = reference_cache_contract,
      builder = function() app_latent_path_feature_block(
        panel = base_panel_full,
        cfg = cfg_beta,
        model_row = model_row,
        drop = drop,
        seed = beta_seed,
        feature_strategy = latent_feature_strategy,
        horizon_scale = horizon_scale
      )
    )
  })
  beta_block <- beta_cache$beta_block
  feature_beta <- beta_block$feature
  qfit_beta <- beta_block$qfit

  if (isTRUE(two_block)) {
    base_panel_disc_full <- app_latent_path_discrepancy_panel(base_panel_full)
    alpha_input_panel_full <- if (identical(discrepancy_input_stream, "reference")) {
      base_panel_full
    } else {
      base_panel_disc_full
    }
    alpha_block <- time_design_step("alpha_feature_block", {
      app_latent_path_feature_block(
        panel = alpha_input_panel_full,
        cfg = cfg_alpha,
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
    alpha_input_panel_full <- base_panel_full
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
  discrepancy_baseline_fixed <- if (identical(
    discrepancy_transition_strategy,
    "persistence_anchored_innovation"
  )) {
    app_latent_path_discrepancy_lag_one(base_panel_disc_full, base_panel$target_date)
  } else {
    rep(0, nrow(base_panel))
  }
  z_fixed <- c(
    base_panel$y_transformed,
    base_panel$g_transformed - discrepancy_baseline_fixed
  )
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
    cfg_beta = cfg_beta,
    cfg_alpha = cfg_alpha,
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
    discrepancy_transition_strategy = discrepancy_transition_strategy,
    discrepancy_input_stream = discrepancy_input_stream,
    runtime_optimization = cfg$runtime_optimization %||% list(),
    discrepancy_baseline_fixed = discrepancy_baseline_fixed,
    covariate_timeline = app_panel_covariate_timeline(
      base_panel_full,
      required = isTRUE(app_qdesn_reservoir_uses_covariates(cfg_beta)) ||
        isTRUE(app_qdesn_reservoir_uses_covariates(cfg_alpha))
    ),
    two_block_design = two_block,
    glofas_future_quantile_path = glofas_future_quantile_path,
    future_discrepancy_convention = if (isTRUE(two_block) && identical(
      discrepancy_transition_strategy,
      "persistence_anchored_innovation"
    )) {
      "last_observed_discrepancy_plus_learned_innovation"
    } else if (isTRUE(two_block)) {
      "recursive_glofas_quantile_minus_latent_reference_path"
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
    fixed_pairing_certificate = app_latent_pairing_certificate(
      X_beta_stack = X_beta_stack,
      source = source,
      beta_index = seq_len(p_beta),
      alpha_index = p_beta + seq_len(p_alpha),
      feature_names = colnames(H_fixed),
      optimization_enabled = !identical(
        (cfg$runtime_optimization %||% list())$paired_fixed_stats,
        FALSE
      )
    ),
    reference_feature_cache = beta_cache$diagnostics,
    X_core_beta = feature_beta$X_core,
    X_core_alpha = feature_alpha$X_core,
    feature_info = feature_beta$feature_info,
    feature_info_beta = feature_beta$feature_info,
    feature_info_alpha = feature_alpha$feature_info,
    feature_meta = feature_beta$meta,
    feature_meta_beta = feature_beta$meta,
    feature_meta_alpha = feature_alpha$meta,
    block_config_beta = cfg_beta,
    block_config_alpha = cfg_alpha,
    discrepancy_input_stream = discrepancy_input_stream,
    block_config_hash_beta = app_qdesn_block_config_hash(cfg, "reference"),
    block_config_hash_alpha = app_qdesn_block_config_hash(cfg, if (isTRUE(two_block)) "discrepancy" else "reference"),
    readout_scale_info = feature_beta$readout_scale_info,
    readout_scale_info_alpha = feature_alpha$readout_scale_info,
    base_panel = base_panel,
    base_panel_full = base_panel_full,
    base_panel_disc_full = base_panel_disc_full,
    keep_idx = feature_beta$keep_idx,
    row_alignment = row_alignment,
    latent_data = latent_data,
    future_key = latent_data$future_key,
    y_future_init = app_latent_path_initial_future(latent_data, p0),
    y_future_oracle = latent_data$y_future_oracle,
    glofas_future_quantile_path = glofas_future_quantile_path,
    discrepancy_baseline_fixed = discrepancy_baseline_fixed,
    discrepancy_baseline_future = if (identical(
      discrepancy_transition_strategy,
      "persistence_anchored_innovation"
    )) {
      rep(utils::tail(as.numeric(base_panel_disc_full$y_transformed), 1L), nrow(latent_data$future_key))
    } else {
      rep(0, nrow(latent_data$future_key))
    },
    discrepancy_transition_strategy = discrepancy_transition_strategy,
    future_context = context,
    future_builder = app_make_latent_path_future_builder(context),
    beta_index = seq_len(p_beta),
    alpha_index = p_beta + seq_len(p_alpha),
    intercept_index = intercept_index,
    p0 = p0,
    feature_strategy = context$feature_strategy,
    horizon_scale = horizon_scale,
    design_version = if (isTRUE(two_block) && identical(discrepancy_input_stream, "reference")) {
      "latent_path_two_block_shared_reference_input_v0.1"
    } else if (isTRUE(two_block) && identical(
      discrepancy_transition_strategy,
      "persistence_anchored_innovation"
    )) {
      "latent_path_two_block_persistence_innovation_v0.1"
    } else if (isTRUE(two_block)) {
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

app_latent_path_restore_legacy_view <- function(x) {
  if (is.null(x$X_base) && !is.null(x$X_beta)) {
    x$X_base <- x$X_beta
  }
  if (is.null(x$feature_meta) && !is.null(x$feature_meta_beta)) {
    x$feature_meta <- x$feature_meta_beta
  }
  if (is.null(x$feature_info) && !is.null(x$feature_info_beta)) {
    x$feature_info <- x$feature_info_beta
  }
  if (!is.null(x$future_context)) {
    if (is.null(x$future_context$qfit) && !is.null(x$future_context$qfit_beta)) {
      x$future_context$qfit <- x$future_context$qfit_beta
    }
    if (is.null(x$future_context$feature_meta) &&
        !is.null(x$future_context$feature_meta_beta)) {
      x$future_context$feature_meta <- x$future_context$feature_meta_beta
    }
  }
  feature_rows <- as.integer(x$row_info_fixed$feature_row %||% integer())
  if (!length(feature_rows) || length(feature_rows) != length(x$source_fixed)) {
    stop("Cannot reconstruct latent-path stacks without fixed-row feature indices.", call. = FALSE)
  }
  if (is.null(x$X_beta_stack)) {
    x$X_beta_stack <- as.matrix(x$X_beta[feature_rows, , drop = FALSE])
  }
  if (is.null(x$X_alpha_stack)) {
    x$X_alpha_stack <- as.matrix(x$X_alpha[feature_rows, , drop = FALSE])
  }
  x
}

app_latent_path_drop_runtime_cache <- function(x, compact = TRUE) {
  if (isTRUE(compact)) {
    semantic_hash <- app_hash_latent_path_design(x)
    removed <- intersect(c("X_beta_stack", "X_alpha_stack"), names(x))
    x$X_beta_stack <- NULL
    x$X_alpha_stack <- NULL
    if (!is.null(x$X_base) && !is.null(x$X_beta) && identical(x$X_base, x$X_beta)) {
      x$X_base <- NULL
      removed <- c(removed, "X_base")
    }
    if (!is.null(x$feature_meta) && !is.null(x$feature_meta_beta) &&
        identical(x$feature_meta, x$feature_meta_beta)) {
      x$feature_meta <- NULL
      removed <- c(removed, "feature_meta")
    }
    if (!is.null(x$feature_info) && !is.null(x$feature_info_beta) &&
        identical(x$feature_info, x$feature_info_beta)) {
      x$feature_info <- NULL
      removed <- c(removed, "feature_info")
    }
    if (!is.null(x$future_context)) {
      if (!is.null(x$future_context$qfit) && !is.null(x$future_context$qfit_beta) &&
          identical(x$future_context$qfit, x$future_context$qfit_beta)) {
        x$future_context$qfit <- NULL
        removed <- c(removed, "future_context$qfit")
      }
      if (!is.null(x$future_context$feature_meta) &&
          !is.null(x$future_context$feature_meta_beta) &&
          identical(x$future_context$feature_meta, x$future_context$feature_meta_beta)) {
        x$future_context$feature_meta <- NULL
        removed <- c(removed, "future_context$feature_meta")
      }
      x$future_builder <- app_make_latent_path_future_builder(x$future_context)
    }
    x$serialization_contract <- list(
      schema_version = "glofas_latent_path_compact_v2",
      semantic_design_hash = semantic_hash,
      omitted_reconstructable_fields = removed,
      created_at = format(Sys.time(), tz = "UTC", usetz = TRUE)
    )
  }
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
  n_history_rows <- nrow(x$X_alpha %||% x$X_base)
  discrepancy_baseline_fixed <- as.numeric(x$discrepancy_baseline_fixed %||% rep(0, n_history_rows))
  if (length(discrepancy_baseline_fixed) != n_history_rows || any(!is.finite(discrepancy_baseline_fixed))) {
    stop("Latent-path fixed discrepancy baselines are invalid.", call. = FALSE)
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
  discrepancy_baseline_future <- as.numeric(probe$discrepancy_baseline_future %||% rep(0, nrow(x$future_key)))
  if (length(discrepancy_baseline_future) != nrow(x$future_key) || any(!is.finite(discrepancy_baseline_future))) {
    stop("Latent-path future discrepancy baselines are invalid.", call. = FALSE)
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
      discrepancy_baseline_fixed = x$discrepancy_baseline_fixed %||% rep(0, nrow(x$X_alpha %||% x$X_base)),
      discrepancy_baseline_future = probe$discrepancy_baseline_future %||% rep(0, nrow(x$future_key)),
      discrepancy_transition_strategy = x$discrepancy_transition_strategy %||% "recursive_level",
      discrepancy_input_stream = x$discrepancy_input_stream %||% "discrepancy",
      two_block_design = isTRUE(x$two_block_design %||% FALSE),
      block_config_hash_beta = x$block_config_hash_beta %||% NA_character_,
      block_config_hash_alpha = x$block_config_hash_alpha %||% NA_character_,
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
  pairing <- x$fixed_pairing_certificate %||% list()
  serialization <- x$serialization_contract %||% list()
  future_contract <- probe$compiled_future_contract %||% list()
  reference_cache <- x$reference_feature_cache %||% list(enabled = FALSE)
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
    n_base_features = ncol(x$X_base %||% x$X_beta),
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
    feature_contract_version = (
      x$feature_meta %||% x$feature_meta_beta %||% list()
    )$feature_contract$version %||% NA_character_,
    design_version = x$design_version %||% "latent_path_v0.1",
    two_block_design = isTRUE(x$two_block_design %||% FALSE),
    block_config_hash_beta = x$block_config_hash_beta %||% NA_character_,
    block_config_hash_alpha = x$block_config_hash_alpha %||% NA_character_,
    discrepancy_transition_strategy = x$discrepancy_transition_strategy %||% "recursive_level",
    discrepancy_input_stream = x$discrepancy_input_stream %||% "discrepancy",
    discrepancy_baseline_fixed_min = min(as.numeric(x$discrepancy_baseline_fixed %||% 0)),
    discrepancy_baseline_fixed_max = max(as.numeric(x$discrepancy_baseline_fixed %||% 0)),
    discrepancy_baseline_future = paste(
      format(as.numeric(probe$discrepancy_baseline_future %||% 0), digits = 16L),
      collapse = ";"
    ),
    future_discrepancy_convention = x$future_discrepancy_convention %||% NA_character_,
    fixed_pairing_certified = isTRUE(pairing$paired_beta_rows),
    fixed_pairing_certificate_hash = pairing$contract_hash %||% NA_character_,
    compiled_future_contract_enabled = isTRUE(future_contract$enabled),
    compiled_future_contract_persistence_static = isTRUE(future_contract$persistence_static),
    compiled_future_contract_hash = future_contract$contract_hash %||% NA_character_,
    serialization_schema_version = serialization$schema_version %||% "legacy_full_design",
    serialization_semantic_design_hash = serialization$semantic_design_hash %||% NA_character_,
    serialization_omitted_fields = paste(
      as.character(serialization$omitted_reconstructable_fields %||% character()),
      collapse = ";"
    ),
    reference_feature_cache_enabled = isTRUE(reference_cache$enabled),
    reference_feature_cache_hit = isTRUE(reference_cache$hit),
    reference_feature_cache_contract_hash = reference_cache$contract_hash %||% NA_character_,
    reference_feature_cache_payload_sha256 = reference_cache$payload_sha256 %||% NA_character_,
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
  base$vb_warm_start_contract_required <- app_as_bool(warm_start$contract_required %||% FALSE)
  base$vb_warm_start_compatibility_mode <- warm_start$compatibility_mode %||% NA_character_
  base$vb_warm_start_compatibility_class <- warm_start$compatibility_class %||% NA_character_
  base$vb_warm_start_compatibility_message <- warm_start$compatibility_message %||% NA_character_
  base$vb_warm_start_message <- warm_start$message %||% NA_character_
  checkpoint <- result$fit$vb_diagnostics$checkpoint %||% list(enabled = FALSE)
  base$vb_checkpoint_enabled <- app_as_bool(checkpoint$enabled %||% FALSE)
  base$vb_checkpoint_resumed <- app_as_bool(checkpoint$resumed %||% FALSE)
  base$vb_checkpoint_recovered_previous <- app_as_bool(
    checkpoint$recovered_previous %||% FALSE
  )
  base$vb_checkpoint_iteration_loaded <- as.integer(
    checkpoint$iteration_loaded %||% 0L
  )
  base$vb_checkpoint_writes <- as.integer(checkpoint$writes %||% 0L)
  base$vb_checkpoint_write_seconds <- as.numeric(checkpoint$write_seconds %||% 0)
  base$vb_checkpoint_contract_hash <- checkpoint$contract_hash %||% NA_character_
  base$vb_checkpoint_schema_version <- checkpoint$schema_version %||% NA_character_
  backend <- result$fit$vb_diagnostics$runtime_backend %||% data.frame()
  base$vb_numerical_backend <- if (nrow(backend)) backend$backend[[1L]] else NA_character_
  base$vb_numerical_backend_verified <- if (nrow(backend)) {
    isTRUE(backend$backend_verified[[1L]])
  } else {
    FALSE
  }
  base$vb_numerical_backend_sha256 <- if (nrow(backend)) {
    backend$external_library_sha256[[1L]]
  } else {
    NA_character_
  }
  base$vb_cpu_affinity <- if (nrow(backend)) backend$cpu_affinity[[1L]] else NA_character_
  base
}

app_latent_path_component_paths <- function(
  X_beta,
  X_alpha,
  beta,
  alpha,
  discrepancy_baseline = NULL
) {
  X_beta <- as.matrix(X_beta)
  X_alpha <- as.matrix(X_alpha)
  beta <- as.numeric(beta)
  alpha <- as.numeric(alpha)
  if (nrow(X_beta) != nrow(X_alpha)) {
    stop("Reference and discrepancy prediction designs must have the same row count.", call. = FALSE)
  }
  if (ncol(X_beta) != length(beta) || ncol(X_alpha) != length(alpha)) {
    stop("Prediction designs and coefficient blocks are not aligned.", call. = FALSE)
  }
  discrepancy_baseline <- as.numeric(
    discrepancy_baseline %||% rep(0, nrow(X_alpha))
  )
  if (length(discrepancy_baseline) != nrow(X_alpha) || any(!is.finite(discrepancy_baseline))) {
    stop("Prediction requires one finite discrepancy baseline per row.", call. = FALSE)
  }
  q_y <- as.numeric(X_beta %*% beta)
  d_g <- discrepancy_baseline + as.numeric(X_alpha %*% alpha)
  list(q_y = q_y, d_g = d_g, q_g = q_y + d_g)
}

app_latent_path_prediction_block_hash <- function(
  X,
  feature_info,
  future_key,
  block,
  block_config_hash = NA_character_
) {
  X <- as.matrix(X)
  if (nrow(feature_info) != ncol(X)) {
    stop("Prediction block hashing requires aligned features and metadata.", call. = FALSE)
  }
  key <- future_key[, intersect(c("target_date", "horizon"), names(future_key)), drop = FALSE]
  if ("target_date" %in% names(key)) key$target_date <- as.character(as.Date(key$target_date))
  app_latent_path_contract_hash(
    list(
      schema_version = "glofas_prediction_block_v1",
      block = as.character(block),
      block_config_hash = as.character(block_config_hash),
      future_key = key,
      feature_info = feature_info,
      X = X
    ),
    prefix = paste0("glofas_prediction_", block, "_")
  )
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
  if (isTRUE(use_linearization)) {
    summary_X_beta <- as.matrix(linearization$X_beta_future %||% linearization$X_future)
    summary_X_alpha <- as.matrix(linearization$X_alpha_future %||% linearization$X_future)
  } else {
    summary_future <- result$design$future_builder(as.numeric(result$fit$variational_state$y_future_mean))
    summary_X_beta <- as.matrix(summary_future$X_beta_future %||% summary_future$X_future)
    summary_X_alpha <- as.matrix(summary_future$X_alpha_future %||% summary_future$X_future)
  }
  beta_feature_info <- result$design$feature_info_beta %||% result$design$feature_info
  alpha_feature_info <- result$design$feature_info_alpha %||% result$design$feature_info
  beta_feature_counts <- app_readout_feature_counts(beta_feature_info)
  alpha_feature_counts <- app_readout_feature_counts(alpha_feature_info)
  beta_prediction_design_hash <- app_latent_path_prediction_block_hash(
    summary_X_beta,
    beta_feature_info,
    result$design$future_key,
    "beta",
    result$design$block_config_hash_beta %||% NA_character_
  )
  alpha_prediction_design_hash <- app_latent_path_prediction_block_hash(
    summary_X_alpha,
    alpha_feature_info,
    result$design$future_key,
    "alpha",
    result$design$block_config_hash_alpha %||% NA_character_
  )
  discrepancy_baseline_future <- as.numeric(
    result$design$discrepancy_baseline_future %||% rep(0, H)
  )
  if (length(discrepancy_baseline_future) != H || any(!is.finite(discrepancy_baseline_future))) {
    stop("Latent-path prediction requires one finite discrepancy baseline per future date.", call. = FALSE)
  }
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
    components <- app_latent_path_component_paths(
      X_beta,
      X_alpha,
      beta,
      alpha,
      discrepancy_baseline_future
    )
    q_y <- components$q_y
    d_g <- components$d_g
    q_g <- components$q_g
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
        discrepancy_transition_strategy = result$design$discrepancy_transition_strategy %||% "recursive_level",
        discrepancy_baseline = discrepancy_baseline_future[[h]],
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
	      discrepancy_transition_strategy = result$design$discrepancy_transition_strategy %||% "recursive_level",
	      prediction_state_strategy = if (isTRUE(use_linearization)) "first_order_delta" else "exact_rebuild",
	      p0 = result$design$p0
	    ),
	    prediction_design_summary = data.frame(
	      fit_id = result$fit_id,
	      model_id = result$model_id,
	      quantile_level = result$quantile_level,
	      n_prediction_rows = H,
	      n_prediction_features = ncol(result$design$X_base %||% result$design$X_beta),
	      n_beta_prediction_features = ncol(summary_X_beta),
	      n_alpha_prediction_features = ncol(summary_X_alpha),
	      n_beta_reservoir_features = beta_feature_counts$n_reservoir_features,
	      n_alpha_reservoir_features = alpha_feature_counts$n_reservoir_features,
	      prediction_design_hash = prediction_design_hash,
	      beta_prediction_design_hash = beta_prediction_design_hash,
	      alpha_prediction_design_hash = alpha_prediction_design_hash,
	      prediction_state_strategy = if (isTRUE(use_linearization)) "first_order_delta" else "exact_rebuild",
	      design_version = result$design$design_version,
	      feature_strategy = result$design$feature_strategy %||% contract$discrepancy_feature_strategy,
	      discrepancy_transition_strategy = result$design$discrepancy_transition_strategy %||% "recursive_level",
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
  fit$warm_start_contract <- app_latent_path_warm_start_contract(
    design,
    design_hash = design_summary$design_hash[[1L]]
  )
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
