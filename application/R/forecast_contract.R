# Forecast-contract helpers for the GloFAS discrepancy-calibration workflow.

app_prediction_contract_defaults <- function() {
  list(
    contract_version = "0.2",
    target = "reference_quantile_from_glofas_discrepancy",
    horizon_scope = "issued_glofas_only",
    q_g_source = "ensemble_empirical_quantile",
    discrepancy_feature_strategy = "origin_state_pilot",
    prediction_unit = "point_bridge",
    posterior_draw_contract = "q_y_draw_equals_q_g_draw_minus_d_g_draw",
    posterior_predictive_sampling = "disabled",
    beyond_issued_horizon = "disabled"
  )
}

app_prediction_contract <- function(cfg, model_family = NULL) {
  defaults <- app_prediction_contract_defaults()
  user <- cfg$prediction %||% list()
  out <- defaults
  for (nm in names(user)) out[[nm]] <- user[[nm]]

  out$contract_version <- as.character(out$contract_version %||% defaults$contract_version)
  out$target <- as.character(out$target %||% defaults$target)
  out$horizon_scope <- as.character(out$horizon_scope %||% defaults$horizon_scope)
  out$q_g_source <- as.character(out$q_g_source %||% defaults$q_g_source)
  out$discrepancy_feature_strategy <- as.character(out$discrepancy_feature_strategy %||% defaults$discrepancy_feature_strategy)
  out$prediction_unit <- as.character(out$prediction_unit %||% defaults$prediction_unit)
  out$posterior_draw_contract <- as.character(out$posterior_draw_contract %||% defaults$posterior_draw_contract)
  out$posterior_predictive_sampling <- as.character(out$posterior_predictive_sampling %||% defaults$posterior_predictive_sampling)
  out$beyond_issued_horizon <- as.character(out$beyond_issued_horizon %||% defaults$beyond_issued_horizon)

  if (identical(model_family, "raw_glofas")) {
    out$target <- "raw_glofas_forecast_system_quantile"
    out$q_g_source <- "ensemble_empirical_quantile"
    out$discrepancy_feature_strategy <- "none"
    out$prediction_unit <- "raw_point_baseline"
    out$posterior_draw_contract <- "not_applicable"
    out$posterior_predictive_sampling <- "not_applicable"
  }

  app_validate_prediction_contract(out, model_family = model_family)
  out
}

app_prediction_contract_name <- function(contract, model_family) {
  if (identical(model_family, "raw_glofas")) return("raw_glofas_ensemble_quantile")
  if (identical(contract$target, "reference_quantile_from_glofas_discrepancy") &&
      identical(contract$horizon_scope, "issued_glofas_only") &&
      identical(contract$q_g_source, "ensemble_empirical_quantile") &&
      identical(contract$discrepancy_feature_strategy, "origin_state_pilot") &&
      identical(contract$prediction_unit, "point_bridge")) {
    return("pilot_origin_state_glofas_quantile_minus_discrepancy")
  }
  if (identical(contract$target, "reference_quantile_from_glofas_discrepancy") &&
      identical(contract$prediction_unit, "posterior_draw")) {
    return("posterior_draw_glofas_quantile_minus_discrepancy")
  }
  paste(
    contract$target,
    contract$horizon_scope,
    contract$q_g_source,
    contract$discrepancy_feature_strategy,
    contract$prediction_unit,
    sep = "__"
  )
}

app_validate_prediction_contract <- function(contract, model_family = NULL) {
  allowed <- list(
    target = c("reference_quantile_from_glofas_discrepancy", "raw_glofas_forecast_system_quantile"),
    horizon_scope = c("issued_glofas_only"),
    q_g_source = c("ensemble_empirical_quantile", "ensemble_bayesian_bootstrap_quantile", "posterior_model_quantile"),
    discrepancy_feature_strategy = c("origin_state_pilot", "horizon_indexed_origin_state", "recursive_latent_path", "none"),
    prediction_unit = c("point_bridge", "posterior_draw", "raw_point_baseline"),
    posterior_draw_contract = c("q_y_draw_equals_q_g_draw_minus_d_g_draw", "not_applicable"),
    posterior_predictive_sampling = c("disabled", "exal_working_likelihood", "al_working_likelihood", "not_applicable"),
    beyond_issued_horizon = c("disabled")
  )
  for (nm in names(allowed)) {
    value <- as.character(contract[[nm]] %||% "")
    if (!value %in% allowed[[nm]]) {
      stop(
        sprintf(
          "Unsupported prediction contract value for '%s': '%s'. Allowed values: %s.",
          nm,
          value,
          paste(allowed[[nm]], collapse = ", ")
        ),
        call. = FALSE
      )
    }
  }

  if (identical(model_family, "qdesn_glofas_discrepancy") &&
      !identical(contract$target, "reference_quantile_from_glofas_discrepancy")) {
    stop("The discrepancy model must target reference_quantile_from_glofas_discrepancy.", call. = FALSE)
  }
  if (identical(model_family, "raw_glofas") &&
      !identical(contract$discrepancy_feature_strategy, "none")) {
    stop("The raw GloFAS baseline cannot use a discrepancy feature strategy.", call. = FALSE)
  }
  if (identical(model_family, "qdesn_glofas_discrepancy") &&
      identical(contract$prediction_unit, "posterior_draw") &&
      !identical(contract$posterior_draw_contract, "q_y_draw_equals_q_g_draw_minus_d_g_draw")) {
    stop("Posterior-draw discrepancy predictions must use q_y_draw_equals_q_g_draw_minus_d_g_draw.", call. = FALSE)
  }
  if (identical(model_family, "qdesn_glofas_discrepancy") &&
      identical(contract$prediction_unit, "posterior_draw") &&
      !contract$q_g_source %in% c("posterior_model_quantile", "ensemble_empirical_quantile", "ensemble_bayesian_bootstrap_quantile")) {
    stop("Posterior-draw discrepancy predictions use an unsupported q_g_source.", call. = FALSE)
  }
  if (identical(model_family, "qdesn_glofas_discrepancy") &&
      identical(contract$prediction_unit, "posterior_draw") &&
      !contract$discrepancy_feature_strategy %in% c("horizon_indexed_origin_state", "recursive_latent_path")) {
    stop(
      "Posterior-draw discrepancy predictions must use discrepancy_feature_strategy = ",
      "'horizon_indexed_origin_state' or 'recursive_latent_path'.",
      call. = FALSE
    )
  }

  invisible(TRUE)
}

app_ensemble_quantile <- function(block, p0) {
  as.numeric(stats::quantile(
    block$g_transformed,
    probs = p0,
    names = FALSE,
    na.rm = TRUE
  ))
}

app_weighted_quantile <- function(x, weights, p0) {
  x <- as.numeric(x)
  weights <- as.numeric(weights)
  keep <- is.finite(x) & is.finite(weights) & weights >= 0
  x <- x[keep]
  weights <- weights[keep]
  if (!length(x)) return(NA_real_)
  if (sum(weights) <= 0) weights <- rep(1, length(weights))
  ord <- order(x)
  x <- x[ord]
  weights <- weights[ord] / sum(weights)
  x[[which(cumsum(weights) >= p0)[[1L]]]]
}

app_ensemble_bayesian_bootstrap_quantiles <- function(values, p0, n_draws, seed = NULL) {
  values <- as.numeric(values)
  values <- values[is.finite(values)]
  n_draws <- as.integer(n_draws)
  if (!length(values) || !is.finite(n_draws) || n_draws <= 0L) return(numeric())

  old_seed <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
    get(".Random.seed", envir = .GlobalEnv)
  } else {
    NULL
  }
  on.exit({
    if (is.null(old_seed)) {
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
    } else {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    }
  }, add = TRUE)
  if (!is.null(seed) && is.finite(as.integer(seed))) set.seed(as.integer(seed))

  vapply(seq_len(n_draws), function(i) {
    w <- stats::rexp(length(values), rate = 1)
    app_weighted_quantile(values, w, p0)
  }, numeric(1L))
}

app_prediction_qg_draw_matrix <- function(panel, row_info, p0, n_draws, q_g_source, seed = NULL) {
  panel$origin_date <- as.Date(panel$origin_date)
  panel$target_date <- as.Date(panel$target_date)
  panel$horizon <- as.integer(panel$horizon)
  row_info$origin_date <- as.Date(row_info$origin_date)
  row_info$target_date <- as.Date(row_info$target_date)
  row_info$horizon <- as.integer(row_info$horizon)
  q_g_source <- as.character(q_g_source)
  n_draws <- as.integer(n_draws)
  out <- matrix(NA_real_, nrow = n_draws, ncol = nrow(row_info))

  for (j in seq_len(nrow(row_info))) {
    idx <- panel$is_ensemble &
      is.finite(panel$g_transformed) &
      panel$origin_date == row_info$origin_date[[j]] &
      panel$target_date == row_info$target_date[[j]] &
      panel$horizon == row_info$horizon[[j]]
    values <- as.numeric(panel$g_transformed[idx])
    if (!length(values)) {
      stop(
        sprintf(
          "No issued GloFAS ensemble members found for origin %s, target %s, horizon %s.",
          row_info$origin_date[[j]], row_info$target_date[[j]], row_info$horizon[[j]]
        ),
        call. = FALSE
      )
    }
    if (identical(q_g_source, "ensemble_empirical_quantile")) {
      out[, j] <- app_weighted_quantile(values, rep(1, length(values)), p0)
    } else if (identical(q_g_source, "ensemble_bayesian_bootstrap_quantile")) {
      local_seed <- if (!is.null(seed) && is.finite(as.integer(seed))) as.integer(seed) + 1009L * j else NULL
      out[, j] <- app_ensemble_bayesian_bootstrap_quantiles(values, p0, n_draws, seed = local_seed)
    } else {
      stop(sprintf("Unsupported issued-ensemble q_g_source '%s'.", q_g_source), call. = FALSE)
    }
  }
  colnames(out) <- paste0("prediction_row_", seq_len(ncol(out)))
  out
}

app_prediction_contract_metadata <- function(contract, model_family) {
  data.frame(
    prediction_contract = app_prediction_contract_name(contract, model_family),
    contract_version = contract$contract_version,
    forecast_scope = contract$horizon_scope,
    q_g_source = contract$q_g_source,
    discrepancy_feature_strategy = contract$discrepancy_feature_strategy,
    prediction_unit = contract$prediction_unit,
    posterior_draw_contract = contract$posterior_draw_contract,
    posterior_predictive_sampling = contract$posterior_predictive_sampling,
    beyond_issued_horizon = contract$beyond_issued_horizon,
    stringsAsFactors = FALSE
  )
}

app_make_raw_glofas_prediction_row <- function(row, key_row, block, p0, cfg) {
  contract <- app_prediction_contract(cfg, model_family = "raw_glofas")
  q_g_hat <- app_ensemble_quantile(block, p0)
  y_ref <- block$y_transformed[[which(is.finite(block$y_transformed))[1L]]]
  cbind(
    data.frame(
      fit_id = row$fit_id[[1L]],
      model_id = row$model_id[[1L]],
      model_family = row$model_family[[1L]],
      quantile_level = p0,
      qhat = q_g_hat,
      y_reference = y_ref,
      q_g_hat = q_g_hat,
      d_g_hat = NA_real_,
      raw_glofas_quantile = q_g_hat,
      discrepancy_hat = NA_real_,
      discrepancy_feature_date = as.Date(NA),
      stringsAsFactors = FALSE
    ),
    app_prediction_contract_metadata(contract, model_family = "raw_glofas"),
    key_row
  )
}

app_make_discrepancy_prediction_row <- function(result, key_row, block, p0, q_g_hat, d_g_hat, feature_date, cfg) {
  contract <- app_prediction_contract(cfg, model_family = "qdesn_glofas_discrepancy")
  y_ref <- block$y_transformed[[which(is.finite(block$y_transformed))[1L]]]
  cbind(
    data.frame(
      fit_id = result$fit_id,
      model_id = result$model_id,
      model_family = result$model_family,
      quantile_level = p0,
      qhat = q_g_hat - d_g_hat,
      y_reference = y_ref,
      q_g_hat = q_g_hat,
      d_g_hat = d_g_hat,
      raw_glofas_quantile = q_g_hat,
      discrepancy_hat = d_g_hat,
      discrepancy_feature_date = as.Date(feature_date),
      stringsAsFactors = FALSE
    ),
    app_prediction_contract_metadata(contract, model_family = "qdesn_glofas_discrepancy"),
    key_row
  )
}

app_validate_prediction_table_contract <- function(predictions, final_launch = FALSE) {
  required <- c(
    "prediction_contract", "contract_version", "forecast_scope", "q_g_source",
    "discrepancy_feature_strategy", "prediction_unit", "posterior_draw_contract",
    "posterior_predictive_sampling", "beyond_issued_horizon", "q_g_hat", "d_g_hat",
    "qhat", "model_family"
  )
  missing <- setdiff(required, names(predictions))
  if (length(missing)) {
    stop(sprintf("Prediction table is missing contract columns: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }

  if (any(!nzchar(as.character(predictions$prediction_contract)))) {
    stop("Prediction table contains blank prediction_contract values.", call. = FALSE)
  }

  disc <- predictions$model_family == "qdesn_glofas_discrepancy"
  if (any(disc)) {
    lhs <- as.numeric(predictions$qhat[disc])
    rhs <- as.numeric(predictions$q_g_hat[disc]) - as.numeric(predictions$d_g_hat[disc])
    ok <- is.finite(lhs) & is.finite(rhs) & abs(lhs - rhs) <= 1.0e-8
    if (!all(ok)) {
      stop("Discrepancy predictions violate qhat = q_g_hat - d_g_hat.", call. = FALSE)
    }
  }

  if (isTRUE(final_launch) && any(startsWith(as.character(predictions$prediction_contract), "pilot_"))) {
    stop("Final launches cannot use prediction contracts whose names begin with 'pilot_'.", call. = FALSE)
  }
  if (isTRUE(final_launch) && any(disc)) {
    unit <- as.character(predictions$prediction_unit[disc])
    if (any(is.na(unit) | unit != "posterior_draw")) {
      stop("Final discrepancy launches must use prediction_unit = 'posterior_draw'.", call. = FALSE)
    }
    q_g_source <- as.character(predictions$q_g_source[disc])
    if (any(is.na(q_g_source) | !q_g_source %in% c("ensemble_bayesian_bootstrap_quantile", "posterior_model_quantile"))) {
      stop("Final discrepancy launches must use a posterior-draw GloFAS quantile source.", call. = FALSE)
    }
  }

  invisible(TRUE)
}

app_validate_posterior_draw_prediction_table <- function(draws, tolerance = 1.0e-8) {
  required <- c(
    "draw_id", "q_y_draw", "q_g_draw", "d_g_draw", "quantile_level",
    "origin_date", "target_date", "horizon", "prediction_contract",
    "prediction_unit", "q_g_source", "posterior_draw_contract",
    "discrepancy_feature_strategy"
  )
  missing <- setdiff(required, names(draws))
  if (length(missing)) {
    stop(
      sprintf(
        "Posterior-draw prediction table is missing required columns: %s",
        paste(missing, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  if (!nrow(draws)) {
    stop("Posterior-draw prediction table has no rows.", call. = FALSE)
  }

  unit <- as.character(draws$prediction_unit)
  if (any(is.na(unit) | unit != "posterior_draw")) {
    stop("Posterior-draw prediction rows must use prediction_unit = 'posterior_draw'.", call. = FALSE)
  }
  contract <- as.character(draws$posterior_draw_contract)
  if (any(is.na(contract) | contract != "q_y_draw_equals_q_g_draw_minus_d_g_draw")) {
    stop(
      "Posterior-draw prediction rows must record posterior_draw_contract = ",
      "'q_y_draw_equals_q_g_draw_minus_d_g_draw'.",
      call. = FALSE
    )
  }
  q_g_source <- as.character(draws$q_g_source)
  if (any(is.na(q_g_source) | !q_g_source %in% c("posterior_model_quantile", "ensemble_empirical_quantile", "ensemble_bayesian_bootstrap_quantile"))) {
    stop(
      "Posterior-draw prediction rows must record a supported q_g_source.",
      call. = FALSE
    )
  }
  feature_strategy <- as.character(draws$discrepancy_feature_strategy)
  allowed_feature_strategies <- c("horizon_indexed_origin_state", "recursive_latent_path")
  if (any(is.na(feature_strategy) | !feature_strategy %in% allowed_feature_strategies)) {
    stop(
      "Posterior-draw prediction rows must record discrepancy_feature_strategy = ",
      "'horizon_indexed_origin_state' or 'recursive_latent_path'.",
      call. = FALSE
    )
  }

  q_y <- as.numeric(draws$q_y_draw)
  q_g <- as.numeric(draws$q_g_draw)
  d_g <- as.numeric(draws$d_g_draw)
  finite <- is.finite(q_y) & is.finite(q_g) & is.finite(d_g)
  if (!all(finite)) {
    stop("Posterior-draw prediction table contains non-finite quantile draws.", call. = FALSE)
  }

  ok <- abs(q_y - (q_g - d_g)) <= tolerance
  if (!all(ok)) {
    stop("Posterior-draw predictions violate q_y_draw = q_g_draw - d_g_draw.", call. = FALSE)
  }

  if (any(is.na(draws$draw_id) | !nzchar(as.character(draws$draw_id)))) {
    stop("Posterior-draw prediction table contains blank draw_id values.", call. = FALSE)
  }
  if (any(is.na(draws$origin_date) | is.na(draws$target_date))) {
    stop("Posterior-draw prediction table contains missing forecast dates.", call. = FALSE)
  }

  invisible(TRUE)
}
