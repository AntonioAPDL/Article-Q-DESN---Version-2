# Deterministic design construction for the GloFAS discrepancy-calibration model.

app_discrepancy_required_panel_columns <- function() {
  c(
    "origin_date", "target_date", "horizon", "member", "is_retrospective",
    "is_ensemble", "y_transformed", "g_transformed", "split", "cutoff_id"
  )
}

app_discrepancy_cutoff_mask <- function(panel, cutoff_row = NULL) {
  mask <- rep(TRUE, nrow(panel))
  if (is.null(cutoff_row) || !nrow(cutoff_row)) return(mask)

  train_start <- as.Date(cutoff_row$train_start[[1L]])
  train_end <- as.Date(cutoff_row$train_end[[1L]])
  if (is.na(train_start) || is.na(train_end)) {
    stop("cutoff_row must contain valid train_start and train_end dates.", call. = FALSE)
  }
  panel$target_date >= train_start & panel$target_date <= train_end
}

app_order_retrospective_panel <- function(panel) {
  panel[order(panel$target_date, panel$origin_date, panel$horizon), , drop = FALSE]
}

app_feature_matrix_from_panel <- function(
  panel,
  cfg,
  model_row = NULL,
  X_base = NULL,
  drop = NULL,
  feature_strategy = "origin_state_pilot",
  horizon_scale = NULL,
  seed_override = NULL
) {
  if (!is.null(X_base)) {
    X_base <- as.matrix(X_base)
    storage.mode(X_base) <- "double"
    if (nrow(X_base) != nrow(panel)) {
      stop(
        sprintf(
          "Supplied X_base has %d rows but the selected retrospective panel has %d rows.",
          nrow(X_base),
          nrow(panel)
        ),
        call. = FALSE
      )
    }
    return(list(
      X = X_base,
      X_core = X_base,
      X_covariates = NULL,
      panel = panel,
      keep_idx = seq_len(nrow(panel)),
      feature_info = NULL,
      readout_scale_info = NULL,
      meta = list(source = "supplied", feature_contract = NULL)
    ))
  }

  seed <- if (!is.null(seed_override)) {
    suppressWarnings(as.integer(seed_override))
  } else if (!is.null(model_row) && "reservoir_seed" %in% names(model_row)) {
    suppressWarnings(as.integer(model_row$reservoir_seed[[1L]]))
  } else {
    NA_integer_
  }
  if (!is.finite(seed)) seed <- as.integer(cfg$reservoir$seed %||% 20260511L)

  design <- app_build_qdesn_design(
    y = panel$y_transformed,
    cfg = cfg,
    seed = seed,
    drop = drop
  )
  keep_idx <- as.integer(design$keep_idx)
  if (any(!is.finite(keep_idx)) || any(keep_idx < 1L) || any(keep_idx > nrow(panel))) {
    stop("Q-DESN design returned invalid keep_idx values.", call. = FALSE)
  }
  X <- as.matrix(design$X)
  storage.mode(X) <- "double"
  if (nrow(X) != length(keep_idx)) {
    stop("Q-DESN design matrix row count does not match keep_idx length.", call. = FALSE)
  }

  panel_kept <- panel[keep_idx, , drop = FALSE]
  panel_kept <- app_copy_covariate_attrs(panel_kept, panel)
  assembled <- app_build_readout_feature_matrix(
    reservoir_X = X,
    panel = panel,
    cfg = cfg,
    output_anchor_dates = panel_kept$target_date,
    covariate_target_dates = panel_kept$target_date,
    horizon = panel_kept$horizon,
    feature_strategy = feature_strategy,
    horizon_scale = horizon_scale,
    fit_scale = TRUE
  )

  meta <- design$meta
  meta$covariates_enabled <- app_covariates_enabled(cfg)
  meta$feature_contract <- assembled$contract
  meta$feature_info <- assembled$feature_info
  meta$readout_scale_info <- assembled$readout_scale_info
  meta$covariate_lags <- if (app_covariates_enabled(cfg)) app_covariate_readout_lags_by_variable(cfg) else list()
  cov_cols <- assembled$feature_info$column_name[assembled$feature_info$block == "direct_covariate_lag"]
  meta$covariate_columns <- cov_cols

  list(
    X = assembled$X,
    X_core = X,
    X_covariates = if (length(cov_cols)) assembled$X[, cov_cols, drop = FALSE] else NULL,
    panel = panel_kept,
    keep_idx = keep_idx,
    feature_info = assembled$feature_info,
    readout_scale_info = assembled$readout_scale_info,
    meta = meta
  )
}

app_discrepancy_feature_contract_version <- function(cfg) {
  as.character((cfg$feature_contract %||% cfg$features %||% list())$version %||% "0.1")
}

app_discrepancy_uses_two_blocks <- function(cfg) {
  if (exists("app_qdesn_two_block_design", mode = "function")) {
    return(app_qdesn_two_block_design(cfg))
  }
  fc <- cfg$feature_contract %||% cfg$features %||% list()
  version <- app_discrepancy_feature_contract_version(cfg)
  identical(version, "0.3") || isTRUE(fc$two_block_design %||% FALSE)
}

app_discrepancy_block_seed <- function(model_row, cfg, block = c("reference", "discrepancy")) {
  block <- match.arg(block)
  if (exists("app_qdesn_block_seed", mode = "function")) {
    return(app_qdesn_block_seed(model_row, cfg, block))
  }
  base_seed <- if (!is.null(model_row) && "reservoir_seed" %in% names(model_row)) {
    suppressWarnings(as.integer(model_row$reservoir_seed[[1L]]))
  } else {
    suppressWarnings(as.integer(cfg$reservoir$seed %||% 20260511L))
  }
  if (!is.finite(base_seed)) base_seed <- as.integer(cfg$reservoir$seed %||% 20260511L)
  if (identical(block, "reference")) return(base_seed)

  fc <- cfg$feature_contract %||% cfg$features %||% list()
  blocks <- fc$blocks %||% list()
  disc <- blocks$discrepancy %||% list()
  offset <- suppressWarnings(as.integer(disc$reservoir_seed_offset %||% fc$discrepancy_reservoir_seed_offset %||% 1009L))
  if (!is.finite(offset)) offset <- 1009L
  base_seed + offset
}

app_discrepancy_horizon_scale <- function(panel, cfg, horizon_scale = NULL) {
  value <- suppressWarnings(as.numeric(horizon_scale %||% cfg$prediction$horizon_feature_scale %||% NA_real_))
  if (is.finite(value) && value > 0) return(value)

  value <- suppressWarnings(as.numeric(cfg$forecast_protocol$default_horizon_max %||% NA_real_))
  if (is.finite(value) && value > 0) return(value)

  h <- suppressWarnings(as.numeric(panel$horizon))
  h <- h[is.finite(h) & h > 0]
  if (length(h)) return(max(h))
  1
}

app_add_discrepancy_horizon_feature <- function(X, horizon, feature_strategy, horizon_scale) {
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  feature_strategy <- as.character(feature_strategy %||% "origin_state_pilot")
  if (!identical(feature_strategy, "horizon_indexed_origin_state")) return(X)

  horizon <- suppressWarnings(as.numeric(horizon))
  if (length(horizon) != nrow(X) || any(!is.finite(horizon))) {
    stop("Horizon-indexed discrepancy features require one finite horizon per design row.", call. = FALSE)
  }
  horizon_scale <- suppressWarnings(as.numeric(horizon_scale))
  if (!is.finite(horizon_scale) || horizon_scale <= 0) {
    stop("Horizon-indexed discrepancy features require a positive horizon scale.", call. = FALSE)
  }
  out <- cbind(X, horizon_scaled = horizon / horizon_scale)
  storage.mode(out) <- "double"
  out
}

app_discrepancy_origin_indices <- function(base_panel, origin_dates) {
  base_dates <- as.Date(base_panel$target_date)
  split_idx <- split(seq_along(base_dates), as.character(base_dates))
  idx <- vapply(as.character(as.Date(origin_dates)), function(origin) {
    hit <- split_idx[[origin]]
    if (!length(hit)) return(NA_integer_)
    as.integer(hit[[1L]])
  }, integer(1L))
  idx
}

app_make_discrepancy_feature_rows <- function(
  base_panel,
  X_core,
  origin_dates,
  target_dates,
  horizons,
  cfg,
  feature_strategy,
  horizon_scale,
  feature_meta = NULL
) {
  origin_idx <- app_discrepancy_origin_indices(base_panel, origin_dates)
  keep <- is.finite(origin_idx)
  if (!any(keep)) {
    return(list(X = matrix(0, nrow = 0L, ncol = 0L), origin_idx = origin_idx, keep = keep))
  }

  X0 <- X_core[origin_idx[keep], , drop = FALSE]
  if (!is.null(feature_meta) && !is.null(feature_meta$feature_contract)) {
    assembled <- app_build_readout_feature_matrix(
      reservoir_X = X0,
      panel = base_panel,
      cfg = cfg,
      output_anchor_dates = as.Date(origin_dates)[keep],
      covariate_target_dates = as.Date(target_dates)[keep],
      horizon = as.integer(horizons)[keep],
      feature_strategy = feature_strategy,
      horizon_scale = horizon_scale,
      feature_meta = feature_meta,
      fit_scale = FALSE
    )
    return(list(X = assembled$X, origin_idx = origin_idx, keep = keep, feature_info = assembled$feature_info))
  }

  tmp_panel <- base_panel[seq_len(nrow(X0)), , drop = FALSE]
  tmp_panel$origin_date <- as.Date(origin_dates)[keep]
  tmp_panel$target_date <- as.Date(target_dates)[keep]
  tmp_panel$horizon <- as.integer(horizons)[keep]
  tmp_panel <- app_copy_covariate_attrs(tmp_panel, base_panel)
  appended <- app_append_covariate_lags(
    X = X0,
    target_dates = tmp_panel$target_date,
    panel = tmp_panel,
    cfg = cfg
  )
  X <- app_add_discrepancy_horizon_feature(
    appended$X,
    horizon = tmp_panel$horizon,
    feature_strategy = feature_strategy,
    horizon_scale = horizon_scale
  )
  list(X = X, origin_idx = origin_idx, keep = keep)
}

app_constant_one_columns <- function(X, tol = 1.0e-10) {
  if (!ncol(X)) return(integer())
  which(vapply(seq_len(ncol(X)), function(j) all(abs(X[, j] - 1) <= tol), logical(1L)))
}

app_make_augmented_discrepancy_design <- function(X_beta, source, X_alpha = NULL) {
  X_beta <- as.matrix(X_beta)
  storage.mode(X_beta) <- "double"
  if (is.null(X_alpha)) X_alpha <- X_beta
  X_alpha <- as.matrix(X_alpha)
  storage.mode(X_alpha) <- "double"
  if (nrow(X_beta) != nrow(X_alpha)) {
    stop("Reference and discrepancy feature blocks must have the same number of rows.", call. = FALSE)
  }
  source <- as.character(source)
  p_beta <- ncol(X_beta)
  p_alpha <- ncol(X_alpha)
  H <- matrix(0, nrow = nrow(X_beta), ncol = p_beta + p_alpha)
  H[, seq_len(p_beta)] <- X_beta
  g_idx <- source == "G"
  if (any(g_idx)) H[g_idx, p_beta + seq_len(p_alpha)] <- X_alpha[g_idx, , drop = FALSE]
  beta_names <- colnames(X_beta)
  alpha_names <- colnames(X_alpha)
  if (is.null(beta_names) || any(!nzchar(beta_names))) beta_names <- paste0("feature_", seq_len(p_beta))
  if (is.null(alpha_names) || any(!nzchar(alpha_names))) alpha_names <- paste0("feature_", seq_len(p_alpha))
  colnames(H) <- c(paste0("beta__", beta_names), paste0("alpha__", alpha_names))
  H
}

app_make_glofas_discrepancy_data <- function(
  panel,
  cfg,
  cutoff_row = NULL,
  model_row = NULL,
  X_base = NULL,
  include_ensemble_training = FALSE,
  feature_strategy = "origin_state_pilot",
  horizon_scale = NULL,
  drop = NULL
) {
  app_check_required_columns(panel, app_discrepancy_required_panel_columns(), "application panel")
  feature_strategy <- as.character(feature_strategy %||% "origin_state_pilot")
  if (!feature_strategy %in% c("origin_state_pilot", "horizon_indexed_origin_state")) {
    stop(
      sprintf("Unsupported discrepancy feature strategy: %s", feature_strategy),
      call. = FALSE
    )
  }
  if (isTRUE(include_ensemble_training) && !identical(feature_strategy, "horizon_indexed_origin_state")) {
    stop(
      "Ensemble training rows require feature_strategy = 'horizon_indexed_origin_state'.",
      call. = FALSE
    )
  }

  panel$origin_date <- as.Date(panel$origin_date)
  panel$target_date <- as.Date(panel$target_date)
  panel$horizon <- as.integer(panel$horizon)

  two_block <- app_discrepancy_uses_two_blocks(cfg)
  if (isTRUE(two_block) && isTRUE(include_ensemble_training)) {
    stop(
      paste(
        "The v0.3 two-block design does not include issued forecast ensemble",
        "members as likelihood rows. Use the issued-ensemble prediction",
        "contract instead."
      ),
      call. = FALSE
    )
  }

  base_mask <- app_discrepancy_cutoff_mask(panel, cutoff_row) &
    panel$is_retrospective &
    is.finite(panel$y_transformed)
  if (isTRUE(two_block)) {
    base_mask <- base_mask & is.finite(panel$g_transformed)
  }
  base_panel <- app_order_retrospective_panel(panel[base_mask, , drop = FALSE])
  base_panel <- app_copy_covariate_attrs(base_panel, panel)
  if (!nrow(base_panel)) {
    stop("No retrospective reference rows are available for discrepancy-design construction.", call. = FALSE)
  }
  base_panel_full <- base_panel

  horizon_scale <- app_discrepancy_horizon_scale(panel, cfg, horizon_scale = horizon_scale)
  feature <- app_feature_matrix_from_panel(
    panel = base_panel,
    cfg = cfg,
    model_row = model_row,
    X_base = X_base,
    drop = drop,
    feature_strategy = feature_strategy,
    horizon_scale = horizon_scale,
    seed_override = app_discrepancy_block_seed(model_row, cfg, "reference")
  )
  base_panel <- feature$panel
  X_core_beta <- feature$X_core %||% feature$X
  X_beta <- feature$X
  if (identical(feature$meta$source %||% "", "supplied")) {
    X_beta <- app_add_discrepancy_horizon_feature(
      X_beta,
      horizon = base_panel$horizon,
      feature_strategy = feature_strategy,
      horizon_scale = horizon_scale
    )
  }

  if (isTRUE(two_block)) {
    discrepancy_panel <- base_panel_full
    discrepancy_panel$y_transformed <- as.numeric(base_panel_full$g_transformed) - as.numeric(base_panel_full$y_transformed)
    if (any(!is.finite(discrepancy_panel$y_transformed))) {
      stop("The v0.3 discrepancy reservoir requires finite retrospective GloFAS - USGS discrepancies.", call. = FALSE)
    }
    discrepancy_panel <- app_copy_covariate_attrs(discrepancy_panel, base_panel)
    alpha_feature <- app_feature_matrix_from_panel(
      panel = discrepancy_panel,
      cfg = cfg,
      model_row = model_row,
      X_base = NULL,
      drop = drop,
      feature_strategy = feature_strategy,
      horizon_scale = horizon_scale,
      seed_override = app_discrepancy_block_seed(model_row, cfg, "discrepancy")
    )
    if (!identical(as.integer(alpha_feature$keep_idx), as.integer(feature$keep_idx))) {
      stop("Reference and discrepancy reservoir designs must retain the same rows after washout.", call. = FALSE)
    }
    X_alpha <- alpha_feature$X
    X_core_alpha <- alpha_feature$X_core %||% alpha_feature$X
    if (nrow(X_alpha) != nrow(X_beta)) {
      stop("Reference and discrepancy feature blocks have different row counts.", call. = FALSE)
    }
    feature_info_alpha <- alpha_feature$feature_info
    feature_meta_alpha <- alpha_feature$meta
    readout_scale_info_alpha <- alpha_feature$readout_scale_info
  } else {
    X_alpha <- X_beta
    X_core_alpha <- X_core_beta
    feature_info_alpha <- feature$feature_info
    feature_meta_alpha <- feature$meta
    readout_scale_info_alpha <- feature$readout_scale_info
  }

  y_idx <- is.finite(base_panel$y_transformed)
  g_idx <- is.finite(base_panel$g_transformed)
  if (!any(y_idx)) stop("No finite reference rows are available after feature construction.", call. = FALSE)
  if (!any(g_idx)) stop("No finite retrospective GloFAS rows are available after feature construction.", call. = FALSE)

  y_rows <- base_panel[y_idx, , drop = FALSE]
  g_rows <- base_panel[g_idx, , drop = FALSE]
  X_y_beta <- X_beta[y_idx, , drop = FALSE]
  X_y_alpha <- X_alpha[y_idx, , drop = FALSE]
  X_g_beta <- X_beta[g_idx, , drop = FALSE]
  X_g_alpha <- X_alpha[g_idx, , drop = FALSE]

  z_parts <- list(y_rows$y_transformed, g_rows$g_transformed)
  source_parts <- list(rep("Y", nrow(y_rows)), rep("G", nrow(g_rows)))
  X_beta_parts <- list(X_y_beta, X_g_beta)
  X_alpha_parts <- list(X_y_alpha, X_g_alpha)
  row_info_parts <- list(
    data.frame(
      source = "Y",
      feature_row = which(y_idx),
      origin_date = y_rows$origin_date,
      target_date = y_rows$target_date,
      horizon = y_rows$horizon,
      member = y_rows$member,
      cutoff_id = y_rows$cutoff_id,
      is_retrospective = y_rows$is_retrospective,
      is_ensemble = y_rows$is_ensemble,
      z = y_rows$y_transformed,
      stringsAsFactors = FALSE
    ),
    data.frame(
      source = "G",
      feature_row = which(g_idx),
      origin_date = g_rows$origin_date,
      target_date = g_rows$target_date,
      horizon = g_rows$horizon,
      member = g_rows$member,
      cutoff_id = g_rows$cutoff_id,
      is_retrospective = g_rows$is_retrospective,
      is_ensemble = g_rows$is_ensemble,
      z = g_rows$g_transformed,
      stringsAsFactors = FALSE
    )
  )

  if (isTRUE(include_ensemble_training)) {
    ensemble_mask <- panel$is_ensemble & is.finite(panel$g_transformed)
    ensemble_panel <- panel[ensemble_mask, , drop = FALSE]
    if (!nrow(ensemble_panel)) {
      stop("No finite issued GloFAS ensemble rows are available for posterior-draw discrepancy fitting.", call. = FALSE)
    }
    ensemble_feature <- app_make_discrepancy_feature_rows(
      base_panel = base_panel,
      X_core = X_core_beta,
      origin_dates = ensemble_panel$origin_date,
      target_dates = ensemble_panel$target_date,
      horizons = ensemble_panel$horizon,
      cfg = cfg,
      feature_strategy = feature_strategy,
      horizon_scale = horizon_scale,
      feature_meta = feature$meta
    )
    origin_idx <- ensemble_feature$origin_idx
    keep_ensemble <- ensemble_feature$keep
    if (!any(keep_ensemble)) {
      stop(
        paste(
          "No issued GloFAS ensemble rows have forecast origins represented",
          "in the fixed reservoir design after washout."
        ),
        call. = FALSE
      )
    }
    ensemble_panel <- ensemble_panel[keep_ensemble, , drop = FALSE]
    origin_idx <- origin_idx[keep_ensemble]
    X_ensemble <- ensemble_feature$X
    z_parts[[length(z_parts) + 1L]] <- ensemble_panel$g_transformed
    source_parts[[length(source_parts) + 1L]] <- rep("G", nrow(ensemble_panel))
    X_beta_parts[[length(X_beta_parts) + 1L]] <- X_ensemble
    X_alpha_parts[[length(X_alpha_parts) + 1L]] <- X_ensemble
    row_info_parts[[length(row_info_parts) + 1L]] <- data.frame(
      source = "G",
      feature_row = origin_idx,
      origin_date = ensemble_panel$origin_date,
      target_date = ensemble_panel$target_date,
      horizon = ensemble_panel$horizon,
      member = ensemble_panel$member,
      cutoff_id = ensemble_panel$cutoff_id,
      is_retrospective = ensemble_panel$is_retrospective,
      is_ensemble = ensemble_panel$is_ensemble,
      z = ensemble_panel$g_transformed,
      stringsAsFactors = FALSE
    )
  }

  z <- unlist(z_parts, use.names = FALSE)
  source <- factor(unlist(source_parts, use.names = FALSE), levels = c("Y", "G"))
  X_beta_stack <- do.call(rbind, X_beta_parts)
  X_alpha_stack <- do.call(rbind, X_alpha_parts)
  H <- app_make_augmented_discrepancy_design(X_beta_stack, source, X_alpha_stack)
  row_info <- do.call(rbind, row_info_parts)

  p_beta <- ncol(X_beta)
  p_alpha <- ncol(X_alpha)
  beta_intercept <- app_constant_one_columns(X_beta)
  alpha_intercept <- app_constant_one_columns(X_alpha)
  intercept_index <- sort(unique(c(beta_intercept, p_beta + alpha_intercept)))
  p0 <- if (!is.null(model_row) && "quantile_level" %in% names(model_row)) {
    suppressWarnings(as.numeric(model_row$quantile_level[[1L]]))
  } else {
    NA_real_
  }
  cfg_seed <- app_config_reservoir_seed(cfg)
  model_seed <- suppressWarnings(as.integer(app_model_row_value(model_row %||% data.frame(), "reservoir_seed", NA_integer_)))
  effective_seed <- app_model_row_reservoir_seed(model_row %||% data.frame(), cfg)
  reference_seed <- app_qdesn_block_seed(model_row %||% data.frame(), cfg, "reference")
  discrepancy_seed <- app_qdesn_block_seed(model_row %||% data.frame(), cfg, "discrepancy")

  out <- list(
    z = as.numeric(z),
    H = H,
    source = source,
    X_base = X_beta,
    X_beta = X_beta,
    X_alpha = X_alpha,
    X_beta_stack = X_beta_stack,
    X_alpha_stack = X_alpha_stack,
    X_core = X_core_beta,
    X_core_beta = X_core_beta,
    X_core_alpha = X_core_alpha,
    X_covariates = feature$X_covariates,
    X_covariates_alpha = if (isTRUE(two_block)) alpha_feature$X_covariates else feature$X_covariates,
    feature_info = feature$feature_info,
    feature_info_beta = feature$feature_info,
    feature_info_alpha = feature_info_alpha,
    readout_scale_info = feature$readout_scale_info,
    readout_scale_info_alpha = readout_scale_info_alpha,
    covariate_timeline = app_panel_covariate_timeline(base_panel, required = FALSE),
    base_panel = base_panel,
    row_info = row_info,
    keep_idx = feature$keep_idx,
    feature_meta = feature$meta,
    feature_meta_beta = feature$meta,
    feature_meta_alpha = feature_meta_alpha,
    design_version = if (isTRUE(two_block)) "0.3" else "0.2",
    two_block_design = isTRUE(two_block),
    feature_strategy = feature_strategy,
    horizon_scale = horizon_scale,
    cfg_reservoir_seed = cfg_seed,
    model_grid_reservoir_seed = model_seed,
    effective_reservoir_seed = effective_seed,
    reference_reservoir_seed = reference_seed,
    discrepancy_reservoir_seed = discrepancy_seed,
    discrepancy_reservoir_seed_offset = discrepancy_seed - reference_seed,
    p0 = p0,
    beta_index = seq_len(p_beta),
    alpha_index = p_beta + seq_len(p_alpha),
    intercept_index = intercept_index,
    include_ensemble_training = isTRUE(include_ensemble_training),
    fit_id = if (!is.null(model_row) && "fit_id" %in% names(model_row)) model_row$fit_id[[1L]] else NA_character_,
    model_id = if (!is.null(model_row) && "model_id" %in% names(model_row)) model_row$model_id[[1L]] else NA_character_
  )
  class(out) <- "glofas_discrepancy_design"
  app_validate_glofas_discrepancy_data(out)
  out
}

app_build_glofas_qdesn_design <- function(panel, cfg, cutoff_row = NULL, model_row = NULL, X_base = NULL, drop = NULL) {
  app_make_glofas_discrepancy_data(
    panel = panel,
    cfg = cfg,
    cutoff_row = cutoff_row,
    model_row = model_row,
    X_base = X_base,
    drop = drop
  )
}

app_make_glofas_prediction_design <- function(design, panel, cfg, model_row = NULL, contract = NULL) {
  app_validate_glofas_discrepancy_data(design)
  contract <- contract %||% app_prediction_contract(cfg, model_family = "qdesn_glofas_discrepancy")
  if (!identical(contract$prediction_unit, "posterior_draw")) {
    stop("Posterior prediction design requires prediction_unit = 'posterior_draw'.", call. = FALSE)
  }
  if (!identical(contract$discrepancy_feature_strategy, "horizon_indexed_origin_state")) {
    stop(
      "Posterior prediction design requires discrepancy_feature_strategy = 'horizon_indexed_origin_state'.",
      call. = FALSE
    )
  }
  if (!identical(design$feature_strategy %||% "origin_state_pilot", "horizon_indexed_origin_state")) {
    stop(
      "The fitted discrepancy design was not built with horizon-indexed origin-state features.",
      call. = FALSE
    )
  }

  app_check_required_columns(panel, app_discrepancy_required_panel_columns(), "application panel")
  panel$origin_date <- as.Date(panel$origin_date)
  panel$target_date <- as.Date(panel$target_date)
  panel$horizon <- as.integer(panel$horizon)

  ens <- panel[panel$is_ensemble & is.finite(panel$g_transformed), , drop = FALSE]
  if (!nrow(ens)) {
    stop("No finite issued GloFAS ensemble rows are available for posterior-draw prediction.", call. = FALSE)
  }
  keys <- unique(ens[, c("origin_date", "target_date", "horizon"), drop = FALSE])
  keys <- keys[order(keys$origin_date, keys$target_date, keys$horizon), , drop = FALSE]
  base_panel <- app_copy_covariate_attrs(design$base_panel, panel)
  if (!is.null(design$covariate_timeline)) {
    attr(base_panel, "model_covariate_timeline") <- design$covariate_timeline
  }
  pred_feature_beta <- app_make_discrepancy_feature_rows(
    base_panel = base_panel,
    X_core = design$X_core_beta %||% design$X_core,
    origin_dates = keys$origin_date,
    target_dates = keys$target_date,
    horizons = keys$horizon,
    cfg = cfg,
    feature_strategy = "horizon_indexed_origin_state",
    horizon_scale = design$horizon_scale %||% app_discrepancy_horizon_scale(panel, cfg),
    feature_meta = design$feature_meta_beta %||% design$feature_meta
  )
  pred_feature_alpha <- app_make_discrepancy_feature_rows(
    base_panel = base_panel,
    X_core = design$X_core_alpha %||% design$X_core,
    origin_dates = keys$origin_date,
    target_dates = keys$target_date,
    horizons = keys$horizon,
    cfg = cfg,
    feature_strategy = "horizon_indexed_origin_state",
    horizon_scale = design$horizon_scale %||% app_discrepancy_horizon_scale(panel, cfg),
    feature_meta = design$feature_meta_alpha %||% design$feature_meta
  )
  if (!identical(as.logical(pred_feature_beta$keep), as.logical(pred_feature_alpha$keep))) {
    stop("Reference and discrepancy prediction feature blocks retained different forecast rows.", call. = FALSE)
  }
  origin_idx <- pred_feature_beta$origin_idx
  keep <- pred_feature_beta$keep
  if (!any(keep)) {
    stop(
      paste(
        "No issued GloFAS forecast origins are represented in the fitted",
        "reservoir design after washout."
      ),
      call. = FALSE
    )
  }
  keys <- keys[keep, , drop = FALSE]
  origin_idx <- origin_idx[keep]

  X_beta_pred <- pred_feature_beta$X
  X_alpha_pred <- pred_feature_alpha$X
  H_g <- app_make_augmented_discrepancy_design(X_beta_pred, rep("G", nrow(X_beta_pred)), X_alpha_pred)

  p0 <- if (!is.null(model_row) && "quantile_level" %in% names(model_row)) {
    suppressWarnings(as.numeric(model_row$quantile_level[[1L]]))
  } else {
    suppressWarnings(as.numeric(design$p0 %||% NA_real_))
  }
  raw_q <- numeric(nrow(keys))
  y_ref <- numeric(nrow(keys))
  for (i in seq_len(nrow(keys))) {
    idx <- ens$origin_date == keys$origin_date[[i]] &
      ens$target_date == keys$target_date[[i]] &
      ens$horizon == keys$horizon[[i]]
    block <- ens[idx, , drop = FALSE]
    raw_q[[i]] <- app_ensemble_quantile(block, p0)
    y_val <- block$y_transformed[is.finite(block$y_transformed)]
    y_ref[[i]] <- if (length(y_val)) y_val[[1L]] else NA_real_
  }

  row_info <- data.frame(
    prediction_row = seq_len(nrow(keys)),
    origin_date = keys$origin_date,
    target_date = keys$target_date,
    horizon = keys$horizon,
    feature_row = origin_idx,
    discrepancy_feature_date = as.Date(design$base_panel$target_date[origin_idx]),
    raw_glofas_quantile = raw_q,
    y_reference = y_ref,
    stringsAsFactors = FALSE
  )

  out <- list(
    X_pred = X_beta_pred,
    X_beta_pred = X_beta_pred,
    X_alpha_pred = X_alpha_pred,
    H_g = H_g,
    row_info = row_info,
    feature_info = pred_feature_beta$feature_info %||% design$feature_info,
    feature_info_beta = pred_feature_beta$feature_info %||% design$feature_info_beta %||% design$feature_info,
    feature_info_alpha = pred_feature_alpha$feature_info %||% design$feature_info_alpha %||% design$feature_info,
    feature_meta = design$feature_meta_beta %||% design$feature_meta,
    feature_meta_beta = design$feature_meta_beta %||% design$feature_meta,
    feature_meta_alpha = design$feature_meta_alpha %||% design$feature_meta,
    design_version = app_discrepancy_design_version(design),
    two_block_design = isTRUE(design$two_block_design %||% FALSE),
    feature_strategy = "horizon_indexed_origin_state",
    horizon_scale = design$horizon_scale,
    p0 = p0,
    fit_id = design$fit_id %||% NA_character_,
    model_id = design$model_id %||% NA_character_
  )
  class(out) <- "glofas_discrepancy_prediction_design"
  app_validate_glofas_prediction_design(out)
  out
}

app_validate_glofas_prediction_design <- function(x) {
  required <- c("X_pred", "H_g", "row_info", "feature_strategy", "p0")
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(sprintf("Prediction design is missing required objects: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  X_beta_pred <- app_discrepancy_prediction_beta_matrix(x)
  X_alpha_pred <- app_discrepancy_prediction_alpha_matrix(x)
  if (!is.matrix(X_beta_pred) || any(!is.finite(X_beta_pred))) {
    stop("Prediction design reference feature block must be a finite numeric matrix.", call. = FALSE)
  }
  if (!is.matrix(X_alpha_pred) || any(!is.finite(X_alpha_pred))) {
    stop("Prediction design discrepancy feature block must be a finite numeric matrix.", call. = FALSE)
  }
  if (nrow(X_beta_pred) != nrow(X_alpha_pred)) {
    stop("Prediction design feature blocks must have the same row count.", call. = FALSE)
  }
  if (!is.matrix(x$H_g) || nrow(x$H_g) != nrow(X_beta_pred) ||
      ncol(x$H_g) != ncol(X_beta_pred) + ncol(X_alpha_pred)) {
    stop("Prediction design H_g is incompatible with reference and discrepancy feature blocks.", call. = FALSE)
  }
  if (!nrow(x$row_info) || nrow(x$row_info) != nrow(X_beta_pred)) {
    stop("Prediction design row_info must have one row per prediction row.", call. = FALSE)
  }
  if (!identical(as.character(x$feature_strategy), "horizon_indexed_origin_state")) {
    stop("Prediction design must use horizon_indexed_origin_state.", call. = FALSE)
  }
  if (any(is.na(as.Date(x$row_info$origin_date))) || any(is.na(as.Date(x$row_info$target_date)))) {
    stop("Prediction design has missing origin or target dates.", call. = FALSE)
  }
  if (!is.null(x$feature_info_beta %||% x$feature_info)) {
    app_validate_readout_feature_design(
      X_beta_pred,
      x$feature_info_beta %||% x$feature_info,
      contract = (x$feature_meta_beta %||% x$feature_meta %||% list())$feature_contract,
      check_reservoir_bias = FALSE
    )
  }
  if (!is.null(x$feature_info_alpha %||% x$feature_info)) {
    app_validate_readout_feature_design(
      X_alpha_pred,
      x$feature_info_alpha %||% x$feature_info,
      contract = (x$feature_meta_alpha %||% x$feature_meta %||% list())$feature_contract,
      check_reservoir_bias = FALSE
    )
  }
  invisible(TRUE)
}

app_hash_prediction_design <- function(x) {
  app_validate_glofas_prediction_design(x)
  tmp <- tempfile("glofas_prediction_design_", fileext = ".rds")
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(
    list(
      X_pred = x$X_pred,
      X_beta_pred = app_discrepancy_prediction_beta_matrix(x),
      X_alpha_pred = app_discrepancy_prediction_alpha_matrix(x),
      H_g = x$H_g,
      row_info = x$row_info,
      feature_info_beta = x$feature_info_beta %||% x$feature_info,
      feature_info_alpha = x$feature_info_alpha %||% x$feature_info,
      feature_contract_beta = (x$feature_meta_beta %||% x$feature_meta %||% list())$feature_contract,
      feature_contract_alpha = (x$feature_meta_alpha %||% x$feature_meta %||% list())$feature_contract,
      design_version = x$design_version %||% "0.2",
      feature_strategy = x$feature_strategy,
      horizon_scale = x$horizon_scale,
      p0 = x$p0
    ),
    tmp
  )
  app_sha256_file(tmp)
}

app_prediction_design_summary <- function(x) {
  app_validate_glofas_prediction_design(x)
  X_beta_pred <- app_discrepancy_prediction_beta_matrix(x)
  X_alpha_pred <- app_discrepancy_prediction_alpha_matrix(x)
  counts <- app_readout_feature_counts(x$feature_info_beta %||% x$feature_info)
  counts_alpha <- app_readout_feature_counts(x$feature_info_alpha %||% x$feature_info)
  feature_contract <- (x$feature_meta_beta %||% x$feature_meta %||% list())$feature_contract %||% list()
  data.frame(
    fit_id = x$fit_id %||% NA_character_,
    model_id = x$model_id %||% NA_character_,
    quantile_level = x$p0 %||% NA_real_,
    n_prediction_rows = nrow(X_beta_pred),
    n_prediction_features = ncol(X_beta_pred),
    n_prediction_beta_features = ncol(X_beta_pred),
    n_prediction_alpha_features = ncol(X_alpha_pred),
    n_intercept_features = counts$n_intercept_features,
    n_reservoir_features = counts$n_reservoir_features,
    n_reservoir_lag_features = counts$n_reservoir_lag_features,
    n_direct_output_lag_features = counts$n_direct_output_lag_features,
    n_direct_covariate_lag_features = counts$n_direct_covariate_lag_features,
    n_horizon_features = counts$n_horizon_features,
    n_alpha_horizon_features = counts_alpha$n_horizon_features,
    feature_contract_version = feature_contract$version %||% NA_character_,
    feature_contract_has_new_contract = isTRUE(feature_contract$has_new_contract %||% FALSE),
    design_version = x$design_version %||% "0.2",
    two_block_design = isTRUE(x$two_block_design %||% FALSE),
    feature_strategy = x$feature_strategy,
    horizon_scale = x$horizon_scale %||% NA_real_,
    prediction_design_hash = app_hash_prediction_design(x),
    stringsAsFactors = FALSE
  )
}

app_discrepancy_design_version <- function(design) {
  as.character(design$design_version %||% if (!is.null(design$X_alpha)) "0.3" else "0.2")
}

app_discrepancy_beta_matrix <- function(design) {
  X <- design$X_beta %||% design$X_base
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  X
}

app_discrepancy_alpha_matrix <- function(design) {
  X <- design$X_alpha %||% design$X_base
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  X
}

app_discrepancy_prediction_beta_matrix <- function(pred_design) {
  X <- pred_design$X_beta_pred %||% pred_design$X_pred
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  X
}

app_discrepancy_prediction_alpha_matrix <- function(pred_design) {
  X <- pred_design$X_alpha_pred %||% pred_design$X_pred
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  X
}

app_discrepancy_beta_feature_info <- function(design) {
  design$feature_info_beta %||% design$feature_info
}

app_discrepancy_alpha_feature_info <- function(design) {
  design$feature_info_alpha %||% design$feature_info
}

app_discrepancy_beta_feature_names <- function(design) {
  colnames(app_discrepancy_beta_matrix(design)) %||%
    paste0("feature_", seq_len(ncol(app_discrepancy_beta_matrix(design))))
}

app_discrepancy_alpha_feature_names <- function(design) {
  colnames(app_discrepancy_alpha_matrix(design)) %||%
    paste0("feature_", seq_len(ncol(app_discrepancy_alpha_matrix(design))))
}

app_hash_discrepancy_design <- function(x) {
  app_validate_glofas_discrepancy_data(x)
  tmp <- tempfile("glofas_discrepancy_design_", fileext = ".rds")
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(
    list(
      z = x$z,
      H = x$H,
      source = as.character(x$source),
      row_info = x$row_info,
      design_version = app_discrepancy_design_version(x),
      X_beta = app_discrepancy_beta_matrix(x),
      X_alpha = app_discrepancy_alpha_matrix(x),
      feature_strategy = x$feature_strategy %||% "origin_state_pilot",
      horizon_scale = x$horizon_scale %||% NA_real_,
      p0 = x$p0,
      beta_index = x$beta_index,
      alpha_index = x$alpha_index,
      intercept_index = x$intercept_index,
      feature_info_beta = app_discrepancy_beta_feature_info(x),
      feature_info_alpha = app_discrepancy_alpha_feature_info(x),
      feature_contract_beta = (x$feature_meta_beta %||% x$feature_meta %||% list())$feature_contract,
      feature_contract_alpha = (x$feature_meta_alpha %||% x$feature_meta %||% list())$feature_contract
    ),
    tmp
  )
  app_sha256_file(tmp)
}

app_discrepancy_design_summary <- function(x) {
  app_validate_glofas_discrepancy_data(x)
  X_beta <- app_discrepancy_beta_matrix(x)
  X_alpha <- app_discrepancy_alpha_matrix(x)
  X_beta_stack <- as.matrix(x$X_beta_stack %||% X_beta[as.integer(x$row_info$feature_row), , drop = FALSE])
  X_alpha_stack <- as.matrix(x$X_alpha_stack %||% X_alpha[as.integer(x$row_info$feature_row), , drop = FALSE])
  storage.mode(X_beta_stack) <- "double"
  storage.mode(X_alpha_stack) <- "double"
  beta_info <- app_discrepancy_beta_feature_info(x)
  alpha_info <- app_discrepancy_alpha_feature_info(x)
  counts <- app_readout_feature_counts(beta_info)
  counts_alpha <- app_readout_feature_counts(alpha_info)
  cov_cols <- if (!is.null(beta_info)) {
    beta_info$column_name[beta_info$block == "direct_covariate_lag"]
  } else {
    colnames(x$X_covariates %||% matrix(nrow = nrow(X_beta), ncol = 0L))
  }
  y_lag_cols <- if (!is.null(beta_info)) {
    beta_info$column_name[beta_info$block == "direct_output_lag"]
  } else {
    character(0)
  }
  feature_contract <- (x$feature_meta %||% list())$feature_contract %||% list()
  data.frame(
    fit_id = x$fit_id %||% NA_character_,
    model_id = x$model_id %||% NA_character_,
    quantile_level = x$p0 %||% NA_real_,
    cfg_reservoir_seed = x$cfg_reservoir_seed %||% NA_integer_,
    model_grid_reservoir_seed = x$model_grid_reservoir_seed %||% NA_integer_,
    effective_reservoir_seed = x$effective_reservoir_seed %||% NA_integer_,
    reference_reservoir_seed = x$reference_reservoir_seed %||% NA_integer_,
    discrepancy_reservoir_seed = x$discrepancy_reservoir_seed %||% NA_integer_,
    discrepancy_reservoir_seed_offset = x$discrepancy_reservoir_seed_offset %||% NA_integer_,
    n_stacked_rows = length(x$z),
    n_y_rows = sum(as.character(x$source) == "Y"),
    n_g_rows = sum(as.character(x$source) == "G"),
    n_base_feature_rows = nrow(X_beta),
    n_base_features = ncol(X_beta),
    n_beta_features = ncol(X_beta),
    n_alpha_features = ncol(X_alpha),
    n_intercept_features = counts$n_intercept_features,
    n_reservoir_features = counts$n_reservoir_features,
    n_reservoir_lag_features = counts$n_reservoir_lag_features,
    n_direct_output_lag_features = counts$n_direct_output_lag_features,
    n_direct_covariate_lag_features = counts$n_direct_covariate_lag_features,
    n_horizon_features = counts$n_horizon_features,
    n_alpha_intercept_features = counts_alpha$n_intercept_features,
    n_alpha_reservoir_features = counts_alpha$n_reservoir_features,
    n_alpha_direct_output_lag_features = counts_alpha$n_direct_output_lag_features,
    n_alpha_direct_covariate_lag_features = counts_alpha$n_direct_covariate_lag_features,
    n_alpha_horizon_features = counts_alpha$n_horizon_features,
    n_covariate_lag_features = length(cov_cols),
    n_augmented_features = ncol(x$H),
    direct_output_lag_columns = paste(y_lag_cols, collapse = ";"),
    direct_covariate_lag_columns = paste(cov_cols, collapse = ";"),
    covariate_lag_columns = paste(cov_cols, collapse = ";"),
    feature_contract_version = feature_contract$version %||% NA_character_,
    feature_contract_has_new_contract = isTRUE(feature_contract$has_new_contract %||% FALSE),
    design_version = app_discrepancy_design_version(x),
    two_block_design = isTRUE(x$two_block_design %||% FALSE),
    feature_strategy = x$feature_strategy %||% "origin_state_pilot",
    horizon_scale = x$horizon_scale %||% NA_real_,
    include_ensemble_training = isTRUE(x$include_ensemble_training),
    intercept_index = paste(x$intercept_index, collapse = ";"),
    design_hash = app_hash_discrepancy_design(x),
    stringsAsFactors = FALSE
  )
}

app_validate_glofas_discrepancy_data <- function(x) {
  required <- c("z", "H", "source", "X_base", "row_info", "beta_index", "alpha_index")
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(sprintf("Discrepancy design is missing required objects: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }

  if (!is.numeric(x$z) || any(!is.finite(x$z))) {
    stop("Discrepancy design z must be finite and numeric.", call. = FALSE)
  }
  if (!is.matrix(x$H) || any(!is.finite(x$H))) {
    stop("Discrepancy design H must be a finite numeric matrix.", call. = FALSE)
  }
  if (nrow(x$H) != length(x$z) || length(x$source) != length(x$z)) {
    stop("Discrepancy design has inconsistent z, H, and source lengths.", call. = FALSE)
  }
  if (!all(as.character(x$source) %in% c("Y", "G"))) {
    stop("Discrepancy design source labels must be Y or G.", call. = FALSE)
  }

  X_beta <- app_discrepancy_beta_matrix(x)
  X_alpha <- app_discrepancy_alpha_matrix(x)
  p_beta <- ncol(X_beta)
  p_alpha <- ncol(X_alpha)
  if (nrow(X_beta) != nrow(X_alpha)) {
    stop("Discrepancy design reference and discrepancy feature blocks must have the same row count.", call. = FALSE)
  }
  if (!identical(as.integer(x$beta_index), seq_len(p_beta))) {
    stop("Discrepancy design beta_index is inconsistent with the reference feature block.", call. = FALSE)
  }
  if (!identical(as.integer(x$alpha_index), p_beta + seq_len(p_alpha))) {
    stop("Discrepancy design alpha_index is inconsistent with the discrepancy feature block.", call. = FALSE)
  }
  if (ncol(x$H) != p_beta + p_alpha) {
    stop("Discrepancy design H column count is incompatible with beta and alpha feature blocks.", call. = FALSE)
  }
  y_rows <- as.character(x$source) == "Y"
  g_rows <- as.character(x$source) == "G"
  if (any(y_rows) && any(abs(x$H[y_rows, p_beta + seq_len(p_alpha), drop = FALSE]) > 1.0e-10)) {
    stop("Y-source rows must have zero discrepancy-design columns.", call. = FALSE)
  }
  if (!nrow(x$row_info) || nrow(x$row_info) != length(x$z)) {
    stop("Discrepancy row_info must have one row per stacked response.", call. = FALSE)
  }
  feature_rows <- as.integer(x$row_info$feature_row)
  if (length(feature_rows) != nrow(x$row_info) || any(!is.finite(feature_rows))) {
    stop("Discrepancy row_info must contain finite feature_row indices.", call. = FALSE)
  }
  if (any(feature_rows < 1L | feature_rows > nrow(X_beta))) {
    stop("Discrepancy row_info feature_row indices are outside the reference feature block.", call. = FALSE)
  }
  X_beta_stack <- as.matrix(x$X_beta_stack %||% X_beta[feature_rows, , drop = FALSE])
  X_alpha_stack <- as.matrix(x$X_alpha_stack %||% X_alpha[feature_rows, , drop = FALSE])
  storage.mode(X_beta_stack) <- "double"
  storage.mode(X_alpha_stack) <- "double"
  if (nrow(X_beta_stack) != length(x$z) || nrow(X_alpha_stack) != length(x$z)) {
    stop("Discrepancy design stacked feature blocks must have one row per stacked response.", call. = FALSE)
  }
  if (any(g_rows) && !isTRUE(all.equal(
    x$H[g_rows, seq_len(p_beta), drop = FALSE],
    X_beta_stack[g_rows, , drop = FALSE],
    tolerance = 1.0e-10,
    check.attributes = FALSE
  ))) {
    stop("G-source rows must match the reference feature rows in the beta block.", call. = FALSE)
  }
  if (any(g_rows) && !isTRUE(all.equal(
    x$H[g_rows, p_beta + seq_len(p_alpha), drop = FALSE],
    X_alpha_stack[g_rows, , drop = FALSE],
    tolerance = 1.0e-10,
    check.attributes = FALSE
  ))) {
    stop("G-source rows must match the discrepancy feature rows in the alpha block.", call. = FALSE)
  }
  if (!is.null(app_discrepancy_beta_feature_info(x))) {
    app_validate_readout_feature_design(
      X_beta,
      app_discrepancy_beta_feature_info(x),
      contract = (x$feature_meta_beta %||% x$feature_meta %||% list())$feature_contract
    )
  }
  if (!is.null(app_discrepancy_alpha_feature_info(x))) {
    app_validate_readout_feature_design(
      X_alpha,
      app_discrepancy_alpha_feature_info(x),
      contract = (x$feature_meta_alpha %||% x$feature_meta %||% list())$feature_contract
    )
  }

  invisible(TRUE)
}
