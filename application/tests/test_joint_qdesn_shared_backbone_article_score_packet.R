#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "..", "scripts", "_joint_qdesn_shared_backbone_article_confirmation_bootstrap.R"))

expect_true <- function(x, msg) {
  if (!isTRUE(x)) stop(msg, call. = FALSE)
}

expect_equal <- function(x, y, msg, tolerance = 1e-12) {
  if (!isTRUE(all.equal(x, y, tolerance = tolerance))) stop(msg, call. = FALSE)
}

contract <- app_joint_article_score_read_contract()
expect_equal(contract$tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95),
             "Jerez score tau grid changed.")
expect_equal(contract$weights_qs,
             c(0.025, 0.100, 0.200, 0.250, 0.200, 0.100, 0.025),
             "Jerez score quadrature weights changed.")
expect_equal(sum(contract$weights_qs), 0.90,
             "Jerez score weights were renormalized.")
expect_true(contract$score_draws_per_chain == 750L &&
              contract$sensitivity_draws_per_chain == 250L,
            "Jerez score draw counts changed.")
expect_true(contract$expected_model_cells == 32L &&
              contract$expected_contrasts == 16L,
            "Jerez score packet cardinalities changed.")

set.seed(20260908)
K <- length(contract$tau)
p <- 3L
n <- 28L
draws_n <- 16L
fit <- list(
  beta_draws = matrix(rnorm(draws_n * K * p), draws_n, K * p),
  alpha_draws = matrix(rnorm(draws_n * K), draws_n, K),
  sigma_draws = matrix(rexp(draws_n * K) + 0.2, draws_n, K),
  gamma_draws = matrix(rnorm(draws_n * K, sd = 0.1), draws_n, K)
)
frame <- app_joint_article_draw_frame(fit)
drop_names <- function(x) {
  dimnames(x) <- NULL
  x
}
expect_equal(drop_names(app_joint_article_score_select_block(frame, "beta")),
             fit$beta_draws,
             "Flattened beta reconstruction changed.")
expect_equal(drop_names(app_joint_article_score_select_block(frame, "alpha")),
             fit$alpha_draws,
             "Flattened alpha reconstruction changed.")
expect_equal(drop_names(app_joint_article_score_select_block(frame, "sigma")),
             fit$sigma_draws,
             "Flattened sigma reconstruction changed.")
expect_equal(drop_names(app_joint_article_score_select_block(frame, "gamma")),
             fit$gamma_draws,
             "Flattened gamma reconstruction changed.")

selected <- app_joint_qdesn_postscore_even_indices(100L, 10L)
expect_true(length(selected) == 10L && all(diff(selected) > 0L),
            "Even retained-draw selection is malformed.")
joint_idx <- app_joint_qdesn_postscore_per_tau_indices(
  selected, K, "joint", contract$primary_pairing_seed, 1L
)
ind_idx_1 <- app_joint_qdesn_postscore_per_tau_indices(
  selected, K, "independent", contract$primary_pairing_seed, 1L
)
ind_idx_2 <- app_joint_qdesn_postscore_per_tau_indices(
  selected, K, "independent", contract$primary_pairing_seed, 1L
)
ind_idx_3 <- app_joint_qdesn_postscore_per_tau_indices(
  selected, K, "independent", contract$sensitivity_pairing_seeds[[1L]], 1L
)
expect_true(all(vapply(joint_idx, identical, logical(1L), selected)),
            "Joint coupling did not preserve retained draw identity.")
expect_true(identical(ind_idx_1, ind_idx_2) && !identical(ind_idx_1, ind_idx_3),
            "Independent coupling is not deterministic and seed-sensitive.")

Z <- matrix(rnorm(n * p), n, p)
fitted <- list(
  beta_draws = fit$beta_draws,
  alpha_draws = fit$alpha_draws,
  sigma_draws = fit$sigma_draws,
  gamma_draws = fit$gamma_draws,
  beta_mean = colMeans(fit$beta_draws),
  alpha_mean = colMeans(fit$alpha_draws),
  sigma_mean = colMeans(fit$sigma_draws),
  gamma_mean = colMeans(fit$gamma_draws),
  tau = contract$tau
)
independent_fit <- app_joint_article_score_complete_fit(
  fitted, "independent", contract$tau, p
)
qhat_full <- app_joint_qdesn_predict_fit(fitted, Z, contract$tau)
qhat_ind <- app_joint_qdesn_predict_fit(independent_fit, Z, contract$tau)
expect_equal(qhat_full, qhat_ind,
             "Independent fit completion changed qhat predictions.")

sc <- data.frame(
  distribution_family = "gaussian", df = NA_real_, al_tau = NA_real_,
  mixture_weight = NA_real_, mixture_mean_1 = NA_real_,
  mixture_sd_1 = NA_real_, mixture_mean_2 = NA_real_,
  mixture_sd_2 = NA_real_, dynamics_class = "test",
  stringsAsFactors = FALSE
)
context <- list(
  y = rnorm(n), Z = Z, true_q = qhat_full + 0.01,
  mu = rep(0, n), sigma = rep(1, n), sc = sc
)
meta <- data.frame(
  mcmc_case_id = "test__joint_qdesn_rhs",
  phase178_template_id = "test", case_id = "test__joint_qdesn_rhs",
  scenario_id = "test", base_scenario_id = "test",
  dgp_replicate_id = "article_fixture",
  validation_partition = "article_evaluation",
  fit_structure = "joint", variant_id = "AL",
  candidate_role = "test", design_role = "test",
  distribution_family = "gaussian", dynamics_class = "test",
  source_model_id = "joint_qdesn_rhs_vb",
  model_id = "joint_qdesn_rhs_mcmc",
  display_label = "Joint QDESN, AL, RHS",
  likelihood_family = "AL", article_seed = 1L,
  selected_candidate_id = "test", design_fingerprint = "test",
  stringsAsFactors = FALSE
)
metric <- app_joint_article_score_window_metrics(
  meta, qhat_full, context, contract$tau, contract$weights_qs, "forecast"
)
expect_true(nrow(metric) == 1L &&
              is.finite(metric$dgp_integrated_acrps[[1L]]) &&
              metric$contract_crossing_pairs[[1L]] == 0L,
            "Canonical action score metric failed.")

formula <- app_joint_article_score_formula_quadrature_audit(contract)
expect_true(nrow(formula) > length(contract$tau) &&
              all(formula$status != "fail") &&
              abs(sum(contract$weights_qs) - 0.90) < 1e-12,
            "Formula or quadrature audit failed.")

contrast_probe <- app_joint_qdesn_bind_rows(lapply(seq_len(8L), function(ii) {
  app_joint_qdesn_bind_rows(lapply(c("AL", "exAL"), function(variant) {
    app_joint_qdesn_bind_rows(lapply(c("joint", "independent"), function(structure) {
      app_joint_qdesn_bind_rows(lapply(seq_len(2L), function(chain_id) {
        data.frame(
          mcmc_case_id = paste(ii, variant, structure, sep = "_"),
          phase178_template_id = "test",
          case_id = paste(ii, variant, structure, sep = "_"),
          scenario_id = sprintf("scenario_%02d", ii),
          base_scenario_id = sprintf("scenario_%02d", ii),
          dgp_replicate_id = "article_fixture",
          validation_partition = "article_evaluation",
          fit_structure = structure, variant_id = variant,
          candidate_role = "test", design_role = "test",
          distribution_family = "gaussian", dynamics_class = "test",
          chain_id = chain_id,
          dgp_integrated_acrps = seq_len(5L) / 10 +
            if (structure == "joint") 0 else 0.01,
          stringsAsFactors = FALSE
        )
      }))
    }))
  }))
}))
contrast <- app_joint_qdesn_postscore_joint_independent_contrasts(
  contrast_probe, contract
)
expect_true(nrow(contrast$summary) == 16L &&
              all(contrast$summary$score_delta_mean < 0),
            "Joint-independent contrast helper cardinality changed.")

runtime <- app_joint_article_default_root()
if (dir.exists(runtime)) {
  reaudit <- app_joint_article_score_reaudit(runtime, contract)
  expect_true(nrow(reaudit) == 10L && all(reaudit$status == "pass"),
              "Runtime closeout re-audit failed.")
}

if (dir.exists(runtime) &&
    file.exists(file.path(runtime, "score_packet", "packet_health_summary.csv"))) {
  packet <- file.path(runtime, "score_packet")
  health <- app_read_csv(file.path(packet, "packet_health_summary.csv"))
  summary <- app_read_csv(file.path(packet, "posterior_dgp_integrated_acrps_summary.csv"))
  contrast_summary <- app_read_csv(file.path(packet, "joint_independent_contrast_summary.csv"))
  winners <- app_read_csv(file.path(packet, "scenario_winner_summary.csv"))
  manifest <- app_joint_shared_verify_manifest(packet, file.path(packet, "artifact_manifest.csv"))
  expect_true(
    health$status[[1L]] == "READY_FOR_MUSCAT_TRANSFER_AND_INTEGRATION_REVIEW" &&
      nrow(summary) == 32L &&
      nrow(contrast_summary) == 16L &&
      nrow(winners) == 8L &&
      all(summary$contract_crossing_pairs == 0L) &&
      all(is.finite(summary$posterior_score_mean)) &&
      all(manifest$verified),
    "Built Jerez score packet failed cardinality, finite, crossing, or manifest checks."
  )
}

cat("JOINT shared-backbone article score-packet tests passed\n")
