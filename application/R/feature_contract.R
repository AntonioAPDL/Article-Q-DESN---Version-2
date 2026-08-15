# Feature-contract helpers for the GloFAS Q-DESN application.
#
# The application owns the readout feature contract. The reservoir builder may
# use an internal input bias, but the readout design has a separate, explicit
# intercept. Direct input features appended to the readout never include the
# reservoir's internal bias column.

app_parse_lag_spec <- function(spec, default = integer(0), allow_zero = TRUE, label = "lags") {
  if (is.null(spec)) spec <- default
  if (is.null(spec)) spec <- integer(0)

  if (is.list(spec) && !is.data.frame(spec)) {
    if (!is.null(spec$range)) {
      rr <- as.integer(unlist(spec$range, use.names = FALSE))
      if (length(rr) != 2L || any(!is.finite(rr))) {
        stop(sprintf("%s range must contain exactly two finite integers.", label), call. = FALSE)
      }
      if (rr[[1L]] > rr[[2L]]) {
        stop(sprintf("%s range lower endpoint cannot exceed upper endpoint.", label), call. = FALSE)
      }
      vals <- seq.int(rr[[1L]], rr[[2L]])
    } else if (!is.null(spec$values)) {
      vals <- as.integer(unlist(spec$values, use.names = FALSE))
    } else if (!is.null(spec$lags)) {
      vals <- app_parse_lag_spec(spec$lags, default = default, allow_zero = allow_zero, label = label)
    } else {
      vals <- as.integer(unlist(spec, use.names = FALSE))
    }
  } else {
    vals <- as.integer(unlist(spec, use.names = FALSE))
  }

  vals <- vals[is.finite(vals)]
  if (length(vals) && any(vals < 0L)) {
    stop(sprintf("%s must be nonnegative.", label), call. = FALSE)
  }
  if (!isTRUE(allow_zero) && any(vals == 0L)) {
    stop(sprintf("%s cannot include lag 0.", label), call. = FALSE)
  }
  sort(unique(vals))
}

app_feature_contract_covariate_variables <- function(cfg) {
  vars <- as.character(unlist((cfg$covariates %||% list())$variables %||% c("ppt", "soil"), use.names = FALSE))
  vars <- unique(vars[nzchar(vars)])
  unknown <- setdiff(vars, c("ppt", "soil"))
  if (length(unknown)) {
    stop(sprintf("Unsupported model covariates: %s. This workflow permits only ppt and soil.", paste(unknown, collapse = ", ")), call. = FALSE)
  }
  vars
}

app_feature_contract_legacy_covariate_lags <- function(cfg) {
  cov <- cfg$covariates %||% list()
  if (!isTRUE(cov$enabled %||% FALSE)) return(list())
  readout <- cov$readout %||% list()
  if (!isTRUE(readout$include_lags %||% TRUE)) return(list())
  lags <- app_parse_lag_spec(readout$lags %||% 0L, default = 0L, allow_zero = TRUE, label = "covariates.readout.lags")
  vars <- app_feature_contract_covariate_variables(cfg)
  out <- rep(list(lags), length(vars))
  names(out) <- vars
  out
}

app_feature_contract_parse_covariate_lags <- function(cov_spec, cfg) {
  if (is.null(cov_spec)) return(app_feature_contract_legacy_covariate_lags(cfg))
  if (!is.list(cov_spec)) {
    stop("feature_contract.readout.input_block.covariates must be a named list.", call. = FALSE)
  }
  vars <- names(cov_spec)
  vars <- vars[nzchar(vars)]
  unknown <- setdiff(vars, c("ppt", "soil"))
  if (length(unknown)) {
    stop(sprintf("Unsupported feature-contract covariates: %s.", paste(unknown, collapse = ", ")), call. = FALSE)
  }
  out <- list()
  for (v in vars) {
    out[[v]] <- app_parse_lag_spec(cov_spec[[v]], default = integer(0), allow_zero = TRUE, label = sprintf("%s readout lags", v))
  }
  out[vapply(out, length, integer(1L)) > 0L]
}

app_feature_contract_parse_reservoir_covariate_lags <- function(reservoir_input, cfg, has_new_contract) {
  if (!isTRUE(has_new_contract)) return(list())
  if (!"covariates" %in% names(reservoir_input)) return(list())
  app_feature_contract_parse_covariate_lags(reservoir_input$covariates, cfg)
}

app_feature_contract <- function(cfg) {
  fc <- cfg$feature_contract %||% cfg$features %||% list()
  has_new_contract <- length(fc) > 0L

  r_m <- as.integer((cfg$reservoir %||% list())$m %||% 0L)
  reservoir_input <- fc$reservoir_input %||% list()
  reservoir_output_default <- if (is.finite(r_m) && r_m > 0L) list(range = c(1L, r_m)) else integer(0)
  reservoir_output_lags <- app_parse_lag_spec(
    reservoir_input$output_lags %||% reservoir_output_default,
    default = reservoir_output_default,
    allow_zero = FALSE,
    label = "reservoir input output_lags"
  )
  reservoir_covariate_lags <- app_feature_contract_parse_reservoir_covariate_lags(
    reservoir_input,
    cfg,
    has_new_contract = has_new_contract
  )

  readout <- fc$readout %||% list()
  legacy_readout_intercept <- isTRUE((cfg$reservoir %||% list())$add_bias %||% FALSE)
  input_block <- readout$input_block %||% list()
  legacy_cov_lags <- app_feature_contract_legacy_covariate_lags(cfg)
  include_input_default <- if (isTRUE(has_new_contract)) length(input_block) > 0L else length(legacy_cov_lags) > 0L

  include_internal_bias <- isTRUE(input_block$include_internal_bias %||% FALSE)
  if (isTRUE(include_internal_bias)) {
    stop(
      paste(
        "The direct readout input block cannot include the reservoir's internal",
        "bias. Use feature_contract.readout.add_intercept for the readout",
        "intercept instead."
      ),
      call. = FALSE
    )
  }

  output_lags <- app_parse_lag_spec(
    input_block$output_lags %||% integer(0),
    default = integer(0),
    allow_zero = FALSE,
    label = "readout input output_lags"
  )
  cov_spec <- if ("covariates" %in% names(input_block)) input_block$covariates else NULL
  covariate_lags <- if (isTRUE(has_new_contract) && !"covariates" %in% names(input_block)) {
    list()
  } else {
    app_feature_contract_parse_covariate_lags(cov_spec, cfg)
  }

  list(
    version = as.character(fc$version %||% "0.1"),
    has_new_contract = has_new_contract,
    reservoir_input = list(
      internal_bias = isTRUE(reservoir_input$internal_bias %||% TRUE),
      output_lags = reservoir_output_lags,
      covariate_lags = reservoir_covariate_lags,
      standardize = isTRUE(reservoir_input$standardize %||% (cfg$reservoir$standardize_inputs %||% FALSE))
    ),
    readout = list(
      add_intercept = isTRUE(readout$add_intercept %||% legacy_readout_intercept),
      include_reservoir_state = isTRUE(readout$include_reservoir_state %||% TRUE),
      reservoir_state_lags = app_parse_lag_spec(readout$reservoir_state_lags %||% integer(0), default = integer(0), allow_zero = FALSE, label = "readout reservoir_state_lags"),
      include_input_block = isTRUE(readout$include_input_block %||% include_input_default),
      input_block = list(
        output_lags = output_lags,
        covariates = covariate_lags,
        include_internal_bias = FALSE
      ),
      include_horizon_scaled = isTRUE(readout$include_horizon_scaled %||% TRUE),
      standardize_output_lags = isTRUE(readout$standardize_output_lags %||% TRUE),
      standardize_non_intercept = isTRUE(readout$standardize_non_intercept %||% FALSE)
    ),
    forecast_alignment = list(
      output_lags_anchor = as.character((fc$forecast_alignment %||% list())$output_lags_anchor %||% "origin_date"),
      covariate_lags_anchor = as.character((fc$forecast_alignment %||% list())$covariate_lags_anchor %||% "target_date")
    )
  )
}

app_feature_contract_covariate_lags <- function(cfg) {
  app_feature_contract(cfg)$readout$input_block$covariates
}

app_feature_contract_reservoir_covariate_lags <- function(cfg) {
  app_feature_contract(cfg)$reservoir_input$covariate_lags
}

app_feature_contract_covariate_lag_columns <- function(cfg) {
  lags_by_var <- app_feature_contract_covariate_lags(cfg)
  if (!length(lags_by_var)) return(character(0))
  unlist(lapply(names(lags_by_var), function(v) sprintf("%s_lag_%d", v, lags_by_var[[v]])), use.names = FALSE)
}

app_feature_contract_reservoir_covariate_lag_columns <- function(cfg) {
  lags_by_var <- app_feature_contract_reservoir_covariate_lags(cfg)
  if (!length(lags_by_var)) return(character(0))
  unlist(lapply(names(lags_by_var), function(v) sprintf("%s_lag_%d", v, lags_by_var[[v]])), use.names = FALSE)
}

app_y_lag_matrix <- function(panel, anchor_dates, lags, scale_params = NULL, standardize = TRUE) {
  lags <- as.integer(lags)
  if (!length(lags)) return(list(X = NULL, scale_params = scale_params))
  if (any(lags <= 0L)) stop("Output lag features must use strictly positive lags.", call. = FALSE)

  y_timeline <- panel[, c("target_date", "y_transformed"), drop = FALSE]
  y_timeline$target_date <- as.Date(y_timeline$target_date)
  y_timeline <- y_timeline[is.finite(y_timeline$y_transformed) & !is.na(y_timeline$target_date), , drop = FALSE]
  y_timeline <- y_timeline[order(y_timeline$target_date), , drop = FALSE]
  y_timeline <- y_timeline[!duplicated(y_timeline$target_date), , drop = FALSE]
  anchor_dates <- as.Date(anchor_dates)

  cols <- list()
  col_names <- character()
  for (L in lags) {
    lookup <- anchor_dates - L
    idx <- match(lookup, y_timeline$target_date)
    if (any(is.na(idx))) {
      missing_dates <- sort(unique(lookup[is.na(idx)]))
      stop(sprintf("Output lag y_lag_%d is missing history dates: %s", L, paste(missing_dates, collapse = ", ")), call. = FALSE)
    }
    vals <- as.numeric(y_timeline$y_transformed[idx])
    if (any(!is.finite(vals))) {
      stop(sprintf("Output lag y_lag_%d contains non-finite values.", L), call. = FALSE)
    }
    cols[[length(cols) + 1L]] <- vals
    col_names <- c(col_names, sprintf("y_lag_%d", L))
  }

  X <- do.call(cbind, cols)
  colnames(X) <- col_names
  storage.mode(X) <- "double"

  if (isTRUE(standardize)) {
    if (is.null(scale_params)) {
      center <- colMeans(X)
      scale <- apply(X, 2L, stats::sd)
      scale[!is.finite(scale) | scale <= 0] <- 1
      scale_params <- list(columns = col_names, center = center, scale = scale)
    }
    center <- as.numeric(scale_params$center[col_names])
    scale <- as.numeric(scale_params$scale[col_names])
    if (any(!is.finite(center)) || any(!is.finite(scale)) || any(scale <= 0)) {
      stop("Invalid output-lag scaling parameters.", call. = FALSE)
    }
    X <- sweep(X, 2L, center, "-")
    X <- sweep(X, 2L, scale, "/")
  } else if (is.null(scale_params)) {
    scale_params <- list(columns = col_names, center = rep(0, length(col_names)), scale = rep(1, length(col_names)))
  }

  list(X = X, scale_params = scale_params)
}

app_feature_info_rows <- function(columns, block, variable = NA_character_, lag = NA_integer_, anchor = "target_date", is_intercept = FALSE, is_internal_bias = FALSE) {
  if (!length(columns)) return(data.frame())
  if (length(variable) == 1L) variable <- rep(variable, length(columns))
  if (length(lag) == 1L) lag <- rep(lag, length(columns))
  data.frame(
    column_name = columns,
    block = block,
    variable = variable,
    lag = as.integer(lag),
    anchor = anchor,
    is_intercept = is_intercept,
    is_internal_bias = is_internal_bias,
    stringsAsFactors = FALSE
  )
}

app_readout_feature_counts <- function(feature_info) {
  if (is.null(feature_info) || !nrow(feature_info)) {
    return(list(
      n_intercept_features = 0L,
      n_reservoir_features = 0L,
      n_reservoir_lag_features = 0L,
      n_direct_output_lag_features = 0L,
      n_direct_covariate_lag_features = 0L,
      n_horizon_features = 0L
    ))
  }
  block <- as.character(feature_info$block)
  list(
    n_intercept_features = sum(block == "readout_intercept"),
    n_reservoir_features = sum(block == "reservoir_state"),
    n_reservoir_lag_features = sum(block == "reservoir_state_lag"),
    n_direct_output_lag_features = sum(block == "direct_output_lag"),
    n_direct_covariate_lag_features = sum(block == "direct_covariate_lag"),
    n_horizon_features = sum(block == "horizon")
  )
}

app_build_readout_feature_matrix <- function(
  reservoir_X,
  panel,
  cfg,
  output_anchor_dates,
  covariate_target_dates,
  horizon = NULL,
  feature_strategy = "origin_state_pilot",
  horizon_scale = NULL,
  feature_meta = NULL,
  fit_scale = TRUE
) {
  contract <- app_feature_contract(cfg)
  reservoir_X <- as.matrix(reservoir_X)
  storage.mode(reservoir_X) <- "double"
  if (nrow(reservoir_X) != length(output_anchor_dates) || nrow(reservoir_X) != length(covariate_target_dates)) {
    stop("Readout feature assembly received incompatible row counts.", call. = FALSE)
  }

  blocks <- list()
  info_rows <- list()
  k <- 1L

  if (length(contract$readout$reservoir_state_lags)) {
    stop(
      paste(
        "readout.reservoir_state_lags is reserved for a later lagged-state",
        "design. Use readout.input_block.output_lags for direct response-lag",
        "features in the current application workflow."
      ),
      call. = FALSE
    )
  }

  if (isTRUE(contract$readout$add_intercept)) {
    X_int <- matrix(1, nrow = nrow(reservoir_X), ncol = 1L)
    colnames(X_int) <- "readout_intercept"
    blocks[[k]] <- X_int
    info_rows[[k]] <- app_feature_info_rows("readout_intercept", "readout_intercept", is_intercept = TRUE)
    k <- k + 1L
  }

  if (isTRUE(contract$readout$include_reservoir_state)) {
    X_res <- reservoir_X
    colnames(X_res) <- paste0("reservoir_", sprintf("%04d", seq_len(ncol(X_res))))
    blocks[[k]] <- X_res
    info_rows[[k]] <- app_feature_info_rows(colnames(X_res), "reservoir_state", anchor = "reservoir_feature_date")
    k <- k + 1L
  }

  scale_info <- feature_meta$readout_scale_info %||% list()
  if (isTRUE(contract$readout$include_input_block)) {
    y_lags <- contract$readout$input_block$output_lags
    if (length(y_lags)) {
      y_scale <- if (isTRUE(fit_scale)) NULL else scale_info$output_lags
      y_block <- app_y_lag_matrix(
        panel = panel,
        anchor_dates = output_anchor_dates,
        lags = y_lags,
        scale_params = y_scale,
        standardize = isTRUE(contract$readout$standardize_output_lags)
      )
      if (!is.null(y_block$X) && ncol(y_block$X)) {
        blocks[[k]] <- y_block$X
        info_rows[[k]] <- app_feature_info_rows(
          colnames(y_block$X),
          "direct_output_lag",
          variable = "y",
          lag = y_lags,
          anchor = contract$forecast_alignment$output_lags_anchor
        )
        scale_info$output_lags <- y_block$scale_params
        k <- k + 1L
      }
    }

    cov_lags <- contract$readout$input_block$covariates
    if (length(cov_lags)) {
      timeline <- app_panel_covariate_timeline(panel, required = TRUE)
      X_cov <- app_covariate_lag_matrix(
        timeline,
        target_dates = covariate_target_dates,
        cfg = cfg,
        lags_by_var = cov_lags
      )
      if (!is.null(X_cov) && ncol(X_cov)) {
        blocks[[k]] <- X_cov
        vars <- sub("_lag_.*$", "", colnames(X_cov))
        lags <- as.integer(sub("^.*_lag_", "", colnames(X_cov)))
        info_rows[[k]] <- app_feature_info_rows(
          colnames(X_cov),
          "direct_covariate_lag",
          variable = vars,
          lag = lags,
          anchor = contract$forecast_alignment$covariate_lags_anchor
        )
        k <- k + 1L
      }
    }
  }

  use_horizon <- isTRUE(contract$readout$include_horizon_scaled) &&
    identical(as.character(feature_strategy), "horizon_indexed_origin_state")
  if (isTRUE(use_horizon)) {
    horizon <- suppressWarnings(as.numeric(horizon))
    if (length(horizon) != nrow(reservoir_X) || any(!is.finite(horizon))) {
      stop("Horizon-indexed readout features require one finite horizon per row.", call. = FALSE)
    }
    horizon_scale <- suppressWarnings(as.numeric(horizon_scale))
    if (!is.finite(horizon_scale) || horizon_scale <= 0) {
      stop("Horizon-indexed readout features require a positive horizon scale.", call. = FALSE)
    }
    X_h <- matrix(horizon / horizon_scale, ncol = 1L)
    colnames(X_h) <- "horizon_scaled"
    blocks[[k]] <- X_h
    info_rows[[k]] <- app_feature_info_rows("horizon_scaled", "horizon", variable = "horizon", lag = 0L, anchor = "target_date")
    k <- k + 1L
  }

  if (!length(blocks)) {
    stop("Readout feature contract produced zero columns.", call. = FALSE)
  }
  X <- do.call(cbind, blocks)
  storage.mode(X) <- "double"
  feature_info <- app_bind_rows_fill(info_rows)
  rownames(feature_info) <- NULL
  feature_info$column_index <- seq_len(nrow(feature_info))
  feature_info <- feature_info[, c("column_index", setdiff(names(feature_info), "column_index")), drop = FALSE]

  if (anyDuplicated(colnames(X))) {
    dup <- unique(colnames(X)[duplicated(colnames(X))])
    stop(sprintf("Readout feature names are duplicated: %s", paste(dup, collapse = ", ")), call. = FALSE)
  }

  list(
    X = X,
    feature_info = feature_info,
    readout_scale_info = scale_info,
    contract = contract
  )
}

app_validate_readout_feature_design <- function(X, feature_info, contract = NULL, check_reservoir_bias = TRUE) {
  X <- as.matrix(X)
  if (any(!is.finite(X))) stop("Readout feature matrix contains non-finite values.", call. = FALSE)
  if (is.null(feature_info) || !nrow(feature_info)) return(invisible(TRUE))

  if (nrow(feature_info) != ncol(X)) {
    stop("Readout feature metadata must contain one row per readout column.", call. = FALSE)
  }
  if (any(as.logical(feature_info$is_internal_bias), na.rm = TRUE)) {
    stop("Readout feature metadata contains an internal reservoir bias column.", call. = FALSE)
  }

  intercept_cols <- feature_info$column_index[which(as.logical(feature_info$is_intercept) %in% TRUE)]
  wants_intercept <- isTRUE((contract %||% list())$readout$add_intercept %||% length(intercept_cols) > 0L)
  if (isTRUE(wants_intercept)) {
    if (length(intercept_cols) != 1L) {
      stop("Readout designs with an intercept must declare exactly one intercept column.", call. = FALSE)
    }
    if (!all(abs(X[, intercept_cols, drop = TRUE] - 1) <= 1.0e-10)) {
      stop("The declared readout intercept column must be equal to one.", call. = FALSE)
    }
  } else if (length(intercept_cols)) {
    stop("Readout intercept is disabled but metadata declares an intercept column.", call. = FALSE)
  }

  if (isTRUE(check_reservoir_bias) && nrow(X) > 1L) {
    constant_cols <- setdiff(app_constant_one_columns(X), as.integer(intercept_cols))
    if (length(constant_cols)) {
      constant_blocks <- as.character(feature_info$block[constant_cols])
      if (any(constant_blocks == "reservoir_state")) {
        stop("A reservoir-state readout column is constant one; the reservoir input bias must not appear in the readout block.", call. = FALSE)
      }
    }
  }
  invisible(TRUE)
}
