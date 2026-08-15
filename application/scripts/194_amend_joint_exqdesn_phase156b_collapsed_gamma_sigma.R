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
  parent_freeze_dir = "application/cache/joint_qdesn_phase156_collapsed_gamma_sigma_freeze_20260731",
  failed_phase157_dir = "application/cache/joint_qdesn_phase157_collapsed_gamma_sigma_mcmc_20260731",
  failed_orchestration_dir = "application/cache/joint_qdesn_phase157_collapsed_gamma_sigma_mcmc_20260731_orchestration",
  output_dir = "application/cache/joint_qdesn_phase156b_collapsed_gamma_sigma_recovery_freeze_20260802",
  phase157b_dir = "application/cache/joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802",
  require_clean_source = "true"
))

value <- function(name) args[[gsub("_", "-", name, fixed = TRUE)]] %||% args[[name]]
path <- function(name, must = FALSE) {
  x <- as.character(value(name))[[1L]]
  normalizePath(if (grepl("^/", x)) x else app_path(x), mustWork = must)
}
flag <- function(name) tolower(as.character(value(name))[[1L]]) %in% c("true", "1", "yes")

result <- app_joint_exqdesn_run_phase156b_amendment(
  parent_freeze_dir = path("parent_freeze_dir", TRUE),
  failed_phase157_dir = path("failed_phase157_dir", TRUE),
  failed_orchestration_dir = path("failed_orchestration_dir", TRUE),
  out_dir = path("output_dir"),
  phase157b_dir = path("phase157b_dir"),
  require_clean_source = flag("require_clean_source")
)

cat(sprintf("Phase156b recovery freeze: %s\n", result$out_dir))
cat(sprintf("Workers/scenarios: %d/%d\n", nrow(result$chain_plan), length(unique(result$chain_plan$scenario_id))))
cat(sprintf("Parent identity gates: %d/%d pass\n", sum(result$identity_audit$status == "pass"), nrow(result$identity_audit)))
cat(sprintf("Failed Phase157 audit: %s\n", result$failed_run_audit$status[[1L]]))
cat(sprintf("Manifest entries verified: %d/%d\n", sum(result$manifest_verification$status == "pass"), nrow(result$manifest_verification)))
