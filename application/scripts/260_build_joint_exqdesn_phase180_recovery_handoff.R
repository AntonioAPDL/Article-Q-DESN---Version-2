#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))

force <- "--force" %in% commandArgs(trailingOnly = TRUE)
packet <- app_joint_exqdesn_phase180_build_packet(force = force)
stage <- app_joint_exqdesn_phase180_stage_article_assets(force = force)
cat(sprintf("Phase180 packet: %s\nPhase180 staging: %s\n", packet$out_dir, stage$out_dir))
print(packet$final, row.names = FALSE)
