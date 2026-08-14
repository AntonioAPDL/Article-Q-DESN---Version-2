#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_exqdesn_exact_structured_inference.R"))
source(app_path("application/R/joint_exqdesn_inference_dispatch.R"))

registry <- app_joint_exqdesn_load_method_registry()
stopifnot(nrow(registry) == 8L)
stopifnot(!anyDuplicated(registry$method_id))
stopifnot(all(c(
  "VB0_point_v", "VB1_structured_v", "VB2_structured_u",
  "M0_v_collapsed_support_logit", "M1b_u_collapsed_support_logit",
  "M1_u_collapsed_p_logit", "K_branch_inverse_cdf"
) %in% registry$method_id))
policy <- app_joint_exqdesn_load_default_policy()
stopifnot(nrow(policy) == 1L)
stopifnot(identical(
  app_joint_exqdesn_default_method_id("mcmc"),
  "M0_v_collapsed_support_logit"
))

fixture <- app_joint_qvp_simulate_ts_toy_synthetic(
  Tn = 22L,
  tau = c(0.25, 0.75),
  seed = 2026080611L,
  innovation = "gaussian"
)
vb_args <- list(
  y = fixture$y,
  Z = fixture$Z,
  tau = fixture$tau,
  max_iter = 2L,
  tol = 1.0e-4,
  max_dense_dim = 100L
)
legacy_vb <- do.call(app_joint_exqdesn_fit_vb_dispatch, vb_args)
explicit_vb0 <- do.call(app_joint_exqdesn_fit_vb_dispatch, c(list(method_id = "VB0_point_v"), vb_args))
stopifnot(max(abs(legacy_vb$qhat_mean - explicit_vb0$qhat_mean)) < 1.0e-12)
stopifnot(identical(legacy_vb$inference_method_id, "legacy_implicit_VB0_point_v"))
stopifnot(identical(explicit_vb0$inference_method_id, "VB0_point_v"))

vb2 <- app_joint_exqdesn_fit_vb_dispatch(
  method_id = "VB2_structured_u",
  y = fixture$y,
  Z = fixture$Z,
  tau = fixture$tau,
  max_iter = 2L,
  tol = 1.0e-4,
  max_dense_dim = 100L,
  init = explicit_vb0,
  quadrature_nodes = c(4L, 8L),
  quadrature_tolerance = 1.0e-3,
  diagnostic_stride = 1L
)
stopifnot(identical(vb2$inference_method_id, "VB2_structured_u"))
stopifnot(identical(vb2$fit_structure, "joint"))
stopifnot(all(is.finite(vb2$qhat_mean)))

independent <- app_joint_exqdesn_fit_independent_vb_dispatch(
  method_id = "VB1_structured_v",
  y = fixture$y,
  Z = fixture$Z,
  tau = fixture$tau,
  max_iter = 1L,
  tol = 1.0e-4,
  max_dense_dim = 100L,
  quadrature_nodes = c(4L, 8L),
  quadrature_tolerance = 1.0e-3,
  diagnostic_stride = 1L
)
stopifnot(length(independent$fits) == length(fixture$tau))
stopifnot(all(independent$component_method_ids == "VB1_structured_v"))
stopifnot(identical(independent$fit_structure, "independent"))

mcmc_args <- list(
  y = fixture$y,
  Z = fixture$Z,
  tau = 0.5,
  n_iter = 16L,
  burn = 8L,
  thin = 2L,
  seed = 2026080612L,
  max_dense_dim = 100L
)
default_mcmc <- do.call(app_joint_exqdesn_fit_mcmc_dispatch, mcmc_args)
explicit_default <- do.call(
  app_joint_exqdesn_fit_mcmc_dispatch,
  c(list(method_id = "M0_v_collapsed_support_logit"), mcmc_args)
)
explicit_legacy <- do.call(
  app_joint_exqdesn_fit_mcmc_dispatch,
  c(list(method_id = "MCMC_legacy_default"), mcmc_args)
)
stopifnot(max(abs(default_mcmc$beta_draws - explicit_default$beta_draws)) < 1.0e-12)
stopifnot(identical(default_mcmc$inference_method_id, "M0_v_collapsed_support_logit"))
stopifnot(identical(default_mcmc$inference_method_source, "production_default"))
stopifnot(identical(explicit_default$inference_method_source, "explicit"))
stopifnot(identical(explicit_legacy$gamma_update, "bounded_slice"))
stopifnot(identical(explicit_legacy$inference_method_id, "MCMC_legacy_default"))
stopifnot(identical(explicit_legacy$inference_method_source, "explicit"))

m0 <- do.call(
  app_joint_exqdesn_fit_mcmc_dispatch,
  c(list(method_id = "M0_v_collapsed_support_logit"), mcmc_args)
)
stopifnot(identical(m0$gamma_update, "collapsed_logit_slice"))
stopifnot(identical(m0$inference_method_id, "M0_v_collapsed_support_logit"))

m1b <- app_joint_exqdesn_fit_mcmc_dispatch(
  method_id = "M1b_u_collapsed_support_logit",
  y = fixture$y,
  Z = fixture$Z,
  tau = 0.5,
  n_iter = 16L,
  burn = 8L,
  thin = 2L,
  seed = 2026080613L,
  max_dense_dim = 100L
)
stopifnot(identical(m1b$gamma_coordinate, "support_logit"))
stopifnot(isTRUE(m1b$sigma_collapsed))
stopifnot(all(is.finite(m1b$qhat_mean)))

independent_default <- app_joint_exqdesn_fit_independent_mcmc_dispatch(
  y = fixture$y,
  Z = fixture$Z,
  tau = 0.5,
  n_iter = 16L,
  burn = 8L,
  thin = 2L,
  seed = 2026080614L,
  max_dense_dim = 100L
)
stopifnot(identical(
  independent_default$inference_method_id,
  "M0_v_collapsed_support_logit"
))
stopifnot(identical(
  independent_default$inference_method_source,
  "production_default"
))

cat("exQDESN inference dispatch tests passed.\n")
