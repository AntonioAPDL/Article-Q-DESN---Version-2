#!/usr/bin/env Rscript
arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", arg[[1]])), "..", ".."), mustWork = TRUE)
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(file.path(root, "application/R/glofas_search3_article_projection.R"))
args <- app_parse_args(list(article_root = root, runtime_root = ""))
g3_check(args$article_root, if (nzchar(args$runtime_root)) args$runtime_root else NULL)
