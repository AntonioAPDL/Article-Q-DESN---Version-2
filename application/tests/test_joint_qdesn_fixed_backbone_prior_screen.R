#!/usr/bin/env Rscript
source("application/scripts/_joint_qdesn_recursive_mean_forecast_bootstrap.R")
source(app_path("application/R/joint_qdesn_fixed_backbone_prior_screen.R"))
expect_error <- function(expr) {
  failed <- tryCatch({force(expr); FALSE}, error = function(e) TRUE)
  stopifnot(failed)
}
ct <- app_joint_prior_contract(); arms <- app_joint_prior_arms(ct); vc <- app_joint_prior_vb_contract(ct)
stopifnot(sum(ct$weights) == .9, nrow(arms) == 15L, sum(arms$baseline) == 1L,
  vc$rhs_slab_fixed, vc$rhs_slab_variance == 1, vc$sigma_lower_bound == 0,
  is.infinite(vc$sigma_upper_bound))
root <- tempfile("joint_prior_test_")
app_joint_prior_prepare(root)
plan <- app_read_csv(file.path(root, "screen", "chains.csv"))
cells <- app_read_csv(file.path(root, "screen", "cells.csv"))
stopifnot(nrow(plan) == 264L, nrow(cells) == 132L, sum(plan$long_budget) == 8L,
  sum(plan$structure == "independent") == 16L, !anyDuplicated(plan$chain_seed),
  !anyDuplicated(plan$start_seed))
expect_error(app_joint_prior_prepare(root))
expect_error(app_joint_prior_select(root))
expect_error(app_joint_prior_stage_prepare(root, "confirmation"))
app_joint_prior_verify_freeze(root)
mock <- expand.grid(arm_id = arms$arm_id, replicate_id = 1:2, stringsAsFactors = FALSE)
mock$scenario_id <- "laplace_bridge"; mock$likelihood <- "exAL"
mock$posterior_score_mean <- mock$canonical_origin_marginal_dgp_integrated_acrps <- 1
mock$posterior_score_mean[mock$arm_id == "prior_01"] <- 1 - 1e-8
mock$functional_status <- "pass"
baseline_id <- arms$arm_id[arms$baseline]
stopifnot(app_joint_prior_select_rows(mock, ct, baseline_id)$arm_id == "prior_01")
mock$functional_status[mock$arm_id == "prior_01"] <- "review"
stopifnot(app_joint_prior_select_rows(mock, ct, baseline_id)$arm_id == baseline_id)
expect_error(app_joint_prior_select_rows(mock[-1, ], ct, baseline_id))
selection <- expand.grid(scenario_id = ct$scenarios, likelihood = c("AL", "exAL"), stringsAsFactors = FALSE)
selection$arm_id <- "prior_01"; selection$baseline_arm_id <- baseline_id
app_write_csv(selection, file.path(root, "screen", "selection.csv"))
app_write_csv(data.frame(note = "test_only"), file.path(root, "screen", "complete_screen_scores.csv"))
paths <- c("selection.csv", "complete_screen_scores.csv")
app_write_csv(data.frame(relative_path = paths,
  sha256 = vapply(file.path(root, "screen", paths), app_sha256_file, character(1L))),
  file.path(root, "screen", "selection_manifest.csv"))
writeLines("TEST_ONLY_FROZEN_SELECTION", file.path(root, "screen", "SELECTION_FROZEN"))
confirmation <- app_joint_prior_stage_prepare(root, "confirmation")
stopifnot(nrow(confirmation$jobs) == 72L, nrow(confirmation$cells) == 24L,
  !any(confirmation$jobs$chain_seed %in% plan$chain_seed),
  !any(app_read_csv(file.path(root, "confirmation", "datasets.csv"))$dgp_seed %in%
    app_read_csv(file.path(root, "screen", "datasets.csv"))$dgp_seed))

# Essential end-to-end test only: real fixture/design, tiny fitting budgets.
test_ct <- ct
test_ct$vb_max_iterations <- 2L; test_ct$oracle_paths_per_shard <- 64L
test_ct$oracle_split_tolerance <- test_ct$oracle_analytic_tolerance <- 1
saveRDS(test_ct, file.path(root, "contract.rds"))
files <- list.files(root, full.names = TRUE)
files <- files[!dir.exists(files) & !basename(files) %in% c("freeze_manifest.csv")]
app_joint_shared_write_manifest(root, setNames(files, basename(files)), filename = "freeze_manifest.csv")
app_joint_prior_dataset(root, "screen", 1L)
context <- app_joint_prior_context(root, "screen", 1L)
stopifnot(length(context$design$fit_local) == 350L,
  length(context$design$validation_local) == 150L,
  max(context$fixture$detailed_split$full_time_index) == max(context$design$row_meta$full_time_index),
  !any(context$fixture$detailed_split$role == "validation"),
  ncol(context$design$Z) == 20L, !context$design$raw_inputs_in_readout)
base <- arms[arms$baseline, ]; altered <- arms[1L, ]
controls <- app_joint_prior_controls(context, base)
stopifnot(controls$anchor_tau0 == context$selected$rhs_tau0,
  controls$innovation_tau0 == context$selected$rhs_tau0)
stopifnot(app_joint_prior_target(context, controls, "AL", "joint") !=
  app_joint_prior_target(context, app_joint_prior_controls(context, altered), "AL", "joint"))
stopifnot(app_joint_prior_target(context, controls, "AL", "joint") ==
  app_joint_prior_target(context, controls, "AL", "joint"))
# Exercise the full current-grid score path using synthetic retained draws.
set.seed(11)
jobs <- plan[plan$cell_id == 1L, ]
for (j in seq_len(nrow(jobs))) {
  frame <- data.frame(draw_index = 1:20)
  for (k in seq_along(ct$tau)) {
    for (p in 1:20) frame[[sprintf("beta_%04d", (k - 1L) * 20L + p)]] <- rnorm(20, 0, .01)
    frame[[sprintf("alpha_%04d", k)]] <- rnorm(20, qnorm(ct$tau[[k]]), .01)
    frame[[sprintf("sigma_%04d", k)]] <- rep(.2, 20)
  }
  directory <- file.path(root, "screen", "chains", sprintf("worker_%04d", jobs$worker_id[[j]]))
  app_ensure_dir(directory)
  app_joint_article_write_gzip_csv(frame, file.path(directory, "posterior_draws.csv.gz"))
  app_write_csv(data.frame(target_hash = "synthetic_test_only", iterations = 40L,
    burn = 0L, thin = 2L, retained_draws = 20L, chain_seed = jobs$chain_seed[[j]]),
    file.path(directory, "metadata.csv"))
  app_joint_prior_seal(directory)
}
app_joint_prior_score(root, "screen", 1L)
score <- app_read_csv(file.path(root, "screen", "scores", "cell_0001", "summary.csv"))
stopifnot(is.finite(score$posterior_score_mean), score$contract_crossing_pairs == 0L,
  score$posterior_score_q025 <= score$posterior_score_mean,
  score$posterior_score_q975 >= score$posterior_score_mean)
# Tiny fits use a two-state subdesign only in this test, never in production.
context$design$Z <- context$design$Z[, 1:2]
context$design$X <- context$design$X[, 1:3]
context$selected$retained_state_budget <- 2L
K <- length(ct$tau)
indices <- unlist(lapply(seq_len(K), function(k) (k - 1L) * 20L + 1:2))
for (key in c("independent_al", "independent_exal")) {
  init <- context[[key]]
  init$beta_mean <- init$beta_mean[indices]
  init$beta_cov <- init$beta_cov[indices, indices]
  init$fits <- lapply(init$fits, function(x) {
    x$beta_mean <- x$beta_mean[1:2]; x$beta_cov <- x$beta_cov[1:2, 1:2]; x$rhs_state <- NULL; x
  })
  context[[key]] <- init
}
context$vc$al_max_iter <- 2L
fits <- app_joint_prior_vb(context, base)
stopifnot(all(is.finite(fits$AL$beta_mean)), all(is.finite(fits$exAL$beta_mean)),
  fits$exAL$inference_method_id == ct$exal_vb_method)
tiny <- ct
tiny$screen_al_iterations <- tiny$screen_exal_iterations <- 12L
tiny$screen_al_burn <- tiny$screen_exal_burn <- 4L; tiny$screen_thin <- 2L
for (family in c("AL", "exAL")) for (structure in c("joint", "independent")) {
  context$initializer <- fits[[family]]
  job <- data.frame(likelihood = family, structure = structure, long_budget = FALSE,
    chain_seed = 204L, start_seed = 205L)
  fit <- app_joint_prior_mcmc_fit(context, base, job, tiny, "screen")
  draws <- app_joint_article_draw_frame(fit$fit)
  stopifnot(nrow(draws) == 4L, all(is.finite(as.matrix(draws))))
  if (family == "exAL") stopifnot(all(
    (fit$fit$component_method_ids %||% fit$fit$inference_method_id) == ct$exal_mcmc_method))
}
# Original-order diagnostics retain deliberate between-chain discrepancies.
set.seed(12)
frames <- list(data.frame(draw_index = 1:40, beta_0001 = rnorm(40)),
  data.frame(draw_index = 1:40, beta_0001 = rnorm(40) + 5))
stopifnot(app_joint_prior_diagnostics(frames)$rank_rhat > 1.2)
file <- file.path(root, "arms.csv"); writeLines("tampered", file)
expect_error(app_joint_prior_verify_freeze(root))
unlink(root, recursive = TRUE)
cat("PASS: prior identity, 264-chain plan, leakage isolation, nested VB, AL/M0 dispatch, provenance failures.\n")
