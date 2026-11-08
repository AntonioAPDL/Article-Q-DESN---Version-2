#!/usr/bin/env Rscript
arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(file.path(root, "application/R/glofas_part4_corrected_target_qualification.R"))
source(file.path(root, "application/R/glofas_part4_hybrid_authority_handoff.R"))
args <- app_parse_args(list(corrected_root = "", qualification_root = "", output_root = "",
  base_ref = "origin/main", tag = "glofas_hybrid_part123_search3_part4_october_20261107"))
required <- c("corrected_root", "qualification_root", "output_root")
if (any(!nzchar(unlist(args[required]))) ) stop("Corrected, qualification and output roots are required.", call. = FALSE)
gpah_build(root, args$corrected_root, args$qualification_root, args$output_root,
  base_ref = args$base_ref, tag = args$tag)
