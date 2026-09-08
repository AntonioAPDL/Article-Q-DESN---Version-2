#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
script_arg <- if (length(file_arg) && !is.na(file_arg)) sub("^--file=", "", file_arg) else NA_character_
repo_root <- if (!is.na(script_arg)) {
  normalizePath(file.path(dirname(normalizePath(script_arg)), "..", ".."))
} else {
  normalizePath(getwd(), mustWork = TRUE)
}
Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1"
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "latent_path_vb_al.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R",
  "joint_qdesn_simulation_validation.R", "joint_qdesn_mcmc_readiness.R",
  "latent_path_design.R",
  "joint_exqdesn_phase151_feature_design_screening.R",
  "glofas_normal_desn_part1_screening.R",
  "joint_exqdesn_trace_tools.R",
  "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_exqdesn_exact_structured_inference.R",
  "joint_exqdesn_inference_dispatch.R",
  "joint_qdesn_dgp_integrated_acrps.R",
  "joint_qdesn_shared_backbone_screening.R",
  "joint_qdesn_shared_backbone_quantile_fit.R",
  "joint_qdesn_shared_backbone_family_campaign.R",
  "joint_qdesn_shared_backbone_article_confirmation.R"
)) source(app_path("application/R", path))

app_joint_article_arg <- function(name, default = NULL) {
  args <- commandArgs(trailingOnly = TRUE)
  index <- match(name, args)
  if (is.na(index) || index == length(args)) default else args[[index + 1L]]
}
