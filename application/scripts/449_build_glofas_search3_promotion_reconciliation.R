#!/usr/bin/env Rscript
arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(file.path(root, "application/R/glofas_search3_final_closeout.R"))
source(file.path(root, "application/R/glofas_search3_article_projection.R"))
source(file.path(root, "application/R/glofas_search3_promotion_reconciliation.R"))
args <- app_parse_args(list(closeout_root = "", root_cause_root = "",
  driver_audit_root = "", output_root = ""))
if (any(!nzchar(unlist(args)))) stop("All four runtime roots are required.", call. = FALSE)
gpr_build(root, args$closeout_root, args$root_cause_root,
  args$driver_audit_root, args$output_root)
