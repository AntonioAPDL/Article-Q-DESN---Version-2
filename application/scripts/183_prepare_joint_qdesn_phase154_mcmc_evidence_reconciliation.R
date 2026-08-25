#!/usr/bin/env Rscript

script_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
repo_root <- normalizePath(file.path(dirname(normalizePath(script_arg)), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R",
  "joint_qdesn_phase153_balanced_independent_replication.R",
  "joint_qdesn_phase154_mcmc_evidence_reconciliation.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  output_dir = app_joint_qdesn_phase154_default_readiness_dir(),
  freeze_dir = app_joint_qdesn_phase154_default_freeze_dir(),
  phase122_dir = app_joint_qdesn_phase154_default_phase122_dir(),
  phase124c_dir = app_joint_qdesn_phase154_default_phase124c_dir(),
  phase125_dir = app_joint_qdesn_phase154_default_phase125_dir(),
  phase150_dir = app_joint_qdesn_phase154_default_phase150_dir(),
  phase153_readiness_dir =
    app_joint_qdesn_phase154_default_phase153_readiness_dir(),
  phase153_results_dir =
    app_joint_qdesn_phase154_default_phase153_results_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  verify_source_manifests = "true"
))
value <- function(hyphen, underscore) args[[hyphen]] %||% args[[underscore]]

result <- app_joint_qdesn_phase154_prepare(
  out_dir = value("output-dir", "output_dir"),
  freeze_dir = value("freeze-dir", "freeze_dir"),
  phase122_dir = value("phase122-dir", "phase122_dir"),
  phase124c_dir = value("phase124c-dir", "phase124c_dir"),
  phase125_dir = value("phase125-dir", "phase125_dir"),
  phase150_dir = value("phase150-dir", "phase150_dir"),
  phase153_readiness_dir = value(
    "phase153-readiness-dir", "phase153_readiness_dir"
  ),
  phase153_results_dir = value(
    "phase153-results-dir", "phase153_results_dir"
  ),
  fixture_dir = value("fixture-dir", "fixture_dir"),
  verify_source_manifests = app_as_bool(value(
    "verify-source-manifests", "verify_source_manifests"
  ))
)
cat(sprintf("Phase154 reconciliation written to %s\n", result$out_dir))
cat(sprintf("Phase154 rerun freeze written to %s\n", result$freeze_dir))
print(result$readiness)
print(table(result$coverage$action))
if (result$readiness$gate_status[[1L]] == "fail") quit(status = 1L)
