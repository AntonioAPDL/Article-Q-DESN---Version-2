repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint exAL MCMC test.", call. = FALSE)
  }
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))

set.seed(20260701)
Tn <- 16L
Z <- cbind(
  x1 = seq(-0.8, 0.8, length.out = Tn),
  x2 = cos(seq(0, pi, length.out = Tn))
)
true_alpha <- c(-0.4, 0.35)
true_beta <- matrix(c(0.45, -0.15, 0.55, -0.05), nrow = 2L, ncol = 2L)
y <- as.numeric(true_alpha[[1L]] + Z %*% true_beta[, 1L] + stats::rt(Tn, df = 5) * 0.08)
tau <- c(0.25, 0.75)
gamma0 <- app_joint_qvp_default_gamma(tau)
support <- app_joint_qvp_exal_support(tau)

fit_a <- app_joint_qvp_fit_exal_mcmc_tiny(
  y = y,
  Z = Z,
  tau = tau,
  n_iter = 18L,
  burn = 9L,
  thin = 3L,
  seed = 707L,
  kappa = 1,
  gamma_init = gamma0,
  max_dense_dim = 20L
)
fit_b <- app_joint_qvp_fit_exal_mcmc_tiny(
  y = y,
  Z = Z,
  tau = tau,
  n_iter = 18L,
  burn = 9L,
  thin = 3L,
  seed = 707L,
  kappa = 1,
  gamma_init = gamma0,
  max_dense_dim = 20L
)

stopifnot(inherits(fit_a, "joint_qvp_qdesn_tiny_fit"))
stopifnot(identical(dim(fit_a$beta_draws), c(3L, 4L)))
stopifnot(identical(dim(fit_a$alpha_draws), c(3L, 2L)))
stopifnot(identical(dim(fit_a$sigma_draws), c(3L, 2L)))
stopifnot(identical(dim(fit_a$gamma_draws), c(3L, 2L)))
stopifnot(all(is.finite(fit_a$beta_draws)))
stopifnot(all(is.finite(fit_a$alpha_draws)))
stopifnot(all(is.finite(fit_a$sigma_draws)))
stopifnot(all(is.finite(fit_a$gamma_draws)))
stopifnot(all(fit_a$sigma_draws > 0))
stopifnot(all(apply(fit_a$alpha_draws, 1L, function(x) diff(x) >= -1.0e-12)))
stopifnot(all(fit_a$gamma_draws[, 1L] > support$lower[[1L]] & fit_a$gamma_draws[, 1L] < support$upper[[1L]]))
stopifnot(all(fit_a$gamma_draws[, 2L] > support$lower[[2L]] & fit_a$gamma_draws[, 2L] < support$upper[[2L]]))
stopifnot(identical(round(fit_a$beta_draws, 12), round(fit_b$beta_draws, 12)))
stopifnot(identical(round(fit_a$alpha_draws, 12), round(fit_b$alpha_draws, 12)))
stopifnot(identical(round(fit_a$sigma_draws, 12), round(fit_b$sigma_draws, 12)))
stopifnot(identical(round(fit_a$gamma_draws, 12), round(fit_b$gamma_draws, 12)))
stopifnot(identical(fit_a$manifest$status[[1L]], "prototype_success"))
stopifnot(identical(fit_a$manifest$likelihood[[1L]], "exal"))
stopifnot(identical(fit_a$manifest$inference[[1L]], "mcmc_tiny"))

kappa_half <- app_joint_qvp_fit_exal_mcmc_tiny(
  y = y,
  Z = Z,
  tau = tau,
  n_iter = 14L,
  burn = 7L,
  thin = 2L,
  seed = 708L,
  kappa = 0.5,
  gamma_init = gamma0,
  max_dense_dim = 20L
)
stopifnot(inherits(kappa_half, "joint_qvp_qdesn_tiny_fit"))
stopifnot(abs(kappa_half$manifest$kappa[[1L]] - 0.5) < 1.0e-12)
stopifnot(all(is.finite(kappa_half$gamma_draws)))
stopifnot(all(kappa_half$sigma_draws > 0))

bad_gamma <- try(app_joint_qvp_fit_exal_mcmc_tiny(
  y = y,
  Z = Z,
  tau = tau,
  n_iter = 10L,
  burn = 5L,
  gamma_init = c(support$lower[[1L]], gamma0[[2L]])
), silent = TRUE)
stopifnot(inherits(bad_gamma, "try-error"))
