cfg_recovery_unit <- list(
  inference = list(
    vb_ld = list(
      max_iter = 4L,
      min_iter_elbo = 1L,
      tol = 1.0e-4,
      n_draws = 6L,
      rhs_tau0 = 0.5,
      intercept_prec = 1.0e-9,
      sigma_a = 2,
      sigma_b = 1
    ),
    mcmc = list(rhs_tau0 = 0.5, intercept_prec = 1.0e-9),
    likelihood_family = "al"
  ),
  synthetic_recovery = list(
    n_history = 35L,
    horizon = 3L,
    n_members = 8L,
    seed = 20260513L,
    p0 = 0.5
  ),
  reservoir = list(seed = 20260513L)
)

sim_recovery_unit <- app_latent_path_recovery_simulate(cfg_recovery_unit)
design_recovery_unit <- app_make_latent_path_recovery_design(sim_recovery_unit, cfg_recovery_unit)
stopifnot(inherits(design_recovery_unit, "glofas_latent_path_design"))
stopifnot(nrow(design_recovery_unit$H_fixed) == 2L * cfg_recovery_unit$synthetic_recovery$n_history)
stopifnot(nrow(design_recovery_unit$future_key) == cfg_recovery_unit$synthetic_recovery$horizon)
probe_recovery_unit <- design_recovery_unit$future_builder(design_recovery_unit$y_future_init)
stopifnot(nrow(probe_recovery_unit$H_y) == cfg_recovery_unit$synthetic_recovery$horizon)
stopifnot(nrow(probe_recovery_unit$H_g) == cfg_recovery_unit$synthetic_recovery$horizon * cfg_recovery_unit$synthetic_recovery$n_members)
stopifnot(all(vapply(probe_recovery_unit$J_y, function(J) all(dim(J) == c(ncol(design_recovery_unit$H_fixed), nrow(design_recovery_unit$future_key))), logical(1L))))

fit_recovery_unit <- app_fit_latent_path_al_vb_core(
  design = design_recovery_unit,
  p0 = sim_recovery_unit$p0,
  coefficient_prior = "rhs_ns",
  vb_args = app_make_qdesn_discrepancy_vb_args(cfg_recovery_unit, prior = "rhs_ns", seed = sim_recovery_unit$seed, likelihood_family = "al"),
  seed = sim_recovery_unit$seed
)
vb_args_recovery_chunked <- app_make_qdesn_discrepancy_vb_args(
  cfg_recovery_unit,
  prior = "rhs_ns",
  seed = sim_recovery_unit$seed,
  likelihood_family = "al"
)
vb_args_recovery_chunked$chunking <- list(enabled = TRUE, mode = "exact", chunk_size = 7L, order = "sequential")
fit_recovery_chunked <- app_fit_latent_path_al_vb_core(
  design = design_recovery_unit,
  p0 = sim_recovery_unit$p0,
  coefficient_prior = "rhs_ns",
  vb_args = vb_args_recovery_chunked,
  seed = sim_recovery_unit$seed
)
stopifnot(isTRUE(fit_recovery_chunked$vb_diagnostics$chunking$enabled))
stopifnot(identical(fit_recovery_chunked$vb_diagnostics$chunking$mode, "exact"))
stopifnot(nrow(fit_recovery_chunked$vb_diagnostics$iteration_timing) > 0L)
stopifnot(max(abs(fit_recovery_unit$summary$theta_mean - fit_recovery_chunked$summary$theta_mean)) < 1.0e-10)
stopifnot(max(abs(fit_recovery_unit$summary$theta_cov - fit_recovery_chunked$summary$theta_cov)) < 1.0e-10)
stopifnot(max(abs(fit_recovery_unit$summary$y_future_mean - fit_recovery_chunked$summary$y_future_mean)) < 1.0e-10)
stopifnot(max(abs(fit_recovery_unit$summary$sigma_mean - fit_recovery_chunked$summary$sigma_mean)) < 1.0e-10)
metrics_recovery_unit <- app_latent_path_recovery_metrics(
  fit_recovery_unit,
  design_recovery_unit,
  tolerances = list(max_draw_identity_error = 1.0e-8)
)
stopifnot(is.finite(metrics_recovery_unit$q_y_rmse))
stopifnot(isTRUE(metrics_recovery_unit$finite_draws))
stopifnot(isTRUE(metrics_recovery_unit$pass_draw_identity))
