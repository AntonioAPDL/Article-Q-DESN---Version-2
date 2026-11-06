local({
  source("scripts/diagnostics/glofas_collapsed_parameter_optimizer.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_al_target.R", local = TRUE)
  source("scripts/diagnostics/glofas_native_parameter_optimizer.R", local = TRUE)
  n <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); n <<- n + 1L }
  reject <- function(x) ok(inherits(try(force(x), silent = TRUE), "try-error"))
  hex <- function(x) paste(rep(x, 64L), collapse = "")
  block <- function(ix, tau0) list(index = ix, intercept_index = ix[1L],
    tau0 = tau0, intercept_prec = 1e-9, slab_shape = 2, slab_rate = 4,
    zeta2_fixed = NULL)
  spec <- gcat_spec(6L, list(beta = block(1:3, .1), alpha = block(4:6, .2)),
    .5, list(Y = c(shape = 2, rate = 1), G = c(shape = 2, rate = 1)))
  prior_export <- function(beta_tau0, alpha_tau0) {
    rhs <- function(tau0) list(tau0 = tau0, intercept_prec = 1e-9,
      slab = list(learned = TRUE, zeta2_fixed = NULL, a_zeta = 2,
        b_zeta = 4, slab_s2_initial = 4,
        slab_s2_role = "variational_state_initializer_not_prior_hyperparameter"),
      rhs_hierarchy = list(
        coefficient_product = "N(b;0,tau2*lambda2) times N(b;0,zeta2)",
        global_conditional_shape = "(r+1)/2 with intercept excluded",
        local_conditional_shape = 1))
    list(schema_version = "glofas_native_prior_export_v1",
      task_id = "gft-al-p050", posterior_target_sha256 = hex("7"),
      declared_prior_sha256 = hex("8"), effective_prior_sha256 = hex("9"),
      effective_prior = list(beta = rhs(beta_tau0), alpha = rhs(alpha_tau0),
        source_scale = list(Y = c(2, 1), G = c(2, 1)),
        coordinate_measure = "coefficients_and_log_positive_parameters",
        jacobian_count = 1L, prior_addition_allowed = FALSE))
  }
  prior <- prior_export(.1, .2)
  binding <- list(schema_version = "glofas_two_desn_particle_binding_v1",
    member_policy = "unit_member_likelihood_v1", target_identity = list(
      task_id = prior$task_id, posterior_target_sha256 = prior$posterior_target_sha256,
      prior_sha256 = prior$declared_prior_sha256), static_sha256 = hex("a"),
    horizon = 2L, member_factors_per_path = 102L,
    gains = c(beta = .5, alpha = .35))
  contract <- gnpo_contract(spec, binding, prior, c(hex("b"), hex("c")), TRUE)
  ok(contract$all_coordinate_count == spec$dimension &&
    length(contract$parameter_names) == spec$dimension)
  ok(contract$scope == "generated_native_interface_fixture" &&
    !contract$native_fit_authorized)
  gnpo_validate_contract(contract, spec$dimension); ok(TRUE)
  H <- rbind(c(1,.2,-.3,0,0,0), c(1,.4,.1,0,0,0),
    c(1,.2,-.3,1,.4,.2), c(1,.4,.1,1,-.2,.1))
  historical <- gcat_bind_historical(spec, H, c(.2,.3,.4,.7), c("Y","Y","G","G"))
  analytic <- function(m, s, factor) gcat_historical_elbo(m, s, historical, factor)
  evidence <- function(x, seed) list(log_estimate = -.01 * sum(x^2),
    complete = TRUE, diagnostic_thresholds_passed = TRUE, callback_calls = 1L)
  mean <- rep(.01, spec$dimension); log_sd <- rep(-2, spec$dimension)
  ctl <- gcpopt_control(max_iterations = 3L, batch_size = 8L,
    minimum_iterations = 3L, stable_iterations = 2L, max_wall_seconds = 60,
    max_evaluations = 100L, max_inner_calls = 1000L, inner_call_bound = 2L,
    seed = 2026110602L)
  generated <- gcpopt_input_contract(spec$coordinate_names, spec$coordinate_measure,
    list(case = "native_parity"), c(hex("b"), hex("c")))
  old <- gcpopt_optimize(log_evidence_estimate = evidence, initial_mean = mean,
    initial_log_sd = log_sd, control = ctl, input_contract = generated,
    analytic_historical = analytic)
  native <- gnpo_optimize(analytic, evidence, mean, log_sd, contract, ctl)
  ok(old$schema_version == "glofas_generated_collapsed_parameter_optimizer_v1")
  ok(native$schema_version == "glofas_native_collapsed_parameter_optimizer_experimental_v1")
  ok(identical(old$mean, native$mean) && identical(old$log_sd, native$log_sd))
  history_fields <- setdiff(names(old$history), "elapsed_seconds")
  ok(identical(old$history[history_fields], native$history[history_fields]) &&
    identical(old$last_gradient, native$last_gradient))
  ok(!native$native_application_qualified && !native$native_fit_authorized &&
    !native$production_launch_authorized)
  ok(grepl("Declared native target", native$seal_scope, fixed = TRUE) &&
    grepl("^[a-f0-9]{64}$", native$native_contract_validator_sha256))
  bad <- contract; bad$parameter_names <- rev(bad$parameter_names)
  reject(gnpo_optimize(analytic, evidence, mean, log_sd, bad, ctl))
  bad <- contract; bad$target_inputs$member_policy <- "fractional"
  reject(gnpo_validate_contract(bad, spec$dimension))
  bad <- contract; bad$native_fit_authorized <- TRUE
  reject(gnpo_validate_contract(bad, spec$dimension))
  bad_prior <- prior; bad_prior$effective_prior$beta$tau0 <- .11
  reject(gnpo_contract(spec, binding, bad_prior, hex("b"), TRUE))
  # Construct and validate the complete application-sized coordinate inventory
  # without reading a native design or running the optimizer.
  big <- gcat_spec(2502L, list(beta = block(1:1501, 5.2043087e-5),
    alpha = block(1502:2502, .0001159)), .5,
    list(Y = c(shape = 2, rate = 1), G = c(shape = 2, rate = 1)))
  app_binding <- binding; app_binding$horizon <- 28L
  app_binding$member_factors_per_path <- 1428L
  app_binding$static_sha256 <- hex("d")
  app_prior <- prior_export(5.2043087e-5, .0001159)
  app_binding$target_identity$prior_sha256 <- app_prior$declared_prior_sha256
  app <- gnpo_contract(big, app_binding, app_prior, c(hex("b"), hex("c")), FALSE)
  ok(big$dimension == 7510L && app$all_coordinate_count == 7510L)
  gnpo_validate_contract(app, 7510L); ok(TRUE)
  bad_binding <- app_binding; bad_binding$gains[["alpha"]] <- .36
  reject(gnpo_contract(big, bad_binding, app_prior, hex("b"), FALSE))
  cat(sprintf("GLOFAS_NATIVE_PARAMETER_OPTIMIZER_PASS checks=%d authentic_reads=0 model_runs=0\n", n))
})
