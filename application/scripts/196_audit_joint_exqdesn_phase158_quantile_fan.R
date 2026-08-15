#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R",
  "joint_qdesn_simulation_validation.R", "joint_qdesn_mcmc_readiness.R",
  "joint_exqdesn_trace_tools.R", "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_exqdesn_phase158_fan_audit.R"
)) source(app_path("application/R", file))

args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase158_quantile_fan_decomposition_20260804",
  phase157_dir = "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802",
  freeze_dir = "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase156b_collapsed_gamma_sigma_recovery_freeze_20260802"
))
value <- function(name) args[[gsub("_", "-", name, fixed = TRUE)]] %||% args[[name]]
resolve <- function(name, must_work) {
  x <- as.character(value(name))[[1L]]
  normalizePath(if (grepl("^/", x)) x else app_path(x), mustWork = must_work)
}
result <- app_joint_exqdesn_run_phase158(
  out_dir = resolve("output_dir", FALSE),
  phase157_dir = resolve("phase157_dir", TRUE),
  freeze_dir = resolve("freeze_dir", TRUE)
)
cat(sprintf("Phase158 complete: %s\n", result$out_dir))
print(result$assessment, row.names = FALSE)
print(result$decisions[, c(
  "scenario_id", "outer_width_ratio", "fitted_to_true_gap_ratio",
  "decision", "recommended_innovation_tau0_multipliers"
)], row.names = FALSE)
