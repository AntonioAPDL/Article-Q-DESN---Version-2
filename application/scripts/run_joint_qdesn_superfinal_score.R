#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_stronger_window_bootstrap.R"))
args <- commandArgs(TRUE)
source_root <- sub("^--source-root=", "", args[grepl("^--source-root=", args)][1L])
root <- sub("^--root=", "", args[grepl("^--root=", args)][1L])
id <- as.integer(sub("^--target-id=", "", args[grepl("^--target-id=", args)][1L]))
tryCatch(
  app_joint_superfinal_run_score(source_root, root, id),
  error = function(e) {
    out <- app_joint_superfinal_score_dir(root, id)
    app_ensure_dir(out)
    writeLines(conditionMessage(e), file.path(out, "failure.txt"))
    writeLines("failed", file.path(out, "FAILED"))
    stop(e)
  }
)
