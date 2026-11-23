#!/usr/bin/env Rscript
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."))
source(file.path(repo_root, "application/scripts/_joint_qdesn_stronger_window_bootstrap.R"))

contract <- app_joint_superfinal_contract()
targets <- app_joint_superfinal_targets()
stopifnot(
  nrow(targets) == 3L,
  identical(targets$source_score_worker_id, c(48L, 84L, 88L)),
  app_joint_superfinal_value(contract, "additional_chains_per_cell", TRUE) == 5,
  app_joint_superfinal_value(contract, "exal_mcmc_method") ==
    "M0_v_collapsed_support_logit",
  app_joint_superfinal_value(contract, "fallback_policy") ==
    "whole_scenario_new_geometry_parity",
  app_joint_superfinal_value(contract, "model_splicing_allowed") == "FALSE",
  app_joint_superfinal_value(contract, "source_git_head") ==
    "4381c14c50aa60de93eb952e3f67965bde9904f5",
  grepl("^[0-9a-f]{64}$", app_joint_superfinal_value(contract,
    "source_inventory_sha256"))
)

x <- data.frame(chain_id = rep(1:3, each = 10), source_draw_index = rep(1:10, 3),
  origin_marginal_dgp_integrated_acrps = c(rep(1, 10), c(rep(1, 9), 100), rep(1, 10)))
chain <- app_joint_superfinal_chain_metrics(x, 20)
diag <- app_joint_exqdesn_modern_diagnostics(matrix(
  x$origin_marginal_dgp_integrated_acrps, ncol = 3))
influence <- app_joint_superfinal_influence(x, diag, contract)
stopifnot(
  nrow(chain) == 3L,
  chain$extreme_draws[chain$chain_id == 2L] == 1L,
  influence$max_draw_fraction > 0.5,
  influence$leave_one_chain_relative_range > 1
)

prepare_body <- paste(deparse(app_joint_superfinal_prepare), collapse = "\n")
final_body <- paste(deparse(app_joint_superfinal_finalize), collapse = "\n")
closeout_body <- paste(deparse(app_joint_superfinal_closeout), collapse = "\n")
stopifnot(
  grepl("source_binding.csv", prepare_body, fixed = TRUE),
  grepl("1500000000L", prepare_body, fixed = TRUE),
  grepl("whole_scenario_new_geometry_parity",
    paste(deparse(app_joint_superfinal_contract), collapse = "\n"), fixed = TRUE),
  grepl("persistent_ok", final_body, fixed = TRUE),
  grepl("packet_complete", final_body, fixed = TRUE),
  grepl("M0_v_collapsed_support_logit", paste(deparse(
    app_joint_superfinal_combined_draws), collapse = "\n"), fixed = TRUE),
  grepl("runtime_transfer_inventory.csv", closeout_body, fixed = TRUE),
  grepl("READY_FOR_INTEGRATION", closeout_body, fixed = TRUE)
)
cat("Super-final predictive-stability tests passed.\n")
