#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."),
  winslash = "/", mustWork = TRUE
)

status <- system2(
  "Rscript",
  c(file.path(repo_root, "scripts/check_joint_qdesn_phase181_interval_figures.R"),
    repo_root),
  stdout = TRUE, stderr = TRUE
)
exit_status <- attr(status, "status")
if (!is.null(exit_status) && exit_status != 0L) {
  cat(status, sep = "\n")
  stop("Joint Phase181 interval-figure checker failed.", call. = FALSE)
}
if (!any(grepl("JOINT_QDESN_PHASE181_INTERVAL_FIGURES_CHECK=PASS", status,
               fixed = TRUE))) {
  cat(status, sep = "\n")
  stop("Joint Phase181 interval-figure checker did not report PASS.",
       call. = FALSE)
}

cat(status, sep = "\n")
