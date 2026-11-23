#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_stronger_window_bootstrap.R"))
args <- commandArgs(TRUE)
root <- sub("^--root=", "", args[grepl("^--root=", args)][1L])
id <- as.integer(sub("^--score-worker-id=", "", args[grepl("^--score-worker-id=", args)][1L]))
tryCatch(app_joint_alkernel_run_score(root, id), error = function(e) {
  out <- app_joint_swscore_cell_dir(root, id); app_ensure_dir(out)
  app_write_csv(data.frame(error_message = conditionMessage(e), stringsAsFactors = FALSE),
    file.path(out, "failure.csv")); writeLines("failed", file.path(out, "FAILED"))
  stop(conditionMessage(e), call. = FALSE)
})
