#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application/scripts", "_joint_qdesn_pure_recursive_bootstrap.R"))

contract <- app_joint_pr2_read_contract()
axes <- app_joint_pr2_read_axes()
registry <- app_joint_pr_read_registry()
stopifnot(
  contract$candidate_count == 1024L,
  contract$candidate_count == 1L + 383L + 512L + 128L,
  contract$seed_advance_count == 50L,
  contract$median_candidate_count == 12L,
  identical(contract$tail_quantiles, c(0.05, 0.95)),
  length(contract$cpu_affinity) == 15L,
  !anyDuplicated(contract$cpu_affinity),
  contract$automatic_stop_after == "three_quantile_al_transfer_review"
)

for (scenario in registry$scenario_id) {
  candidates <- app_joint_pr2_candidates(scenario, contract, axes)
  roles <- candidates$candidate_role
  stopifnot(
    nrow(candidates) == 1024L,
    sum(roles == "authoritative_v2_parity_anchor") == 1L,
    sum(grepl(paste0("targeted_v2_", if (scenario == "persistent_heavy_tail") "persistent_local" else "regime_local"), roles)) == 383L,
    sum(grepl("targeted_v2_global", roles)) == 512L,
    sum(grepl(paste0("targeted_v2_", if (scenario == "persistent_heavy_tail") "persistent_mechanism" else "regime_mechanism"), roles)) == 128L,
    !anyDuplicated(candidates$architecture_signature),
    all(candidates$reservoir_seed == contract$canonical_reservoir_seed),
    all(!app_as_bool_vec(candidates$raw_inputs_in_readout)),
    all(app_as_bool_vec(candidates$full_states_all_layers)),
    max(candidates$retained_state_budget) <= contract$max_readout_dimension
  )
}

fake <- data.frame(
  scenario_id = "test", candidate_id = paste0("candidate_", seq_len(15L)),
  candidate_role = c("authoritative_v2_parity_anchor", rep("targeted_v2_global_flat_flat", 14L)),
  calibration_acrps_mean = seq(0.2, 0.34, length.out = 15L),
  calibration_acrps_worst_rep = seq(0.3, 0.44, length.out = 15L),
  calibration_acrps_between_rep_sd = 0.01, convergence_fraction = 1,
  rhs_tau0 = 10^seq(-6, 1, length.out = 15L), stringsAsFactors = FALSE
)
short <- app_joint_pr2_best_unique(fake, 12L, TRUE)
stopifnot(nrow(short) == 12L, sum(short$candidate_role == "authoritative_v2_parity_anchor") == 1L,
  !anyDuplicated(short$candidate_id))

fake_tau <- rbind(fake, fake[1L, , drop = FALSE])
fake_tau$rhs_tau0[c(1L, nrow(fake_tau))] <- c(0.1, 1)
fake_tau$calibration_acrps_mean[c(1L, nrow(fake_tau))] <- c(0.1, 0.5)
short_tau <- app_joint_pr2_best_unique(fake_tau, 12L, TRUE, parity_tau0 = 1)
stopifnot(nrow(short_tau) == 12L,
  short_tau$rhs_tau0[short_tau$candidate_role == "authoritative_v2_parity_anchor"] == 1)

temp <- tempfile("joint_pr2_health_"); dir.create(temp)
app_write_csv(data.frame(parity_worker_id = 1:2), file.path(temp, "parity_worker_plan.csv"))
health <- app_joint_pr2_health(temp, "parity")
stopifnot(health$status[[1L]] == "ready", health$completed[[1L]] == 0L, health$remaining[[1L]] == 2L)

dgp <- app_joint_qdesn_load_simulation_registry()
sc <- dgp[dgp$scenario_id == "regime_shift", , drop = FALSE]
sc$seed <- registry$calibration_seed_base[registry$scenario_id == "regime_shift"]
fixture <- app_joint_qdesn_fixture_from_registry_row(sc); fixture$registry_row <- sc
selector <- app_joint_pure_selector_fixture(fixture, contract)
stopifnot(selector$protected_rows_persisted == 0L, nrow(selector$detailed_split) == 1000L)

cat("Targeted persistent/regime recalibration v2 tests passed.\n")
