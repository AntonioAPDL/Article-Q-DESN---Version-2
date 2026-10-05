#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L]))), "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(
  source_root = app_joint_pure_confirmation_root(),
  score_root = app_joint_pure_score_root()
))
result <- app_joint_pure_prepare_score_packet(
  args[["source-root"]] %||% args$source_root,
  args[["score-root"]] %||% args$score_root
)
cat(sprintf(
  "Prepared %d posterior-score cells and %d primary oracle shards at %s\n",
  nrow(result$cells), sum(app_as_bool_vec(result$oracle$is_primary)), result$root
))
