#!/usr/bin/env Rscript
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R")); app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R")); source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_exqdesn_phase162_scenario_classification.R"))
dirs <- app_joint_exqdesn_phase162_default_dirs()
if (all(dir.exists(unlist(dirs[c("phase150", "phase154_al", "phase160", "phase161")])))) {
  dirs$output <- tempfile("phase162_")
  result <- app_joint_exqdesn_phase162_run(dirs)
  stopifnot(result$assessment$gate_status == "pass", nrow(result$classification) == 8L,
    nrow(result$experiments) >= 1L, !result$assessment$new_sampling_performed,
    file.exists(file.path(dirs$output, "artifact_manifest.csv")))
  manifest <- read.csv(file.path(dirs$output, "artifact_manifest.csv"), stringsAsFactors = FALSE)
  stopifnot(nrow(manifest) == 8L, all(file.exists(file.path(dirs$output, manifest$relative_path))))
}
cat("Phase162 scenario-classification tests passed.\n")
