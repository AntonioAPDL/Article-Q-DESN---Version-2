# Truth-free adapter from an authenticated retained two-DESN binding to the
# fixed-parameter factorial target. It performs no file reads or model fits.

gnfa_stop <- function(message) stop(paste0("GloFAS native factorial adapter: ",
  message), call. = FALSE)

gnfa_hash <- function(x) {
  if (!requireNamespace("digest", quietly = TRUE)) gnfa_stop("digest is required")
  digest::digest(x, algo = "sha256", serialize = TRUE)
}

gnfa_build <- function(binding, parameters, gaussian_path_mean,
    gaussian_path_covariance) {
  if (!exists("gtdpb_reference_locations", mode = "function", inherits = TRUE) ||
      !exists("gffd_grid", mode = "function", inherits = TRUE)) {
    gnfa_stop("load the two-DESN backend and factorial modules first")
  }
  if (!is.list(binding) ||
      !identical(binding$schema_version, "glofas_two_desn_particle_binding_v1") ||
      !identical(binding$horizon, 28L) || !identical(dim(binding$members), c(28L, 51L)) ||
      !identical(binding$member_policy, "unit_member_likelihood_v1") ||
      !identical(binding$member_factors_per_path, 28L * 51L) ||
      !identical(binding$future_truth_read, FALSE) ||
      !identical(binding$production_qualified, FALSE) ||
      any(binding$member_weights != 1)) {
    gnfa_stop("an H=28, M=51, unit-member, truth-free retained binding is required")
  }
  if (!is.list(parameters) || !is.numeric(parameters$coefficients) ||
      length(parameters$coefficients) != binding$spec$p ||
      any(!is.finite(parameters$coefficients)) || !is.numeric(parameters$sigma) ||
      !all(c("Y", "G") %in% names(parameters$sigma)) ||
      any(!is.finite(parameters$sigma[c("Y", "G")])) ||
      any(parameters$sigma[c("Y", "G")] <= 0)) {
    gnfa_stop("fixed finite coefficients and positive named Y/G scales are required")
  }
  probability <- as.numeric(binding$spec$probability)
  if (length(probability) != 1L || !is.finite(probability) || probability <= 0 ||
      probability >= 1) gnfa_stop("binding probability is invalid")
  parameter_id <- gnfa_hash(list(binding_static_sha256 = binding$static_sha256,
    coefficients = parameters$coefficients, sigma = parameters$sigma,
    target_identity = binding$target_identity))
  feature_id <- gnfa_hash(list(binding_static_sha256 = binding$static_sha256,
    dates = binding$dates, contracts = binding$contracts,
    initial_states = binding$initial_states, gains = binding$gains))
  callback <- function(path) {
    locations <- gtdpb_reference_locations(binding, path, parameters)
    list(reference_location = locations$reference,
      ensemble_location = locations$ensemble)
  }
  grid <- gffd_grid("authentic", probability, binding$members,
    unname(parameters$sigma[["Y"]]), unname(parameters$sigma[["G"]]),
    gaussian_path_mean, gaussian_path_covariance, parameter_id, feature_id)
  primary <- "same_family_al_transition__unit_member_likelihood_v1"
  if (!identical(names(grid), c(
      "same_family_al_transition__unit_member_likelihood_v1",
      "same_family_al_transition__fractional_marginal_information_diagnostic_v1",
      "gaussian_path_prior__unit_member_likelihood_v1",
      "gaussian_path_prior__fractional_marginal_information_diagnostic_v1")) ||
      !isTRUE(grid[[primary]]$promotion_eligible) ||
      sum(vapply(grid, function(x) x$promotion_eligible, logical(1L))) != 1L) {
    gnfa_stop("factorial grid identity or promotion boundary is invalid")
  }
  out <- list(schema_version = "glofas_native_factorial_adapter_v1",
    binding_static_sha256 = binding$static_sha256,
    target_identity = binding$target_identity, parameter_id = parameter_id,
    feature_id = feature_id, fixed_parameters = parameters,
    callback = callback, contracts = grid, primary_contract = primary,
    path_laws = unique(vapply(grid, `[[`, character(1L), "path_law")),
    member_policies = unique(vapply(grid, `[[`, character(1L), "member_policy")),
    future_truth_read = FALSE, original_file_reads = 0L,
    full_parameter_refits = 0L, production_qualified = FALSE,
    purpose = "fixed_parameter_truth_free_root_cause_diagnostic")
  out$adapter_sha256 <- gnfa_hash(out[setdiff(names(out), c("callback", "adapter_sha256"))])
  out
}
