#!/usr/bin/env Rscript

if (!exists("app_joint_recursive_empirical_expected_check", mode = "function")) {
  file_arg <- sub("^--file=", "", commandArgs(FALSE)[grep(
    "^--file=", commandArgs(FALSE))])
  source(file.path(dirname(file_arg), "..", "scripts",
    "_joint_qdesn_recursive_mean_forecast_bootstrap.R"))
}

set.seed(91)
y <- sort(stats::rt(300, df = 5))
prefix <- cumsum(y)
q <- seq(-2, 2, length.out = 17)
for (tau in c(0.05, 0.25, 0.50, 0.90, 0.95)) {
  fast <- app_joint_recursive_empirical_expected_check(q, tau, y, prefix)
  brute <- vapply(q, function(value) mean(
    app_joint_qdesn_postscore_check_loss(y, value, tau)
  ), numeric(1L))
  stopifnot(max(abs(fast - brute)) < 1e-12)
}

# Matrix lookup preserves one value per time/draw pair.
oracle <- list(
  sorted_response = cbind(y, y + 1),
  prefix_response = cbind(cumsum(y), cumsum(y + 1))
)
pred <- matrix(c(0, 1, 0.5, 1.5), nrow = 2L)
observed <- app_joint_recursive_oracle_expected_matrix(oracle, pred, 0.5)
stopifnot(identical(dim(observed), c(2L, 2L)), all(is.finite(observed)))

source_candidates <- c(
  Sys.getenv("JOINT_RECURSIVE_SOURCE_ROOT", unset = ""),
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_corrected_article_comparison_muscat_11core_20260909/application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909",
  app_joint_recursive_default_source()
)
source_root <- source_candidates[dir.exists(source_candidates)][1L]
if (length(source_root) && !is.na(source_root)) {
  contract <- app_joint_recursive_read_contract()
  plans <- app_joint_recursive_build_plans(source_root, contract)
  row <- plans$oracle[
    plans$oracle$scenario_id == "normal_bridge" &
      app_as_bool_vec(plans$oracle$is_primary), , drop = FALSE][1L, ]
  fixture <- readRDS(file.path(source_root, row$fixture_relative_path))
  design <- readRDS(file.path(source_root, row$design_relative_path))
  shard_a <- app_joint_recursive_dgp_shard(fixture, design$forecast_map, 128L, 801L)
  shard_b <- app_joint_recursive_dgp_shard(fixture, design$forecast_map, 128L, 802L)
  paths <- file.path(tempdir(), c("recursive_oracle_a.rds", "recursive_oracle_b.rds"))
  saveRDS(shard_a, paths[[1L]])
  saveRDS(shard_b, paths[[2L]])
  combined <- app_joint_recursive_combine_oracle_shards(
    paths, fixture, contract$tau, contract$weights,
    analytic_tolerance = Inf, split_half_tolerance = Inf
  )
  stopifnot(
    combined$n_paths == 256L,
    identical(dim(combined$true_q), c(990L, 7L)),
    identical(combined$diagnostics$status[[1L]], "pass")
  )
}

cat("test_joint_qdesn_recursive_dgp_oracle: PASS\n")
