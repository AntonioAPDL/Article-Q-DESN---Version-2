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

Z_direct <- Matrix::Matrix(matrix(c(1, 0, 0, 1, 1, 1), nrow = 3L),
  sparse = TRUE)
y_direct <- c(0.2, -0.1, 0.4)
w_direct <- c(1.1, 0.9, 1.3)
P_direct <- Matrix::Diagonal(x = c(0.5, 0.8))
historical_update <- app_joint_qvp_beta_gaussian_update(
  Z_direct, y_direct, w_direct, P_direct
)
set.seed(20260911)
historical_draw <- app_joint_qvp_precision_draw(
  historical_update$mean, historical_update$precision,
  max_dense_dim = 0L, repair = FALSE
)
system_env <- new.env(parent = emptyenv())
set.seed(20260911)
guarded_draw <- app_joint_qvp_beta_gaussian_draw(
  Z_direct, y_direct, w_direct, P_direct,
  max_dense_dim = 0L, repair = TRUE,
  repair_start_rel = 1.0e-12, repair_max_rel = 1.0e-8,
  diagnostic_env = system_env
)
stopifnot(
  identical(historical_draw, guarded_draw$beta),
  identical(historical_update$mean, guarded_draw$mean),
  identical(historical_update$precision, guarded_draw$precision),
  identical(system_env$last_precision_draw$status[[1L]], "direct"),
  identical(system_env$last_precision_draw$failure_stage[[1L]], "none")
)

Z_singular <- Matrix::Matrix(matrix(0, nrow = 2L, ncol = 2L), sparse = TRUE)
P_singular <- Matrix::forceSymmetric(Matrix::Matrix(
  matrix(c(1, 1, 1, 1 + 1.0e-16), nrow = 2L), sparse = TRUE
))
mean_failure <- suppressWarnings(try(app_joint_qvp_beta_gaussian_draw(
  Z_singular, c(0, 0), c(1, 1), P_singular,
  max_dense_dim = 0L, repair = FALSE
), silent = TRUE))
stopifnot(inherits(mean_failure, "try-error"))

mean_repair_env <- new.env(parent = emptyenv())
set.seed(20260912)
mean_repaired <- suppressWarnings(app_joint_qvp_beta_gaussian_draw(
  Z_singular, c(0, 0), c(1, 1), P_singular,
  max_dense_dim = 0L, repair = TRUE,
  repair_start_rel = 1.0e-12, repair_max_rel = 1.0e-8,
  diagnostic_env = mean_repair_env
))
stopifnot(
  all(is.finite(mean_repaired$beta)),
  identical(mean_repair_env$last_precision_draw$status[[1L]], "repaired"),
  identical(mean_repair_env$last_precision_draw$failure_stage[[1L]],
    "mean_solve"),
  mean_repair_env$last_precision_draw$jitter_relative[[1L]] <= 1.0e-8
)

P_draw_failure <- Matrix::Diagonal(x = c(1, 1, -1.0e-10))
draw_failure_update <- app_joint_qvp_beta_gaussian_update(
  Matrix::Matrix(matrix(0, nrow = 3L, ncol = 3L), sparse = TRUE),
  rep(0, 3), rep(1, 3), P_draw_failure
)
set.seed(20260913)
historical_repaired_draw <- suppressWarnings(app_joint_qvp_precision_draw(
  draw_failure_update$mean, draw_failure_update$precision,
  max_dense_dim = 0L, repair = TRUE,
  repair_start_rel = 1.0e-12, repair_max_rel = 1.0e-8
))
draw_repair_env <- new.env(parent = emptyenv())
set.seed(20260913)
draw_repaired <- suppressWarnings(app_joint_qvp_beta_gaussian_draw(
  Matrix::Matrix(matrix(0, nrow = 3L, ncol = 3L), sparse = TRUE),
  rep(0, 3), rep(1, 3), P_draw_failure,
  max_dense_dim = 0L, repair = TRUE,
  repair_start_rel = 1.0e-12, repair_max_rel = 1.0e-8,
  diagnostic_env = draw_repair_env
))
stopifnot(
  all(is.finite(draw_repaired$beta)),
  identical(historical_repaired_draw, draw_repaired$beta),
  identical(draw_repair_env$last_precision_draw$status[[1L]], "repaired"),
  identical(draw_repair_env$last_precision_draw$failure_stage[[1L]],
    "draw_factorization"),
  draw_repair_env$last_precision_draw$jitter_relative[[1L]] <= 1.0e-8
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
