#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))

dirs <- app_joint_exqdesn_phase176_dirs()
if (!file.exists(file.path(dirs$phase179_article_freeze, "artifact_manifest.csv"))) {
  result <- app_joint_exqdesn_phase179_finalize_article_confirmation()
  print(result$assessment, row.names = FALSE)
} else {
  health <- app_joint_exqdesn_phase178_m0_health(
    dirs$phase179_article_freeze, dirs$phase179_article_orchestration,
    "phase179_frozen_article_fixture_exact_M0_freeze"
  )
  print(health$summary, row.names = FALSE); print(health$by_case, row.names = FALSE)
  if (health$summary$failed[[1L]] == 0L && health$summary$remaining[[1L]] == 0L) {
    result <- app_joint_exqdesn_phase179_finalize_article_confirmation()
    print(result$assessment, row.names = FALSE)
  }
}
