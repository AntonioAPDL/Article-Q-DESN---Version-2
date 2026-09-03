#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(
  root, "application/scripts/_joint_qdesn_phase181_score_stability_bootstrap.R"
))

cache_root <- app_joint_qdesn_phase181_arg(
  "--cache-root", app_joint_exqdesn_phase164_cache_root()
)
dirs <- app_joint_qdesn_phase181_dirs(cache_root)
health <- app_joint_qdesn_phase181_health(dirs$freeze, dirs$orchestration)
print(health$summary, row.names = FALSE)
if (app_joint_qdesn_phase181_flag("--write")) {
  app_ensure_dir(dirs$orchestration)
  app_joint_qvp_write_csv(
    health$summary, file.path(dirs$orchestration, "health_summary.csv")
  )
  app_joint_qvp_write_csv(
    health$by_case, file.path(dirs$orchestration, "health_by_case.csv")
  )
}
if (health$summary$failed[[1L]] > 0L) quit(status = 2L)
