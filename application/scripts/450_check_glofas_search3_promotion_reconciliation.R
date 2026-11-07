#!/usr/bin/env Rscript
arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(file.path(root, "application/R/glofas_search3_article_projection.R"))
source(file.path(root, "application/R/glofas_search3_promotion_reconciliation.R"))
args <- app_parse_args(list(runtime_root = "", closeout_root = ""))
if (!nzchar(args$runtime_root)) stop("An explicit reconciliation runtime is required.", call. = FALSE)
gpr_check(args$runtime_root, if (nzchar(args$closeout_root)) args$closeout_root else NULL, root)
