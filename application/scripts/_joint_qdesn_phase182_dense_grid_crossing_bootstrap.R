file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(
  root, "application/scripts/_joint_qdesn_phase181_score_stability_bootstrap.R"
))
source(app_path("application/R/joint_qdesn_phase182_dense_grid_crossing.R"))

app_joint_qdesn_phase182_arg <- function(name, default = NULL) {
  args <- commandArgs(trailingOnly = TRUE)
  index <- match(name, args)
  if (is.na(index) || index == length(args)) default else args[[index + 1L]]
}

app_joint_qdesn_phase182_flag <- function(name) {
  name %in% commandArgs(trailingOnly = TRUE)
}
