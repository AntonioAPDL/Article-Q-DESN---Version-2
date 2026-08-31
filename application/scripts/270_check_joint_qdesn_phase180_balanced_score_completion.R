#!/usr/bin/env Rscript

source(file.path(dirname(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L])), "_joint_qdesn_phase180_balanced_score_bootstrap.R"))

cache_root <- app_joint_qdesn_phase180_arg(
  "--cache-root", app_joint_exqdesn_phase164_cache_root()
)
dirs <- app_joint_qdesn_phase180_dirs(cache_root)
health <- app_joint_qdesn_phase180_health(
  app_joint_qdesn_phase180_arg("--freeze-dir", dirs$freeze),
  app_joint_qdesn_phase180_arg("--orchestration-dir", dirs$orchestration)
)
print(health$summary, row.names = FALSE)
if ("--write" %in% commandArgs(trailingOnly = TRUE)) {
  app_ensure_dir(dirs$orchestration)
  app_joint_qvp_write_csv(
    health$summary, file.path(dirs$orchestration, "health_summary.csv")
  )
  app_joint_qvp_write_csv(
    health$by_case, file.path(dirs$orchestration, "health_by_case.csv")
  )
}
if (health$summary$failed[[1L]] > 0L) quit(status = 2L)
