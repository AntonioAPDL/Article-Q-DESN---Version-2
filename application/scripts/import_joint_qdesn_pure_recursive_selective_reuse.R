#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L]))), "_joint_qdesn_pure_recursive_bootstrap.R"))

args <- app_parse_args(list(
  stage = NA_character_, target_root = NA_character_, source_root = NA_character_,
  target_campaign_root = NA_character_, source_campaign_root = NA_character_
))
stage <- args$stage
target_root <- args[["target-root"]] %||% args$target_root
source_root <- args[["source-root"]] %||% args$source_root
target_campaign_root <- args[["target-campaign-root"]] %||%
  args$target_campaign_root
source_campaign_root <- args[["source-campaign-root"]] %||%
  args$source_campaign_root

result <- switch(stage,
  quantile = app_joint_pure_import_quantile_reuse(target_root, source_root),
  vb = app_joint_pure_import_vb_reuse(
    target_root, source_root, target_campaign_root, source_campaign_root
  ),
  mcmc = app_joint_pure_import_mcmc_reuse(
    target_root, source_root, target_campaign_root, source_campaign_root
  ),
  stop("--stage must be one of quantile, vb, or mcmc.", call. = FALSE)
)
print(result)
