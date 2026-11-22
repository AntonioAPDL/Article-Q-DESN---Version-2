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
cat("Stronger-window confirmation tests passed.\n")
