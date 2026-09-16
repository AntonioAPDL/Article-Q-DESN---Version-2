# Shared Normal-RHS recursive trajectory banks for GloFAS forecasts.

app_glofas_driver_matrix <- function(x, label, horizon = NULL, paths = NULL) {
  x <- as.matrix(x)
  storage.mode(x) <- "double"
  if (!nrow(x) || !ncol(x) || any(!is.finite(x))) {
    stop(sprintf("Normal driver component '%s' must be a finite non-empty matrix.", label), call. = FALSE)
  }
  if (!is.null(horizon) && nrow(x) != horizon) {
    stop(sprintf("Normal driver component '%s' has the wrong horizon.", label), call. = FALSE)
  }
  if (!is.null(paths) && ncol(x) != paths) {
    stop(sprintf("Normal driver component '%s' has the wrong path count.", label), call. = FALSE)
  }
  x
}

app_glofas_normal_driver_bank <- function(
  future_dates,
  components,
  cutoff_date,
  seed,
  source_fit_path = NA_character_,
  source_fit_sha256 = NA_character_,
  source_model_id = NA_character_,
  response_scale = "log1p",
  exogenous_policy = "oracle_prism_era5_no_future_usgs",
  observed_sources = character(),
  forbidden_sources = c("future_usgs_truth", "part4_glofas_ensemble")
) {
  future_dates <- as.Date(future_dates)
  if (!length(future_dates) || anyNA(future_dates) || any(diff(future_dates) != 1)) {
    stop("Normal driver dates must be a finite contiguous daily horizon.", call. = FALSE)
  }
  if (!is.list(components) || !length(components) || is.null(names(components)) || any(!nzchar(names(components)))) {
    stop("Normal driver components must be a named non-empty list.", call. = FALSE)
  }
  first <- app_glofas_driver_matrix(components[[1L]], names(components)[[1L]])
  H <- nrow(first)
  S <- ncol(first)
  if (H != length(future_dates)) stop("Normal driver dates and component horizon differ.", call. = FALSE)
  components[[1L]] <- first
  if (length(components) > 1L) {
    for (i in 2:length(components)) {
      components[[i]] <- app_glofas_driver_matrix(components[[i]], names(components)[[i]], H, S)
    }
  }
  cutoff_date <- as.Date(cutoff_date)
  if (length(cutoff_date) != 1L || is.na(cutoff_date) || future_dates[[1L]] != cutoff_date + 1L) {
    stop("Normal driver horizon must begin one day after the cutoff.", call. = FALSE)
  }
  source_fit_path <- as.character(source_fit_path %||% NA_character_)[[1L]]
  observed_sha <- if (!is.na(source_fit_path) && nzchar(source_fit_path) && file.exists(source_fit_path)) {
    app_sha256_file(source_fit_path)
  } else {
    NA_character_
  }
  supplied_sha <- tolower(as.character(source_fit_sha256 %||% NA_character_)[[1L]])
  if (!is.na(observed_sha) && !is.na(supplied_sha) && nzchar(supplied_sha) && !identical(observed_sha, supplied_sha)) {
    stop("Normal driver source-fit SHA256 mismatch.", call. = FALSE)
  }
  path_id <- sprintf("path_%05d", seq_len(S))
  dimnames(components[[1L]]) <- list(as.character(future_dates), path_id)
  if (length(components) > 1L) {
    for (i in 2:length(components)) dimnames(components[[i]]) <- list(as.character(future_dates), path_id)
  }
  effective_sha <- if (!is.na(observed_sha) && nzchar(observed_sha)) {
    observed_sha
  } else if (!is.na(supplied_sha) && nzchar(supplied_sha)) {
    supplied_sha
  } else {
    NA_character_
  }
  contract <- list(
    schema_version = "glofas_normal_driver_bank_v1",
    cutoff_date = as.character(cutoff_date),
    future_dates = as.character(future_dates),
    horizon = H,
    n_paths = S,
    path_id = path_id,
    component_names = names(components),
    seed = as.integer(seed),
    response_scale = as.character(response_scale),
    exogenous_policy = as.character(exogenous_policy),
    observed_sources = sort(unique(as.character(observed_sources))),
    forbidden_sources = as.character(forbidden_sources),
    source_model_id = as.character(source_model_id %||% NA_character_),
    source_fit_path = source_fit_path,
    source_fit_sha256 = effective_sha
  )
  contract$contract_hash <- app_latent_path_contract_hash(contract, "glofas_normal_driver_bank_")
  structure(list(contract = contract, components = components), class = c("glofas_normal_driver_bank", "list"))
}

app_validate_glofas_normal_driver_bank <- function(
  bank,
  required_components,
  expected_paths = 500L,
  expected_dates = NULL,
  verify_source_hash = TRUE
) {
  if (!inherits(bank, "glofas_normal_driver_bank") ||
      !identical(bank$contract$schema_version, "glofas_normal_driver_bank_v1")) {
    stop("Unsupported GloFAS Normal driver bank schema.", call. = FALSE)
  }
  required_components <- as.character(required_components)
  missing <- setdiff(required_components, names(bank$components))
  if (length(missing)) stop(sprintf("Normal driver bank is missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  H <- as.integer(bank$contract$horizon)
  S <- as.integer(bank$contract$n_paths)
  if (!is.null(expected_paths) && S != as.integer(expected_paths)) {
    stop(sprintf("Normal driver bank must contain exactly %d paths.", as.integer(expected_paths)), call. = FALSE)
  }
  invisible(lapply(required_components, function(name) {
    app_glofas_driver_matrix(bank$components[[name]], name, H, S)
  }))
  dates <- as.Date(bank$contract$future_dates)
  if (!is.null(expected_dates) && !identical(dates, as.Date(expected_dates))) {
    stop("Normal driver bank dates do not match the requested horizon.", call. = FALSE)
  }
  observed_sources <- as.character(bank$contract$observed_sources %||% character())
  forbidden_sources <- as.character(bank$contract$forbidden_sources %||% character())
  if (length(intersect(observed_sources, forbidden_sources))) {
    stop("Normal driver bank contains a forbidden future source.", call. = FALSE)
  }
  expected_hash <- bank$contract$contract_hash
  contract <- bank$contract
  contract$contract_hash <- NULL
  if (!identical(expected_hash, app_latent_path_contract_hash(contract, "glofas_normal_driver_bank_"))) {
    stop("Normal driver contract hash mismatch.", call. = FALSE)
  }
  source_path <- as.character(bank$contract$source_fit_path %||% NA_character_)[[1L]]
  source_sha <- as.character(bank$contract$source_fit_sha256 %||% NA_character_)[[1L]]
  if (isTRUE(verify_source_hash) && !is.na(source_path) && nzchar(source_path) && file.exists(source_path) &&
      !identical(app_sha256_file(source_path), source_sha)) {
    stop("Normal driver source fit changed after the bank was created.", call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_normal_driver_bank_from_part1 <- function(forecast, cutoff_date, seed, source_fit_path = NA_character_) {
  app_glofas_normal_driver_bank(
    future_dates = forecast$future_dates,
    components = list(usgs = forecast$forecast_draws),
    cutoff_date = cutoff_date,
    seed = seed,
    source_fit_path = source_fit_path,
    source_model_id = "part1_normal_rhs"
  )
}

app_glofas_normal_driver_bank_from_part2 <- function(forecast, cutoff_date, seed, source_fit_path = NA_character_) {
  draws <- forecast$forecast_draws %||% forecast$discrepancy_draws
  app_glofas_normal_driver_bank(
    future_dates = forecast$future_dates,
    components = list(discrepancy = draws),
    cutoff_date = cutoff_date,
    seed = seed,
    source_fit_path = source_fit_path,
    source_model_id = "part2_normal_rhs"
  )
}

app_glofas_normal_driver_bank_from_part3 <- function(forecast, cutoff_date, seed, source_fit_path = NA_character_) {
  app_glofas_normal_driver_bank(
    future_dates = forecast$origin$future_dates,
    components = list(
      usgs = forecast$reference_draws,
      discrepancy = forecast$discrepancy_draws,
      glofas = forecast$glofas_draws
    ),
    cutoff_date = cutoff_date,
    seed = seed,
    source_fit_path = source_fit_path,
    source_model_id = "part3_normal_rhs"
  )
}
