#!/usr/bin/env Rscript
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."))
source(file.path(repo_root, "application/scripts/_joint_qdesn_stronger_window_bootstrap.R"))
ct <- app_joint_swcf_contract()
stopifnot(
  app_joint_swcf_value(ct, "practical_noninferiority_margin", TRUE) == 0.01,
  app_joint_swcf_value(ct, "chains_per_cell", TRUE) == 3,
  app_joint_swcf_value(ct, "exal_mcmc_method") == "M0_v_collapsed_support_logit",
  app_joint_swcf_value(ct, "canonical_forecast_policy") == "recursive_mean_state"
)
body <- paste(deparse(app_joint_swcf_mcmc_fit), collapse = "\n")
stopifnot(
  grepl("M0_v_collapsed_support_logit", body, fixed = TRUE),
  grepl("app_joint_article_mcmc_precision_repair_controls", body, fixed = TRUE),
  grepl("protected_rows_loaded = 0L", paste(deparse(app_joint_swcf_run_sentinel), collapse = "\n"), fixed = TRUE),
  grepl("protected_scores_computed = FALSE", paste(deparse(app_joint_swcf_run_vb), collapse = "\n"), fixed = TRUE)
)
root <- file.path(repo_root, "application/cache/joint_qdesn_stronger_window_richer_screen_20261121")
if (file.exists(file.path(root, "full_confirmation/mcmc_sentinel_plan.csv"))) {
  sentinel <- app_read_csv(file.path(root, "full_confirmation/mcmc_sentinel_plan.csv"))
  packet <- app_joint_swcf_load_transfer_packet(root,
    sentinel[sentinel$sentinel_model_id == "independent_exqdesn_rhs", , drop = FALSE])
  stopifnot(
    length(packet$independent_exqdesn_rhs$fits) == 7L,
    length(packet$independent_exqdesn_rhs$sigma_mean) == 7L,
    length(packet$independent_exqdesn_rhs$gamma_mean) == 7L
  )
  init <- app_joint_swcf_packet_init(packet, "independent_exqdesn_rhs")
  stopifnot(
    length(init$fits) == 7L,
    length(init$beta_mean) == sum(vapply(init$fits, function(x) length(x$beta_mean), integer(1L))),
    length(init$alpha_mean) == 7L,
    length(init$sigma_mean) == 7L,
    length(init$gamma_mean) == 7L
  )
}
launcher <- paste(readLines(file.path(repo_root,
  "application/scripts/launch_joint_qdesn_stronger_window_confirmation.sh"), warn = FALSE),
  collapse = "\n")
stopifnot(
  grepl("JOINT_SWCF_CONFIRM_STAGE", launcher, fixed = TRUE),
  grepl("physical_package_id", launcher, fixed = TRUE),
  grepl("taskset -c", launcher, fixed = TRUE),
  grepl("mcmc_worker_plan.csv", launcher, fixed = TRUE),
  grepl("oracle_worker_plan.csv", launcher, fixed = TRUE),
  grepl("score_worker_plan.csv", launcher, fixed = TRUE)
)
metadata <- app_joint_swcf_model_metadata("joint_exqdesn_rhs")
stopifnot(metadata$fit_structure == "joint", metadata$likelihood_family == "exAL")
mcmc_body <- paste(deparse(app_joint_swcf_run_mcmc), collapse = "\n")
finalize_body <- paste(deparse(app_joint_swcf_finalize_vb), collapse = "\n")
stopifnot(
  grepl("app_joint_article_overdispersed_start", mcmc_body, fixed = TRUE),
  grepl("protected_scores_computed = FALSE", mcmc_body, fixed = TRUE),
  grepl("nrow(workers) != 192L", finalize_body, fixed = TRUE),
  grepl("M0_v_collapsed_support_logit", finalize_body, fixed = TRUE)
)
cat("Stronger-window confirmation tests passed.\n")
