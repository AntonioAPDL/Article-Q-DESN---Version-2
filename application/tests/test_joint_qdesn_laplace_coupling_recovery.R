#!/usr/bin/env Rscript
source("application/scripts/_joint_qdesn_laplace_coupling_recovery_bootstrap.R")
rc <- app_joint_recovery_contract(); ct <- app_joint_prior_contract()
stopifnot(rc$supplemental_chains_per_cell == 2, rc$max_workers == 15,
  ct$exal_mcmc_method == "M0_v_collapsed_support_logit",
  ct$exal_vb_method == "VB1_structured_v")

mock <- expand.grid(arm_id = app_joint_coupling_arms()$arm_id,
  replicate_id = 1:2, stringsAsFactors = FALSE)
mock$scenario_id <- "laplace_bridge"; mock$likelihood <- "AL"
mock$posterior_score_mean <- 1
mock$posterior_score_mean[mock$arm_id == "relaxed_innovation_slab"] <- .99
mock$posterior_score_mean[mock$arm_id == "conditional_variance_budget"] <- .995
mock$posterior_score_interval_width <- .1
mock$canonical_origin_marginal_dgp_integrated_acrps <- mock$posterior_score_mean
mock$score_rank_rhat <- 1.1; mock$quantile_functional_max_rhat <- 1.1
mock$state_half_score_relative_difference <- .01; mock$chain_score_relative_range <- .01
mock$contract_crossing_pairs <- mock$canonical_contract_crossing_pairs <- 0
selected <- app_joint_recovery_select_group(mock, ct)
stopifnot(selected$status$status == "ready_for_fresh_confirmation",
  selected$selection$arm_id == "relaxed_innovation_slab")

blocked <- mock
blocked$quantile_functional_max_rhat[blocked$arm_id == "baseline" &
  blocked$replicate_id == 2L] <- 1.85
decision <- app_joint_recovery_select_group(blocked, ct)
stopifnot(decision$status$status == "blocked_baseline_functional_pathology",
  nrow(decision$selection) == 0L)

fallback <- mock
fallback$quantile_functional_max_rhat[fallback$arm_id == "relaxed_innovation_slab" &
  fallback$replicate_id == 2L] <- 1.85
decision <- app_joint_recovery_select_group(fallback, ct)
stopifnot(decision$selection$arm_id == "conditional_variance_budget")

selection <- data.frame(likelihood = "exAL", arm_id = "relaxed_innovation_slab")
plan <- app_joint_recovery_confirmation_plan(selection, ct)
stopifnot(nrow(plan$datasets) == 2L, nrow(plan$cells) == 6L,
  nrow(plan$chains) == 18L, nrow(plan$warmups) == 4L,
  !anyDuplicated(plan$chains$chain_seed), !anyDuplicated(plan$chains$start_seed))
selection <- rbind(selection,
  data.frame(likelihood = "AL", arm_id = "conditional_variance_budget"))
plan <- app_joint_recovery_confirmation_plan(selection, ct)
stopifnot(nrow(plan$cells) == 12L, nrow(plan$chains) == 36L,
  nrow(plan$warmups) == 6L)

from <- tempfile("recovery_copy_source_"); to <- tempfile("recovery_copy_target_")
dir.create(file.path(from, "nested"), recursive = TRUE)
writeLines("sealed", file.path(from, "nested", "value.txt"))
app_joint_recovery_copy_tree(from, to)
stopifnot(identical(readLines(file.path(to, "nested", "value.txt")), "sealed"))
unlink(c(from, to), recursive = TRUE)
cat("PASS: explicit baseline pathology, eligible fallback, partial/full confirmation plans, immutable copy helper, VB1/M0 contract.\n")
