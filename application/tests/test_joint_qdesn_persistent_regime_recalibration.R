#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application/scripts", "_joint_qdesn_pure_recursive_bootstrap.R"))

contract <- app_joint_pr_read_contract()
axes <- app_joint_pr_read_axes()
registry <- app_joint_pr_read_registry()
stopifnot(
  identical(contract$scenario_ids, registry$scenario_id),
  contract$candidate_count == 1024L,
  contract$advance_count == 50L,
  contract$median_advance_count == 8L,
  contract$protected_selection_forbidden,
  contract$automatic_stop_after == "median_al_vb_review",
  max(axes$depth) == 6L,
  max(axes$state_budget) == 600L,
  max(axes$response_lags) == 240L,
  length(axes$reservoir_seed) == 3L
)

candidate_pool <- app_joint_pr_candidate_pool(1400L, axes)
for (scenario in registry$scenario_id) {
  candidates <- app_joint_pr_candidates(scenario, contract, axes, candidate_pool)
  stopifnot(
    nrow(candidates) == 1024L,
    sum(candidates$candidate_role == "authoritative_v2_parity_anchor") == 1L,
    !anyDuplicated(candidates$architecture_signature),
    all(!app_as_bool_vec(candidates$raw_inputs_in_readout)),
    all(app_as_bool_vec(candidates$full_states_all_layers)),
    all(candidates$retained_state_budget <= contract$max_readout_dimension)
  )
}

pool <- app_joint_pr_candidate_pool(128L, axes)
layer_varying <- vapply(seq_len(nrow(pool)), function(ii) {
  length(unique(app_joint_shared_parse_num_vec(pool$alpha[[ii]]))) > 1L ||
    length(unique(app_joint_shared_parse_num_vec(pool$rho[[ii]]))) > 1L
}, logical(1L))
stopifnot(any(layer_varying), length(unique(pool$reservoir_seed)) > 1L)

dgp <- app_joint_qdesn_load_simulation_registry()
sc <- dgp[dgp$scenario_id == "persistent_heavy_tail", , drop = FALSE]
sc$seed <- registry$calibration_seed_base[registry$scenario_id == "persistent_heavy_tail"]
fixture <- app_joint_qdesn_fixture_from_registry_row(sc); fixture$registry_row <- sc
selector <- app_joint_pure_selector_fixture(fixture, contract)
stopifnot(selector$protected_rows_persisted == 0L, nrow(selector$detailed_split) == 1000L)

cat("Targeted persistent/regime recalibration tests passed.\n")
