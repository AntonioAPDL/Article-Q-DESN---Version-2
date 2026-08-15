#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_exqdesn_phase164_165_readiness.R"))
source(app_path("application/R/joint_exqdesn_phase167_169_mcmc_method_selection.R"))

# Phase167 must select structured-v only when its implementation, stability,
# noninferiority, and runtime conditions are supported by matched rows.
scenarios <- paste0("scenario_", seq_len(8L))
replicates <- sprintf("r%03d", seq_len(10L))
structures <- c("joint", "independent")
methods <- c("VB0_point_v", "VB1_structured_v", "VB2_structured_u")
grid <- expand.grid(
  base_scenario_id = scenarios,
  dgp_replicate_id = replicates,
  fit_structure = structures,
  inference_method_id = methods,
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)
method_offset <- match(grid$inference_method_id, methods)
grid$candidate_id <- paste(
  grid$base_scenario_id, grid$dgp_replicate_id,
  grid$fit_structure, grid$inference_method_id, sep = "__"
)
grid$implementation_status <- "pass"
grid$gate_status <- "pass"
grid$vb_converged <- TRUE
grid$fit_truth_mae <- 0.10 + c(0.002, 0, 0.00005)[method_offset]
grid$forecast_truth_mae <- 0.11 + c(0.003, 0, 0.00005)[method_offset]
grid$fit_check_loss_mean <- 0.08 + c(0.002, 0, 0.00001)[method_offset]
grid$forecast_check_loss_mean <- 0.09 + c(0.002, 0, 0.00001)[method_offset]
grid$fit_crps_grid_mean <- 0.30 + c(0.002, 0, 0.000001)[method_offset]
grid$forecast_crps_grid_mean <- 0.31 + c(0.002, 0, 0.000001)[method_offset]
grid$fit_contract_crossing_pairs <- 0L
grid$forecast_contract_crossing_pairs <- 0L
grid$total_elapsed_seconds <- c(400, 120, 220)[method_offset]

audit <- app_joint_exqdesn_phase167_method_audit(grid)
stopifnot(nrow(audit$paired) == 160L)
stopifnot(nrow(audit$decision) == 2L)
stopifnot(all(audit$decision$method_decision_status == "pass"))
stopifnot(all(audit$decision$selected_vb_method == "VB1_structured_v"))
stopifnot(all(audit$decision$median_runtime_delta_u_minus_v > 0))

# Phase169 is a fixed 5 x 2 x 3 x 8 matched-chain design.
controls <- expand.grid(
  base_scenario_id = app_joint_exqdesn_phase169_scenarios(),
  fit_structure = c("joint", "independent"),
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)
controls$scenario_ids <- paste0(controls$base_scenario_id, "__r001")
controls$mcmc_case_id <- paste(controls$scenario_ids, controls$fit_structure, sep = "__")
plan <- app_joint_exqdesn_phase169_chain_plan(
  controls = controls,
  out_dir = file.path(tempdir(), "phase169_test"),
  n_chains = 8L,
  n_iter = 12000L,
  burn = 3000L,
  thin = 3L,
  workers_per_wave = 32L
)
stopifnot(nrow(plan) == 240L)
stopifnot(length(unique(plan$chain_seed)) == 240L)
stopifnot(length(unique(plan$worker_output_dir)) == 240L)
stopifnot(all(table(plan$mcmc_case_id, plan$inference_method_id) == 8L))
stopifnot(max(plan$wave_id) == 8L)
stopifnot(all(plan$n_keep == 3000L))

# Compact initializations reconstruct the joint and independent contracts, and
# matched starts change only gamma/sigma while preserving beta/intercepts.
K <- 3L
p <- 2L
case_id <- controls$mcmc_case_id[[1L]]
init_rows <- do.call(rbind, list(
  data.frame(mcmc_case_id = case_id, parameter_block = "beta", parameter_index = seq_len(K * p), value = seq_len(K * p) / 10),
  data.frame(mcmc_case_id = case_id, parameter_block = "alpha", parameter_index = seq_len(K), value = seq_len(K) / 20),
  data.frame(mcmc_case_id = case_id, parameter_block = "sigma", parameter_index = seq_len(K), value = c(0.8, 1, 1.2)),
  data.frame(mcmc_case_id = case_id, parameter_block = "gamma", parameter_index = seq_len(K), value = c(-0.2, 0, 0.2))
))
joint_init <- app_joint_exqdesn_phase169_init_from_rows(init_rows, case_id, "joint", K, p)
independent_init <- app_joint_exqdesn_phase169_init_from_rows(init_rows, case_id, "independent", K, p)
stopifnot(length(joint_init$beta_mean) == K * p)
stopifnot(length(independent_init$fits) == K)
stopifnot(all(vapply(independent_init$fits, function(x) length(x$beta_mean), integer(1L)) == p))

starts <- do.call(rbind, lapply(seq_len(K), function(k) rbind(
  data.frame(mcmc_case_id = case_id, chain_id = 1L, parameter = "gamma", quantile_index = k, value = 0.05 * k),
  data.frame(mcmc_case_id = case_id, chain_id = 1L, parameter = "sigma", quantile_index = k, value = 0.7 + 0.1 * k)
)))
job <- data.frame(mcmc_case_id = case_id, chain_id = 1L, stringsAsFactors = FALSE)
started <- app_joint_exqdesn_phase169_apply_chain_start(independent_init, starts, job, K, p)
stopifnot(all.equal(started$gamma_mean, c(0.05, 0.10, 0.15), tolerance = 1.0e-12))
stopifnot(all.equal(started$sigma_mean, c(0.8, 0.9, 1.0), tolerance = 1.0e-12))
stopifnot(all(vapply(seq_len(K), function(k) started$fits[[k]]$gamma_mean, numeric(1L)) == started$gamma_mean))

cat("Phase167/169 method-selection tests passed.\n")
