args <- commandArgs(trailingOnly = TRUE)
library_path <- if (length(args)) args[[1L]] else {
  "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_libraries/exdqlm_pricefm_r75_large_n_gig_repair"
}

description <- utils::packageDescription("exdqlm", lib.loc = library_path)
namespace <- loadNamespace("exdqlm", lib.loc = library_path)
internal <- function(name) get(name, envir = namespace, inherits = FALSE)
stopifnot(
  identical(as.character(description$Version), "1.1.1.9002"),
  identical(as.character(description$Repository), "PriceFM-local"),
  identical(as.character(description[["Config/PriceFM/repair"]]),
            "scale-aware-SPD-plus-large-n-GIG")
)

n_large <- 100000
stats_large <- internal(".exal_sigmagam_stats")(
  sum_einv_quad = 0.5 * n_large,
  sum_t = 0,
  sum_v = 0.2 * n_large,
  sum_s_einv_t = 0,
  sum_s = 0.8 * n_large,
  sum_s2_einv = 1.2 * n_large,
  n = n_large,
  a_sigma = 1,
  b_sigma = 1
)
bounds <- c(internal("L.fn")(0.5), internal("U.fn")(0.5))
structured <- internal(".exal_sigmagam_structured_update")(
  stats = stats_large,
  p0 = 0.5,
  bounds = bounds,
  PriorSigma = list(a_sig = 1, b_sig = 1),
  log_prior_gamma = function(gamma) stats::dnorm(gamma, 0, sqrt(10), log = TRUE),
  grid_size = 21L,
  span_sd = 3
)
stopifnot(
  all(is.finite(c(
    structured$E.sigma, structured$E.inv.sigma, structured$E.gam,
    structured$entrop, structured$V.sigma
  ))),
  structured$E.sigma > 0,
  structured$E.inv.sigma > 0,
  structured$structured$grid_size >= 21L
)

set.seed(75)
n <- 2000L
X <- cbind(1, matrix(stats::rnorm(n * 5L), nrow = n))
y <- as.numeric(X %*% c(0.2, -0.1, 0.3, 0, 0.15, -0.2) + stats::rnorm(n, sd = 0.3))
sigmagam <- getExportedValue("exdqlm", "exal_make_vb_sigmagam_control")(
  factorization = "structured",
  structured_grid_size = 21L,
  structured_span_sd = 4,
  freeze_warmup_iters = 1L,
  force_after_warmup = TRUE,
  postwarmup_damping = 0.2,
  postwarmup_damping_iters = 2L,
  min_postwarmup_updates = 1L
)
control <- getExportedValue("exdqlm", "exal_make_vb_control")(
  max_iter = 6L, tol = 1e-4, n_samp_xi = 10L,
  verbose = FALSE, sigmagam = sigmagam
)
fit <- getExportedValue("exdqlm", "exalStaticLDVB")(
  y = y, X = X, p0 = 0.5,
  beta_prior = "rhs_ns",
  beta_prior_controls = list(
    tau0 = 0.001, init_tau = 1,
    freeze_tau_iters = 2L, freeze_tau_warmup_iters = 2L,
    shrink_intercept = FALSE
  ),
  init = list(beta = rep(0, ncol(X)), sigma = 0.3, gamma = 0),
  dqlm.ind = FALSE, n.samp = 5L,
  vb_control = control, verbose = FALSE
)
trace <- fit$diagnostics$vb_trace
stopifnot(
  all(is.finite(fit$qbeta$m)),
  is.finite(fit$qsiggam$sigma_mean), fit$qsiggam$sigma_mean > 0,
  is.finite(fit$qsiggam$gamma_mean),
  identical(fit$qsiggam$factorization, "structured_qgamma_qsigma_given_gamma"),
  fit$diagnostics$ld_block$sigmagam$update_count >= 1L,
  all(is.finite(trace$delta_s)),
  any(trace$delta_s > 0)
)
