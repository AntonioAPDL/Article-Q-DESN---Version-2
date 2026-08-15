repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_exqdesn_trace_tools.R"))
source(app_path("application/R/joint_exqdesn_phase156_collapsed_gamma_sigma.R"))

set.seed(156L)
n <- 12L
y <- stats::rnorm(n)
fitted <- seq(-0.15, 0.15, length.out = n)
alpha <- -0.1
s <- abs(stats::rnorm(n)) + 0.05
v <- abs(stats::rnorm(n)) + 0.05
tau <- 0.1
gamma <- 0
a_sigma <- 2
b_sigma <- 1

terms <- app_joint_qvp_exal_sigma_gig_terms(
  gamma, y, fitted, alpha, s, v, tau, 1, a_sigma, b_sigma
)
stopifnot(!is.null(terms), terms$chi > 0, terms$psi > 0)
sufficient <- app_joint_qvp_exal_collapsed_sufficient_stats(y, fitted, alpha, s, v)
terms_fast <- app_joint_qvp_exal_sigma_gig_terms(
  gamma, y, fitted, alpha, s, v, tau, 1, a_sigma, b_sigma,
  sufficient_stats = sufficient
)
stopifnot(max(abs(unlist(terms[c("lambda", "chi", "psi", "log_Bv_sum", "lambda_s_centered_over_Bv_sum")]) -
                      unlist(terms_fast[c("lambda", "chi", "psi", "log_Bv_sum", "lambda_s_centered_over_Bv_sum")]))) < 1.0e-10)

# The direct joint kernel and its GIG decomposition may differ only by a
# gamma-independent normalization constant at fixed gamma.
sigmas <- exp(seq(log(0.05), log(3), length.out = 9L))
direct <- vapply(sigmas, function(sig) {
  app_joint_qvp_exal_sigma_gamma_log_kernel(
    sig, gamma, y, fitted, alpha, s, v, tau, 1,
    a_sigma = a_sigma, b_sigma = b_sigma
  )
}, numeric(1L))
gig_part <- (terms$lambda - 1) * log(sigmas) -
  0.5 * (terms$chi / sigmas + terms$psi * sigmas)
stopifnot(max(abs((direct - gig_part) - (direct[[1L]] - gig_part[[1L]]))) < 1.0e-9)

collapsed <- app_joint_qvp_exal_gamma_collapsed_log_kernel(
  gamma, y, fitted, alpha, s, v, tau, 1,
  a_sigma = a_sigma, b_sigma = b_sigma
)
stopifnot(is.finite(collapsed))
collapsed_fast <- app_joint_qvp_exal_gamma_collapsed_log_kernel(
  gamma, y, fitted, alpha, s, v, tau, 1,
  a_sigma = a_sigma, b_sigma = b_sigma,
  sufficient_stats = sufficient
)
stopifnot(abs(collapsed - collapsed_fast) < 1.0e-10)

support <- app_joint_qvp_exal_support(tau)
grid <- seq(support$lower[[1L]] + 0.01, support$upper[[1L]] - 0.01, length.out = 31L)
grid_log <- vapply(grid, function(g) {
  app_joint_qvp_exal_gamma_collapsed_log_kernel(
    g, y, fitted, alpha, s, v, tau, 1,
    a_sigma = a_sigma, b_sigma = b_sigma
  )
}, numeric(1L))
stopifnot(all(is.finite(grid_log)))

draw_a <- local({
  set.seed(157L)
  app_joint_qvp_exal_sigma_gamma_collapsed_draw(
    sigma = 0.5, gamma = gamma, y = y, fitted_no_alpha = fitted,
    alpha = alpha, s = s, v = v, tau = tau, kappa = 1,
    gamma_slice_width = 2, gamma_slice_max_steps = 80L,
    a_sigma = a_sigma, b_sigma = b_sigma
  )
})
draw_b <- local({
  set.seed(157L)
  app_joint_qvp_exal_sigma_gamma_collapsed_draw(
    sigma = 0.5, gamma = gamma, y = y, fitted_no_alpha = fitted,
    alpha = alpha, s = s, v = v, tau = tau, kappa = 1,
    gamma_slice_width = 2, gamma_slice_max_steps = 80L,
    a_sigma = a_sigma, b_sigma = b_sigma
  )
})
stopifnot(is.finite(draw_a$sigma), draw_a$sigma > 0)
stopifnot(draw_a$gamma > support$lower[[1L]], draw_a$gamma < support$upper[[1L]])
stopifnot(draw_a$density_evaluations > 0L)
stopifnot(identical(draw_a, draw_b))

stable <- cbind(
  stats::rnorm(400), stats::rnorm(400), stats::rnorm(400), stats::rnorm(400)
)
shifted <- stable
shifted[, 4L] <- shifted[, 4L] + 2.5
stable_diag <- app_joint_exqdesn_modern_diagnostics(stable)
shifted_diag <- app_joint_exqdesn_modern_diagnostics(shifted)
stopifnot(all(is.finite(unlist(stable_diag[c("rank_rhat", "folded_rhat", "bulk_ess", "tail_ess", "mcse_mean")], use.names = FALSE))))
stopifnot(stable_diag$rank_rhat < 1.1)
stopifnot(shifted_diag$rank_rhat > stable_diag$rank_rhat)

hist <- app_joint_exqdesn_rank_histogram(stable, n_bins = 10L)
stopifnot(nrow(hist) == 40L)
stopifnot(all(stats::aggregate(hist$count, list(hist$chain_id), sum)$x == 400L))

fake_fit <- list(
  beta_mean = seq(-0.2, 0.2, length.out = 6L),
  alpha_mean = c(-0.5, 0, 0.5),
  sigma_mean = c(0.3, 0.4, 0.5),
  gamma_mean = c(0, 0, 0)
)
init_rows <- app_joint_exqdesn_phase156_init_rows(fake_fit, "test_case")
round_trip <- app_joint_exqdesn_phase156_init_from_rows(init_rows, "test_case")
stopifnot(identical(round_trip$beta_mean, fake_fit$beta_mean))
stopifnot(identical(round_trip$alpha_mean, fake_fit$alpha_mean))
stopifnot(identical(round_trip$sigma_mean, fake_fit$sigma_mean))
stopifnot(identical(round_trip$gamma_mean, fake_fit$gamma_mean))

# Preserve the four posterior blocks without relying on data.frame/cbind
# argument dispatch. This is the exact lifecycle boundary that failed in the
# first Phase157 launch after all MCMC iterations had completed.
fake_draw_fit <- list(
  beta_draws = matrix(seq_len(24L) / 100, nrow = 4L, ncol = 6L),
  alpha_draws = matrix(seq_len(12L) / 10, nrow = 4L, ncol = 3L),
  sigma_draws = matrix(seq_len(12L) / 20 + 0.1, nrow = 4L, ncol = 3L),
  gamma_draws = matrix(seq_len(12L) / 50 - 0.1, nrow = 4L, ncol = 3L)
)
draw_frame <- app_joint_exqdesn_phase157_draw_frame(fake_draw_fit)
stopifnot(nrow(draw_frame) == 4L, ncol(draw_frame) == 16L)
stopifnot(identical(names(draw_frame), c(
  "draw_index", sprintf("beta_%04d", 1:6), sprintf("alpha_%02d", 1:3),
  sprintf("sigma_%02d", 1:3), sprintf("gamma_%02d", 1:3)
)))
bad_draw_fit <- fake_draw_fit
bad_draw_fit$gamma_draws <- bad_draw_fit$gamma_draws[-1L, , drop = FALSE]
draw_error <- tryCatch(
  {
    app_joint_exqdesn_phase157_draw_frame(bad_draw_fit)
    NULL
  },
  error = identity
)
stopifnot(inherits(draw_error, "error"))

starts <- app_joint_exqdesn_phase156_chain_starts(fake_fit, c(0.1, 0.5, 0.9), "test_case", 8L)
stopifnot(nrow(starts) == 8L * 3L * 2L)
stopifnot(all(is.finite(starts$value)))
stopifnot(all(starts$value[starts$parameter == "sigma"] > 0))
for (kk in 1:3) {
  bounds <- app_joint_qvp_exal_support(c(0.1, 0.5, 0.9))
  g <- starts$value[starts$parameter == "gamma" & starts$quantile_index == kk]
  stopifnot(all(g > bounds$lower[[kk]]), all(g < bounds$upper[[kk]]))
}

tmp <- tempfile("phase157-gzip-")
dir.create(tmp)
draw_path <- app_joint_exqdesn_phase157_write_gzip_csv(
  data.frame(draw_index = 1:3, beta_0001 = c(0.1, 0.2, 0.3)),
  file.path(tmp, "posterior_draws.csv.gz")
)
draw_check <- app_joint_exqdesn_phase156_read_csv(draw_path)
stopifnot(identical(draw_check$draw_index, 1:3))
stopifnot(max(abs(draw_check$beta_0001 - c(0.1, 0.2, 0.3))) < 1.0e-12)
draw_path_2 <- app_joint_exqdesn_phase157_write_gzip_csv(
  data.frame(draw_index = 1:3, beta_0001 = c(0.1, 0.2, 0.3)),
  file.path(tmp, "posterior_draws_repeat.csv.gz")
)
stopifnot(identical(
  app_joint_exqdesn_phase157b_canonical_draw_hash(draw_path),
  app_joint_exqdesn_phase157b_canonical_draw_hash(draw_path_2)
))
unlink(tmp, recursive = TRUE)

receipt_root <- tempfile("phase157-failure-receipt-")
receipt_freeze <- file.path(receipt_root, "freeze")
receipt_worker <- file.path(receipt_root, "worker")
receipt_external <- file.path(receipt_root, "orchestration", "failures")
dir.create(receipt_freeze, recursive = TRUE)
utils::write.csv(data.frame(
  worker_id = 3L,
  scenario_id = "test_case",
  chain_id = 2L,
  chain_seed = 991L,
  worker_output_dir = receipt_worker,
  stringsAsFactors = FALSE
), file.path(receipt_freeze, "chain_plan.csv"), row.names = FALSE)
receipt <- app_joint_exqdesn_phase157_failure_receipt(
  receipt_freeze, 3L, "draw_frame", simpleError("synthetic serialization failure"), receipt_external
)
stopifnot(nrow(receipt$receipt) == 1L)
stopifnot(receipt$receipt$stage[[1L]] == "draw_frame")
stopifnot(receipt$receipt$message[[1L]] == "synthetic serialization failure")
stopifnot(file.exists(file.path(receipt_worker, "failure_receipt.csv")))
stopifnot(file.exists(file.path(receipt_external, "worker_003.csv")))
unlink(receipt_root, recursive = TRUE)

snapshot_dir <- tempfile("phase156-snapshot-")
dir.create(snapshot_dir)
snapshot <- app_joint_exqdesn_phase156_attach_code_snapshot(snapshot_dir, repo_root)
stopifnot(nrow(snapshot$snapshot) == 14L)
stopifnot(all(nchar(snapshot$snapshot$sha256) == 64L))
stopifnot(file.exists(snapshot$snapshot_path), file.exists(snapshot$manifest_path))
unlink(snapshot_dir, recursive = TRUE)
