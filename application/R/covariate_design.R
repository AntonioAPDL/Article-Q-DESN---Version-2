# Precipitation and soil-moisture covariate design for the GloFAS application.

if (!exists("app_manifest_path", mode = "function")) {
  app_manifest_path <- function(manifest, input_id) {
    idx <- match(input_id, manifest$input_id)
    if (is.na(idx)) stop(sprintf("Input manifest does not contain input_id '%s'.", input_id), call. = FALSE)
    path <- manifest$local_path[[idx]]
    if (grepl("^/", path)) path else app_path(path)
  }
}

app_covariates_enabled <- function(cfg) {
  isTRUE((cfg$covariates %||% list())$enabled %||% FALSE)
}

app_covariate_variables <- function(cfg) {
  vars <- as.character(unlist((cfg$covariates %||% list())$variables %||% c("ppt", "soil"), use.names = FALSE))
  vars <- unique(vars[nzchar(vars)])
  unknown <- setdiff(vars, c("ppt", "soil"))
  if (length(unknown)) {
    stop(sprintf("Unsupported model covariates: %s. This workflow permits only ppt and soil.", paste(unknown, collapse = ", ")), call. = FALSE)
  }
  vars
}

app_covariate_readout_lags <- function(cfg) {
  by_var <- app_covariate_readout_lags_by_variable(cfg)
  sort(unique(as.integer(unlist(by_var, use.names = FALSE))))
}

app_covariate_readout_lags_by_variable <- function(cfg) {
  if (exists("app_feature_contract_covariate_lags", mode = "function")) {
    return(app_feature_contract_covariate_lags(cfg))
  }
  readout <- ((cfg$covariates %||% list())$readout %||% list())
  if (!isTRUE(readout$include_lags %||% TRUE)) return(list())
  lags <- as.integer(unlist(readout$lags %||% 0L, use.names = FALSE))
  lags <- sort(unique(lags[is.finite(lags) & lags >= 0L]))
  vars <- app_covariate_variables(cfg)
  out <- rep(list(lags), length(vars))
  names(out) <- vars
  out
}

app_covariate_use_scaled <- function(cfg) {
  readout <- ((cfg$covariates %||% list())$readout %||% list())
  isTRUE(readout$standardize %||% TRUE)
}

app_covariate_manifest_path <- function(manifest) {
  ids <- as.character(manifest$input_id)
  if ("ppt_soil_covariates" %in% ids) return(app_manifest_path(manifest, "ppt_soil_covariates"))
  if ("climate_covariates" %in% ids) return(app_manifest_path(manifest, "climate_covariates"))
  stop(
    paste(
      "Covariates are enabled, but the input manifest has neither",
      "'ppt_soil_covariates' nor the legacy 'climate_covariates' input."
    ),
    call. = FALSE
  )
}

app_load_realized_ppt_soil <- function(manifest) {
  path <- app_covariate_manifest_path(manifest)
  x <- app_read_table(path)
  if (!"date" %in% names(x)) stop("Covariate file must contain a date column.", call. = FALSE)

  ppt_col <- if ("ppt" %in% names(x)) "ppt" else if ("precipitation_mm" %in% names(x)) "precipitation_mm" else NA_character_
  soil_col <- if ("soil" %in% names(x)) "soil" else if ("soil_moisture" %in% names(x)) "soil_moisture" else NA_character_
  if (is.na(ppt_col) || is.na(soil_col)) {
    stop("Covariate file must contain ppt/precipitation_mm and soil/soil_moisture columns.", call. = FALSE)
  }

  out <- data.frame(
    date = as.Date(x$date),
    ppt = as.numeric(x[[ppt_col]]),
    soil = as.numeric(x[[soil_col]]),
    stringsAsFactors = FALSE
  )
  out <- out[!is.na(out$date), , drop = FALSE]
  out <- out[order(out$date), , drop = FALSE]
  out <- out[!duplicated(out$date), , drop = FALSE]
  attr(out, "source_path") <- path
  out
}

app_parse_quantile_reduction <- function(reduction) {
  reduction <- tolower(as.character(reduction %||% "q85")[[1L]])
  if (identical(reduction, "mean") || identical(reduction, "median")) return(reduction)
  if (grepl("^q[0-9]+$", reduction)) {
    p <- as.numeric(sub("^q", "", reduction)) / 100
    if (is.finite(p) && p >= 0 && p <= 1) return(p)
  }
  stop(sprintf("Unsupported GEFS reduction '%s'. Use mean, median, or qNN.", reduction), call. = FALSE)
}

app_gefs_member_columns <- function(x) {
  cols <- grep("^member_", names(x), value = TRUE)
  if (!length(cols)) stop("GEFS member file has no member_* columns.", call. = FALSE)
  cols
}

app_reduce_numeric <- function(x, reduction) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  if (identical(reduction, "mean")) return(mean(x))
  if (identical(reduction, "median")) return(stats::median(x))
  stats::quantile(x, probs = reduction, na.rm = TRUE, names = FALSE, type = 8)
}

app_daily_gefs_reduction <- function(path, variable, reduction = "q85") {
  x <- app_read_csv(path)
  app_check_required_columns(x, c("target_date"), sprintf("GEFS %s member file", variable))
  x$target_date <- as.Date(x$target_date)
  members <- app_gefs_member_columns(x)
  reduction <- app_parse_quantile_reduction(reduction)
  variable <- tolower(as.character(variable)[[1L]])

  dates <- sort(unique(x$target_date[!is.na(x$target_date)]))
  daily_member <- matrix(NA_real_, nrow = length(dates), ncol = length(members))
  colnames(daily_member) <- members
  rownames(daily_member) <- as.character(dates)
  for (j in seq_along(members)) {
    v <- as.numeric(x[[members[[j]]]])
    by_date <- split(v, x$target_date)
    daily_member[, j] <- vapply(as.character(dates), function(d) {
      vals <- by_date[[d]]
      vals <- vals[is.finite(vals)]
      if (!length(vals)) return(NA_real_)
      if (identical(variable, "ppt")) sum(vals) else mean(vals)
    }, numeric(1L))
  }

  out <- data.frame(
    date = dates,
    value = apply(daily_member, 1L, app_reduce_numeric, reduction = reduction),
    stringsAsFactors = FALSE
  )
  out <- out[is.finite(out$value), , drop = FALSE]
  attr(out, "source_path") <- path
  attr(out, "member_columns") <- members
  attr(out, "daily_member_matrix") <- daily_member
  out
}

app_covariate_handoff_root <- function(cfg) {
  root <- ((cfg$covariates %||% list())$forecast %||% list())$handoff_root %||% ""
  if (!nzchar(as.character(root))) {
    stop("covariates.forecast.handoff_root must be defined when GEFS forecast covariates are enabled.", call. = FALSE)
  }
  app_resolve_path(root, must_work = TRUE)
}

app_covariate_bool <- function(x, default = FALSE) {
  if (is.null(x) || !length(x)) return(default)
  if (is.logical(x)) return(isTRUE(x[[1L]]))
  z <- tolower(trimws(as.character(x[[1L]])))
  if (z %in% c("true", "t", "yes", "y", "1")) return(TRUE)
  if (z %in% c("false", "f", "no", "n", "0")) return(FALSE)
  default
}

app_covariate_default_source_variable <- function(variable) {
  switch(
    variable,
    ppt = "APCP_surface",
    soil = "SOILW_0_0_1_m_below_ground",
    stop(sprintf("Unsupported GEFS covariate variable '%s'.", variable), call. = FALSE)
  )
}

app_covariate_future_policy <- function(cfg) {
  cov <- cfg$covariates %||% list()
  legacy_source_policy <- as.character(cov$source_policy %||% "")
  future_policy <- cov$future_policy %||% NA_character_
  if (!nzchar(as.character(future_policy)) || is.na(future_policy)) {
    future_policy <- switch(
      legacy_source_policy,
      realized_history_and_blended_gefs_forecast = "gefs_realized_blend",
      realized_history_and_gefs_forecast = "gefs_only",
      realized_history_and_oracle_future = "oracle_realized",
      external_forecast_table = "external_table",
      "gefs_realized_blend"
    )
  }
  future_policy <- tolower(as.character(future_policy[[1L]]))
  allowed <- c("gefs_only", "gefs_realized_blend", "oracle_realized", "external_table")
  if (!future_policy %in% allowed) {
    stop(sprintf(
      "Unsupported covariates.future_policy '%s'. Use one of: %s.",
      future_policy,
      paste(allowed, collapse = ", ")
    ), call. = FALSE)
  }

  forecast <- cov$forecast %||% list()
  provider <- forecast$provider %||% switch(
    future_policy,
    oracle_realized = "realized_future_oracle",
    external_table = "external_table",
    "gefs_handoff"
  )
  allow_realized_future <- app_covariate_bool(
    cov$allow_realized_future %||% cov$allow_realized_future_blend,
    default = identical(future_policy, "gefs_realized_blend")
  )
  list(
    future_policy = future_policy,
    source_provider = as.character(provider[[1L]]),
    allow_realized_future = allow_realized_future,
    legacy_source_policy = if (nzchar(legacy_source_policy)) legacy_source_policy else NA_character_
  )
}

app_covariate_gefs_variable_dir <- function(cfg, variable) {
  vcfg <- app_covariate_var_cfg(cfg, variable)
  as.character(vcfg$source_variable %||% app_covariate_default_source_variable(variable))[[1L]]
}

app_covariate_gefs_path <- function(cfg, cutoff_date, variable) {
  root <- app_covariate_handoff_root(cfg)
  variable_dir <- app_covariate_gefs_variable_dir(cfg, variable)
  path <- file.path(root, "forecast_cache", "gefs", sprintf("issue_date=%s", as.character(cutoff_date)), sprintf("variable=%s", variable_dir), "gefs_members.csv")
  if (!file.exists(path)) {
    stop(sprintf("Missing GEFS %s handoff member file: %s", variable, path), call. = FALSE)
  }
  path
}

app_covariate_var_cfg <- function(cfg, variable, policy = NULL) {
  all <- cfg$covariates %||% list()
  policy <- policy %||% app_covariate_future_policy(cfg)$future_policy
  correction_default <- identical(policy, "gefs_realized_blend")
  defaults <- list(
    reduction = "q85",
    source_variable = app_covariate_default_source_variable(variable),
    forecast_noise = list(enabled = FALSE),
    realized_future_correction = list(enabled = correction_default, observed_weight = if (correction_default) 0.5 else 0)
  )
  local <- all[[variable]] %||% list()
  if (is.null(local$forecast_noise) && !is.null(local$noisy_blend)) local$forecast_noise <- local$noisy_blend
  if (is.null(local$realized_future_correction) && !is.null(local$observed_blend)) local$realized_future_correction <- local$observed_blend
  out <- utils::modifyList(defaults, local)
  out$noisy_blend <- out$forecast_noise
  out$observed_blend <- out$realized_future_correction
  out
}

app_covariate_source_hash <- function(path) {
  if (is.null(path) || !length(path) || is.na(path[[1L]]) || !nzchar(as.character(path[[1L]]))) return(NA_character_)
  path <- as.character(path[[1L]])
  if (!file.exists(path)) return(NA_character_)
  app_sha256_file(path)
}

app_covariate_uses_realized_future_cfg <- function(vcfg, variable) {
  obs_cfg <- vcfg$realized_future_correction %||% list()
  enabled <- app_covariate_bool(obs_cfg$enabled, default = FALSE)
  if (!enabled) return(FALSE)
  w <- suppressWarnings(as.numeric(obs_cfg$observed_weight %||% 0))
  zero_prob <- if (identical(variable, "ppt")) suppressWarnings(as.numeric(obs_cfg$observed_zero_stay_prob %||% 0)) else 0
  (is.finite(w) && w > 0) || (is.finite(zero_prob) && zero_prob > 0)
}

app_validate_covariate_source_policy <- function(cfg, manifest = NULL, cutoff_row = NULL, stop_on_failure = TRUE) {
  if (!app_covariates_enabled(cfg)) {
    return(data.frame(
      future_policy = NA_character_,
      source_provider = NA_character_,
      deployable_forecast_covariates = NA,
      uses_realized_future = NA,
      allow_realized_future = NA,
      status = "skipped",
      message = "covariates disabled",
      stringsAsFactors = FALSE
    ))
  }
  policy <- app_covariate_future_policy(cfg)
  vars <- app_covariate_variables(cfg)
  per_var_uses_realized <- vapply(vars, function(v) {
    app_covariate_uses_realized_future_cfg(app_covariate_var_cfg(cfg, v, policy = policy$future_policy), v)
  }, logical(1L))
  uses_realized_future <- identical(policy$future_policy, "oracle_realized") ||
    identical(policy$future_policy, "gefs_realized_blend") ||
    any(per_var_uses_realized)

  status <- "PASS"
  messages <- character()
  if (identical(policy$future_policy, "gefs_only") && any(per_var_uses_realized)) {
    status <- "FAIL"
    messages <- c(messages, "gefs_only cannot use realized_future_correction, observed_weight, or observed_zero_stay_prob")
  }
  if (uses_realized_future && !isTRUE(policy$allow_realized_future)) {
    status <- "FAIL"
    messages <- c(messages, "future policy uses realized future covariates but covariates.allow_realized_future is not true")
  }
  if (policy$future_policy %in% c("gefs_only", "gefs_realized_blend") && !is.null(cutoff_row)) {
    tryCatch({
      for (v in vars) app_covariate_gefs_path(cfg, as.Date(cutoff_row$origin_date[[1L]]), v)
    }, error = function(e) {
      status <<- "FAIL"
      messages <<- c(messages, conditionMessage(e))
    })
  }
  if (identical(policy$future_policy, "external_table")) {
    ext <- ((cfg$covariates %||% list())$forecast %||% list())$external_table %||% ""
    if (!nzchar(as.character(ext))) {
      status <- "FAIL"
      messages <- c(messages, "external_table policy requires covariates.forecast.external_table")
    } else if (!file.exists(app_resolve_path(ext, must_work = FALSE))) {
      status <- "FAIL"
      messages <- c(messages, sprintf("external covariate table does not exist: %s", app_resolve_path(ext, must_work = FALSE)))
    }
  }
  if (!length(messages)) messages <- sprintf(
    "future_policy=%s; provider=%s; realized_future=%s",
    policy$future_policy,
    policy$source_provider,
    uses_realized_future
  )
  out <- data.frame(
    future_policy = policy$future_policy,
    source_provider = policy$source_provider,
    deployable_forecast_covariates = policy$future_policy %in% c("gefs_only", "external_table") && !uses_realized_future,
    uses_realized_future = uses_realized_future,
    allow_realized_future = policy$allow_realized_future,
    status = status,
    message = paste(messages, collapse = "; "),
    stringsAsFactors = FALSE
  )
  if (isTRUE(stop_on_failure) && identical(status, "FAIL")) stop(out$message[[1L]], call. = FALSE)
  out
}

app_noise_vector <- function(n, noisy_cfg, variable) {
  if (!app_covariate_bool(noisy_cfg$enabled, default = FALSE)) return(rep(0, n))
  sd <- as.numeric(noisy_cfg$noise_sd %||% 0)
  if (!is.finite(sd) || sd <= 0) return(rep(0, n))
  seed <- as.integer(noisy_cfg$noise_seed %||% 20260415L)
  if (!is.finite(seed)) seed <- 20260415L
  seed <- seed + if (identical(variable, "soil")) 1009L else 0L
  old_seed <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) get(".Random.seed", envir = .GlobalEnv) else NULL
  on.exit({
    if (is.null(old_seed)) {
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
    } else {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(seed)
  z <- stats::rnorm(n, mean = 0, sd = sd)
  if (identical(tolower(as.character(noisy_cfg$noise_distribution %||% "normal")), "abs_normal")) z <- abs(z)
  z
}

app_blend_forecast_covariate <- function(realized, forecast, cutoff_date, horizon_max, cfg, variable) {
  variable <- as.character(variable)[[1L]]
  vcfg <- app_covariate_var_cfg(cfg, variable, policy = "gefs_realized_blend")
  dates <- seq(as.Date(cutoff_date) + 1L, as.Date(cutoff_date) + as.integer(horizon_max), by = "day")
  realized_idx <- match(dates, realized$date)
  forecast_idx <- match(dates, forecast$date)
  if (any(is.na(realized_idx))) {
    stop(sprintf("Realized %s covariates are missing dates needed by the blend: %s", variable, paste(dates[is.na(realized_idx)], collapse = ", ")), call. = FALSE)
  }
  if (any(is.na(forecast_idx))) {
    stop(sprintf("GEFS %s covariates are missing dates needed by the blend: %s", variable, paste(dates[is.na(forecast_idx)], collapse = ", ")), call. = FALSE)
  }

  obs <- realized[[variable]][realized_idx]
  fc <- forecast$value[forecast_idx]
  noise <- app_noise_vector(length(dates), vcfg$forecast_noise %||% list(), variable)
  fc_noisy <- fc + noise
  if (app_covariate_bool((vcfg$forecast_noise %||% list())$floor_at_zero, default = FALSE)) fc_noisy <- pmax(fc_noisy, 0)

  obs_cfg <- vcfg$realized_future_correction %||% list()
  if (app_covariate_bool(obs_cfg$enabled, default = TRUE)) {
    w <- as.numeric(obs_cfg$observed_weight %||% 0.5)
    if (!is.finite(w) || w < 0 || w > 1) stop(sprintf("%s observed_weight must lie in [0, 1].", variable), call. = FALSE)
    value <- w * obs + (1 - w) * fc_noisy
  } else {
    value <- fc_noisy
  }

  if (identical(variable, "ppt")) {
    dry_threshold <- suppressWarnings(as.numeric(vcfg$dry_day_threshold_mm %||% NA_real_))
    zero_prob <- suppressWarnings(as.numeric(obs_cfg$observed_zero_stay_prob %||% NA_real_))
    if (app_covariate_bool(obs_cfg$enabled, default = TRUE) && is.finite(dry_threshold) && is.finite(zero_prob) && zero_prob > 0) {
      old_seed <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) get(".Random.seed", envir = .GlobalEnv) else NULL
      on.exit({
        if (is.null(old_seed)) {
          if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
        } else {
          assign(".Random.seed", old_seed, envir = .GlobalEnv)
        }
      }, add = TRUE)
      set.seed(as.integer(obs_cfg$observed_zero_stay_seed %||% 20260415L))
      stay_zero <- obs <= dry_threshold & stats::runif(length(obs)) <= zero_prob
      value[stay_zero] <- 0
    }
    value <- pmax(value, 0)
  }

  data.frame(
    date = dates,
    value = as.numeric(value),
    realized_value = obs,
    gefs_reduced_value = fc,
    blend_noise = noise,
    source_role = "forecast_blended",
    source_policy = "gefs_realized_blend",
    source_provider = "gefs_handoff",
    source_variable = as.character(vcfg$source_variable %||% app_covariate_default_source_variable(variable)),
    source_path = attr(forecast, "source_path") %||% NA_character_,
    source_sha256 = app_covariate_source_hash(attr(forecast, "source_path") %||% NA_character_),
    uses_realized_future = TRUE,
    source = sprintf("GEFS %s %s blended with realized %s", variable, vcfg$reduction %||% "q85", variable),
    leakage_status = "uses realized future covariate in configured observed-weight blend",
    stringsAsFactors = FALSE
  )
}

app_gefs_only_forecast_covariate <- function(forecast, cutoff_date, horizon_max, cfg, variable) {
  variable <- as.character(variable)[[1L]]
  vcfg <- app_covariate_var_cfg(cfg, variable, policy = "gefs_only")
  dates <- seq(as.Date(cutoff_date) + 1L, as.Date(cutoff_date) + as.integer(horizon_max), by = "day")
  forecast_idx <- match(dates, forecast$date)
  if (any(is.na(forecast_idx))) {
    stop(sprintf("GEFS %s covariates are missing dates needed by gefs_only: %s", variable, paste(dates[is.na(forecast_idx)], collapse = ", ")), call. = FALSE)
  }
  fc <- forecast$value[forecast_idx]
  noise <- app_noise_vector(length(dates), vcfg$forecast_noise %||% list(), variable)
  value <- fc + noise
  if (identical(variable, "ppt") || app_covariate_bool((vcfg$forecast_noise %||% list())$floor_at_zero, default = FALSE)) {
    value <- pmax(value, 0)
  }
  data.frame(
    date = dates,
    value = as.numeric(value),
    realized_value = NA_real_,
    gefs_reduced_value = fc,
    blend_noise = noise,
    source_role = "forecast_gefs",
    source_policy = "gefs_only",
    source_provider = "gefs_handoff",
    source_variable = as.character(vcfg$source_variable %||% app_covariate_default_source_variable(variable)),
    source_path = attr(forecast, "source_path") %||% NA_character_,
    source_sha256 = app_covariate_source_hash(attr(forecast, "source_path") %||% NA_character_),
    uses_realized_future = FALSE,
    source = sprintf("GEFS %s %s", variable, vcfg$reduction %||% "q85"),
    leakage_status = "deployable forecast covariate; no realized future covariate used",
    stringsAsFactors = FALSE
  )
}

app_oracle_future_covariate <- function(realized, cutoff_date, horizon_max, cfg, variable) {
  variable <- as.character(variable)[[1L]]
  dates <- seq(as.Date(cutoff_date) + 1L, as.Date(cutoff_date) + as.integer(horizon_max), by = "day")
  realized_idx <- match(dates, realized$date)
  if (any(is.na(realized_idx))) {
    stop(sprintf("Realized %s covariates are missing dates needed by oracle_realized: %s", variable, paste(dates[is.na(realized_idx)], collapse = ", ")), call. = FALSE)
  }
  source_path <- attr(realized, "source_path") %||% NA_character_
  data.frame(
    date = dates,
    value = as.numeric(realized[[variable]][realized_idx]),
    realized_value = as.numeric(realized[[variable]][realized_idx]),
    gefs_reduced_value = NA_real_,
    blend_noise = 0,
    source_role = "oracle_realized",
    source_policy = "oracle_realized",
    source_provider = "realized_future_oracle",
    source_variable = variable,
    source_path = source_path,
    source_sha256 = app_covariate_source_hash(source_path),
    uses_realized_future = TRUE,
    source = sprintf("realized future %s oracle", variable),
    leakage_status = "oracle diagnostic; uses realized future covariate",
    stringsAsFactors = FALSE
  )
}

app_external_future_covariate <- function(cfg, cutoff_date, horizon_max, variable) {
  variable <- as.character(variable)[[1L]]
  ext <- ((cfg$covariates %||% list())$forecast %||% list())$external_table
  path <- app_resolve_path(ext, must_work = TRUE)
  x <- app_read_table(path)
  if (!"date" %in% names(x)) stop("External covariate table must contain a date column.", call. = FALSE)
  x$date <- as.Date(x$date)
  if (all(c("variable", "value") %in% names(x))) {
    x <- x[as.character(x$variable) == variable, c("date", "value"), drop = FALSE]
  } else if (variable %in% names(x)) {
    x <- x[, c("date", variable), drop = FALSE]
    names(x) <- c("date", "value")
  } else {
    stop(sprintf("External covariate table must contain %s or variable/value columns.", variable), call. = FALSE)
  }
  dates <- seq(as.Date(cutoff_date) + 1L, as.Date(cutoff_date) + as.integer(horizon_max), by = "day")
  idx <- match(dates, x$date)
  if (any(is.na(idx))) {
    stop(sprintf("External %s covariates are missing forecast dates: %s", variable, paste(dates[is.na(idx)], collapse = ", ")), call. = FALSE)
  }
  data.frame(
    date = dates,
    value = as.numeric(x$value[idx]),
    realized_value = NA_real_,
    gefs_reduced_value = NA_real_,
    blend_noise = 0,
    source_role = "forecast_external",
    source_policy = "external_table",
    source_provider = "external_table",
    source_variable = variable,
    source_path = path,
    source_sha256 = app_covariate_source_hash(path),
    uses_realized_future = FALSE,
    source = sprintf("external forecast table %s", variable),
    leakage_status = "external forecast covariate table; no realized future covariate used by Article pipeline",
    stringsAsFactors = FALSE
  )
}

app_covariate_scale_reference <- function(realized, cutoff_row, cfg) {
  ref_mode <- tolower(as.character((((cfg$covariates %||% list())$readout %||% list())$scale_reference %||% "retrospective_train")[[1L]]))
  cutoff_date <- as.Date(cutoff_row$origin_date[[1L]])
  if (identical(ref_mode, "retrospective_train")) {
    train_start <- as.Date(cutoff_row$train_start[[1L]])
    train_end <- as.Date(cutoff_row$train_end[[1L]])
    realized[realized$date >= train_start & realized$date <= train_end & realized$date <= cutoff_date, , drop = FALSE]
  } else if (identical(ref_mode, "through_cutoff")) {
    realized[realized$date <= cutoff_date, , drop = FALSE]
  } else {
    stop(sprintf("Unsupported covariate scale_reference '%s'.", ref_mode), call. = FALSE)
  }
}

app_build_model_covariate_timeline <- function(cfg, manifest, cutoff_row, panel = NULL) {
  if (!app_covariates_enabled(cfg)) return(NULL)
  vars <- app_covariate_variables(cfg)
  cutoff_date <- as.Date(cutoff_row$origin_date[[1L]])
  configured_horizon <- as.integer(((cfg$covariates %||% list())$forecast %||% list())$horizon_days %||% NA_integer_)
  cutoff_horizon <- as.integer(cutoff_row$horizon_max[[1L]] %||% cfg$forecast_protocol$default_horizon_max %||% 30L)
  horizon_max <- max(c(configured_horizon, cutoff_horizon), na.rm = TRUE)
  if (is.finite(horizon_max) && !is.null(panel) && nrow(panel)) {
    horizon_max <- max(horizon_max, as.integer(max(as.Date(panel$target_date), na.rm = TRUE) - cutoff_date), na.rm = TRUE)
  }
  horizon_max <- max(1L, as.integer(horizon_max))

  realized <- app_load_realized_ppt_soil(manifest)
  source_path <- attr(realized, "source_path") %||% NA_character_
  policy <- app_covariate_future_policy(cfg)
  policy_audit <- app_validate_covariate_source_policy(cfg, manifest, cutoff_row, stop_on_failure = TRUE)
  hist <- realized[realized$date <= cutoff_date, c("date", vars), drop = FALSE]
  if (!nrow(hist)) stop("No realized ppt/soil covariate rows are available through the cutoff.", call. = FALSE)

  future_parts <- list()
  for (v in vars) {
    vcfg <- app_covariate_var_cfg(cfg, v, policy = policy$future_policy)
    future_parts[[v]] <- switch(
      policy$future_policy,
      gefs_only = {
        gefs_path <- app_covariate_gefs_path(cfg, cutoff_date, v)
        reduced <- app_daily_gefs_reduction(gefs_path, variable = v, reduction = vcfg$reduction %||% "q85")
        app_gefs_only_forecast_covariate(reduced, cutoff_date, horizon_max, cfg, v)
      },
      gefs_realized_blend = {
        gefs_path <- app_covariate_gefs_path(cfg, cutoff_date, v)
        reduced <- app_daily_gefs_reduction(gefs_path, variable = v, reduction = vcfg$reduction %||% "q85")
        app_blend_forecast_covariate(realized, reduced, cutoff_date, horizon_max, cfg, v)
      },
      oracle_realized = app_oracle_future_covariate(realized, cutoff_date, horizon_max, cfg, v),
      external_table = app_external_future_covariate(cfg, cutoff_date, horizon_max, v)
    )
  }

  future <- data.frame(date = seq(cutoff_date + 1L, cutoff_date + horizon_max, by = "day"), stringsAsFactors = FALSE)
  for (v in vars) {
    fp <- future_parts[[v]]
    future[[v]] <- fp$value[match(future$date, fp$date)]
    future[[paste0(v, "_realized_value")]] <- fp$realized_value[match(future$date, fp$date)]
    future[[paste0(v, "_gefs_reduced_value")]] <- fp$gefs_reduced_value[match(future$date, fp$date)]
    future[[paste0(v, "_blend_noise")]] <- fp$blend_noise[match(future$date, fp$date)]
    future[[paste0(v, "_role")]] <- fp$source_role[match(future$date, fp$date)]
    future[[paste0(v, "_source")]] <- fp$source[match(future$date, fp$date)]
    future[[paste0(v, "_leakage_status")]] <- fp$leakage_status[match(future$date, fp$date)]
    future[[paste0(v, "_source_policy")]] <- fp$source_policy[match(future$date, fp$date)]
    future[[paste0(v, "_source_provider")]] <- fp$source_provider[match(future$date, fp$date)]
    future[[paste0(v, "_source_variable")]] <- fp$source_variable[match(future$date, fp$date)]
    future[[paste0(v, "_source_path")]] <- fp$source_path[match(future$date, fp$date)]
    future[[paste0(v, "_source_sha256")]] <- fp$source_sha256[match(future$date, fp$date)]
    future[[paste0(v, "_uses_realized_future")]] <- fp$uses_realized_future[match(future$date, fp$date)]
  }

  for (v in vars) {
    hist[[paste0(v, "_realized_value")]] <- hist[[v]]
    hist[[paste0(v, "_gefs_reduced_value")]] <- NA_real_
    hist[[paste0(v, "_blend_noise")]] <- 0
    hist[[paste0(v, "_role")]] <- "retrospective_realized"
    hist[[paste0(v, "_source")]] <- "realized retrospective covariate"
    hist[[paste0(v, "_leakage_status")]] <- "available retrospectively through cutoff"
    hist[[paste0(v, "_source_policy")]] <- "retrospective_realized"
    hist[[paste0(v, "_source_provider")]] <- "realized_archive"
    hist[[paste0(v, "_source_variable")]] <- v
    hist[[paste0(v, "_source_path")]] <- source_path
    hist[[paste0(v, "_source_sha256")]] <- app_covariate_source_hash(source_path)
    hist[[paste0(v, "_uses_realized_future")]] <- FALSE
  }

  timeline <- rbind(hist[, names(future), drop = FALSE], future)
  timeline <- timeline[order(timeline$date), , drop = FALSE]
  scale_ref <- app_covariate_scale_reference(realized, cutoff_row, cfg)
  scale_params <- list()
  for (v in vars) {
    mu <- mean(scale_ref[[v]], na.rm = TRUE)
    sdv <- stats::sd(scale_ref[[v]], na.rm = TRUE)
    if (!is.finite(sdv) || sdv <= 0) sdv <- 1
    timeline[[paste0(v, "_scaled")]] <- (timeline[[v]] - mu) / sdv
    scale_params[[v]] <- list(center = mu, scale = sdv)
  }

  attr(timeline, "variables") <- vars
  attr(timeline, "scale_params") <- scale_params
  attr(timeline, "realized_source_path") <- source_path
  attr(timeline, "cutoff_date") <- as.character(cutoff_date)
  attr(timeline, "covariate_future_policy") <- policy$future_policy
  attr(timeline, "covariate_source_provider") <- policy$source_provider
  attr(timeline, "covariate_policy_audit") <- policy_audit
  timeline
}

app_attach_model_covariates <- function(panel, timeline) {
  if (is.null(timeline)) return(panel)
  idx <- match(as.Date(panel$target_date), as.Date(timeline$date))
  if (any(is.na(idx))) {
    missing_dates <- sort(unique(as.Date(panel$target_date)[is.na(idx)]))
    stop(sprintf("Panel target dates missing from covariate timeline: %s", paste(missing_dates, collapse = ", ")), call. = FALSE)
  }
  vars <- attr(timeline, "variables") %||% c("ppt", "soil")
  for (v in vars) {
    panel[[v]] <- timeline[[v]][idx]
    panel[[paste0(v, "_scaled")]] <- timeline[[paste0(v, "_scaled")]][idx]
    panel[[paste0(v, "_role")]] <- timeline[[paste0(v, "_role")]][idx]
  }
  panel$model_covariate_role <- if (all(paste0(vars, "_role") %in% names(panel))) {
    apply(panel[paste0(vars, "_role")], 1L, function(z) paste(unique(z), collapse = "+"))
  } else {
    NA_character_
  }
  attr(panel, "model_covariate_timeline") <- timeline
  attr(panel, "model_covariate_meta") <- list(
    variables = vars,
    scale_params = attr(timeline, "scale_params")
  )
  panel
}

app_copy_covariate_attrs <- function(to, from) {
  attr(to, "model_covariate_timeline") <- attr(from, "model_covariate_timeline", exact = TRUE)
  attr(to, "model_covariate_meta") <- attr(from, "model_covariate_meta", exact = TRUE)
  to
}

app_panel_covariate_timeline <- function(panel, required = FALSE) {
  out <- attr(panel, "model_covariate_timeline", exact = TRUE)
  if (is.null(out) && isTRUE(required)) {
    stop("Model covariates are enabled but the panel has no model_covariate_timeline attribute.", call. = FALSE)
  }
  out
}

app_covariate_lag_matrix <- function(timeline, target_dates, cfg, lags_by_var = NULL) {
  if (!app_covariates_enabled(cfg)) return(NULL)
  lags_by_var <- lags_by_var %||% app_covariate_readout_lags_by_variable(cfg)
  lags_by_var <- lags_by_var[vapply(lags_by_var, length, integer(1L)) > 0L]
  if (!length(lags_by_var)) return(NULL)
  vars <- names(lags_by_var)
  unknown <- setdiff(vars, app_covariate_variables(cfg))
  if (length(unknown)) {
    stop(sprintf("Covariate lag spec contains variables not enabled in cfg$covariates: %s", paste(unknown, collapse = ", ")), call. = FALSE)
  }
  timeline$date <- as.Date(timeline$date)
  target_dates <- as.Date(target_dates)
  use_scaled <- app_covariate_use_scaled(cfg)
  cols <- list()
  col_names <- character()
  for (v in vars) {
    val_col <- if (isTRUE(use_scaled)) paste0(v, "_scaled") else v
    for (L in as.integer(lags_by_var[[v]])) {
      lookup_date <- target_dates - as.integer(L)
      idx <- match(lookup_date, timeline$date)
      if (any(is.na(idx))) {
        missing_dates <- sort(unique(lookup_date[is.na(idx)]))
        stop(sprintf("Covariate lag %s_lag_%d is missing timeline dates: %s", v, L, paste(missing_dates, collapse = ", ")), call. = FALSE)
      }
      values <- as.numeric(timeline[[val_col]][idx])
      if (any(!is.finite(values))) {
        stop(sprintf("Covariate lag %s_lag_%d contains non-finite values.", v, L), call. = FALSE)
      }
      cols[[length(cols) + 1L]] <- values
      col_names <- c(col_names, sprintf("%s_lag_%d", v, L))
    }
  }
  out <- do.call(cbind, cols)
  colnames(out) <- col_names
  storage.mode(out) <- "double"
  out
}

app_append_covariate_lags <- function(X, target_dates, panel, cfg) {
  if (!app_covariates_enabled(cfg)) return(list(X = X, X_covariates = NULL))
  timeline <- app_panel_covariate_timeline(panel, required = TRUE)
  X_cov <- app_covariate_lag_matrix(timeline, target_dates = target_dates, cfg = cfg)
  if (is.null(X_cov) || !ncol(X_cov)) return(list(X = X, X_covariates = NULL))
  out <- cbind(X, X_cov)
  storage.mode(out) <- "double"
  list(X = out, X_covariates = X_cov)
}

app_covariate_timeline_summary <- function(timeline) {
  if (is.null(timeline)) return(data.frame())
  vars <- attr(timeline, "variables") %||% c("ppt", "soil")
  known_roles <- c("retrospective_realized", "forecast_blended", "forecast_gefs", "oracle_realized", "forecast_external")
  rows <- lapply(vars, function(v) {
    role_col <- paste0(v, "_role")
    role <- as.character(timeline[[role_col]] %||% rep(NA_character_, nrow(timeline)))
    uses_col <- paste0(v, "_uses_realized_future")
    uses_realized <- if (uses_col %in% names(timeline)) as.logical(timeline[[uses_col]]) else rep(FALSE, nrow(timeline))
    out <- data.frame(
      variable = v,
      n_rows = nrow(timeline),
      date_min = as.character(min(timeline$date, na.rm = TRUE)),
      date_max = as.character(max(timeline$date, na.rm = TRUE)),
      n_missing = sum(!is.finite(timeline[[v]])),
      n_uses_realized_future = sum(uses_realized, na.rm = TRUE),
      future_policy = attr(timeline, "covariate_future_policy") %||% NA_character_,
      source_provider = attr(timeline, "covariate_source_provider") %||% NA_character_,
      stringsAsFactors = FALSE
    )
    for (rr in known_roles) out[[paste0("n_", rr)]] <- sum(role == rr, na.rm = TRUE)
    out
  })
  do.call(rbind, rows)
}

app_covariate_source_manifest <- function(timeline) {
  if (is.null(timeline)) return(data.frame())
  vars <- attr(timeline, "variables") %||% c("ppt", "soil")
  rows <- list()
  for (v in vars) {
    required <- paste0(v, c(
      "_role", "_source_policy", "_source_provider", "_source_variable",
      "_source_path", "_source_sha256", "_uses_realized_future"
    ))
    if (!all(required %in% names(timeline))) next
    x <- data.frame(
      variable = v,
      role = as.character(timeline[[paste0(v, "_role")]]),
      source_policy = as.character(timeline[[paste0(v, "_source_policy")]]),
      source_provider = as.character(timeline[[paste0(v, "_source_provider")]]),
      source_variable = as.character(timeline[[paste0(v, "_source_variable")]]),
      source_path = as.character(timeline[[paste0(v, "_source_path")]]),
      source_sha256 = as.character(timeline[[paste0(v, "_source_sha256")]]),
      uses_realized_future = as.logical(timeline[[paste0(v, "_uses_realized_future")]]),
      stringsAsFactors = FALSE
    )
    key <- paste(x$role, x$source_policy, x$source_provider, x$source_variable, x$source_path, x$source_sha256, x$uses_realized_future, sep = "\r")
    keep <- !duplicated(key)
    y <- x[keep, , drop = FALSE]
    y$n_rows <- vapply(key[keep], function(k) sum(key == k, na.rm = TRUE), integer(1L))
    rows[[v]] <- y
  }
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

app_covariate_source_manifest_hash <- function(timeline) {
  manifest <- app_covariate_source_manifest(timeline)
  if (!nrow(manifest)) return(NA_character_)
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  app_write_csv(manifest, tmp)
  app_sha256_file(tmp)
}

app_covariate_policy_audit <- function(timeline) {
  out <- app_covariate_timeline_summary(timeline)
  if (!nrow(out)) return(out)
  out$source_manifest_hash <- app_covariate_source_manifest_hash(timeline)
  out
}
