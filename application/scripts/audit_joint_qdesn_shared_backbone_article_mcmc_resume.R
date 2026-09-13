#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
script_arg <- if (length(file_arg) && !is.na(file_arg)) {
  sub("^--file=", "", file_arg)
} else {
  NA_character_
}
script_dir <- if (!is.na(script_arg) && nzchar(script_arg) &&
    !identical(script_arg, "-")) {
  dirname(normalizePath(script_arg))
} else {
  file.path(normalizePath(getwd(), mustWork = TRUE), "application", "scripts")
}
source(file.path(script_dir,
  "_joint_qdesn_shared_backbone_article_confirmation_bootstrap.R"))

args <- app_parse_args(list(
  root = app_joint_article_default_root(),
  compatible_execution_commits = "",
  out_dir = ""
))
commits <- args[["compatible-execution-commits"]] %||%
  args$compatible_execution_commits
commits <- trimws(strsplit(as.character(commits), ",", fixed = TRUE)[[1L]])
out_dir <- args[["out-dir"]] %||% args$out_dir
result <- app_joint_article_mcmc_resume_compatibility_audit(
  root = args$root,
  compatible_execution_commits = commits,
  out_dir = out_dir
)

print(result$assessment)
print(result$inventory)
cat(sprintf("JOINT MCMC resume compatibility audit written to: %s\n",
  result$out_dir))
