#!/usr/bin/env Rscript

source(file.path(dirname(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L])), "_joint_qdesn_phase180_balanced_score_bootstrap.R"))

cache_root <- app_joint_qdesn_phase180_arg(
  "--cache-root", app_joint_exqdesn_phase164_cache_root()
)
dirs <- app_joint_qdesn_phase180_dirs(cache_root)
recovery_dir <- app_joint_qdesn_phase180_arg(
  "--recovery-dir", dirs$recovery_freeze
)
orchestration_dir <- app_joint_qdesn_phase180_arg(
  "--orchestration-dir", dirs$recovery_orchestration
)
health <- app_joint_qdesn_phase180_recovery_health(
  recovery_dir, orchestration_dir
)
print(health$summary, row.names = FALSE)
if ("--write" %in% commandArgs(trailingOnly = TRUE)) {
  app_ensure_dir(orchestration_dir)
  app_joint_qvp_write_csv(
    health$summary, file.path(orchestration_dir, "health_summary.csv")
  )
  app_joint_qvp_write_csv(
    health$by_case, file.path(orchestration_dir, "health_by_case.csv")
  )
}
if (health$summary$failed[[1L]] > 0L) quit(status = 2L)
