#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R", "joint_exqdesn_trace_tools.R", "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_exqdesn_phase158_fan_audit.R", "joint_exqdesn_phase159_split_rhs_screening.R"
)) source(app_path("application/R", file))
args <- app_parse_args(list(
  freeze_dir = "application/cache/joint_qdesn_phase159_split_rhs_calibration_freeze_20260804",
  output_dir = "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase159_split_rhs_calibration_mcmc_20260804",
  phase158_dir = "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase158_quantile_fan_decomposition_20260804",
  phase156b_dir = "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase156b_collapsed_gamma_sigma_recovery_freeze_20260802",
  n_chains = 4L, n_iter = 6000L, burn = 1500L, thin = 3L, workers = 24L, n_vb_cores = 12L
))
value <- function(name) args[[gsub("_", "-", name, fixed = TRUE)]] %||% args[[name]]
resolve <- function(name, must_work = FALSE) {
  x <- as.character(value(name))[[1L]]
  normalizePath(if (grepl("^/", x)) x else app_path(x), mustWork = must_work)
}
result <- app_joint_exqdesn_phase159_prepare(
  freeze_dir = resolve("freeze_dir"), output_dir = resolve("output_dir"),
  phase158_dir = resolve("phase158_dir", TRUE), phase156b_dir = resolve("phase156b_dir", TRUE),
  n_chains = as.integer(value("n_chains")), n_iter = as.integer(value("n_iter")),
  burn = as.integer(value("burn")), thin = as.integer(value("thin")),
  workers = as.integer(value("workers")), n_vb_cores = as.integer(value("n_vb_cores"))
)
cat(sprintf("Phase159 freeze ready: %s\n", result$freeze_dir))
print(result$readiness, row.names = FALSE)
