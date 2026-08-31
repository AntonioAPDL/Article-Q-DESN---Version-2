file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
setwd(root)
source(app_path("application/scripts/_joint_qdesn_phase180_balanced_score_bootstrap.R"))
source(app_path("application/R/joint_qdesn_phase181_score_stability_extension.R"))

app_joint_qdesn_phase181_arg <- function(name, default = NULL) {
  args <- commandArgs(trailingOnly = TRUE)
  index <- match(name, args)
  if (is.na(index) || index == length(args)) default else args[[index + 1L]]
}

app_joint_qdesn_phase181_flag <- function(name) {
  name %in% commandArgs(trailingOnly = TRUE)
}
