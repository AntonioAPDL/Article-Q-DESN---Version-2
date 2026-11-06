# Native-facing contract for the existing all-coordinate score optimizer.
# This module admits generated interface fixtures and can construct the exact
# 7,510-dimensional application contract, but never authorizes a native fit.

gnpo_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS native parameter optimizer: ", why), call. = FALSE)
  invisible(TRUE)
}
gnpo_hash <- function(x) {
  gnpo_require(requireNamespace("digest", quietly = TRUE), "digest is required")
  digest::digest(x, algo = "sha256", serialize = TRUE)
}

gnpo_prior_identity <- function(spec) list(
  probability = spec$probability,
  prior = spec$prior,
  coordinate_measure = spec$coordinate_measure,
  jacobian_count = 1L,
  blocks = lapply(spec$blocks[c("beta", "alpha")], function(x) list(
    index = x$index, intercept_index = x$intercept_index,
    penalized = x$penalized, tau0 = x$tau0,
    intercept_prec = x$intercept_prec, slab_shape = x$slab_shape,
    slab_rate = x$slab_rate, zeta2_fixed = x$zeta2_fixed)),
  source_scale = spec$scale_prior[c("Y", "G")]
)

gnpo_assert_prior_compatible <- function(spec, prior_export) {
  q <- gnpo_require
  effective <- prior_export$effective_prior
  q(is.list(effective) && all(c("beta", "alpha", "source_scale") %in%
    names(effective)) && identical(effective$coordinate_measure,
      spec$coordinate_measure) && identical(as.integer(effective$jacobian_count), 1L) &&
    identical(effective$prior_addition_allowed, FALSE),
    "complete effective prior with one Jacobian and no prior addition required")
  for (name in c("beta", "alpha")) {
    from_spec <- spec$blocks[[name]]
    from_export <- effective[[name]]
    q(is.list(from_export) && is.list(from_export$slab) &&
      isTRUE(from_export$slab$learned) && is.null(from_export$slab$zeta2_fixed) &&
      is.null(from_spec$zeta2_fixed) &&
      isTRUE(all.equal(as.numeric(from_export$tau0), from_spec$tau0,
        tolerance = 0)) &&
      isTRUE(all.equal(as.numeric(from_export$intercept_prec),
        from_spec$intercept_prec, tolerance = 0)) &&
      isTRUE(all.equal(as.numeric(from_export$slab$a_zeta),
        from_spec$slab_shape, tolerance = 0)) &&
      isTRUE(all.equal(as.numeric(from_export$slab$b_zeta),
        from_spec$slab_rate, tolerance = 0)) &&
      identical(from_export$rhs_hierarchy$coefficient_product,
        "N(b;0,tau2*lambda2) times N(b;0,zeta2)") &&
      identical(from_export$rhs_hierarchy$global_conditional_shape,
        "(r+1)/2 with intercept excluded") &&
      isTRUE(all.equal(as.numeric(from_export$rhs_hierarchy$local_conditional_shape),
        1, tolerance = 0)), paste0("effective ", name,
          " prior differs from the collapsed target specification"))
  }
  for (name in c("Y", "G")) {
    exported <- as.numeric(effective$source_scale[[name]])
    q(length(exported) == 2L && isTRUE(all.equal(exported,
      unname(as.numeric(spec$scale_prior[[name]][c("shape", "rate")])),
      tolerance = 0)), paste0("effective ", name,
        " source-scale prior differs from the collapsed target"))
  }
  invisible(TRUE)
}

gnpo_contract <- function(spec, binding, prior_export, source_sha256,
    fixture_only = FALSE) {
  q <- gnpo_require
  q(is.list(spec) && identical(spec$schema_version,
    "glofas_generated_collapsed_AL_target_v1") &&
    is.list(binding) && identical(binding$schema_version,
      "glofas_two_desn_particle_binding_v1") &&
    is.list(prior_export) && identical(prior_export$schema_version,
      "glofas_native_prior_export_v1") &&
    is.character(source_sha256) && length(source_sha256) > 0L &&
    all(grepl("^[a-f0-9]{64}$", source_sha256)),
    "exact target, two-DESN, prior, and source identities required")
  q(identical(binding$member_policy, "unit_member_likelihood_v1") &&
    identical(binding$target_identity$posterior_target_sha256,
      prior_export$posterior_target_sha256) &&
    identical(binding$target_identity$prior_sha256,
      prior_export$declared_prior_sha256) &&
    identical(binding$target_identity$task_id, prior_export$task_id),
    "binding and prior export identify different targets")
  q(identical(spec$coordinate_names, as.character(spec$coordinate_names)) &&
    length(spec$coordinate_names) == spec$dimension &&
    !anyDuplicated(spec$coordinate_names), "complete unique coordinate map required")
  gnpo_assert_prior_compatible(spec, prior_export)
  if (!isTRUE(fixture_only)) {
    q(spec$dimension == 7510L && spec$p == 2502L && binding$horizon == 28L &&
      binding$member_factors_per_path == 1428L &&
      max(abs(binding$gains[c("beta", "alpha")] - c(beta = .5, alpha = .35))) < 1e-14,
      "application contract requires 7,510 physical coordinates, H28, all 1,428 factors, and retained gains")
  }
  target_inputs <- list(
    task_id = prior_export$task_id,
    posterior_target_sha256 = prior_export$posterior_target_sha256,
    declared_prior_sha256 = prior_export$declared_prior_sha256,
    effective_prior_sha256 = prior_export$effective_prior_sha256,
    two_desn_static_sha256 = binding$static_sha256,
    member_policy = binding$member_policy,
    member_count = 51L,
    horizon = binding$horizon,
    member_factors_per_path = binding$member_factors_per_path,
    prior = "N_product_NS_with_all_normalizers",
    coordinate_jacobian_count = 1L,
    historical_target = "marginal_AL_full_NS_product",
    future_target = "normalized_AL_transitions_times_unit_member_likelihood",
    model_prior_contract_sha256 = gnpo_hash(gnpo_prior_identity(spec)),
    fixture_only = isTRUE(fixture_only)
  )
  list(schema_version = "glofas_native_outer_score_input_v1",
    scope = if (isTRUE(fixture_only)) "generated_native_interface_fixture" else
      "native_application_source_frozen_not_launch_admitted",
    parameter_names = spec$coordinate_names,
    coordinate_map_sha256 = gnpo_hash(list(names = spec$coordinate_names,
      measure = spec$coordinate_measure)),
    coordinate_measure = spec$coordinate_measure,
    all_coordinate_count = spec$dimension,
    all_coordinates_mapped = TRUE,
    jacobian_policy = "exactly_once_in_historical_target_same_measure_log_q",
    inner_kernel_phi_independent = TRUE,
    target_inputs = target_inputs,
    target_inputs_sha256 = gnpo_hash(target_inputs),
    source_sha256 = source_sha256,
    native_payload_reads_authorized = FALSE,
    native_fit_authorized = FALSE,
    production_authorized = FALSE,
    publication_authorized = FALSE)
}

gnpo_validate_contract <- function(contract, p) {
  q <- gnpo_require
  q(is.list(contract) && identical(contract$schema_version,
    "glofas_native_outer_score_input_v1") &&
    contract$scope %in% c("generated_native_interface_fixture",
      "native_application_source_frozen_not_launch_admitted") &&
    length(contract$parameter_names) == p && contract$all_coordinate_count == p &&
    identical(contract$all_coordinates_mapped, TRUE) &&
    identical(contract$inner_kernel_phi_independent, TRUE) &&
    identical(contract$jacobian_policy,
      "exactly_once_in_historical_target_same_measure_log_q") &&
    identical(contract$coordinate_map_sha256,
      gnpo_hash(list(names = contract$parameter_names,
        measure = contract$coordinate_measure))) &&
    identical(contract$target_inputs_sha256, gnpo_hash(contract$target_inputs)) &&
    identical(contract$target_inputs$member_policy, "unit_member_likelihood_v1") &&
    identical(contract$target_inputs$prior,
      "N_product_NS_with_all_normalizers") &&
    is.character(contract$target_inputs$model_prior_contract_sha256) &&
    length(contract$target_inputs$model_prior_contract_sha256) == 1L &&
    grepl("^[a-f0-9]{64}$", contract$target_inputs$model_prior_contract_sha256) &&
    identical(contract$native_payload_reads_authorized, FALSE) &&
    identical(contract$native_fit_authorized, FALSE) &&
    identical(contract$production_authorized, FALSE) &&
    identical(contract$publication_authorized, FALSE),
    "sealed non-launch native target and coordinate contract required")
  if (identical(contract$scope, "native_application_source_frozen_not_launch_admitted")) {
    q(p == 7510L && contract$target_inputs$horizon == 28L &&
      contract$target_inputs$member_count == 51L &&
      contract$target_inputs$member_factors_per_path == 1428L,
      "application dimensions and unit-member inventory changed")
  } else {
    q(isTRUE(contract$target_inputs$fixture_only),
      "generated interface scope must remain explicit")
  }
  invisible(TRUE)
}

gnpo_optimize <- function(analytic_historical, log_evidence_estimate,
    initial_mean, initial_log_sd, input_contract, control = gcpopt_control(),
    control_variate = NULL, step_strategy = "legacy_adam_0999") {
  gnpo_require(exists(".gcpopt_optimize_core", mode = "function", inherits = TRUE),
    "load the collapsed parameter optimizer core first")
  out <- .gcpopt_optimize_core(log_evidence_estimate = log_evidence_estimate,
    initial_mean = initial_mean, initial_log_sd = initial_log_sd,
    factor = NULL, control = control, input_contract = input_contract,
    analytic_historical = analytic_historical, control_variate = control_variate,
    future_projection = NULL, step_strategy = step_strategy,
    contract_validator = gnpo_validate_contract,
    output_schema = "glofas_native_collapsed_parameter_optimizer_experimental_v1")
  out$native_application_qualified <- FALSE
  out$native_fit_authorized <- FALSE
  out$production_launch_authorized <- FALSE
  out$publication_authorized <- FALSE
  out$native_contract_validator_sha256 <- gnpo_hash(list(
    formals = deparse(formals(gnpo_validate_contract)),
    body = deparse(body(gnpo_validate_contract))))
  out$seal_scope <- paste(
    "Declared native target, coordinate and source value inputs plus callback bodies;",
    "opaque closure environments are not serialized or authenticated.")
  out
}
