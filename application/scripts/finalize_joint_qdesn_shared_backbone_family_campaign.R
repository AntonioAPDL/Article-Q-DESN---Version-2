#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_shared_backbone_family_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_shared_family_default_root()))
result <- app_joint_shared_family_finalize(args$root)
print(result$decision)
cat(sprintf("Finalized %d family-specific backbones and %d future MCMC cells.\n",
  nrow(result$selected), nrow(result$mcmc_plan)))
