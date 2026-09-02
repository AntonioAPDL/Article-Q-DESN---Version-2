# Historical two-DESN Normal bridge for the GloFAS application.
#
# This is a screening/initialization scaffold only. It uses retrospective USGS
# and retrospective GloFAS values up to the cutoff, with no issued forecast
# ensembles. The reference component learns the USGS path; the discrepancy
# component learns GloFAS - USGS. The implied corrected historical path is
# GloFAS - fitted discrepancy.

app_glofas_normal_part2_default_values <- function() {
  base <- app_glofas_normal_part1_default_values()
  base$reference_seed <- 20260512L
  base$discrepancy_seed <- 20261521L
  base
}

app_glofas_normal_part2_required_panel_columns <- function() {
  c(
    "origin_date", "target_date", "horizon", "member", "is_retrospective",
    "is_ensemble", "y_reference", "g_glofas", "y_transformed",
    "g_transformed", "split", "cutoff_id"
  )
}

app_glofas_normal_part2_row_value <- function(row, name, default = NULL, prefix = NULL) {
  row <- row[1L, , drop = FALSE]
  candidates <- c()
  if (!is.null(prefix) && nzchar(prefix)) candidates <- c(candidates, paste0(prefix, "_", name))
  candidates <- c(candidates, name)
  for (nm in candidates) {
    if (!nm %in% names(row)) next
    value <- row[[nm]][[1L]]
    if (length(value) && !(length(value) == 1L && is.na(value))) return(value)
  }
  default
}

app_glofas_normal_part2_component_cfg <- function(base_cfg, candidate_row, component) {
  component <- match.arg(component, c("reference", "discrepancy"))
  defaults <- app_glofas_normal_part2_default_values()
  prefix <- if (identical(component, "reference")) "ref" else "disc"
  seed_default <- if (identical(component, "reference")) defaults$reference_seed else defaults$discrepancy_seed
  app_glofas_normal_part1_make_cfg(
    base_cfg = base_cfg,
    n = app_glofas_normal_part2_row_value(candidate_row, "n_vector", prefix = prefix),
    m = app_glofas_normal_part2_row_value(candidate_row, "m", prefix = prefix),
    output_lag_max = app_glofas_normal_part2_row_value(candidate_row, "output_lag_max", prefix = prefix),
    covariate_lag_max = app_glofas_normal_part2_row_value(candidate_row, "covariate_lag_max", prefix = prefix),
    alpha = app_glofas_normal_part2_row_value(candidate_row, "alpha", prefix = prefix),
    rho = app_glofas_normal_part2_row_value(candidate_row, "rho", prefix = prefix),
    seed = app_glofas_normal_part2_row_value(candidate_row, "seed", seed_default, prefix = prefix),
    washout = app_glofas_normal_part2_row_value(candidate_row, "washout", defaults$washout, prefix = prefix)
  )
}

app_glofas_normal_part2_prepare_panel_from_panel <- function(panel, cutoff) {
  app_check_required_columns(panel, app_glofas_normal_part2_required_panel_columns(), "historical bridge panel")
  if (is.null(cutoff) || !nrow(cutoff)) {
    stop("Part 2 historical bridge requires a cutoff row.", call. = FALSE)
  }
  cutoff <- cutoff[1L, , drop = FALSE]
  panel$origin_date <- as.Date(panel$origin_date)
  panel$target_date <- as.Date(panel$target_date)
  panel$horizon <- as.integer(panel$horizon)
  train_start <- as.Date(cutoff$train_start[[1L]])
  train_end <- as.Date(cutoff$train_end[[1L]])
  if (is.na(train_start) || is.na(train_end)) {
    stop("Part 2 cutoff must contain valid train_start and train_end dates.", call. = FALSE)
  }
  hist <- panel[
    app_as_bool_vec(panel$is_retrospective) &
      panel$target_date >= train_start &
      panel$target_date <= train_end &
      is.finite(panel$y_transformed) &
      is.finite(panel$g_transformed),
    ,
    drop = FALSE
  ]
  hist <- hist[order(hist$target_date, hist$origin_date, hist$horizon), , drop = FALSE]
  if (!nrow(hist)) stop("No paired retrospective USGS/GloFAS rows are available for Part 2.", call. = FALSE)
  if (anyDuplicated(hist$target_date)) {
    stop("Part 2 historical bridge expects exactly one paired row per target date.", call. = FALSE)
  }
  hist$d_g_transformed <- as.numeric(hist$g_transformed) - as.numeric(hist$y_transformed)
  hist$d_g_raw <- as.numeric(hist$g_glofas) - as.numeric(hist$y_reference)
  if (any(!is.finite(hist$d_g_transformed))) {
    stop("Part 2 discrepancy target contains non-finite transformed GloFAS - USGS values.", call. = FALSE)
  }
  identity_gap <- max(abs(as.numeric(hist$g_transformed) - hist$d_g_transformed - as.numeric(hist$y_transformed)))
  if (!is.finite(identity_gap) || identity_gap > 1.0e-10) {
    stop("Part 2 discrepancy identity check failed: y != g - (g - y).", call. = FALSE)
  }
  hist <- app_copy_covariate_attrs(hist, panel)
  list(panel = hist, cutoff = cutoff)
}

app_glofas_normal_part2_prepare_panel <- function(cfg, manifest = NULL, schema = NULL, panel_bundle = NULL) {
  if (!is.null(panel_bundle)) {
    return(app_glofas_normal_part2_prepare_panel_from_panel(panel_bundle$panel, panel_bundle$cutoff))
  }
  manifest <- manifest %||% app_load_input_manifest(app_config_path(cfg, "input_manifest"), required = TRUE)
  schema <- schema %||% app_read_yaml(app_config_path(cfg, "schema"))
  panel <- app_build_application_panel(cfg, manifest, schema)
  cutoffs <- app_validate_cutoffs(app_config_path(cfg, "cutoffs"))
  if (nrow(cutoffs) != 1L) {
    stop("Normal Part 2 historical bridge expects exactly one enabled cutoff.", call. = FALSE)
  }
  app_glofas_normal_part2_prepare_panel_from_panel(panel, cutoffs[1L, , drop = FALSE])
}

app_glofas_normal_part2_component_design <- function(
  panel,
  cfg,
  response_col,
  component,
  seed,
  drop
) {
  if (!response_col %in% names(panel)) {
    stop(sprintf("Missing Part 2 response column '%s'.", response_col), call. = FALSE)
  }
  panel_component <- panel
  panel_component$y_transformed <- as.numeric(panel[[response_col]])
  if (any(!is.finite(panel_component$y_transformed))) {
    stop(sprintf("Response column '%s' contains non-finite values.", response_col), call. = FALSE)
  }
  panel_component <- app_copy_covariate_attrs(panel_component, panel)
  design <- app_qdesn_build_article_design_full(
    panel = panel_component,
    cfg = cfg,
    seed = as.integer(seed),
    drop = as.integer(drop)
  )
  readout <- app_glofas_normal_part1_readout_matrix(design)
  X_full <- readout$X
  if (ncol(X_full) < 2L) {
    stop("Part 2 component design must include at least one reservoir state.", call. = FALSE)
  }
  state_X <- X_full[, -1L, drop = FALSE]
  colnames(state_X) <- paste0(component, "__", colnames(state_X))
  feature_info <- readout$feature_info[-1L, , drop = FALSE]
  feature_info$column_name <- colnames(state_X)
  feature_info$block <- paste0(component, "_reservoir_state")
  feature_info$component <- component
  feature_info$response <- response_col
  feature_info$is_intercept <- FALSE
  dates <- as.Date(panel$target_date[design$meta$keep_idx])
  list(
    cfg = cfg,
    state_X = state_X,
    y = as.numeric(design$y_fit),
    dates = dates,
    keep_idx = as.integer(design$meta$keep_idx),
    feature_info = feature_info,
    design_meta = design$meta,
    reservoir = design$reservoir
  )
}

app_glofas_normal_part2_add_intercept <- function(X_state, component) {
  X <- cbind(readout_intercept = 1, as.matrix(X_state))
  storage.mode(X) <- "double"
  feature_info <- app_feature_info_rows(
    colnames(X),
    block = c("readout_intercept", rep(paste0(component, "_reservoir_state"), ncol(X) - 1L)),
    is_intercept = c(TRUE, rep(FALSE, ncol(X) - 1L))
  )
  feature_info$component <- c("intercept", rep(component, ncol(X) - 1L))
  feature_info$column_index <- seq_len(nrow(feature_info))
  feature_info <- feature_info[, c("column_index", setdiff(names(feature_info), "column_index")), drop = FALSE]
  app_validate_readout_feature_design(X, feature_info, contract = list(readout = list(add_intercept = TRUE)))
  list(X = X, feature_info = feature_info)
}

app_glofas_normal_part2_lag_by_date <- function(dates, values, lag_days = 1L) {
  dates <- as.Date(dates)
  values <- as.numeric(values)
  idx <- match(dates - as.integer(lag_days), dates)
  out <- rep(NA_real_, length(values))
  keep <- !is.na(idx)
  out[keep] <- values[idx[keep]]
  out
}

app_glofas_normal_part2_build_design <- function(base_cfg, candidate_row, panel_bundle = NULL) {
  candidate_row <- candidate_row[1L, , drop = FALSE]
  paired <- app_glofas_normal_part2_prepare_panel(base_cfg, panel_bundle = panel_bundle)
  panel <- paired$panel
  ref_cfg <- app_glofas_normal_part2_component_cfg(base_cfg, candidate_row, "reference")
  disc_cfg <- app_glofas_normal_part2_component_cfg(base_cfg, candidate_row, "discrepancy")
  ref_seed <- as.integer(ref_cfg$reservoir$seed)
  disc_seed <- as.integer(disc_cfg$reservoir$seed)
  ref_drop <- as.integer(ref_cfg$reservoir$washout %||% app_glofas_normal_part2_default_values()$washout)
  disc_drop <- as.integer(disc_cfg$reservoir$washout %||% app_glofas_normal_part2_default_values()$washout)
  reference <- app_glofas_normal_part2_component_design(
    panel = panel,
    cfg = ref_cfg,
    response_col = "y_transformed",
    component = "reference",
    seed = ref_seed,
    drop = ref_drop
  )
  discrepancy <- app_glofas_normal_part2_component_design(
    panel = panel,
    cfg = disc_cfg,
    response_col = "d_g_transformed",
    component = "discrepancy",
    seed = disc_seed,
    drop = disc_drop
  )
  common_dates <- sort(intersect(reference$dates, discrepancy$dates))
  if (length(common_dates) < 50L) {
    stop("Part 2 reference/discrepancy designs have too few aligned dates.", call. = FALSE)
  }
  ref_idx <- match(common_dates, reference$dates)
  disc_idx <- match(common_dates, discrepancy$dates)
  panel_idx <- match(common_dates, as.Date(panel$target_date))
  if (any(is.na(ref_idx)) || any(is.na(disc_idx)) || any(is.na(panel_idx))) {
    stop("Part 2 failed to align component designs to the paired historical panel.", call. = FALSE)
  }
  ref_readout <- app_glofas_normal_part2_add_intercept(reference$state_X[ref_idx, , drop = FALSE], "reference")
  disc_readout <- app_glofas_normal_part2_add_intercept(discrepancy$state_X[disc_idx, , drop = FALSE], "discrepancy")
  y <- as.numeric(panel$y_transformed[panel_idx])
  g <- as.numeric(panel$g_transformed[panel_idx])
  d <- as.numeric(panel$d_g_transformed[panel_idx])
  d_lag1 <- app_glofas_normal_part2_lag_by_date(common_dates, d, lag_days = 1L)
  if (nrow(ref_readout$X) != length(y) || nrow(disc_readout$X) != length(d)) {
    stop("Part 2 readout dimensions are incompatible with aligned responses.", call. = FALSE)
  }
  list(
    cfg = list(reference = ref_cfg, discrepancy = disc_cfg),
    panel = panel[panel_idx, , drop = FALSE],
    dates = common_dates,
    y_reference = y,
    g_retrospective = g,
    d_g = d,
    d_g_lag1 = d_lag1,
    reference = list(
      X = ref_readout$X,
      y = y,
      feature_info = ref_readout$feature_info,
      component_design = reference
    ),
    discrepancy = list(
      X = disc_readout$X,
      y = d,
      feature_info = disc_readout$feature_info,
      component_design = discrepancy
    ),
    design_hash = list(
      reference_full = app_glofas_normal_part1_design_fingerprint(ref_readout$X, y, common_dates, ref_readout$feature_info),
      discrepancy_full = app_glofas_normal_part1_design_fingerprint(disc_readout$X, d, common_dates, disc_readout$feature_info)
    )
  )
}

app_glofas_normal_part2_score_baseline <- function(observed, predicted, prefix = "") {
  err <- as.numeric(predicted) - as.numeric(observed)
  out <- data.frame(
    mae = mean(abs(err), na.rm = TRUE),
    rmse = sqrt(mean(err^2, na.rm = TRUE)),
    bias = mean(err, na.rm = TRUE),
    correlation = suppressWarnings(stats::cor(observed, predicted, use = "complete.obs")),
    stringsAsFactors = FALSE
  )
  if (nzchar(prefix)) names(out) <- paste0(prefix, names(out))
  out
}

app_glofas_normal_part2_tail_value <- function(x, name, default = NA_real_) {
  if (is.null(x) || !is.data.frame(x) || !nrow(x) || !name %in% names(x)) return(default)
  value <- x[[name]][[nrow(x)]]
  if (length(value)) value else default
}

app_glofas_normal_part2_prediction_detail <- function(
  design,
  valid_idx,
  reference_pred,
  discrepancy_pred,
  candidate_id,
  method,
  rhs_tau0_reference = NA_real_,
  rhs_tau0_discrepancy = NA_real_
) {
  y <- design$y_reference[valid_idx]
  g <- design$g_retrospective[valid_idx]
  d <- design$d_g[valid_idx]
  corrected_mean <- g - discrepancy_pred$mean
  corrected_sd <- discrepancy_pred$sd
  data.frame(
    candidate_id = as.character(candidate_id),
    method = as.character(method),
    rhs_tau0_reference = as.numeric(rhs_tau0_reference),
    rhs_tau0_discrepancy = as.numeric(rhs_tau0_discrepancy),
    date = design$dates[valid_idx],
    observed_usgs = y,
    retrospective_glofas = g,
    observed_discrepancy = d,
    discrepancy_lag1 = design$d_g_lag1[valid_idx],
    reference_pred_mean = reference_pred$mean,
    reference_pred_sd = reference_pred$sd,
    discrepancy_pred_mean = discrepancy_pred$mean,
    discrepancy_pred_sd = discrepancy_pred$sd,
    corrected_pred_mean = corrected_mean,
    corrected_pred_sd = corrected_sd,
    reference_crps = app_glofas_normal_crps(y, reference_pred$mean, reference_pred$sd),
    discrepancy_crps = app_glofas_normal_crps(d, discrepancy_pred$mean, discrepancy_pred$sd),
    corrected_crps = app_glofas_normal_crps(y, corrected_mean, corrected_sd),
    corrected_abs_error = abs(corrected_mean - y),
    corrected_squared_error = (corrected_mean - y)^2,
    raw_abs_error = abs(g - y),
    raw_squared_error = (g - y)^2,
    stringsAsFactors = FALSE
  )
}

app_glofas_normal_part2_component_warm_start <- function(
  candidate_row,
  component,
  design_component,
  train_idx,
  fit,
  train_hash
) {
  cid <- as.character(candidate_row$candidate_id[[1L]] %||% "part2_candidate")
  warm <- list(
    type = "glofas_normal_part1_ridge_warm_start",
    version = "0.1",
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    candidate_id = paste(cid, component, sep = "__"),
    candidate_row = candidate_row,
    split = list(
      train_idx_range = range(train_idx),
      valid_idx_range = NA_integer_
    ),
    design = list(
      n_rows = nrow(design_component$X),
      n_features = ncol(design_component$X),
      train_design_fingerprint = train_hash,
      full_design_fingerprint = NA_character_,
      colnames = colnames(design_component$X),
      feature_info = design_component$feature_info,
      design_start_date = NA_character_,
      design_end_date = NA_character_
    ),
    fit = list(
      beta_mean = as.numeric(fit$beta_mean),
      beta_var_diag = as.numeric(fit$beta_var_diag),
      sigma_a = as.numeric(fit$sigma_a),
      sigma_b = as.numeric(fit$sigma_b),
      sigma2_mean = as.numeric(fit$sigma2_mean),
      ridge_tau2 = as.numeric(fit$ridge_tau2),
      intercept_var = as.numeric(fit$intercept_var),
      n_train = as.integer(fit$n_train),
      p = as.integer(fit$p)
    )
  )
  class(warm) <- c("glofas_normal_part1_ridge_warm_start", "list")
  warm
}

app_glofas_normal_part2_fit_ridge_components <- function(base_cfg, candidate_row, panel_bundle = NULL) {
  candidate_row <- candidate_row[1L, , drop = FALSE]
  design <- app_glofas_normal_part2_build_design(base_cfg, candidate_row, panel_bundle = panel_bundle)
  split <- app_glofas_normal_part1_validation_split(
    length(design$dates),
    app_glofas_normal_part2_row_value(
      candidate_row,
      "validation_n",
      app_glofas_normal_part2_default_values()$validation_n
    )
  )
  train_idx <- split$train_idx
  ridge_tau2 <- as.numeric(app_glofas_normal_part2_row_value(candidate_row, "ridge_tau2", app_glofas_normal_part2_default_values()$ridge_tau2))
  intercept_var <- as.numeric(app_glofas_normal_part2_row_value(candidate_row, "intercept_var", app_glofas_normal_part2_default_values()$intercept_var))
  sigma_a <- as.numeric(app_glofas_normal_part2_row_value(candidate_row, "sigma_a", app_glofas_normal_part2_default_values()$sigma_a))
  sigma_b <- as.numeric(app_glofas_normal_part2_row_value(candidate_row, "sigma_b", app_glofas_normal_part2_default_values()$sigma_b))
  ref_fit <- app_glofas_normal_ridge_fit(
    X = design$reference$X[train_idx, , drop = FALSE],
    y = design$reference$y[train_idx],
    ridge_tau2 = ridge_tau2,
    intercept_var = intercept_var,
    sigma_a = sigma_a,
    sigma_b = sigma_b
  )
  disc_fit <- app_glofas_normal_ridge_fit(
    X = design$discrepancy$X[train_idx, , drop = FALSE],
    y = design$discrepancy$y[train_idx],
    ridge_tau2 = ridge_tau2,
    intercept_var = intercept_var,
    sigma_a = sigma_a,
    sigma_b = sigma_b
  )
  train_hash_ref <- app_glofas_normal_part1_design_fingerprint(
    design$reference$X[train_idx, , drop = FALSE],
    design$reference$y[train_idx],
    design$dates[train_idx],
    design$reference$feature_info
  )
  train_hash_disc <- app_glofas_normal_part1_design_fingerprint(
    design$discrepancy$X[train_idx, , drop = FALSE],
    design$discrepancy$y[train_idx],
    design$dates[train_idx],
    design$discrepancy$feature_info
  )
  warm_start <- list(
    type = "glofas_normal_part2_ridge_warm_start",
    version = "0.1",
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    candidate_id = as.character(candidate_row$candidate_id[[1L]] %||% "part2_candidate"),
    split = split,
    design_hash = list(
      reference_train = train_hash_ref,
      discrepancy_train = train_hash_disc,
      reference_full = design$design_hash$reference_full,
      discrepancy_full = design$design_hash$discrepancy_full
    ),
    reference = app_glofas_normal_part2_component_warm_start(
      candidate_row, "reference", design$reference, train_idx, ref_fit, train_hash_ref
    ),
    discrepancy = app_glofas_normal_part2_component_warm_start(
      candidate_row, "discrepancy", design$discrepancy, train_idx, disc_fit, train_hash_disc
    )
  )
  class(warm_start) <- c("glofas_normal_part2_ridge_warm_start", "list")
  list(
    design = design,
    split = split,
    reference_fit = ref_fit,
    discrepancy_fit = disc_fit,
    warm_start = warm_start
  )
}

app_glofas_normal_part2_validate_warm_start <- function(warm_start, design = NULL, train_idx = NULL) {
  if (!inherits(warm_start, "glofas_normal_part2_ridge_warm_start") ||
      !identical(as.character(warm_start$type %||% "")[[1L]], "glofas_normal_part2_ridge_warm_start")) {
    stop("Expected a GloFAS Normal Part 2 ridge warm-start object.", call. = FALSE)
  }
  app_glofas_normal_part1_validate_ridge_warm_start(warm_start$reference, strict_hash = FALSE)
  app_glofas_normal_part1_validate_ridge_warm_start(warm_start$discrepancy, strict_hash = FALSE)
  if (!is.null(design)) {
    if (ncol(design$reference$X) != as.integer(warm_start$reference$fit$p)) {
      stop("Reference warm-start dimension does not match the Part 2 design.", call. = FALSE)
    }
    if (ncol(design$discrepancy$X) != as.integer(warm_start$discrepancy$fit$p)) {
      stop("Discrepancy warm-start dimension does not match the Part 2 design.", call. = FALSE)
    }
    if (!is.null(train_idx)) {
      ref_hash <- app_glofas_normal_part1_design_fingerprint(
        design$reference$X[train_idx, , drop = FALSE],
        design$reference$y[train_idx],
        design$dates[train_idx],
        design$reference$feature_info
      )
      disc_hash <- app_glofas_normal_part1_design_fingerprint(
        design$discrepancy$X[train_idx, , drop = FALSE],
        design$discrepancy$y[train_idx],
        design$dates[train_idx],
        design$discrepancy$feature_info
      )
      if (!identical(ref_hash, as.character(warm_start$design_hash$reference_train))) {
        stop("Reference warm-start training design fingerprint mismatch.", call. = FALSE)
      }
      if (!identical(disc_hash, as.character(warm_start$design_hash$discrepancy_train))) {
        stop("Discrepancy warm-start training design fingerprint mismatch.", call. = FALSE)
      }
    }
  }
  invisible(TRUE)
}

app_glofas_normal_part2_score_from_fits <- function(
  design,
  split,
  reference_fit,
  discrepancy_fit,
  candidate_row,
  method,
  started,
  rhs_tau0_reference = NA_real_,
  rhs_tau0_discrepancy = NA_real_,
  trace = NULL,
  activity = NULL
) {
  train_idx <- split$train_idx
  valid_idx <- split$valid_idx
  ref_valid <- app_glofas_normal_predict(reference_fit, design$reference$X[valid_idx, , drop = FALSE], chunk_size = 64L)
  disc_valid <- app_glofas_normal_predict(discrepancy_fit, design$discrepancy$X[valid_idx, , drop = FALSE], chunk_size = 64L)
  ref_train <- app_glofas_normal_predict(reference_fit, design$reference$X[train_idx, , drop = FALSE], chunk_size = 64L)
  disc_train <- app_glofas_normal_predict(discrepancy_fit, design$discrepancy$X[train_idx, , drop = FALSE], chunk_size = 64L)

  corrected_valid <- list(
    mean = design$g_retrospective[valid_idx] - disc_valid$mean,
    sd = disc_valid$sd
  )
  corrected_train <- list(
    mean = design$g_retrospective[train_idx] - disc_train$mean,
    sd = disc_train$sd
  )
  persistence_valid <- is.finite(design$d_g_lag1[valid_idx])
  corrected_persistence <- design$g_retrospective[valid_idx] - design$d_g_lag1[valid_idx]
  candidate_id <- as.character(candidate_row$candidate_id[[1L]] %||% "part2_candidate")
  detail <- app_glofas_normal_part2_prediction_detail(
    design = design,
    valid_idx = valid_idx,
    reference_pred = ref_valid,
    discrepancy_pred = disc_valid,
    candidate_id = candidate_id,
    method = method,
    rhs_tau0_reference = rhs_tau0_reference,
    rhs_tau0_discrepancy = rhs_tau0_discrepancy
  )
  windows <- c(50L, 200L)
  window_scores <- lapply(windows, function(w) {
    idx <- utils::tail(seq_along(valid_idx), min(w, length(valid_idx)))
    cbind(
      app_glofas_normal_score_predictions(
        design$y_reference[valid_idx][idx],
        list(mean = corrected_valid$mean[idx], sd = corrected_valid$sd[idx]),
        prefix = paste0("corrected_valid_last", w, "_")
      ),
      app_glofas_normal_score_predictions(
        design$d_g[valid_idx][idx],
        list(mean = disc_valid$mean[idx], sd = disc_valid$sd[idx]),
        prefix = paste0("discrepancy_valid_last", w, "_")
      )
    )
  })
  window_scores <- do.call(cbind, window_scores)
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  trace_tail_ref <- data.frame()
  trace_tail_disc <- data.frame()
  if (!is.null(trace) && nrow(trace)) {
    trace_tail_ref <- utils::tail(trace[trace$component == "reference", , drop = FALSE], 1L)
    trace_tail_disc <- utils::tail(trace[trace$component == "discrepancy", , drop = FALSE], 1L)
  }
  summary <- cbind(
    candidate_row,
    data.frame(
      status = "completed",
      method = as.character(method),
      n_rows_design = length(design$dates),
      n_train = length(train_idx),
      n_valid = length(valid_idx),
      n_reference_readout_features = ncol(design$reference$X),
      n_discrepancy_readout_features = ncol(design$discrepancy$X),
      design_start_date = as.character(min(design$dates)),
      design_end_date = as.character(max(design$dates)),
      valid_start_date = as.character(min(design$dates[valid_idx])),
      valid_end_date = as.character(max(design$dates[valid_idx])),
      reference_design_hash = design$design_hash$reference_full,
      discrepancy_design_hash = design$design_hash$discrepancy_full,
      rhs_tau0_reference = as.numeric(rhs_tau0_reference),
      rhs_tau0_discrepancy = as.numeric(rhs_tau0_discrepancy),
      runtime_seconds = elapsed,
      reference_iterations = as.integer(reference_fit$iterations %||% NA_integer_),
      discrepancy_iterations = as.integer(discrepancy_fit$iterations %||% NA_integer_),
      reference_converged = isTRUE(reference_fit$converged %||% TRUE),
      discrepancy_converged = isTRUE(discrepancy_fit$converged %||% TRUE),
      reference_effective_tau = as.numeric(app_glofas_normal_part2_tail_value(trace_tail_ref, "effective_tau")),
      discrepancy_effective_tau = as.numeric(app_glofas_normal_part2_tail_value(trace_tail_disc, "effective_tau")),
      stringsAsFactors = FALSE
    ),
    app_glofas_normal_score_predictions(design$reference$y[train_idx], ref_train, prefix = "reference_train_"),
    app_glofas_normal_score_predictions(design$reference$y[valid_idx], ref_valid, prefix = "reference_valid_"),
    app_glofas_normal_score_predictions(design$discrepancy$y[train_idx], disc_train, prefix = "discrepancy_train_"),
    app_glofas_normal_score_predictions(design$discrepancy$y[valid_idx], disc_valid, prefix = "discrepancy_valid_"),
    app_glofas_normal_score_predictions(design$y_reference[train_idx], corrected_train, prefix = "corrected_train_"),
    app_glofas_normal_score_predictions(design$y_reference[valid_idx], corrected_valid, prefix = "corrected_valid_"),
    app_glofas_normal_part2_score_baseline(design$y_reference[valid_idx], design$g_retrospective[valid_idx], prefix = "raw_valid_"),
    app_glofas_normal_part2_score_baseline(
      design$d_g[valid_idx][persistence_valid],
      design$d_g_lag1[valid_idx][persistence_valid],
      prefix = "discrepancy_lag1_valid_"
    ),
    app_glofas_normal_part2_score_baseline(
      design$y_reference[valid_idx][persistence_valid],
      corrected_persistence[persistence_valid],
      prefix = "corrected_lag1_valid_"
    ),
    window_scores
  )
  summary$valid_mean_crps <- summary$corrected_valid_mean_crps
  summary$valid_mae <- summary$corrected_valid_mae
  summary$valid_rmse <- summary$corrected_valid_rmse
  summary$primary_score_contract <- "corrected_usgs_from_retrospective_glofas_minus_predicted_discrepancy"
  list(
    summary = summary,
    detail = detail,
    trace = trace %||% data.frame(),
    activity = activity %||% data.frame(),
    reference_fit = reference_fit,
    discrepancy_fit = discrepancy_fit,
    design = design
  )
}

app_glofas_normal_part2_score_ridge_candidate <- function(base_cfg, candidate_row, panel_bundle = NULL) {
  candidate_row <- candidate_row[1L, , drop = FALSE]
  started <- Sys.time()
  fits <- app_glofas_normal_part2_fit_ridge_components(base_cfg, candidate_row, panel_bundle = panel_bundle)
  app_glofas_normal_part2_score_from_fits(
    design = fits$design,
    split = fits$split,
    reference_fit = fits$reference_fit,
    discrepancy_fit = fits$discrepancy_fit,
    candidate_row = candidate_row,
    method = "normal_scaled_ridge_two_component_bridge",
    started = started
  )
}

app_glofas_normal_part2_score_rhs_candidate <- function(
  base_cfg,
  rhs_row,
  panel_bundle = NULL,
  warm_start = NULL
) {
  rhs_row <- rhs_row[1L, , drop = FALSE]
  started <- Sys.time()
  design <- app_glofas_normal_part2_build_design(base_cfg, rhs_row, panel_bundle = panel_bundle)
  split <- app_glofas_normal_part1_validation_split(
    length(design$dates),
    app_glofas_normal_part2_row_value(
      rhs_row,
      "validation_n",
      app_glofas_normal_part2_default_values()$validation_n
    )
  )
  if (is.null(warm_start)) {
    warm_start <- app_glofas_normal_part2_fit_ridge_components(
      base_cfg,
      rhs_row,
      panel_bundle = panel_bundle
    )$warm_start
  }
  app_glofas_normal_part2_validate_warm_start(warm_start, design = design, train_idx = split$train_idx)
  tau0_reference <- as.numeric(app_glofas_normal_part2_row_value(rhs_row, "rhs_tau0_reference", default = app_glofas_normal_part2_row_value(rhs_row, "rhs_tau0", 1)))
  tau0_discrepancy <- as.numeric(app_glofas_normal_part2_row_value(rhs_row, "rhs_tau0_discrepancy", default = app_glofas_normal_part2_row_value(rhs_row, "rhs_tau0", 1)))
  max_iter <- as.integer(app_glofas_normal_part2_row_value(rhs_row, "rhs_max_iter", 100L))
  min_iter <- as.integer(app_glofas_normal_part2_row_value(rhs_row, "rhs_min_iter", 30L))
  tol <- as.numeric(app_glofas_normal_part2_row_value(rhs_row, "rhs_tol", 1.0e-4))
  update_every <- as.integer(app_glofas_normal_part2_row_value(rhs_row, "rhs_update_every", 1L))
  freeze_tau <- as.integer(app_glofas_normal_part2_row_value(rhs_row, "rhs_freeze_tau_warmup_iters", 0L))
  min_tau_updates <- as.integer(app_glofas_normal_part2_row_value(rhs_row, "rhs_min_tau_updates", 0L))
  ref_fit <- app_glofas_normal_rhs_fit(
    X = design$reference$X[split$train_idx, , drop = FALSE],
    y = design$reference$y[split$train_idx],
    ridge_warm_start = warm_start$reference,
    tau0 = tau0_reference,
    max_iter = max_iter,
    min_iter = min_iter,
    tol = tol,
    rhs_update_every = update_every,
    freeze_tau_warmup_iters = freeze_tau,
    min_tau_updates = min_tau_updates
  )
  disc_fit <- app_glofas_normal_rhs_fit(
    X = design$discrepancy$X[split$train_idx, , drop = FALSE],
    y = design$discrepancy$y[split$train_idx],
    ridge_warm_start = warm_start$discrepancy,
    tau0 = tau0_discrepancy,
    max_iter = max_iter,
    min_iter = min_iter,
    tol = tol,
    rhs_update_every = update_every,
    freeze_tau_warmup_iters = freeze_tau,
    min_tau_updates = min_tau_updates
  )
  ref_trace <- ref_fit$trace
  disc_trace <- disc_fit$trace
  if (nrow(ref_trace)) ref_trace$component <- "reference"
  if (nrow(disc_trace)) disc_trace$component <- "discrepancy"
  trace <- app_bind_rows_fill(list(ref_trace, disc_trace))
  if (nrow(trace)) {
    trace$candidate_id <- as.character(rhs_row$candidate_id[[1L]] %||% "part2_candidate")
    trace$rhs_candidate_id <- as.character(rhs_row$rhs_candidate_id[[1L]] %||% trace$candidate_id[[1L]])
  }
  ref_coef <- app_glofas_normal_rhs_coefficient_table(ref_fit, design$reference$feature_info)
  disc_coef <- app_glofas_normal_rhs_coefficient_table(disc_fit, design$discrepancy$feature_info)
  ref_coef$component <- "reference"
  disc_coef$component <- "discrepancy"
  activity <- app_bind_rows_fill(list(
    transform(app_glofas_normal_rhs_activity_summary(ref_coef), component = "reference"),
    transform(app_glofas_normal_rhs_activity_summary(disc_coef), component = "discrepancy")
  ))
  app_glofas_normal_part2_score_from_fits(
    design = design,
    split = split,
    reference_fit = ref_fit,
    discrepancy_fit = disc_fit,
    candidate_row = rhs_row,
    method = "normal_rhs_vb_two_component_bridge",
    started = started,
    rhs_tau0_reference = tau0_reference,
    rhs_tau0_discrepancy = tau0_discrepancy,
    trace = trace,
    activity = activity
  )
}

app_glofas_normal_part2_candidate_template <- function() {
  defaults <- app_glofas_normal_part2_default_values()
  data.frame(
    candidate_id = "part2_template_D1_n300_L360_a050_r090",
    ref_n_vector = "300",
    disc_n_vector = "300",
    ref_m = 360L,
    disc_m = 360L,
    ref_output_lag_max = 360L,
    disc_output_lag_max = 360L,
    ref_covariate_lag_max = 360L,
    disc_covariate_lag_max = 360L,
    ref_washout = defaults$washout,
    disc_washout = defaults$washout,
    ref_alpha = 0.50,
    disc_alpha = 0.50,
    ref_rho = 0.90,
    disc_rho = 0.90,
    ref_seed = defaults$reference_seed,
    disc_seed = defaults$discrepancy_seed,
    ridge_tau2 = defaults$ridge_tau2,
    intercept_var = defaults$intercept_var,
    sigma_a = defaults$sigma_a,
    sigma_b = defaults$sigma_b,
    validation_n = defaults$validation_n,
    rhs_tau0_reference = 1.0,
    rhs_tau0_discrepancy = 1.0,
    rhs_max_iter = 100L,
    rhs_min_iter = 30L,
    rhs_tol = 1.0e-4,
    rhs_update_every = 1L,
    rhs_freeze_tau_warmup_iters = 0L,
    rhs_min_tau_updates = 0L,
    stringsAsFactors = FALSE
  )
}
