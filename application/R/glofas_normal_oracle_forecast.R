# Oracle-realized recursive forecasts for the GloFAS Normal-DESN diagnostics.
#
# These helpers deliberately use realized retrospective ppt/soil covariates after
# an origin date. They are diagnostic/oracle forecasts, not operational forecasts.

app_glofas_oracle_forbidden_source_regex <- function() "(?i)(^|[^[:alpha:]])(gefs|cefs)([^[:alpha:]]|$)"

app_glofas_oracle_repo_root_candidates <- function(repo_root = app_repo_root()) {
  env <- c(
    Sys.getenv("APP_GLOFAS_DATA_REPO_ROOT", unset = ""),
    Sys.getenv("APP_ARTICLE_Q_DESN_V2_DATA_ROOT", unset = "")
  )
  worktree_base <- sub("__wt__.*$", "", normalizePath(repo_root, mustWork = TRUE))
  candidates <- c(repo_root, env[nzchar(env)], worktree_base)
  candidates <- unique(candidates[nzchar(candidates)])
  candidates <- candidates[dir.exists(candidates)]
  normalizePath(candidates, mustWork = TRUE)
}

app_glofas_oracle_resolve_repo_path <- function(path, root_candidates = NULL, must_work = TRUE) {
  if (is.null(path) || !length(path) || !nzchar(as.character(path[[1L]]))) {
    stop("Cannot resolve an empty path.", call. = FALSE)
  }
  path <- as.character(path[[1L]])
  if (grepl("^/", path)) {
    if (isTRUE(must_work) && !file.exists(path)) {
      stop(sprintf("Path does not exist: %s", path), call. = FALSE)
    }
    return(normalizePath(path, mustWork = must_work))
  }
  root_candidates <- root_candidates %||% app_glofas_oracle_repo_root_candidates()
  attempts <- file.path(root_candidates, path)
  hit <- attempts[file.exists(attempts)]
  if (length(hit)) return(normalizePath(hit[[1L]], mustWork = TRUE))
  if (isTRUE(must_work)) {
    stop(
      sprintf(
        "Could not resolve relative path '%s' under candidate roots: %s",
        path,
        paste(root_candidates, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  normalizePath(attempts[[1L]], mustWork = FALSE)
}

app_glofas_oracle_config_path <- function(cfg, key, root_candidates = NULL, must_work = TRUE) {
  val <- (cfg$paths %||% list())[[key]]
  if (is.null(val)) stop(sprintf("Config path '%s' is not defined.", key), call. = FALSE)
  app_glofas_oracle_resolve_repo_path(val, root_candidates = root_candidates, must_work = must_work)
}

app_glofas_oracle_manifest_path <- function(manifest, input_id, root_candidates = NULL) {
  idx <- match(input_id, manifest$input_id)
  if (is.na(idx)) stop(sprintf("Input manifest does not contain input_id '%s'.", input_id), call. = FALSE)
  app_glofas_oracle_resolve_repo_path(manifest$local_path[[idx]], root_candidates = root_candidates)
}

app_glofas_oracle_read_manifest <- function(cfg, root_candidates = NULL) {
  path <- app_glofas_oracle_config_path(cfg, "input_manifest", root_candidates = root_candidates)
  manifest <- app_load_input_manifest(path, required = TRUE)
  attr(manifest, "resolved_path") <- path
  manifest
}

app_glofas_oracle_cutoff_row <- function(cfg, root_candidates = NULL, origin_date = NULL) {
  cutoffs <- app_validate_cutoffs(app_glofas_oracle_config_path(cfg, "cutoffs", root_candidates = root_candidates))
  if (nrow(cutoffs) != 1L) {
    stop("Oracle forecast diagnostics expect exactly one enabled cutoff.", call. = FALSE)
  }
  cutoff <- cutoffs[1L, , drop = FALSE]
  for (nm in intersect(c("origin_date", "train_start", "train_end", "eval_start", "eval_end"), names(cutoff))) {
    cutoff[[nm]] <- as.Date(cutoff[[nm]])
  }
  if (!is.null(origin_date)) {
    origin_date <- as.Date(origin_date)
    cutoff$origin_date <- origin_date
    cutoff$train_end <- origin_date
    if ("eval_start" %in% names(cutoff)) cutoff$eval_start <- origin_date + 1L
  }
  cutoff
}

app_glofas_oracle_numeric_column <- function(x, preferred, label) {
  hit <- intersect(preferred, names(x))
  if (length(hit)) return(hit[[1L]])
  numeric_cols <- names(x)[vapply(x, is.numeric, logical(1L))]
  numeric_cols <- setdiff(numeric_cols, c("date", "origin_date", "target_date", "horizon", "member", "site_id", "station_id"))
  if (!length(numeric_cols)) {
    stop(sprintf("Could not identify numeric value column for %s.", label), call. = FALSE)
  }
  numeric_cols[[1L]]
}

app_glofas_oracle_transform <- function(x, method) {
  if (exists("app_transform_value", mode = "function", inherits = TRUE)) {
    return(app_transform_value(x, method))
  }
  method <- tolower(as.character(method %||% "identity"))
  if (identical(method, "identity")) return(as.numeric(x))
  if (identical(method, "log1p")) return(log1p(pmax(as.numeric(x), 0)))
  stop(sprintf("Unknown transformation method '%s'.", method), call. = FALSE)
}

app_glofas_oracle_load_reference <- function(cfg, manifest, root_candidates = NULL) {
  path <- app_glofas_oracle_manifest_path(manifest, "reference_gauge", root_candidates = root_candidates)
  ref <- app_read_csv(path)
  app_check_required_columns(ref, c("date"), "reference_gauge")
  value_col <- app_glofas_oracle_numeric_column(ref, c("streamflow", "y_reference", "value"), "reference_gauge")
  out <- data.frame(
    date = as.Date(ref$date),
    y_reference = as.numeric(ref[[value_col]]),
    stringsAsFactors = FALSE
  )
  out$y_transformed <- app_glofas_oracle_transform(out$y_reference, cfg$data$transform$response %||% "identity")
  out <- out[!is.na(out$date), , drop = FALSE]
  out <- out[order(out$date), , drop = FALSE]
  out <- out[!duplicated(out$date), , drop = FALSE]
  attr(out, "source_path") <- path
  out
}

app_glofas_oracle_load_glofas_retrospective <- function(cfg, manifest, root_candidates = NULL) {
  path <- app_glofas_oracle_manifest_path(manifest, "glofas_retrospective", root_candidates = root_candidates)
  ret <- app_read_csv(path)
  app_check_required_columns(ret, c("date"), "glofas_retrospective")
  value_col <- app_glofas_oracle_numeric_column(ret, c("glofas_streamflow", "streamflow", "g_glofas", "value"), "glofas_retrospective")
  out <- data.frame(
    date = as.Date(ret$date),
    g_glofas = as.numeric(ret[[value_col]]),
    stringsAsFactors = FALSE
  )
  out$g_transformed <- app_glofas_oracle_transform(out$g_glofas, cfg$data$transform$forecast %||% "identity")
  out <- out[!is.na(out$date), , drop = FALSE]
  out <- out[order(out$date), , drop = FALSE]
  out <- out[!duplicated(out$date), , drop = FALSE]
  attr(out, "source_path") <- path
  out
}

app_glofas_oracle_load_realized_covariates <- function(manifest, root_candidates = NULL) {
  input_id <- if ("ppt_soil_covariates" %in% manifest$input_id) {
    "ppt_soil_covariates"
  } else if ("climate_covariates" %in% manifest$input_id) {
    "climate_covariates"
  } else {
    stop("Input manifest does not contain ppt/soil realized covariates.", call. = FALSE)
  }
  path <- app_glofas_oracle_manifest_path(manifest, input_id, root_candidates = root_candidates)
  cov <- app_read_csv(path)
  app_check_required_columns(cov, c("date", "ppt", "soil"), input_id)
  out <- data.frame(
    date = as.Date(cov$date),
    ppt = as.numeric(cov$ppt),
    soil = as.numeric(cov$soil),
    stringsAsFactors = FALSE
  )
  out <- out[!is.na(out$date), , drop = FALSE]
  out <- out[order(out$date), , drop = FALSE]
  out <- out[!duplicated(out$date), , drop = FALSE]
  attr(out, "source_path") <- path
  attr(out, "input_id") <- input_id
  out
}

app_glofas_oracle_covariate_timeline <- function(covariates, origin_date, train_start = NULL) {
  origin_date <- as.Date(origin_date)
  train_start <- as.Date(train_start %||% min(covariates$date, na.rm = TRUE))
  source_path <- attr(covariates, "source_path", exact = TRUE) %||% NA_character_
  out <- data.frame(
    date = as.Date(covariates$date),
    ppt = as.numeric(covariates$ppt),
    soil = as.numeric(covariates$soil),
    ppt_role = ifelse(as.Date(covariates$date) <= origin_date, "retrospective_realized", "oracle_realized_future"),
    soil_role = ifelse(as.Date(covariates$date) <= origin_date, "retrospective_realized", "oracle_realized_future"),
    ppt_source = "realized_ppt_soil_covariates",
    soil_source = "realized_ppt_soil_covariates",
    source_path = source_path,
    stringsAsFactors = FALSE
  )
  scale_ref <- covariates[
    as.Date(covariates$date) >= train_start &
      as.Date(covariates$date) <= origin_date,
    ,
    drop = FALSE
  ]
  if (!nrow(scale_ref)) scale_ref <- covariates[as.Date(covariates$date) <= origin_date, , drop = FALSE]
  scale_params <- list()
  for (v in c("ppt", "soil")) {
    mu <- mean(scale_ref[[v]], na.rm = TRUE)
    sdv <- stats::sd(scale_ref[[v]], na.rm = TRUE)
    if (!is.finite(mu)) mu <- 0
    if (!is.finite(sdv) || sdv <= 0) sdv <- 1
    out[[paste0(v, "_scaled")]] <- (out[[v]] - mu) / sdv
    out[[paste0(v, "_realized_value")]] <- out[[v]]
    out[[paste0(v, "_source_policy")]] <- ifelse(out$date <= origin_date, "retrospective_realized", "oracle_realized")
    out[[paste0(v, "_source_provider")]] <- "realized_archive"
    out[[paste0(v, "_uses_realized_future")]] <- out$date > origin_date
    scale_params[[v]] <- list(center = mu, scale = sdv)
  }
  attr(out, "variables") <- c("ppt", "soil")
  attr(out, "scale_params") <- scale_params
  attr(out, "realized_source_path") <- source_path
  attr(out, "cutoff_date") <- as.character(origin_date)
  attr(out, "covariate_future_policy") <- "oracle_realized"
  attr(out, "covariate_source_provider") <- "realized_archive"
  app_glofas_oracle_validate_no_forbidden_sources(out, label = "oracle covariate timeline")
  out
}

app_glofas_oracle_validate_no_forbidden_sources <- function(x, label = "object") {
  text <- unlist(x, recursive = TRUE, use.names = FALSE)
  text <- as.character(text[!is.na(text)])
  bad <- grep(app_glofas_oracle_forbidden_source_regex(), text, perl = TRUE, value = TRUE)
  if (length(bad)) {
    stop(
      sprintf("%s contains forbidden GEFS/CEFS source references: %s", label, paste(unique(utils::head(bad, 5L)), collapse = "; ")),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

app_glofas_oracle_contiguous_horizon <- function(dates, origin_date, finite_ok) {
  origin_date <- as.Date(origin_date)
  dates <- as.Date(dates)
  o <- order(dates)
  dates <- dates[o]
  finite_ok <- as.logical(finite_ok[o])
  if (!length(dates)) return(0L)
  by_date <- finite_ok[match(seq.Date(min(dates), max(dates), by = "day"), dates)]
  all_dates <- seq.Date(min(dates), max(dates), by = "day")
  future <- all_dates[all_dates > origin_date]
  if (!length(future)) return(0L)
  ok <- by_date[all_dates > origin_date]
  stop_at <- which(is.na(ok) | !ok)
  if (length(stop_at)) return(max(0L, stop_at[[1L]] - 1L))
  length(future)
}

app_glofas_oracle_prepare_panel_bundle <- function(
  cfg,
  origin_date = NULL,
  horizon_days = NULL,
  target = c("usgs", "discrepancy"),
  root_candidates = NULL
) {
  target <- match.arg(target)
  root_candidates <- root_candidates %||% app_glofas_oracle_repo_root_candidates()
  manifest <- app_glofas_oracle_read_manifest(cfg, root_candidates = root_candidates)
  cutoff <- app_glofas_oracle_cutoff_row(cfg, root_candidates = root_candidates, origin_date = origin_date)
  origin_date <- as.Date(cutoff$train_end[[1L]])
  train_start <- as.Date(cutoff$train_start[[1L]])

  ref <- app_glofas_oracle_load_reference(cfg, manifest, root_candidates = root_candidates)
  cov <- app_glofas_oracle_load_realized_covariates(manifest, root_candidates = root_candidates)
  finite_cov_dates <- cov$date[is.finite(cov$ppt) & is.finite(cov$soil)]
  if (!length(finite_cov_dates)) stop("No finite realized ppt/soil rows are available.", call. = FALSE)
  effective_train_start <- max(train_start, min(finite_cov_dates, na.rm = TRUE))
  truth_source <- ref[, c("date", "y_reference", "y_transformed"), drop = FALSE]
  hist <- ref[ref$date >= effective_train_start & ref$date <= origin_date & is.finite(ref$y_transformed), , drop = FALSE]
  if (!nrow(hist)) stop("No finite historical USGS rows are available through the forecast origin.", call. = FALSE)

  if (identical(target, "discrepancy")) {
    ret <- app_glofas_oracle_load_glofas_retrospective(cfg, manifest, root_candidates = root_candidates)
    paired_all <- merge(ref, ret, by = "date", all = FALSE, sort = FALSE)
    paired_all$d_g_transformed <- as.numeric(paired_all$g_transformed) - as.numeric(paired_all$y_transformed)
    paired_all$d_g_raw <- as.numeric(paired_all$g_glofas) - as.numeric(paired_all$y_reference)
    truth_source <- data.frame(
      date = as.Date(paired_all$date),
      y_reference = paired_all$d_g_raw,
      y_transformed = paired_all$d_g_transformed,
      stringsAsFactors = FALSE
    )
    paired <- paired_all[paired_all$date >= effective_train_start & paired_all$date <= origin_date, , drop = FALSE]
    paired <- paired[order(paired$date), , drop = FALSE]
    hist <- data.frame(
      date = as.Date(paired$date),
      y_reference = paired$d_g_raw,
      y_transformed = paired$d_g_transformed,
      original_y_reference = paired$y_reference,
      original_y_transformed = paired$y_transformed,
      g_glofas = paired$g_glofas,
      g_transformed = paired$g_transformed,
      stringsAsFactors = FALSE
    )
  }

  finite_cov_h <- app_glofas_oracle_contiguous_horizon(
    cov$date,
    origin_date,
    is.finite(cov$ppt) & is.finite(cov$soil)
  )
  truth <- truth_source[
    truth_source$date > origin_date & is.finite(truth_source$y_transformed),
    c("date", "y_reference", "y_transformed"),
    drop = FALSE
  ]
  truth_h <- app_glofas_oracle_contiguous_horizon(truth$date, origin_date, is.finite(truth$y_transformed))
  max_score_horizon <- min(finite_cov_h, truth_h)
  max_covariate_horizon <- finite_cov_h
  requested_horizon <- as.integer(horizon_days %||% max_score_horizon)
  if (!is.finite(requested_horizon) || requested_horizon < 1L) {
    requested_horizon <- max_score_horizon
  }
  effective_horizon <- min(requested_horizon, max_covariate_horizon)
  if (effective_horizon < 1L) {
    stop("No finite realized ppt/soil horizon is available after the forecast origin.", call. = FALSE)
  }
  future_dates <- seq.Date(origin_date + 1L, origin_date + effective_horizon, by = "day")
  future_truth <- truth[match(future_dates, truth$date), , drop = FALSE]
  future_truth$date <- future_dates
  future_truth_available <- is.finite(future_truth$y_transformed)

  panel <- data.frame(
    origin_date = hist$date,
    target_date = hist$date,
    horizon = 0L,
    member = NA_character_,
    is_retrospective = TRUE,
    is_ensemble = FALSE,
    y_reference = as.numeric(hist$y_reference),
    g_glofas = as.numeric(hist$g_glofas %||% NA_real_),
    y_transformed = as.numeric(hist$y_transformed),
    g_transformed = as.numeric(hist$g_transformed %||% NA_real_),
    split = "train",
    cutoff_id = as.character(cutoff$cutoff_id[[1L]] %||% "cutoff"),
    stringsAsFactors = FALSE
  )
  for (nm in setdiff(names(hist), names(panel))) panel[[nm]] <- hist[[nm]]
  timeline <- app_glofas_oracle_covariate_timeline(cov, origin_date = origin_date, train_start = effective_train_start)
  panel <- app_attach_model_covariates(panel, timeline)
  list(
    panel = panel,
    cutoff = cutoff,
    manifest = manifest,
    future_dates = future_dates,
    future_truth = future_truth,
    future_truth_available = future_truth_available,
    max_covariate_horizon = max_covariate_horizon,
    max_score_horizon = max_score_horizon,
    requested_horizon = requested_horizon,
    effective_horizon = effective_horizon,
    target = target,
    root_candidates = root_candidates
  )
}

app_glofas_oracle_default_part1_winner_row <- function() {
  data.frame(
    rhs_candidate_id = "normal_rhs_top10_03_part1wide_0150_D1_n3000__Y360_X180__a050_r090__tau1",
    candidate_id = "part1wide_0150_D1_n3000__Y360_X180__a050_r090",
    D = 1L,
    n_vector = "3000",
    n_tilde = NA_character_,
    lag_id = "Y360_X180",
    m = 360L,
    output_lag_max = 360L,
    covariate_lag_max = 180L,
    alpha = 0.5,
    rho = 0.9,
    seed = 20260512L,
    washout = 500L,
    ridge_tau2 = 10000,
    intercept_var = 1e6,
    sigma_a = 2,
    sigma_b = 1,
    validation_n = 365L,
    rhs_tau0 = 1,
    rhs_max_iter = 100L,
    rhs_min_iter = 30L,
    rhs_tol = 1.0e-4,
    rhs_update_every = 1L,
    rhs_freeze_tau_warmup_iters = 0L,
    rhs_min_tau_updates = 0L,
    stringsAsFactors = FALSE
  )
}

app_glofas_oracle_complete_part1_candidate_row <- function(row) {
  defaults <- app_glofas_oracle_default_part1_winner_row()
  row <- row[1L, , drop = FALSE]
  for (nm in names(defaults)) {
    if (!nm %in% names(row) || length(row[[nm]]) == 0L || is.na(row[[nm]][[1L]])) {
      row[[nm]] <- defaults[[nm]][[1L]]
    }
  }
  if (!"n_vector" %in% names(row) || is.na(row$n_vector[[1L]]) || !nzchar(as.character(row$n_vector[[1L]]))) {
    row$n_vector <- as.character(row$n[[1L]] %||% defaults$n_vector[[1L]])
  }
  row$D <- length(app_glofas_normal_part1_as_int_vec(row$n_vector[[1L]], "n_vector"))
  row
}

app_glofas_oracle_part1_candidate_from_scores <- function(score_path = NULL, rhs_candidate_id = NULL, candidate_id = NULL, rank = 1L) {
  if (is.null(score_path) || !nzchar(as.character(score_path))) {
    return(app_glofas_oracle_default_part1_winner_row())
  }
  score_path <- app_glofas_oracle_resolve_repo_path(score_path)
  scores <- app_read_csv(score_path)
  if (nrow(scores)) {
    if (!is.null(rhs_candidate_id) && nzchar(as.character(rhs_candidate_id))) {
      scores <- scores[as.character(scores$rhs_candidate_id) == as.character(rhs_candidate_id), , drop = FALSE]
    }
    if (!is.null(candidate_id) && nzchar(as.character(candidate_id))) {
      scores <- scores[as.character(scores$candidate_id) == as.character(candidate_id), , drop = FALSE]
    }
    if ("status" %in% names(scores)) scores <- scores[scores$status == "completed", , drop = FALSE]
    if ("valid_mean_crps" %in% names(scores)) {
      scores$valid_mean_crps <- suppressWarnings(as.numeric(scores$valid_mean_crps))
      scores <- scores[order(scores$valid_mean_crps), , drop = FALSE]
    }
  }
  rank <- as.integer(rank)
  if (!nrow(scores) || rank < 1L || rank > nrow(scores)) {
    stop("No matching score row is available for oracle forecast candidate selection.", call. = FALSE)
  }
  app_glofas_oracle_complete_part1_candidate_row(scores[rank, , drop = FALSE])
}

app_glofas_oracle_ridge_warm_start <- function(candidate_row, design, fit, train_idx = seq_len(nrow(design$X))) {
  warm <- list(
    type = "glofas_normal_part1_ridge_warm_start",
    version = "0.1",
    oracle_forecast_role = "full_history_through_origin",
    candidate_id = as.character(candidate_row$candidate_id[[1L]]),
    train_idx = as.integer(train_idx),
    fit = list(
      beta_mean = as.numeric(fit$beta_mean),
      beta_var_diag = as.numeric(fit$beta_var_diag),
      sigma_a = as.numeric(fit$sigma_a),
      sigma_b = as.numeric(fit$sigma_b),
      sigma2_mean = as.numeric(fit$sigma2_mean),
      p = as.integer(fit$p)
    ),
    design = list(
      n = nrow(design$X),
      p = ncol(design$X),
      colnames = colnames(design$X),
      date_min = as.character(min(design$dates)),
      date_max = as.character(max(design$dates)),
      design_hash = app_glofas_normal_part1_design_fingerprint(
        design$X[train_idx, , drop = FALSE],
        design$y[train_idx],
        design$dates[train_idx],
        design$feature_info
      )
    )
  )
  class(warm) <- c("glofas_normal_part1_ridge_warm_start", "list")
  warm
}

app_glofas_oracle_build_part1_design <- function(base_cfg, candidate_row, panel_bundle) {
  candidate_row <- candidate_row[1L, , drop = FALSE]
  dlm_extension <- app_glofas_normal_part1_parse_dlm_extension(
    candidate_row,
    output_lag_max = candidate_row$output_lag_max[[1L]]
  )
  cfg <- app_glofas_normal_part1_make_cfg(
    base_cfg = base_cfg,
    n = candidate_row$n_vector[[1L]],
    m = candidate_row$m[[1L]],
    output_lag_max = candidate_row$output_lag_max[[1L]],
    covariate_lag_max = candidate_row$covariate_lag_max[[1L]],
    alpha = candidate_row$alpha[[1L]],
    rho = candidate_row$rho[[1L]],
    seed = candidate_row$seed[[1L]],
    washout = candidate_row$washout[[1L]],
    dlm_extension = dlm_extension
  )
  invisible(app_feature_contract(cfg))
  dlm_applied <- app_glofas_normal_part1_apply_dlm_extension(
    base_cfg = base_cfg,
    panel_bundle = panel_bundle,
    dlm_extension = dlm_extension
  )
  design_panel_bundle <- dlm_applied$panel_bundle
  qfit <- app_qdesn_build_article_design_full(
    panel = design_panel_bundle$panel,
    cfg = cfg,
    seed = as.integer(candidate_row$seed[[1L]]),
    drop = as.integer(candidate_row$washout[[1L]])
  )
  readout <- app_glofas_normal_part1_readout_matrix(qfit)
  y <- as.numeric(qfit$y_fit)
  dates <- as.Date(design_panel_bundle$panel$target_date[qfit$meta$keep_idx])
  if (nrow(readout$X) != length(y) || length(y) != length(dates)) {
    stop("Oracle Part 1 design produced incompatible X/y/date dimensions.", call. = FALSE)
  }
  list(
    cfg = cfg,
    X = readout$X,
    y = y,
    dates = dates,
    feature_info = readout$feature_info,
    design_meta = qfit$meta,
    reservoir = qfit$reservoir,
    states = qfit$states,
    qfit = qfit,
    dlm_extension = dlm_applied$meta
  )
}

app_glofas_oracle_fit_part1 <- function(
  base_cfg,
  candidate_row,
  panel_bundle,
  method = c("rhs", "ridge"),
  max_iter = NULL,
  min_iter = NULL,
  tol = NULL
) {
  method <- match.arg(method)
  candidate_row <- app_glofas_oracle_complete_part1_candidate_row(candidate_row)
  if (!is.null(max_iter)) candidate_row$rhs_max_iter <- as.integer(max_iter)
  if (!is.null(min_iter)) candidate_row$rhs_min_iter <- as.integer(min_iter)
  if (!is.null(tol)) candidate_row$rhs_tol <- as.numeric(tol)
  started <- Sys.time()
  design <- app_glofas_oracle_build_part1_design(base_cfg, candidate_row, panel_bundle = panel_bundle)
  train_idx <- seq_len(nrow(design$X))
  ridge_fit <- app_glofas_normal_ridge_fit(
    X = design$X,
    y = design$y,
    ridge_tau2 = as.numeric(candidate_row$ridge_tau2[[1L]]),
    intercept_var = as.numeric(candidate_row$intercept_var[[1L]]),
    sigma_a = as.numeric(candidate_row$sigma_a[[1L]]),
    sigma_b = as.numeric(candidate_row$sigma_b[[1L]])
  )
  warm_start <- app_glofas_oracle_ridge_warm_start(candidate_row, design, ridge_fit, train_idx = train_idx)
  fit <- if (identical(method, "ridge")) {
    ridge_fit$type <- "normal_ridge"
    ridge_fit$uses_vb <- FALSE
    ridge_fit$iterations <- 0L
    ridge_fit$converged <- TRUE
    ridge_fit
  } else {
    app_glofas_normal_rhs_fit(
      X = design$X,
      y = design$y,
      ridge_warm_start = warm_start,
      tau0 = as.numeric(candidate_row$rhs_tau0[[1L]]),
      max_iter = as.integer(candidate_row$rhs_max_iter[[1L]]),
      min_iter = as.integer(candidate_row$rhs_min_iter[[1L]]),
      tol = as.numeric(candidate_row$rhs_tol[[1L]]),
      rhs_update_every = as.integer(candidate_row$rhs_update_every[[1L]]),
      freeze_tau_warmup_iters = as.integer(candidate_row$rhs_freeze_tau_warmup_iters[[1L]]),
      min_tau_updates = as.integer(candidate_row$rhs_min_tau_updates[[1L]])
    )
  }
  list(
    method = method,
    candidate_row = candidate_row,
    design = design,
    fit = fit,
    ridge_fit = ridge_fit,
    warm_start = warm_start,
    fit_runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs"))
  )
}

app_glofas_oracle_validate_forecastable_qfit <- function(qfit) {
  spec <- (qfit$meta %||% list())$reservoir_input_spec %||% NULL
  if (is.null(spec)) stop("Forecast continuation requires qfit$meta$reservoir_input_spec.", call. = FALSE)
  if (isTRUE(spec$uses_dlm_components %||% FALSE)) {
    stop("DLM-augmented reservoir inputs cannot yet be recursively forecast without future DLM components.", call. = FALSE)
  }
  if (isTRUE(spec$uses_auxiliary_lags %||% FALSE)) {
    stop("Auxiliary-lag reservoir inputs cannot yet be recursively forecast without declared future auxiliary streams.", call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_oracle_make_readout_row <- function(core, readout_colnames, component_prefix = "") {
  core <- as.numeric(core)
  nm <- paste0(component_prefix, "reservoir_", sprintf("%04d", seq_along(core)))
  out <- matrix(c(1, core), nrow = 1L)
  colnames(out) <- c("readout_intercept", nm)
  missing <- setdiff(readout_colnames, colnames(out))
  extra <- setdiff(colnames(out), readout_colnames)
  if (length(missing) || length(extra)) {
    stop(
      sprintf(
        "Forecast readout columns do not match training design. Missing: %s; extra: %s",
        paste(missing, collapse = ", "),
        paste(extra, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  out[, readout_colnames, drop = FALSE]
}

app_glofas_oracle_with_seed <- function(seed = NULL, expr) {
  if (is.null(seed) || !nzchar(as.character(seed))) return(force(expr))
  seed <- suppressWarnings(as.integer(seed)[[1L]])
  if (!is.finite(seed)) stop("seed must be a finite integer.", call. = FALSE)
  has_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (has_seed) old_seed <- get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  on.exit({
    if (has_seed) {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(seed)
  force(expr)
}

app_glofas_oracle_inverse_gamma_draws <- function(shape, rate, n_draws) {
  shape <- as.numeric(shape)
  rate <- as.numeric(rate)
  n_draws <- as.integer(n_draws)
  if (!is.finite(shape) || shape <= 0 || !is.finite(rate) || rate <= 0) {
    stop("Inverse-gamma draw parameters must be finite and positive.", call. = FALSE)
  }
  if (!is.finite(n_draws) || n_draws < 1L) stop("n_draws must be positive.", call. = FALSE)
  1 / stats::rgamma(n_draws, shape = shape, rate = rate)
}

app_glofas_oracle_beta_deviation_draws <- function(fit, n_draws, use_precision_chol = TRUE) {
  p <- as.integer(fit$p %||% length(fit$beta_mean))
  if (!is.finite(p) || p < 1L) stop("Fit object does not declare a positive coefficient dimension.", call. = FALSE)
  n_draws <- as.integer(n_draws)
  if (!is.finite(n_draws) || n_draws < 1L) stop("n_draws must be positive.", call. = FALSE)
  if (isTRUE(use_precision_chol) && !is.null(fit$precision_chol)) {
    chol_precision <- as.matrix(fit$precision_chol)
    if (all(dim(chol_precision) == c(p, p)) && all(is.finite(chol_precision))) {
      z <- matrix(stats::rnorm(p * n_draws), nrow = p, ncol = n_draws)
      out <- t(backsolve(chol_precision, z))
      attr(out, "backend") <- "precision_chol_backsolve"
      return(out)
    }
  }
  cov <- fit$beta_cov %||% fit$precision_inv %||% NULL
  if (is.null(cov)) stop("Fit object lacks beta covariance or precision inverse for draws.", call. = FALSE)
  out <- app_latent_mvn_draws_exact(rep(0, p), as.matrix(cov), n_draws, seed = NULL, backend = "chol_eigen_fallback")
  attr(out, "backend") <- paste0("covariance_", attr(out, "backend", exact = TRUE) %||% "chol_eigen_fallback")
  out
}

app_glofas_oracle_parameter_draws <- function(
  fit,
  method = c("rhs", "ridge"),
  n_draws = 500L,
  seed = NULL
) {
  method <- match.arg(method)
  n_draws <- as.integer(n_draws)
  if (!is.finite(n_draws) || n_draws < 1L) stop("n_draws must be positive.", call. = FALSE)
  p <- as.integer(fit$p %||% length(fit$beta_mean))
  beta_mean <- as.numeric(fit$beta_mean)
  if (length(beta_mean) != p || any(!is.finite(beta_mean))) {
    stop("Fit beta mean is not finite or has the wrong length.", call. = FALSE)
  }
  app_glofas_oracle_with_seed(seed, {
    sigma2 <- app_glofas_oracle_inverse_gamma_draws(fit$sigma_a, fit$sigma_b, n_draws)
    if (identical(method, "ridge")) {
      base_fit <- fit
      if (!is.null(fit$precision_inv) && is.finite(fit$sigma2_mean %||% NA_real_)) {
        base_fit$beta_cov <- as.matrix(fit$precision_inv)
      }
      dev <- app_glofas_oracle_beta_deviation_draws(base_fit, n_draws, use_precision_chol = TRUE)
      beta <- sweep(dev, 1L, sqrt(pmax(sigma2, .Machine$double.eps)), "*")
    } else {
      dev <- app_glofas_oracle_beta_deviation_draws(fit, n_draws, use_precision_chol = TRUE)
      beta <- dev
    }
    beta <- sweep(beta, 2L, beta_mean, "+")
    beta_names <- names(fit$beta_mean)
    if (is.null(beta_names) || length(beta_names) != p || any(!nzchar(beta_names))) {
      beta_names <- paste0("beta_", seq_len(p))
    }
    colnames(beta) <- beta_names
    list(
      beta = beta,
      sigma2 = sigma2,
      sigma = sqrt(pmax(sigma2, .Machine$double.eps)),
      n_draws = n_draws,
      method = method,
      beta_draw_backend = attr(dev, "backend", exact = TRUE) %||% "unknown",
      sigma_draw_backend = "inverse_gamma_shape_rate"
    )
  })
}

app_glofas_oracle_recursive_forecast <- function(
  fitted,
  future_dates,
  covariate_timeline = NULL,
  component_prefix = ""
) {
  design <- fitted$design
  fit <- fitted$fit
  qfit <- list(
    reservoir = design$reservoir,
    states = design$states,
    meta = design$design_meta
  )
  app_glofas_oracle_validate_forecastable_qfit(qfit)
  future_dates <- as.Date(future_dates)
  H <- length(future_dates)
  if (!H || any(is.na(future_dates))) stop("Future dates must be non-empty and finite.", call. = FALSE)
  history_dates <- as.Date(qfit$meta$history_dates)
  y_history <- as.numeric(qfit$meta$y_history)
  if (!length(history_dates) || length(history_dates) != length(y_history)) {
    stop("Historical dates and response history are not available in the Q-DESN fit.", call. = FALSE)
  }
  covariate_timeline <- covariate_timeline %||% qfit$meta$covariate_timeline %||% NULL
  y_future <- rep(NA_real_, H)
  states <- app_qdesn_last_states(qfit)
  pred_mean <- pred_sd <- numeric(H)
  input_rows <- matrix(NA_real_, nrow = H, ncol = qfit$meta$reservoir_input_spec$m_input)
  colnames(input_rows) <- qfit$meta$reservoir_input_spec$columns
  audit_rows <- vector("list", H)
  X_future <- matrix(NA_real_, nrow = H, ncol = ncol(design$X))
  colnames(X_future) <- colnames(design$X)

  for (h in seq_len(H)) {
    row <- app_qdesn_reservoir_input_row(
      spec = qfit$meta$reservoir_input_spec,
      history_dates = history_dates,
      y_history = y_history,
      target_date = future_dates[[h]],
      covariate_timeline = covariate_timeline,
      future_dates = future_dates,
      y_future = y_future,
      h_current = h
    )
    states <- app_qdesn_continue_one_step(states, row$value, design$reservoir, qfit$meta)
    core <- app_qdesn_readout_row_from_states(states, design$reservoir)
    Xrow <- app_glofas_oracle_make_readout_row(core, colnames(design$X), component_prefix = component_prefix)
    pred <- app_glofas_normal_predict(fit, Xrow, chunk_size = 1L)
    pred_mean[[h]] <- pred$mean[[1L]]
    pred_sd[[h]] <- pred$sd[[1L]]
    y_future[[h]] <- pred_mean[[h]]
    X_future[h, ] <- Xrow
    input_rows[h, ] <- row$value
    audit_rows[[h]] <- row$audit
  }
  audit <- app_bind_rows_fill(audit_rows)
  app_latent_path_validate_no_usgs_leakage(
    data.frame(date = audit$input_date, role = audit$role, stringsAsFactors = FALSE),
    cutoff_date = max(history_dates)
  )
  app_glofas_oracle_validate_no_forbidden_sources(audit, label = "oracle forecast input audit")
  list(
    future_dates = future_dates,
    pred_mean = pred_mean,
    pred_sd = pred_sd,
    pred_median = pred_mean,
    pred_q025 = pred_mean - 1.96 * pred_sd,
    pred_q975 = pred_mean + 1.96 * pred_sd,
    X_future = X_future,
    input_lag_matrix = input_rows,
    future_input_audit = audit,
    y_future_plugin = y_future,
    forecast_mode = "plugin_mean_recursive",
    n_draws = 0L,
    seed = NA_integer_
  )
}

app_glofas_oracle_draw_recursive_forecast <- function(
  fitted,
  future_dates,
  covariate_timeline = NULL,
  component_prefix = "",
  n_draws = 500L,
  seed = 20260903L
) {
  design <- fitted$design
  fit <- fitted$fit
  method <- match.arg(fitted$method %||% "rhs", c("rhs", "ridge"))
  qfit <- list(
    reservoir = design$reservoir,
    states = design$states,
    meta = design$design_meta
  )
  app_glofas_oracle_validate_forecastable_qfit(qfit)
  future_dates <- as.Date(future_dates)
  H <- length(future_dates)
  if (!H || any(is.na(future_dates))) stop("Future dates must be non-empty and finite.", call. = FALSE)
  n_draws <- as.integer(n_draws)
  if (!is.finite(n_draws) || n_draws < 1L) stop("n_draws must be positive.", call. = FALSE)
  history_dates <- as.Date(qfit$meta$history_dates)
  y_history <- as.numeric(qfit$meta$y_history)
  if (!length(history_dates) || length(history_dates) != length(y_history)) {
    stop("Historical dates and response history are not available in the Q-DESN fit.", call. = FALSE)
  }
  covariate_timeline <- covariate_timeline %||% qfit$meta$covariate_timeline %||% NULL
  input_template <- matrix(NA_real_, nrow = H, ncol = qfit$meta$reservoir_input_spec$m_input)
  colnames(input_template) <- qfit$meta$reservoir_input_spec$columns
  y_draws <- matrix(NA_real_, nrow = H, ncol = n_draws)
  mu_draws <- matrix(NA_real_, nrow = H, ncol = n_draws)
  input_sum <- matrix(0, nrow = H, ncol = ncol(input_template))
  colnames(input_sum) <- colnames(input_template)
  audit_rows <- vector("list", H)

  timing <- list()
  time_part <- function(step, expr) {
    started <- proc.time()[["elapsed"]]
    value <- force(expr)
    timing[[length(timing) + 1L]] <<- data.frame(
      step = step,
      elapsed_seconds = as.numeric(proc.time()[["elapsed"]] - started),
      stringsAsFactors = FALSE
    )
    value
  }

  result <- app_glofas_oracle_with_seed(seed, {
    draws <- time_part("posterior_parameter_draws", {
      app_glofas_oracle_parameter_draws(fit, method = method, n_draws = n_draws, seed = NULL)
    })
    for (s in seq_len(n_draws)) {
      states <- app_qdesn_last_states(qfit)
      y_future <- rep(NA_real_, H)
      beta_s <- as.numeric(draws$beta[s, ])
      sigma_s <- as.numeric(draws$sigma[[s]])
      for (h in seq_len(H)) {
        row <- app_qdesn_reservoir_input_row(
          spec = qfit$meta$reservoir_input_spec,
          history_dates = history_dates,
          y_history = y_history,
          target_date = future_dates[[h]],
          covariate_timeline = covariate_timeline,
          future_dates = future_dates,
          y_future = y_future,
          h_current = h
        )
        states <- app_qdesn_continue_one_step(states, row$value, design$reservoir, qfit$meta)
        core <- app_qdesn_readout_row_from_states(states, design$reservoir)
        Xrow <- app_glofas_oracle_make_readout_row(core, colnames(design$X), component_prefix = component_prefix)
        mu_h <- sum(as.numeric(Xrow) * beta_s)
        y_h <- stats::rnorm(1L, mean = mu_h, sd = sigma_s)
        mu_draws[h, s] <- mu_h
        y_draws[h, s] <- y_h
        y_future[[h]] <- y_h
        input_sum[h, ] <- input_sum[h, ] + as.numeric(row$value)
        if (s == 1L) audit_rows[[h]] <- row$audit
      }
    }
    draws
  })

  audit <- app_bind_rows_fill(audit_rows)
  app_latent_path_validate_no_usgs_leakage(
    data.frame(date = audit$input_date, role = audit$role, stringsAsFactors = FALSE),
    cutoff_date = max(history_dates)
  )
  app_glofas_oracle_validate_no_forbidden_sources(audit, label = "oracle draw-recursive forecast input audit")
  input_mean <- input_sum / n_draws
  draw_summary <- data.frame(
    target_date = future_dates,
    horizon = seq_len(H),
    pred_mean = rowMeans(y_draws),
    pred_median = apply(y_draws, 1L, stats::median),
    pred_sd = apply(y_draws, 1L, stats::sd),
    pred_q025 = as.numeric(apply(y_draws, 1L, stats::quantile, probs = 0.025, names = FALSE, type = 8)),
    pred_q975 = as.numeric(apply(y_draws, 1L, stats::quantile, probs = 0.975, names = FALSE, type = 8)),
    conditional_mean_mean = rowMeans(mu_draws),
    conditional_mean_sd = apply(mu_draws, 1L, stats::sd),
    stringsAsFactors = FALSE
  )
  colnames(y_draws) <- sprintf("draw_%05d", seq_len(n_draws))
  colnames(mu_draws) <- sprintf("draw_%05d", seq_len(n_draws))
  list(
    future_dates = future_dates,
    pred_mean = draw_summary$pred_mean,
    pred_median = draw_summary$pred_median,
    pred_sd = draw_summary$pred_sd,
    pred_q025 = draw_summary$pred_q025,
    pred_q975 = draw_summary$pred_q975,
    conditional_mean_mean = draw_summary$conditional_mean_mean,
    conditional_mean_sd = draw_summary$conditional_mean_sd,
    input_lag_matrix = input_mean,
    future_input_audit = audit,
    forecast_draws = y_draws,
    conditional_mean_draws = mu_draws,
    draw_summary = draw_summary,
    forecast_mode = "draw_recursive",
    n_draws = n_draws,
    seed = as.integer(seed),
    beta_draw_backend = result$beta_draw_backend,
    sigma_draw_backend = result$sigma_draw_backend,
    timing = app_bind_rows_fill(timing)
  )
}

app_glofas_oracle_path_table <- function(fitted, forecast, future_truth = NULL) {
  train_pred <- app_glofas_normal_predict(fitted$fit, fitted$design$X, chunk_size = 64L)
  hist <- data.frame(
    date = as.Date(fitted$design$dates),
    segment = "historical_fit",
    observed = as.numeric(fitted$design$y),
    pred_mean = train_pred$mean,
    pred_median = train_pred$mean,
    pred_sd = train_pred$sd,
    ci95_lower = train_pred$mean - 1.96 * train_pred$sd,
    ci95_upper = train_pred$mean + 1.96 * train_pred$sd,
    forecast_mode = "historical_fit",
    stringsAsFactors = FALSE
  )
  if (!is.null(future_truth) && nrow(future_truth)) {
    truth <- as.numeric(future_truth$y_transformed)
    if (length(truth) != length(forecast$future_dates)) {
      truth <- truth[match(forecast$future_dates, as.Date(future_truth$date))]
    }
  } else {
    truth <- rep(NA_real_, length(forecast$future_dates))
  }
  fut <- data.frame(
    date = as.Date(forecast$future_dates),
    segment = "oracle_realized_forecast",
    observed = truth,
    pred_mean = forecast$pred_mean,
    pred_median = forecast$pred_median %||% forecast$pred_mean,
    pred_sd = forecast$pred_sd,
    ci95_lower = forecast$pred_q025 %||% (forecast$pred_mean - 1.96 * forecast$pred_sd),
    ci95_upper = forecast$pred_q975 %||% (forecast$pred_mean + 1.96 * forecast$pred_sd),
    forecast_mode = forecast$forecast_mode %||% "plugin_mean_recursive",
    stringsAsFactors = FALSE
  )
  out <- rbind(hist, fut)
  out
}

app_glofas_oracle_empirical_crps <- function(y, draws) {
  y <- as.numeric(y)
  draws <- as.matrix(draws)
  if (nrow(draws) != length(y)) stop("Draw matrix must have one row per observed value.", call. = FALSE)
  vapply(seq_along(y), function(i) {
    if (!is.finite(y[[i]])) return(NA_real_)
    x <- sort(as.numeric(draws[i, ]))
    x <- x[is.finite(x)]
    S <- length(x)
    if (!S) return(NA_real_)
    mean_abs <- mean(abs(x - y[[i]]))
    pair_term <- sum((2 * seq_len(S) - S - 1) * x) / (S^2)
    mean_abs - pair_term
  }, numeric(1L))
}

app_glofas_oracle_score_forecast <- function(path_table, forecast = NULL) {
  all_future <- path_table[path_table$segment == "oracle_realized_forecast", , drop = FALSE]
  keep <- is.finite(all_future$observed)
  fut <- all_future[keep, , drop = FALSE]
  if (!nrow(fut)) return(data.frame())
  horizon <- which(keep)
  crps <- if (!is.null(forecast$forecast_draws)) {
    draw_idx <- match(fut$date, as.Date(forecast$future_dates))
    app_glofas_oracle_empirical_crps(fut$observed, forecast$forecast_draws[draw_idx, , drop = FALSE])
  } else {
    app_glofas_normal_crps(fut$observed, fut$pred_mean, fut$pred_sd)
  }
  pointwise <- data.frame(
    date = fut$date,
    horizon = as.integer(horizon),
    observed = fut$observed,
    pred_mean = fut$pred_mean,
    pred_median = fut$pred_median %||% fut$pred_mean,
    pred_sd = fut$pred_sd,
    crps = crps,
    abs_error = abs(fut$pred_mean - fut$observed),
    squared_error = (fut$pred_mean - fut$observed)^2,
    median_abs_error = abs((fut$pred_median %||% fut$pred_mean) - fut$observed),
    stringsAsFactors = FALSE
  )
  summarize_pointwise <- function(x, prefix = "") {
    out <- data.frame(
      mean_crps = mean(x$crps, na.rm = TRUE),
      mae = mean(x$abs_error, na.rm = TRUE),
      rmse = sqrt(mean(x$squared_error, na.rm = TRUE)),
      mean_sd = mean(x$pred_sd, na.rm = TRUE),
      median_mae = mean(x$median_abs_error, na.rm = TRUE),
      mean_abs_error = mean(x$abs_error, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
    if (nzchar(prefix)) names(out) <- paste0(prefix, names(out))
    out
  }
  all_score <- summarize_pointwise(pointwise, prefix = "future_")
  blocks <- c(7L, 14L, 30L, 60L, 90L, 180L, 365L)
  block_scores <- app_bind_rows_fill(lapply(blocks, function(h) {
    idx <- seq_len(min(h, nrow(pointwise)))
    cbind(
      data.frame(horizon_block_days = h, n_scored = length(idx), stringsAsFactors = FALSE),
      summarize_pointwise(pointwise[idx, , drop = FALSE], prefix = "")
    )
  }))
  list(aggregate = all_score, by_block = block_scores, pointwise = pointwise)
}

app_glofas_oracle_plot_path <- function(path_table, pdf_path, origin_date, last_n_history = NULL, title = NULL) {
  app_ensure_dir(dirname(pdf_path))
  origin_date <- as.Date(origin_date)
  x <- path_table
  if (!is.null(last_n_history)) {
    hist_dates <- utils::tail(sort(unique(x$date[x$segment == "historical_fit"])), as.integer(last_n_history))
    x <- x[x$date %in% c(hist_dates, x$date[x$segment == "oracle_realized_forecast"]), , drop = FALSE]
  }
  ylim <- range(c(x$observed, x$pred_mean, x$ci95_lower, x$ci95_upper), finite = TRUE)
  pdf(pdf_path, width = 10.5, height = 5.8)
  on.exit(dev.off(), add = TRUE)
  par(mar = c(4.2, 4.4, 2.6, 1.1), las = 1)
  plot(
    x$date,
    x$pred_mean,
    type = "n",
    xlab = "Date",
    ylab = "Transformed response",
    ylim = ylim,
    main = title %||% "Oracle-realized recursive forecast"
  )
  polygon(
    c(x$date, rev(x$date)),
    c(x$ci95_lower, rev(x$ci95_upper)),
    col = grDevices::adjustcolor("#7aa6c2", alpha.f = 0.22),
    border = NA
  )
  lines(x$date, x$pred_mean, col = "#1f5f8b", lwd = 2)
  points(x$date[x$segment == "historical_fit"], x$observed[x$segment == "historical_fit"], pch = 16, cex = 0.38, col = "#1d1d1d")
  points(x$date[x$segment == "oracle_realized_forecast"], x$observed[x$segment == "oracle_realized_forecast"], pch = 16, cex = 0.52, col = "#c0392b")
  abline(v = origin_date, lty = 2, col = "#555555", lwd = 1.2)
  legend(
    "topleft",
    bty = "n",
    lwd = c(NA, 2, NA, NA, 1.2),
    pch = c(16, NA, 16, 15, NA),
    col = c("#1d1d1d", "#1f5f8b", "#c0392b", grDevices::adjustcolor("#7aa6c2", alpha.f = 0.45), "#555555"),
    legend = c("observed history", "recursive mean", "future observed score", "95% predictive band", "origin"),
    pt.cex = c(0.8, 1, 0.9, 1.3, 1),
    cex = 0.86
  )
  invisible(pdf_path)
}

app_glofas_oracle_plot_trace <- function(fitted, pdf_path) {
  trace <- fitted$fit$trace %||% data.frame()
  if (!nrow(trace)) return(NA_character_)
  app_ensure_dir(dirname(pdf_path))
  pdf(pdf_path, width = 8.8, height = 4.8)
  on.exit(dev.off(), add = TRUE)
  par(mar = c(4.2, 4.4, 2.3, 1.1), las = 1)
  y <- as.numeric(trace$partial_elbo %||% trace$normal_rhs_partial_elbo)
  plot(trace$iter, y, type = "l", lwd = 2, col = "#2b6c7f", xlab = "VB iteration", ylab = "Partial ELBO", main = "Normal RHS VB trace")
  points(trace$iter, y, pch = 16, cex = 0.45, col = "#2b6c7f")
  invisible(pdf_path)
}

app_glofas_oracle_score_scalar <- function(scores, name) {
  aggregate <- scores$aggregate %||% data.frame()
  if (!nrow(aggregate) || !name %in% names(aggregate)) return(NA_real_)
  out <- suppressWarnings(as.numeric(aggregate[[name]][[1L]]))
  if (is.finite(out)) out else NA_real_
}

app_glofas_oracle_write_result <- function(result, root, run_label = "oracle_forecast") {
  root <- normalizePath(root, mustWork = FALSE)
  dirs <- file.path(root, c("tables", "figures", "objects", "logs"))
  invisible(lapply(dirs, app_ensure_dir))
  tables_dir <- file.path(root, "tables")
  figures_dir <- file.path(root, "figures")
  objects_dir <- file.path(root, "objects")
  logs_dir <- file.path(root, "logs")

  app_write_csv(result$path_table, file.path(tables_dir, paste0(run_label, "_path.csv")))
  app_write_csv(result$forecast$future_input_audit, file.path(tables_dir, paste0(run_label, "_future_input_audit.csv")))
  app_write_csv(result$forecast$input_lag_matrix, file.path(tables_dir, paste0(run_label, "_future_input_lag_matrix.csv")))
  if (nrow(result$forecast$draw_summary %||% data.frame())) {
    app_write_csv(result$forecast$draw_summary, file.path(tables_dir, paste0(run_label, "_draw_summary.csv")))
  }
  if (nrow(result$scores$aggregate %||% data.frame())) {
    app_write_csv(result$scores$aggregate, file.path(tables_dir, paste0(run_label, "_forecast_scores.csv")))
    app_write_csv(result$scores$by_block, file.path(tables_dir, paste0(run_label, "_forecast_scores_by_horizon_block.csv")))
    app_write_csv(result$scores$pointwise, file.path(tables_dir, paste0(run_label, "_forecast_scores_by_horizon.csv")))
  }
  if (nrow(result$fitted$fit$trace %||% data.frame())) {
    app_write_csv(result$fitted$fit$trace, file.path(tables_dir, paste0(run_label, "_vb_trace.csv")))
  }
  if (nrow(result$forecast$timing %||% data.frame())) {
    app_write_csv(result$forecast$timing, file.path(logs_dir, paste0(run_label, "_forecast_timing.csv")))
  }
  app_write_csv(result$fitted$candidate_row, file.path(tables_dir, paste0(run_label, "_candidate.csv")))
  summary <- data.frame(
    run_label = run_label,
    target = result$target,
    method = result$fitted$method,
    forecast_mode = result$forecast_mode %||% result$forecast$forecast_mode %||% "plugin_mean_recursive",
    candidate_id = as.character(result$fitted$candidate_row$candidate_id[[1L]]),
    rhs_candidate_id = as.character(result$fitted$candidate_row$rhs_candidate_id[[1L]]),
    origin_date = as.character(result$origin_date),
    effective_horizon = as.integer(result$effective_horizon),
    max_covariate_horizon = as.integer(result$max_covariate_horizon),
    max_score_horizon = as.integer(result$max_score_horizon),
    n_draws = as.integer(result$forecast$n_draws %||% 0L),
    seed = as.integer(result$forecast$seed %||% NA_integer_),
    beta_draw_backend = as.character(result$forecast$beta_draw_backend %||% NA_character_),
    sigma_draw_backend = as.character(result$forecast$sigma_draw_backend %||% NA_character_),
    fit_runtime_seconds = as.numeric(result$fitted$fit_runtime_seconds),
    forecast_runtime_seconds = as.numeric(result$forecast_runtime_seconds),
    iterations = as.integer(result$fitted$fit$iterations %||% 0L),
    converged = isTRUE(result$fitted$fit$converged),
    future_mean_crps = app_glofas_oracle_score_scalar(result$scores, "future_mean_crps"),
    future_mae = app_glofas_oracle_score_scalar(result$scores, "future_mae"),
    future_rmse = app_glofas_oracle_score_scalar(result$scores, "future_rmse"),
    future_median_mae = app_glofas_oracle_score_scalar(result$scores, "future_median_mae"),
    stringsAsFactors = FALSE
  )
  app_write_csv(summary, file.path(tables_dir, paste0(run_label, "_summary.csv")))
  app_write_yaml(
    list(
      run_label = run_label,
      diagnostic_type = "oracle_realized_recursive_forecast",
      forecast_mode = summary$forecast_mode[[1L]],
      n_draws = as.integer(summary$n_draws[[1L]]),
      seed = as.integer(summary$seed[[1L]]),
      forbidden_sources = c("GEFS", "CEFS"),
      future_covariate_policy = "realized retrospective ppt/soil only",
      response_leakage_policy = if (identical(summary$forecast_mode[[1L]], "draw_recursive")) {
        "future response unavailable to recursive inputs; posterior predictive draws are fed recursively into future output lags"
      } else {
        "future response unavailable to recursive inputs; plug-in prediction used for future output lags"
      },
      posterior_draw_contract = if (identical(summary$forecast_mode[[1L]], "draw_recursive")) {
        "beta and sigma2 sampled from Normal-DESN posterior/VB approximation; observations sampled from Normal likelihood"
      } else {
        "not used"
      }
    ),
    file.path(logs_dir, paste0(run_label, "_contract.yaml"))
  )
  saveRDS(result$fitted$fit, file.path(objects_dir, paste0(run_label, "_fit.rds")), version = 2L)
  if (isTRUE(result$retain_draws %||% FALSE) && !is.null(result$forecast$forecast_draws)) {
    saveRDS(
      list(
        forecast_draws = result$forecast$forecast_draws,
        conditional_mean_draws = result$forecast$conditional_mean_draws,
        future_dates = result$forecast$future_dates,
        forecast_mode = result$forecast$forecast_mode,
        seed = result$forecast$seed
      ),
      file.path(objects_dir, paste0(run_label, "_forecast_draws.rds")),
      version = 2L
    )
  }

  overall_pdf <- file.path(figures_dir, paste0(run_label, "_forecast_full_history.pdf"))
  recent_pdf <- file.path(figures_dir, paste0(run_label, "_forecast_last200_history.pdf"))
  trace_pdf <- file.path(figures_dir, paste0(run_label, "_vb_trace.pdf"))
  app_glofas_oracle_plot_path(
    result$path_table,
    overall_pdf,
    origin_date = result$origin_date,
    title = sprintf("%s oracle-realized forecast: full history", result$target)
  )
  app_glofas_oracle_plot_path(
    result$path_table,
    recent_pdf,
    origin_date = result$origin_date,
    last_n_history = 200L,
    title = sprintf("%s oracle-realized forecast: last 200 history rows", result$target)
  )
  trace_out <- app_glofas_oracle_plot_trace(result$fitted, trace_pdf)
  app_write_csv(
    data.frame(
      figure = c("full_history", "last200_history", "vb_trace"),
      path = c(overall_pdf, recent_pdf, trace_out),
      stringsAsFactors = FALSE
    ),
    file.path(figures_dir, paste0(run_label, "_figure_manifest.csv"))
  )
  list(summary = summary, root = root, figures = c(overall_pdf, recent_pdf, trace_out))
}

app_glofas_oracle_forecast_part1_single <- function(
  base_cfg,
  candidate_row = NULL,
  origin_date = NULL,
  horizon_days = NULL,
  target = c("usgs", "discrepancy"),
  method = c("rhs", "ridge"),
  forecast_mode = c("plugin_mean_recursive", "draw_recursive"),
  n_draws = 500L,
  seed = 20260903L,
  retain_draws = FALSE,
  max_iter = NULL,
  min_iter = NULL,
  tol = NULL,
  root_candidates = NULL
) {
  target <- match.arg(target)
  method <- match.arg(method)
  forecast_mode <- match.arg(forecast_mode)
  candidate_row <- candidate_row %||% app_glofas_oracle_default_part1_winner_row()
  candidate_row <- app_glofas_oracle_complete_part1_candidate_row(candidate_row)
  bundle <- app_glofas_oracle_prepare_panel_bundle(
    cfg = base_cfg,
    origin_date = origin_date,
    horizon_days = horizon_days,
    target = target,
    root_candidates = root_candidates
  )
  fitted <- app_glofas_oracle_fit_part1(
    base_cfg = base_cfg,
    candidate_row = candidate_row,
    panel_bundle = bundle,
    method = method,
    max_iter = max_iter,
    min_iter = min_iter,
    tol = tol
  )
  started <- Sys.time()
  forecast <- if (identical(forecast_mode, "draw_recursive")) {
    app_glofas_oracle_draw_recursive_forecast(
      fitted = fitted,
      future_dates = bundle$future_dates,
      covariate_timeline = attr(bundle$panel, "model_covariate_timeline", exact = TRUE),
      n_draws = n_draws,
      seed = seed
    )
  } else {
    app_glofas_oracle_recursive_forecast(
      fitted = fitted,
      future_dates = bundle$future_dates,
      covariate_timeline = attr(bundle$panel, "model_covariate_timeline", exact = TRUE)
    )
  }
  path_table <- app_glofas_oracle_path_table(fitted, forecast, future_truth = bundle$future_truth)
  scores <- app_glofas_oracle_score_forecast(path_table, forecast = forecast)
  list(
    target = target,
    forecast_mode = forecast_mode,
    retain_draws = isTRUE(retain_draws),
    origin_date = as.Date(bundle$cutoff$train_end[[1L]]),
    effective_horizon = bundle$effective_horizon,
    max_covariate_horizon = bundle$max_covariate_horizon,
    max_score_horizon = bundle$max_score_horizon,
    requested_horizon = bundle$requested_horizon,
    fitted = fitted,
    forecast = forecast,
    path_table = path_table,
    scores = scores,
    future_truth_available = bundle$future_truth_available,
    forecast_runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs"))
  )
}

app_glofas_oracle_origin_plan <- function(cfg, tail_days = 365L, stride_days = 30L, max_origins = Inf, root_candidates = NULL) {
  cutoff <- app_glofas_oracle_cutoff_row(cfg, root_candidates = root_candidates)
  train_start <- as.Date(cutoff$train_start[[1L]])
  train_end <- as.Date(cutoff$train_end[[1L]])
  start <- max(train_start + 730L, train_end - as.integer(tail_days) + 1L)
  origins <- seq.Date(start, train_end, by = paste(as.integer(stride_days), "days"))
  if (tail(origins, 1L) != train_end) origins <- c(origins, train_end)
  if (is.finite(max_origins)) origins <- utils::tail(origins, as.integer(max_origins))
  data.frame(origin_date = as.Date(origins), origin_index = seq_along(origins), stringsAsFactors = FALSE)
}

app_glofas_oracle_forecast_part1_rolling <- function(
  base_cfg,
  candidate_row = NULL,
  horizons = c(1L, 7L, 14L, 30L, 60L, 90L),
  tail_days = 365L,
  stride_days = 30L,
  max_origins = Inf,
  target = c("usgs", "discrepancy"),
  method = c("rhs", "ridge"),
  forecast_mode = c("plugin_mean_recursive", "draw_recursive"),
  n_draws = 500L,
  seed = 20260903L,
  retain_draws = FALSE,
  max_iter = NULL,
  min_iter = NULL,
  tol = NULL,
  root_candidates = NULL
) {
  target <- match.arg(target)
  method <- match.arg(method)
  forecast_mode <- match.arg(forecast_mode)
  candidate_row <- candidate_row %||% app_glofas_oracle_default_part1_winner_row()
  plan <- app_glofas_oracle_origin_plan(
    cfg = base_cfg,
    tail_days = tail_days,
    stride_days = stride_days,
    max_origins = max_origins,
    root_candidates = root_candidates
  )
  max_h <- max(as.integer(horizons))
  rows <- vector("list", nrow(plan))
  for (i in seq_len(nrow(plan))) {
    res <- app_glofas_oracle_forecast_part1_single(
      base_cfg = base_cfg,
      candidate_row = candidate_row,
      origin_date = plan$origin_date[[i]],
      horizon_days = max_h,
      target = target,
      method = method,
      forecast_mode = forecast_mode,
      n_draws = n_draws,
      seed = as.integer(seed) + i - 1L,
      retain_draws = retain_draws,
      max_iter = max_iter,
      min_iter = min_iter,
      tol = tol,
      root_candidates = root_candidates
    )
    fut <- res$path_table[res$path_table$segment == "oracle_realized_forecast", , drop = FALSE]
    point <- res$scores$pointwise %||% data.frame()
    keep <- point[point$horizon %in% horizons & is.finite(point$observed), , drop = FALSE]
    rows[[i]] <- cbind(
      plan[i, , drop = FALSE],
      data.frame(
        target = target,
        method = method,
        forecast_mode = forecast_mode,
        candidate_id = as.character(res$fitted$candidate_row$candidate_id[[1L]]),
        rhs_tau0 = as.numeric(res$fitted$candidate_row$rhs_tau0[[1L]]),
        horizon = keep$horizon,
        observed = keep$observed,
        pred_mean = keep$pred_mean,
        pred_median = keep$pred_median,
        pred_sd = keep$pred_sd,
        crps = keep$crps,
        abs_error = keep$abs_error,
        squared_error = keep$squared_error,
        median_abs_error = keep$median_abs_error,
        stringsAsFactors = FALSE
      )
    )
  }
  details <- app_bind_rows_fill(rows)
  summary <- app_bind_rows_fill(lapply(split(details, details$horizon), function(x) {
    data.frame(
      horizon = unique(x$horizon),
      n_origins = nrow(x),
      mean_crps = mean(x$crps),
      mae = mean(x$abs_error),
      rmse = sqrt(mean(x$squared_error)),
      median_mae = mean(x$median_abs_error),
      stringsAsFactors = FALSE
    )
  }))
  list(plan = plan, details = details, summary = summary)
}
