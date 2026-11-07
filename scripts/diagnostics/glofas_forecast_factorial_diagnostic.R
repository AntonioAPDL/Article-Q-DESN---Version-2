# Fixed-parameter decomposition of GloFAS future path law, member information,
# approximation and reporting. Fractional cells are diagnostic only and are
# not exact replays of the historical powered augmentation.

gffd_stop <- function(message) {
  stop(paste0("GloFAS forecast factorial diagnostic: ", message), call. = FALSE)
}

gffd_hash <- function(x) {
  if (!requireNamespace("digest", quietly = TRUE)) gffd_stop("digest is required")
  digest::digest(x, algo = "sha256", serialize = TRUE)
}

gffd_log_al <- function(response, location, probability, scale) {
  residual <- response - location
  log(probability) + log1p(-probability) - log(scale) -
    residual * (probability - (residual < 0)) / scale
}

gffd_log_mvn <- function(value, mean, covariance) {
  root <- tryCatch(chol(covariance), error = function(e) NULL)
  if (is.null(root)) gffd_stop("Gaussian path covariance is not positive definite")
  centered <- as.numeric(value) - as.numeric(mean)
  standardized <- backsolve(root, centered, transpose = TRUE)
  -.5 * (length(centered) * log(2 * pi) + 2 * sum(log(diag(root))) +
    sum(standardized^2))
}

gffd_contract <- function(mode = c("generated", "authentic"), probability,
    issued, sigma_y, sigma_g, path_law = c("same_family_al_transition",
      "gaussian_path_prior"), member_policy = c("unit_member_likelihood_v1",
      "fractional_marginal_information_diagnostic_v1"),
    gaussian_path_mean = NULL, gaussian_path_covariance = NULL,
    parameter_id, feature_id, truth_access = "forbidden") {
  mode <- match.arg(mode)
  path_law <- match.arg(path_law)
  member_policy <- match.arg(member_policy)
  issued <- as.matrix(issued)
  H <- nrow(issued)
  M <- ncol(issued)
  if (!H || H > 28L || M > 51L || any(!is.finite(issued)) ||
      length(probability) != 1L || !is.finite(probability) ||
      probability <= 0 || probability >= 1 ||
      any(!is.finite(c(sigma_y, sigma_g))) || sigma_y <= 0 || sigma_g <= 0 ||
      !identical(truth_access, "forbidden") ||
      !is.character(parameter_id) || length(parameter_id) != 1L || !nzchar(parameter_id) ||
      !is.character(feature_id) || length(feature_id) != 1L || !nzchar(feature_id)) {
    gffd_stop("invalid truth-free fixed-parameter contract")
  }
  if (mode == "authentic" && (H != 28L || M != 51L)) {
    gffd_stop("authentic-source contracts require H=28 and 51 issued members")
  }
  if (path_law == "gaussian_path_prior") {
    gaussian_path_mean <- as.numeric(gaussian_path_mean)
    gaussian_path_covariance <- as.matrix(gaussian_path_covariance)
    if (length(gaussian_path_mean) != H ||
        !identical(dim(gaussian_path_covariance), c(H, H)) ||
        any(!is.finite(c(gaussian_path_mean, gaussian_path_covariance))) ||
        is.null(tryCatch(chol(gaussian_path_covariance), error = function(e) NULL))) {
      gffd_stop("Gaussian path law requires an aligned positive-definite prior")
    }
  } else {
    gaussian_path_mean <- numeric()
    gaussian_path_covariance <- matrix(numeric(), 0L, 0L)
  }
  member_weight <- if (member_policy == "unit_member_likelihood_v1") 1 else
    if (M) 1 / M else 1
  contract <- list(schema_version = "glofas_forecast_factorial_contract_v1",
    mode = mode, probability = probability, issued = issued, horizon = H,
    members = M, sigma_y = sigma_y, sigma_g = sigma_g,
    path_law = path_law, member_policy = member_policy,
    member_weight = member_weight,
    gaussian_path_mean = gaussian_path_mean,
    gaussian_path_covariance = gaussian_path_covariance,
    parameter_id = parameter_id, feature_id = feature_id,
    truth_access = truth_access,
    promotion_eligible = path_law == "same_family_al_transition" &&
      member_policy == "unit_member_likelihood_v1",
    authentic_source_diagnostic_only = mode == "authentic" &&
      member_policy != "unit_member_likelihood_v1",
    exact_legacy_augmented_replay = FALSE,
    purpose = "fixed_parameter_root_cause_diagnostic_not_model_selection")
  contract$contract_sha256 <- gffd_hash(contract)
  contract
}

gffd_grid <- function(mode = "generated", probability, issued, sigma_y, sigma_g,
    gaussian_path_mean, gaussian_path_covariance, parameter_id, feature_id) {
  laws <- c("same_family_al_transition", "gaussian_path_prior")
  policies <- c("unit_member_likelihood_v1",
    "fractional_marginal_information_diagnostic_v1")
  out <- list()
  for (law in laws) for (policy in policies) {
    id <- paste(law, policy, sep = "__")
    out[[id]] <- gffd_contract(mode, probability, issued, sigma_y, sigma_g,
      law, policy, gaussian_path_mean, gaussian_path_covariance,
      parameter_id, feature_id)
  }
  out
}

gffd_locations <- function(path, location_callback, contract) {
  if (!is.function(location_callback) || length(path) != contract$horizon ||
      any(!is.finite(path))) gffd_stop("path and location callback are not aligned")
  locations <- location_callback(as.numeric(path))
  if (!is.list(locations) ||
      !all(c("reference_location", "ensemble_location") %in% names(locations)) ||
      length(locations$reference_location) != contract$horizon ||
      length(locations$ensemble_location) != contract$horizon ||
      any(!is.finite(c(locations$reference_location, locations$ensemble_location)))) {
    gffd_stop("location callback must return finite total locations")
  }
  list(reference_location = as.numeric(locations$reference_location),
    ensemble_location = as.numeric(locations$ensemble_location))
}

gffd_log_target <- function(path, location_callback, contract, components = FALSE) {
  if (!is.list(contract) ||
      !identical(contract$schema_version, "glofas_forecast_factorial_contract_v1") ||
      !identical(contract$contract_sha256,
        gffd_hash(contract[setdiff(names(contract), "contract_sha256")]))) {
    gffd_stop("unsealed factorial contract")
  }
  locations <- gffd_locations(path, location_callback, contract)
  path_term <- if (contract$path_law == "same_family_al_transition") {
    sum(gffd_log_al(path, locations$reference_location, contract$probability,
      contract$sigma_y))
  } else {
    gffd_log_mvn(path, contract$gaussian_path_mean,
      contract$gaussian_path_covariance)
  }
  member_term <- 0
  if (contract$members) {
    member_locations <- matrix(locations$ensemble_location, contract$horizon,
      contract$members)
    member_term <- contract$member_weight * sum(gffd_log_al(contract$issued,
      member_locations, contract$probability, contract$sigma_g))
  }
  total <- path_term + member_term
  if (!is.finite(total)) gffd_stop("nonfinite factorial target")
  if (isTRUE(components)) list(total = total, path = path_term,
    members = member_term, locations = locations) else total
}

gffd_reference <- function(contract, location_callback, proposal_mean,
    proposal_covariance, probabilities, importance_control,
    tempering_control = NULL) {
  if (!exists("ggpr_importance", mode = "function", inherits = TRUE)) {
    gffd_stop("load the global path reference module first")
  }
  target <- function(path) gffd_log_target(path, location_callback, contract)
  importance <- ggpr_importance(target, proposal_mean, proposal_covariance,
    probabilities, importance_control, retain_paths = TRUE)
  tempered <- NULL
  if (!is.null(tempering_control)) {
    tempered <- ggpr_tempered(target, proposal_mean, proposal_covariance,
      probabilities, tempering_control, retain_paths = TRUE)
  }
  list(schema_version = "glofas_forecast_factorial_reference_v1",
    contract = contract, importance = importance, tempered = tempered,
    future_truth_read = FALSE, full_parameter_refits = 0L,
    production_qualified = FALSE)
}

gffd_reporting <- function(reference, location_callback, local_gaussian = NULL) {
  draw <- if (!is.null(reference$tempered) && isTRUE(reference$tempered$complete))
    reference$tempered else reference$importance
  if (is.null(draw$paths) || is.null(draw$weights)) {
    gffd_stop("retained complete paths and weights are required")
  }
  contract <- reference$contract
  weights <- draw$weights / sum(draw$weights)
  locations <- lapply(seq_len(nrow(draw$paths)), function(i)
    gffd_locations(draw$paths[i, ], location_callback, contract)$reference_location)
  location_matrix <- do.call(rbind, locations)
  response <- data.frame(horizon = seq_len(contract$horizon),
    probability = contract$probability,
    estimate = vapply(seq_len(contract$horizon), function(h)
      ggpr_weighted_quantile(draw$paths[, h], weights, contract$probability), numeric(1L)),
    reporting_operator = "marginal_future_response_quantile")
  legacy <- data.frame(horizon = seq_len(contract$horizon),
    probability = contract$probability,
    estimate = colSums(location_matrix * weights),
    reporting_operator = "legacy_weighted_mean_readout_location")
  rows <- rbind(response, legacy)
  if (!is.null(local_gaussian)) {
    mean <- as.numeric(local_gaussian$mean)
    covariance <- as.matrix(local_gaussian$covariance)
    if (length(mean) != contract$horizon ||
        !identical(dim(covariance), c(contract$horizon, contract$horizon)) ||
        any(!is.finite(c(mean, covariance))) || any(diag(covariance) < 0)) {
      gffd_stop("invalid local Gaussian-Delta summary")
    }
    rows <- rbind(rows, data.frame(horizon = seq_len(contract$horizon),
      probability = contract$probability,
      estimate = mean + stats::qnorm(contract$probability) * sqrt(diag(covariance)),
      reporting_operator = "local_gaussian_delta_marginal_quantile"))
  }
  rows$path_law <- contract$path_law
  rows$member_policy <- contract$member_policy
  rows$contract_sha256 <- contract$contract_sha256
  rows
}

gffd_crossings <- function(rows, value = "estimate", tolerance = 1e-10) {
  needed <- c("horizon", "probability", value)
  if (!is.data.frame(rows) || !all(needed %in% names(rows))) {
    gffd_stop("crossing rows are incomplete")
  }
  groups <- intersect(c("reporting_operator", "path_law", "member_policy"), names(rows))
  key <- if (length(groups)) interaction(rows[groups], drop = TRUE, lex.order = TRUE) else
    factor(rep("all", nrow(rows)))
  output <- list()
  for (group in levels(key)) {
    block <- rows[key == group, , drop = FALSE]
    for (h in sort(unique(block$horizon))) {
      x <- block[block$horizon == h, , drop = FALSE]
      x <- x[order(x$probability), , drop = FALSE]
      delta <- diff(as.numeric(x[[value]]))
      output[[length(output) + 1L]] <- data.frame(
        group = group, horizon = h,
        adjacent_comparisons = length(delta),
        crossing_pairs = sum(delta < -tolerance),
        maximum_crossing = if (length(delta)) max(c(0, -delta)) else 0)
    }
  }
  do.call(rbind, output)
}

