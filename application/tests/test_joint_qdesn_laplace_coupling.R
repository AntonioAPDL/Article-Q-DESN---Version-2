#!/usr/bin/env Rscript
source("application/scripts/_joint_qdesn_laplace_coupling_bootstrap.R")
expect_error <- function(expr) {
  failed <- tryCatch({force(expr); FALSE}, error = function(e) TRUE)
  stopifnot(failed)
}
ct <- app_joint_prior_contract(); arms <- app_joint_prior_arms(ct)
stopifnot(nrow(arms) == 3L, sum(arms$baseline) == 1L, sum(ct$weights) == .9)
root <- tempfile("joint_coupling_test_")
app_joint_prior_prepare(root)
plan <- app_read_csv(file.path(root, "screen/chains.csv"))
stopifnot(nrow(plan) == 32L, !any(plan$long_budget), !anyDuplicated(plan$chain_seed),
  !anyDuplicated(plan$start_seed), nrow(app_read_csv(file.path(root, "screen/cells.csv"))) == 16L)
expect_error(app_joint_prior_prepare(root))
expect_error(app_joint_prior_select(root))
expect_error(app_joint_prior_stage_prepare(root, "confirmation"))

test_ct <- ct
test_ct$vb_max_iterations <- 2L; test_ct$oracle_paths_per_shard <- 64L
test_ct$oracle_split_tolerance <- test_ct$oracle_analytic_tolerance <- 1
saveRDS(test_ct, file.path(root, "contract.rds"))
files <- list.files(root, full.names = TRUE)
files <- files[!dir.exists(files) & basename(files) != "freeze_manifest.csv"]
app_joint_shared_write_manifest(root, setNames(files, basename(files)), filename = "freeze_manifest.csv")
app_joint_prior_dataset(root, "screen", 1L)
context <- app_joint_coupling_parent_context(root, "screen", 1L)
stopifnot(length(context$design$fit_local) == 350L,
  length(context$design$validation_local) == 150L, ncol(context$design$Z) == 48L,
  !context$design$raw_inputs_in_readout,
  max(context$design$row_meta$full_time_index[context$design$fit_local]) <
    min(context$design$forecast_map$full_time_index))
cal <- app_joint_coupling_calibrated_arms(context, ct)
expect_error(app_joint_prior_context(root, "screen", 1L))
app_joint_coupling_calibrate(root, "screen", 1L)
verified <- app_joint_prior_context(root, "screen", 1L)
stopifnot(isTRUE(all.equal(cal$arms, verified$calibrated_arms, check.attributes = FALSE)))
app_joint_prior_warmup(root, "screen", 1L)
cached <- file.path(root, "screen/calibrations/dataset_01/baseline_initializers.rds")
stopifnot(app_sha256_file(cached) == app_sha256_file(file.path(root, "screen/warmups/worker_001/initializers.rds")))
perturbed <- context
perturbed$design$Z[-context$design$fit_local, ] <- 1e6
perturbed$design$y[-context$design$fit_local] <- -1e6
perturbed$fixture <- NULL
stopifnot(identical(cal, app_joint_coupling_calibrated_arms(perturbed, ct)))
context$calibrated_arms <- cal$arms
base <- arms[1L, ]; relaxed <- arms[2L, ]; budget <- arms[3L, ]
c0 <- app_joint_prior_controls(context, base)
stopifnot(identical(c0, app_joint_coupling_parent_controls(context, base)),
  identical(app_joint_prior_controls(context, relaxed, independent = TRUE),
    app_joint_coupling_parent_controls(context, base, independent = TRUE)))
c1 <- app_joint_prior_controls(context, relaxed); c2 <- app_joint_prior_controls(context, budget)
stopifnot(c1$innovation_zeta2 > c0$innovation_zeta2,
  c1$anchor_tau0 == c0$anchor_tau0, c1$innovation_tau0 == c0$innovation_tau0,
  c2$anchor_zeta2 == c0$anchor_zeta2, c2$innovation_zeta2 == c0$innovation_zeta2)
for (c in list(c1, c2)) stopifnot(app_joint_prior_target(context, c, "AL", "joint") !=
  app_joint_prior_target(context, c0, "AL", "joint"))
state <- app_joint_qvp_initialize_rhs_state(7L, 1L, tau0 = c2$tau0,
  anchor_tau0 = c2$anchor_tau0, innovation_tau0 = c2$innovation_tau0,
  anchor_zeta2 = c2$anchor_zeta2, innovation_zeta2 = c2$innovation_zeta2, slab_fixed = TRUE)
prior <- app_joint_qvp_rhs_state_to_prior(state)
V <- solve(as.matrix(app_joint_qvp_build_prior_precision(7L, 1L, prior$anchor, prior$innovations)$P_beta))
stopifnot(abs(V[7L, 7L] - cal$arms$conditional_reference_variance[3L]) < 1e-10)

# Only this essential test reduces the state count and fitting budgets.
original_p <- ncol(context$design$Z); K <- length(ct$tau)
context$design$Z <- context$design$Z[, 1:2]
indices <- unlist(lapply(seq_len(K), function(k) (k - 1L) * original_p + 1:2))
for (key in c("independent_al", "independent_exal")) {
  init <- context[[key]]; init$beta_mean <- init$beta_mean[indices]
  init$beta_cov <- init$beta_cov[indices, indices]
  init$fits <- lapply(init$fits, function(x) {
    x$beta_mean <- x$beta_mean[1:2]; x$beta_cov <- x$beta_cov[1:2, 1:2]; x$rhs_state <- NULL; x
  })
  context[[key]] <- init
}
context$vc$al_max_iter <- context$vc$exal_max_iter <- 2L
old <- app_joint_coupling_parent_vb(context, base)
fits <- app_joint_prior_vb(context, base)
for (family in c("AL", "exAL")) stopifnot(
  max(abs(old[[family]]$beta_mean - fits[[family]]$beta_mean)) < 1e-10,
  max(abs(old[[family]]$alpha_mean - fits[[family]]$alpha_mean)) < 1e-10)
tiny <- ct
tiny$screen_al_iterations <- tiny$screen_exal_iterations <- 12L
tiny$screen_al_burn <- tiny$screen_exal_burn <- 4L; tiny$screen_thin <- 2L
for (arm in list(relaxed, budget)) {
  fits <- app_joint_prior_vb(context, arm)
  controls <- app_joint_prior_controls(context, arm)
  for (family in c("AL", "exAL")) {
    context$initializer <- fits[[family]]
    job <- data.frame(likelihood = family, structure = "joint", long_budget = FALSE,
      chain_seed = 209L, start_seed = 211L)
    result <- app_joint_prior_mcmc_fit(context, arm, job, tiny, "screen")
    draws <- app_joint_article_draw_frame(result$fit)
    stopifnot(nrow(draws) == 4L, all(is.finite(as.matrix(draws))),
      result$target_hash == app_joint_prior_target(context, controls, family, "joint"))
    if (family == "exAL") stopifnot(result$fit$inference_method_id == ct$exal_mcmc_method,
      fits[[family]]$inference_method_id == ct$exal_vb_method)
  }
}

# Exercise the unchanged scorer through the new sealed calibration context.
set.seed(17)
jobs <- plan[plan$cell_id == 1L, ]
for (j in seq_len(nrow(jobs))) {
  frame <- data.frame(draw_index = 1:20)
  for (k in seq_along(ct$tau)) {
    for (p in seq_len(original_p)) frame[[sprintf("beta_%04d", (k - 1L) * original_p + p)]] <- rnorm(20, 0, .001)
    frame[[sprintf("alpha_%04d", k)]] <- rnorm(20, qnorm(ct$tau[k]), .01)
    frame[[sprintf("sigma_%04d", k)]] <- .2
  }
  directory <- file.path(root, "screen/chains", sprintf("worker_%04d", jobs$worker_id[j]))
  app_ensure_dir(directory)
  app_joint_article_write_gzip_csv(frame, file.path(directory, "posterior_draws.csv.gz"))
  app_write_csv(data.frame(target_hash = "synthetic_test_only", iterations = 40L,
    burn = 0L, thin = 2L, retained_draws = 20L, chain_seed = jobs$chain_seed[j]), file.path(directory, "metadata.csv"))
  app_joint_prior_seal(directory)
}
app_joint_prior_score(root, "screen", 1L)
score <- app_read_csv(file.path(root, "screen/scores/cell_0001/summary.csv"))
stopifnot(is.finite(score$posterior_score_mean), score$contract_crossing_pairs == 0,
  score$posterior_score_q025 <= score$posterior_score_q975)

mock <- expand.grid(arm_id = arms$arm_id, replicate_id = 1:2, stringsAsFactors = FALSE)
mock$scenario_id <- "laplace_bridge"; mock$likelihood <- "exAL"
mock$posterior_score_mean <- mock$canonical_origin_marginal_dgp_integrated_acrps <- 1
mock$posterior_score_mean[mock$arm_id == relaxed$arm_id] <- 1 - 1e-8
mock$functional_status <- "review"
mock$score_rank_rhat <- mock$quantile_functional_max_rhat <- 1.25
mock$state_half_score_relative_difference <- mock$chain_score_relative_range <- .01
mock$contract_crossing_pairs <- mock$canonical_contract_crossing_pairs <- 0
stopifnot(app_joint_prior_select_rows(mock, ct, "baseline")$arm_id == relaxed$arm_id)
mock$state_half_score_relative_difference[mock$arm_id == relaxed$arm_id] <- .4
stopifnot(app_joint_prior_select_rows(mock, ct, "baseline")$arm_id == "baseline")
expect_error(app_joint_prior_select_rows(mock[-1L, ], ct, "baseline"))
selection <- data.frame(scenario_id = "laplace_bridge", likelihood = c("AL", "exAL"),
  arm_id = c(relaxed$arm_id, budget$arm_id), baseline_arm_id = "baseline")
app_write_csv(selection, file.path(root, "screen/selection.csv"))
app_write_csv(mock, file.path(root, "screen/complete_screen_scores.csv"))
paths <- c("selection.csv", "complete_screen_scores.csv")
app_write_csv(data.frame(relative_path = paths,
  sha256 = vapply(file.path(root, "screen", paths), app_sha256_file, character(1L))),
  file.path(root, "screen/selection_manifest.csv"))
writeLines("TEST_ONLY_FROZEN_SELECTION", file.path(root, "screen/SELECTION_FROZEN"))
app_joint_prior_stage_prepare(root, "confirmation")
confirm <- app_read_csv(file.path(root, "confirmation/chains.csv"))
stopifnot(nrow(confirm) == 36L, !any(confirm$chain_seed %in% plan$chain_seed),
  !any(app_read_csv(file.path(root, "confirmation/datasets.csv"))$dgp_seed %in%
    app_read_csv(file.path(root, "screen/datasets.csv"))$dgp_seed))
writeLines("tampered", file.path(root, "arms.csv")); expect_error(app_joint_prior_verify_freeze(root))
unlink(root, recursive = TRUE)
cat("PASS: 32/36-worker bounds, training-only calibration, conditional covariance, unchanged baseline, slab wiring, VB1/M0 targets, review-level positive gains, pathology/completeness gates.\n")
