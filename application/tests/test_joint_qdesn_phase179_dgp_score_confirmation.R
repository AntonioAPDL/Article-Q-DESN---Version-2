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

cat("Phase179 case-specific DGP-score confirmation tests passed\n")
