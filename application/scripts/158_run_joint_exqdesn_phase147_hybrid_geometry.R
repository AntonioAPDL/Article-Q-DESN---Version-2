#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg))), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R",
  "joint_qdesn_simulation_validation.R", "joint_qdesn_vb_spec_screening.R",
  "joint_qdesn_calibration_screening.R", "joint_qdesn_mcmc_readiness.R",
  "joint_exqdesn_trace_tools.R", "joint_exqdesn_phase136_gamma_kernel_packet.R",
  "joint_exqdesn_phase145_gamma_sampler_root_cause.R",
  "joint_exqdesn_phase147_hybrid_geometry.R"
)) source(app_path("application/R", path))
args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase147_hybrid_geometry_student_t_20260726",
  n_chains = "8", mcmc_n_iter = "15000", mcmc_burn = "3000",
  mcmc_thin = "3", n_cores = "24", vb_n_cores = "6", dry_run = "false"
))
value <- function(name) args[[gsub("_", "-", name, fixed = TRUE)]] %||% args[[name]]
int <- function(name) as.integer(as.numeric(value(name)))
result <- app_joint_exqdesn_run_phase147_hybrid_geometry(
  out_dir = value("output_dir"), n_chains = int("n_chains"),
  mcmc_n_iter = int("mcmc_n_iter"), mcmc_burn = int("mcmc_burn"),
  mcmc_thin = int("mcmc_thin"), n_cores = int("n_cores"),
  vb_n_cores = int("vb_n_cores"),
  dry_run = tolower(as.character(value("dry_run"))) %in% c("true", "1", "yes")
)
cat(sprintf("Phase147 artifacts: %s\n", result$out_dir))
cat(sprintf("Gate: %s\n", result$decision$gate_status[[1L]]))
cat(sprintf("Recommendation: %s\n", result$decision$recommendation[[1L]]))
