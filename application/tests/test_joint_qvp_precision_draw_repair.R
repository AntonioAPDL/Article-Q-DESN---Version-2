#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)
source(app_path("application/R/joint_qvp_qdesn.R"))

near_precision <- diag(c(1, 1, -1.0e-10))
no_repair <- suppressWarnings(try(app_joint_qvp_precision_draw(
  rep(0, 3), near_precision, max_dense_dim = 0L, repair = FALSE
), silent = TRUE))
stopifnot(inherits(no_repair, "try-error"))

env <- new.env(parent = emptyenv())
set.seed(20260908)
draw_a <- suppressWarnings(app_joint_qvp_precision_draw(
  rep(0, 3), near_precision, max_dense_dim = 0L, repair = TRUE,
  repair_start_rel = 1.0e-12, repair_max_rel = 1.0e-8,
  diagnostic_env = env
))
diag_a <- env$last_precision_draw
stopifnot(
  length(draw_a) == 3L,
  all(is.finite(draw_a)),
  identical(diag_a$status[[1L]], "repaired"),
  diag_a$jitter_relative[[1L]] <= 1.0e-8,
  diag_a$jitter_absolute[[1L]] > 0
)

env_b <- new.env(parent = emptyenv())
set.seed(20260908)
draw_b <- suppressWarnings(app_joint_qvp_precision_draw(
  rep(0, 3), near_precision, max_dense_dim = 0L, repair = TRUE,
  repair_start_rel = 1.0e-12, repair_max_rel = 1.0e-8,
  diagnostic_env = env_b
))
stopifnot(identical(round(draw_a, 12), round(draw_b, 12)))

hard_precision <- diag(c(1, 1, -0.1))
hard_failure <- suppressWarnings(try(app_joint_qvp_precision_draw(
  rep(0, 3), hard_precision, max_dense_dim = 0L, repair = TRUE,
  repair_start_rel = 1.0e-12, repair_max_rel = 1.0e-8
), silent = TRUE))
stopifnot(inherits(hard_failure, "try-error"))

direct_env <- new.env(parent = emptyenv())
set.seed(9)
direct <- app_joint_qvp_precision_draw(
  rep(0, 3), diag(c(1, 2, 3)), max_dense_dim = 0L,
  repair = TRUE, diagnostic_env = direct_env
)
stopifnot(
  all(is.finite(direct)),
  identical(direct_env$last_precision_draw$status[[1L]], "direct"),
  direct_env$last_precision_draw$jitter_relative[[1L]] == 0
)

fixture <- app_joint_qvp_simulate_synthetic(
  Tn = 18L, p = 2L, tau = c(0.25, 0.5, 0.75), seed = 20260910
)
al_args <- list(
  y = fixture$y, Z = fixture$Z, tau = fixture$tau,
  n_iter = 10L, burn = 4L, thin = 2L, seed = 202609101L,
  tau0 = 0.5, zeta2 = 1, slab_fixed = TRUE,
  alpha_prior_mean = "empirical_quantile", alpha_prior_sd = 2,
  max_dense_dim = 0L
)
al_direct <- do.call(app_joint_qvp_fit_al_mcmc_tiny,
  c(al_args, list(precision_repair = FALSE)))
al_guarded <- do.call(app_joint_qvp_fit_al_mcmc_tiny,
  c(al_args, list(
    precision_repair = TRUE,
    precision_repair_start_rel = 1.0e-12,
    precision_repair_max_rel = 1.0e-8,
    precision_repair_growth = 10
  )))
stopifnot(
  identical(al_direct$beta_draws, al_guarded$beta_draws),
  identical(al_direct$alpha_draws, al_guarded$alpha_draws),
  identical(al_direct$sigma_draws, al_guarded$sigma_draws),
  !isTRUE(al_direct$precision_repair_enabled),
  isTRUE(al_guarded$precision_repair_enabled),
  al_guarded$precision_repair_count == 0L,
  al_guarded$precision_repair_max_rel_used == 0,
  is.data.frame(al_guarded$precision_repair_diagnostics),
  nrow(al_guarded$precision_repair_diagnostics) == 0L
)

cat("JOINT QVP precision draw repair tests passed\n")
