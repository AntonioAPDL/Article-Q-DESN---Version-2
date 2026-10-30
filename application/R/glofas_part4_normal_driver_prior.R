# Joint Gaussian future-USGS prior estimated from a truth-free Normal-RHS bank.

app_glofas_part4_stabilize_driver_covariance <- function(
  covariance,
  relative_floor = 1.0e-8,
  absolute_floor = 1.0e-10
) {
  covariance <- as.matrix(covariance)
  if (nrow(covariance) != ncol(covariance) || !nrow(covariance) || any(!is.finite(covariance))) {
    stop("Part 4 driver covariance must be a finite square matrix.", call. = FALSE)
  }
  symmetric <- (covariance + t(covariance)) / 2
  eig <- eigen(symmetric, symmetric = TRUE)
  floor_value <- max(as.numeric(absolute_floor), as.numeric(relative_floor) * max(eig$values, 1))
  values <- pmax(eig$values, floor_value)
  stabilized <- eig$vectors %*% (values * t(eig$vectors))
  precision <- eig$vectors %*% ((1 / values) * t(eig$vectors))
  list(
    covariance = (stabilized + t(stabilized)) / 2,
    precision = (precision + t(precision)) / 2,
    diagnostics = list(
      raw_min_eigenvalue = min(eig$values),
      stabilized_min_eigenvalue = min(values),
      stabilized_max_eigenvalue = max(values),
      eigenvalue_floor = floor_value,
      n_eigenvalues_floored = sum(eig$values < floor_value),
      condition_number = max(values) / min(values)
    )
  )
}

app_glofas_part4_normal_driver_prior <- function(
  driver_bank,
  component = "usgs",
  expected_paths = 500L,
  relative_floor = 1.0e-8,
  absolute_floor = 1.0e-10
) {
  app_validate_glofas_normal_driver_bank(
    driver_bank, component, expected_paths = expected_paths,
    expected_dates = as.Date(driver_bank$contract$future_dates)
  )
  paths <- as.matrix(driver_bank$components[[component]])
  mean <- rowMeans(paths)
  covariance <- stats::cov(t(paths))
  stabilized <- app_glofas_part4_stabilize_driver_covariance(
    covariance, relative_floor = relative_floor, absolute_floor = absolute_floor
  )
  contract <- list(
    schema_version = "glofas_part4_normal_driver_prior_v1",
    source = "part3_normal_rhs_recursive_driver_bank",
    driver_contract_hash = driver_bank$contract$contract_hash,
    source_fit_sha256 = driver_bank$contract$source_fit_sha256,
    cutoff_date = driver_bank$contract$cutoff_date,
    future_dates = driver_bank$contract$future_dates,
    response_scale = driver_bank$contract$response_scale,
    n_paths = ncol(paths),
    horizon = nrow(paths),
    component = component,
    replace_future_y_working_likelihood = TRUE,
    ensemble_used_to_build_prior = FALSE,
    future_truth_used_to_build_prior = FALSE,
    seed = driver_bank$contract$seed,
    covariance_regularization = stabilized$diagnostics
  )
  contract$contract_hash <- app_latent_path_contract_hash(contract, "glofas_part4_normal_driver_prior_")
  structure(
    list(
      mean = mean,
      covariance = stabilized$covariance,
      precision = stabilized$precision,
      replace_future_y_working_likelihood = TRUE,
      source = contract$source,
      contract_hash = contract$contract_hash,
      contract = contract
    ),
    class = c("glofas_part4_normal_driver_prior", "list")
  )
}

app_validate_glofas_part4_normal_driver_prior <- function(
  prior,
  expected_dates,
  expected_scale = "log1p",
  expected_paths = 500L
) {
  if (!inherits(prior, "glofas_part4_normal_driver_prior") ||
      !identical(prior$contract$schema_version, "glofas_part4_normal_driver_prior_v1")) {
    stop("Unsupported Part 4 Normal-driver prior schema.", call. = FALSE)
  }
  expected_dates <- as.Date(expected_dates)
  if (!identical(as.Date(prior$contract$future_dates), expected_dates)) {
    stop("Part 4 Normal-driver prior dates do not match the latent horizon.", call. = FALSE)
  }
  if (!identical(as.character(prior$contract$response_scale), as.character(expected_scale))) {
    stop("Part 4 Normal-driver prior response scale mismatch.", call. = FALSE)
  }
  if (as.integer(prior$contract$n_paths) != as.integer(expected_paths)) {
    stop("Part 4 Normal-driver prior path count mismatch.", call. = FALSE)
  }
  if (!isTRUE(prior$replace_future_y_working_likelihood) ||
      isTRUE(prior$contract$ensemble_used_to_build_prior) ||
      isTRUE(prior$contract$future_truth_used_to_build_prior)) {
    stop("Part 4 Normal-driver prior violates the replacement/leakage contract.", call. = FALSE)
  }
  source_sha <- as.character(prior$contract$source_fit_sha256 %||% NA_character_)[[1L]]
  if (is.na(source_sha) || !grepl("^[0-9a-f]{64}$", source_sha)) {
    stop("Part 4 Normal-driver prior must be bound to a source-fit SHA256.", call. = FALSE)
  }
  contract <- prior$contract
  observed_hash <- contract$contract_hash
  contract$contract_hash <- NULL
  if (!identical(observed_hash, app_latent_path_contract_hash(contract, "glofas_part4_normal_driver_prior_"))) {
    stop("Part 4 Normal-driver prior contract hash mismatch.", call. = FALSE)
  }
  normalized <- app_latent_normalize_future_gaussian_prior(prior, length(expected_dates))
  if (!identical(normalized$contract_hash, observed_hash)) {
    stop("Part 4 Normal-driver prior normalization lost its contract hash.", call. = FALSE)
  }
  invisible(TRUE)
}
