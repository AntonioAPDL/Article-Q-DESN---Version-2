repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
}
source(file.path(repo_root, "application/R/00_packages.R")); app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R", "joint_exqdesn_trace_tools.R", "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_exqdesn_phase158_fan_audit.R", "joint_exqdesn_phase159_split_rhs_screening.R"
)) source(app_path("application/R", file))

# Legacy and explicit equal-block controls must be exactly identical.
legacy <- app_joint_qvp_initialize_rhs_state(3, 2, tau0 = 0.4, zeta2 = 16)
explicit <- app_joint_qvp_initialize_rhs_state(
  3, 2, tau0 = 0.4, zeta2 = 16,
  anchor_tau0 = 0.4, innovation_tau0 = 0.4,
  anchor_zeta2 = 16, innovation_zeta2 = 16
)
stopifnot(identical(legacy, explicit))
split <- app_joint_qvp_initialize_rhs_state(
  3, 2, tau0 = 0.4, zeta2 = 16,
  anchor_tau0 = 0.4, innovation_tau0 = 0.8,
  anchor_zeta2 = 16, innovation_zeta2 = 32
)
stopifnot(split$anchor$tau0 == 0.4, split$delta_2$tau0 == 0.8)
stopifnot(split$anchor$zeta2 == 16, split$delta_2$zeta2 == 32)
P_legacy <- app_joint_qvp_build_prior_precision(3, 2, app_joint_qvp_rhs_state_to_prior(legacy)$anchor, app_joint_qvp_rhs_state_to_prior(legacy)$innovations)$P_beta
P_split <- app_joint_qvp_build_prior_precision(3, 2, app_joint_qvp_rhs_state_to_prior(split)$anchor, app_joint_qvp_rhs_state_to_prior(split)$innovations)$P_beta
stopifnot(max(abs(as.matrix(P_legacy - P_split))) > 0)

# Small fitter exercise verifies that both VB and collapsed MCMC accept split controls.
set.seed(159)
Z <- cbind(1, stats::rnorm(30))
y <- 0.2 + 0.5 * Z[, 2] + stats::rnorm(30, sd = 0.3)
tau <- c(0.1, 0.5, 0.9)
vb <- app_joint_qvp_fit_exal_vb_ld_tiny(
  y, Z, tau, max_iter = 3, tau0 = 0.4, zeta2 = 16,
  anchor_tau0 = 0.4, innovation_tau0 = 0.8,
  anchor_zeta2 = 16, innovation_zeta2 = 32,
  a_sigma = 2, b_sigma = 1, alpha_prior_mean = "empirical_quantile",
  alpha_prior_sd = 1, rhs_vb_inner = 1
)
stopifnot(all(is.finite(vb$beta_mean)), all(vb$sigma_mean > 0))
mcmc <- app_joint_qvp_fit_exal_mcmc_tiny(
  y, Z, tau, n_iter = 10, burn = 5, thin = 1, seed = 159,
  tau0 = 0.4, zeta2 = 16, anchor_tau0 = 0.4, innovation_tau0 = 0.8,
  anchor_zeta2 = 16, innovation_zeta2 = 32,
  a_sigma = 2, b_sigma = 1, alpha_prior_mean = "empirical_quantile",
  alpha_prior_sd = 1, gamma_update = "collapsed_logit_slice",
  gamma_slice_width = 2, gamma_slice_max_steps = 40
)
stopifnot(nrow(mcmc$beta_draws) == 5, all(is.finite(mcmc$beta_draws)), all(mcmc$sigma_draws > 0))

# Quantile-fan decomposition preserves qhat = alpha + dynamic and finite gaps.
window <- list(
  role = "forecast", tau = tau, Z = Z,
  row_meta = data.frame(full_time_index = seq_len(nrow(Z))),
  y = y,
  true_q = cbind(-0.4 + 0.5 * Z[, 2], 0.2 + 0.5 * Z[, 2], 0.8 + 0.5 * Z[, 2])
)
posterior <- list(beta_mean = rep(c(0, 0.5), 3), alpha_mean = c(-0.3, 0.2, 0.7))
component <- app_joint_exqdesn_phase158_component_tables(window, posterior, "test")
stopifnot(nrow(component$quantile) == 3, nrow(component$adjacent) == 2)
stopifnot(all(is.finite(component$adjacent$fitted_to_true_gap_ratio)))
stopifnot(all(component$adjacent$nonpositive_fitted_gap_count == 0))

# Phase159 finalization metadata must satisfy the shared CRPS grouping contract.
meta_fixture <- c(window, list(
  scenario_id = "test_scenario",
  scenario_meta = data.frame(
    scenario_class = "stress", distribution_family = "Gaussian",
    dynamics_class = "test", stringsAsFactors = FALSE
  )
))
meta_row <- data.frame(
  case_id = "test_case", candidate_id = "test_candidate", stringsAsFactors = FALSE
)
meta_spec <- app_joint_qdesn_phase122_select_spec("joint_exqdesn_rhs_vb")
phase159_meta <- app_joint_qdesn_phase122_meta(
  meta_fixture, meta_spec, meta_row, "MCMC", "joint_exqdesn_rhs_mcmc_phase159"
)
phase159_score <- app_joint_qdesn_phase122_score_qhat(
  phase159_meta, meta_fixture,
  cbind(-0.3 + 0.5 * Z[, 2], 0.2 + 0.5 * Z[, 2], 0.7 + 0.5 * Z[, 2]),
  "qhat", "phase159_test"
)
phase159_crps <- app_joint_qdesn_crps_grid_summary(phase159_score$scored)
stopifnot(nrow(phase159_crps) == 1L, is.finite(phase159_crps$crps_grid_mean[[1L]]))

# The Phase159 registry is case-specific: six cases by four candidates.
tmp <- tempfile("phase159-registry-"); dir.create(tmp)
p158 <- file.path(tmp, "phase158"); p156 <- file.path(tmp, "phase156"); out <- file.path(tmp, "output")
dir.create(p158); dir.create(p156); dir.create(out)
scenarios <- paste0("scenario_", 1:6)
utils::write.csv(data.frame(
  scenario_id = scenarios, decision = "target_split_rhs_calibration",
  diagnosis = "synthetic compression", recommended_innovation_tau0_multipliers = c("1,1.25,1.5", "1,1.5,2", "1,2,3", "1,1.5,2", "1,1.5,2", "1,1.25,1.5"),
  stringsAsFactors = FALSE
), file.path(p158, "scenario_diagnosis.csv"), row.names = FALSE)
controls <- data.frame(
  case_id = paste0(scenarios, "__joint_exqdesn_rhs_vb"), scenario_ids = scenarios,
  model_ids = "joint_exqdesn_rhs_vb", candidate_id = paste0("base_", scenarios),
  vb_max_iter = 1200L, adaptive_vb_max_iter_grid = "1200", vb_tol = 1e-4,
  rhs_vb_inner = 5L, tau0 = 0.5, zeta2 = 16, a_sigma = 2, b_sigma = 1,
  alpha_prior_sd = 1, alpha_min_spacing = 0, max_dense_dim = 300L,
  stringsAsFactors = FALSE
)
utils::write.csv(controls, file.path(p156, "case_winner_controls.csv"), row.names = FALSE)
registry <- app_joint_exqdesn_phase159_registry(p158, p156, out)
stopifnot(nrow(registry) == 24L, !anyDuplicated(registry$candidate_id))
stopifnot(all(table(registry$scenario_ids) == 4L))
stopifnot(all(registry$anchor_tau0 == 0.5), any(registry$innovation_tau0 > registry$anchor_tau0))
unlink(tmp, recursive = TRUE)

cat("Phase158/159 focused tests passed.\n")
