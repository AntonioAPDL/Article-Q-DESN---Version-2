#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_shared_backbone_family_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_shared_family_default_root(), scenario_id = ""))
scenario_id <- args[["scenario-id"]] %||% args$scenario_id
if (!nzchar(scenario_id)) stop("--scenario-id is required.", call. = FALSE)
result <- app_joint_shared_family_prepare_quantile(args$root, scenario_id)
print(result$readiness)
cat(sprintf("Prepared quantile continuation for %s\n", scenario_id))
