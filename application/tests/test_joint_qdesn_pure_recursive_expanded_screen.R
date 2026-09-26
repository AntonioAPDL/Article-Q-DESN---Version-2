#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application/scripts/_joint_qdesn_pure_recursive_bootstrap.R"))

source_contract <- app_joint_pure_read_contract()
contract <- app_joint_pure_expanded_read_contract()
axes <- app_joint_pure_expanded_read_axes()
stopifnot(
  source_contract$candidate_count == 256L,
  contract$version == "joint_qdesn_pure_recursive_expanded_screen_v2",
  contract$candidate_count == 768L,
  contract$legacy_candidate_count == 256L,
  contract$expanded_candidate_count == 512L,
  contract$advance_count == 64L,
  contract$max_readout_dimension == 300L,
  contract$screening_only,
  identical(axes$depth, 1:4),
  identical(axes$response_lags, c(1L, 2L, 3L, 5L, 8L, 12L, 15L, 24L, 30L, 45L, 60L, 75L, 90L, 120L, 150L)),
  identical(axes$exogenous_lags, 0L)
)

H1 <- app_joint_pure_expanded_halton(32L, 9L, axes$halton_skip)
H2 <- app_joint_pure_expanded_halton(32L, 9L, axes$halton_skip)
stopifnot(identical(H1, H2), all(H1 > 0), all(H1 < 1))

pool1 <- app_joint_pure_expanded_candidate_pool(2048L, axes)
pool2 <- app_joint_pure_expanded_candidate_pool(2048L, axes)
stopifnot(
  identical(pool1$architecture_signature, pool2$architecture_signature),
  !anyDuplicated(pool1$architecture_signature),
  all(pool1$D %in% 1:4),
  all(pool1$response_lags %in% axes$response_lags),
  all(pool1$retained_state_budget %in% axes$state_budget),
  max(pool1$retained_state_budget) == 300L,
  min(pool1$retained_state_budget) == 20L,
  all(vapply(strsplit(pool1$n, ";", fixed = TRUE), function(x) sum(as.integer(x)), integer(1L)) == pool1$retained_state_budget),
  all(vapply(seq_len(nrow(pool1)), function(i) length(strsplit(pool1$n[[i]], ";", fixed = TRUE)[[1L]]) == pool1$D[[i]], logical(1L)))
)
alpha <- vapply(strsplit(pool1$alpha, ";", fixed = TRUE), function(x) as.numeric(x[[1L]]), numeric(1L))
rho <- vapply(strsplit(pool1$rho, ";", fixed = TRUE), function(x) as.numeric(x[[1L]]), numeric(1L))
stopifnot(
  min(alpha) == 0.01, max(alpha) == 0.99,
  min(rho) == 0.20, max(rho) == 0.99,
  all(alpha >= 0.01 & alpha <= 0.99),
  all(rho >= 0.20 & rho <= 0.99),
  all(axes$response_lags %in% pool1$response_lags)
)

legacy <- app_joint_pure_candidates("normal_bridge", source_contract)$candidates
combined <- app_joint_pure_expanded_candidates(legacy, "normal_bridge", contract, axes)
stopifnot(
  nrow(combined) == 768L,
  identical(combined$candidate_id[seq_len(256L)], legacy$candidate_id),
  identical(combined$architecture_signature[seq_len(256L)], legacy$architecture_signature),
  sum(grepl("^expanded_", combined$candidate_role)) == 512L,
  !anyDuplicated(combined$candidate_id),
  !anyDuplicated(combined$architecture_signature)
)

wide <- combined[which.max(combined$retained_state_budget), , drop = FALSE]
reservoir <- app_joint_pure_reservoir(wide, m_input = wide$response_lags[[1L]] + 3L,
  max_readout_dimension = 300L)
stopifnot(sum(wide$retained_state_budget) == 300L, length(reservoir$n) == wide$D[[1L]])
rejected <- try(app_joint_pure_reservoir(wide, m_input = 4L, max_readout_dimension = 192L), silent = TRUE)
stopifnot(inherits(rejected, "try-error"))

summary <- data.frame(
  candidate_id = "old", worker_id = 1L, replicate_id = 1L,
  dgp_seed = 10L, fixture_path = "old.rds", calibration_acrps_mean = 1,
  stringsAsFactors = FALSE)
summary_path <- tempfile(fileext = ".csv")
app_write_csv(summary, summary_path)
target <- data.frame(
  candidate_id = "new", worker_id = 99L, replicate_id = 2L,
  dgp_seed = 20L, fixture_path = "new.rds", stringsAsFactors = FALSE)
rewritten <- app_joint_pure_expanded_rewrite_summary(summary_path, target, "ridge")
stopifnot(
  rewritten$candidate_id == "new", rewritten$worker_id == 99L,
  rewritten$replicate_id == 2L, rewritten$dgp_seed == 20L,
  rewritten$fixture_path == "new.rds", rewritten$calibration_acrps_mean == 1
)

cat("Expanded pure-recursive JOINT screening tests passed.\n")
