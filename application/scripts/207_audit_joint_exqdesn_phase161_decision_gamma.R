#!/usr/bin/env Rscript
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R")); app_set_repo_root(repo_root)
for (file in c("input_contract.R", "synthesize_quantiles.R", "score_forecasts.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R",
  "joint_exqdesn_trace_tools.R", "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_exqdesn_phase158_fan_audit.R", "joint_exqdesn_phase161_decision_gamma_audit.R")) source(app_path("application/R", file))
args <- app_parse_args(list(phase160_dir = app_joint_exqdesn_phase161_default_phase160_dir(),
  output_dir = app_joint_exqdesn_phase161_default_output_dir()))
result <- app_joint_exqdesn_phase161_run(args[["phase160-dir"]] %||% args$phase160_dir,
  args[["output-dir"]] %||% args$output_dir)
print(result$gate, row.names = FALSE); print(result$decision[, c("scenario_id", "decision", "article_replacement")], row.names = FALSE)
