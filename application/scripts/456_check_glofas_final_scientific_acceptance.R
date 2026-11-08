#!/usr/bin/env Rscript
arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(root, "application/R/glofas_final_scientific_acceptance.R"))
args <- commandArgs(TRUE)
value <- sub("^--root=", "", args[grepl("^--root=", args)])
if (length(value) != 1L || !nzchar(value)) stop("Provide --root=<acceptance-root>.", call. = FALSE)
gfsa_check(value)

