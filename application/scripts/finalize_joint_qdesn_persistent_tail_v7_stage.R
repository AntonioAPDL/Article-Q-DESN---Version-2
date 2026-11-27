#!/usr/bin/env Rscript

source("application/scripts/_joint_qdesn_persistent_tail_v7_bootstrap.R")
args <- commandArgs(TRUE)
if (length(args) != 2L) stop("Usage: finalizer ROOT STAGE", call. = FALSE)
result <- switch(args[[2L]], vb = app_joint_pht7_finalize_vb(args[[1L]]),
  mcmc = app_joint_pht7_finalize_mcmc(args[[1L]]),
  score = app_joint_pht7_finalize_score(args[[1L]]),
  inventory = app_joint_pht7_transfer_inventory(args[[1L]]),
  stop("Unknown V7 finalization stage.", call. = FALSE))
print(result)
