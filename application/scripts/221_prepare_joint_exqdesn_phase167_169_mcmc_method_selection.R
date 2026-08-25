#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)

for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R", "joint_exqdesn_trace_tools.R",
  "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_qdesn_phase153_balanced_independent_replication.R",
  "joint_exqdesn_exact_structured_inference.R",
  "joint_exqdesn_inference_dispatch.R",
  "joint_exqdesn_phase164_165_readiness.R",
  "joint_exqdesn_phase166_168_structured_vb.R",
  "joint_exqdesn_phase167_169_mcmc_method_selection.R"
)) source(app_path("application/R", file))

arg_value <- function(name, default = NULL) {
  args <- commandArgs(trailingOnly = TRUE)
  index <- match(name, args)
  if (is.na(index) || index == length(args)) return(default)
  args[[index + 1L]]
}

result <- app_joint_exqdesn_phase169_prepare(
  n_chains = as.integer(arg_value("--n-chains", "8")),
  n_iter = as.integer(arg_value("--n-iter", "12000")),
  burn = as.integer(arg_value("--burn", "3000")),
  thin = as.integer(arg_value("--thin", "3")),
  seed_base = as.integer(arg_value("--seed-base", "202608070")),
  chain_seed_stride = as.integer(arg_value("--chain-seed-stride", "1009")),
  workers_per_wave = as.integer(arg_value("--workers-per-wave", "32")),
  n_vb_cores = as.integer(arg_value("--vb-cores", "10"))
)
print(result$phase167$assessment, row.names = FALSE)
cat("\nPhase169 readiness:\n")
print(result$readiness, row.names = FALSE)
