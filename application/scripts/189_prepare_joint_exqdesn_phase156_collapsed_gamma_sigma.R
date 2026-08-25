#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R",
  "joint_qdesn_simulation_validation.R", "joint_qdesn_vb_spec_screening.R",
  "joint_qdesn_calibration_screening.R", "joint_qdesn_mcmc_readiness.R",
  "joint_exqdesn_trace_tools.R", "joint_exqdesn_phase156_collapsed_gamma_sigma.R"
)) source(app_path("application/R", file))

args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase156_collapsed_gamma_sigma_freeze_20260731",
  phase150_freeze_dir = "application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_freeze_20260727",
  phase150_mcmc_dir = "application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727",
  phase154_dir = "application/cache/joint_qdesn_phase154_balanced_mcmc_final_20260730",
  fixture_dir = "application/cache/joint_qdesn_simulation_dgp_fixtures_20260706",
  phase157_dir = "application/cache/joint_qdesn_phase157_collapsed_gamma_sigma_mcmc_20260731",
  n_chains = "8", n_iter = "12000", burn = "3000", thin = "3",
  seed_offset = "15700", chain_seed_stride = "101",
  gamma_slice_width = "4", gamma_slice_max_steps = "250",
  workers_per_wave = "24", n_vb_cores = "8"
))

value <- function(name) args[[gsub("_", "-", name, fixed = TRUE)]] %||% args[[name]]
path <- function(name, must = FALSE) {
  x <- as.character(value(name))[[1L]]
  normalizePath(if (grepl("^/", x)) x else app_path(x), mustWork = must)
}
num <- function(name) as.numeric(as.character(value(name))[[1L]])
int <- function(name) as.integer(num(name))

result <- app_joint_exqdesn_run_phase156_freeze(
  out_dir = path("output_dir"), phase150_freeze_dir = path("phase150_freeze_dir", TRUE),
  phase150_mcmc_dir = path("phase150_mcmc_dir"), phase154_dir = path("phase154_dir"),
  fixture_dir = path("fixture_dir", TRUE), phase157_dir = path("phase157_dir"),
  n_chains = int("n_chains"), n_iter = int("n_iter"), burn = int("burn"), thin = int("thin"),
  seed_offset = int("seed_offset"), chain_seed_stride = int("chain_seed_stride"),
  gamma_slice_width = num("gamma_slice_width"), gamma_slice_max_steps = int("gamma_slice_max_steps"),
  workers_per_wave = int("workers_per_wave"), n_vb_cores = int("n_vb_cores")
)
cat(sprintf("Phase156 freeze: %s\n", result$out_dir))
cat(sprintf("Cases/workers: %d/%d\n", nrow(result$controls), nrow(result$chain_plan)))
cat(sprintf("Kernel audit: %s\n", result$kernel_audit$status[[1L]]))
cat(sprintf("VB converged: %d/%d\n", sum(result$convergence$converged), nrow(result$convergence)))
