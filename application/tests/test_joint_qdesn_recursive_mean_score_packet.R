#!/usr/bin/env Rscript

if (!exists("app_joint_recursive_read_contract", mode = "function")) {
  file_arg <- sub("^--file=", "", commandArgs(FALSE)[grep(
    "^--file=", commandArgs(FALSE))])
  source(file.path(dirname(file_arg), "..", "scripts",
    "_joint_qdesn_recursive_mean_forecast_bootstrap.R"))
}

contract <- app_joint_recursive_read_contract()
stopifnot(
  contract$workers == 8L,
  contract$score_rows == 990L,
  identical(contract$tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)),
  identical(contract$weights, c(0.025, 0.100, 0.200, 0.250, 0.200, 0.100, 0.025))
)

mean <- c(-0.5, 0.3, 1.2)
covariance <- matrix(c(1, .2, 0, .2, .5, .1, 0, .1, .8), 3L)
draws <- app_joint_recursive_mvn_draws(mean, covariance, 50000L, 712L)
stopifnot(
  max(abs(colMeans(draws) - mean)) < 0.02,
  max(abs(stats::cov(draws) - covariance)) < 0.03,
  attr(draws, "covariance_repair")$material_negative[[1L]] == FALSE
)

beta <- matrix(seq_len(120), nrow = 20L, ncol = 6L)
alpha <- matrix(seq_len(60), nrow = 20L, ncol = 3L)
coupled_a <- app_joint_recursive_couple_independent(beta, alpha, 2L, 101L)
coupled_b <- app_joint_recursive_couple_independent(beta, alpha, 2L, 101L)
stopifnot(
  identical(coupled_a, coupled_b),
  !identical(coupled_a$beta, beta),
  identical(dim(coupled_a$beta), dim(beta))
)

set.seed(77L)
truth <- matrix(stats::rnorm(800L * 4L), nrow = 800L, ncol = 4L)
sorted_truth <- apply(truth, 2L, sort)
toy_oracle <- list(
  sorted_response = sorted_truth,
  prefix_response = apply(sorted_truth, 2L, cumsum),
  observed_y = truth[1L, ],
  true_q = t(apply(truth, 2L, stats::quantile,
    probs = contract$tau, names = FALSE, type = 8))
)
toy_design <- cbind(1, seq(-1, 1, length.out = 4L))
toy_beta <- matrix(0, nrow = 12L, ncol = 14L)
toy_alpha <- matrix(rep(stats::qnorm(contract$tau), each = 12L), nrow = 12L)
toy_scores <- app_joint_recursive_score_draws(
  toy_design, toy_beta, toy_alpha, toy_oracle,
  contract$tau, contract$weights, chunk_size = 5L
)
stopifnot(
  nrow(toy_scores) == 12L,
  all(is.finite(toy_scores$origin_marginal_dgp_integrated_acrps)),
  all(toy_scores$contract_crossing_pairs == 0L)
)

source_candidates <- c(
  Sys.getenv("JOINT_RECURSIVE_SOURCE_ROOT", unset = ""),
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_corrected_article_comparison_muscat_11core_20260909/application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909",
  app_joint_recursive_default_source()
)
source_root <- source_candidates[dir.exists(source_candidates)][1L]
if (length(source_root) && !is.na(source_root)) {
  plans <- app_joint_recursive_build_plans(source_root, contract)
  stopifnot(
    nrow(plans$cells) == 64L,
    sum(plans$cells$inference_method == "vb") == 32L,
    sum(plans$cells$inference_method == "mcmc") == 32L,
    nrow(plans$oracle) == 32L,
    sum(app_as_bool_vec(plans$oracle$is_primary)) == 16L,
    sum(app_as_bool_vec(plans$cells$sentinel)) == 3L
  )
  independent <- plans$cells[
    plans$cells$fit_structure == "independent" &
      plans$cells$inference_method == "vb", , drop = FALSE][1L, ]
  vb <- app_joint_recursive_vb_draws(source_root, independent, 100L, 991L)
  stopifnot(
    nrow(vb$beta) == 100L,
    nrow(vb$covariance_repair) == length(contract$tau),
    !vb$alpha_uncertainty_included
  )
}

cat("test_joint_qdesn_recursive_mean_score_packet: PASS\n")
