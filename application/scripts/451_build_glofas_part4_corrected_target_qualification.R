#!/usr/bin/env Rscript
arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(file.path(root, "application/R/glofas_part4_corrected_target_qualification.R"))
args <- app_parse_args(list(corrected_root = "", rejected_root = "", search3_root = "",
  root_cause_path = "", output_root = "", deep_fit_audit = "true"))
required <- c("corrected_root", "rejected_root", "search3_root", "root_cause_path", "output_root")
if (any(!nzchar(unlist(args[required])))) stop("All runtime roots and the output root are required.", call. = FALSE)
gptq_build(root, args$corrected_root, args$rejected_root, args$search3_root,
  args$root_cause_path, args$output_root,
  deep_fit_audit = tolower(args$deep_fit_audit) %in% c("true", "1", "yes"))
