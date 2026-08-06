#!/usr/bin/env Rscript
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R")); app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R")); source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_exqdesn_phase162_scenario_classification.R"))
result <- app_joint_exqdesn_phase162_run()
print(result$assessment, row.names = FALSE)
print(result$classification[, c("scenario_id", "performance_class", "limitation_class", "next_priority")], row.names = FALSE)
