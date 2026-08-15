repo_root <- normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R",
  "joint_qdesn_simulation_validation.R", "joint_qdesn_vb_spec_screening.R",
  "joint_qdesn_calibration_screening.R", "joint_qdesn_mcmc_readiness.R",
  "joint_exqdesn_trace_tools.R", "joint_exqdesn_phase136_gamma_kernel_packet.R",
  "joint_exqdesn_phase145_gamma_sampler_root_cause.R",
  "joint_exqdesn_phase146_sigma_gamma_geometry.R"
)) source(app_path("application/R", path))

specs <- app_joint_exqdesn_phase146_variant_specs()
stopifnot(nrow(specs) == 3L)
stopifnot(sum(specs$gamma_update == "joint_rw_mh") == 2L)
stopifnot(all(abs(specs$gamma_sigma_mh_rho_abs[specs$gamma_update == "joint_rw_mh"] - 0.9) < 1e-12))

set.seed(146L)
y <- stats::rnorm(12)
Z <- cbind(1, seq(-1, 1, length.out = 12))
fit1 <- app_joint_qvp_fit_exal_mcmc_tiny(
  y, Z, c(0.25, 0.75), n_iter = 20L, burn = 10L, thin = 2L, seed = 1461L,
  gamma_update = "joint_rw_mh", gamma_refresh_repeats = 2L,
  gamma_sigma_mh_eta_sd = 0.2, gamma_sigma_mh_log_sigma_sd = 0.04,
  gamma_sigma_mh_rho = c(-0.9, 0.9), max_dense_dim = 20L
)
fit2 <- app_joint_qvp_fit_exal_mcmc_tiny(
  y, Z, c(0.25, 0.75), n_iter = 20L, burn = 10L, thin = 2L, seed = 1461L,
  gamma_update = "joint_rw_mh", gamma_refresh_repeats = 2L,
  gamma_sigma_mh_eta_sd = 0.2, gamma_sigma_mh_log_sigma_sd = 0.04,
  gamma_sigma_mh_rho = c(-0.9, 0.9), max_dense_dim = 20L
)
stopifnot(all(is.finite(fit1$gamma_draws)), all(is.finite(fit1$sigma_draws)))
stopifnot(all(fit1$sigma_draws > 0))
stopifnot(identical(round(fit1$gamma_draws, 12), round(fit2$gamma_draws, 12)))
stopifnot(identical(round(fit1$sigma_draws, 12), round(fit2$sigma_draws, 12)))
stopifnot(all(is.finite(fit1$gamma_sigma_mh_acceptance_rate)))
stopifnot(all(fit1$gamma_sigma_mh_acceptance_rate >= 0 & fit1$gamma_sigma_mh_acceptance_rate <= 1))

cat("Joint exQDESN Phase146 sigma-gamma geometry tests passed.\n")
