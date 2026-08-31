#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/scripts/_joint_qdesn_phase181_diagnostic_atlas_bootstrap.R"))

output_dir <- app_joint_qdesn_atlas_arg(
  "--output-dir",
  app_path("local_trackers/joint_qdesn_phase181_diagnostic_atlas_20260831")
)
page <- as.integer(app_joint_qdesn_atlas_arg("--page"))
if (!is.finite(page)) stop("Usage: --page <integer>", call. = FALSE)
result <- app_joint_qdesn_atlas_render_page(output_dir, page)
cat(sprintf("page=%d pdf=%s\n", page, result$pdf_path[[1L]]))
