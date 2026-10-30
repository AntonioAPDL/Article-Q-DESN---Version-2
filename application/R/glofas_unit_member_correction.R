# Unit-member Part 4 target. Legacy targets retain their original defaults.

app_glofas_unit_member_contract <- function() {
  list(schema_version = "glofas_unit_member_part4_v1",
    policy = "unit_member_likelihood_v1", horizons = 28L, members = 51L,
    included_issued_factors = 1428L, future_truth_used_in_fit = FALSE,
    quantile_future_y_likelihood = FALSE,
    quantile_reporting = "monte_carlo_mean_reference_readout_location",
    normal_reporting = "latent_future_path_empirical_quantiles_type8",
    ensemble_factorization = "conditionally_independent_members_and_horizons_given_path_and_parameters",
    path_prior_source = "frozen_part3_normal_rhs_recursive_driver_bank",
    target_change_resets_iterations = TRUE, retuning_authorized = FALSE)
}

app_glofas_unit_member_materialize_design <- function(frozen_design) {
  app_validate_glofas_latent_path_design(frozen_design)
  if (is.null(frozen_design$future_context$latent_data) || is.null(frozen_design$latent_data)) {
    stop("Unit-member materialization requires the authentic saved future context.", call. = FALSE)
  }
  out <- frozen_design
  data <- out$latent_data
  data$ensemble_member_weight_policy <- "unit_member_likelihood_v1"
  data$g_ensemble$ensemble_weight <- app_glofas_latent_path_ensemble_weights(
    data$g_ensemble, "unit_member_likelihood_v1")
  app_validate_glofas_latent_path_data(data)
  if (nrow(data$future_key) != 28L || nrow(data$g_ensemble) != 1428L ||
      any(table(data$g_ensemble$horizon) != 51L) ||
      anyDuplicated(paste(data$g_ensemble$target_date, data$g_ensemble$member))) {
    stop("Unit-member correction requires exactly 28 horizons and 51 distinct members per horizon.", call. = FALSE)
  }
  out$latent_data <- data
  out$ensemble_member_weight_policy <- data$ensemble_member_weight_policy
  out$future_context$latent_data <- data
  out$future_builder <- app_make_latent_path_future_builder(out$future_context)
  out$design_version <- paste0(frozen_design$design_version, "__unit_member_v1")
  out$unit_member_contract <- app_glofas_unit_member_contract()
  attr(out, "future_probe_init") <- NULL
  app_validate_glofas_latent_path_design(out)
  if (!identical(out$H_fixed, frozen_design$H_fixed) ||
      !identical(out$z_fixed, frozen_design$z_fixed) ||
      !identical(out$weight_fixed, frozen_design$weight_fixed) ||
      !identical(out$future_key, frozen_design$future_key)) {
    stop("Unit-member materialization changed protected historical data or geometry.", call. = FALSE)
  }
  old <- app_latent_path_future_probe(frozen_design)
  new <- app_latent_path_future_probe(out)
  if (!identical(new$z_g, old$z_g) ||
      !isTRUE(all.equal(new$H_y, old$H_y, tolerance = 1e-12)) ||
      !isTRUE(all.equal(app_latent_future_H_g_key(new), app_latent_future_H_g_key(old), tolerance = 1e-12)) ||
      !all(new$weight_g == 1) ||
      identical(app_glofas_part4_state_contract_hash(out), app_glofas_part4_state_contract_hash(frozen_design))) {
    stop("Unit-member materialization failed future geometry/weight/identity checks.", call. = FALSE)
  }
  out
}

app_glofas_unit_member_validate_design <- function(design) {
  app_validate_glofas_latent_path_design(design)
  app_validate_glofas_latent_path_data(design$latent_data)
  app_validate_glofas_latent_path_data(design$future_context$latent_data)
  if (!identical(design$ensemble_member_weight_policy, "unit_member_likelihood_v1") ||
      !identical(design$unit_member_contract$schema_version, "glofas_unit_member_part4_v1") ||
      !identical(design$future_truth_policy, "physically_excluded_from_fit_objects_scoring_sidecar_only")) {
    stop("The unit-member worker rejects legacy or unversioned designs.", call. = FALSE)
  }
  probe <- app_latent_path_future_probe(design)
  if (length(probe$weight_g) != 1428L || any(probe$weight_g != 1) ||
      any((design$weight_fixed %||% rep(1, length(design$z_fixed))) != 1)) {
    stop("The unit-member worker requires unit weights for all included factors.", call. = FALSE)
  }
  H <- nrow(design$future_key)
  Js <- probe$J_g_key
  if (length(Js) != H || any(vapply(seq_len(H), function(h) {
      J <- as.matrix(Js[[h]])
      ncol(J) != H || any(!is.finite(J)) || any(abs(J[, seq.int(h, H), drop=FALSE]) > 1e-12)
    }, logical(1L)))) {
    stop("Unit-member future design violates its strictly lagged path-Jacobian contract.", call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_unit_member_vb_controls <- function(vb_args, cfg) {
  controls <- cfg$unit_member_execution
  if (is.null(controls) || !identical(controls$schema_version, "glofas_unit_member_execution_v1") ||
      !isTRUE(controls$reset_target_state) || as.integer(controls$joint_inner_workers) != 1L) {
    stop("Missing or unsafe unit-member execution controls.", call. = FALSE)
  }
  pass <- setdiff(names(controls), c("schema_version", "reset_target_state"))
  for (name in pass) vb_args[[name]] <- controls[[name]]
  vb_args$max_iter_hard_cap <- as.integer(controls$max_iter)
  # Initial values may transfer moments only, never convergence/objective state.
  vb_args$warm_start <- NULL
  vb_args$checkpoint <- NULL
  vb_args
}

app_glofas_unit_member_default_controls <- function() {
  list(schema_version = "glofas_unit_member_execution_v1", reset_target_state = TRUE,
    max_iter = 2000L, min_iter_elbo = 200L, tol = 1e-4,
    joint_outer_max_iter = 200L, joint_outer_min_iter = 10L,
    joint_outer_tol = 1e-3, joint_rhs_tol = 1e-3,
    joint_inner_max_iter = 60L, joint_inner_min_iter = 10L,
    joint_inner_workers = 1L, joint_rhs_freeze_outer_iters = 5L,
    joint_rhs_min_tau_updates = 2L, joint_require_post_release = TRUE,
    joint_terminal_consecutive_passes = 3L,
    quadrature_nodes = c(16L, 24L, 32L, 48L), quadrature_tolerance = 1e-6)
}
