#!/usr/bin/env Rscript

source("application/scripts/_joint_qdesn_persistent_tail_v7_bootstrap.R")
args <- commandArgs(TRUE)
if (length(args) != 5L) stop("Usage: prepare V6_ROOT AUTHORITY_ROOT FIXTURE ORACLE OUTPUT_ROOT", call. = FALSE)
print(app_joint_pht7_prepare(args[[1L]], args[[2L]], args[[3L]], args[[4L]], args[[5L]]))
