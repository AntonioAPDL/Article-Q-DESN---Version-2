# Generated adapter contract only. The real two-DESN state engine is covered by
# test_glofas_two_desn_particle_backend.R.
local({
  source("scripts/diagnostics/glofas_global_path_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_forecast_factorial_diagnostic.R", local = TRUE)
  gtdpb_reference_locations <- function(binding, path, parameters) {
    reference <- numeric(28L)
    ensemble <- numeric(28L)
    for (h in 1:28) {
      prefix <- if (h == 1L) 0 else path[h - 1L]
      reference[h] <- parameters$coefficients[1L] + .1 * tanh(prefix)
      ensemble[h] <- reference[h] + parameters$coefficients[2L]
    }
    list(reference = reference, ensemble = ensemble)
  }
  source("scripts/diagnostics/glofas_native_factorial_adapter.R", local = TRUE)
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L }
  reject <- function(expr) ok(inherits(try(force(expr), silent = TRUE), "try-error"))
  binding <- list(schema_version = "glofas_two_desn_particle_binding_v1",
    horizon = 28L, members = matrix(0, 28L, 51L),
    member_policy = "unit_member_likelihood_v1", member_factors_per_path = 28L * 51L,
    future_truth_read = FALSE, production_qualified = FALSE, member_weights = rep(1, 51L),
    spec = list(p = 2L, probability = .5),
    static_sha256 = paste(rep("a", 64L), collapse = ""),
    target_identity = list(task_id = "generated", posterior_target_sha256 =
      paste(rep("b", 64L), collapse = ""), prior_sha256 = paste(rep("c", 64L), collapse = "")),
    dates = as.Date("2022-12-25") + 1:28, contracts = list(generated = TRUE),
    initial_states = list(generated = TRUE), gains = c(beta = .5, alpha = .35))
  parameters <- list(coefficients = c(.1, -.2), sigma = c(Y = .7, G = .3))
  adapter <- gnfa_build(binding, parameters, rep(0, 28L), diag(28L))
  ok(identical(adapter$schema_version, "glofas_native_factorial_adapter_v1") &&
    length(adapter$contracts) == 4L && adapter$primary_contract ==
      "same_family_al_transition__unit_member_likelihood_v1")
  ok(sum(vapply(adapter$contracts, function(x) x$promotion_eligible, logical(1L))) == 1L &&
    sum(vapply(adapter$contracts, function(x) x$authentic_source_diagnostic_only,
      logical(1L))) == 2L)
  ok(!adapter$future_truth_read && adapter$original_file_reads == 0L &&
    adapter$full_parameter_refits == 0L && !adapter$production_qualified)
  locations <- adapter$callback(rep(0, 28L))
  ok(length(locations$reference_location) == 28L &&
    length(locations$ensemble_location) == 28L &&
    all(is.finite(c(locations$reference_location, locations$ensemble_location))))
  primary <- adapter$contracts[[adapter$primary_contract]]
  fractional <- adapter$contracts[[
    "same_family_al_transition__fractional_marginal_information_diagnostic_v1"]]
  components_primary <- gffd_log_target(rep(0, 28L), adapter$callback, primary, TRUE)
  components_fractional <- gffd_log_target(rep(0, 28L), adapter$callback, fractional, TRUE)
  ok(abs(components_primary$members - 51 * components_fractional$members) < 1e-10)
  repeated <- gnfa_build(binding, parameters, rep(0, 28L), diag(28L))
  ok(identical(adapter$adapter_sha256, repeated$adapter_sha256) &&
    identical(adapter$parameter_id, repeated$parameter_id) &&
    identical(adapter$feature_id, repeated$feature_id))
  bad <- binding; bad$member_weights[1L] <- 1 / 51
  reject(gnfa_build(bad, parameters, rep(0, 28L), diag(28L)))
  bad <- parameters; bad$coefficients <- bad$coefficients[1L]
  reject(gnfa_build(binding, bad, rep(0, 28L), diag(28L)))
  reject(gnfa_build(binding, parameters, rep(0, 27L), diag(27L)))
  message("GLOFAS_NATIVE_FACTORIAL_ADAPTER_PASS checks=", checks,
    " authentic_reads=0 scientific_fits=0")
})
