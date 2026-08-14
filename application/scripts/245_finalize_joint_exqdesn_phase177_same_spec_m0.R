#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R",
  "joint_qdesn_simulation_validation.R", "joint_qdesn_mcmc_readiness.R",
  "joint_exqdesn_trace_tools.R", "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_qdesn_phase153_balanced_independent_replication.R",
  "joint_qdesn_phase154_mcmc_evidence_reconciliation.R", "joint_qdesn_phase155_article_promotion.R",
  "latent_path_design.R", "joint_exqdesn_phase151_feature_design_screening.R",
  "joint_exqdesn_exact_structured_inference.R", "joint_exqdesn_inference_dispatch.R",
  "joint_exqdesn_phase164_165_readiness.R", "joint_exqdesn_phase166_168_structured_vb.R",
  "joint_exqdesn_phase167_169_mcmc_method_selection.R", "joint_exqdesn_phase169r_recovery.R",
  "joint_exqdesn_phase170_default_promotion.R", "joint_exqdesn_phase171_175_article_confirmation.R",
  "joint_exqdesn_phase176_180_post_m0_recovery.R"
)) source(app_path("application/R", file))

args <- commandArgs(trailingOnly = TRUE)
value <- function(name, default = NULL) {
  i <- match(name, args); if (is.na(i) || i == length(args)) default else args[[i + 1L]]
}
result <- app_joint_exqdesn_phase177_finalize(
  freeze_dir = value("--freeze-dir", app_joint_exqdesn_phase176_dirs()$phase177_freeze),
  out_dir = value("--output-dir", app_joint_exqdesn_phase176_dirs()$phase177_audit),
  force = "--force" %in% args
)
print(result$final, row.names = FALSE)
