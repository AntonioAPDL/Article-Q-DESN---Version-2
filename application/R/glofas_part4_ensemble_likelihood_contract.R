# GloFAS Part 4 fixed ensemble-likelihood launch contract.
#
# This module prepares gated Part 4 artifacts from frozen G1/G2 winners. An
# exact-design Part 3 joint fit may be supplied as an optional initializer. It
# does not fit models. Production execution is delegated to the explicit Part 4
# family workers and remains blocked until separate operator approval.

app_glofas_part4_quantile_grid <- function() {
  c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95)
}

app_glofas_part4_quantile_id <- function(q) {
  sprintf("p%02d", as.integer(round(as.numeric(q) * 100)))
}

app_glofas_part4_model_families <- function() {
  data.frame(
    part4_family = c(
      "independent_al_rhs_vb",
      "independent_exal_rhs_vb",
      "joint_al_rhs_vb",
      "joint_exal_rhs_vb",
      "normal_ridge_diagnostic",
      "normal_rhs_vb_diagnostic"
    ),
    likelihood_family = c("al", "exal", "al", "exal", "normal", "normal"),
    inference_method = rep("vb_ld", 6L),
    coefficient_prior = c("rhs", "rhs", "rhs", "rhs", "ridge", "rhs"),
    quantile_slots = c(7L, 7L, 1L, 1L, 1L, 1L),
    executable_status = rep("implemented_tested_not_launched", 6L),
    stringsAsFactors = FALSE
  )
}

app_glofas_part4_required_anchor_columns <- function() {
  c(
    "role",
    "stage",
    "candidate_id",
    "source_runtime_root",
    "score_path",
    "method",
    "status",
    "n_vector",
    "m",
    "output_lag_max",
    "covariate_lag_max",
    "washout",
    "alpha",
    "rho",
    "seed",
    "rhs_tau0",
    "design_hash",
    "frozen"
  )
}

app_glofas_part4_expected_anchor_roles <- function() {
  c("reference_anchor", "discrepancy_anchor")
}

app_glofas_part4_allowed_anchor_roles <- function() {
  c(app_glofas_part4_expected_anchor_roles(), "historical_joint_anchor")
}

app_glofas_part4_truthy <- function(x) {
  if (is.logical(x)) return(isTRUE(x[[1L]]))
  tolower(trimws(as.character(x[[1L]]))) %in% c("true", "t", "yes", "y", "1")
}

app_glofas_part4_numeric_scalar <- function(x, label, positive = FALSE, nonnegative = FALSE) {
  value <- suppressWarnings(as.numeric(as.character(x[[1L]])))
  if (length(value) != 1L || !is.finite(value)) {
    stop(sprintf("%s must be one finite numeric value.", label), call. = FALSE)
  }
  if (isTRUE(positive) && value <= 0) {
    stop(sprintf("%s must be positive.", label), call. = FALSE)
  }
  if (isTRUE(nonnegative) && value < 0) {
    stop(sprintf("%s must be nonnegative.", label), call. = FALSE)
  }
  value
}

app_glofas_part4_parse_numeric_vector <- function(x, label) {
  if (is.null(x) || !length(x)) {
    stop(sprintf("%s is missing.", label), call. = FALSE)
  }
  if (is.numeric(x) && length(x) > 1L) return(as.numeric(x))
  text <- paste(as.character(x), collapse = ",")
  text <- trimws(text)
  if (!nzchar(text)) stop(sprintf("%s is empty.", label), call. = FALSE)

  repeat_match <- regexec(
    "^\\s*\\[?\\s*([-+0-9.eE]+)\\s*\\]?\\s*(?:x|X|\\*)\\s*([0-9]+)\\s*$",
    text,
    perl = TRUE
  )
  repeat_parts <- regmatches(text, repeat_match)[[1L]]
  if (length(repeat_parts) == 3L) {
    value <- suppressWarnings(as.numeric(repeat_parts[[2L]]))
    count <- suppressWarnings(as.integer(repeat_parts[[3L]]))
    if (is.finite(value) && is.finite(count) && count > 0L) {
      return(rep(value, count))
    }
  }

  cleaned <- gsub("\\[|\\]|\\(|\\)", "", text)
  cleaned <- gsub("[;,]", " ", cleaned)
  values <- suppressWarnings(as.numeric(strsplit(cleaned, "[[:space:]]+")[[1L]]))
  values <- values[is.finite(values)]
  if (!length(values)) {
    stop(sprintf("%s could not be parsed as a numeric vector: %s", label, text), call. = FALSE)
  }
  values
}

app_glofas_part4_parse_int_vector <- function(x, label) {
  values <- app_glofas_part4_parse_numeric_vector(x, label)
  ints <- as.integer(round(values))
  if (any(!is.finite(values)) || any(abs(values - ints) > 1.0e-8) || any(ints < 1L)) {
    stop(sprintf("%s must contain positive integer values.", label), call. = FALSE)
  }
  ints
}

app_glofas_part4_match_length <- function(values, target_len, label) {
  if (length(values) == target_len) return(values)
  if (length(values) == 1L) return(rep(values, target_len))
  stop(sprintf(
    "%s must have length 1 or %d; observed length %d.",
    label,
    target_len,
    length(values)
  ), call. = FALSE)
}

app_glofas_part4_identity_n_tilde <- function(n) {
  n <- as.integer(n)
  if (length(n) <= 1L) return(integer(0))
  head(n, -1L)
}

app_glofas_part4_row_value <- function(row, name, default = NULL) {
  if (!is.data.frame(row) || !nrow(row) || !name %in% names(row)) return(default)
  value <- row[[name]][[1L]]
  if (is.na(value) || !nzchar(trimws(as.character(value)))) return(default)
  value
}

app_glofas_part4_anchor_row <- function(anchor_manifest, role) {
  idx <- which(tolower(trimws(anchor_manifest$role)) == role)
  if (length(idx) != 1L) {
    stop(sprintf("Expected exactly one Part 4 anchor row for role '%s'.", role), call. = FALSE)
  }
  anchor_manifest[idx, , drop = FALSE]
}

app_glofas_part4_optional_anchor_row <- function(anchor_manifest, role) {
  idx <- which(tolower(trimws(anchor_manifest$role)) == role)
  if (length(idx) > 1L) {
    stop(sprintf("Expected at most one Part 4 anchor row for role '%s'.", role), call. = FALSE)
  }
  if (!length(idx)) return(anchor_manifest[0L, , drop = FALSE])
  anchor_manifest[idx, , drop = FALSE]
}

app_glofas_part4_validate_anchor_manifest <- function(anchor_manifest, require_frozen = TRUE) {
  if (!is.data.frame(anchor_manifest) || !nrow(anchor_manifest)) {
    stop("Part 4 selected-anchor manifest is empty.", call. = FALSE)
  }
  app_check_required_columns(
    anchor_manifest,
    app_glofas_part4_required_anchor_columns(),
    "Part 4 selected-anchor manifest"
  )
  anchor_manifest$role <- tolower(trimws(as.character(anchor_manifest$role)))
  missing_roles <- setdiff(app_glofas_part4_expected_anchor_roles(), anchor_manifest$role)
  if (length(missing_roles)) {
    stop(sprintf(
      "Part 4 selected-anchor manifest is missing roles: %s",
      paste(missing_roles, collapse = ", ")
    ), call. = FALSE)
  }
  unknown_roles <- setdiff(unique(anchor_manifest$role), app_glofas_part4_allowed_anchor_roles())
  if (length(unknown_roles)) {
    stop(sprintf(
      "Part 4 selected-anchor manifest has unsupported roles: %s",
      paste(unknown_roles, collapse = ", ")
    ), call. = FALSE)
  }
  duplicate_roles <- unique(anchor_manifest$role[duplicated(anchor_manifest$role)])
  if (length(duplicate_roles)) {
    stop(sprintf(
      "Part 4 selected-anchor manifest has duplicate roles: %s",
      paste(duplicate_roles, collapse = ", ")
    ), call. = FALSE)
  }
  if (isTRUE(require_frozen)) {
    frozen <- vapply(anchor_manifest$frozen, app_glofas_part4_truthy, logical(1L))
    if (!all(frozen)) {
      stop("Part 4 selected-anchor manifest contains unfrozen rows.", call. = FALSE)
    }
  }
  status <- tolower(trimws(as.character(anchor_manifest$status)))
  allowed_status <- c("completed", "frozen", "promoted", "authoritative")
  bad_status <- unique(status[!status %in% allowed_status])
  if (length(bad_status)) {
    stop(sprintf(
      "Part 4 selected-anchor manifest has non-terminal statuses: %s",
      paste(bad_status, collapse = ", ")
    ), call. = FALSE)
  }
  for (role in anchor_manifest$role) {
    row <- app_glofas_part4_anchor_row(anchor_manifest, role)
    for (name in c("m", "output_lag_max", "covariate_lag_max", "washout")) {
      app_glofas_part4_numeric_scalar(row[[name]], sprintf("%s.%s", role, name), nonnegative = TRUE)
    }
    app_glofas_part4_parse_int_vector(row$n_vector, sprintf("%s.n_vector", role))
    app_glofas_part4_numeric_scalar(row$alpha, sprintf("%s.alpha", role), positive = TRUE)
    app_glofas_part4_numeric_scalar(row$rho, sprintf("%s.rho", role), nonnegative = TRUE)
    app_glofas_part4_numeric_scalar(row$seed, sprintf("%s.seed", role), nonnegative = TRUE)
    app_glofas_part4_numeric_scalar(row$rhs_tau0, sprintf("%s.rhs_tau0", role), positive = TRUE)
  }
  for (role in anchor_manifest$role) {
    row <- app_glofas_part4_anchor_row(anchor_manifest, role)
    fit_path <- as.character(app_glofas_part4_row_value(row, "fit_object_path", ""))
    fit_sha <- tolower(as.character(app_glofas_part4_row_value(row, "fit_object_sha256", "")))
    if (xor(nzchar(fit_path), nzchar(fit_sha))) {
      stop(sprintf(
        "%s fit_object_path and fit_object_sha256 must be supplied together.", role
      ), call. = FALSE)
    }
    if (nzchar(fit_path)) {
      if (!grepl("^[0-9a-f]{64}$", fit_sha)) {
        stop(sprintf("%s fit_object_sha256 is malformed.", role), call. = FALSE)
      }
      resolved_fit <- app_resolve_path(fit_path, must_work = TRUE)
      if (!identical(tolower(app_sha256_file(resolved_fit)), fit_sha)) {
        stop(sprintf("%s fit object does not match its declared SHA256.", role), call. = FALSE)
      }
    }
  }
  anchor_manifest
}

app_glofas_part4_list_scalar <- function(x, default = NULL) {
  value <- x %||% default
  if (is.null(value) || !length(value)) return(default)
  if (is.list(value)) value <- unlist(value, use.names = FALSE)
  value[[1L]]
}

app_glofas_part4_anchor_reservoir <- function(row, base_reservoir = list(), label = "anchor") {
  n <- app_glofas_part4_parse_int_vector(row$n_vector, sprintf("%s.n_vector", label))
  D <- length(n)
  n_tilde_raw <- app_glofas_part4_row_value(row, "n_tilde", default = "")
  n_tilde <- if (nzchar(as.character(n_tilde_raw))) {
    app_glofas_part4_parse_int_vector(n_tilde_raw, sprintf("%s.n_tilde", label))
  } else {
    app_glofas_part4_identity_n_tilde(n)
  }
  alpha <- app_glofas_part4_match_length(
    app_glofas_part4_parse_numeric_vector(row$alpha, sprintf("%s.alpha", label)),
    D,
    sprintf("%s.alpha", label)
  )
  rho <- app_glofas_part4_match_length(
    app_glofas_part4_parse_numeric_vector(row$rho, sprintf("%s.rho", label)),
    D,
    sprintf("%s.rho", label)
  )
  pi_w <- app_glofas_part4_match_length(
    app_glofas_part4_parse_numeric_vector(
      app_glofas_part4_row_value(row, "pi_w", app_glofas_part4_list_scalar(base_reservoir$pi_w, 0.03)),
      sprintf("%s.pi_w", label)
    ),
    D,
    sprintf("%s.pi_w", label)
  )
  pi_in <- app_glofas_part4_match_length(
    app_glofas_part4_parse_numeric_vector(
      app_glofas_part4_row_value(row, "pi_in", app_glofas_part4_list_scalar(base_reservoir$pi_in, 1.0)),
      sprintf("%s.pi_in", label)
    ),
    D,
    sprintf("%s.pi_in", label)
  )
  reservoir <- base_reservoir
  reservoir$D <- as.integer(D)
  reservoir$n <- as.integer(n)
  reservoir$n_tilde <- as.integer(n_tilde)
  reservoir$m <- as.integer(round(app_glofas_part4_numeric_scalar(row$m, sprintf("%s.m", label), positive = TRUE)))
  reservoir$washout <- as.integer(round(app_glofas_part4_numeric_scalar(row$washout, sprintf("%s.washout", label), nonnegative = TRUE)))
  reservoir$alpha <- as.numeric(alpha)
  reservoir$rho <- as.numeric(rho)
  reservoir$pi_w <- as.numeric(pi_w)
  reservoir$pi_in <- as.numeric(pi_in)
  reservoir$seed <- as.integer(round(app_glofas_part4_numeric_scalar(row$seed, sprintf("%s.seed", label), nonnegative = TRUE)))
  for (name in c("win_scale_global", "win_scale_bias", "activation", "reducer")) {
    value <- app_glofas_part4_row_value(row, name, default = NULL)
    if (!is.null(value)) reservoir[[name]] <- value
  }
  app_qdesn_validate_reservoir_spec(reservoir, label = sprintf("Part 4 %s reservoir", label))
  reservoir
}

app_glofas_part4_lag_contract <- function(row, label = "anchor") {
  output_lag_max <- as.integer(round(app_glofas_part4_numeric_scalar(
    row$output_lag_max,
    sprintf("%s.output_lag_max", label),
    nonnegative = TRUE
  )))
  covariate_lag_max <- as.integer(round(app_glofas_part4_numeric_scalar(
    row$covariate_lag_max,
    sprintf("%s.covariate_lag_max", label),
    nonnegative = TRUE
  )))
  list(
    output_lags = if (output_lag_max > 0L) list(range = c(1L, output_lag_max)) else integer(0),
    covariates = list(
      variables = c("ppt", "soil"),
      lags = list(range = c(0L, covariate_lag_max))
    ),
    standardize = TRUE
  )
}

app_glofas_part4_block_override <- function(row, base_reservoir, block = c("reference", "discrepancy")) {
  block <- match.arg(block)
  input_stream <- if (identical(block, "reference")) {
    "reference"
  } else {
    tolower(trimws(as.character(app_glofas_part4_row_value(row, "input_stream", "discrepancy"))))
  }
  if (!input_stream %in% c("reference", "discrepancy")) {
    stop(sprintf("Part 4 %s input_stream must be 'reference' or 'discrepancy'.", block), call. = FALSE)
  }
  list(
    input_stream = input_stream,
    reservoir = app_glofas_part4_anchor_reservoir(row, base_reservoir, label = block),
    reservoir_input = app_glofas_part4_lag_contract(row, label = block),
    readout = list(
      add_intercept = TRUE,
      include_reservoir_state = TRUE,
      include_input_block = FALSE
    )
  )
}

app_glofas_part4_joint_tau0 <- function(anchor_manifest, role, fallback) {
  joint <- app_glofas_part4_optional_anchor_row(anchor_manifest, "historical_joint_anchor")
  field <- if (identical(role, "reference")) "rhs_tau0_reference" else "rhs_tau0_discrepancy"
  value <- app_glofas_part4_row_value(joint, field, default = fallback)
  label <- if (nrow(joint)) sprintf("historical_joint_anchor.%s", field) else sprintf("%s_anchor.rhs_tau0", role)
  app_glofas_part4_numeric_scalar(value, label, positive = TRUE)
}

app_glofas_part4_config_from_anchors <- function(
    base_cfg,
    anchor_manifest,
    quantile = 0.50,
    part4_family = "independent_al_rhs_vb",
    run_label = "glofas_part4_ensemble_likelihood",
    require_frozen = TRUE) {
  anchors <- app_glofas_part4_validate_anchor_manifest(anchor_manifest, require_frozen = require_frozen)
  ref <- app_glofas_part4_anchor_row(anchors, "reference_anchor")
  disc <- app_glofas_part4_anchor_row(anchors, "discrepancy_anchor")
  ref_tau0 <- app_glofas_part4_joint_tau0(anchors, "reference", ref$rhs_tau0[[1L]])
  disc_tau0 <- app_glofas_part4_joint_tau0(anchors, "discrepancy", disc$rhs_tau0[[1L]])

  cfg <- base_cfg
  cfg$application_name <- run_label
  cfg$application_model <- cfg$application_model %||% list()
  cfg$application_model$contract <- "latent_path_ensemble_likelihood"
  cfg$prediction <- cfg$prediction %||% list()
  cfg$prediction$q_g_source <- "posterior_model_quantile"
  cfg$prediction$prediction_unit <- "posterior_draw"
  cfg$prediction$beyond_issued_horizon <- "disabled"
  cfg$prediction$part4_scope <- "fixed_issued_ensemble_latent_path"
  cfg$prediction$rolling_origin_enabled <- FALSE

  cfg$covariates <- cfg$covariates %||% list()
  cfg$covariates$enabled <- TRUE
  cfg$covariates$variables <- c("ppt", "soil")
  cfg$covariates$source_policy <- "realized_history_and_oracle_future"
  cfg$covariates$future_policy <- "oracle_realized"
  cfg$covariates$allow_realized_future <- TRUE
  cfg$covariates$allow_realized_future_blend <- FALSE
  cfg$covariates$forecast <- list(
    provider = "realized_future_oracle",
    horizon_days = 28L
  )
  for (variable in c("ppt", "soil")) {
    cfg$covariates[[variable]] <- cfg$covariates[[variable]] %||% list()
    cfg$covariates[[variable]]$forecast_noise <- list(enabled = FALSE)
    cfg$covariates[[variable]]$noisy_blend <- list(enabled = FALSE)
    cfg$covariates[[variable]]$realized_future_correction <- list(
      enabled = FALSE,
      observed_weight = 0
    )
    cfg$covariates[[variable]]$observed_blend <- list(
      enabled = FALSE,
      observed_weight = 0
    )
  }

  cfg$feature_contract <- cfg$feature_contract %||% cfg$features %||% list()
  cfg$feature_contract$version <- cfg$feature_contract$version %||% "0.3"
  cfg$feature_contract$two_block_design <- TRUE
  cfg$feature_contract$readout <- cfg$feature_contract$readout %||% list()
  cfg$feature_contract$readout$include_input_block <- FALSE
  cfg$feature_contract$readout$add_intercept <- TRUE
  cfg$feature_contract$readout$include_reservoir_state <- TRUE
  cfg$feature_contract$blocks <- cfg$feature_contract$blocks %||% list()
  cfg$feature_contract$blocks$reference <- app_glofas_part4_block_override(
    ref,
    cfg$reservoir %||% list(),
    block = "reference"
  )
  cfg$feature_contract$blocks$discrepancy <- app_glofas_part4_block_override(
    disc,
    cfg$reservoir %||% list(),
    block = "discrepancy"
  )
  cfg$reservoir <- cfg$feature_contract$blocks$reference$reservoir

  cfg$inference <- cfg$inference %||% list()
  cfg$inference$vb_ld <- cfg$inference$vb_ld %||% list()
  cfg$inference$vb_ld$rhs_tau0 <- ref_tau0
  cfg$inference$vb_ld$rhs_alpha_tau0 <- disc_tau0
  cfg$inference$vb_ld$part4_anchor_tau0_source <- list(
    reference = "historical_joint_anchor.rhs_tau0_reference_if_present_else_reference_anchor.rhs_tau0",
    discrepancy = "historical_joint_anchor.rhs_tau0_discrepancy_if_present_else_discrepancy_anchor.rhs_tau0"
  )
  cfg$quantile <- as.numeric(quantile)
  cfg$part4_anchor_manifest <- list(
    selected_reference_candidate_id = as.character(ref$candidate_id[[1L]]),
    selected_discrepancy_candidate_id = as.character(disc$candidate_id[[1L]]),
    selected_historical_joint_candidate_id = as.character(app_glofas_part4_row_value(
      app_glofas_part4_optional_anchor_row(anchors, "historical_joint_anchor"),
      "candidate_id",
      ""
    )),
    reference_design_hash = as.character(ref$design_hash[[1L]]),
    discrepancy_design_hash = as.character(disc$design_hash[[1L]]),
    part4_family = part4_family
  )
  app_validate_application_model_contract(cfg)
  app_qdesn_validate_block_configs(cfg)
  cfg
}

app_glofas_part4_make_quantile_grid <- function(quantile) {
  data.frame(
    quantile_id = app_glofas_part4_quantile_id(quantile),
    quantile_level = as.numeric(quantile),
    role = sprintf("q%03d", as.integer(round(as.numeric(quantile) * 100))),
    enabled = TRUE,
    stringsAsFactors = FALSE
  )
}

app_glofas_part4_make_model_grid <- function(
    run_label,
    quantile,
    part4_family = "independent_al_rhs_vb",
    reservoir_seed = NA_integer_) {
  quantile <- as.numeric(quantile)
  qid <- vapply(quantile, app_glofas_part4_quantile_id, character(1L))
  likelihood_family <- if (grepl("exal", part4_family, fixed = TRUE)) {
    "exal"
  } else if (grepl("normal", part4_family, fixed = TRUE)) {
    "normal"
  } else {
    "al"
  }
  prior <- if (identical(part4_family, "normal_ridge_diagnostic")) "ridge" else "rhs"
  data.frame(
    fit_id = c(
      sprintf("raw_glofas_part4_%s_%s", run_label, qid),
      sprintf("qdesn_part4_%s_%s", run_label, qid)
    ),
    model_id = c(
      rep(sprintf("raw_glofas_part4_%s", run_label), length(quantile)),
      rep(sprintf("qdesn_part4_%s", run_label), length(quantile))
    ),
    model_family = c(
      rep("raw_glofas", length(quantile)),
      rep("qdesn_glofas_discrepancy", length(quantile))
    ),
    quantile_level = rep(quantile, 2L),
    inference_method = c(rep("none", length(quantile)), rep("vb_ld", length(quantile))),
    coefficient_prior = c(rep("none", length(quantile)), rep(prior, length(quantile))),
    reservoir_seed = c(rep(NA_integer_, length(quantile)), rep(reservoir_seed, length(quantile))),
    likelihood_family = c(rep("none", length(quantile)), rep(likelihood_family, length(quantile))),
    required = TRUE,
    enabled = TRUE,
    config_hash = "TO_BE_COMPUTED",
    notes = c(
      rep("Raw issued GloFAS ensemble baseline for fixed Part 4 synthesis.", length(quantile)),
      rep(sprintf("Part 4 %s component; gated by selected Part 1/Part 2 geometry anchors.", part4_family), length(quantile))
    ),
    stringsAsFactors = FALSE
  )
}

app_glofas_part4_flatten <- function(x, prefix = "") {
  if (is.null(x)) return(character())
  if (!is.list(x)) {
    name <- if (nzchar(prefix)) prefix else "value"
    out <- as.character(x)
    names(out) <- rep(name, length(out))
    return(out)
  }
  pieces <- list()
  nms <- names(x)
  if (is.null(nms)) nms <- as.character(seq_along(x))
  for (i in seq_along(x)) {
    nm <- if (nzchar(nms[[i]])) nms[[i]] else as.character(i)
    child_prefix <- if (nzchar(prefix)) paste(prefix, nm, sep = ".") else nm
    pieces[[length(pieces) + 1L]] <- app_glofas_part4_flatten(x[[i]], child_prefix)
  }
  unlist(pieces, use.names = TRUE)
}

app_glofas_part4_source_audit <- function(cfg, allow_forbidden_sources = FALSE) {
  flat <- app_glofas_part4_flatten(cfg)
  text <- tolower(paste(names(flat), flat, collapse = "\n"))
  forbidden <- c("cefs", "gefs")
  hit <- forbidden[vapply(forbidden, function(token) grepl(token, text, fixed = TRUE), logical(1L))]
  data.frame(
    check = "no_forbidden_cefs_gefs_source_strings",
    status = if (length(hit) && !isTRUE(allow_forbidden_sources)) "fail" else "pass",
    detail = if (length(hit)) paste(hit, collapse = ",") else "none_detected",
    stringsAsFactors = FALSE
  )
}

app_glofas_part4_validate_no_forecast_contract <- function(
    cfg,
    allow_forbidden_sources = FALSE) {
  checks <- list()
  checks[[length(checks) + 1L]] <- data.frame(
    check = "application_model_contract",
    status = if (identical(app_application_model_contract(cfg), "latent_path_ensemble_likelihood")) "pass" else "fail",
    detail = app_application_model_contract(cfg),
    stringsAsFactors = FALSE
  )
  pred <- cfg$prediction %||% list()
  checks[[length(checks) + 1L]] <- data.frame(
    check = "prediction_q_g_source",
    status = if (identical(as.character(pred$q_g_source %||% "")[[1L]], "posterior_model_quantile")) "pass" else "fail",
    detail = as.character(pred$q_g_source %||% "")[[1L]],
    stringsAsFactors = FALSE
  )
  checks[[length(checks) + 1L]] <- data.frame(
    check = "prediction_unit",
    status = if (identical(as.character(pred$prediction_unit %||% "")[[1L]], "posterior_draw")) "pass" else "fail",
    detail = as.character(pred$prediction_unit %||% "")[[1L]],
    stringsAsFactors = FALSE
  )
  rolling_values <- c(
    pred$rolling_origin_enabled %||% FALSE,
    (cfg$forecast_protocol %||% list())$rolling_origin_enabled %||% FALSE,
    (cfg$forecast %||% list())$rolling_origin_enabled %||% FALSE
  )
  checks[[length(checks) + 1L]] <- data.frame(
    check = "no_rolling_origin_part4",
    status = if (any(vapply(rolling_values, app_as_bool, logical(1L)))) "fail" else "pass",
    detail = paste(as.character(rolling_values), collapse = ","),
    stringsAsFactors = FALSE
  )
  recursive_oracle <- c(
    pred$recursive_oracle_forecast %||% FALSE,
    (cfg$forecast_protocol %||% list())$recursive_oracle_forecast %||% FALSE
  )
  checks[[length(checks) + 1L]] <- data.frame(
    check = "no_recursive_oracle_forecast_part4",
    status = if (any(vapply(recursive_oracle, app_as_bool, logical(1L)))) "fail" else "pass",
    detail = paste(as.character(recursive_oracle), collapse = ","),
    stringsAsFactors = FALSE
  )
  checks[[length(checks) + 1L]] <- app_glofas_part4_source_audit(
    cfg,
    allow_forbidden_sources = allow_forbidden_sources
  )
  out <- app_bind_rows_fill(checks)
  if (any(out$status != "pass")) {
    stop(sprintf(
      "Part 4 no-forecast ensemble-likelihood contract failed: %s",
      paste(out$check[out$status != "pass"], collapse = ", ")
    ), call. = FALSE)
  }
  out
}

app_glofas_part4_manifest_status_from_gates <- function(
    anchors_ok,
    source_ok,
    part4_family,
    quantile) {
  if (!isTRUE(anchors_ok)) return("blocked_missing_frozen_g1_g2_g3_anchor_manifest")
  if (!isTRUE(source_ok)) return("blocked_part4_source_or_contract_audit_failed")
  if (identical(part4_family, "normal_ridge_diagnostic")) {
    return("ready_after_operator_launch_approval")
  }
  "blocked_until_dependencies_complete"
}

app_glofas_part4_job_id <- function(run_label, family, quantile = NA_real_) {
  qid <- if (is.finite(as.numeric(quantile))) {
    paste0("_", app_glofas_part4_quantile_id(quantile))
  } else {
    ""
  }
  sprintf("%s_%s%s", run_label, family, qid)
}

app_glofas_part4_job_dependencies <- function(run_label, family, quantile = NA_real_) {
  id <- function(f, q = NA_real_) app_glofas_part4_job_id(run_label, f, q)
  if (identical(family, "normal_ridge_diagnostic")) return(character())
  if (identical(family, "normal_rhs_vb_diagnostic")) return(id("normal_ridge_diagnostic"))
  if (identical(family, "independent_al_rhs_vb")) {
    q <- as.numeric(quantile)
    parent <- if (abs(q - 0.50) < 1.0e-12) {
      id("normal_rhs_vb_diagnostic")
    } else {
      parent_q <- c(`0.35` = 0.50, `0.20` = 0.35, `0.05` = 0.20,
                    `0.65` = 0.50, `0.80` = 0.65, `0.95` = 0.80)
      value <- parent_q[[sprintf("%.2f", q)]]
      if (is.null(value)) stop(sprintf("Unsupported Part 4 AL quantile %.4f.", q), call. = FALSE)
      id("independent_al_rhs_vb", value)
    }
    return(parent)
  }
  if (identical(family, "independent_exal_rhs_vb")) {
    return(id("independent_al_rhs_vb", as.numeric(quantile)))
  }
  if (identical(family, "joint_al_rhs_vb")) {
    return(vapply(app_glofas_part4_quantile_grid(), function(q) id("independent_al_rhs_vb", q), character(1L)))
  }
  if (identical(family, "joint_exal_rhs_vb")) {
    return(vapply(app_glofas_part4_quantile_grid(), function(q) id("independent_exal_rhs_vb", q), character(1L)))
  }
  stop(sprintf("Unknown Part 4 family '%s'.", family), call. = FALSE)
}

app_glofas_part4_launch_manifest <- function(
    run_label,
    selected_anchor_manifest = NULL,
    base_cfg = NULL,
    require_frozen = TRUE,
    allow_forbidden_sources = FALSE) {
  anchors_ok <- FALSE
  anchor_message <- "no selected-anchor manifest supplied"
  anchors <- data.frame()
  if (!is.null(selected_anchor_manifest)) {
    anchor_result <- tryCatch(
      {
        anchors <- app_glofas_part4_validate_anchor_manifest(
          selected_anchor_manifest,
          require_frozen = require_frozen
        )
        list(ok = TRUE, message = "selected-anchor manifest valid")
      },
      error = function(e) list(ok = FALSE, message = conditionMessage(e))
    )
    anchors_ok <- anchor_result$ok
    anchor_message <- anchor_result$message
  }
  source_ok <- is.null(base_cfg)
  source_message <- if (is.null(base_cfg)) "base config not supplied; source audit deferred" else "not_checked"
  if (!is.null(base_cfg) && isTRUE(anchors_ok)) {
    source_result <- tryCatch(
      {
        tmp_cfg <- app_glofas_part4_config_from_anchors(
          base_cfg,
          anchors,
          quantile = 0.50,
          run_label = run_label,
          require_frozen = require_frozen
        )
        app_glofas_part4_validate_no_forecast_contract(
          tmp_cfg,
          allow_forbidden_sources = allow_forbidden_sources
        )
        list(ok = TRUE, message = "Part 4 no-forecast source contract valid")
      },
      error = function(e) list(ok = FALSE, message = conditionMessage(e))
    )
    source_ok <- source_result$ok
    source_message <- source_result$message
  }
  ref <- if (nrow(anchors)) app_glofas_part4_anchor_row(anchors, "reference_anchor") else data.frame()
  disc <- if (nrow(anchors)) app_glofas_part4_anchor_row(anchors, "discrepancy_anchor") else data.frame()
  joint <- if (nrow(anchors)) {
    app_glofas_part4_optional_anchor_row(anchors, "historical_joint_anchor")
  } else {
    data.frame()
  }
  rows <- list()
  add_row <- function(part4_family, quantile = NA_real_) {
    status <- app_glofas_part4_manifest_status_from_gates(
      anchors_ok,
      source_ok,
      part4_family,
      quantile %||% 0.50
    )
    qid <- if (is.finite(as.numeric(quantile))) app_glofas_part4_quantile_id(quantile) else ""
    run_id <- app_glofas_part4_job_id(run_label, part4_family, quantile)
    dependencies <- app_glofas_part4_job_dependencies(run_label, part4_family, quantile)
    rows[[length(rows) + 1L]] <<- data.frame(
      run_label = run_label,
      part4_family = part4_family,
      quantile = if (is.finite(as.numeric(quantile))) sprintf("%.2f", as.numeric(quantile)) else "",
      quantile_id = qid,
      worker_slots = 1L,
      status = status,
      anchor_manifest_status = anchor_message,
      source_contract_status = source_message,
      selected_reference_candidate_id = app_glofas_part4_row_value(ref, "candidate_id", ""),
      selected_discrepancy_candidate_id = app_glofas_part4_row_value(disc, "candidate_id", ""),
      selected_historical_joint_candidate_id = app_glofas_part4_row_value(joint, "candidate_id", ""),
      config_path = "",
      model_grid_path = "",
      quantile_grid_path = "",
      run_id = run_id,
      dependencies = paste(dependencies, collapse = "|"),
      initializer_policy = if (!length(dependencies)) {
        "optional_exact_design_part3_initializer_else_cold_closed_form_ridge"
      } else {
        "exact_dependency_fit"
      },
      launch_command = "",
      stringsAsFactors = FALSE
    )
  }
  add_row("normal_ridge_diagnostic")
  add_row("normal_rhs_vb_diagnostic")
  for (q in c(0.50, 0.35, 0.65, 0.20, 0.80, 0.05, 0.95)) add_row("independent_al_rhs_vb", q)
  for (q in app_glofas_part4_quantile_grid()) add_row("independent_exal_rhs_vb", q)
  add_row("joint_al_rhs_vb")
  add_row("joint_exal_rhs_vb")
  app_bind_rows_fill(rows)
}

app_glofas_part4_prepare_bundle <- function(
    base_config_path,
    anchor_manifest_path = NULL,
    run_label = "glofas_part4_ensemble_likelihood_deferred_20260903",
    runtime_root = file.path("local_trackers", "runtime_configs", run_label),
    require_frozen = TRUE,
    allow_forbidden_sources = FALSE,
    dry_run = TRUE,
    write_candidate_configs = TRUE,
    max_iter = 100L,
    min_iter = 30L,
    tol = 0.01,
    freeze_beta_warmup_iters = 20L,
    min_beta_updates = 10L,
    n_draws = 500L) {
  base_cfg <- app_read_config(app_resolve_path(base_config_path, must_work = TRUE))
  anchors <- NULL
  if (!is.null(anchor_manifest_path) && nzchar(as.character(anchor_manifest_path))) {
    anchors <- app_read_csv(app_resolve_path(anchor_manifest_path, must_work = TRUE))
  }
  runtime_abs <- app_resolve_path(runtime_root, must_work = FALSE)
  configs_dir <- file.path(runtime_abs, "configs")
  scripts_dir <- file.path(runtime_abs, "scripts")
  logs_dir <- file.path(runtime_abs, "logs")
  app_ensure_dir(configs_dir)
  app_ensure_dir(scripts_dir)
  app_ensure_dir(logs_dir)

  manifest <- app_glofas_part4_launch_manifest(
    run_label = run_label,
    selected_anchor_manifest = anchors,
    base_cfg = base_cfg,
    require_frozen = require_frozen,
    allow_forbidden_sources = allow_forbidden_sources
  )

  can_materialize <- !is.null(anchors) &&
    any(!grepl("^blocked_missing|^blocked_part4", manifest$status)) &&
    isTRUE(write_candidate_configs)

  if (isTRUE(can_materialize)) {
    anchors_valid <- app_glofas_part4_validate_anchor_manifest(anchors, require_frozen = require_frozen)
    selected_anchor_path <- file.path(configs_dir, "selected_anchor_manifest.csv")
    app_write_csv(anchors_valid, selected_anchor_path)
    for (i in seq_len(nrow(manifest))) {
      row <- manifest[i, , drop = FALSE]
      family <- row$part4_family[[1L]]
      q <- if (nzchar(row$quantile[[1L]])) as.numeric(row$quantile[[1L]]) else app_glofas_part4_quantile_grid()
      qid <- if (nzchar(row$quantile_id[[1L]])) row$quantile_id[[1L]] else "all7"
      cand_dir <- file.path(configs_dir, row$run_id[[1L]])
      app_ensure_dir(cand_dir)
      qgrid_path <- file.path(cand_dir, sprintf("quantile_grid_%s.csv", qid))
      model_grid_path <- file.path(cand_dir, sprintf("model_grid_%s.csv", qid))
      config_path <- file.path(cand_dir, sprintf("config_%s.yaml", qid))
      run_id <- row$run_id[[1L]]
      qgrid <- app_glofas_part4_make_quantile_grid(q)
      cfg <- app_glofas_part4_config_from_anchors(
        base_cfg,
        anchors_valid,
        quantile = q,
        part4_family = family,
        run_label = run_id,
        require_frozen = require_frozen
      )
      cfg$paths$quantile_grid <- app_prefer_repo_relative_path(qgrid_path)
      cfg$paths$model_grid <- app_prefer_repo_relative_path(model_grid_path)
      cfg$execution <- cfg$execution %||% list()
      cfg$execution$final_launch <- cfg$execution$final_launch %||% list()
      cfg$execution$final_launch$enabled <- TRUE
      cfg$execution$final_launch$note <- "Part 4 fixed ensemble-likelihood candidate prepared from frozen Part 1/Part 2 geometry anchors; Part 3 initializer optional."
      cfg$post_analysis <- cfg$post_analysis %||% list()
      cfg$post_analysis$run_after_outputs <- TRUE
      cfg$inference$likelihood_family <- if (grepl("exal", family, fixed = TRUE)) {
        "exal"
      } else if (grepl("normal", family, fixed = TRUE)) {
        "normal"
      } else {
        "al"
      }
      cfg$inference$default_method <- "vb_ld"
      cfg$inference$vb_ld$max_iter <- as.integer(max_iter)
      cfg$inference$vb_ld$min_iter_elbo <- as.integer(min_iter)
      cfg$inference$vb_ld$tol <- as.numeric(tol)
      cfg$inference$vb_ld$tol_par <- as.numeric(tol)
      cfg$inference$vb_ld$freeze_beta_warmup_iters <- as.integer(freeze_beta_warmup_iters)
      cfg$inference$vb_ld$min_beta_updates <- as.integer(min_beta_updates)
      cfg$inference$vb_ld$progress_every <- 1L
      cfg$inference$vb_ld$n_draws <- as.integer(n_draws)
      cfg$part4_execution <- list(
        model_fit_only = TRUE,
        separate_forecast_stage = FALSE,
        future_usgs_role = "latent_during_fit_post_fit_scoring_only",
        ensemble_weight_contract = "one_over_members_within_horizon",
        common_ensemble_center_across_quantiles = TRUE,
        crossing_fix = FALSE
      )
      model_grid <- app_glofas_part4_make_model_grid(
        run_label = run_label,
        quantile = q,
        part4_family = family,
        reservoir_seed = as.integer(cfg$reservoir$seed %||% NA_integer_)
      )
      app_write_csv(qgrid, qgrid_path)
      app_write_csv(model_grid, model_grid_path)
      app_validate_model_grid(model_grid_path, app_config_path(cfg, "schema"))
      app_validate_qdesn_seed_contract(cfg, app_validate_model_grid(model_grid_path, app_config_path(cfg, "schema")))
      app_glofas_part4_validate_no_forecast_contract(
        cfg,
        allow_forbidden_sources = allow_forbidden_sources
      )
      app_write_yaml(cfg, config_path)
      manifest$config_path[[i]] <- app_prefer_repo_relative_path(config_path)
      manifest$model_grid_path[[i]] <- app_prefer_repo_relative_path(model_grid_path)
      manifest$quantile_grid_path[[i]] <- app_prefer_repo_relative_path(qgrid_path)
      manifest$launch_command[[i]] <- sprintf(
        "Rscript application/scripts/386_run_glofas_part4_latent_family_job.R --runtime_root %s --job_id %s",
        shQuote(app_prefer_repo_relative_path(runtime_abs)),
        shQuote(run_id)
      )
    }
  }

  manifest_path <- file.path(configs_dir, "part4_model_manifest.csv")
  app_write_csv(manifest, manifest_path)

  launch_path <- file.path(scripts_dir, "launch_part4_ensemble_likelihood.sh")
  launch_lines <- c(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    sprintf("echo %s", shQuote(sprintf("Prepared manifest: %s", manifest_path))),
    "echo 'No models are launched by default.'",
    "echo 'Use application/scripts/387_launch_glofas_part4_latent_family_dag.py only after explicit operator approval.'",
    ""
  )
  app_ensure_dir(dirname(launch_path))
  writeLines(launch_lines, launch_path, useBytes = TRUE)
  Sys.chmod(launch_path, mode = "0755")

  metadata <- list(
    run_label = run_label,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    repo_root = app_repo_root(),
    runtime_root = app_prefer_repo_relative_path(runtime_abs),
    base_config_path = app_prefer_repo_relative_path(app_resolve_path(base_config_path, must_work = TRUE)),
    anchor_manifest_path = if (!is.null(anchor_manifest_path) && nzchar(as.character(anchor_manifest_path))) {
      app_prefer_repo_relative_path(app_resolve_path(anchor_manifest_path, must_work = TRUE))
    } else {
      ""
    },
    selected_anchor_manifest_path = if (exists("selected_anchor_path", inherits = FALSE)) {
      app_prefer_repo_relative_path(selected_anchor_path)
    } else {
      ""
    },
    manifest_path = app_prefer_repo_relative_path(manifest_path),
    launch_path = app_prefer_repo_relative_path(launch_path),
    rows = nrow(manifest),
    ready_rows = sum(manifest$status == "ready_after_operator_launch_approval"),
    blocked_rows = sum(grepl("^blocked", manifest$status)),
    dry_run = app_as_bool(dry_run),
    max_iter = as.integer(max_iter),
    min_iter = as.integer(min_iter),
    tol = as.numeric(tol),
    freeze_beta_warmup_iters = as.integer(freeze_beta_warmup_iters),
    min_beta_updates = as.integer(min_beta_updates),
    n_draws = as.integer(n_draws),
    launched = FALSE
  )
  metadata_path <- file.path(configs_dir, "part4_launch_metadata.json")
  app_write_json(metadata, metadata_path)
  list(
    manifest = manifest,
    metadata = metadata,
    manifest_path = manifest_path,
    launch_path = launch_path,
    metadata_path = metadata_path
  )
}

app_glofas_part4_check_bundle <- function(runtime_root) {
  runtime_abs <- app_resolve_path(runtime_root, must_work = TRUE)
  manifest_path <- file.path(runtime_abs, "configs", "part4_model_manifest.csv")
  manifest <- app_read_csv(manifest_path)
  statuses <- table(manifest$status)
  configured <- !is.na(manifest$config_path) &
    nzchar(trimws(as.character(manifest$config_path)))
  summary <- data.frame(
    metric = c(
      "manifest_rows",
      "ready_after_operator_launch_approval",
      "blocked",
      "configured_model_rows",
      "completed_markers",
      "failed_markers"
    ),
    value = c(
      nrow(manifest),
      sum(manifest$status == "ready_after_operator_launch_approval"),
      sum(grepl("^blocked", manifest$status)),
      sum(configured),
      length(list.files(runtime_abs, pattern = "COMPLETED$", recursive = TRUE, full.names = TRUE)),
      length(list.files(runtime_abs, pattern = "FAILED$", recursive = TRUE, full.names = TRUE))
    ),
    stringsAsFactors = FALSE
  )
  list(
    summary = summary,
    status_counts = data.frame(status = names(statuses), count = as.integer(statuses), stringsAsFactors = FALSE),
    manifest = manifest,
    manifest_path = manifest_path
  )
}
