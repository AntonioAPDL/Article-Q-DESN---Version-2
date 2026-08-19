#!/usr/bin/env Rscript

args <- commandArgs(FALSE)
file_arg <- grep("^--file=", args, value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))

expect_true <- function(x, message) {
  if (!isTRUE(x)) stop(message, call. = FALSE)
}
expect_equal <- function(x, y, tolerance = 1e-8, message = "Values differ.") {
  if (length(x) != length(y) || any(abs(x - y) > tolerance)) {
    stop(message, call. = FALSE)
  }
}

contract <- app_joint_qdesn_postscore_read_contract()
expect_equal(
  contract$tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95),
  message = "The frozen tau grid changed."
)
expect_equal(
  contract$weights_qs, c(0.025, 0.10, 0.20, 0.25, 0.20, 0.10, 0.025),
  message = "The frozen trapezoidal weights changed."
)
expect_equal(sum(contract$weights_qs), 0.90, message = "Weights were renormalized.")

formula_contract <- contract
formula_contract$monte_carlo_tolerance <- 0.025
formula <- app_joint_qdesn_postscore_formula_audit(
  formula_contract, mc_n = 60000L, seed = 1729001L
)
expect_true(all(formula$analytic_status == "pass"), "Analytic/numerical formula audit failed.")
expect_true(all(formula$monte_carlo_status == "pass"), "Analytic/Monte Carlo formula audit failed.")
oracle <- app_joint_qdesn_postscore_oracle_minimum_audit(contract)
expect_true(all(oracle$status == "pass"), "True quantiles did not minimize expected check loss.")

sc <- app_joint_qdesn_postscore_validation_scenarios()[1L, , drop = FALSE]
tau <- contract$tau
q_true <- matrix(
  rep(app_joint_qvp_registry_standardized_quantile(tau, sc), each = 20L),
  nrow = 20L, ncol = length(tau)
)
y <- seq(-1.5, 1.5, length.out = 20L)
oracle_score <- app_joint_qdesn_postscore_score_matrix(
  q_true, y, rep(0, 20L), rep(1, 20L), sc, tau, contract$weights_qs
)
shifted_score <- app_joint_qdesn_postscore_score_matrix(
  q_true + 0.2, y, rep(0, 20L), rep(1, 20L), sc, tau, contract$weights_qs
)
expect_true(
  shifted_score$dgp_integrated_acrps >= oracle_score$dgp_integrated_acrps,
  "Expected finite-grid regret became negative."
)

raw <- rbind(
  c(-1, -0.5, 0, 0.2, 0.1, 0.8, 1.2),
  c(-1, -0.8, -0.2, 0, 0.3, 0.7, 1.0)
)
monotone <- app_joint_qdesn_postscore_contract_rows(raw, tau)
expect_true(any(monotone$raw_crossing > 0), "Raw crossing fixture did not cross.")
expect_true(
  all(monotone$contract_crossing <= 1e-12),
  "Monotone draw contract retained a crossing."
)

selected <- app_joint_qdesn_postscore_even_indices(100L, 25L)
joint_index <- app_joint_qdesn_postscore_per_tau_indices(
  selected, length(tau), "joint", 100L, 1L
)
independent_a <- app_joint_qdesn_postscore_per_tau_indices(
  selected, length(tau), "independent", 100L, 1L
)
independent_b <- app_joint_qdesn_postscore_per_tau_indices(
  selected, length(tau), "independent", 101L, 1L
)
expect_true(all(vapply(joint_index, identical, logical(1L), selected)),
            "Joint coupling did not preserve draw identity.")
expect_true(identical(
  independent_a,
  app_joint_qdesn_postscore_per_tau_indices(
    selected, length(tau), "independent", 100L, 1L
  )
), "Independent coupling is not deterministic.")
expect_true(!identical(independent_a, independent_b),
            "Independent coupling seed has no effect.")
expect_true(all(vapply(independent_a, function(x) {
  identical(sort(x), sort(selected))
}, logical(1L))), "Independent product coupling is not draw-balanced.")

set.seed(3201)
n_keep <- 80L; p <- 2L; n_time <- 18L; K <- length(tau)
fit <- list(
  beta_draws = matrix(rnorm(n_keep * K * p, sd = 0.03), nrow = n_keep),
  alpha_draws = matrix(
    rep(stats::qnorm(tau), each = n_keep) + rnorm(n_keep * K, sd = 0.02),
    nrow = n_keep, ncol = K
  )
)
forecast <- list(Z = cbind(seq(-1, 1, length.out = n_time), sin(seq_len(n_time))))
chain_draws <- app_joint_qdesn_postscore_chain_draws(
  fit, forecast, y = rnorm(n_time), mu = rep(0, n_time), sigma = rep(1, n_time),
  sc = sc, tau = tau, weights = contract$weights_qs,
  fit_structure = "joint", chain_id = 1L, pairing_seed = 400L,
  draws_per_chain = 50L, chunk_size = 13L,
  oracle_score = oracle_score$dgp_integrated_acrps
)
expect_true(nrow(chain_draws) == 50L, "Chunked score reconstruction lost draws.")
expect_true(all(is.finite(chain_draws$dgp_integrated_acrps)), "Draw scores are nonfinite.")
expect_true(all(chain_draws$contract_crossing_pairs == 0L), "Contract draw scores cross.")

left <- do.call(rbind, lapply(1:4, function(chain) {
  data.frame(chain_id = chain, dgp_integrated_acrps = 0.30 + rnorm(60, sd = 0.01))
}))
right <- do.call(rbind, lapply(1:4, function(chain) {
  data.frame(chain_id = chain, dgp_integrated_acrps = 0.31 + rnorm(60, sd = 0.01))
}))
paired_a <- app_joint_qdesn_postscore_pair_scalar_draws(
  left, right, 500L, "left", "right"
)
paired_b <- app_joint_qdesn_postscore_pair_scalar_draws(
  left, right, 500L, "left", "right"
)
expect_true(identical(paired_a, paired_b), "Contrast pairing is not deterministic.")
expect_true(mean(paired_a$score_delta) < 0, "Synthetic contrast direction is wrong.")

aggregate_fixture <- data.frame(
  case_id = "case", base_scenario_id = "base", fit_structure = "joint",
  phase178_template_id = c("parity", "better", "near_tie"),
  variant_id = c("parity", "better", "near_tie"), protected_replicates = 3L,
  median_posterior_score_mean = c(0.30, 0.29, 0.2995),
  median_canonical_action_score = c(0.30, 0.29, 0.2995),
  median_expected_regret = 0.10, median_forecast_truth_mae = c(0.10, 0.101, 0.10),
  median_fit_truth_mae = c(0.10, 0.101, 0.10), median_realized_acrps = 0.30,
  maximum_score_rank_rhat = 1.01, minimum_score_bulk_ess = 500,
  minimum_score_tail_ess = 300, maximum_raw_crossing_rate = 0,
  all_contract_crossings_zero = TRUE, score_functional_pass_fraction = 1,
  coherence_pass_fraction = 1, pairing_pass_fraction = 1,
  parity_median_posterior_score_mean = 0.30,
  parity_median_forecast_truth_mae = 0.10, parity_median_fit_truth_mae = 0.10,
  score_ratio_vs_parity = c(1, 0.29 / 0.30, 0.2995 / 0.30),
  forecast_truth_mae_ratio_vs_parity = c(1, 1.01, 1),
  fit_truth_mae_ratio_vs_parity = c(1, 1.01, 1), stringsAsFactors = FALSE
)
contrast_fixture <- do.call(rbind, lapply(c("better", "near_tie"), function(id) {
  superior <- id == "better"
  data.frame(
    case_id = "case", base_scenario_id = "base", fit_structure = "joint",
    dgp_replicate_id = paste0("r", 1:3), candidate_template_id = id,
    candidate_variant_id = id, parity_template_id = "parity", n_draws = 100,
    score_delta_mean = if (superior) -0.01 else -0.0005,
    score_delta_median = 0, score_delta_q025 = -0.02, score_delta_q975 = 0.01,
    relative_score_delta_mean = if (superior) -0.033 else -0.0017,
    probability_lower_score = if (superior) 0.99 else 0.60,
    probability_practical_superiority = if (superior) 0.98 else 0.30,
    probability_noninferior = 0.99, stringsAsFactors = FALSE
  )
}))
decision_fixture <- app_joint_qdesn_postscore_decisions(
  aggregate_fixture, contrast_fixture, contract
)$decisions
expect_true(
  decision_fixture$selected_template_id[[1L]] == "better",
  "Predeclared superiority rule did not select the supported challenger."
)

tmp <- tempfile("postscore_cell_")
meta <- data.frame(
  mcmc_case_id = "toy", phase178_template_id = "toy_parity", case_id = "toy_case",
  scenario_id = "toy_scenario", base_scenario_id = "toy", dgp_replicate_id = "r001",
  validation_partition = "m0_ranking", fit_structure = "joint", variant_id = "parity",
  candidate_role = "parity", design_role = "parity", distribution_family = "gaussian",
  dynamics_class = "toy", stringsAsFactors = FALSE
)
toy_draws <- cbind(meta[rep(1L, 4L), , drop = FALSE], data.frame(
  chain_id = rep(1:2, each = 2), score_draw_index_within_chain = rep(1:2, 2),
  anchor_source_draw_index = rep(1:2, 2), pairing_seed = 1L,
  dgp_integrated_acrps_raw = 0.3, dgp_integrated_acrps = 0.3,
  expected_oracle_acrps = 0.2, expected_regret = 0.1,
  realized_acrps_raw = 0.31, realized_acrps = 0.31,
  raw_crossing_pairs = 0L, contract_crossing_pairs = 0L,
  max_raw_crossing_magnitude = 0, mean_abs_adjustment_over_sigma = 0,
  max_abs_adjustment = 0
))
toy <- list(
  draws = toy_draws,
  diagnostics = cbind(meta, data.frame(status = "pass")),
  canonical = cbind(meta, data.frame(score = 0.3)),
  canonical_tau = cbind(meta[rep(1L, K), , drop = FALSE], data.frame(tau = tau)),
  allocation = cbind(meta, data.frame(allocation_id = "all")),
  pairing_sensitivity = cbind(meta, data.frame(pairing_seed = 1L)),
  source = cbind(meta, data.frame(worker_id = 1L)),
  previsibility = cbind(meta, data.frame(status = "pass"))
)
app_joint_qdesn_postscore_write_cell(toy, tmp)
expect_true(app_joint_qdesn_postscore_cell_complete(tmp), "Cell manifest did not verify.")
toy_read <- app_joint_qdesn_postscore_read_cell(tmp)
expect_true(nrow(toy_read$draws) == nrow(toy_draws), "Compressed draw checkpoint changed rows.")
unlink(tmp, recursive = TRUE, force = TRUE)

cat("post-Phase178 DGP-integrated aCRPS tests passed\n")
