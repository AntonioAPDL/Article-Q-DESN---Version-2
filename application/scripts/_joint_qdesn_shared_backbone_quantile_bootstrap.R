#!/usr/bin/env Rscript

script_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
repo_root <- normalizePath(file.path(dirname(normalizePath(script_arg)), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "latent_path_vb_al.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R",
  "joint_qdesn_simulation_validation.R", "latent_path_design.R",
  "joint_exqdesn_phase151_feature_design_screening.R",
  "glofas_normal_desn_part1_screening.R",
  "joint_exqdesn_exact_structured_inference.R",
  "joint_exqdesn_inference_dispatch.R",
  "joint_qdesn_dgp_integrated_acrps.R",
  "joint_qdesn_shared_backbone_screening.R",
  "joint_qdesn_shared_backbone_quantile_fit.R"
)) source(app_path("application/R", path))
