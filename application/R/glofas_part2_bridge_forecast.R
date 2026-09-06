# Fixed-origin Part 2 bridge forecasts for the verified GloFAS discrepancy model.
#
# Part 2 forecasts the observed discrepancy
#   d_g(t) = retrospective GloFAS(t) - USGS(t)
# and reports the corrected USGS path
#   corrected(t) = retrospective GloFAS(t) - predicted discrepancy(t).
# The winning disc_covars contract uses discrepancy lags and realized ppt/soil
# covariates only. Future discrepancy lags are recursive model outputs.

app_glofas_part2_bridge_quantile_grid <- function() {
  if (exists("app_glofas_part1_quantile_grid", mode = "function", inherits = TRUE)) {
    return(app_glofas_part1_quantile_grid())
  }
  c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95)
}

app_glofas_part2_bridge_slug <- function(x) {
  gsub("[^A-Za-z0-9_]+", "_", as.character(x))
}

app_glofas_part2_bridge_tau_slug <- function(tau) {
  paste0("q", gsub("\\.", "p", sprintf("%.2f", as.numeric(tau))))
}

app_glofas_part2_bridge_bool <- function(x) {
  if (is.logical(x)) return(isTRUE(x[[1L]]))
  tolower(as.character(x[[1L]] %||% "")) %in% c("true", "t", "1", "yes", "y")
}

app_glofas_part2_bridge_resolve <- function(path, must_work = FALSE) {
  app_glofas_oracle_resolve_repo_path(path, must_work = must_work)
}

app_glofas_part2_bridge_scores_path <- function(rhs_runtime_root) {
  file.path(app_glofas_part2_bridge_resolve(rhs_runtime_root, must_work = TRUE), "tables", "part2_rhs_scores_latest.csv")
}

app_glofas_part2_bridge_selected_rhs_row <- function(
  rhs_runtime_root,
  rhs_candidate_id = NULL,
  candidate_id = NULL,
  rank = 1L,
  score_path = NULL
) {
  score_path <- score_path %||% app_glofas_part2_bridge_scores_path(rhs_runtime_root)
  score_path <- app_glofas_part2_bridge_resolve(score_path, must_work = TRUE)
  scores <- app_read_csv(score_path)
  app_check_required_columns(
    scores,
    c("rhs_candidate_id", "candidate_id", "disc_input_contract", "corrected_valid_mean_crps", "status"),
    "Part 2 RHS score table"
  )
  if (!is.null(rhs_candidate_id) && nzchar(as.character(rhs_candidate_id))) {
    scores <- scores[as.character(scores$rhs_candidate_id) == as.character(rhs_candidate_id), , drop = FALSE]
  }
  if (!is.null(candidate_id) && nzchar(as.character(candidate_id))) {
    scores <- scores[as.character(scores$candidate_id) == as.character(candidate_id), , drop = FALSE]
  }
  scores <- scores[as.character(scores$status) == "completed", , drop = FALSE]
  scores$corrected_valid_mean_crps <- suppressWarnings(as.numeric(scores$corrected_valid_mean_crps))
  scores$discrepancy_valid_mean_crps <- suppressWarnings(as.numeric(scores$discrepancy_valid_mean_crps %||% NA_real_))
  scores <- scores[order(scores$corrected_valid_mean_crps, scores$discrepancy_valid_mean_crps, scores$rhs_candidate_id), , drop = FALSE]
  rank <- as.integer(rank)
  if (!nrow(scores) || !is.finite(rank) || rank < 1L || rank > nrow(scores)) {
    stop("No completed Part 2 RHS score row matches the requested winner.", call. = FALSE)
  }
  out <- scores[rank, , drop = FALSE]
  attr(out, "source_path") <- score_path
  out
}

app_glofas_part2_bridge_validate_disc_covars_contract <- function(row, strict_winner = FALSE) {
  row <- row[1L, , drop = FALSE]
  violations <- character()
  add <- function(msg) violations <<- c(violations, msg)
  if (!identical(as.character(row$disc_input_contract[[1L]]), "disc_covars")) add("disc_input_contract is not disc_covars")
  if (!app_glofas_part2_bridge_bool(row$disc_include_covariates)) add("disc_include_covariates is not TRUE")
  if (app_glofas_part2_bridge_bool(row$disc_include_glofas_lags)) add("disc_include_glofas_lags is TRUE")
  if (app_glofas_part2_bridge_bool(row$disc_include_usgs_lags)) add("disc_include_usgs_lags is TRUE")
  if (as.integer(row$disc_output_lag_max[[1L]]) != 360L) add("disc_output_lag_max is not 360")
  if (as.integer(row$disc_covariate_lag_max[[1L]]) != 180L) add("disc_covariate_lag_max is not 180")
  if (as.integer(row$disc_auxiliary_lag_max[[1L]] %||% 360L) != 360L) add("disc_auxiliary_lag_max is not 360")
  if (as.integer(row$disc_D[[1L]] %||% 1L) != 1L) add("disc_D is not 1")
  if (isTRUE(strict_winner)) {
    if (!identical(as.character(row$disc_n_vector[[1L]]), "2500")) add("disc_n_vector is not 2500")
    if (abs(as.numeric(row$disc_alpha[[1L]]) - 0.8) > 1.0e-12) add("disc_alpha is not 0.8")
    if (abs(as.numeric(row$disc_rho[[1L]]) - 0.7) > 1.0e-12) add("disc_rho is not 0.7")
  }
  if (length(violations)) {
    stop(sprintf("Part 2 discrepancy input contract failed: %s", paste(violations, collapse = "; ")), call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_part2_bridge_candidate_from_rhs_row <- function(row) {
  row <- row[1L, , drop = FALSE]
  get <- function(name, default = NA) {
    if (name %in% names(row)) row[[name]][[1L]] else default
  }
  out <- data.frame(
    rhs_candidate_id = as.character(get("rhs_candidate_id", "")),
    candidate_id = as.character(get("candidate_id", "part2_discrepancy_candidate")),
    D = as.integer(get("disc_D", 1L)),
    n_vector = as.character(get("disc_n_vector", get("n_vector", "2500"))),
    n_tilde = as.character(get("disc_n_tilde", NA_character_)),
    lag_id = sprintf("D%s_X%s", as.integer(get("disc_output_lag_max", 360L)), as.integer(get("disc_covariate_lag_max", 180L))),
    m = as.integer(get("disc_m", get("m", 360L))),
    output_lag_max = as.integer(get("disc_output_lag_max", 360L)),
    covariate_lag_max = as.integer(get("disc_covariate_lag_max", 180L)),
    alpha = as.numeric(get("disc_alpha", get("alpha", 0.8))),
    rho = as.numeric(get("disc_rho", get("rho", 0.7))),
    seed = as.integer(get("disc_seed", get("seed", 20261521L))),
    washout = as.integer(get("disc_washout", get("washout", 500L))),
    ridge_tau2 = as.numeric(get("ridge_tau2", 10000)),
    intercept_var = as.numeric(get("intercept_var", 1.0e6)),
    sigma_a = as.numeric(get("sigma_a", 2)),
    sigma_b = as.numeric(get("sigma_b", 1)),
    validation_n = as.integer(get("validation_n", 365L)),
    rhs_tau0 = as.numeric(get("rhs_tau0_discrepancy", get("rhs_tau0", 1))),
    rhs_max_iter = as.integer(get("rhs_max_iter", 100L)),
    rhs_min_iter = as.integer(get("rhs_min_iter", 30L)),
    rhs_tol = as.numeric(get("rhs_tol", 1.0e-4)),
    rhs_update_every = as.integer(get("rhs_update_every", 1L)),
    rhs_freeze_tau_warmup_iters = as.integer(get("rhs_freeze_tau_warmup_iters", 0L)),
    rhs_min_tau_updates = as.integer(get("rhs_min_tau_updates", 0L)),
    part2_rhs_candidate_id = as.character(get("rhs_candidate_id", "")),
    part2_source_candidate_id = as.character(get("candidate_id", "")),
    part2_target_contract = "observed_discrepancy_retrospective_glofas_minus_usgs",
    part2_input_contract = "disc_covars",
    stringsAsFactors = FALSE
  )
  app_glofas_oracle_complete_part1_candidate_row(out)
}

app_glofas_part2_bridge_validate_design_contract <- function(fitted) {
  spec <- fitted$design$design_meta$reservoir_input_spec %||% NULL
  if (is.null(spec)) stop("Discrepancy design lacks a reservoir input spec.", call. = FALSE)
  out_lags <- sort(unique(as.integer(unlist(spec$output_lags %||% integer(), use.names = FALSE))))
  cov_lags <- sort(unique(as.integer(unlist(spec$covariate_lags %||% integer(), use.names = FALSE))))
  columns <- as.character(spec$columns %||% character())
  if (!identical(out_lags, seq_len(360L))) stop("Discrepancy output lags must be exactly 1:360.", call. = FALSE)
  if (!identical(cov_lags, 0:180)) stop("Discrepancy covariate lags must be exactly 0:180.", call. = FALSE)
  if (!isTRUE(spec$uses_covariates %||% FALSE)) stop("disc_covars forecast must use realized ppt/soil covariates.", call. = FALSE)
  if (isTRUE(spec$uses_auxiliary_lags %||% FALSE)) stop("disc_covars forecast must not use auxiliary USGS/GloFAS lags.", call. = FALSE)
  if (any(grepl("usgs|glofas", columns, ignore.case = TRUE))) {
    stop("disc_covars reservoir inputs contain direct USGS/GloFAS lag columns.", call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_part2_bridge_object_path <- function(rhs_runtime_root, object_name) {
  file.path(app_glofas_part2_bridge_resolve(rhs_runtime_root, must_work = TRUE), "objects", object_name)
}

app_glofas_part2_bridge_rhs_compact_path <- function(rhs_runtime_root, rhs_candidate_id) {
  app_glofas_part2_bridge_object_path(rhs_runtime_root, paste0(rhs_candidate_id, "_normal_part2_rhs_compact.rds"))
}

app_glofas_part2_bridge_warm_start_path <- function(rhs_runtime_root, row) {
  path <- as.character(row$warm_start_path[[1L]] %||% "")
  if (nzchar(path) && file.exists(app_glofas_part2_bridge_resolve(path, must_work = FALSE))) {
    return(app_glofas_part2_bridge_resolve(path, must_work = TRUE))
  }
  app_glofas_part2_bridge_object_path(rhs_runtime_root, paste0(as.character(row$candidate_id[[1L]]), "_part2_ridge_warm_start.rds"))
}

app_glofas_part2_bridge_load_retained_fit <- function(rhs_runtime_root, row, method = c("ridge", "rhs")) {
  method <- match.arg(method)
  row <- row[1L, , drop = FALSE]
  if (identical(method, "ridge")) {
    path <- app_glofas_part2_bridge_warm_start_path(rhs_runtime_root, row)
    warm <- readRDS(path)
    if (!is.list(warm) || is.null(warm$discrepancy) || is.null(warm$discrepancy$fit)) {
      stop(sprintf("Part 2 ridge warm-start lacks discrepancy fit: %s", path), call. = FALSE)
    }
    fit <- warm$discrepancy$fit
    fit$type <- fit$type %||% "normal_ridge"
    fit$uses_vb <- FALSE
    fit$iterations <- as.integer(fit$iterations %||% 0L)
    fit$converged <- TRUE
    fit$retained_object_role <- "part2_ridge_warm_start_discrepancy_fit"
  } else {
    path <- app_glofas_part2_bridge_rhs_compact_path(rhs_runtime_root, as.character(row$rhs_candidate_id[[1L]]))
    compact <- readRDS(path)
    if (!is.list(compact) || is.null(compact$discrepancy_fit)) {
      stop(sprintf("Part 2 RHS compact object lacks discrepancy_fit: %s", path), call. = FALSE)
    }
    fit <- compact$discrepancy_fit
    fit$type <- fit$type %||% "normal_rhs_vb"
    fit$uses_vb <- TRUE
    fit$retained_object_role <- "part2_rhs_compact_discrepancy_fit"
  }
  p <- as.integer(fit$p %||% length(fit$beta_mean))
  if (!is.finite(p) || p < 1L || length(fit$beta_mean) != p) {
    stop("Retained discrepancy fit has incompatible beta dimension.", call. = FALSE)
  }
  if (is.null(fit$beta_var_diag) && is.null(fit$beta_cov) && is.null(fit$precision_inv)) {
    stop("Retained discrepancy fit lacks variance information for predictive scoring.", call. = FALSE)
  }
  fit$p <- p
  fit$fit_object_path <- path
  fit
}

app_glofas_part2_bridge_prepare_discrepancy_fitted <- function(
  base_cfg,
  rhs_runtime_root,
  rhs_row,
  method = c("ridge", "rhs"),
  origin_date = NULL,
  horizon_days = 30L,
  root_candidates = NULL,
  strict_winner = TRUE
) {
  method <- match.arg(method)
  app_glofas_part2_bridge_validate_disc_covars_contract(rhs_row, strict_winner = strict_winner)
  candidate <- app_glofas_part2_bridge_candidate_from_rhs_row(rhs_row)
  bundle <- app_glofas_oracle_prepare_panel_bundle(
    cfg = base_cfg,
    origin_date = origin_date,
    horizon_days = horizon_days,
    target = "discrepancy",
    root_candidates = root_candidates
  )
  design <- app_glofas_oracle_build_part1_design(
    base_cfg = base_cfg,
    candidate_row = candidate,
    panel_bundle = bundle
  )
  fit <- app_glofas_part2_bridge_load_retained_fit(rhs_runtime_root, rhs_row, method = method)
  if (ncol(design$X) != fit$p) {
    stop(
      sprintf("Retained fit dimension mismatch: rebuilt discrepancy design has %d columns but fit has %d.", ncol(design$X), fit$p),
      call. = FALSE
    )
  }
  names(fit$beta_mean) <- colnames(design$X)
  fitted <- list(
    method = method,
    candidate_row = candidate,
    part2_rhs_row = rhs_row,
    base_cfg = base_cfg,
    bundle = bundle,
    design = design,
    fit = fit,
    ridge_fit = if (identical(method, "ridge")) fit else NULL,
    warm_start = NULL,
    fit_runtime_seconds = 0,
    fit_reused = TRUE,
    fit_object_path = fit$fit_object_path,
    fit_reuse_contract = sprintf("retained_%s_discrepancy_readout_reused_without_refit", method)
  )
  app_glofas_part2_bridge_validate_design_contract(fitted)
  fitted
}

app_glofas_part2_bridge_relabel_audit <- function(audit) {
  if (is.null(audit) || !nrow(audit)) return(audit)
  is_y <- as.character(audit$input_block %||% "") == "output_lag"
  audit$role[is_y & audit$role == "historical_usgs"] <- "historical_discrepancy"
  audit$role[is_y & audit$role == "latent_future_usgs"] <- "latent_future_discrepancy"
  audit$source[is_y & audit$source == "observed_usgs_history"] <- "observed_discrepancy_history"
  audit$source[is_y & audit$source == "recursive_latent_path"] <- "recursive_discrepancy_path"
  audit
}

app_glofas_part2_bridge_validate_no_future_usgs_leakage <- function(audit) {
  if (is.null(audit) || !nrow(audit)) return(invisible(TRUE))
  future <- grepl("future", as.character(audit$role %||% ""), ignore.case = TRUE)
  bad <- future & grepl("usgs", as.character(audit$role %||% ""), ignore.case = TRUE)
  if (any(bad, na.rm = TRUE)) {
    stop("Part 2 future input audit still contains a future-USGS role.", call. = FALSE)
  }
  cols <- c("input_block", "variable", "source")
  cols <- cols[cols %in% names(audit)]
  if (length(cols)) {
    bad_direct <- audit$input_block == "output_lag" &
      grepl("usgs|glofas", apply(audit[, cols, drop = FALSE], 1L, paste, collapse = " "), ignore.case = TRUE) &
      !grepl("discrepancy", apply(audit[, cols, drop = FALSE], 1L, paste, collapse = " "), ignore.case = TRUE)
    if (any(bad_direct, na.rm = TRUE)) {
      stop("Part 2 output-lag audit contains direct USGS/GloFAS lag references.", call. = FALSE)
    }
  }
  invisible(TRUE)
}

app_glofas_part2_bridge_reference_truth <- function(base_cfg, bundle) {
  manifest <- bundle$manifest
  root_candidates <- bundle$root_candidates
  ref <- app_glofas_oracle_load_reference(base_cfg, manifest, root_candidates = root_candidates)
  ret <- app_glofas_oracle_load_glofas_retrospective(base_cfg, manifest, root_candidates = root_candidates)
  paired <- merge(ref, ret, by = "date", all = FALSE, sort = FALSE)
  paired <- paired[order(paired$date), , drop = FALSE]
  paired$observed_usgs <- as.numeric(paired$y_transformed)
  paired$retrospective_glofas <- as.numeric(paired$g_transformed)
  paired$observed_discrepancy <- paired$retrospective_glofas - paired$observed_usgs
  paired[, c("date", "observed_usgs", "retrospective_glofas", "observed_discrepancy"), drop = FALSE]
}

app_glofas_part2_bridge_default_diagnostic_origin <- function(base_cfg, horizon_days = 30L, root_candidates = NULL) {
  horizon_days <- as.integer(horizon_days)
  if (!is.finite(horizon_days) || horizon_days < 1L) stop("horizon_days must be positive.", call. = FALSE)
  manifest <- app_glofas_oracle_read_manifest(base_cfg, root_candidates = root_candidates)
  ref <- app_glofas_oracle_load_reference(base_cfg, manifest, root_candidates = root_candidates)
  ret <- app_glofas_oracle_load_glofas_retrospective(base_cfg, manifest, root_candidates = root_candidates)
  paired <- merge(ref, ret, by = "date", all = FALSE, sort = FALSE)
  paired <- paired[is.finite(paired$y_transformed) & is.finite(paired$g_transformed), , drop = FALSE]
  if (nrow(paired) <= horizon_days) stop("Not enough paired GloFAS/USGS rows for the requested diagnostic horizon.", call. = FALSE)
  max(as.Date(paired$date), na.rm = TRUE) - horizon_days
}

app_glofas_part2_bridge_augment_normal_path <- function(fitted, forecast, truth_table) {
  base_path <- app_glofas_oracle_path_table(fitted, forecast, future_truth = fitted$bundle$future_truth)
  idx <- match(as.Date(base_path$date), as.Date(truth_table$date))
  g <- as.numeric(truth_table$retrospective_glofas[idx])
  y <- as.numeric(truth_table$observed_usgs[idx])
  d <- as.numeric(truth_table$observed_discrepancy[idx])
  data.frame(
    date = as.Date(base_path$date),
    segment = base_path$segment,
    observed_usgs = y,
    retrospective_glofas = g,
    observed_discrepancy = d,
    pred_discrepancy_mean = base_path$pred_mean,
    pred_discrepancy_median = base_path$pred_median,
    pred_discrepancy_sd = base_path$pred_sd,
    pred_discrepancy_q025 = base_path$ci95_lower,
    pred_discrepancy_q975 = base_path$ci95_upper,
    corrected_pred_mean = g - base_path$pred_mean,
    corrected_pred_median = g - base_path$pred_median,
    corrected_pred_sd = base_path$pred_sd,
    corrected_pred_q025 = g - base_path$ci95_upper,
    corrected_pred_q975 = g - base_path$ci95_lower,
    forecast_mode = base_path$forecast_mode,
    stringsAsFactors = FALSE
  )
}

app_glofas_part2_bridge_score_normal <- function(path_table, forecast = NULL) {
  fut <- path_table[path_table$segment == "oracle_realized_forecast", , drop = FALSE]
  keep <- is.finite(fut$observed_usgs) & is.finite(fut$observed_discrepancy) & is.finite(fut$retrospective_glofas)
  fut <- fut[keep, , drop = FALSE]
  if (!nrow(fut)) return(list(pointwise = data.frame(), by_block = data.frame(), aggregate = data.frame()))
  draw_idx <- match(as.Date(fut$date), as.Date(forecast$future_dates %||% fut$date))
  if (!is.null(forecast$forecast_draws)) {
    disc_draws <- as.matrix(forecast$forecast_draws[draw_idx, , drop = FALSE])
    corrected_draws <- fut$retrospective_glofas - disc_draws
    disc_crps <- app_glofas_oracle_empirical_crps(fut$observed_discrepancy, disc_draws)
    corrected_crps <- app_glofas_oracle_empirical_crps(fut$observed_usgs, corrected_draws)
  } else {
    disc_crps <- app_glofas_normal_crps(fut$observed_discrepancy, fut$pred_discrepancy_mean, fut$pred_discrepancy_sd)
    corrected_crps <- app_glofas_normal_crps(fut$observed_usgs, fut$corrected_pred_mean, fut$corrected_pred_sd)
  }
  pointwise <- data.frame(
    date = fut$date,
    horizon = seq_len(nrow(fut)),
    observed_usgs = fut$observed_usgs,
    retrospective_glofas = fut$retrospective_glofas,
    observed_discrepancy = fut$observed_discrepancy,
    pred_discrepancy_mean = fut$pred_discrepancy_mean,
    corrected_pred_mean = fut$corrected_pred_mean,
    discrepancy_crps = disc_crps,
    corrected_crps = corrected_crps,
    discrepancy_abs_error = abs(fut$pred_discrepancy_mean - fut$observed_discrepancy),
    corrected_abs_error = abs(fut$corrected_pred_mean - fut$observed_usgs),
    discrepancy_squared_error = (fut$pred_discrepancy_mean - fut$observed_discrepancy)^2,
    corrected_squared_error = (fut$corrected_pred_mean - fut$observed_usgs)^2,
    stringsAsFactors = FALSE
  )
  summarize <- function(x, prefix = "") {
    out <- data.frame(
      mean_crps = mean(x$corrected_crps, na.rm = TRUE),
      discrepancy_mean_crps = mean(x$discrepancy_crps, na.rm = TRUE),
      mae = mean(x$corrected_abs_error, na.rm = TRUE),
      discrepancy_mae = mean(x$discrepancy_abs_error, na.rm = TRUE),
      rmse = sqrt(mean(x$corrected_squared_error, na.rm = TRUE)),
      discrepancy_rmse = sqrt(mean(x$discrepancy_squared_error, na.rm = TRUE)),
      stringsAsFactors = FALSE
    )
    if (nzchar(prefix)) names(out) <- paste0(prefix, names(out))
    out
  }
  blocks <- c(7L, 14L, 30L)
  by_block <- app_bind_rows_fill(lapply(blocks, function(h) {
    idx <- seq_len(min(h, nrow(pointwise)))
    cbind(data.frame(horizon_block_days = h, n_scored = length(idx), stringsAsFactors = FALSE), summarize(pointwise[idx, , drop = FALSE]))
  }))
  list(
    pointwise = pointwise,
    by_block = by_block,
    aggregate = summarize(pointwise, prefix = "future_corrected_")
  )
}

app_glofas_part2_bridge_screen_score_origin <- function(base_cfg, rhs_row, root_candidates = NULL) {
  if ("valid_end_date" %in% names(rhs_row) && nzchar(as.character(rhs_row$valid_end_date[[1L]] %||% ""))) {
    return(as.Date(rhs_row$valid_end_date[[1L]]))
  }
  cutoff <- app_glofas_oracle_cutoff_row(base_cfg, root_candidates = root_candidates)
  as.Date(cutoff$train_end[[1L]])
}

app_glofas_part2_bridge_score_reproduction <- function(
  base_cfg,
  rhs_runtime_root,
  rhs_row,
  method = c("ridge", "rhs"),
  root_candidates = NULL
) {
  method <- match.arg(method)
  fitted <- app_glofas_part2_bridge_prepare_discrepancy_fitted(
    base_cfg = base_cfg,
    rhs_runtime_root = rhs_runtime_root,
    rhs_row = rhs_row,
    method = method,
    origin_date = app_glofas_part2_bridge_screen_score_origin(base_cfg, rhs_row, root_candidates = root_candidates),
    horizon_days = 1L,
    root_candidates = root_candidates,
    strict_winner = TRUE
  )
  validation_n <- as.integer(rhs_row$validation_n[[1L]] %||% 365L)
  split <- app_glofas_normal_part1_validation_split(length(fitted$design$dates), validation_n)
  valid_idx <- split$valid_idx
  pred <- app_glofas_normal_predict(fitted$fit, fitted$design$X[valid_idx, , drop = FALSE], chunk_size = 64L)
  dates <- as.Date(fitted$design$dates[valid_idx])
  truth <- app_glofas_part2_bridge_reference_truth(base_cfg, fitted$bundle)
  idx <- match(dates, truth$date)
  observed_d <- as.numeric(truth$observed_discrepancy[idx])
  observed_y <- as.numeric(truth$observed_usgs[idx])
  g <- as.numeric(truth$retrospective_glofas[idx])
  corrected_mean <- g - pred$mean
  compact <- list(
    discrepancy_valid_mean_crps = mean(app_glofas_normal_crps(observed_d, pred$mean, pred$sd), na.rm = TRUE),
    corrected_valid_mean_crps = mean(app_glofas_normal_crps(observed_y, corrected_mean, pred$sd), na.rm = TRUE),
    discrepancy_valid_mae = mean(abs(pred$mean - observed_d), na.rm = TRUE),
    corrected_valid_mae = mean(abs(corrected_mean - observed_y), na.rm = TRUE)
  )
  rows <- list()
  add_row <- function(check, value, expected, status = NULL, note = "", source_path = NA_character_, max_abs_diff = NA_real_) {
    diff <- abs(as.numeric(value) - as.numeric(expected))
    if (is.null(status)) status <- if (is.finite(diff) && diff <= 1.0e-8) "pass" else "not_exact_or_unavailable"
    rows[[length(rows) + 1L]] <<- data.frame(
      check = check,
      value = as.numeric(value),
      rhs_screen_expected = as.numeric(expected),
      abs_diff = diff,
      max_abs_diff = as.numeric(max_abs_diff),
      status = status,
      note = note,
      source_path = as.character(source_path),
      stringsAsFactors = FALSE
    )
  }
  for (nm in names(compact)) {
    source_col <- if (identical(method, "ridge")) paste0("ridge_", nm) else nm
    expected <- suppressWarnings(as.numeric(rhs_row[[source_col]][[1L]] %||% NA_real_))
    status <- NULL
    note <- ""
    if (grepl("crps", nm) && identical(method, "rhs")) {
      status <- "diagnostic_compact_diagonal_only"
      note <- "Compact RHS artifact omits full beta covariance; diagonal predictive CRPS is not expected to match the original screen CRPS exactly."
    }
    add_row(paste0("rebuilt_compact_", nm), compact[[nm]], expected, status = status, note = note)
  }

  if (identical(method, "rhs")) {
    detail_path <- file.path(
      app_glofas_part2_bridge_resolve(rhs_runtime_root, must_work = TRUE),
      "scores",
      paste0(as.character(rhs_row$rhs_candidate_id[[1L]]), "_rhs_validation_detail.csv")
    )
    if (file.exists(detail_path)) {
      detail <- app_read_csv(detail_path)
      detail$date <- as.Date(detail$date)
      detail <- detail[match(dates, detail$date), , drop = FALSE]
      if (nrow(detail) == length(dates) && all(as.Date(detail$date) == dates)) {
        add_row(
          "stored_detail_discrepancy_pred_mean_max_abs_diff",
          0,
          0,
          status = if (max(abs(as.numeric(detail$discrepancy_pred_mean) - pred$mean), na.rm = TRUE) <= 1.0e-8) "pass" else "fail",
          note = "Rebuilt retained mean path compared date-by-date to the original RHS validation detail.",
          source_path = detail_path,
          max_abs_diff = max(abs(as.numeric(detail$discrepancy_pred_mean) - pred$mean), na.rm = TRUE)
        )
        add_row(
          "stored_detail_corrected_pred_mean_max_abs_diff",
          0,
          0,
          status = if (max(abs(as.numeric(detail$corrected_pred_mean) - corrected_mean), na.rm = TRUE) <= 1.0e-8) "pass" else "fail",
          note = "Corrected mean path is retrospective GloFAS minus rebuilt discrepancy mean.",
          source_path = detail_path,
          max_abs_diff = max(abs(as.numeric(detail$corrected_pred_mean) - corrected_mean), na.rm = TRUE)
        )
        add_row(
          "stored_detail_corrected_valid_mean_crps_vs_score_row",
          mean(as.numeric(detail$corrected_crps), na.rm = TRUE),
          suppressWarnings(as.numeric(rhs_row$corrected_valid_mean_crps[[1L]])),
          source_path = detail_path
        )
        add_row(
          "stored_detail_discrepancy_valid_mean_crps_vs_score_row",
          mean(as.numeric(detail$discrepancy_crps), na.rm = TRUE),
          suppressWarnings(as.numeric(rhs_row$discrepancy_valid_mean_crps[[1L]])),
          source_path = detail_path
        )
      }
    }
  }
  app_bind_rows_fill(rows)
}

app_glofas_part2_bridge_normal_forecast <- function(
  base_cfg,
  rhs_runtime_root,
  rhs_row,
  method = c("ridge", "rhs"),
  origin_date = NULL,
  horizon_days = 30L,
  forecast_mode = c("plugin_mean_recursive", "draw_recursive"),
  n_draws = 500L,
  seed = 20260904L,
  retain_draws = FALSE,
  forecast_backend = c("auto", "cpp", "r"),
  progress_every = NULL,
  root_candidates = NULL,
  strict_winner = TRUE,
  require_future_retrospective = FALSE
) {
  method <- match.arg(method)
  forecast_mode <- match.arg(forecast_mode)
  forecast_backend <- match.arg(forecast_backend)
  if (is.null(origin_date)) {
    origin_date <- app_glofas_part2_bridge_default_diagnostic_origin(
      base_cfg,
      horizon_days = horizon_days,
      root_candidates = root_candidates
    )
  }
  fitted <- app_glofas_part2_bridge_prepare_discrepancy_fitted(
    base_cfg = base_cfg,
    rhs_runtime_root = rhs_runtime_root,
    rhs_row = rhs_row,
    method = method,
    origin_date = origin_date,
    horizon_days = horizon_days,
    root_candidates = root_candidates,
    strict_winner = strict_winner
  )
  names(fitted$fit$beta_mean) <- colnames(fitted$design$X)
  app_glofas_part2_bridge_validate_design_contract(fitted)
  cov_timeline <- attr(fitted$bundle$panel, "model_covariate_timeline", exact = TRUE)
  started <- Sys.time()
  forecast <- if (identical(forecast_mode, "draw_recursive")) {
    app_glofas_oracle_draw_recursive_forecast(
      fitted = fitted,
      future_dates = fitted$bundle$future_dates,
      covariate_timeline = cov_timeline,
      n_draws = n_draws,
      seed = seed,
      forecast_backend = forecast_backend,
      progress_every = progress_every
    )
  } else {
    app_glofas_oracle_recursive_forecast(
      fitted = fitted,
      future_dates = fitted$bundle$future_dates,
      covariate_timeline = cov_timeline,
      forecast_backend = forecast_backend
    )
  }
  forecast$future_input_audit <- app_glofas_part2_bridge_relabel_audit(forecast$future_input_audit)
  app_glofas_part2_bridge_validate_no_future_usgs_leakage(forecast$future_input_audit)
  truth <- app_glofas_part2_bridge_reference_truth(base_cfg, fitted$bundle)
  future_g <- truth$retrospective_glofas[match(fitted$bundle$future_dates, truth$date)]
  if (isTRUE(require_future_retrospective) && any(!is.finite(future_g))) {
    stop("Retrospective GloFAS is required for every Part 2 corrected forecast date.", call. = FALSE)
  }
  path_table <- app_glofas_part2_bridge_augment_normal_path(fitted, forecast, truth)
  scores <- app_glofas_part2_bridge_score_normal(path_table, forecast)
  score_reproduction <- app_glofas_part2_bridge_score_reproduction(
    base_cfg = base_cfg,
    rhs_runtime_root = rhs_runtime_root,
    rhs_row = rhs_row,
    method = method,
    root_candidates = root_candidates
  )
  list(
    target = "discrepancy",
    corrected_target = "usgs",
    diagnostic_type = "part2_fixed_origin_discrepancy_bridge_forecast",
    fitted = fitted,
    part2_rhs_row = rhs_row,
    forecast = forecast,
    path_table = path_table,
    scores = scores,
    score_reproduction = score_reproduction,
    forecast_mode = forecast_mode,
    origin_date = as.Date(fitted$bundle$cutoff$train_end[[1L]]),
    effective_horizon = fitted$bundle$effective_horizon,
    max_covariate_horizon = fitted$bundle$max_covariate_horizon,
    max_score_horizon = fitted$bundle$max_score_horizon,
    forecast_runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    retain_draws = retain_draws,
    future_retrospective_available = all(is.finite(future_g)),
    future_scoring_status = if (all(is.finite(future_g))) "available" else "unavailable_missing_future_retrospective_glofas"
  )
}

app_glofas_part2_bridge_quantile_transform_path <- function(result, base_cfg) {
  truth <- app_glofas_part2_bridge_reference_truth(base_cfg, result$prepared$bundle)
  x <- result$path_table
  idx <- match(as.Date(x$date), as.Date(truth$date))
  out <- data.frame(
    date = as.Date(x$date),
    segment = x$segment,
    discrepancy_tau = as.numeric(x$tau),
    corrected_tau = 1 - as.numeric(x$tau),
    observed_usgs = as.numeric(truth$observed_usgs[idx]),
    retrospective_glofas = as.numeric(truth$retrospective_glofas[idx]),
    observed_discrepancy = as.numeric(truth$observed_discrepancy[idx]),
    discrepancy_qhat = as.numeric(x$qhat),
    corrected_qhat = as.numeric(truth$retrospective_glofas[idx]) - as.numeric(x$qhat),
    stringsAsFactors = FALSE
  )
  out
}

app_glofas_part2_bridge_score_quantile <- function(path_table) {
  fut <- path_table[path_table$segment == "oracle_realized_forecast", , drop = FALSE]
  keep <- is.finite(fut$observed_discrepancy) & is.finite(fut$observed_usgs) & is.finite(fut$retrospective_glofas)
  fut <- fut[keep, , drop = FALSE]
  if (!nrow(fut)) return(list(pointwise = data.frame(), aggregate = data.frame()))
  fut$discrepancy_check_loss <- app_glofas_part1_quantile_check_loss(
    fut$observed_discrepancy,
    fut$discrepancy_qhat,
    fut$discrepancy_tau
  )
  fut$corrected_check_loss <- app_glofas_part1_quantile_check_loss(
    fut$observed_usgs,
    fut$corrected_qhat,
    fut$corrected_tau
  )
  aggregate <- app_bind_rows_fill(lapply(split(fut, sprintf("%.2f", fut$discrepancy_tau)), function(x) {
    data.frame(
      discrepancy_tau = unique(x$discrepancy_tau)[[1L]],
      corrected_tau = unique(x$corrected_tau)[[1L]],
      n_scores = nrow(x),
      discrepancy_forecast_check_loss_mean = mean(x$discrepancy_check_loss, na.rm = TRUE),
      corrected_forecast_check_loss_mean = mean(x$corrected_check_loss, na.rm = TRUE),
      corrected_mae = mean(abs(x$corrected_qhat - x$observed_usgs), na.rm = TRUE),
      discrepancy_mae = mean(abs(x$discrepancy_qhat - x$observed_discrepancy), na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))
  list(pointwise = fut, aggregate = aggregate)
}

app_glofas_part2_bridge_quantile_forecast <- function(
  base_cfg,
  rhs_runtime_root,
  rhs_row,
  model_family = c("independent_al", "independent_exal", "joint_al", "joint_exal"),
  tau = NULL,
  origin_date = NULL,
  horizon_days = 30L,
  max_iter = 100L,
  tol = 0.01,
  min_iter = 30L,
  tau0 = NULL,
  zeta2 = Inf,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_sd = Inf,
  max_dense_dim = NULL,
  rhs_vb_inner = 5L,
  exal_method_id = "VB1_structured_v",
  exal_prefit_max_iter = 25L,
  joint_backend = "auto",
  freeze_beta_warmup_iters = 0L,
  min_beta_updates = 0L,
  init_fit_path = NULL,
  init_fit_paths = NULL,
  progress_path = NULL,
  progress_every = 1L,
  forecast_backend = c("auto", "cpp", "r"),
  root_candidates = NULL,
  strict_winner = TRUE
) {
  model_family <- match.arg(model_family)
  forecast_backend <- match.arg(forecast_backend)
  if (is.null(origin_date)) {
    origin_date <- app_glofas_part2_bridge_default_diagnostic_origin(
      base_cfg,
      horizon_days = horizon_days,
      root_candidates = root_candidates
    )
  }
  app_glofas_part2_bridge_validate_disc_covars_contract(rhs_row, strict_winner = strict_winner)
  candidate <- app_glofas_part2_bridge_candidate_from_rhs_row(rhs_row)
  tau <- tau %||% if (startsWith(model_family, "joint")) app_glofas_part2_bridge_quantile_grid() else 0.5
  result <- app_glofas_part1_quantile_oracle_forecast(
    base_cfg = base_cfg,
    candidate_row = candidate,
    model_family = model_family,
    tau = as.numeric(tau),
    origin_date = origin_date,
    horizon_days = horizon_days,
    target = "discrepancy",
    max_iter = max_iter,
    tol = tol,
    min_iter = min_iter,
    tau0 = tau0 %||% candidate$rhs_tau0[[1L]],
    zeta2 = zeta2,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_sd = alpha_prior_sd,
    max_dense_dim = max_dense_dim,
    rhs_vb_inner = rhs_vb_inner,
    exal_method_id = exal_method_id,
    exal_prefit_max_iter = exal_prefit_max_iter,
    joint_backend = joint_backend,
    freeze_beta_warmup_iters = freeze_beta_warmup_iters,
    min_beta_updates = min_beta_updates,
    init_fit_path = init_fit_path,
    init_fit_paths = init_fit_paths,
    progress_path = progress_path,
    progress_every = progress_every,
    forecast_backend = forecast_backend,
    root_candidates = root_candidates
  )
  result$forecast$future_input_audit <- app_glofas_part2_bridge_relabel_audit(result$forecast$future_input_audit)
  app_glofas_part2_bridge_validate_no_future_usgs_leakage(result$forecast$future_input_audit)
  result$prepared <- list(bundle = app_glofas_oracle_prepare_panel_bundle(
    cfg = base_cfg,
    origin_date = origin_date,
    horizon_days = horizon_days,
    target = "discrepancy",
    root_candidates = root_candidates
  ))
  path <- app_glofas_part2_bridge_quantile_transform_path(result, base_cfg)
  scores <- app_glofas_part2_bridge_score_quantile(path)
  result$part2_path_table <- path
  result$part2_scores <- scores
  result$part2_rhs_row <- rhs_row
  result$part2_input_contract <- "disc_covars"
  result$part2_target_contract <- "observed_discrepancy_retrospective_glofas_minus_usgs"
  result
}

app_glofas_part2_bridge_plot_normal_path <- function(path_table, pdf_path, origin_date, last_n_history = NULL, title = NULL) {
  app_ensure_dir(dirname(pdf_path))
  x <- path_table
  if (!is.null(last_n_history)) {
    hist_dates <- utils::tail(sort(unique(x$date[x$segment == "historical_fit"])), as.integer(last_n_history))
    x <- x[x$date %in% c(hist_dates, x$date[x$segment == "oracle_realized_forecast"]), , drop = FALSE]
  }
  ylim <- range(c(x$observed_usgs, x$retrospective_glofas, x$corrected_pred_mean, x$corrected_pred_q025, x$corrected_pred_q975), finite = TRUE)
  pdf(pdf_path, width = 10.5, height = 5.8)
  on.exit(dev.off(), add = TRUE)
  par(mar = c(4.2, 4.4, 2.6, 1.1), las = 1)
  plot(x$date, x$corrected_pred_mean, type = "n", xlab = "Date", ylab = "Transformed streamflow", ylim = ylim, main = title %||% "Part 2 corrected bridge forecast")
  polygon(c(x$date, rev(x$date)), c(x$corrected_pred_q025, rev(x$corrected_pred_q975)), col = grDevices::adjustcolor("#7aa6c2", alpha.f = 0.22), border = NA)
  lines(x$date, x$retrospective_glofas, col = "#a05a2c", lwd = 1.3, lty = 3)
  lines(x$date, x$corrected_pred_mean, col = "#1f5f8b", lwd = 2)
  points(x$date[x$segment == "historical_fit"], x$observed_usgs[x$segment == "historical_fit"], pch = 16, cex = 0.34, col = "#1d1d1d")
  points(x$date[x$segment == "oracle_realized_forecast"], x$observed_usgs[x$segment == "oracle_realized_forecast"], pch = 16, cex = 0.55, col = "#c0392b")
  abline(v = as.Date(origin_date), lty = 2, col = "#555555", lwd = 1.1)
  legend("topleft", bty = "n", cex = 0.82, lwd = c(NA, 2, 1.3, NA, 1.1), pch = c(16, NA, NA, 16, NA), col = c("#1d1d1d", "#1f5f8b", "#a05a2c", "#c0392b", "#555555"), legend = c("observed history", "corrected mean", "retrospective GloFAS", "future observed", "origin"))
  invisible(pdf_path)
}

app_glofas_part2_bridge_plot_quantile_path <- function(path_table, pdf_path, origin_date, last_n_history = NULL, title = NULL) {
  app_ensure_dir(dirname(pdf_path))
  x <- path_table
  if (!is.null(last_n_history)) {
    hist_dates <- utils::tail(sort(unique(x$date[x$segment == "historical_fit"])), as.integer(last_n_history))
    x <- x[x$date %in% c(hist_dates, x$date[x$segment == "oracle_realized_forecast"]), , drop = FALSE]
  }
  tau_values <- sort(unique(as.numeric(x$corrected_tau)))
  cols <- grDevices::hcl.colors(length(tau_values), palette = "Dark 3")
  ylim <- range(c(x$observed_usgs, x$corrected_qhat), finite = TRUE)
  pdf(pdf_path, width = 10.5, height = 5.8)
  on.exit(dev.off(), add = TRUE)
  par(mar = c(4.2, 4.4, 2.7, 1.1), las = 1)
  plot(x$date, x$corrected_qhat, type = "n", xlab = "Date", ylab = "Transformed streamflow", ylim = ylim, main = title %||% "Part 2 corrected quantile bridge forecast")
  points(x$date[x$segment == "historical_fit"], x$observed_usgs[x$segment == "historical_fit"], pch = 16, cex = 0.35, col = grDevices::adjustcolor("#1d1d1d", alpha.f = 0.75))
  points(x$date[x$segment == "oracle_realized_forecast"], x$observed_usgs[x$segment == "oracle_realized_forecast"], pch = 16, cex = 0.55, col = "#c0392b")
  for (kk in seq_along(tau_values)) {
    block <- x[abs(as.numeric(x$corrected_tau) - tau_values[[kk]]) < 1.0e-12, , drop = FALSE]
    block <- block[order(block$date), , drop = FALSE]
    lines(block$date, block$corrected_qhat, col = cols[[kk]], lwd = 1.7)
  }
  abline(v = as.Date(origin_date), lty = 2, col = "#555555", lwd = 1.1)
  legend("topleft", bty = "n", cex = 0.82, lwd = c(rep(1.7, length(tau_values)), NA, NA, 1.1), pch = c(rep(NA, length(tau_values)), 16, 16, NA), col = c(cols, "#1d1d1d", "#c0392b", "#555555"), legend = c(sprintf("corrected tau %.2f", tau_values), "observed history", "future observed", "origin"))
  invisible(pdf_path)
}

app_glofas_part2_bridge_write_normal_result <- function(result, root, run_label) {
  root <- normalizePath(root, mustWork = FALSE)
  dirs <- file.path(root, c("tables", "figures", "objects", "logs"))
  invisible(lapply(dirs, app_ensure_dir))
  app_write_csv(result$path_table, file.path(root, "tables", paste0(run_label, "_path.csv")))
  app_write_csv(result$forecast$future_input_audit, file.path(root, "tables", paste0(run_label, "_future_input_audit.csv")))
  app_write_csv(result$forecast$input_lag_matrix, file.path(root, "tables", paste0(run_label, "_future_input_lag_matrix.csv")))
  if (nrow(result$forecast$draw_summary %||% data.frame())) {
    app_write_csv(result$forecast$draw_summary, file.path(root, "tables", paste0(run_label, "_discrepancy_draw_summary.csv")))
  }
  app_write_csv(result$scores$pointwise, file.path(root, "tables", paste0(run_label, "_forecast_scores_by_horizon.csv")))
  app_write_csv(result$scores$by_block, file.path(root, "tables", paste0(run_label, "_forecast_scores_by_horizon_block.csv")))
  app_write_csv(result$scores$aggregate, file.path(root, "tables", paste0(run_label, "_forecast_scores.csv")))
  app_write_csv(result$score_reproduction, file.path(root, "tables", paste0(run_label, "_retained_fit_score_reproduction.csv")))
  app_write_csv(result$fitted$candidate_row, file.path(root, "tables", paste0(run_label, "_discrepancy_candidate.csv")))
  app_write_csv(result$part2_rhs_row, file.path(root, "tables", paste0(run_label, "_part2_rhs_winner_row.csv")))
  summary <- data.frame(
    run_label = run_label,
    method = result$fitted$method,
    target = result$target,
    corrected_target = result$corrected_target,
    rhs_candidate_id = as.character(result$part2_rhs_row$rhs_candidate_id[[1L]]),
    candidate_id = as.character(result$part2_rhs_row$candidate_id[[1L]]),
    origin_date = as.character(result$origin_date),
    effective_horizon = as.integer(result$effective_horizon),
    forecast_mode = result$forecast$forecast_mode,
    forecast_backend = result$forecast$forecast_backend,
    n_draws = as.integer(result$forecast$n_draws %||% 0L),
    beta_draw_backend = as.character(result$forecast$beta_draw_backend %||% NA_character_),
    sigma_draw_backend = as.character(result$forecast$sigma_draw_backend %||% NA_character_),
    fit_reused = TRUE,
    fit_object_path = as.character(result$fitted$fit_object_path),
    fit_reuse_contract = as.character(result$fitted$fit_reuse_contract),
    future_corrected_mean_crps = as.numeric(result$scores$aggregate$future_corrected_mean_crps[[1L]] %||% NA_real_),
    future_corrected_discrepancy_mean_crps = as.numeric(result$scores$aggregate$future_corrected_discrepancy_mean_crps[[1L]] %||% NA_real_),
    future_corrected_mae = as.numeric(result$scores$aggregate$future_corrected_mae[[1L]] %||% NA_real_),
    future_corrected_rmse = as.numeric(result$scores$aggregate$future_corrected_rmse[[1L]] %||% NA_real_),
    runtime_seconds = as.numeric(result$forecast_runtime_seconds),
    stringsAsFactors = FALSE
  )
  app_write_csv(summary, file.path(root, "tables", paste0(run_label, "_summary.csv")))
  app_write_yaml(
    list(
      run_label = run_label,
      diagnostic_type = result$diagnostic_type,
      target = "observed discrepancy = retrospective GloFAS - USGS",
      corrected_path = "retrospective GloFAS - predicted discrepancy",
      input_contract = "disc_covars: discrepancy lags 1:360 plus realized ppt/soil lags 0:180; no direct USGS/GloFAS lags",
      origin_policy = "fixed-origin 30-day diagnostic forecast",
      forecast_ensembles = FALSE,
      synthesis = FALSE,
      fit_reused = TRUE,
      retained_fit_path = summary$fit_object_path[[1L]],
      forecast_mode = summary$forecast_mode[[1L]],
      forecast_backend = summary$forecast_backend[[1L]],
      posterior_draw_contract = if (identical(summary$forecast_mode[[1L]], "draw_recursive")) {
        "posterior coefficient draws plus Normal observation-scale draws; compact RHS uses diagonal beta posterior covariance"
      } else {
        "not used"
      }
    ),
    file.path(root, "logs", paste0(run_label, "_contract.yaml"))
  )
  saveRDS(result$fitted$fit, file.path(root, "objects", paste0(run_label, "_retained_fit_view.rds")), version = 2L)
  if (isTRUE(result$retain_draws %||% FALSE) && !is.null(result$forecast$forecast_draws)) {
    saveRDS(
      list(
        discrepancy_forecast_draws = result$forecast$forecast_draws,
        discrepancy_conditional_mean_draws = result$forecast$conditional_mean_draws,
        future_dates = result$forecast$future_dates,
        forecast_mode = result$forecast$forecast_mode,
        seed = result$forecast$seed
      ),
      file.path(root, "objects", paste0(run_label, "_discrepancy_forecast_draws.rds")),
      version = 2L
    )
  }
  full_pdf <- file.path(root, "figures", paste0(run_label, "_corrected_forecast_full_history.pdf"))
  recent_pdf <- file.path(root, "figures", paste0(run_label, "_corrected_forecast_last200_history.pdf"))
  app_glofas_part2_bridge_plot_normal_path(result$path_table, full_pdf, result$origin_date, title = paste(run_label, "full history"))
  app_glofas_part2_bridge_plot_normal_path(result$path_table, recent_pdf, result$origin_date, last_n_history = 200L, title = paste(run_label, "last 200 history rows"))
  app_write_csv(data.frame(figure = c("full_history", "last200_history"), path = c(full_pdf, recent_pdf), stringsAsFactors = FALSE), file.path(root, "figures", paste0(run_label, "_figure_manifest.csv")))
  list(root = root, summary = summary, figures = c(full_pdf, recent_pdf))
}

app_glofas_part2_bridge_write_quantile_result <- function(result, root, run_label) {
  root <- normalizePath(root, mustWork = FALSE)
  dirs <- file.path(root, c("tables", "figures", "objects", "logs", "traces", "coefficients"))
  invisible(lapply(dirs, app_ensure_dir))
  app_write_csv(result$part2_path_table, file.path(root, "tables", paste0(run_label, "_corrected_path.csv")))
  app_write_csv(result$path_table, file.path(root, "tables", paste0(run_label, "_discrepancy_path.csv")))
  app_write_csv(result$forecast$forecast, file.path(root, "tables", paste0(run_label, "_discrepancy_forecast.csv")))
  app_write_csv(result$forecast$future_input_audit, file.path(root, "tables", paste0(run_label, "_future_input_audit.csv")))
  app_write_csv(result$forecast$input_lag_matrix, file.path(root, "tables", paste0(run_label, "_future_input_lag_matrix.csv")))
  app_write_csv(result$part2_scores$pointwise, file.path(root, "tables", paste0(run_label, "_forecast_scores_by_horizon.csv")))
  app_write_csv(result$part2_scores$aggregate, file.path(root, "tables", paste0(run_label, "_score_summary_by_tau.csv")))
  app_write_csv(result$trace, file.path(root, "traces", paste0(run_label, "_vb_trace.csv")))
  app_write_csv(result$coefficients, file.path(root, "coefficients", paste0(run_label, "_coefficients.csv")))
  app_write_csv(result$candidate_row, file.path(root, "tables", paste0(run_label, "_discrepancy_candidate.csv")))
  app_write_csv(result$part2_rhs_row, file.path(root, "tables", paste0(run_label, "_part2_rhs_winner_row.csv")))
  summary <- data.frame(
    run_label = run_label,
    target = "discrepancy",
    corrected_target = "usgs",
    model_family = result$model_family,
    likelihood = result$likelihood,
    fit_structure = result$fit_structure,
    discrepancy_tau_grid = paste(sprintf("%.2f", result$tau), collapse = ","),
    corrected_tau_grid = paste(sprintf("%.2f", 1 - result$tau), collapse = ","),
    rhs_candidate_id = as.character(result$part2_rhs_row$rhs_candidate_id[[1L]]),
    candidate_id = as.character(result$part2_rhs_row$candidate_id[[1L]]),
    max_iter = as.integer(result$controls$max_iter),
    tol = as.numeric(result$controls$tol),
    min_iter = as.integer(result$controls$min_iter),
    converged = isTRUE(result$fit$converged),
    fit_runtime_seconds = as.numeric(result$fit$fit_runtime_seconds),
    forecast_runtime_seconds = as.numeric(result$forecast$forecast_runtime_seconds),
    forecast_backend = result$forecast$forecast_backend,
    joint_backend_used = result$fit$joint_backend_used %||% NA_character_,
    init_source_path = result$fit$init_source_path %||% NA_character_,
    synthesis = FALSE,
    stringsAsFactors = FALSE
  )
  app_write_csv(summary, file.path(root, "tables", paste0(run_label, "_summary.csv")))
  app_write_yaml(
    list(
      run_label = run_label,
      diagnostic_type = "part2_fixed_origin_discrepancy_quantile_bridge_forecast",
      target = "observed discrepancy = retrospective GloFAS - USGS",
      corrected_quantile_transform = "corrected_tau = 1 - discrepancy_tau; corrected_qhat = retrospective GloFAS - discrepancy_qhat",
      model_family = result$model_family,
      likelihood = result$likelihood,
      input_contract = "disc_covars: discrepancy lags 1:360 plus realized ppt/soil lags 0:180; no direct USGS/GloFAS lags",
      max_iter = as.integer(result$controls$max_iter),
      min_iter = as.integer(result$controls$min_iter),
      tol = as.numeric(result$controls$tol),
      progress_path = result$controls$progress_path %||% NA_character_,
      synthesis = FALSE
    ),
    file.path(root, "logs", paste0(run_label, "_contract.yaml"))
  )
  saveRDS(result$fit, file.path(root, "objects", paste0(run_label, "_fit.rds")), version = 2L)
  full_pdf <- file.path(root, "figures", paste0(run_label, "_corrected_forecast_full_history.pdf"))
  recent_pdf <- file.path(root, "figures", paste0(run_label, "_corrected_forecast_last200_history.pdf"))
  app_glofas_part2_bridge_plot_quantile_path(result$part2_path_table, full_pdf, result$origin_date, title = paste(run_label, "full history"))
  app_glofas_part2_bridge_plot_quantile_path(result$part2_path_table, recent_pdf, result$origin_date, last_n_history = 200L, title = paste(run_label, "last 200 history rows"))
  app_write_csv(data.frame(figure = c("full_history", "last200_history"), path = c(full_pdf, recent_pdf), stringsAsFactors = FALSE), file.path(root, "figures", paste0(run_label, "_figure_manifest.csv")))
  list(root = root, summary = summary, figures = c(full_pdf, recent_pdf), fit_path = file.path(root, "objects", paste0(run_label, "_fit.rds")))
}
