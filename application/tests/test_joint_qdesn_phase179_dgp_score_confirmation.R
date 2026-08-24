#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))

expect_true <- function(x, message) {
  if (!isTRUE(x)) stop(message, call. = FALSE)
}

policy <- app_joint_qdesn_phase179_read_policy()
expect_true(policy$expected_target_cells == 5L, "Target-cell policy changed.")
expect_true(policy$expected_confirmation_templates == 8L, "Template count changed.")
expect_true(policy$expected_confirmation_workers == 384L, "Worker count changed.")
expect_true(policy$relative_gain_floor == 0, "Any-gain threshold is not zero.")
expect_true(!policy$global_specification_selected, "Policy selected a universal specification.")

cases <- app_joint_qdesn_phase179_required_cases()
winner_variant <- c("parity", "tau0_upper", "parity", "tau0_lower", "tau0_lower")
aggregate <- app_joint_qdesn_bind_rows(lapply(seq_along(cases), function(ii) {
  variants <- c("parity", "tau0_lower", "tau0_upper")
  scores <- c(0.30, 0.301, 0.302)
  if (winner_variant[[ii]] == "tau0_lower") scores <- c(0.30, 0.2999, 0.301)
  if (winner_variant[[ii]] == "tau0_upper") scores <- c(0.30, 0.301, 0.2998)
  data.frame(
    case_id = cases[[ii]], base_scenario_id = sub("__.*", "", cases[[ii]]),
    fit_structure = if (grepl("joint_exqdesn", cases[[ii]])) "joint" else "independent",
    phase178_template_id = paste(cases[[ii]], variants, sep = "__"),
    variant_id = variants, median_posterior_score_mean = scores,
    score_ratio_vs_parity = scores / scores[[1L]],
    median_forecast_truth_mae = 0.10,
    forecast_truth_mae_ratio_vs_parity = 1,
    median_fit_truth_mae = 0.10, fit_truth_mae_ratio_vs_parity = 1,
    all_contract_crossings_zero = TRUE, stringsAsFactors = FALSE
  )
}))
controls <- aggregate[, c(
  "case_id", "base_scenario_id", "fit_structure", "phase178_template_id", "variant_id"
), drop = FALSE]
controls$tau0 <- rep(c(0.5, 0.25, 0.75), length(cases))
controls$zeta2 <- rep(seq_along(cases), each = 3L)
controls$alpha_prior_sd <- "1"
controls$source_control_row_sha256 <- sprintf("hash_%02d", seq_len(nrow(controls)))
controls$source_candidate_id <- paste0("source_", seq_len(nrow(controls)))
controls$design_role <- "direct"
controls$design_class <- "direct"

selection <- app_joint_qdesn_phase179_selection(aggregate, controls, policy)
expect_true(nrow(selection$decisions) == 5L, "Selection did not retain five cells.")
expect_true(
  sum(!selection$decisions$selected_is_parity) == 3L,
  "Selection did not advance exactly three numerical challengers."
)
expect_true(nrow(selection$templates) == 8L, "Selected-versus-parity did not deduplicate.")
expect_true(
  all(!selection$decisions$global_specification_selected),
  "Selection accidentally declared a global specification."
)
expect_true(
  length(unique(selection$selected$source_control_row_sha256)) == 5L,
  "Case-specific frozen control hashes were not preserved."
)

case <- selection$decisions[!selection$decisions$selected_is_parity, , drop = FALSE][1L, ]
ids <- c(case$selected_template_id[[1L]], case$parity_template_id[[1L]])
score_summary <- app_joint_qdesn_bind_rows(lapply(ids, function(id) {
  candidate <- id == case$selected_template_id[[1L]]
  data.frame(
    case_id = case$case_id[[1L]], phase178_template_id = id,
    dgp_replicate_id = paste0("confirmation_r00", 1:3),
    posterior_score_mean = if (candidate) c(0.2999, 0.3001, 0.2998) else 0.30,
    forecast_truth_mae = if (candidate) c(0.101, 0.099, 0.100) else 0.10,
    fit_truth_mae = if (candidate) c(0.100, 0.101, 0.099) else 0.10,
    contract_crossing_pairs = 0L, score_rank_rhat = 1.06,
    score_bulk_ess = 250, score_tail_ess = 150,
    raw_crossing_rate = 0.02, stringsAsFactors = FALSE
  )
}))
m0_summary <- score_summary[, c(
  "case_id", "phase178_template_id", "dgp_replicate_id"
), drop = FALSE]
m0_summary$implementation_status <- "pass"
contrast <- data.frame(
  case_id = case$case_id[[1L]],
  candidate_template_id = case$selected_template_id[[1L]],
  probability_lower_score = c(0.51, 0.49, 0.52), stringsAsFactors = FALSE
)
decision <- app_joint_qdesn_phase179_matched_decision(
  case, score_summary, m0_summary, contrast, controls, policy
)
expect_true(
  decision$promoted_nonparity[[1L]],
  "A small two-of-three fresh score gain was not promoted."
)
expect_true(
  decision$gate_status[[1L]] == "review",
  "Moderate mixing/crossing diagnostics should remain visible as review."
)
expect_true(
  decision$posterior_probability_is_reporting_only[[1L]],
  "Posterior score probability became an undeclared superiority gate."
)

closeout_decisions <- data.frame(
  case_id = cases, base_scenario_id = sub("__.*", "", cases),
  fit_structure = ifelse(grepl("joint_exqdesn", cases), "joint", "independent"),
  final_selected_template_id = paste0(cases, "__selected"),
  final_selected_variant_id = c("parity", "tau0_upper", "parity", "tau0_lower", "tau0_lower"),
  promoted_nonparity = c(FALSE, TRUE, FALSE, TRUE, TRUE), fresh_replicates = 3L,
  median_score_ratio_vs_parity = c(1, 0.9998, 1, 0.9995, 0.9999),
  relative_score_improvement = c(0, 0.0002, 0, 0.0005, 0.0001),
  lower_score_replicate_fraction = c(0, 2 / 3, 0, 2 / 3, 2 / 3),
  median_probability_lower_score = c(0.5, 0.51, 0.5, 0.52, 0.51),
  median_forecast_oracle_mae_ratio = 1, maximum_forecast_oracle_mae_ratio = 1,
  median_fit_oracle_mae_ratio = 1, maximum_fit_oracle_mae_ratio = 1,
  source_and_implementation_pass = TRUE, score_functional_hard_pass = TRUE,
  oracle_safeguard_pass = TRUE, directional_gain_confirmed = c(FALSE, TRUE, FALSE, TRUE, TRUE),
  gate_status = "review", stringsAsFactors = FALSE
)
closeout_controls <- data.frame(
  case_id = cases,
  phase178_template_id = closeout_decisions$final_selected_template_id,
  variant_id = closeout_decisions$final_selected_variant_id,
  tau0 = seq(0.1, 0.5, length.out = 5L), zeta2 = 16L,
  alpha_prior_sd = 1, source_control_row_sha256 = paste0("selected_hash_", seq_along(cases)),
  phase179_final_role = ifelse(closeout_decisions$promoted_nonparity, "promoted", "parity"),
  stringsAsFactors = FALSE
)
closeout_scores <- app_joint_qdesn_bind_rows(lapply(seq_along(cases), function(ii) {
  data.frame(
    case_id = cases[[ii]],
    phase178_template_id = closeout_decisions$final_selected_template_id[[ii]],
    dgp_replicate_id = sprintf("confirmation_r%03d", 1:3),
    posterior_score_mean = 0.3 + ii / 1000, posterior_score_median = 0.3 + ii / 1000,
    posterior_score_q025 = 0.29, posterior_score_q975 = 0.31,
    canonical_action_dgp_integrated_acrps = 0.3 + ii / 1000,
    score_rank_rhat = 1.01, score_bulk_ess = 500, score_tail_ess = 300,
    raw_crossing_rate = 0.02, contract_crossing_pairs = 0L,
    score_functional_status = "pass", stringsAsFactors = FALSE
  )
}))
parity_scores <- app_joint_qdesn_bind_rows(lapply(
  which(closeout_decisions$promoted_nonparity), function(ii) {
    out <- closeout_scores[closeout_scores$case_id == cases[[ii]], , drop = FALSE]
    out$phase178_template_id <- paste0(cases[[ii]], "__parity_reference")
    out
  }
))
closeout_scores <- rbind(closeout_scores, parity_scores)
closeout_mcmc <- data.frame(
  mcmc_case_id = paste0("mcmc_", seq_len(24L)), implementation_status = "pass",
  scalar_mixing_status = "review", forecast_contract_crossing_pairs = 0L,
  stringsAsFactors = FALSE
)
closeout_parameters <- data.frame(
  parameter = rep(c("gamma", "sigma", "alpha", "trend"), each = 3L),
  rank_rhat = rep(c(1.01, 1.02, 1.20, 1.25), each = 3L),
  bulk_ess = rep(c(2000, 2500, 50, 45), each = 3L),
  tail_ess = rep(c(1500, 1800, 80, 75), each = 3L), stringsAsFactors = FALSE
)
closeout_pairing <- data.frame(
  fit_structure = rep(c("joint", "independent"), each = 12L),
  maximum_relative_mean_shift = rep(c(0, 1e-05), each = 12L),
  pairing_status = "pass", stringsAsFactors = FALSE
)
closeout_runtime <- data.frame(
  worker_id = seq_len(384L), elapsed_seconds = 3600, stringsAsFactors = FALSE
)
closeout_assessment <- data.frame(
  workers_planned = 384L, workers_complete = 384L, workers_failed = 0L,
  confirmation_cases = 24L, target_cells = 5L, promoted_nonparity = 3L,
  retained_parity = 2L, contract_crossing_pairs = 0L, stringsAsFactors = FALSE
)
source_completeness <- data.frame(
  source_model_id = c(
    "joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb",
    "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"
  ),
  article_cells = 8L, posterior_draw_cells_available = c(0L, 0L, 8L, 8L),
  worker_manifests_verified = c(0L, 0L, 64L, 64L),
  source_manifest_verified = TRUE,
  stringsAsFactors = FALSE
)
closeout <- app_joint_qdesn_phase179_closeout_tables(
  closeout_assessment, closeout_decisions, closeout_controls, closeout_scores,
  closeout_mcmc, closeout_parameters, closeout_pairing, closeout_runtime,
  source_completeness
)
expect_true(closeout$evidence$ready_for_integration[[1L]], "Closeout is not integration-ready.")
expect_true(
  !closeout$evidence$ready_for_article_launch_from_current_branch[[1L]],
  "Closeout authorized an article launch from the stale scientific branch."
)
expect_true(nrow(closeout$selected) == 5L, "Closeout did not preserve five cell decisions.")
expect_true(
  sum(closeout$selected$promoted_nonparity) == 3L,
  "Closeout did not preserve three case-specific promotions."
)
article_stage <- closeout$next_stage[
  closeout$next_stage$stage == "matched_article_fixture_confirmation", , drop = FALSE
]
expect_true(
  nrow(article_stage) == 1L && article_stage$planned_cases[[1L]] == 6L &&
    article_stage$planned_workers[[1L]] == 96L,
  "Matched article-fixture launch contract changed."
)
expect_true(
  sum(closeout$source_completeness$article_cells) == 32L,
  "Balanced source-completeness inventory changed."
)

crossed <- closeout_scores
crossed$contract_crossing_pairs[[1L]] <- 1L
expect_true(
  inherits(try(app_joint_qdesn_phase179_closeout_tables(
    closeout_assessment, closeout_decisions, closeout_controls, crossed,
    closeout_mcmc, closeout_parameters, closeout_pairing, closeout_runtime,
    source_completeness
  ), silent = TRUE), "try-error"),
  "Closeout did not fail closed on a contract crossing."
)

cat("Phase179 case-specific DGP-score confirmation tests passed\n")
