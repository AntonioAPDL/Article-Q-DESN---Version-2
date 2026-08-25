#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_phase153_balanced_independent_replication.R",
  "joint_exqdesn_exact_structured_inference.R",
  "joint_exqdesn_inference_dispatch.R",
  "joint_exqdesn_phase164_165_readiness.R"
)) source(app_path("application/R", file))

args <- commandArgs(trailingOnly = TRUE)
force_shards <- any(args == "--force-shards")
phase164 <- app_joint_exqdesn_phase164_prepare(force_shards = force_shards)
print(phase164$assessment, row.names = FALSE)
if (phase164$assessment$gate_status[[1L]] != "pass") stop("Phase164 did not pass.", call. = FALSE)
phase165 <- app_joint_exqdesn_phase165_run(phase164$dirs)
print(phase165$assessment, row.names = FALSE)
if (phase165$assessment$gate_status[[1L]] != "pass") stop("Phase165 did not pass.", call. = FALSE)
