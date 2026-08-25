#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))

cache_root <- app_joint_exqdesn_phase176_180_arg(
  "--cache-root", app_joint_exqdesn_phase164_cache_root()
)
health <- app_joint_qdesn_phase179_health(cache_root)
print(health$summary, row.names = FALSE)
print(health$by_case, row.names = FALSE)
if (health$summary$failed[[1L]] == 0L && health$summary$remaining[[1L]] == 0L) {
  result <- app_joint_qdesn_phase179_finalize_confirmation(
    cache_root = cache_root,
    score_cores = as.integer(app_joint_exqdesn_phase176_180_arg("--score-cores", "12")),
    force = "--force-finalize" %in% commandArgs(trailingOnly = TRUE)
  )
  print(result$assessment, row.names = FALSE)
}
