#!/usr/bin/env Rscript

if (!exists("app_path", mode = "function")) {
  source("application/R/00_packages.R")
  app_set_repo_root(getwd())
}
source(app_path("application/R/joint_qdesn_case_a_width_closure.R"))

ct <- app_joint_case_a_width_contract()
scores <- app_read_csv(app_path(ct$score_summary_relative_path))
recursive <- app_read_csv(app_path(ct$recursive_policy_relative_path))
fit <- app_read_csv(app_path(ct$fit_diagnostics_relative_path))
backbone <- app_joint_case_a_width_backbone_audit(
  app_read_csv(app_path(ct$selected_backbones_relative_path)), ct
)
case_a <- scores[scores$scenario_id == ct$scenario_id & scores$inference_method == "mcmc", ]
mean_design <- data.frame(
  scenario_id = ct$scenario_id,
  worker_id = case_a$worker_id,
  half_score_relative_difference = rep(0.001, 4L),
  chain_score_max_relative_deviation = rep(0.003, 4L),
  score_stability_status = "pass",
  stringsAsFactors = FALSE
)
current <- app_joint_case_a_width_current_audit(scores, recursive, fit, mean_design, ct)
pairs <- app_joint_case_a_width_pair_summary(current)
stopifnot(
  nrow(current) == 4L,
  nrow(backbone) == 1L,
  nrow(pairs) == 2L,
  all(!current$predictive_pathology),
  all(pairs$independent_to_joint_width_ratio > 1),
  all(!pairs$independent_predictive_pathology)
)

fresh <- do.call(rbind, lapply(c("AL", "exAL"), function(likelihood) {
  do.call(rbind, lapply(1:2, function(replicate_id) {
    data.frame(
      scenario_id = ct$scenario_id,
      replicate_id = replicate_id,
      likelihood = likelihood,
      structure = c("joint", "independent"),
      arm_id = ct$baseline_joint_arm_id,
      posterior_score_mean = c(0.40, 0.38),
      posterior_score_interval_width = c(0.10, 0.025),
      functional_status = "pass",
      contract_crossing_pairs = 0L,
      stringsAsFactors = FALSE
    )
  }))
}))
fresh_audit <- app_joint_case_a_width_fresh_seed_audit(fresh, pairs, ct)
stopifnot(
  nrow(fresh_audit) == 2L,
  all(fresh_audit$replicates == 2L),
  all(fresh_audit$independent_to_joint_width_ratio == 0.25),
  all(fresh_audit$width_order_reverses_article_fixture)
)

comparison <- data.frame(
  scenario_id = ct$scenario_id,
  model_id = current$model_id,
  fit_structure = current$fit_structure,
  likelihood_family = current$likelihood_family,
  inference_method = "mcmc",
  posterior_score_mean = current$posterior_score_mean,
  posterior_score_interval_width = current$posterior_score_interval_width,
  posterior_score_mean_baseline = current$posterior_score_mean * 1.02,
  posterior_score_interval_width_baseline = current$posterior_score_interval_width * 1.1,
  mean_change_percent = -2,
  interval_width_ratio = 1 / 1.1,
  intervals_overlap_baseline = TRUE,
  stringsAsFactors = FALSE
)
architecture <- app_joint_case_a_width_architecture_sensitivity(comparison, ct)
wording <- app_joint_case_a_width_article_wording_audit(getwd())
stopifnot(nrow(architecture) == 4L, all(wording$pass))

tmp <- tempfile("case_a_source_")
writeLines("frozen", tmp)
sha <- app_joint_case_a_width_sha256(tmp)
invisible(app_joint_case_a_width_assert_source(tmp, sha, "test"))
writeLines("changed", tmp)
failed <- tryCatch({
  app_joint_case_a_width_assert_source(tmp, sha, "test")
  FALSE
}, error = function(error) TRUE)
unlink(tmp)
stopifnot(failed)

cat("PASS: Case A current diagnostics, fresh-seed reversal, wording, and hash gates.\n")
