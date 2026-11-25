#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application/scripts",
  "_joint_qdesn_persistent_tail_fit_first_bootstrap.R"))

contract <- app_joint_phtff_read_contract()
stopifnot(contract$source_candidate_count == 10L,
  contract$fresh_replicates == 5L,
  contract$shards_per_fixture == 8L,
  contract$paths_per_shard == 4096L,
  contract$protected_selection_forbidden,
  contract$article_fixture_materialization_forbidden,
  !contract$automatic_downstream_launch)

aggregate <- data.frame(
  candidate_id = c("smooth", "balanced", "fallback"),
  fit_first_role = c("v3_tail_shortlist", "v3_tail_shortlist", "exact_v2_fallback"),
  fit_oracle_quantile_mae_mean = c(0.198, 0.068, 0.059),
  horizon1_oracle_quantile_mae_mean = c(0.190, 0.070, 0.065),
  fit_outer_tail_mae_max_mean = c(0.250, 0.085, 0.080),
  origin_marginal_dgp_integrated_acrps_mean = c(0.5164, 0.5186, 0.5212),
  horizon1_5_dgp_acrps_mean = c(0.470, 0.448, 0.456),
  finite_all = TRUE, recursive_state_finite_all = TRUE,
  contract_crossings_sum = 0L, stringsAsFactors = FALSE)
selection <- app_joint_phtff_apply_selection(aggregate, contract)
stopifnot(selection$selected$candidate_id[[1L]] == "fallback",
  !selection$table$fit_gate_pass[selection$table$candidate_id == "smooth"],
  all(selection$table$fit_gate_pass[selection$table$candidate_id %in%
    c("balanced", "fallback")]))

bad <- aggregate
bad$contract_crossings_sum[bad$candidate_id == "balanced"] <- 1L
selection_bad <- app_joint_phtff_apply_selection(bad, contract)
stopifnot(selection_bad$selected$candidate_id[[1L]] == "fallback")

detail <- expand.grid(origin_index = 1:2, horizon = 1:3,
  tau = c(0.05, 0.5, 0.95), KEEP.OUT.ATTRS = FALSE)
detail <- detail[order(detail$tau, detail$origin_index, detail$horizon), ]
detail$qhat <- seq_len(nrow(detail))
matrix <- app_joint_phtff_matrix_from_detail(detail, "qhat", c(0.05, 0.5, 0.95))
stopifnot(identical(dim(matrix), c(6L, 3L)))

registry <- app_joint_qdesn_load_simulation_registry()
registry <- registry[registry$scenario_id == "persistent_heavy_tail", , drop = FALSE]
stopifnot(nrow(registry) == 1L)
oracle_fixture <- list(mu = c(-0.5, 0.25), sigma = c(1, 2), registry_row = registry)
tau <- c(0.05, 0.5, 0.95)
truth <- app_joint_phtff_oracle_true_q(oracle_fixture, tau)
standardized <- app_joint_qvp_registry_standardized_quantile(tau, registry)
stopifnot(identical(dim(truth), c(2L, 3L)),
  max(abs(truth - (matrix(oracle_fixture$mu, 2L, 3L) +
    oracle_fixture$sigma %o% standardized))) < 1e-12)

cat("JOINT_PERSISTENT_TAIL_FIT_FIRST_TEST_PASS expectations=20 production_runs=0\n")
