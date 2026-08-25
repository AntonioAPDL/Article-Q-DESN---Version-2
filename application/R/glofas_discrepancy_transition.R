# Causal discrepancy-transition contracts for the GloFAS latent-path model.

app_glofas_transition_bool <- function(x, default = FALSE) {
  if (is.null(x) || !length(x)) return(default)
  if (is.logical(x)) return(isTRUE(x[[1L]]))
  value <- tolower(trimws(as.character(x[[1L]])))
  if (value %in% c("true", "t", "yes", "y", "1")) return(TRUE)
  if (value %in% c("false", "f", "no", "n", "0")) return(FALSE)
  stop(sprintf("Cannot interpret '%s' as a transition-contract boolean.", value), call. = FALSE)
}

app_glofas_discrepancy_transition_contract <- function(cfg) {
  prediction <- cfg$prediction %||% list()
  raw <- prediction[["discrepancy_transition"]] %||% NULL
  legacy <- as.character(
    prediction$discrepancy_transition_strategy %||% "recursive_level"
  )[[1L]]

  if (is.null(raw)) {
    if (!legacy %in% c("recursive_level", "persistence_anchored_innovation")) {
      stop(
        paste(
          "prediction.discrepancy_transition_strategy must be",
          "'recursive_level' or 'persistence_anchored_innovation'."
        ),
        call. = FALSE
      )
    }
    contract <- if (identical(legacy, "recursive_level")) {
      list(
        schema_version = "glofas_discrepancy_transition_v1",
        origin = "legacy_strategy",
        strategy_label = "recursive_level",
        anchor = list(method = "none", window = NA_integer_, half_life = NA_real_),
        evolution = list(method = "recursive_level"),
        context = list(
          glofas_level = FALSE,
          glofas_anomaly = FALSE,
          anomaly_window = 50L,
          include_in_reservoir = TRUE,
          include_in_readout = TRUE,
          lags = 0L
        )
      )
    } else {
      list(
        schema_version = "glofas_discrepancy_transition_v1",
        origin = "legacy_strategy",
        strategy_label = "persistence_anchored_innovation",
        anchor = list(method = "last", window = NA_integer_, half_life = NA_real_),
        evolution = list(method = "static_anchor_innovation"),
        context = list(
          glofas_level = FALSE,
          glofas_anomaly = FALSE,
          anomaly_window = 50L,
          include_in_reservoir = TRUE,
          include_in_readout = TRUE,
          lags = 0L
        )
      )
    }
  } else {
    if (!is.list(raw)) {
      stop("prediction.discrepancy_transition must be a mapping.", call. = FALSE)
    }
    anchor <- raw$anchor %||% list()
    evolution <- raw$evolution %||% list()
    context <- raw$context %||% list()
    anchor_method <- tolower(as.character(anchor$method %||% "last")[[1L]])
    evolution_method <- tolower(as.character(
      evolution$method %||% "static_anchor_innovation"
    )[[1L]])
    window <- suppressWarnings(as.integer(anchor$window %||% NA_integer_))
    half_life <- suppressWarnings(as.numeric(anchor$half_life %||% NA_real_))
    anomaly_window <- suppressWarnings(as.integer(context$anomaly_window %||% 50L))
    lags <- app_parse_lag_spec(
      context$lags %||% 0L,
      default = 0L,
      allow_zero = TRUE,
      label = "prediction.discrepancy_transition.context.lags"
    )
    contract <- list(
      schema_version = "glofas_discrepancy_transition_v1",
      origin = "factorized_contract",
      strategy_label = if (identical(evolution_method, "recursive_level")) {
        "recursive_level"
      } else {
        "anchored_innovation"
      },
      anchor = list(
        method = anchor_method,
        window = window,
        half_life = half_life
      ),
      evolution = list(method = evolution_method),
      context = list(
        glofas_level = app_glofas_transition_bool(context$glofas_level, FALSE),
        glofas_anomaly = app_glofas_transition_bool(context$glofas_anomaly, FALSE),
        anomaly_window = anomaly_window,
        include_in_reservoir = app_glofas_transition_bool(
          context$include_in_reservoir,
          TRUE
        ),
        include_in_readout = app_glofas_transition_bool(
          context$include_in_readout,
          TRUE
        ),
        lags = lags
      )
    )
  }

  anchor_allowed <- c("none", "last", "rolling_mean", "rolling_median", "ewma")
  if (!contract$anchor$method %in% anchor_allowed) {
    stop(sprintf(
      "Unsupported discrepancy anchor '%s'. Use one of: %s.",
      contract$anchor$method,
      paste(anchor_allowed, collapse = ", ")
    ), call. = FALSE)
  }
  evolution_allowed <- c("recursive_level", "static_anchor_innovation")
  if (!contract$evolution$method %in% evolution_allowed) {
    stop(sprintf(
      "Unsupported discrepancy evolution '%s'. Use one of: %s.",
      contract$evolution$method,
      paste(evolution_allowed, collapse = ", ")
    ), call. = FALSE)
  }
  if (identical(contract$evolution$method, "recursive_level") &&
      !identical(contract$anchor$method, "none")) {
    stop("recursive_level requires anchor.method = 'none'.", call. = FALSE)
  }
  if (identical(contract$evolution$method, "static_anchor_innovation") &&
      identical(contract$anchor$method, "none")) {
    stop("static_anchor_innovation requires a non-empty causal anchor.", call. = FALSE)
  }
  if (contract$anchor$method %in% c("rolling_mean", "rolling_median") &&
      (!is.finite(contract$anchor$window) || contract$anchor$window < 1L)) {
    stop("Rolling discrepancy anchors require anchor.window >= 1.", call. = FALSE)
  }
  if (identical(contract$anchor$method, "ewma") &&
      (!is.finite(contract$anchor$half_life) || contract$anchor$half_life <= 0)) {
    stop("EWMA discrepancy anchors require anchor.half_life > 0.", call. = FALSE)
  }
  if (!is.finite(contract$context$anomaly_window) ||
      contract$context$anomaly_window < 1L) {
    stop("GloFAS anomaly context requires anomaly_window >= 1.", call. = FALSE)
  }
  if ((contract$context$glofas_level || contract$context$glofas_anomaly) &&
      !(contract$context$include_in_reservoir ||
        contract$context$include_in_readout)) {
    stop(
      "Enabled GloFAS context must enter the discrepancy reservoir or readout.",
      call. = FALSE
    )
  }
  contract$contract_hash <- app_qdesn_hash_object(
    contract,
    prefix = "glofas_discrepancy_transition_"
  )
  contract
}

app_glofas_discrepancy_transition_is_static <- function(contract) {
  identical(
    (contract %||% list())$evolution$method %||% NA_character_,
    "static_anchor_innovation"
  )
}

app_glofas_discrepancy_context_variables <- function(contract) {
  context <- (contract %||% list())$context %||% list()
  out <- character()
  if (isTRUE(context$glofas_level)) out <- c(out, "glofas_level")
  if (isTRUE(context$glofas_anomaly)) out <- c(out, "glofas_anomaly")
  out
}

app_glofas_discrepancy_transition_contract_row <- function(contract) {
  context_vars <- app_glofas_discrepancy_context_variables(contract)
  data.frame(
    discrepancy_transition_schema = contract$schema_version,
    discrepancy_transition_origin = contract$origin,
    discrepancy_transition_strategy = contract$strategy_label,
    discrepancy_anchor_method = contract$anchor$method,
    discrepancy_anchor_window = contract$anchor$window,
    discrepancy_anchor_half_life = contract$anchor$half_life,
    discrepancy_evolution_method = contract$evolution$method,
    discrepancy_context_variables = paste(context_vars, collapse = ";"),
    discrepancy_context_anomaly_window = contract$context$anomaly_window,
    discrepancy_context_in_reservoir = contract$context$include_in_reservoir,
    discrepancy_context_in_readout = contract$context$include_in_readout,
    discrepancy_context_lags = paste(contract$context$lags, collapse = ";"),
    discrepancy_transition_contract_hash = contract$contract_hash,
    stringsAsFactors = FALSE
  )
}

app_glofas_discrepancy_series <- function(panel) {
  required <- c("target_date", "y_transformed")
  missing <- setdiff(required, names(panel))
  if (length(missing)) {
    stop(sprintf(
      "Discrepancy anchor panel is missing: %s.",
      paste(missing, collapse = ", ")
    ), call. = FALSE)
  }
  out <- data.frame(
    date = as.Date(panel$target_date),
    value = as.numeric(panel$y_transformed),
    stringsAsFactors = FALSE
  )
  out <- out[!is.na(out$date) & is.finite(out$value), , drop = FALSE]
  out <- out[order(out$date), , drop = FALSE]
  out <- out[!duplicated(out$date, fromLast = TRUE), , drop = FALSE]
  if (!nrow(out)) stop("Discrepancy anchor history is empty.", call. = FALSE)
  out
}

app_glofas_discrepancy_anchor_one <- function(history, target_date, contract) {
  method <- contract$anchor$method
  if (identical(method, "none")) return(0)
  prior <- history[history$date < as.Date(target_date), , drop = FALSE]
  if (!nrow(prior)) {
    stop(sprintf(
      "Discrepancy anchor at %s has no strictly prior history.",
      as.character(target_date)
    ), call. = FALSE)
  }
  if (identical(method, "last")) return(utils::tail(prior$value, 1L))
  if (method %in% c("rolling_mean", "rolling_median")) {
    values <- utils::tail(prior$value, as.integer(contract$anchor$window))
    return(if (identical(method, "rolling_mean")) {
      mean(values)
    } else {
      stats::median(values)
    })
  }
  if (identical(method, "ewma")) {
    age <- as.numeric(as.Date(target_date) - prior$date)
    weights <- exp(log(0.5) * age / as.numeric(contract$anchor$half_life))
    return(sum(weights * prior$value) / sum(weights))
  }
  stop(sprintf("Unsupported discrepancy anchor method '%s'.", method), call. = FALSE)
}

app_glofas_discrepancy_historical_anchor <- function(
  panel,
  anchor_dates,
  contract
) {
  anchor_dates <- as.Date(anchor_dates)
  history <- app_glofas_discrepancy_series(panel)
  out <- vapply(anchor_dates, function(date) {
    app_glofas_discrepancy_anchor_one(history, date, contract)
  }, numeric(1L))
  if (length(out) != length(anchor_dates) || any(!is.finite(out))) {
    stop("Historical discrepancy anchors are not finite and date aligned.", call. = FALSE)
  }
  out
}

app_glofas_discrepancy_future_anchor <- function(
  panel,
  origin_date,
  horizon,
  contract
) {
  horizon <- suppressWarnings(as.integer(horizon))
  if (!is.finite(horizon) || horizon < 1L) {
    stop("Future discrepancy anchor requires a positive horizon.", call. = FALSE)
  }
  history <- app_glofas_discrepancy_series(panel)
  anchor <- app_glofas_discrepancy_anchor_one(
    history,
    as.Date(origin_date) + 1L,
    contract
  )
  rep(anchor, horizon)
}

app_glofas_discrepancy_context_block_config <- function(cfg, contract) {
  vars <- app_glofas_discrepancy_context_variables(contract)
  if (!length(vars)) return(cfg)
  if (!identical(as.character(cfg$.__qdesn_block__ %||% ""), "discrepancy")) {
    stop("GloFAS transition context may only be added to the discrepancy block.", call. = FALSE)
  }
  cfg$covariates <- cfg$covariates %||% list()
  cfg$covariates$enabled <- TRUE
  cfg$covariates$variables <- unique(c(
    as.character(unlist(cfg$covariates$variables %||% c("ppt", "soil"))),
    vars
  ))

  fc_name <- if (!is.null(cfg$feature_contract)) {
    "feature_contract"
  } else if (!is.null(cfg$features)) {
    "features"
  } else {
    "feature_contract"
  }
  fc <- cfg[[fc_name]] %||% list()
  lag_spec <- list(values = as.integer(contract$context$lags))
  if (isTRUE(contract$context$include_in_reservoir)) {
    fc$reservoir_input <- fc$reservoir_input %||% list()
    fc$reservoir_input$covariates <- fc$reservoir_input$covariates %||% list()
    for (variable in vars) fc$reservoir_input$covariates[[variable]] <- lag_spec
  }
  if (isTRUE(contract$context$include_in_readout)) {
    fc$readout <- fc$readout %||% list()
    fc$readout$include_input_block <- TRUE
    fc$readout$input_block <- fc$readout$input_block %||% list()
    fc$readout$input_block$covariates <-
      fc$readout$input_block$covariates %||% list()
    for (variable in vars) {
      fc$readout$input_block$covariates[[variable]] <- lag_spec
    }
  }
  cfg[[fc_name]] <- fc
  cfg
}

app_glofas_discrepancy_context_timeline <- function(
  base_timeline,
  latent_data,
  p0,
  contract
) {
  variables <- app_glofas_discrepancy_context_variables(contract)
  if (!length(variables)) return(base_timeline)
  origin_date <- as.Date(latent_data$origin_date)
  historical <- data.frame(
    date = as.Date(latent_data$g_retro$target_date),
    glofas_level = as.numeric(latent_data$g_retro$g_transformed),
    stringsAsFactors = FALSE
  )
  historical <- historical[
    !is.na(historical$date) & is.finite(historical$glofas_level) &
      historical$date <= origin_date,
    ,
    drop = FALSE
  ]
  historical <- historical[order(historical$date), , drop = FALSE]
  historical <- historical[!duplicated(historical$date, fromLast = TRUE), , drop = FALSE]
  if (!nrow(historical)) {
    stop("GloFAS context requires finite retrospective levels through the origin.", call. = FALSE)
  }

  qg_future <- app_latent_path_glofas_quantile_path(latent_data, p0)
  future <- data.frame(
    date = as.Date(latent_data$future_key$target_date),
    glofas_level = as.numeric(qg_future),
    stringsAsFactors = FALSE
  )
  if (any(!is.finite(future$glofas_level))) {
    stop("GloFAS context requires a finite issued-ensemble quantile path.", call. = FALSE)
  }

  if (is.null(base_timeline)) {
    timeline <- data.frame(
      date = sort(unique(c(historical$date, future$date))),
      stringsAsFactors = FALSE
    )
    attr(timeline, "variables") <- character()
    attr(timeline, "scale_params") <- list()
    attr(timeline, "cutoff_date") <- as.character(origin_date)
    attr(timeline, "covariate_future_policy") <- "glofas_issued_context"
    attr(timeline, "covariate_source_provider") <- "glofas_bundle"
  } else {
    timeline <- base_timeline
    timeline$date <- as.Date(timeline$date)
  }
  values <- c(historical$glofas_level, future$glofas_level)
  dates <- c(historical$date, future$date)
  timeline$glofas_level <- values[match(timeline$date, dates)]

  anomaly_window <- as.integer(contract$context$anomaly_window)
  historical_anomaly <- vapply(seq_len(nrow(historical)), function(i) {
    if (i == 1L) return(0)
    reference <- utils::tail(historical$glofas_level[seq_len(i - 1L)], anomaly_window)
    historical$glofas_level[[i]] - mean(reference)
  }, numeric(1L))
  origin_reference <- mean(utils::tail(historical$glofas_level, anomaly_window))
  future_anomaly <- future$glofas_level - origin_reference
  anomaly_values <- c(historical_anomaly, future_anomaly)
  timeline$glofas_anomaly <- anomaly_values[match(timeline$date, dates)]

  is_future <- timeline$date > origin_date
  source_role <- ifelse(
    is_future,
    "issued_glofas_quantile_context",
    "retrospective_glofas_context"
  )
  source_policy <- ifelse(
    is_future,
    "issued_ensemble_quantile",
    "retrospective_available"
  )
  for (variable in c("glofas_level", "glofas_anomaly")) {
    history_value <- timeline[[variable]][timeline$date <= origin_date]
    history_value <- history_value[is.finite(history_value)]
    if (!length(history_value)) {
      stop(sprintf("GloFAS context '%s' has no finite scaling history.", variable), call. = FALSE)
    }
    center <- mean(history_value)
    scale <- stats::sd(history_value)
    if (!is.finite(scale) || scale <= 0) scale <- 1
    timeline[[paste0(variable, "_scaled")]] <-
      (timeline[[variable]] - center) / scale
    timeline[[paste0(variable, "_realized_value")]] <- ifelse(
      is_future,
      NA_real_,
      timeline[[variable]]
    )
    timeline[[paste0(variable, "_gefs_reduced_value")]] <- NA_real_
    timeline[[paste0(variable, "_blend_noise")]] <- 0
    timeline[[paste0(variable, "_role")]] <- source_role
    timeline[[paste0(variable, "_source")]] <- ifelse(
      is_future,
      "issued GloFAS ensemble quantile available at origin",
      "GloFAS retrospective available by target date"
    )
    timeline[[paste0(variable, "_leakage_status")]] <-
      "origin-available GloFAS context; no future USGS value used"
    timeline[[paste0(variable, "_source_policy")]] <- source_policy
    timeline[[paste0(variable, "_source_provider")]] <- "glofas_bundle"
    timeline[[paste0(variable, "_source_variable")]] <- variable
    timeline[[paste0(variable, "_source_path")]] <- NA_character_
    timeline[[paste0(variable, "_source_sha256")]] <- NA_character_
    timeline[[paste0(variable, "_uses_realized_future")]] <- FALSE
    scale_params <- attr(timeline, "scale_params") %||% list()
    scale_params[[variable]] <- list(center = center, scale = scale)
    attr(timeline, "scale_params") <- scale_params
  }
  attr(timeline, "variables") <- unique(c(
    attr(timeline, "variables") %||% character(),
    variables
  ))
  attr(timeline, "glofas_context_variables") <- variables
  attr(timeline, "glofas_context_contract_hash") <- contract$contract_hash
  attr(timeline, "glofas_context_origin_date") <- as.character(origin_date)
  attr(timeline, "glofas_context_quantile") <- as.numeric(p0)
  timeline
}

app_glofas_discrepancy_ensemble_context_summary <- function(latent_data, p0) {
  key <- latent_data$future_key
  rows <- lapply(seq_len(nrow(key)), function(i) {
    idx <- latent_data$g_ensemble$target_date == key$target_date[[i]] &
      latent_data$g_ensemble$horizon == key$horizon[[i]]
    values <- as.numeric(latent_data$g_ensemble$g_transformed[idx])
    values <- values[is.finite(values)]
    data.frame(
      target_date = as.Date(key$target_date[[i]]),
      horizon = as.integer(key$horizon[[i]]),
      quantile_level = as.numeric(p0),
      glofas_quantile = app_ensemble_quantile(
        latent_data$g_ensemble[idx, , drop = FALSE],
        p0
      ),
      glofas_member_mean = mean(values),
      glofas_member_sd = stats::sd(values),
      glofas_member_iqr = stats::IQR(values),
      n_members = length(values),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_glofas_discrepancy_causal_baselines <- function(
  discrepancy_panel,
  origin_date,
  horizon
) {
  methods <- list(
    last = list(anchor = list(method = "last")),
    rolling_mean_14 = list(anchor = list(method = "rolling_mean", window = 14L)),
    rolling_mean_30 = list(anchor = list(method = "rolling_mean", window = 30L)),
    rolling_mean_50 = list(anchor = list(method = "rolling_mean", window = 50L)),
    rolling_mean_90 = list(anchor = list(method = "rolling_mean", window = 90L)),
    rolling_median_30 = list(anchor = list(method = "rolling_median", window = 30L)),
    rolling_median_50 = list(anchor = list(method = "rolling_median", window = 50L)),
    ewma_14 = list(anchor = list(method = "ewma", half_life = 14)),
    ewma_30 = list(anchor = list(method = "ewma", half_life = 30))
  )
  rows <- lapply(names(methods), function(name) {
    cfg <- list(
      prediction = list(
        discrepancy_transition = c(
          methods[[name]],
          list(
            evolution = list(method = "static_anchor_innovation"),
            context = list()
          )
        )
      )
    )
    contract <- app_glofas_discrepancy_transition_contract(cfg)
    value <- app_glofas_discrepancy_future_anchor(
      discrepancy_panel,
      origin_date,
      horizon,
      contract
    )
    data.frame(
      baseline_id = name,
      horizon = seq_len(horizon),
      discrepancy = value,
      transition_contract_hash = contract$contract_hash,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}
