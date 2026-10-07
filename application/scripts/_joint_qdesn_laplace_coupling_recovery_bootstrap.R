file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
script_arg <- if (length(file_arg) && !is.na(file_arg)) sub("^--file=", "", file_arg) else NA_character_
root <- if (!is.na(script_arg)) normalizePath(file.path(dirname(normalizePath(script_arg)), "..", "..")) else getwd()
source(file.path(root, "application/scripts/_joint_qdesn_laplace_coupling_bootstrap.R"))
source(app_path("application/R/joint_qdesn_laplace_coupling_recovery.R"))
