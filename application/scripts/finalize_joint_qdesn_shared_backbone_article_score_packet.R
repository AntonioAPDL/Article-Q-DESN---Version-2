#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_shared_backbone_article_confirmation_bootstrap.R"))

args <- app_parse_args(list(
  root = app_joint_article_default_root(),
  contract_path = app_joint_article_score_contract_path(),
  score_cores = 4L,
  force = FALSE
))
result <- app_joint_article_score_finalize(
  root = args$root,
  contract_path = args[["contract-path"]] %||% args$contract_path,
  score_cores = as.integer(args$score_cores),
  force = isTRUE(args[["force"]])
)
print(result$health)
cat(sprintf("Jerez score packet: %s\n", result$out_dir))
