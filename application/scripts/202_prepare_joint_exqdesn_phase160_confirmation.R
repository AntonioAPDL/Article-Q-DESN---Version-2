#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R")); app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R", "joint_exqdesn_trace_tools.R", "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_exqdesn_phase158_fan_audit.R", "joint_exqdesn_phase159_split_rhs_screening.R",
  "joint_exqdesn_phase160_independent_confirmation.R"
)) source(app_path("application/R", file))
args <- app_parse_args(list(
  freeze_dir = app_joint_exqdesn_phase160_default_freeze_dir(),
  output_dir = app_joint_exqdesn_phase160_default_output_dir(),
  phase159_dir = app_joint_exqdesn_phase160_default_phase159_dir(),
  phase159_freeze_dir = app_joint_exqdesn_phase160_default_phase159_freeze_dir(),
  phase157_dir = app_joint_exqdesn_phase160_default_phase157_dir(),
  n_chains = 8L, n_iter = 12000L, burn = 3000L, thin = 3L, workers = 16L,
  seed_base = 202608050L, chain_seed_stride = 1009L
))
value <- function(name) args[[gsub("_", "-", name, fixed = TRUE)]] %||% args[[name]]
result <- app_joint_exqdesn_phase160_prepare(
  freeze_dir = as.character(value("freeze_dir")), output_dir = as.character(value("output_dir")),
  phase159_dir = as.character(value("phase159_dir")), phase159_freeze_dir = as.character(value("phase159_freeze_dir")),
  phase157_dir = as.character(value("phase157_dir")), n_chains = as.integer(value("n_chains")),
  n_iter = as.integer(value("n_iter")), burn = as.integer(value("burn")), thin = as.integer(value("thin")),
  workers = as.integer(value("workers")), seed_base = as.integer(value("seed_base")),
  chain_seed_stride = as.integer(value("chain_seed_stride"))
)
cat(sprintf("Phase160 freeze ready: %s\n", result$freeze_dir)); print(result$readiness, row.names = FALSE)
