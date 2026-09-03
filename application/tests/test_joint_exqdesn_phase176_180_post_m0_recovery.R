#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)

for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R", "joint_exqdesn_trace_tools.R",
  "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_qdesn_phase153_balanced_independent_replication.R",
  "joint_qdesn_phase154_mcmc_evidence_reconciliation.R",
  "joint_qdesn_phase155_article_promotion.R",
  "latent_path_design.R", "joint_exqdesn_phase151_feature_design_screening.R",
  "joint_exqdesn_exact_structured_inference.R",
  "joint_exqdesn_inference_dispatch.R",
  "joint_exqdesn_phase164_165_readiness.R",
  "joint_exqdesn_phase166_168_structured_vb.R",
  "joint_exqdesn_phase167_169_mcmc_method_selection.R",
  "joint_exqdesn_phase169r_recovery.R",
  "joint_exqdesn_phase170_default_promotion.R",
  "joint_exqdesn_phase171_175_article_confirmation.R",
  "joint_exqdesn_phase176_180_post_m0_recovery.R"
)) source(app_path("application/R", file))

stopifnot(
  identical(
    app_joint_exqdesn_phase176_required_case_ids(),
    c(
      "laplace_bridge__exqdesn_rhs_independent_vb",
      "normal_bridge__exqdesn_rhs_independent_vb",
      "persistent_heavy_tail__exqdesn_rhs_independent_vb",
      "regime_shift__exqdesn_rhs_independent_vb",
      "regime_shift__joint_exqdesn_rhs_vb"
    )
  )
)

make_moments <- function(offset) data.frame(
  row_index = rep(1:3, 2), quantile_index = rep(1:2, each = 3),
  tau = rep(c(0.1, 0.9), each = 3),
  posterior_mean = seq_len(6) / 10 + offset,
  posterior_sd = rep(0.2, 6),
  q05 = seq_len(6) / 10 + offset - 1.644854 * 0.2,
  q95 = seq_len(6) / 10 + offset + 1.644854 * 0.2,
  stringsAsFactors = FALSE
)
moments <- setNames(lapply(c(0, 0.01, 0.35, 0.37), make_moments), as.character(1:4))
pair <- app_joint_exqdesn_phase176_pairwise_qhat(
  moments, "test__joint", "forecast",
  data.frame(full_time_index = 1:3, horizon = 1:3)
)
stopifnot(
  nrow(pair$summary) == 6L,
  all(is.finite(pair$summary$rms_standardized_qhat_delta)),
  !any(c("y", "true_quantile", "truth_abs_error") %in% names(pair$summary))
)
assignment_a <- app_joint_exqdesn_phase176_cluster_assignments(
  pair$summary, "test__joint", cluster_counts = c(2L, 3L)
)
set.seed(176L)
assignment_b <- app_joint_exqdesn_phase176_cluster_assignments(
  pair$summary[sample(seq_len(nrow(pair$summary))), , drop = FALSE],
  "test__joint", cluster_counts = c(2L, 3L)
)
ord <- function(x) x[order(x$cluster_count, x$chain_id), c(
  "cluster_count", "chain_id", "cluster_id", "truth_used_for_clustering"
), drop = FALSE]
rownames(assignment_a) <- rownames(assignment_b) <- NULL
stopifnot(
  identical(ord(assignment_a), ord(assignment_b)),
  all(!assignment_a$truth_used_for_clustering)
)

fit <- list(
  beta_draws = matrix(1:24, 8, 3),
  alpha_draws = matrix(1:16, 8, 2),
  sigma_draws = matrix(seq(1, 2.5, length.out = 16), 8, 2),
  gamma_draws = matrix(seq(-0.2, 0.2, length.out = 16), 8, 2)
)
half <- app_joint_exqdesn_phase176_subset_fit(fit, 1:4)
stopifnot(
  nrow(half$beta_draws) == 4L,
  identical(half$beta_mean, colMeans(fit$beta_draws[1:4, , drop = FALSE])),
  all(half$sigma_mean > 0)
)

fallback <- data.frame(
  case_id = c("a", "b"), scenario_id = c("s1", "s2"),
  fit_structure = c("independent", "joint"),
  historical_forecast_truth_mae = c(0.10, 0.10),
  m0_forecast_truth_mae = c(0.09, 0.12),
  m0_forecast_truth_mae_jackknife_mcse = c(0.001, 0.001),
  stringsAsFactors = FALSE
)
pairwise <- data.frame(
  case_id = rep(c("a", "b"), each = 2), window = "forecast",
  q99_standardized_qhat_delta = c(0.4, 0.5, 0.7, 0.8),
  q01_central90_overlap_fraction = c(0.7, 0.7, 0.6, 0.6),
  stringsAsFactors = FALSE
)
drift <- data.frame(
  case_id = rep(c("a", "b"), each = 2), window = "forecast",
  q99_standardized_qhat_delta = c(0.3, 0.4, 1.2, 1.3),
  q01_central90_overlap_fraction = c(0.8, 0.8, 0.4, 0.4),
  stringsAsFactors = FALSE
)
cluster <- data.frame(
  case_id = rep(c("a", "b"), each = 2),
  sensitivity_role = "cluster_only",
  forecast_truth_mae = c(0.09, 0.095, 0.11, 0.13),
  stringsAsFactors = FALSE
)
classified <- app_joint_exqdesn_phase176_classify(
  fallback, pairwise, drift, cluster
)
stopifnot(
  classified$recovery_classification[[1L]] ==
    "same_spec_additional_chains_eligible",
  classified$recovery_classification[[2L]] ==
    "post_m0_spec_screen_required",
  all(!classified$pre_m0_screening_authoritative),
  all(classified$exact_m0_required_for_new_winner)
)

policy178 <- app_joint_exqdesn_phase178_load_compute_policy()
authority178 <- app_joint_exqdesn_phase178_load_authority()
neighborhood178 <- app_joint_exqdesn_phase178_load_neighborhood()
stopifnot(
  nrow(policy178) == 1L,
  nrow(authority178) >= 8L,
  nrow(neighborhood178) == 5L,
  !isTRUE(policy178$article_fixture_selection_allowed[[1L]]),
  isTRUE(policy178$exact_m0_required_for_rank[[1L]]),
  all(authority178$prior_stage != "phases_118_150" |
    authority178$authority_after_exact_m0 == "candidate_region_history_only")
)

template <- data.frame(
  phase178_template_id = "laplace_bridge__exqdesn_rhs_independent_vb__parity",
  case_id = "laplace_bridge__exqdesn_rhs_independent_vb",
  base_scenario_id = "laplace_bridge", fit_structure = "independent",
  variant_id = "parity", candidate_role = "exact_phase174_parity",
  design_role = "direct", design_class = "direct", tau0 = 0.5,
  zeta2 = 16, alpha_prior_sd = "1;1;1;1;1;1;1",
  tau_seed_stride = 1009L, exact_m0_rank_required = TRUE,
  article_fixture_selection_allowed = FALSE, stringsAsFactors = FALSE
)
dgp <- data.frame(
  scenario_id = paste0("laplace_bridge__phase178_m0_ranking_r", 1:3),
  base_scenario_id = "laplace_bridge", validation_partition = "m0_ranking",
  dgp_replicate_id = sprintf("m0_ranking_r%03d", 1:3), seed = 178011001:178011003,
  stringsAsFactors = FALSE
)
m0_plan_a <- app_joint_exqdesn_phase178_expand_m0_registry(
  template, dgp, policy178, "m0_ranking", 178500000L
)
m0_plan_b <- app_joint_exqdesn_phase178_expand_m0_registry(
  template, dgp, policy178, "m0_ranking", 178500000L
)
components <- app_joint_exqdesn_phase178_component_seed_plan(m0_plan_a)
stopifnot(
  identical(m0_plan_a, m0_plan_b),
  nrow(m0_plan_a) == 3L * policy178$m0_ranking_chains[[1L]],
  all(table(m0_plan_a$mcmc_case_id) == policy178$m0_ranking_chains[[1L]]),
  !anyDuplicated(m0_plan_a$chain_seed), !anyDuplicated(components$component_seed),
  nrow(components) == 7L * nrow(m0_plan_a),
  all(m0_plan_a$inference_method_id == "M0_v_collapsed_support_logit"),
  all(!app_as_bool_vec(m0_plan_a$article_fixture_selection_allowed))
)
stopifnot(
  identical(
    app_joint_exqdesn_phase178_candidate_design_id(data.frame(
      phase166_candidate_id = "vb_init", phase178_template_id = "template",
      candidate_id = "source", stringsAsFactors = FALSE
    )),
    "vb_init"
  ),
  identical(
    app_joint_exqdesn_phase178_candidate_design_id(data.frame(
      phase178_template_id = "template", candidate_id = "source",
      stringsAsFactors = FALSE
    )),
    "template"
  ),
  identical(
    app_joint_exqdesn_phase178_candidate_design_id(data.frame(
      candidate_id = "source", stringsAsFactors = FALSE
    )),
    "source"
  )
)

rank_summary <- do.call(rbind, lapply(1:3, function(rr) {
  rbind(
    data.frame(
      case_id = template$case_id, base_scenario_id = "laplace_bridge",
      fit_structure = "independent", phase178_template_id = template$phase178_template_id,
      variant_id = "parity", candidate_role = "exact_phase174_parity",
      design_role = "direct", tau0 = 0.5, alpha_prior_sd = template$alpha_prior_sd,
      dgp_replicate_id = sprintf("m0_ranking_r%03d", rr),
      implementation_status = "pass", forecast_truth_mae = 0.10,
      fit_truth_mae = 0.10, forecast_check_loss_mean = 0.10,
      forecast_crps_grid_mean = 0.20, max_forecast_partition_q99 = 0.4,
      min_forecast_partition_overlap = 0.8, scalar_mixing_status = "review",
      exact_m0_rank = TRUE, stringsAsFactors = FALSE
    ),
    data.frame(
      case_id = template$case_id, base_scenario_id = "laplace_bridge",
      fit_structure = "independent",
      phase178_template_id = paste0(template$case_id, "__tau0_lower"),
      variant_id = "tau0_lower", candidate_role = "post_m0_tau0_local",
      design_role = "direct", tau0 = 0.35, alpha_prior_sd = template$alpha_prior_sd,
      dgp_replicate_id = sprintf("m0_ranking_r%03d", rr),
      implementation_status = "pass", forecast_truth_mae = 0.09,
      fit_truth_mae = 0.10, forecast_check_loss_mean = 0.10,
      forecast_crps_grid_mean = 0.20, max_forecast_partition_q99 = 0.6,
      min_forecast_partition_overlap = 0.7, scalar_mixing_status = "review",
      exact_m0_rank = TRUE, stringsAsFactors = FALSE
    )
  )
}))
ranked <- app_joint_exqdesn_phase178_rank_m0_candidates(rank_summary, policy178)
stopifnot(
  nrow(ranked$decisions) == 1L,
  ranked$decisions$selected_variant_id[[1L]] == "tau0_lower",
  !ranked$decisions$selected_is_parity[[1L]],
  ranked$decisions$selected_scalar_mixing_review_fraction[[1L]] == 1
)

dirs <- app_joint_exqdesn_phase176_dirs()
if (file.exists(file.path(dirs$phase176, "artifact_manifest.csv"))) {
  verification <- app_joint_exqdesn_verify_manifest(dirs$phase176, "phase176")
  actual <- app_read_csv(file.path(dirs$phase176, "fallback_classification.csv"))
  stopifnot(
    all(verification$status == "pass"), nrow(actual) == 5L,
    setequal(actual$case_id, app_joint_exqdesn_phase176_required_case_ids()),
    all(!actual$pre_m0_screening_authoritative),
    all(actual$exact_m0_required_for_new_winner)
  )
}

cat("joint exQDESN Phase176-180 post-M0 recovery tests passed\n")
