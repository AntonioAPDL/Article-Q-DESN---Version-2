#!/usr/bin/env Rscript
arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(file.path(root, "application/R/glofas_part4_corrected_target_qualification.R"))
source(file.path(root, "application/R/glofas_part4_hybrid_authority_handoff.R"))
source(file.path(root, "application/R/glofas_final_scientific_acceptance.R"))
args <- app_parse_args(list(handoff_root = "", qualification_root = "", driver_root = "",
  root_cause_root = "", candidate_root = "", candidate_commit = "", output_root = ""))
required <- c("handoff_root", "qualification_root", "driver_root", "root_cause_root",
  "candidate_root", "candidate_commit", "output_root")
if (any(!nzchar(unlist(args[required]))))
  stop("All final-acceptance roots and candidate commit are required.", call. = FALSE)
gfsa_build(root, args$handoff_root, args$qualification_root, args$driver_root,
  args$root_cause_root, args$candidate_root, args$candidate_commit, args$output_root)

