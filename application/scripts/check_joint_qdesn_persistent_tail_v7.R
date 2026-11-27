#!/usr/bin/env Rscript

source("application/scripts/_joint_qdesn_persistent_tail_v7_bootstrap.R")
args <- commandArgs(TRUE)
print(app_joint_pht7_check(if (length(args)) args[[1L]] else app_joint_pht7_default_root()))
