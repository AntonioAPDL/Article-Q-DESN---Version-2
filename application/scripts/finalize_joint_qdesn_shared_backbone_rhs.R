#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))), "_joint_qdesn_shared_backbone_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_shared_default_root()))
result <- app_joint_shared_finalize_rhs(args$root)
cat(sprintf(
  "Selected %s at Gaussian RHS tau0=%s (observational calibration aCRPS %.8f).\n",
  result$selected$candidate_id[[1L]],
  format(result$selected$rhs_tau0[[1L]], scientific = TRUE),
  result$selected$calibration_acrps_mean[[1L]]
))
