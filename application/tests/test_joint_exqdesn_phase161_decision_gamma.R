#!/usr/bin/env Rscript
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R")); app_set_repo_root(repo_root)
for (file in c("input_contract.R", "synthesize_quantiles.R", "score_forecasts.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R",
  "joint_exqdesn_trace_tools.R", "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_exqdesn_phase158_fan_audit.R", "joint_exqdesn_phase161_decision_gamma_audit.R")) source(app_path("application/R", file))
source_dir <- app_joint_exqdesn_phase161_default_phase160_dir()
draws <- if (dir.exists(source_dir)) list.files(source_dir, "^posterior_draws\\.csv\\.gz$", recursive = TRUE) else character()
if (length(draws) == 16L) {
  out <- tempfile("phase161_"); result <- app_joint_exqdesn_phase161_run(source_dir, out)
  stopifnot(result$gate$gate_status == "pass", nrow(result$decision) == 2L,
    !any(result$decision$article_replacement), file.exists(file.path(out, "artifact_manifest.csv")))
  manifest <- read.csv(file.path(out, "artifact_manifest.csv"), stringsAsFactors = FALSE)
  stopifnot(nrow(manifest) >= 10L, all(file.exists(file.path(out, manifest$relative_path))))
} else {
  out <- app_joint_exqdesn_phase161_default_output_dir()
  stopifnot(file.exists(file.path(out, "decision_freeze.csv")),
    file.exists(file.path(out, "artifact_manifest.csv")),
    file.exists(file.path(out, "legacy_cleanup", "cleanup_inventory.csv")))
  decision <- read.csv(file.path(out, "decision_freeze.csv"), stringsAsFactors = FALSE)
  cleanup <- read.csv(file.path(out, "legacy_cleanup", "cleanup_inventory.csv"), stringsAsFactors = FALSE)
  stopifnot(nrow(decision) == 2L, !any(decision$article_replacement),
    nrow(cleanup) == 104L, all(cleanup$status == "deleted_verified"))
}
cat("Phase161 decision/gamma audit tests passed.\n")
