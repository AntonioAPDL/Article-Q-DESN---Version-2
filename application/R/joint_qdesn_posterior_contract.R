# Posterior-target contracts for shared Q--DESN quantile comparisons.

app_joint_posterior_format_numeric <- function(x) {
  x <- as.numeric(x)
  vapply(x, function(value) {
    if (is.infinite(value)) {
      if (value > 0) "Inf" else "-Inf"
    } else {
      formatC(value, digits = 17L, format = "fg", flag = "#")
    }
  }, character(1L))
}

app_joint_posterior_contract <- function(
    likelihood_family,
    fit_structure,
    tau,
    design_fingerprint,
    tau0,
    zeta2,
    slab_fixed = FALSE,
    a_sigma,
    b_sigma,
    alpha_prior_mean,
    alpha_prior_sd,
    alpha_min_spacing,
    sigma_bounds = c(0, Inf),
    kappa = 1,
    coefficient_hierarchy = "first_quantile_anchor_adjacent_differences",
    ordered_intercepts = identical(fit_structure, "joint"),
    gamma_prior_type = "none",
    score_definition = "dgp_integrated_finite_grid_acrps",
    projection_rule = "weighted_isotonic_equal_weights",
    draw_coupling = "matched_draw_index_with_repeated_permutation_sensitivity",
    contract_version = "joint_qdesn_posterior_target_v1") {
  likelihood_family <- as.character(likelihood_family)[[1L]]
  fit_structure <- as.character(fit_structure)[[1L]]
  if (!likelihood_family %in% c("AL", "exAL")) {
    stop("likelihood_family must be AL or exAL.", call. = FALSE)
  }
  if (!fit_structure %in% c("independent", "joint")) {
    stop("fit_structure must be independent or joint.", call. = FALSE)
  }
  expected_hierarchy <- if (fit_structure == "joint") {
    "first_quantile_anchor_adjacent_differences"
  } else {
    "independent_quantile_specific_rhs"
  }
  if (!identical(as.character(coefficient_hierarchy)[[1L]],
      expected_hierarchy)) {
    stop(sprintf("coefficient_hierarchy must be '%s' for %s fits.",
      expected_hierarchy, fit_structure), call. = FALSE)
  }
  tau <- app_joint_qvp_validate_tau_grid(tau)
  K <- length(tau)
  scalar_positive <- function(x, label, allow_infinite = FALSE) {
    x <- as.numeric(x)[[1L]]
    valid <- length(x) == 1L && !is.na(x) && x > 0 &&
      (is.finite(x) || (allow_infinite && is.infinite(x)))
    if (!valid) stop(sprintf("%s must be positive%s.", label,
      if (allow_infinite) " finite or Inf" else " and finite"), call. = FALSE)
    x
  }
  tau0 <- scalar_positive(tau0, "tau0")
  zeta2 <- scalar_positive(zeta2, "zeta2", allow_infinite = TRUE)
  slab_fixed <- isTRUE(slab_fixed)
  if (slab_fixed && !is.finite(zeta2)) {
    stop("slab_fixed requires a positive finite zeta2.", call. = FALSE)
  }
  a_sigma <- scalar_positive(a_sigma, "a_sigma")
  b_sigma <- scalar_positive(b_sigma, "b_sigma")
  kappa <- scalar_positive(kappa, "kappa")
  alpha_prior_mean <- as.numeric(alpha_prior_mean)
  alpha_prior_sd <- as.numeric(alpha_prior_sd)
  if (length(alpha_prior_mean) == 1L) alpha_prior_mean <- rep(alpha_prior_mean, K)
  if (length(alpha_prior_sd) == 1L) alpha_prior_sd <- rep(alpha_prior_sd, K)
  if (length(alpha_prior_mean) != K || any(!is.finite(alpha_prior_mean)) ||
      is.unsorted(alpha_prior_mean, strictly = FALSE)) {
    stop("alpha_prior_mean must be a finite ordered vector on the quantile grid.",
      call. = FALSE)
  }
  if (length(alpha_prior_sd) != K || any(is.na(alpha_prior_sd)) ||
      any(alpha_prior_sd <= 0) ||
      any(!is.finite(alpha_prior_sd) & !is.infinite(alpha_prior_sd))) {
    stop("alpha_prior_sd must contain positive finite values or Inf.", call. = FALSE)
  }
  alpha_min_spacing <- as.numeric(alpha_min_spacing)[[1L]]
  if (!is.finite(alpha_min_spacing) || alpha_min_spacing < 0) {
    stop("alpha_min_spacing must be nonnegative and finite.", call. = FALSE)
  }
  sigma_bounds <- app_joint_qvp_validate_sigma_bounds(sigma_bounds)
  if (!identical(fit_structure, "joint") && isTRUE(ordered_intercepts)) {
    stop("Independent fits cannot impose a joint ordered-intercept constraint.",
      call. = FALSE)
  }
  fields <- data.frame(
    field = c(
      "contract_version", "likelihood_family", "fit_structure",
      "coefficient_hierarchy", "ordered_intercepts", "quantile_grid",
      "data_design_fingerprint", "kappa", "tau0", "zeta2", "slab_fixed",
      "a_sigma", "b_sigma",
      "alpha_prior_mean", "alpha_prior_sd", "alpha_min_spacing",
      "sigma_lower_bound", "sigma_upper_bound", "gamma_prior_type",
      "score_definition", "projection_rule", "draw_coupling"
    ),
    value = c(
      contract_version, likelihood_family, fit_structure,
      coefficient_hierarchy, tolower(as.character(isTRUE(ordered_intercepts))),
      paste(app_joint_posterior_format_numeric(tau), collapse = ";"),
      as.character(design_fingerprint)[[1L]],
      app_joint_posterior_format_numeric(kappa),
      app_joint_posterior_format_numeric(tau0),
      app_joint_posterior_format_numeric(zeta2),
      tolower(as.character(slab_fixed)),
      app_joint_posterior_format_numeric(a_sigma),
      app_joint_posterior_format_numeric(b_sigma),
      paste(app_joint_posterior_format_numeric(alpha_prior_mean), collapse = ";"),
      paste(app_joint_posterior_format_numeric(alpha_prior_sd), collapse = ";"),
      app_joint_posterior_format_numeric(alpha_min_spacing),
      app_joint_posterior_format_numeric(sigma_bounds[[1L]]),
      app_joint_posterior_format_numeric(sigma_bounds[[2L]]),
      as.character(gamma_prior_type)[[1L]],
      as.character(score_definition)[[1L]],
      as.character(projection_rule)[[1L]],
      as.character(draw_coupling)[[1L]]
    ),
    stringsAsFactors = FALSE
  )
  canonical <- paste(paste(fields$field, fields$value, sep = "="), collapse = "\n")
  list(
    fields = fields,
    hash = app_joint_qvp_sha256_text(canonical),
    likelihood_family = likelihood_family,
    fit_structure = fit_structure,
    tau = tau,
    design_fingerprint = as.character(design_fingerprint)[[1L]],
    kappa = kappa,
    tau0 = tau0,
    zeta2 = zeta2,
    slab_fixed = slab_fixed,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_mean = alpha_prior_mean,
    alpha_prior_sd = alpha_prior_sd,
    alpha_min_spacing = alpha_min_spacing,
    sigma_bounds = sigma_bounds,
    coefficient_hierarchy = coefficient_hierarchy,
    ordered_intercepts = isTRUE(ordered_intercepts),
    gamma_prior_type = as.character(gamma_prior_type)[[1L]]
  )
}

app_joint_posterior_assert_identical <- function(contracts) {
  if (!length(contracts)) stop("At least one posterior contract is required.", call. = FALSE)
  hashes <- vapply(contracts, function(x) as.character(x$hash)[[1L]], character(1L))
  if (any(!nzchar(hashes)) || length(unique(hashes)) != 1L) {
    stop("Posterior-target contracts differ across fits or chains.", call. = FALSE)
  }
  invisible(hashes[[1L]])
}

app_joint_posterior_assert_initialization_only <- function(init) {
  if (!is.list(init)) stop("Initialization must be a list.", call. = FALSE)
  forbidden <- intersect(names(init), c(
    "alpha_prior_mean", "alpha_prior_sd", "alpha_min_spacing", "tau0",
    "zeta2", "slab_fixed", "a_sigma", "b_sigma", "kappa",
    "sigma_bounds", "gamma_prior_type", "coefficient_hierarchy",
    "ordered_intercepts", "design_fingerprint",
    "posterior_data_design_fingerprint", "posterior_target_sha256"
  ))
  if (length(forbidden)) {
    stop(sprintf(
      "Initialization contains posterior-target fields: %s.",
      paste(forbidden, collapse = ", ")
    ), call. = FALSE)
  }
  invisible(TRUE)
}
