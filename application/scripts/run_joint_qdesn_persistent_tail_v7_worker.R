#!/usr/bin/env Rscript

source("application/scripts/_joint_qdesn_persistent_tail_v7_bootstrap.R")
args <- commandArgs(TRUE)
if (length(args) != 3L) stop("Usage: worker ROOT STAGE WORKER_ID", call. = FALSE)
root <- args[[1L]]; stage <- args[[2L]]; id <- as.integer(args[[3L]])
switch(stage, vb = app_joint_pht7_run_vb(root, id),
  mcmc = app_joint_pht7_run_mcmc(root, id),
  score = app_joint_pht7_run_score(root, id),
  stop("Unknown V7 worker stage.", call. = FALSE))
