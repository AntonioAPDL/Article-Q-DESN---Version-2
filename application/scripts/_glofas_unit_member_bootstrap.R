source("application/R/00_packages.R")
app_set_repo_root(getwd())
for (path in c(
  "input_contract.R", "engine_contract.R", "model_contract.R", "feature_contract.R",
  "covariate_design.R", "build_application_panel.R", "build_qdesn_features.R",
  "latent_path_design.R", "discrepancy_design.R", "forecast_contract.R",
  "fit_qdesn_discrepancy.R", "latent_path_runtime_backend.R", "latent_path_checkpoint.R",
  "latent_path_vb_al.R", "latent_path_vb_normal.R", "joint_qvp_qdesn.R",
  "joint_exqdesn_exact_structured_inference.R", "latent_path_vb_exal.R",
  "glofas_quantile_integrity.R", "glofas_normal_desn_part1_screening.R",
  "glofas_part3_partitioned_rhs.R", "latent_path_vb_joint.R", "fit_qdesn_latent_path.R",
  "glofas_part4_ensemble_likelihood_contract.R", "glofas_normal_driver_bank.R",
  "glofas_part4_normal_driver_prior.R", "glofas_part4_latent_family.R",
  "glofas_unit_member_correction.R"
)) source(app_path("application/R", path))
