#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(
  campaign_root = app_joint_pure_default_root(),
  output_dir = app_joint_pure_confirmation_root(),
  execution_branch = "work/joint-qdesn-pure-desn-recursive-selection-20260925",
  run_tag = NA_character_,
  source_worktree = normalizePath(getwd(), mustWork = TRUE),
  contract_version = "joint_qdesn_pure_recursive_article_confirmation_v2"
))
output_dir <- args[["output-dir"]] %||% args$output_dir
run_tag <- args[["run-tag"]] %||% args$run_tag
if (length(run_tag) != 1L || is.na(run_tag) || !nzchar(run_tag)) {
  run_tag <- basename(output_dir)
}
result <- app_joint_pure_prepare_confirmation(
  args[["campaign-root"]] %||% args$campaign_root,
  output_dir,
  execution_branch = args[["execution-branch"]] %||% args$execution_branch,
  run_tag = run_tag,
  source_worktree = args[["source-worktree"]] %||% args$source_worktree,
  contract_version = args[["contract-version"]] %||% args$contract_version
)
print(result$readiness)
