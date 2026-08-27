#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))

result <- app_joint_exqdesn_phase178_prepare(
  materialize_fixtures = TRUE,
  force = "--force" %in% commandArgs(trailingOnly = TRUE)
)
cat(sprintf("Phase178 freeze: %s\n", result$out_dir))
print(result$readiness, row.names = FALSE)
