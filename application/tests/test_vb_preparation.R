vb_cfg <- app_read_config(app_path("application/config/glofas_discrepancy_vb_large_dec25.yaml"))
vb_p50_cfg <- app_read_config(app_path("application/config/glofas_discrepancy_vb_large_dec25_p50_pilot.yaml"))
vb_dryrun_cfg <- app_read_config(app_path("application/config/glofas_discrepancy_vb_posterior_draw_dryrun.yaml"))
mcmc_cfg <- app_read_config(app_path("application/config/glofas_discrepancy_mcmc_large_dec25.yaml"))
vb_grid <- app_validate_model_grid(app_config_path(vb_cfg, "model_grid"), app_config_path(vb_cfg, "schema"))
vb_p50_grid <- app_validate_model_grid(app_config_path(vb_p50_cfg, "model_grid"), app_config_path(vb_p50_cfg, "schema"))
vb_dryrun_grid <- app_validate_model_grid(app_config_path(vb_dryrun_cfg, "model_grid"), app_config_path(vb_dryrun_cfg, "schema"))
app_validate_qdesn_model_grid_prior_contract(vb_grid)
app_validate_qdesn_model_grid_prior_contract(vb_p50_grid)
app_validate_qdesn_model_grid_prior_contract(vb_dryrun_grid)

stopifnot(identical(vb_cfg$application_name, "glofas_qdesn_discrepancy_vb_large_dec25"))
stopifnot(identical(vb_p50_cfg$application_name, "glofas_qdesn_discrepancy_vb_large_dec25_p50_pilot"))
stopifnot(identical(vb_dryrun_cfg$application_name, "glofas_qdesn_discrepancy_vb_posterior_draw_dryrun"))
stopifnot(identical(vb_cfg$paths$source_registry, mcmc_cfg$paths$source_registry))
stopifnot(identical(vb_p50_cfg$paths$source_registry, vb_cfg$paths$source_registry))
stopifnot(identical(vb_cfg$paths$input_bundle, mcmc_cfg$paths$input_bundle))
stopifnot(identical(vb_p50_cfg$paths$input_bundle, vb_cfg$paths$input_bundle))
stopifnot(identical(vb_cfg$paths$cutoffs, mcmc_cfg$paths$cutoffs))
stopifnot(identical(vb_p50_cfg$paths$cutoffs, vb_cfg$paths$cutoffs))
stopifnot(identical(vb_cfg$paths$quantile_grid, mcmc_cfg$paths$quantile_grid))
stopifnot(identical(vb_cfg$inference$default_method, "vb_ld"))
stopifnot(identical(vb_p50_cfg$inference$default_method, "vb_ld"))
stopifnot(identical(vb_cfg$inference$likelihood_family, "al"))
stopifnot(identical(vb_p50_cfg$inference$likelihood_family, "al"))
stopifnot(identical(vb_cfg$prediction$prediction_unit, "posterior_draw"))
stopifnot(identical(vb_p50_cfg$prediction$prediction_unit, "posterior_draw"))
stopifnot(identical(vb_dryrun_cfg$inference$default_method, "vb_ld"))
stopifnot(identical(vb_dryrun_cfg$inference$likelihood_family, "al"))
stopifnot(identical(vb_dryrun_cfg$prediction$prediction_unit, "posterior_draw"))
stopifnot(identical(vb_dryrun_cfg$prediction$q_g_source, "ensemble_bayesian_bootstrap_quantile"))
stopifnot(identical(vb_cfg$prediction$q_g_source, "ensemble_bayesian_bootstrap_quantile"))
stopifnot(identical(vb_p50_cfg$prediction$q_g_source, "ensemble_bayesian_bootstrap_quantile"))
stopifnot(identical(vb_cfg$feature_contract$version, "0.3"))
stopifnot(isTRUE(vb_cfg$feature_contract$two_block_design))
stopifnot(identical(as.integer(vb_cfg$feature_contract$blocks$discrepancy$reservoir_seed_offset), 1009L))
stopifnot(!isTRUE(vb_cfg$feature_contract$readout$include_input_block))
stopifnot(!isTRUE(vb_p50_cfg$feature_contract$readout$include_input_block))
stopifnot(!isTRUE(mcmc_cfg$feature_contract$readout$include_input_block))
stopifnot(!isTRUE(vb_cfg$feature_contract$readout$include_horizon_scaled))
stopifnot(!isTRUE(vb_p50_cfg$feature_contract$readout$include_horizon_scaled))
stopifnot(!isTRUE(mcmc_cfg$feature_contract$readout$include_horizon_scaled))
stopifnot(identical(vb_cfg$prediction$discrepancy_feature_strategy, "horizon_indexed_origin_state"))
stopifnot(identical(vb_p50_cfg$prediction$discrepancy_feature_strategy, "horizon_indexed_origin_state"))
stopifnot(isTRUE(vb_cfg$execution$inference_support$allow_unsupported_design_gate))
stopifnot(isTRUE(vb_p50_cfg$execution$inference_support$allow_unsupported_design_gate))
stopifnot(isTRUE(vb_cfg$execution$inference_support$require_supported_for_model_fit))
stopifnot(isTRUE(vb_p50_cfg$execution$inference_support$require_supported_for_model_fit))

qrows <- vb_grid[vb_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
stopifnot(nrow(qrows) == 3L)
stopifnot(all(qrows$inference_method == "vb_ld"))
stopifnot(all(qrows$likelihood_family == "al"))
stopifnot(all(qrows$coefficient_prior == "rhs"))
stopifnot(all(app_as_bool_vec(qrows$required)))

p50_qrows <- vb_p50_grid[vb_p50_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
stopifnot(nrow(p50_qrows) == 1L)
stopifnot(identical(as.numeric(p50_qrows$quantile_level[[1L]]), 0.50))
stopifnot(identical(p50_qrows$inference_method[[1L]], "vb_ld"))
stopifnot(identical(p50_qrows$likelihood_family[[1L]], "al"))
stopifnot(identical(p50_qrows$coefficient_prior[[1L]], "rhs"))
stopifnot(isTRUE(app_as_bool(p50_qrows$required[[1L]])))

fake_engine_report <- list(
  ok = TRUE,
  engine = "exdqlm",
  repo_git_sha = "fake",
  env = new.env(parent = emptyenv())
)

app_cfg <- app_read_config(app_path("application/config/glofas_discrepancy_application.yaml"))
app_grid <- app_validate_model_grid(app_config_path(app_cfg, "model_grid"), app_config_path(app_cfg, "schema"))
app_qrows <- app_grid[app_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
stopifnot(nrow(app_qrows) > 0L)
stopifnot(identical(app_model_row_likelihood_family(app_qrows[1L, , drop = FALSE], app_cfg), "exal"))
app_diag_row <- app_qrows[1L, , drop = FALSE]
app_diag_row$inference_method <- "mcmc"
stopifnot(identical(app_model_row_likelihood_family(app_diag_row, app_cfg), "al"))
app_support <- app_qdesn_discrepancy_inference_support(app_cfg, app_grid, fake_engine_report)
stopifnot(nrow(app_support) == nrow(app_qrows))
stopifnot(all(app_support$likelihood_family == "exal"))
stopifnot(!app_qdesn_inference_support_all_fit_ready(app_support, required_only = TRUE))
stopifnot(app_qdesn_inference_support_allows_input_gate(app_cfg, app_support))

vb_support <- app_qdesn_discrepancy_inference_support(vb_cfg, vb_grid, fake_engine_report)
stopifnot(nrow(vb_support) == 3L)
stopifnot(all(vb_support$requested_inference_method == "vb_ld"))
stopifnot(all(vb_support$engine_method == "vb"))
stopifnot(!any(app_as_bool_vec(vb_support$fit_supported)))
stopifnot(app_qdesn_inference_support_allows_input_gate(vb_cfg, vb_support))
stopifnot(!app_qdesn_inference_support_all_fit_ready(vb_support, required_only = TRUE))

capability_engine <- list(
  ok = TRUE,
  engine = "exdqlm",
  repo_git_sha = "fake",
  env = new.env(parent = emptyenv())
)
capability_engine$env$qdesn_discrepancy_capabilities <- function() {
  data.frame(
    method = c("mcmc", "vb", "mcmc", "vb"),
    likelihood_family = c("al", "al", "exal", "exal"),
    fit_supported = c(TRUE, TRUE, FALSE, FALSE),
    support_status = c(
      "implemented",
      "implemented",
      "not_yet_implemented",
      "not_yet_implemented"
    ),
    notes = c(
      "AL MCMC supported.",
      "AL VB supported.",
      "exAL MCMC gated.",
      "exAL VB gated."
    ),
    stringsAsFactors = FALSE
  )
}
vb_supported <- app_qdesn_discrepancy_inference_support(vb_cfg, vb_grid, capability_engine)
stopifnot(nrow(vb_supported) == 3L)
stopifnot(all(vb_supported$requested_inference_method == "vb_ld"))
stopifnot(all(vb_supported$engine_method == "vb"))
stopifnot(all(app_as_bool_vec(vb_supported$fit_supported)))
stopifnot(app_qdesn_inference_support_all_fit_ready(vb_supported, required_only = TRUE))

vb_p50_supported <- app_qdesn_discrepancy_inference_support(vb_p50_cfg, vb_p50_grid, capability_engine)
stopifnot(nrow(vb_p50_supported) == 1L)
stopifnot(identical(vb_p50_supported$requested_inference_method[[1L]], "vb_ld"))
stopifnot(identical(vb_p50_supported$engine_method[[1L]], "vb"))
stopifnot(isTRUE(app_as_bool(vb_p50_supported$fit_supported[[1L]])))
stopifnot(app_qdesn_inference_support_all_fit_ready(vb_p50_supported, required_only = TRUE))

vb_dryrun_supported <- app_qdesn_discrepancy_inference_support(vb_dryrun_cfg, vb_dryrun_grid, capability_engine)
vb_dryrun_qrows <- vb_dryrun_supported[vb_dryrun_supported$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
stopifnot(nrow(vb_dryrun_qrows) == 1L)
stopifnot(identical(vb_dryrun_qrows$requested_inference_method[[1L]], "vb_ld"))
stopifnot(identical(vb_dryrun_qrows$engine_method[[1L]], "vb"))
stopifnot(isTRUE(app_as_bool(vb_dryrun_qrows$fit_supported[[1L]])))

mcmc_cfg <- app_read_config(app_path("application/config/glofas_discrepancy_mcmc_large_dec25.yaml"))
mcmc_grid <- app_validate_model_grid(app_config_path(mcmc_cfg, "model_grid"), app_config_path(mcmc_cfg, "schema"))
mcmc_support <- app_qdesn_discrepancy_inference_support(mcmc_cfg, mcmc_grid, fake_engine_report)
stopifnot(nrow(mcmc_support) == 3L)
stopifnot(all(mcmc_support$requested_inference_method == "mcmc"))
stopifnot(all(mcmc_support$engine_method == "mcmc"))
stopifnot(all(app_as_bool_vec(mcmc_support$fit_supported)))
stopifnot(app_qdesn_inference_support_all_fit_ready(mcmc_support, required_only = TRUE))

vb_args <- app_make_qdesn_discrepancy_vb_args(vb_cfg, prior = "rhs_ns", seed = 42L, likelihood_family = "al")
stopifnot(identical(vb_args$beta_prior_type, "rhs_ns"))
stopifnot(identical(vb_args$max_iter, 200L))
stopifnot(identical(vb_args$max_iter_hard_cap, 500L))
stopifnot(identical(vb_args$n_draws, 2000L))
stopifnot(abs(vb_args$beta_rhs$tau0 - 1.0e-4) < 1.0e-14)
stopifnot(!isTRUE(vb_args$ld_block_active))
stopifnot(identical(vb_args$future_moment_strategy, "streamed_grouped"))
stopifnot(identical(vb_args$future_update_strategy, "linearized_delta"))
stopifnot(identical(vb_args$future_objective_strategy, "grouped"))
stopifnot(is.null(vb_args$chunking))

vb_cfg_chunked <- vb_cfg
vb_cfg_chunked$inference$vb_ld$chunking <- list(enabled = TRUE, mode = "exact", chunk_size = 128L, order = "sequential")
vb_args_chunked <- app_make_qdesn_discrepancy_vb_args(vb_cfg_chunked, prior = "rhs_ns", seed = 42L, likelihood_family = "al")
stopifnot(isTRUE(vb_args_chunked$chunking$enabled))
stopifnot(identical(vb_args_chunked$chunking$mode, "exact"))
stopifnot(identical(as.integer(vb_args_chunked$chunking$chunk_size), 128L))

vb_exact_chunked_smoke_cfg <- app_read_config(app_path("application/config/glofas_latent_path_al_vb_dec25_exact_chunked_smoke.yaml"))
stopifnot(identical(vb_exact_chunked_smoke_cfg$application_name, "glofas_latent_path_al_vb_dec25_exact_chunked_smoke"))
smoke_vb_args <- app_make_qdesn_discrepancy_vb_args(vb_exact_chunked_smoke_cfg, prior = "rhs_ns", seed = 42L, likelihood_family = "al")
stopifnot(isTRUE(smoke_vb_args$chunking$enabled))
stopifnot(identical(smoke_vb_args$chunking$mode, "exact"))
stopifnot(identical(as.integer(smoke_vb_args$chunking$chunk_size), 512L))

exal_args <- app_make_qdesn_discrepancy_vb_args(vb_cfg, prior = "rhs_ns", seed = 42L, likelihood_family = "exal")
stopifnot(isTRUE(exal_args$ld_block_active))

vb_cfg_too_long <- vb_cfg
vb_cfg_too_long$inference$vb_ld$max_iter <- 501L
cap_error <- tryCatch({
  app_make_qdesn_discrepancy_vb_args(vb_cfg_too_long, prior = "rhs_ns", seed = 42L, likelihood_family = "al")
  FALSE
}, error = function(e) grepl("hard cap", conditionMessage(e)))
stopifnot(isTRUE(cap_error))

mock_theta <- matrix(
  c(
    1.0, 0.2, -0.5, 0.1,
    1.1, 0.1, -0.4, 0.2,
    0.9, 0.3, -0.6, 0.0
  ),
  nrow = 3L,
  byrow = TRUE
)
mock_result <- list(
  fit_id = "mock_vb",
  model_id = "mock_vb_model",
  model_family = "qdesn_glofas_discrepancy",
  quantile_level = 0.5,
  method = "vb",
  likelihood_family = "al",
  coefficient_prior = "rhs_ns",
  fit = list(
    draws = list(theta = mock_theta),
    vb_diagnostics = list(
      converged = TRUE,
      iterations = 22L,
      runtime_seconds = 1.5,
      elbo_final = -123.4,
      elbo_relative_change = 9.0e-5,
      max_parameter_change = 8.0e-5
    )
  ),
  design = list(
    beta_index = 1:2,
    alpha_index = 3:4
  )
)
diag <- app_discrepancy_fit_diagnostics(mock_result)
stopifnot(identical(diag$method, "vb"))
stopifnot(is.na(diag$theta_ess_min))
stopifnot(is.na(diag$sigma_ess_min))
stopifnot(isTRUE(diag$vb_converged))
stopifnot(identical(as.integer(diag$vb_iterations), 22L))
stopifnot(abs(diag$vb_runtime_seconds - 1.5) < 1.0e-12)
stopifnot(abs(diag$vb_elbo_final + 123.4) < 1.0e-12)
stopifnot(abs(diag$vb_max_parameter_change - 8.0e-5) < 1.0e-12)
