#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/scripts/_joint_qdesn_phase181_diagnostic_atlas_bootstrap.R"))

output_dir <- app_joint_qdesn_atlas_arg(
  "--output-dir",
  app_path("local_trackers/joint_qdesn_phase181_diagnostic_atlas_20260831")
)
result <- app_joint_qdesn_atlas_check(output_dir)
print(result$gates, row.names = FALSE)
cat(sprintf("status=%s pdf=%s sha256=%s\n", result$status,
            result$combined_pdf, result$combined_pdf_sha256))
