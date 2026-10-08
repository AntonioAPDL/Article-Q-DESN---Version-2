#!/usr/bin/env Rscript
arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", arg[[1]])), "..", ".."), mustWork = TRUE)
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(file.path(root, "application/R/glofas_search3_article_projection.R"))
args <- app_parse_args(list(runtime_root = "", output_root = root))
if (!nzchar(args$runtime_root)) stop("An explicit --runtime_root frozen authority is required.", call. = FALSE)
g3_build(root, args$runtime_root, args$output_root)
