#!/usr/bin/env Rscript

script_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
repo_root <- normalizePath(file.path(dirname(normalizePath(script_arg)), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_vb_spec_screening.R", "joint_exqdesn_phase149_case_specific_screening.R",
  "latent_path_design.R", "joint_exqdesn_phase151_feature_design_screening.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  output_dir = app_joint_exqdesn_phase151_default_readiness_dir(),
  screening_dir = app_joint_exqdesn_phase151_default_dir(),
  fixture_dir = app_joint_exqdesn_phase151_default_fixture_dir(),
  phase150_freeze_dir = app_joint_exqdesn_phase151_default_phase150_freeze_dir(),
  phase150_audit_dir = app_joint_exqdesn_phase151_default_phase150_audit_dir()
))

result <- app_joint_exqdesn_run_phase151_readiness(
  out_dir = args[["output-dir"]] %||% args$output_dir,
  screening_dir = args[["screening-dir"]] %||% args$screening_dir,
  fixture_dir = args[["fixture-dir"]] %||% args$fixture_dir,
  phase150_freeze_dir = args[["phase150-freeze-dir"]] %||% args$phase150_freeze_dir,
  phase150_audit_dir = args[["phase150-audit-dir"]] %||% args$phase150_audit_dir
)
cat(sprintf("Phase151 readiness written to %s\n", result$out_dir))
print(result$assessment)
if (result$assessment$gate_status[[1L]] == "fail") quit(status = 1L)
