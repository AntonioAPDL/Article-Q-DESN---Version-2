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
  "joint_exqdesn_phase147_hybrid_geometry.R"
)) source(app_path("application/R", path))

specs <- app_joint_exqdesn_phase147_variant_specs()
stopifnot(nrow(specs) == 3L)
stopifnot(sum(specs$gamma_update == "hybrid_refresh_joint_mh") == 2L)
stopifnot(all(specs$gamma_refresh_repeats[2:3] == 2L))

set.seed(147)
y <- stats::rnorm(14)
Z <- cbind(1, seq(-1, 1, length.out = 14))
args <- list(
  y = y, Z = Z, tau = c(0.25, 0.75), n_iter = 24L, burn = 12L,
  thin = 2L, seed = 1471L, gamma_update = "hybrid_refresh_joint_mh",
  gamma_refresh_repeats = 2L, gamma_refresh_block = "sigma_s",
  gamma_sigma_mh_repeats = 2L,
  gamma_sigma_mh_eta_sd = c(0.08, 0.08),
  gamma_sigma_mh_log_sigma_sd = c(0.014, 0.014),
  gamma_sigma_mh_rho = c(-0.9, 0.9), max_dense_dim = 20L
)
fit1 <- do.call(app_joint_qvp_fit_exal_mcmc_tiny, args)
fit2 <- do.call(app_joint_qvp_fit_exal_mcmc_tiny, args)
stopifnot(all(is.finite(fit1$gamma_draws)), all(fit1$sigma_draws > 0))
stopifnot(identical(round(fit1$gamma_draws, 12), round(fit2$gamma_draws, 12)))
stopifnot(identical(round(fit1$sigma_draws, 12), round(fit2$sigma_draws, 12)))
stopifnot(all(is.finite(fit1$gamma_sigma_mh_acceptance_rate)))

scored <- data.frame(
  scenario_id = "s", model_id = "m", display_label = "M", likelihood = "exal",
  fit_structure = "joint", inference = "MCMC",
  phase136_variant_id = rep(c("a", "b"), each = 4),
  tau = rep(c(0.25, 0.75), 4), check_loss = 1:8, hit = rep(c(TRUE,FALSE),4),
  truth_abs_error = 1:8, truth_sq_error = (1:8)^2, truth_error = 1:8
)
summary <- app_joint_qdesn_truth_summary(scored)
stopifnot(nrow(summary) == 4L)
stopifnot(all(c("phase136_variant_id", "inference") %in% names(summary)))

cat("Joint exQDESN Phase147 hybrid geometry tests passed.\n")
