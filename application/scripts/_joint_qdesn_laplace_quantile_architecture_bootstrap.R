source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])),
  "_joint_qdesn_fixed_backbone_prior_bootstrap.R"))
source(app_path("application/R/joint_qdesn_laplace_quantile_architecture.R"))
