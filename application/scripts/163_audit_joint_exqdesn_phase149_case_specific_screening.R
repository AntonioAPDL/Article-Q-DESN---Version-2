#!/usr/bin/env Rscript

script_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
repo_root <- normalizePath(file.path(dirname(normalizePath(script_arg)), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_vb_spec_screening.R", "joint_exqdesn_phase136_gamma_kernel_packet.R",
  "joint_exqdesn_phase148_target_invariance.R",
  "joint_exqdesn_phase149_case_specific_screening.R"
)) source(app_path("application/R", path))

result <- app_joint_exqdesn_run_phase149_result_audit()
cat(sprintf("Phase149 result audit written to %s\n", result$out_dir))
print(result$assessment)
if (identical(result$assessment$gate_status[[1L]], "fail")) quit(status = 1L)
